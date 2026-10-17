import Foundation

struct UsageTokens: Equatable {
    var input: Double = 0
    var output: Double = 0
    var cacheRead: Double = 0
    var cacheWrite: Double = 0
    var total: Double { input + output + cacheRead + cacheWrite }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(input: lhs.input + rhs.input, output: lhs.output + rhs.output,
             cacheRead: lhs.cacheRead + rhs.cacheRead, cacheWrite: lhs.cacheWrite + rhs.cacheWrite)
    }
}

struct UsageHistoryRow {
    let source: String
    let model: String
    var tokens: UsageTokens
    var estimatedUSD: Double?
    var firstDate: Date?
    var lastDate: Date?
    var id: String { source + ":" + model }
}

struct UsageAccountTotal {
    let label: String
    let tokens: Double?
    let status: String
}

struct UsageHistorySnapshot {
    var rows: [UsageHistoryRow] = []
    var coverage: [String] = []
    var accountTotals: [UsageAccountTotal] = []
    var updatedAt = Date()
    var tokens: UsageTokens { rows.reduce(UsageTokens()) { $0 + $1.tokens } }
    var estimatedUSD: Double? {
        let priced = rows.compactMap(\.estimatedUSD)
        return priced.isEmpty ? nil : priced.reduce(0, +)
    }
    var unpricedTokens: Double { rows.filter { $0.estimatedUSD == nil }.reduce(0) { $0 + $1.tokens.total } }
    var firstDate: Date? { rows.compactMap(\.firstDate).min() }

    mutating func merge(_ incoming: [UsageHistoryRow]) {
        var grouped = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        for row in incoming {
            guard var existing = grouped[row.id] else { grouped[row.id] = row; continue }
            existing.tokens = existing.tokens + row.tokens
            if let old = existing.estimatedUSD, let new = row.estimatedUSD { existing.estimatedUSD = old + new }
            else { existing.estimatedUSD = nil }
            existing.firstDate = [existing.firstDate, row.firstDate].compactMap { $0 }.min()
            existing.lastDate = [existing.lastDate, row.lastDate].compactMap { $0 }.max()
            grouped[row.id] = existing
        }
        rows = grouped.values.sorted { $0.tokens.total == $1.tokens.total ? $0.id < $1.id : $0.tokens.total > $1.tokens.total }
    }
}

enum UsagePricing {
    struct Rate {
        let input: Double
        let read: Double
        let write: Double
        let output: Double
    }

    // Standard short-context list rates, checked 2026-10-17. Unknown models remain unpriced.
    static let rates: [String: Rate] = [
        "gpt-6-astra": Rate(input: 10, read: 1, write: 12.5, output: 50),
        "gpt-6.1-sol": Rate(input: 2, read: 0.1, write: 2.5, output: 10),
        "gpt-6-sol": Rate(input: 2, read: 0.2, write: 2.5, output: 10),
        "gpt-6-luna": Rate(input: 0.1, read: 0.01, write: 0.125, output: 0.5),
        "gpt-5.6-sol": Rate(input: 4, read: 0.4, write: 5, output: 20),
        "gpt-5.6-terra": Rate(input: 2, read: 0.2, write: 2.5, output: 12),
        "gpt-5.6-luna": Rate(input: 0.2, read: 0.02, write: 0.25, output: 1.2),
        "gpt-5.5": Rate(input: 5, read: 0.5, write: 5, output: 30),
        "gpt-5.4": Rate(input: 2.5, read: 0.25, write: 2.5, output: 15),
        "gpt-5.4-mini": Rate(input: 0.75, read: 0.075, write: 0.75, output: 4.5),
        "gpt-5.4-nano": Rate(input: 0.2, read: 0.02, write: 0.2, output: 1.25),
        "gpt-5.3-codex": Rate(input: 1.75, read: 0.175, write: 1.75, output: 14),
        "gpt-5.2": Rate(input: 1.75, read: 0.175, write: 1.75, output: 14),
        "gpt-5.1": Rate(input: 1.25, read: 0.125, write: 1.25, output: 10),
        "gpt-5": Rate(input: 1.25, read: 0.125, write: 1.25, output: 10),
        "claude-fable-5-1": Rate(input: 10, read: 0.25, write: 12.5, output: 50),
        "claude-mythos-5-1": Rate(input: 10, read: 0.25, write: 12.5, output: 50),
        "claude-fable-5": Rate(input: 10, read: 1, write: 12.5, output: 50),
        "claude-mythos-5": Rate(input: 10, read: 1, write: 12.5, output: 50),
        "claude-opus-5-5": Rate(input: 4, read: 0.2, write: 5, output: 20),
        "claude-opus-5": Rate(input: 5, read: 0.5, write: 6.25, output: 25),
        "claude-opus-4-8": Rate(input: 5, read: 0.5, write: 6.25, output: 25),
        "claude-opus-4-7": Rate(input: 5, read: 0.5, write: 6.25, output: 25),
        "claude-opus-4-6": Rate(input: 5, read: 0.5, write: 6.25, output: 25),
        "claude-opus-4-5": Rate(input: 5, read: 0.5, write: 6.25, output: 25),
        "claude-sonnet-5-5": Rate(input: 2, read: 0.1, write: 2.5, output: 10),
        "claude-sonnet-5": Rate(input: 2, read: 0.2, write: 2.5, output: 10),
        "claude-sonnet-4-6": Rate(input: 3, read: 0.3, write: 3.75, output: 15),
        "claude-sonnet-4-5": Rate(input: 3, read: 0.3, write: 3.75, output: 15),
        "claude-haiku-4-5": Rate(input: 1, read: 0.1, write: 1.25, output: 5)
    ]

