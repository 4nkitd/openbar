import AppKit
import Darwin

enum OpenCodeSSE {
    static func frames(from chunk: String, remainder: inout String) -> [Data] {
        remainder += chunk
        var frames: [Data] = []
        while let range = remainder.range(of: "\n\n") {
            let block = String(remainder[..<range.lowerBound])
            remainder.removeSubrange(..<range.upperBound)
            var payload = ""
            for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
                guard line.hasPrefix("data:") else { continue }
                let value = line.dropFirst(5)
                if !payload.isEmpty { payload += "\n" }
                payload += value.first == " " ? String(value.dropFirst()) : String(value)
            }
            if let data = payload.data(using: .utf8), !payload.isEmpty { frames.append(data) }
        }
        return frames
    }
}

enum OpenCodeEvent {
    static func isConsumption(_ type: String) -> Bool {
        type.hasPrefix("session.tool")
            || type.hasPrefix("session.reasoning")
            || type.hasPrefix("session.text")
            || type.hasPrefix("session.step")
    }

    static func activitySessionID(in object: [String: Any]) -> String? {
        guard let type = object["type"] as? String, isConsumption(type) else { return nil }
        let data = object["data"] as? [String: Any]
        if let id = data?["sessionID"] as? String, id.hasPrefix("ses") { return id }
        return nil
    }

    static func providerID(fromSession object: [String: Any]) -> String? {
        let root = (object["data"] as? [String: Any]) ?? object
        return (root["model"] as? [String: Any])?["providerID"] as? String
    }
}

struct OpenCodeServiceEndpoint: Equatable {
    let url: URL
    let password: String
    let pid: pid_t?

    static func parse(_ data: Data) -> OpenCodeServiceEndpoint? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["url"] as? String,
              let url = URL(string: raw),
              let host = url.host,
              ["127.0.0.1", "localhost", "::1"].contains(host),
              url.scheme == "http" || url.scheme == "https",
              let password = object["password"] as? String, !password.isEmpty else { return nil }
        let pidValue = object["pid"] as? Int
        return OpenCodeServiceEndpoint(url: url, password: password, pid: pidValue.map { pid_t($0) })
    }

    var isProcessAlive: Bool {
        guard let pid, pid > 1 else { return true }
        return kill(pid, 0) == 0 || errno != ESRCH
    }

    var eventURL: URL { url.appendingPathComponent("api/event") }

    func sessionURL(_ sessionID: String) -> URL {
        url.appendingPathComponent("api/session").appendingPathComponent(sessionID)
    }

    var authorization: String {
        let token = Data("opencode:\(password)".utf8).base64EncodedString()
        return "Basic \(token)"
    }
}

@MainActor
final class OpenCodeActivityMonitor: NSObject, URLSessionDataDelegate {
    static let grace: TimeInterval = 5
    var onChange: (() -> Void)?
    private(set) var active: Set<IntegrationID> = []
    private let files: [URL]
    private let configuration: URLSessionConfiguration
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var endpoint: OpenCodeServiceEndpoint?
    private var remainder = ""
    private var lastBeat: [IntegrationID: Date] = [:]
    private var providers: [String: IntegrationID] = [:]
    private var resolutions: [String: URLSessionDataTask] = [:]
    private var unsupportedUntil: [String: Date] = [:]
    private var generation = UUID()
    private var poll: Timer?
    private var expiry: Timer?
    private var reconnect: Timer?
    private var backoff: TimeInterval = 1
    private var wakeObserver: NSObjectProtocol?

    init(files: [URL] = OpenCodeActivityMonitor.serviceFiles(), configuration: URLSessionConfiguration = .ephemeral) {
        self.files = files
        self.configuration = configuration
        super.init()
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60 * 24
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
    }

