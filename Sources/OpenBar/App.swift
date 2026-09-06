import AppKit
import Sparkle
import ServiceManagement

@main
@MainActor
final class OpenBarApp: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = OpenBarApp()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings = SettingsStore.shared
    private let service = IntegrationService()
    private lazy var store = QuotaStore { [service] in try await service.fetch($0) }
    private lazy var notifications = NotificationManager(settings: settings)
    private var settingsWindow: SettingsWindowController?
    private let popover = NSPopover()
    private let controller = UsagePopoverViewController()
    private var actionsMenu: NSMenu?
    private var updater: SPUStandardUpdaterController?
    private var refreshTimer: Timer?
    private var loginTimer: Timer?
    private var keyMonitor: Any?
    private var interval: TimeInterval = 0
    private var resetting = Set<String>()
    private var statusKey = ""
    private var diagnostics = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = AppBranding.logoImage
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self
        controller.onRefresh = { [weak self] in self?.store.refresh() }
        controller.onOpenSettings = { [weak self] in self?.showSettings() }
        controller.onUseResetCredit = { [weak self] id in self?.useResetCredit(accountID: id) }
        store.onChange = { [weak self] in self?.render() }
        store.onFresh = { [weak self] in self?.notifications.evaluate($0) }
        settings.applyLaunchAtLoginDefaultIfNeeded()
        if ProcessInfo.processInfo.arguments.contains("--enable-launch-at-login"), Bundle.main.bundleURL.pathExtension == "app" {
            do {
                try settings.setLaunchAtLogin(true)
                let status = SMAppService.mainApp.status == .enabled ? "enabled" : "requires approval in System Settings"
                FileHandle.standardError.write(Data("Launch at login: \(status).\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("Launch at login setup failed: \(error.localizedDescription)\n".utf8))
            }
        }
        configureUpdater()
        buildActionsMenu()
        configureTimer()
        notifications.requestAuthorizationIfNeeded()
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: .openBarSettingsDidChange, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.store.refresh() }
        }
        store.setAccounts(settings.enabledAccounts)
        Task {
            if ProcessInfo.processInfo.arguments.contains("--import-google-oauth-clients") {
                let result = await Task.detached {
                    Result { try CredentialStore.importGoogleOAuthClients(environment: ProcessInfo.processInfo.environment) }
                }.value
                switch result {
                case .success(let count): print("Imported \(count) Google OAuth client(s) into OpenBar's local Keychain entries.")
                case .failure(let error): NSAlert(error: error).runModal()
                }
            }
            await store.restore()
            store.refresh()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func configureUpdater() {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return }
        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    private func configureTimer() {
        guard interval != settings.refreshInterval else { return }
        interval = settings.refreshInterval
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.refresh() }
        }
        refreshTimer?.tolerance = min(30, interval * 0.1)
    }

    private func render() {
        if ProcessInfo.processInfo.arguments.contains("--diagnostics") {
            let summary = store.accounts.map { account in
                let state = store.states[account.id] ?? IntegrationState()
                return "\(account.integration.rawValue): \(state.status); \(state.providers.count) quota account(s)"
            }.joined(separator: "\n")
            if summary != diagnostics {
                diagnostics = summary
                FileHandle.standardError.write(Data((summary + "\n").utf8))
            }
        }
        if popover.isShown { updatePopover() }
        settingsWindow?.updateStatuses(store.states)
        let candidates = store.accounts.flatMap { account in (store.states[account.id]?.providers ?? []).map { ($0, store.states[account.id]) } }
        let selected = candidates.max { $0.0.limitingWindow.usedPercent < $1.0.limitingWindow.usedPercent }
        let warning = store.accounts.contains { store.states[$0.id]?.message != nil }
        let percent = selected.map { settings.displayMode == .used ? $0.0.limitingWindow.usedPercent : $0.0.limitingWindow.remainingPercent }
        let text = percent.map { "\(Int($0.rounded()))%" } ?? "—"
        let key = "\(text)-\(warning)-\(selected?.0.id ?? "")-\(settings.displayMode.rawValue)"
        guard key != statusKey, let button = statusItem.button else { return }
        statusKey = key
        let state: StatusIconState = selected.map {
            .usage(progress: (percent ?? 0) / 100, color: AppBranding.progressColor(forUsedPercent: Int($0.0.limitingWindow.usedPercent)))
        } ?? .empty
        button.image = StatusIconRenderer.render(state, logo: AppBranding.logoImage)
        button.attributedTitle = NSAttributedString(string: text + (warning ? " ⚠" : ""), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor
        ])
        button.toolTip = selected.map { "\($0.0.name)\($0.0.accountLabel.map { " / \($0)" } ?? ""): \($0.0.limitingWindow.displayLabel), \(text) \(settings.displayMode.rawValue)" } ?? "Configure integrations in Settings"
        button.setAccessibilityLabel(button.toolTip)
    }

    private func updatePopover() {
        controller.update(states: store.presentationStates, enabled: store.enabled, displayMode: settings.displayMode)
    }

    @objc private func settingsChanged() {
        configureTimer()
        updater?.updater.automaticallyChecksForUpdates = settings.checkForUpdates
        notifications.requestAuthorizationIfNeeded()
        let added = settings.enabledAccounts.filter { !store.accounts.contains($0) }
        if store.accounts != settings.enabledAccounts { store.setAccounts(settings.enabledAccounts) }
        for account in added { store.refresh(only: account.id) }
        render()
    }

    @objc private func clicked() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = actionsMenu
            button.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            updatePopover()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func buildActionsMenu() {
        let menu = NSMenu()
        for (title, action, key) in [
            ("Refresh", #selector(refresh), "r"), ("Settings…", #selector(showSettings), ","),
            ("Sign In to Codex…", #selector(signIn), ""), ("Check for Updates…", #selector(checkForUpdates), ""),
            ("Quit OpenBar", #selector(quit), "q")
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        actionsMenu = menu
    }

    @objc private func refresh() { store.refresh() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func checkForUpdates() { updater?.checkForUpdates(nil) }

    @objc private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                settings: settings,
                onCheckForUpdates: { [weak self] in self?.checkForUpdates() },
                onSignIn: { [weak self] in self?.signIn() },
                onCredentialsChanged: { [weak self] id in self?.store.credentialsChanged(id) },
                onOAuthChanged: { [weak self] in
                    guard let self else { return }
                    for account in self.store.accounts where account.integration == .antigravity { self.store.credentialsChanged(account.id) }
                },
                canCheckForUpdates: { [weak self] in self?.updater != nil }
            )
        }
        settingsWindow?.updateStatuses(store.states)
        settingsWindow?.show()
    }

    private func useResetCredit(accountID: String) {
        guard !resetting.contains(accountID), let account = store.accounts.first(where: { $0.id == accountID && $0.integration == .codex }), store.states[accountID]?.isRefreshing != true else { return }
        resetting.insert(accountID)
        Task {
            let result: Result<ConsumeResetCreditsResponse, Error>
            do { result = .success(try await service.consumeCodexResetCredit(account: account)) } catch { result = .failure(error) }
            resetting.remove(accountID)
            controller.showResetCreditResult(result, accountID: accountID)
            if case .success = result { store.credentialsChanged(accountID) }
        }
    }

    @objc private func signIn() {
        let before = authFingerprint()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Terminal\" to do script \"codex login\"", "-e", "tell application \"Terminal\" to activate"]
        do { try process.run() } catch { NSAlert(error: error).runModal(); return }
        loginTimer?.invalidate()
        let deadline = Date().addingTimeInterval(300)
        loginTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                if Date() > deadline { timer.invalidate(); return }
                if let fingerprint = self.authFingerprint(), fingerprint != before {
                    timer.invalidate()
                    self.store.credentialsChanged(IntegrationAccount.current(.codex).id)
                }
            }
        }
    }

    private func authFingerprint() -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: CredentialStore.codexAuthURL().path),
              let date = attrs[.modificationDate] as? Date else { return nil }
        return "\(date)-\(attrs[.size] ?? 0)"
    }

    func popoverDidShow(_ notification: Notification) {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.modifierFlags.contains(.command) else { return event }
            switch event.charactersIgnoringModifiers {
            case "r": self.refresh()
            case ",": self.showSettings()
            case "q": self.quit()
            default: return event
            }
            return nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
        controller.cancelResetConfirmation()
    }
}