    static func estimate(model: String, tokens: UsageTokens) -> Double? {
        var key = model
        if let range = key.range(of: #"-\d{8}$"#, options: .regularExpression) { key.removeSubrange(range) }
        guard let rate = rates[key] else { return nil }
        return (tokens.input * rate.input + tokens.output * rate.output + tokens.cacheRead * rate.read + tokens.cacheWrite * rate.write) / 1_000_000
    }
}

enum UsageHistoryError: Error { case invalidData, unavailable }

enum UsageHistoryParsing {
    static func count(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let number = value.doubleValue
        return number.isFinite && number >= 0 && number <= 9_007_199_254_740_991 && number.rounded() == number ? number : nil
    }

    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func codexLifetime(_ data: Data) throws -> Double {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stats = root["stats"] as? [String: Any], let total = count(stats["lifetime_tokens"]) else { throw UsageHistoryError.invalidData }
        return total
    }

    static func openCode(_ data: Data) throws -> [UsageHistoryRow] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = root["data"] as? [String: Any], let models = body["models"] as? [[String: Any]],
              let range = body["range"] as? [String: Any], let from = count(range["from"]), let to = count(range["to"]), from <= to else {
            throw UsageHistoryError.invalidData
        }
        return try models.map { item in
            guard let model = item["model"] as? [String: Any], let id = model["id"] as? String,
                  let provider = model["providerID"] as? String, let raw = item["tokens"] as? [String: Any],
                  let cache = raw["cache"] as? [String: Any], let input = count(raw["input"]),
                  let output = count(raw["output"]), let reasoning = count(raw["reasoning"]),
                  let read = count(cache["read"]), let write = count(cache["write"]) else { throw UsageHistoryError.invalidData }
            let tokens = UsageTokens(input: input, output: output + reasoning, cacheRead: read, cacheWrite: write)
            let reportedCost = (item["cost"] as? NSNumber)?.doubleValue
            let estimate = reportedCost.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? UsagePricing.estimate(model: id, tokens: tokens)
            return UsageHistoryRow(source: "OpenCode / \(provider)", model: id, tokens: tokens, estimatedUSD: estimate,
                                   firstDate: Date(timeIntervalSince1970: from / 1000), lastDate: Date(timeIntervalSince1970: to / 1000))
        }
    }
}

struct LocalUsageFile {
    var sessionID: String
    var rows: [UsageHistoryRow] = []
    var claudeMessages: [String: UsageHistoryRow] = [:]
    var skipped = 0
}

struct LocalUsageParser {
    enum Kind { case codex, claude }
    let kind: Kind
    var result: LocalUsageFile
    private var model = "Unknown model"
    private var start: Date?
    private var previous = UsageTokens()

    init(kind: Kind, fileID: String) { self.kind = kind; result = LocalUsageFile(sessionID: fileID) }

