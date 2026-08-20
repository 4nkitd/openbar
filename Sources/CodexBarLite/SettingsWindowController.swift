import AppKit
import ServiceManagement

struct AuthStatus {
    let signedIn: Bool
    let accountID: String?
}

/// Native tabbed settings window: NSToolbar tab bar over a tabless NSTabView,
/// grouped rounded sections with concise captions. Presentation only — every
/// control reads/writes SettingsStore exactly as before.
final class SettingsWindowController: NSWindowController {
    private enum Pane: String, CaseIterable {
        case general
        case authentication
        case notifications
        case about

        var title: String {
            switch self {
            case .general: return "General"
            case .authentication: return "Authentication"
            case .notifications: return "Notifications"
            case .about: return "About"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .authentication: return "key"
            case .notifications: return "bell"
            case .about: return "info.circle"
            }
        }

        var toolbarIdentifier: NSToolbarItem.Identifier {
            NSToolbarItem.Identifier(rawValue)
        }
    }

    private let settings: SettingsStore
    private let onCheckForUpdates: () -> Void
    private let onSignIn: () -> Void
    private let authStatusProvider: () -> AuthStatus
    private let canCheckForUpdates: () -> Bool

    private let contentWidth: CGFloat = 440
    private let tabView = NSTabView()
    private var paneHeights: [Pane: CGFloat] = [:]
    private var currentPane: Pane = .general

    // General
    private let launchAtLoginSwitch = SettingsWindowController.makeSwitch()
    private let refreshPopup = NSPopUpButton()
    private let displayUsedRadio = NSButton(radioButtonWithTitle: "Percentage used", target: nil, action: nil)
    private let displayRemainingRadio = NSButton(radioButtonWithTitle: "Percentage remaining", target: nil, action: nil)
    private let updatesSwitch = SettingsWindowController.makeSwitch()

    // Authentication
    private let authStatusIcon = NSImageView()
    private let authStatusLabel = NSTextField(labelWithString: "")
    private let authAccountLabel = NSTextField(labelWithString: "")
    private let signInTerminalButton = NSButton(title: "Sign In via Terminal…", target: nil, action: nil)

    // Notifications
    private let notify80Switch = SettingsWindowController.makeSwitch()
    private let notify90Switch = SettingsWindowController.makeSwitch()
    private let notifyExhaustedSwitch = SettingsWindowController.makeSwitch()
    private let notifyResetSwitch = SettingsWindowController.makeSwitch()

    // About
    private let checkUpdatesButton = NSButton(title: "Check for Updates…", target: nil, action: nil)

    init(
        settings: SettingsStore,
        onCheckForUpdates: @escaping () -> Void,
        onSignIn: @escaping () -> Void,
        authStatusProvider: @escaping () -> AuthStatus,
        canCheckForUpdates: @escaping () -> Bool
    ) {
        self.settings = settings
        self.onCheckForUpdates = onCheckForUpdates
        self.onSignIn = onSignIn
        self.authStatusProvider = authStatusProvider
        self.canCheckForUpdates = canCheckForUpdates

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: 420),
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

        let contentHeight = paneHeights.values.max() ?? 420
        window.setContentSize(NSSize(width: contentWidth, height: contentHeight))
        window.center()

        syncControls()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        syncControls()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Re-reads the Codex session state (called after login completes or usage loads).
    func reloadAuth() {
        let status = authStatusProvider()
        authStatusIcon.image = Symbols.image(
            status.signedIn ? "checkmark.circle.fill" : "xmark.circle",
            pointSize: 14,
            weight: .medium
        )
        authStatusIcon.contentTintColor = status.signedIn ? .systemGreen : .secondaryLabelColor
        authStatusLabel.stringValue = status.signedIn ? "Signed in" : "Not signed in"
        if let accountID = status.accountID, !accountID.isEmpty {
            authAccountLabel.stringValue = String(accountID.prefix(8)) + "…"
            authAccountLabel.toolTip = accountID
        } else {
            authAccountLabel.stringValue = "—"
            authAccountLabel.toolTip = nil
        }
    }

    // MARK: - Panes

    private func buildPanes() {
        tabView.tabViewType = .noTabsNoBorder
        tabView.translatesAutoresizingMaskIntoConstraints = false

        let panes: [(Pane, NSView)] = [
            (.general, buildGeneralPane()),
            (.authentication, buildAuthenticationPane()),
            (.notifications, buildNotificationsPane()),
            (.about, buildAboutPane())
        ]

        for (pane, view) in panes {
            let item = NSTabViewItem(identifier: pane.rawValue)
            item.view = view
            tabView.addTabViewItem(item)
            view.layoutSubtreeIfNeeded()
            paneHeights[pane] = max(140, view.fittingSize.height)
        }
    }

