import AppKit
import Network
import Sparkle

@main
@MainActor
private final class SparkleChecks: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!
    private var found = false
    private var listener: NWListener?
    private var fixtureURL: String?
    private var feed = Data()

    static func main() throws {
        let app = NSApplication.shared
        let delegate = SparkleChecks()
        delegate.feed = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            let feed = feed
            listener.newConnectionHandler = { connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { _, _, _, _ in
                    var response = Data("HTTP/1.1 200 OK\r\nContent-Type: application/rss+xml\r\nContent-Length: \(feed.count)\r\nConnection: close\r\n\r\n".utf8)
                    response.append(feed)
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                }
            }
            listener.stateUpdateHandler = { state in
                Task { @MainActor in
                    if case .ready = state, let port = listener.port {
                        self.fixtureURL = "http://127.0.0.1:\(port.rawValue)/appcast.xml"
                        self.checkFeed()
                    } else if case .failed(let error) = state { self.finish(error.localizedDescription) }
                }
            }
            listener.start(queue: .global())
        } catch { finish(error.localizedDescription) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { self.finish("Timed out checking fixture feed") }
    }

    func feedURLString(for updater: SPUUpdater) -> String? { fixtureURL }

    private func checkFeed() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        do {
            try controller.updater.start()
            precondition(!controller.updater.automaticallyChecksForUpdates, "Sparkle must honor automatic-check opt-out at startup")
            precondition(controller.updater.canCheckForUpdates, "Manual checks remain available after automatic opt-out")
            controller.updater.checkForUpdateInformation()
            precondition(!controller.updater.canCheckForUpdates, "The manual action must be disabled while a background check is running")
        } catch { finish(error.localizedDescription) }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        found = item.versionString == "2" && item.displayVersionString == "1.0.1"
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error { finish("\(error as NSError) \((error as NSError).userInfo)"); return }
        guard found else { finish("Sparkle did not discover fixture version 1.0.1"); return }
        guard updater.canCheckForUpdates else { finish("Manual checks did not re-enable after completion"); return }
        print("PASS real Sparkle startup, automatic opt-out, feed discovery and busy/ready transitions")
        finish(nil)
    }

    private func finish(_ error: String?) {
        listener?.cancel()
        if let error { FileHandle.standardError.write(Data("FAIL \(error)\n".utf8)) }
        if let identifier = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: identifier) }
        exit(error == nil ? 0 : 1)
    }
}