    mutating func consume(_ data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { result.skipped += 1; return }
        switch kind {
        case .codex:
            let payload = root["payload"] as? [String: Any] ?? [:]
            if root["type"] as? String == "session_meta" {
                result.sessionID = payload["id"] as? String ?? payload["session_id"] as? String ?? result.sessionID
                start = UsageHistoryParsing.date(payload["timestamp"])
            }
            if root["type"] as? String == "turn_context" { model = payload["model"] as? String ?? model }
            guard root["type"] as? String == "event_msg", payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any], let usage = info["total_token_usage"] as? [String: Any],
                  let input = UsageHistoryParsing.count(usage["input_tokens"]), let output = UsageHistoryParsing.count(usage["output_tokens"]),
                  let read = UsageHistoryParsing.count(usage["cached_input_tokens"] ?? 0),
                  let write = UsageHistoryParsing.count(usage["cache_write_input_tokens"] ?? 0), input >= read + write else { return }
            let current = UsageTokens(input: input - read - write, output: output, cacheRead: read, cacheWrite: write)
            let delta = UsageTokens(input: max(0, current.input - previous.input), output: max(0, current.output - previous.output),
                                    cacheRead: max(0, current.cacheRead - previous.cacheRead), cacheWrite: max(0, current.cacheWrite - previous.cacheWrite))
            previous = UsageTokens(input: max(previous.input, current.input), output: max(previous.output, current.output),
                                   cacheRead: max(previous.cacheRead, current.cacheRead), cacheWrite: max(previous.cacheWrite, current.cacheWrite))
            let timestamp = UsageHistoryParsing.date(root["timestamp"])
            if let start, let timestamp, timestamp < start { return }
            guard delta.total > 0 else { return }
            let row = UsageHistoryRow(source: "Codex local", model: model, tokens: delta,
                                      estimatedUSD: UsagePricing.estimate(model: model, tokens: delta), firstDate: timestamp, lastDate: timestamp)
            var summary = UsageHistorySnapshot(rows: result.rows)
            summary.merge([row])
            result.rows = summary.rows
        case .claude:
            guard root["type"] as? String == "assistant", let message = root["message"] as? [String: Any],
                  let id = message["id"] as? String, let model = message["model"] as? String,
                  let usage = message["usage"] as? [String: Any], let input = UsageHistoryParsing.count(usage["input_tokens"]),
                  let output = UsageHistoryParsing.count(usage["output_tokens"]),
                  let read = UsageHistoryParsing.count(usage["cache_read_input_tokens"] ?? 0),
                  let write = UsageHistoryParsing.count(usage["cache_creation_input_tokens"] ?? 0) else { return }
            let tokens = UsageTokens(input: input, output: output, cacheRead: read, cacheWrite: write)
            if let old = result.claudeMessages[id], old.tokens.total >= tokens.total { return }
            let timestamp = UsageHistoryParsing.date(root["timestamp"])
            result.claudeMessages[id] = UsageHistoryRow(source: "Claude local", model: model, tokens: tokens,
                                                       estimatedUSD: UsagePricing.estimate(model: model, tokens: tokens), firstDate: timestamp, lastDate: timestamp)
        }
    }
}

