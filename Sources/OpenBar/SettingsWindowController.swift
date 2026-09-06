import AppKit
import ServiceManagement

final class SettingsWindowController: NSWindowController {
    private enum Pane: String, CaseIterable {
        case general
        case integrations
        case notifications
        case about

        var title: String {
            switch self {
            case .general: return "General"
            case .integrations: return "Integrations"
            case .notifications: return "Notifications"
            case .about: return "About"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .integrations: return "point.3.connected.trianglepath.dotted"
            case .notifications: return "bell"
            case .about: return "info.circle"
            }
        }

        var toolbarIdentifier: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue) }
    }

    private let settings: SettingsStore
    private let onCheckForUpdates: () -> Void
    private let onSignIn: () -> Void
    private let onCredentialsChanged: (IntegrationID) -> Void
    private let canCheckForUpdates: () -> Bool
    private let contentWidth: CGFloat = 520
    private let tabView = NSTabView()
    private var paneHeights: [Pane: CGFloat] = [:]

    private let launchAtLoginSwitch = SettingsWindowController.makeSwitch()
    private let refreshPopup = NSPopUpButton()
    private let displayUsedRadio = NSButton(radioButtonWithTitle: "Percentage used", target: nil, action: nil)
    private let displayRemainingRadio = NSButton(radioButtonWithTitle: "Percentage remaining", target: nil, action: nil)
    private let updatesSwitch = SettingsWindowController.makeSwitch()
    private var integrationSwitches: [IntegrationID: NSButton] = [:]
    private var integrationStatusLabels: [IntegrationID: NSTextField] = [:]
    private var latestStates: [IntegrationID: IntegrationState] = [:]
    private var saving = Set<IntegrationID>()
    private let openCodeTokenField = NSSecureTextField()
    private let githubTokenField = NSSecureTextField()
    private let notify80Switch = SettingsWindowController.makeSwitch()
    private let notify90Switch = SettingsWindowController.makeSwitch()
    private let notifyExhaustedSwitch = SettingsWindowController.makeSwitch()
    private let notifyResetSwitch = SettingsWindowController.makeSwitch()
    private let checkUpdatesButton = NSButton(title: "Check for Updates…", target: nil, action: nil)

    init(
        settings: SettingsStore,
        onCheckForUpdates: @escaping () -> Void,
        onSignIn: @escaping () -> Void,
        onCredentialsChanged: @escaping (IntegrationID) -> Void,
        canCheckForUpdates: @escaping () -> Bool
    ) {
        self.settings = settings
        self.onCheckForUpdates = onCheckForUpdates
        self.onSignIn = onSignIn
        self.onCredentialsChanged = onCredentialsChanged
        self.canCheckForUpdates = canCheckForUpdates

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = Pane.general.title
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)

        buildPanes()
        window.contentView = tabView
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        toolbar.selectedItemIdentifier = Pane.general.toolbarIdentifier
        window.setContentSize(NSSize(width: contentWidth, height: paneHeights.values.max() ?? 480))
        window.center()
        syncControls()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        syncControls()
        select(.integrations)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func updateStatuses(_ states: [IntegrationID: IntegrationState]) {
        latestStates = states
        reloadIntegrationStatuses()
    }

    private func reloadIntegrationStatuses() {
        for integration in IntegrationID.allCases {
            let state = latestStates[integration]
            let text = !settings.isIntegrationEnabled(integration) ? "Disabled" : state?.isRefreshing == true ? "Verifying…" : state?.message != nil ? "Needs attention" : state?.updatedAt != nil ? "Verified" : "Not checked"
            integrationStatusLabels[integration]?.stringValue = saving.contains(integration) ? "Saving…" : text
            integrationStatusLabels[integration]?.textColor = text == "Verified" ? .systemGreen : .secondaryLabelColor
            integrationStatusLabels[integration]?.toolTip = state?.message ?? integration.setupHint
        }
        openCodeTokenField.placeholderString = "OpenCode API key"
        githubTokenField.placeholderString = "Copilot token"
    }

    private func buildPanes() {
        tabView.tabViewType = .noTabsNoBorder
        let panes: [(Pane, NSView)] = [
            (.general, buildGeneralPane()),
            (.integrations, buildIntegrationsPane()),
            (.notifications, buildNotificationsPane()),
            (.about, buildAboutPane())
        ]
        for (pane, view) in panes {
            let item = NSTabViewItem(identifier: pane.rawValue)
            item.view = view
            tabView.addTabViewItem(item)
            view.layoutSubtreeIfNeeded()
            paneHeights[pane] = max(180, view.fittingSize.height)
        }
    }

    private func paneRoot() -> (NSView, NSStackView) {
        let view = SettingsBackgroundView()
        view.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20)
        ])
        return (view, stack)
    }

    private func addSection(to stack: NSStackView, title: String, icon: String, group: RoundedGroupView, caption: String) {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 6
        let header = NSStackView(views: [
            Symbols.view(icon, pointSize: 13, weight: .medium, tint: AppBranding.accentColor),
            label(title, size: 13, weight: .semibold)
        ])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        let captionLabel = NSTextField(wrappingLabelWithString: caption)
        captionLabel.font = .systemFont(ofSize: 11)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.preferredMaxLayoutWidth = contentWidth - 40
        section.addArrangedSubview(header)
        section.addArrangedSubview(group)
        group.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        section.addArrangedSubview(captionLabel)
        stack.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func controlRow(title: String, control: NSView) -> NSView {
        let titleLabel = label(title, size: 13)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [titleLabel, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return row
    }

    private func buildGeneralPane() -> NSView {
        let (view, stack) = paneRoot()
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchAtLoginChanged)
        let startup = RoundedGroupView(insets: NSEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
        startup.addRow(controlRow(title: "Launch CodexBar Lite at login", control: launchAtLoginSwitch))
        addSection(to: stack, title: "Startup", icon: "power", group: startup, caption: "Opens automatically when you log in to your Mac.")

        refreshPopup.addItems(withTitles: ["1 minute", "5 minutes", "15 minutes", "30 minutes"])
        refreshPopup.target = self
        refreshPopup.action = #selector(refreshIntervalChanged)
        displayUsedRadio.target = self
        displayUsedRadio.action = #selector(displayModeChanged(_:))
        displayRemainingRadio.target = self
        displayRemainingRadio.action = #selector(displayModeChanged(_:))
        let usage = RoundedGroupView(insets: NSEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
        usage.addRow(controlRow(title: "Refresh interval", control: refreshPopup))
        usage.addDivider()
        usage.addRow(controlRow(title: "Progress bars", control: displayUsedRadio))
        usage.addRow(controlRow(title: "", control: displayRemainingRadio))
        addSection(to: stack, title: "Usage", icon: "gauge", group: usage, caption: "Controls every enabled provider and the menu-bar summary.")

        updatesSwitch.target = self
        updatesSwitch.action = #selector(checkForUpdatesChanged)
        let updates = RoundedGroupView(insets: NSEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
        updates.addRow(controlRow(title: "Automatically check for updates", control: updatesSwitch))
        addSection(to: stack, title: "Updates", icon: "arrow.triangle.2.circlepath", group: updates, caption: "New versions are checked through Sparkle.")
        return view
    }

    private func buildIntegrationsPane() -> NSView {
        let (view, stack) = paneRoot()
        let providers = RoundedGroupView(insets: NSEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
        for (index, integration) in IntegrationID.allCases.enumerated() {
            if index > 0 { providers.addDivider() }
            let toggle = SettingsWindowController.makeSwitch()
            toggle.identifier = NSUserInterfaceItemIdentifier(integration.rawValue)
            toggle.target = self
            toggle.action = #selector(integrationChanged(_:))
            integrationSwitches[integration] = toggle
            let status = label("", size: 10.5)
            status.setContentHuggingPriority(.required, for: .horizontal)
            integrationStatusLabels[integration] = status
            let row = NSStackView(views: [label(integration.name, size: 13), flexibleSpacer(), status, toggle])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 9
            row.heightAnchor.constraint(equalToConstant: 30).isActive = true
            providers.addRow(row)
        }
        addSection(
            to: stack,
            title: "Providers",
            icon: "gauge.with.dots.needle.67percent",
            group: providers,
            caption: "Only enabled providers are queried and shown. Quota collection uses provider HTTP APIs; local stores are used only to discover credentials."
        )

        for field in [openCodeTokenField, githubTokenField] {
            field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 170).isActive = true
        }
        let openCodeSave = smallButton("Save & verify", #selector(saveOpenCodeToken))
        let openCodeClear = smallButton("Clear", #selector(clearOpenCodeToken))
        let githubSave = smallButton("Save & verify", #selector(saveGitHubToken))
        let githubClear = smallButton("Clear", #selector(clearGitHubToken))
        let tokens = RoundedGroupView(insets: NSEdgeInsets(top: 5, left: 16, bottom: 5, right: 16))
        tokens.addRow(tokenRow(title: "OpenCode Go", field: openCodeTokenField, save: openCodeSave, clear: openCodeClear))
        tokens.addDivider()
        tokens.addRow(tokenRow(title: "GitHub", field: githubTokenField, save: githubSave, clear: githubClear))
        addSection(
            to: stack,
            title: "Tokens",
            icon: "key.horizontal",
            group: tokens,
            caption: "Saved in Keychain, then checked against the provider API. GitHub's internal quota endpoint requires a compatible Copilot token; not every personal access token works. Errors appear on the provider row. Clear removes the saved token and disables polling."
        )

        let signIn = NSButton(title: "Sign In via Terminal…", target: self, action: #selector(signInClicked))
        signIn.bezelStyle = .rounded
        let codex = RoundedGroupView(insets: NSEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
        let row = NSStackView(views: [label("Codex CLI session", size: 13), flexibleSpacer(), signIn])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.heightAnchor.constraint(equalToConstant: 30).isActive = true
        codex.addRow(row)
        addSection(to: stack, title: "Codex sign-in", icon: "terminal", group: codex, caption: "Runs codex login in Terminal, then detects the updated session automatically.")
        return view
    }

    private func tokenRow(title: String, field: NSSecureTextField, save: NSButton, clear: NSButton) -> NSView {
        let row = NSStackView(views: [label(title, size: 12), flexibleSpacer(), field, save, clear])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        row.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return row
    }

    private func buildNotificationsPane() -> NSView {
        let (view, stack) = paneRoot()
        let group = RoundedGroupView(insets: NSEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
        let rows: [(String, NSButton)] = [
            ("Notify at 80% usage", notify80Switch),
            ("Notify at 90% usage", notify90Switch),
            ("Notify when exhausted", notifyExhaustedSwitch),
            ("Notify when a quota resets", notifyResetSwitch)
        ]
        for (index, item) in rows.enumerated() {
            if index > 0 { group.addDivider() }
            item.1.target = self
            item.1.action = #selector(notificationPreferenceChanged)
            group.addRow(controlRow(title: item.0, control: item.1))
        }
        addSection(to: stack, title: "Alerts", icon: "bell", group: group, caption: "Applies independently to every quota window returned by enabled providers.")
        return view
    }

    private func buildAboutPane() -> NSView {
        let (view, stack) = paneRoot()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let name = label("CodexBar Lite", size: 15, weight: .semibold)
        let versionLabel = label("Version \(version)", size: 11)
        versionLabel.textColor = .secondaryLabelColor
        let title = NSStackView(views: [name, versionLabel])
        title.orientation = .vertical
        title.alignment = .leading
        title.spacing = 2
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        if let logo = AppBranding.logoImage {
            let logoView = NSImageView(image: logo)
            logoView.widthAnchor.constraint(equalToConstant: 48).isActive = true
            logoView.heightAnchor.constraint(equalToConstant: 48).isActive = true
            row.addArrangedSubview(logoView)
        }
        row.addArrangedSubview(title)
        let github = NSButton(title: "View on GitHub", target: self, action: #selector(openGitHub))
        github.bezelStyle = .rounded
        checkUpdatesButton.bezelStyle = .rounded
        checkUpdatesButton.target = self
        checkUpdatesButton.action = #selector(checkForUpdates)
        let buttons = NSStackView(views: [github, checkUpdatesButton, flexibleSpacer()])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let group = RoundedGroupView(insets: NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))
        group.addRow(row)
        group.addDivider()
        group.addRow(buttons)
        addSection(
            to: stack,
            title: "About",
            icon: "info.circle",
            group: group,
            caption: "Local-first quota tracking over first-party HTTP APIs. No browser cookies, telemetry, or third-party backend. Independent utility; not affiliated with any provider."
        )
        return view
    }

    private func syncControls() {
        let intervals: [TimeInterval] = [60, 300, 900, 1800]
        refreshPopup.selectItem(at: intervals.enumerated().min(by: { abs($0.element - settings.refreshInterval) < abs($1.element - settings.refreshInterval) })?.offset ?? 1)
        launchAtLoginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        displayUsedRadio.state = settings.displayMode == .used ? .on : .off
        displayRemainingRadio.state = settings.displayMode == .remaining ? .on : .off
        updatesSwitch.state = settings.checkForUpdates ? .on : .off
        notify80Switch.state = settings.notifyAt80 ? .on : .off
        notify90Switch.state = settings.notifyAt90 ? .on : .off
        notifyExhaustedSwitch.state = settings.notifyWhenExhausted ? .on : .off
        notifyResetSwitch.state = settings.notifyWhenReset ? .on : .off
        checkUpdatesButton.isEnabled = canCheckForUpdates()
        for integration in IntegrationID.allCases {
            integrationSwitches[integration]?.state = settings.isIntegrationEnabled(integration) ? .on : .off
        }
        reloadIntegrationStatuses()
    }

    @objc private func refreshIntervalChanged() {
        let intervals: [TimeInterval] = [60, 300, 900, 1800]
        settings.refreshInterval = intervals[max(0, refreshPopup.indexOfSelectedItem)]
    }

    @objc private func launchAtLoginChanged() {
        do {
            try settings.setLaunchAtLogin(launchAtLoginSwitch.state == .on)
        } catch {
            syncControls()
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t update Launch at Login"
            alert.runModal()
        }
    }

    @objc private func displayModeChanged(_ sender: NSButton) {
        settings.displayMode = sender == displayUsedRadio ? .used : .remaining
        syncControls()
    }

    @objc private func checkForUpdatesChanged() { settings.checkForUpdates = updatesSwitch.state == .on }

    @objc private func notificationPreferenceChanged() {
        settings.notifyAt80 = notify80Switch.state == .on
        settings.notifyAt90 = notify90Switch.state == .on
        settings.notifyWhenExhausted = notifyExhaustedSwitch.state == .on
        settings.notifyWhenReset = notifyResetSwitch.state == .on
    }

    @objc private func integrationChanged(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let integration = IntegrationID(rawValue: raw) else { return }
        settings.setIntegration(integration, enabled: sender.state == .on)
    }

    @objc private func saveOpenCodeToken() { saveToken(from: openCodeTokenField, for: .openCodeGo) }
    @objc private func saveGitHubToken() { saveToken(from: githubTokenField, for: .githubCopilot) }
    @objc private func clearOpenCodeToken() { clearToken(.openCodeGo, field: openCodeTokenField) }
    @objc private func clearGitHubToken() { clearToken(.githubCopilot, field: githubTokenField) }

    private func saveToken(from field: NSSecureTextField, for integration: IntegrationID) {
        let token = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, saving.insert(integration).inserted else { return }
        field.isEnabled = false
        reloadIntegrationStatuses()
        Task { @MainActor in
            let result = await Task.detached { () -> Result<Void, Error> in
                Result { try CredentialStore.saveConfiguredToken(token, for: integration) }
            }.value
            saving.remove(integration)
            field.isEnabled = true
            switch result {
            case .success:
                field.stringValue = ""
                onCredentialsChanged(integration)
                settings.setIntegration(integration, enabled: true)
                syncControls()
            case .failure(let error):
                let alert = NSAlert(error: error)
                alert.messageText = "Couldn’t save \(integration.name) token"
                alert.runModal()
            }
        }
    }

    private func clearToken(_ integration: IntegrationID, field: NSSecureTextField) {
        guard saving.insert(integration).inserted else { return }
        Task { @MainActor in
            let result = await Task.detached { Result { try CredentialStore.clearConfiguredToken(for: integration) } }.value
            saving.remove(integration)
            switch result {
            case .success:
                settings.setIntegration(integration, enabled: false)
                onCredentialsChanged(integration)
                field.stringValue = ""
                syncControls()
            case .failure(let error): NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func signInClicked() { onSignIn() }
    @objc private func openGitHub() { NSWorkspace.shared.open(URL(string: "https://github.com/wei-b0/codexbar-lite")!) }
    @objc private func checkForUpdates() { onCheckForUpdates() }

    private func smallButton(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.controlSize = .small
        return button
    }

    private func label(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: size, weight: weight)
        return label
    }

    private static func makeSwitch() -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        button.setButtonType(.switch)
        return button
    }

    private func select(_ pane: Pane) {
        if let index = Pane.allCases.firstIndex(of: pane) { tabView.selectTabViewItem(at: index) }
        window?.title = pane.title
        window?.toolbar?.selectedItemIdentifier = pane.toolbarIdentifier
    }
}

private final class SettingsBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

extension SettingsWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Pane.allCases.map(\.toolbarIdentifier) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Pane.allCases.map(\.toolbarIdentifier) }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Pane.allCases.map(\.toolbarIdentifier) }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let pane = Pane(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = pane.title
        item.image = Symbols.image(pane.icon, pointSize: 15, weight: .medium)
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }

    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        guard let pane = Pane(rawValue: sender.itemIdentifier.rawValue) else { return }
        select(pane)
    }
}