    private func paneRoot() -> (NSView, NSStackView) {
        let view = NSView()
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

        let headerIcon = Symbols.view(icon, pointSize: 13, weight: .medium, tint: AppBranding.accentColor)
        let headerLabel = NSTextField(labelWithString: title)
        headerLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let header = NSStackView(views: [headerIcon, headerLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6

        let captionLabel = NSTextField(labelWithString: caption)
        captionLabel.font = .systemFont(ofSize: 11)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.maximumNumberOfLines = 0
        captionLabel.lineBreakMode = .byWordWrapping
        captionLabel.preferredMaxLayoutWidth = contentWidth - 40

        section.addArrangedSubview(header)
        section.addArrangedSubview(group)
        group.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        section.addArrangedSubview(captionLabel)

        stack.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func controlRow(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return row
    }

    private func valueRow(title: String, value: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .systemFont(ofSize: 13)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [label, valueLabel])
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
        let startupGroup = RoundedGroupView(insets: NSEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
        startupGroup.addRow(controlRow(title: "Launch CodexBar Lite at login", control: launchAtLoginSwitch))
        addSection(
            to: stack, title: "Startup", icon: "power", group: startupGroup,
            caption: "CodexBar Lite opens automatically when you log in to your Mac."
        )

        refreshPopup.addItems(withTitles: ["1 minute", "5 minutes", "15 minutes", "30 minutes"])
        refreshPopup.target = self
        refreshPopup.action = #selector(refreshIntervalChanged)

        displayUsedRadio.target = self
        displayUsedRadio.action = #selector(displayModeChanged(_:))
        displayRemainingRadio.target = self
        displayRemainingRadio.action = #selector(displayModeChanged(_:))

        let usageGroup = RoundedGroupView(insets: NSEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
        usageGroup.addRow(controlRow(title: "Refresh interval", control: refreshPopup))
        usageGroup.addDivider()
        let usedRow = NSStackView(views: [displayUsedRadio])
        usedRow.heightAnchor.constraint(equalToConstant: 26).isActive = true
        usageGroup.addRow(usedRow)
        let remainingRow = NSStackView(views: [displayRemainingRadio])
        remainingRow.heightAnchor.constraint(equalToConstant: 26).isActive = true
        usageGroup.addRow(remainingRow)
        addSection(
            to: stack, title: "Usage", icon: "gauge", group: usageGroup,
            caption: "How often usage is fetched, and what the menu bar and popover show."
        )

        updatesSwitch.target = self
        updatesSwitch.action = #selector(checkForUpdatesChanged)
        let updatesGroup = RoundedGroupView(insets: NSEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
        updatesGroup.addRow(controlRow(title: "Automatically check for updates", control: updatesSwitch))
        addSection(
            to: stack, title: "Updates", icon: "arrow.triangle.2.circlepath", group: updatesGroup,
            caption: "New versions are downloaded in the background via Sparkle."
        )

        return view
    }

    private func buildAuthenticationPane() -> NSView {
        let (view, stack) = paneRoot()

        authStatusIcon.imageScaling = .scaleProportionallyUpOrDown
        authStatusIcon.setContentHuggingPriority(.required, for: .horizontal)
        authStatusLabel.font = .systemFont(ofSize: 13)
        authStatusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        authAccountLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        authAccountLabel.textColor = .secondaryLabelColor
        authAccountLabel.setContentHuggingPriority(.required, for: .horizontal)

        let statusRow = NSStackView(views: [authStatusIcon, authStatusLabel, authAccountLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8
        statusRow.heightAnchor.constraint(equalToConstant: 30).isActive = true

        signInTerminalButton.bezelStyle = .rounded
        signInTerminalButton.target = self
        signInTerminalButton.action = #selector(signInClicked)
        let signInRow = NSStackView(views: [flexibleSpacer(), signInTerminalButton])
        signInRow.orientation = .horizontal
        signInRow.alignment = .centerY
        signInRow.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let group = RoundedGroupView(insets: NSEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
        group.addRow(statusRow)
        group.addDivider()
        group.addRow(valueRow(title: "Session file", value: "~/.codex/auth.json"))
        group.addDivider()
        group.addRow(signInRow)
        addSection(
            to: stack, title: "Codex Session", icon: "key", group: group,
            caption: "CodexBar Lite reads only ~/.codex/auth.json — no Keychain, no cookies, no browser access. Signing in runs codex login in Terminal."
        )

        return view
    }

    private func buildNotificationsPane() -> NSView {
        let (view, stack) = paneRoot()

        let group = RoundedGroupView(insets: NSEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
        let rows: [(String, NSButton)] = [
            ("Notify at 80% usage", notify80Switch),
            ("Notify at 90% usage", notify90Switch),
            ("Notify when exhausted", notifyExhaustedSwitch),
            ("Notify when credits reset", notifyResetSwitch)
        ]
        for (index, row) in rows.enumerated() {
            if index > 0 { group.addDivider() }
            row.1.target = self
            row.1.action = #selector(notificationPreferenceChanged)
            group.addRow(controlRow(title: row.0, control: row.1))
        }
        addSection(
            to: stack, title: "Alerts", icon: "bell", group: group,
            caption: "CodexBar Lite sends a macOS notification when usage crosses a threshold."
        )

        return view
    }

    private func buildAboutPane() -> NSView {
        let (view, stack) = paneRoot()

        let nameLabel = NSTextField(labelWithString: "CodexBar Lite")
        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let versionText: String
        if let build, !build.isEmpty {
            versionText = "Version \(version) (\(build))"
        } else {
            versionText = "Version \(version)"
        }
        let versionLabel = NSTextField(labelWithString: versionText)
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor

        let titleStack = NSStackView(views: [nameLabel, versionLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        let iconRow = NSStackView()
        iconRow.orientation = .horizontal
        iconRow.alignment = .centerY
        iconRow.spacing = 12
        if let logo = AppBranding.logoImage {
            let logoView = NSImageView(image: logo)
            logoView.imageScaling = .scaleProportionallyUpOrDown
            logoView.widthAnchor.constraint(equalToConstant: 48).isActive = true
            logoView.heightAnchor.constraint(equalToConstant: 48).isActive = true
            iconRow.addArrangedSubview(logoView)
        }
        iconRow.addArrangedSubview(titleStack)
        iconRow.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let githubButton = NSButton(title: "View on GitHub", target: self, action: #selector(openGitHub))
        githubButton.bezelStyle = .rounded
        checkUpdatesButton.bezelStyle = .rounded
        checkUpdatesButton.target = self
        checkUpdatesButton.action = #selector(checkForUpdates)
        let buttonRow = NSStackView(views: [githubButton, checkUpdatesButton, flexibleSpacer()])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let group = RoundedGroupView(insets: NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))
        group.addRow(iconRow)
        group.addDivider()
        group.addRow(buttonRow)
        addSection(
            to: stack, title: "About", icon: "info.circle", group: group,
            caption: "Native Codex usage from your existing CLI session. No browser cookies, Keychain access, telemetry, or analytics. Independent utility; not affiliated with OpenAI."
        )

        return view
    }

    // MARK: - Syncing

    private func syncControls() {
        let intervals: [TimeInterval] = [60, 300, 900, 1800]
        let selectedInterval = intervals.enumerated().min(by: {
            abs($0.element - settings.refreshInterval) < abs($1.element - settings.refreshInterval)
        })?.offset ?? 1
        refreshPopup.selectItem(at: selectedInterval)
        launchAtLoginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        displayUsedRadio.state = settings.displayMode == .used ? .on : .off
        displayRemainingRadio.state = settings.displayMode == .used ? .off : .on
        updatesSwitch.state = settings.checkForUpdates ? .on : .off
        notify80Switch.state = settings.notifyAt80 ? .on : .off
        notify90Switch.state = settings.notifyAt90 ? .on : .off
        notifyExhaustedSwitch.state = settings.notifyWhenExhausted ? .on : .off
        notifyResetSwitch.state = settings.notifyWhenReset ? .on : .off
        checkUpdatesButton.isEnabled = canCheckForUpdates()
        reloadAuth()
    }

    // MARK: - Actions

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
        displayUsedRadio.state = settings.displayMode == .used ? .on : .off
        displayRemainingRadio.state = settings.displayMode == .used ? .off : .on
    }

    @objc private func checkForUpdatesChanged() {
        settings.checkForUpdates = updatesSwitch.state == .on
    }

    @objc private func notificationPreferenceChanged() {
        settings.notifyAt80 = notify80Switch.state == .on
        settings.notifyAt90 = notify90Switch.state == .on
        settings.notifyWhenExhausted = notifyExhaustedSwitch.state == .on
        settings.notifyWhenReset = notifyResetSwitch.state == .on
    }

    @objc private func signInClicked() {
        onSignIn()
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/wei-b0/codexbar-lite")!)
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates()
    }

    private static func makeSwitch() -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        button.setButtonType(.switch)
        return button
    }

    // MARK: - Pane selection

    private func select(_ pane: Pane) {
        currentPane = pane
        if let index = Pane.allCases.firstIndex(of: pane) {
            tabView.selectTabViewItem(at: index)
        }
        window?.title = pane.title
        window?.toolbar?.selectedItemIdentifier = pane.toolbarIdentifier
    }
}

extension SettingsWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Pane.allCases.map { $0.toolbarIdentifier }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Pane.allCases.map { $0.toolbarIdentifier }
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Pane.allCases.map { $0.toolbarIdentifier }
    }

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