actor UsageHistoryService {
    private struct CachedFile { let size: Int; let modified: Date; let parsed: LocalUsageFile }
    private var cache: [URL: CachedFile] = [:]
    private let codexRoot: URL
    private let claudeRoot: URL
    private let serviceFiles: [URL]
    private let session: URLSession

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, environment: [String: String] = ProcessInfo.processInfo.environment,
         serviceFiles: [URL] = OpenCodeActivityMonitor.serviceFiles(), configuration: URLSessionConfiguration = .ephemeral) {
        codexRoot = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
        claudeRoot = environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claude")
        self.serviceFiles = serviceFiles
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration, delegate: UsageHistoryRedirects(), delegateQueue: nil)
    }

    func load() async throws -> UsageHistorySnapshot {
        var result = try localHistory()
        do {
            guard let endpoint = serviceFiles.compactMap({ url in
                (try? Data(contentsOf: url)).flatMap(OpenCodeServiceEndpoint.parse)
            }).first(where: { $0.isProcessAlive }) else { throw UsageHistoryError.unavailable }
            var components = URLComponents(url: endpoint.url.appendingPathComponent("api/experimental/session/stats"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "tools", value: "none")]
            var request = URLRequest(url: components.url!)
            request.setValue(endpoint.authorization, forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UsageHistoryError.unavailable }
            let rows = try UsageHistoryParsing.openCode(data)
            result.merge(rows)
            result.coverage.append("OpenCode API: all history returned by the local service. Includes all recorded providers.")
        } catch {
            try Task.checkCancellation()
            result.coverage.append("OpenCode API unavailable. Its usage is not included; open OpenCode and refresh.")
        }
        return result
    }

    func localHistory() throws -> UsageHistorySnapshot {
        let fm = FileManager.default
        var result = UsageHistorySnapshot()
        var sessions: [String: LocalUsageFile] = [:]
        var messages: [String: UsageHistoryRow] = [:]
        var visited = Set<URL>()
        var fileCounts = ["Codex": 0, "Claude": 0]
        var skipped = 0
        let roots: [(String, URL, LocalUsageParser.Kind)] = [
            ("Codex", codexRoot.appendingPathComponent("sessions"), .codex),
            ("Codex", codexRoot.appendingPathComponent("archived_sessions"), .codex),
            ("Claude", claudeRoot.appendingPathComponent("projects"), .claude)
        ]
        for (name, root, kind) in roots {
            guard fm.fileExists(atPath: root.path) else { continue }
            guard let files = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                                            options: [.skipsHiddenFiles], errorHandler: { _, _ in skipped += 1; return true }) else { skipped += 1; continue }
            for case let url as URL in files {
                try Task.checkCancellation()
                if url.pathExtension == "zst" { skipped += 1; continue }
                guard url.pathExtension == "jsonl" else { continue }
                do {
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
                    guard values.isRegularFile == true, let size = values.fileSize, let modified = values.contentModificationDate else { continue }
                    visited.insert(url)
                    let parsed: LocalUsageFile
                    if let cached = cache[url], cached.size == size, cached.modified == modified { parsed = cached.parsed }
                    else {
                        parsed = try parseFile(url, kind: kind)
                        cache[url] = CachedFile(size: size, modified: modified, parsed: parsed)
                    }
                    fileCounts[name, default: 0] += 1
                    skipped += parsed.skipped
                    if kind == .codex {
                        let existingTotal = sessions[parsed.sessionID]?.rows.reduce(0) { $0 + $1.tokens.total } ?? -1
                        let incomingTotal = parsed.rows.reduce(0) { $0 + $1.tokens.total }
                        if incomingTotal > existingTotal { sessions[parsed.sessionID] = parsed }
                    } else {
                        for (id, row) in parsed.claudeMessages where (messages[id]?.tokens.total ?? -1) < row.tokens.total { messages[id] = row }
                    }
                } catch {
                    try Task.checkCancellation()
                    skipped += 1
                }
            }
        }
        cache = cache.filter { visited.contains($0.key) }
        for session in sessions.values { result.merge(session.rows) }
        result.merge(Array(messages.values))
        for name in ["Codex", "Claude"] {
            let count = fileCounts[name, default: 0]
            result.coverage.append(count == 0 ? "\(name): no local history found." : "\(name): \(count) local history files. Deleted history and other Macs are not included.")
        }
        if skipped > 0 { result.coverage.append("Partial local history: \(skipped) unreadable, compressed or malformed records/files skipped.") }
        return result
    }

    private func parseFile(_ url: URL, kind: LocalUsageParser.Kind) throws -> LocalUsageFile {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var parser = LocalUsageParser(kind: kind, fileID: url.lastPathComponent)
        var pending = Data()
        var dropping = false
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            pending.append(chunk)
            while let end = pending.firstIndex(of: 10) {
                let line = pending[..<end]
                if !dropping && !line.isEmpty { parser.consume(Data(line)) }
                pending.removeSubrange(...end)
                dropping = false
            }
            if pending.count > 16 * 1_024 * 1_024 {
                pending.removeAll(keepingCapacity: false)
                dropping = true
                parser.result.skipped += 1
            }
        }
        // An unterminated final line may still be in flight; retry it when the file changes.
        if !pending.isEmpty { parser.result.skipped += 1 }
        return parser.result
    }
}

private final class UsageHistoryRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
