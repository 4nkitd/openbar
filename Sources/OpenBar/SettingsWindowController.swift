import AppKit
import ServiceManagement

final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    private enum Pane: String, CaseIterable {
        case general, integrations, notifications, about
        var title: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .integrations: return "person.2"
            case .notifications: return "bell"
            case .about: return "info.circle"
            }
        }
        var identifier: NSToolbarItem.Identifier { .init(rawValue) }
        var height: CGFloat {
            switch self {
            case .general: return 250
            case .integrations: return 490
            case .notifications: return 240
            case .about: return 300
            }
        }
    }

    private let settings: SettingsStore
    private let onCheckForUpdates: () -> Void
    private let canCheckForUpdates: () -> Bool
    private let tabs = NSTabView()
    private let accountsView: AccountsPreferencesView
    private var toggles: [String: NSButton] = [:]
    private let refreshPopup = NSPopUpButton()
    private let modePopup = NSPopUpButton()
    private let updateButton = NSButton(title: "Check for Updates…", target: nil, action: nil)

    init(settings: SettingsStore, onCheckForUpdates: @escaping () -> Void, onSignIn: @escaping () -> Void,
         onCredentialsChanged: @escaping (String) -> Void, onOAuthChanged: @escaping () -> Void,
         canCheckForUpdates: @escaping () -> Bool) {
        self.settings = settings
        self.onCheckForUpdates = onCheckForUpdates
        self.canCheckForUpdates = canCheckForUpdates
        accountsView = AccountsPreferencesView(settings: settings, onSignIn: onSignIn,
                                              onCredentialsChanged: onCredentialsChanged, onOAuthChanged: onOAuthChanged)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 490), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        super.init(window: window)
        tabs.tabViewType = .noTabsNoBorder
        let panes: [NSView] = [generalPane(), accountsView, notificationsPane(), aboutPane()]
        for (pane, view) in zip(Pane.allCases, panes) {
            let tab = NSTabViewItem(identifier: pane.rawValue)
            tab.view = view
            tabs.addTabViewItem(tab)
        }
        window.contentView = tabs
        let toolbar = NSToolbar(identifier: "OpenBarSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
        select(.integrations)
        window.center()
        sync()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        sync()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func updateStatuses(_ states: [String: IntegrationState]) { accountsView.updateStatuses(states) }

    private func pane(_ items: [NSView]) -> NSView {
        let view = SettingsBackgroundView()
        let stack = NSStackView(views: items)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24)
        ])
        for item in items { item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return view
    }

    private func toggle(_ title: String, key: String) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggleChanged(_:)))
        button.identifier = .init(key)
        toggles[key] = button
        return button
    }

    private func generalPane() -> NSView {
        refreshPopup.addItems(withTitles: ["1 minute", "5 minutes", "15 minutes", "30 minutes"])
        refreshPopup.target = self
        refreshPopup.action = #selector(refreshChanged)
        modePopup.addItems(withTitles: ["Percentage used", "Percentage remaining"])
        modePopup.target = self
        modePopup.action = #selector(modeChanged)
        return pane([
            toggle("Launch OpenBar at login", key: "login"),
            settingRow("Refresh interval", control: refreshPopup),
            settingRow("Progress bars", control: modePopup),
            toggle("Automatically check for updates", key: "updates"),
            settingsCaption("Each account has its own refresh state and retry delay. Display changes do not trigger API requests.")
        ])
    }

    private func notificationsPane() -> NSView {
        pane([
            toggle("Notify at 80% usage", key: "80"), toggle("Notify at 90% usage", key: "90"),
            toggle("Notify when a quota is exhausted", key: "exhausted"), toggle("Notify when a quota resets", key: "reset"),
            settingsCaption("Alerts apply separately to each account and quota window. Cached readings never trigger notifications.")
        ])
    }

    private func aboutPane() -> NSView {
        let name = NSTextField(labelWithString: AppBranding.name)
        name.font = .systemFont(ofSize: 23, weight: .semibold)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let subtitle = NSStackView(views: [name, settingsCaption("Version \(version) · by 4nkitd")])
        subtitle.orientation = .vertical
        subtitle.alignment = .leading
        let icon = NSImageView(image: AppBranding.logoImage ?? NSImage())
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true
        let title = NSStackView(views: [icon, subtitle, flexibleSpacer()])
        title.spacing = 14
        let github = NSButton(title: "OpenBar on GitHub", target: self, action: #selector(openGitHub))
        let issue = NSButton(title: "Report an issue", target: self, action: #selector(openIssues))
        for button in [github, issue, updateButton] { button.bezelStyle = .rounded }
        updateButton.target = self
        updateButton.action = #selector(checkForUpdates)
        let buttons = NSStackView(views: [github, issue, flexibleSpacer()])
        buttons.spacing = 8
        return pane([
            title,
            settingsCaption("Your AI coding quotas, in one menu bar. Codex, Claude Code, OpenCode Go, GitHub Copilot, Antigravity and xAI Grok, with separate accounts and direct HTTP usage collection."),
            buttons,
            settingsCaption("No browser cookies, telemetry or third-party backend. Built on CodexBar Lite, with integration references from Headroom and OpenCode Bar. Independent of all providers."),
            updateButton,
            settingsCaption(canCheckForUpdates() ? "Updates are verified by Sparkle." : "Automatic updates are not configured for this build.")
        ])
    }

    private func sync() {
        toggles["login"]?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        toggles["updates"]?.state = settings.checkForUpdates ? .on : .off
        toggles["updates"]?.isEnabled = canCheckForUpdates()
        toggles["80"]?.state = settings.notifyAt80 ? .on : .off
        toggles["90"]?.state = settings.notifyAt90 ? .on : .off
        toggles["exhausted"]?.state = settings.notifyWhenExhausted ? .on : .off
        toggles["reset"]?.state = settings.notifyWhenReset ? .on : .off
        refreshPopup.selectItem(at: [60.0, 300, 900, 1800].firstIndex(of: settings.refreshInterval) ?? 1)
        modePopup.selectItem(at: settings.displayMode == .used ? 0 : 1)
        updateButton.isEnabled = canCheckForUpdates()
        accountsView.reload()
    }

    @objc private func refreshChanged() { settings.refreshInterval = [60.0, 300, 900, 1800][max(0, refreshPopup.indexOfSelectedItem)] }
    @objc private func modeChanged() { settings.displayMode = modePopup.indexOfSelectedItem == 0 ? .used : .remaining }
    @objc private func toggleChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        switch sender.identifier?.rawValue {
        case "login":
            do { try settings.setLaunchAtLogin(enabled) } catch { NSAlert(error: error).runModal(); sync() }
        case "updates": settings.checkForUpdates = enabled
        case "80": settings.notifyAt80 = enabled
        case "90": settings.notifyAt90 = enabled
        case "exhausted": settings.notifyWhenExhausted = enabled
        case "reset": settings.notifyWhenReset = enabled
        default: break
        }
    }
    @objc private func openGitHub() { NSWorkspace.shared.open(AppBranding.repositoryURL) }
    @objc private func openIssues() { NSWorkspace.shared.open(AppBranding.issuesURL) }
    @objc private func checkForUpdates() { onCheckForUpdates() }

    private func select(_ pane: Pane) {
        tabs.selectTabViewItem(at: Pane.allCases.firstIndex(of: pane)!)
        window?.title = "OpenBar · \(pane.title)"
        window?.toolbar?.selectedItemIdentifier = pane.identifier
        window?.setContentSize(NSSize(width: 560, height: pane.height))
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Pane.allCases.map(\.identifier) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Pane.allCases.map(\.identifier) }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Pane.allCases.map(\.identifier) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = Pane(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = pane.title
        item.image = Symbols.image(pane.icon, pointSize: 16)
        item.target = self
        item.action = #selector(selectPane(_:))
        return item
    }
    @objc private func selectPane(_ sender: NSToolbarItem) {
        if let pane = Pane(rawValue: sender.itemIdentifier.rawValue) { select(pane) }
    }
}

class SettingsBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
}

func settingsCaption(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: 11)
    label.textColor = .secondaryLabelColor
    return label
}

func settingRow(_ text: String, control: NSView) -> NSStackView {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 13)
    let row = NSStackView(views: [label, flexibleSpacer(), control])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 8
    return row
}
