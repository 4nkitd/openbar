import AppKit
import Sparkle

@main
@MainActor
final class CodexBarLiteApp: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = CodexBarLiteApp()
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
    private var resetting = false
    private var statusKey = ""

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
        controller.onUseResetCredit = { [weak self] in self?.useResetCredit() }
        store.onChange = { [weak self] in self?.render() }
        store.onFresh = { [weak self] in self?.notifications.evaluate($0) }
        settings.applyLaunchAtLoginDefaultIfNeeded()
        configureUpdater()
        buildActionsMenu()
        configureTimer()
        notifications.requestAuthorizationIfNeeded()
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: .codexBarSettingsDidChange, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.store.refresh() }
        }
        store.setEnabled(settings.enabledIntegrations)
        Task {
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
        if popover.isShown { updatePopover() }
        settingsWindow?.updateStatuses(store.states)
        let candidates = store.enabled.flatMap { id in (store.states[id]?.providers ?? []).map { ($0, store.states[id]) } }
        let selected = candidates.max { $0.0.limitingWindow.usedPercent < $1.0.limitingWindow.usedPercent }
        let warning = store.enabled.contains { store.states[$0]?.message != nil }
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
        button.toolTip = selected.map { "\($0.0.name): \($0.0.limitingWindow.displayLabel), \(text) \(settings.displayMode.rawValue)" } ?? "Configure integrations in Settings"
        button.setAccessibilityLabel(button.toolTip)
    }

    private func updatePopover() {
        controller.update(states: store.states, enabled: store.enabled, displayMode: settings.displayMode)
    }

    @objc private func settingsChanged() {
        configureTimer()
        updater?.updater.automaticallyChecksForUpdates = settings.checkForUpdates
        notifications.requestAuthorizationIfNeeded()
        let added = settings.enabledIntegrations.filter { !store.enabled.contains($0) }
        if store.enabled != settings.enabledIntegrations { store.setEnabled(settings.enabledIntegrations) }
        for id in added { store.refresh(only: id) }
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
            ("Quit CodexBar Lite", #selector(quit), "q")
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
                canCheckForUpdates: { [weak self] in self?.updater != nil }
            )
        }
        settingsWindow?.updateStatuses(store.states)
        settingsWindow?.show()
    }

    private func useResetCredit() {
        guard !resetting, store.enabled.contains(.codex), store.states[.codex]?.isRefreshing != true else { return }
        resetting = true
        Task {
            let result: Result<ConsumeResetCreditsResponse, Error>
            do { result = .success(try await service.consumeCodexResetCredit()) } catch { result = .failure(error) }
            resetting = false
            controller.showResetCreditResult(result)
            if case .success = result { store.credentialsChanged(.codex) }
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
                    self.store.credentialsChanged(.codex)
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