    nonisolated static func serviceFiles() -> [URL] {
        var urls: [URL] = []
        if let xdg = ProcessInfo.processInfo.environment["XDG_STATE_HOME"], !xdg.isEmpty {
            urls.append(URL(fileURLWithPath: xdg).appendingPathComponent("opencode/service.json"))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        urls.append(home.appendingPathComponent(".local/state/opencode/service.json"))
        urls.append(home.appendingPathComponent("Library/Application Support/opencode/service.json"))
        return urls
    }

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func start() {
        guard poll == nil else { return }
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        poll?.tolerance = 0.5
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconnectNow() }
        }
        reconcile()
    }

    func stop() {
        poll?.invalidate()
        poll = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        resetConnection()
        session?.invalidateAndCancel()
        session = nil
        endpoint = nil
    }

    private func resetConnection() {
        generation = UUID()
        reconnect?.invalidate()
        reconnect = nil
        expiry?.invalidate()
        expiry = nil
        task?.cancel()
        task = nil
        for resolution in resolutions.values { resolution.cancel() }
        resolutions.removeAll()
        providers.removeAll()
        unsupportedUntil.removeAll()
        remainder = ""
        lastBeat = [:]
        publish()
    }

    private func reconcile() {
        guard poll != nil else { return }
        let next = loadEndpoint()
        guard next != endpoint else {
            if task == nil, reconnect == nil, endpoint != nil { connect() }
            return
        }
        resetConnection()
        endpoint = next
        backoff = 1
        if next != nil { connect() }
    }

    private func loadEndpoint() -> OpenCodeServiceEndpoint? {
        for url in files {
            guard let data = try? Data(contentsOf: url), let endpoint = OpenCodeServiceEndpoint.parse(data), endpoint.isProcessAlive else { continue }
            return endpoint
        }
        return nil
    }

    private func reconnectNow() {
        guard poll != nil else { return }
        resetConnection()
        endpoint = nil
        reconcile()
    }

    private func scheduleReconnect() {
        guard poll != nil, endpoint != nil, reconnect == nil, task == nil else { return }
        let generation = generation
        let delay = backoff
        backoff = min(15, max(1, backoff * 2))
        reconnect = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                self.reconnect = nil
                self.connect()
            }
        }
    }

    private func connect() {
        guard poll != nil, let session else { return }
        reconnect?.invalidate()
        reconnect = nil
        task?.cancel()
        task = nil
        remainder = ""
        guard let endpoint else { return }
        var request = URLRequest(url: endpoint.eventURL)
        request.setValue(endpoint.authorization, forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let next = session.dataTask(with: request)
        task = next
        next.resume()
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let allow = (response as? HTTPURLResponse)?.statusCode == 200
        completionHandler(allow ? .allow : .cancel)
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        Task { @MainActor in
            guard dataTask === self.task else { return }
            self.backoff = 1
            for frame in OpenCodeSSE.frames(from: text, remainder: &self.remainder) {
                self.handle(frame)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            guard task === self.task else { return }
            self.task = nil
            self.scheduleReconnect()
        }
    }

    private func handle(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = OpenCodeEvent.activitySessionID(in: object) else { return }
        if let integration = providers[sessionID] {
            beat(integration)
            return
        }
        resolve(sessionID)
    }

    private func resolve(_ sessionID: String) {
        guard resolutions[sessionID] == nil, (unsupportedUntil[sessionID] ?? .distantPast) <= Date(), let endpoint, let session else { return }
        let generation = generation
        var request = URLRequest(url: endpoint.sessionURL(sessionID))
        request.timeoutInterval = 10
        request.setValue(endpoint.authorization, forHTTPHeaderField: "Authorization")
        let resolution = session.dataTask(with: request) { [weak self] data, response, _ in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                self.resolutions[sessionID] = nil
                guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let provider = OpenCodeEvent.providerID(fromSession: object) else { return }
                guard let integration = IntegrationID.matchingOpenCodeProvider(provider) else {
                    self.unsupportedUntil[sessionID] = Date().addingTimeInterval(Self.grace)
                    return
                }
                self.providers[sessionID] = integration
                self.beat(integration)
            }
        }
        resolutions[sessionID] = resolution
        resolution.resume()
    }

    private func beat(_ integration: IntegrationID) {
        lastBeat[integration] = Date()
        publish()
        scheduleExpiry()
    }

    private func scheduleExpiry() {
        guard expiry == nil else { return }
        let cutoff = Date().addingTimeInterval(-Self.grace)
        lastBeat = lastBeat.filter { $0.value >= cutoff }
        guard let oldest = lastBeat.values.min() else { publish(); return }
        let delay = max(0.05, oldest.addingTimeInterval(Self.grace).timeIntervalSinceNow)
        let generation = generation
        expiry = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                self.expiry = nil
                self.scheduleExpiry()
            }
        }
        publish()
    }

    private func publish() {
        let cutoff = Date().addingTimeInterval(-Self.grace)
        let next = Set(lastBeat.compactMap { $0.value >= cutoff ? $0.key : nil })
        guard next != active else { return }
        active = next
        onChange?()
    }
}
