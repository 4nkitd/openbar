import AppKit
import Foundation
import Sparkle

struct CodexAuth: Decodable {
    let tokens: Tokens?

    struct Tokens: Decodable {
        let accessToken: String?
        let accountID: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountID = "account_id"
        }
    }
}

struct CodexUsage: Codable {
    let planType: String
    let rateLimit: RateLimit
    let rateLimitResetCredits: ResetCredits?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case rateLimitResetCredits = "rate_limit_reset_credits"
    }
}

struct RateLimit: Codable {
    let allowed: Bool?
    let limitReached: Bool?
    let primaryWindow: UsageWindow
    let secondaryWindow: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

struct UsageWindow: Codable {
    let usedPercent: Int
    let limitWindowSeconds: Int?
    let resetAfterSeconds: Int
    let resetAt: Int

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }
}

struct ResetCredits: Codable {
    let availableCount: Int
    let applicableAvailableCount: Int?

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
        case applicableAvailableCount = "applicable_available_count"
    }
}

struct ConsumeResetCreditsResponse: Decodable {
    let code: String
    let windowsReset: Int

    enum CodingKeys: String, CodingKey {
        case code
        case windowsReset = "windows_reset"
    }
}

final class CodexBarLiteApp: NSObject, NSApplicationDelegate {
    private enum PresentationState {
        case usage
        case signedOut(signingIn: Bool)
        case failure(String)
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings = SettingsStore.shared
    private let usageURL = URL(string: "https://chatgpt.com/backend-api/codex/usage")!
    private let resetCreditsConsumeURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume")!
    private lazy var notificationManager = NotificationManager(settings: settings)
    private var settingsWindowController: SettingsWindowController?
    private let popover = NSPopover()
    private let popoverController = UsagePopoverViewController()
    private var actionsMenu: NSMenu?
    private var updaterController: SPUStandardUpdaterController?
    private var refreshTimer: Timer?
    private var loginPollTimer: Timer?
    private var lastUsage: CodexUsage?
    private var lastUpdatedAt: Date?
    private var lastWarning: String?
    private var presentationState: PresentationState?
    private var popoverKeyMonitor: Any?
    private var loginLaunched = false
    private var authFingerprintBeforeLogin: String?
    private var isRefreshing = false
    private var isConsumingReset = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let logoImage = AppBranding.logoImage {
            NSApp.applicationIconImage = logoImage
        }
        configureStatusItem()
        renderStatusItem()
        configurePopover()

        settings.applyLaunchAtLoginDefaultIfNeeded()
        configureUpdater()
        configureRefreshTimer()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: .codexBarSettingsDidChange,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }

        refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Status item & popover

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.contentViewController = popoverController
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popoverController.onRefresh = { [weak self] in self?.refresh() }
        popoverController.onSignIn = { [weak self] in self?.runCodexLogin() }
        popoverController.onUseResetCredit = { [weak self] in self?.useResetCredit() }
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem.button, let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            guard let menu = actionsMenu else { return }
            statusItem.menu = menu
            button.performClick(nil)
            statusItem.menu = nil
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func installPopoverKeyMonitor() {
        guard popoverKeyMonitor == nil else { return }
        popoverKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.modifierFlags.contains(.command) else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "r":
                self.refresh()
                return nil
            case ",":
                self.showSettings()
                return nil
            case "q":
                self.quit()
                return nil
            default:
                return event
            }
        }
    }

    private func removePopoverKeyMonitor() {
        if let monitor = popoverKeyMonitor {
            NSEvent.removeMonitor(monitor)
            popoverKeyMonitor = nil
        }
    }

    private func refreshDisplayedState() {
        switch presentationState {
        case .usage:
            if let usage = lastUsage, let updatedAt = lastUpdatedAt {
                popoverController.update(
                    state: .usage(usage, updatedAt: updatedAt, warning: lastWarning),
                    displayMode: settings.displayMode
                )
            }
        case .signedOut(let signingIn):
            popoverController.update(state: .signedOut(signingIn: signingIn), displayMode: settings.displayMode)
        case .failure(let message):
            popoverController.update(state: .failure(message), displayMode: settings.displayMode)
        case nil:
            break
        }
    }

    // MARK: - Setup

    private func configureUpdater() {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else {
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
    }

    private func configureRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: settings.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task {
            do {
                let auth = try readAuth()
                let usage = try await fetchUsage(auth: auth)

                await MainActor.run {
                    let updatedAt = Date()
                    self.loginPollTimer?.invalidate()
                    self.loginPollTimer = nil
                    self.renderUsage(usage, updatedAt: updatedAt, warning: nil)
                    self.notificationManager.requestAuthorizationIfNeeded()
                    self.notificationManager.evaluate(usage)
                    try? self.writeCache(usage)
                    self.isRefreshing = false
                }
            } catch CodexError.notLoggedIn {
                await MainActor.run {
                    self.handleNotLoggedIn()
                    self.isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    if let cached = try? self.readCache() {
                        self.renderUsage(cached.usage, updatedAt: cached.updatedAt, warning: error.localizedDescription)
                    } else {
                        self.renderErrorMenu(error)
                    }
                    self.isRefreshing = false
                }
            }
        }
    }

    private func useResetCredit() {
        guard !isConsumingReset else { return }
        isConsumingReset = true

        Task {
            do {
                let auth = try readAuth()
                let result = try await consumeResetCredit(auth: auth)
                await MainActor.run {
                    self.isConsumingReset = false
                    self.popoverController.showResetCreditResult(.success(result))
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    self.isConsumingReset = false
                    self.popoverController.showResetCreditResult(.failure(error))
                }
            }
        }
    }

    private func handleNotLoggedIn() {
        if !loginLaunched {
            authFingerprintBeforeLogin = authFingerprint()
            loginLaunched = true
            renderLoginMenu(signingIn: true)
            launchCodexLogin()
            startLoginPolling()
        } else {
            renderLoginMenu(signingIn: loginPollTimer != nil)
        }
    }

    private func startLoginPolling() {
        loginPollTimer?.invalidate()
        loginPollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let fingerprint = self.authFingerprint()
            guard fingerprint != nil, fingerprint != self.authFingerprintBeforeLogin else { return }
            self.authFingerprintBeforeLogin = fingerprint
            self.refresh()
        }
    }

    private func readAuth() throws -> CodexAuth.Tokens {
        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")

        guard FileManager.default.fileExists(atPath: authURL.path) else {
            throw CodexError.notLoggedIn
        }

        let data = try Data(contentsOf: authURL)
        let auth = try JSONDecoder().decode(CodexAuth.self, from: data)

        guard let tokens = auth.tokens, let accessToken = tokens.accessToken, !accessToken.isEmpty else {
            throw CodexError.notLoggedIn
        }

        return tokens
    }

    private func currentAuthStatus() -> AuthStatus {
        guard let tokens = try? readAuth(),
              let accessToken = tokens.accessToken, !accessToken.isEmpty else {
            return AuthStatus(signedIn: false, accountID: nil)
        }
        return AuthStatus(signedIn: true, accountID: tokens.accountID)
    }

    private func authFingerprint() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return "\(date.timeIntervalSince1970)-\(size.intValue)"
    }

    private func fetchUsage(auth: CodexAuth.Tokens) async throws -> CodexUsage {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(auth.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-cli/0.11.0", forHTTPHeaderField: "User-Agent")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        if let accountID = auth.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let body = String(data: data, encoding: .utf8) ?? ""

        if body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<html") {
            throw CodexError.cloudflareChallenge
        }

        guard let http = response as? HTTPURLResponse else {
            throw CodexError.invalidResponse
        }

        if http.statusCode == 401 {
            throw CodexError.notLoggedIn
        }

        guard (200..<300).contains(http.statusCode) else {
            throw CodexError.httpError(http.statusCode)
        }

        return try JSONDecoder().decode(CodexUsage.self, from: data)
    }

    private func consumeResetCredit(auth: CodexAuth.Tokens) async throws -> ConsumeResetCreditsResponse {
        var request = URLRequest(url: resetCreditsConsumeURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(auth.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("codex-cli/0.11.0", forHTTPHeaderField: "User-Agent")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        if let accountID = auth.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        }
        request.httpBody = try JSONEncoder().encode(["redeem_request_id": UUID().uuidString])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw CodexError.invalidResponse
        }

        if http.statusCode == 401 {
            throw CodexError.notLoggedIn
        }

        guard (200..<300).contains(http.statusCode) else {
            throw CodexError.httpError(http.statusCode)
        }

        return try JSONDecoder().decode(ConsumeResetCreditsResponse.self, from: data)
    }

    // MARK: - Presentation

    private func renderUsage(_ usage: CodexUsage, updatedAt: Date, warning: String?) {
        lastUsage = usage
        lastUpdatedAt = updatedAt
        lastWarning = warning
        presentationState = .usage
        renderStatusItem()
        rebuildActionsMenu(showLogin: false)
        popoverController.update(
            state: .usage(usage, updatedAt: updatedAt, warning: warning),
            displayMode: settings.displayMode
        )
        settingsWindowController?.reloadAuth()
    }

    private func renderLoginMenu(signingIn: Bool) {
        lastUsage = nil
        lastUpdatedAt = nil
        presentationState = .signedOut(signingIn: signingIn)
        renderStatusItem()
        rebuildActionsMenu(showLogin: true)
        popoverController.update(state: .signedOut(signingIn: signingIn), displayMode: settings.displayMode)
    }

    private func renderErrorMenu(_ error: Error) {
        presentationState = .failure(error.localizedDescription)
        renderStatusItem()
        rebuildActionsMenu(showLogin: false)
        popoverController.update(state: .failure(error.localizedDescription), displayMode: settings.displayMode)
    }

    private func rebuildActionsMenu(showLogin: Bool) {
        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshMenuAction), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        if showLogin {
            let loginItem = NSMenuItem(title: "Sign In to Codex", action: #selector(runCodexLogin), keyEquivalent: "")
            loginItem.target = self
            menu.addItem(loginItem)
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesMenuAction), keyEquivalent: "")
        updateItem.target = self
        updateItem.isEnabled = updaterController != nil
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit CodexBar Lite", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        actionsMenu = menu
        popoverController.actionsMenu = menu
    }

    private func renderStatusItem() {
        guard let button = statusItem.button else { return }

        let logo = AppBranding.logoImage

        switch presentationState {
        case .usage:
            guard let usage = lastUsage else {
                button.image = StatusIconRenderer.render(.empty, logo: logo)
                return
            }
            let used = usage.rateLimit.primaryWindow.usedPercent
            let shown = settings.displayMode == .used ? used : 100 - used
            let progress = Double(max(0, min(100, shown))) / 100
            let color = AppBranding.progressColor(forUsedPercent: used)
            button.image = StatusIconRenderer.render(.usage(progress: progress, color: color), logo: logo)
            button.attributedTitle = statusItemTitle("\(shown)%", warningSuffix: lastWarning != nil)
        case .signedOut:
            button.image = StatusIconRenderer.render(.empty, logo: logo)
            button.attributedTitle = statusItemTitle("—%", warningSuffix: false)
        case .failure:
            button.image = StatusIconRenderer.render(.empty, logo: logo)
            button.attributedTitle = statusItemTitle("—%", warningSuffix: false)
        case nil:
            button.image = StatusIconRenderer.render(.empty, logo: logo)
            button.attributedTitle = statusItemTitle("—%", warningSuffix: false)
        }
    }

    private func statusItemTitle(_ text: String, warningSuffix: Bool) -> NSAttributedString {
        let suffixText = warningSuffix ? " ⚠" : ""
        let baseFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let attr = NSMutableAttributedString(string: text + suffixText, attributes: [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor
        ])
        if warningSuffix {
            let ns = attr.string as NSString
            let range = ns.range(of: suffixText)
            if range.location != NSNotFound {
                attr.addAttribute(.foregroundColor, value: NSColor.systemYellow, range: range)
            }
        }
        return attr
    }

    private func displayedPercent(_ window: UsageWindow) -> Int {
        settings.displayMode == .used ? window.usedPercent : 100 - window.usedPercent
    }

    // MARK: - Actions

    @objc private func refreshMenuAction() {
        refresh()
    }

    @objc private func runCodexLogin() {
        authFingerprintBeforeLogin = authFingerprint()
        loginLaunched = true
        renderLoginMenu(signingIn: true)
        launchCodexLogin()
        startLoginPolling()
    }

    private func launchCodexLogin() {
        let script = """
        tell application "Terminal"
            activate
            do script "codex login"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
        } catch {
            renderErrorMenu(CodexError.loginLaunchFailed)
        }
    }

    @objc private func showSettings() {
        popover.performClose(nil)
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings,
                onCheckForUpdates: { [weak self] in self?.checkForUpdates() },
                onSignIn: { [weak self] in self?.runCodexLogin() },
                authStatusProvider: { [weak self] in
                    self?.currentAuthStatus() ?? AuthStatus(signedIn: false, accountID: nil)
                },
                canCheckForUpdates: { [weak self] in self?.updaterController != nil }
            )
        }
        settingsWindowController?.show()
    }

    @objc private func checkForUpdatesMenuAction() {
        checkForUpdates()
    }

    private func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func settingsDidChange() {
        configureRefreshTimer()
        if let updater = updaterController?.updater,
           updater.automaticallyChecksForUpdates != settings.checkForUpdates {
            updater.automaticallyChecksForUpdates = settings.checkForUpdates
        }
        notificationManager.requestAuthorizationIfNeeded()
        refreshDisplayedState()
        renderStatusItem()
    }

    // MARK: - Cache

    private func cacheURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexBarLite/usage.json")
    }

    private func writeCache(_ usage: CodexUsage) throws {
        let url = cacheURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(usage)
        try data.write(to: url, options: .atomic)
    }

    private func readCache() throws -> (usage: CodexUsage, updatedAt: Date) {
        let url = cacheURL()
        let data = try Data(contentsOf: url)
        let usage = try JSONDecoder().decode(CodexUsage.self, from: data)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let updatedAt = attributes[.modificationDate] as? Date ?? Date()
        return (usage, updatedAt)
    }
}

extension CodexBarLiteApp: NSPopoverDelegate {
    func popoverWillShow(_ notification: Notification) {
        refreshDisplayedState()
    }

    func popoverDidShow(_ notification: Notification) {
        installPopoverKeyMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        removePopoverKeyMonitor()
    }
}

enum CodexError: LocalizedError {
    case notLoggedIn
    case invalidResponse
    case cloudflareChallenge
    case httpError(Int)
    case loginLaunchFailed

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Not logged in."
        case .invalidResponse:
            return "Invalid response."
        case .cloudflareChallenge:
            return "Cloudflare challenge. Showing cached usage."
        case .httpError(let status):
            return "Request failed with status \(status)."
        case .loginLaunchFailed:
            return "Couldn’t open Terminal for codex login."
        }
    }
}

let app = NSApplication.shared
let delegate = CodexBarLiteApp()
app.delegate = delegate
app.run()
