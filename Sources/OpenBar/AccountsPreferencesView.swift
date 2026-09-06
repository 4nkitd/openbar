import AppKit

final class AccountsPreferencesView: SettingsBackgroundView {
    private let settings: SettingsStore
    private let onSignIn: () -> Void
    private let onCredentialsChanged: (String) -> Void
    private let onOAuthChanged: () -> Void
    private let provider = NSPopUpButton()
    private let integrationToggle = NSButton(checkboxWithTitle: "Show this integration", target: nil, action: nil)
    private let list = NSStackView()
    private let scroll = NSScrollView()
    private let document = AccountDocumentView()
    private let nameField = NSTextField()
    private let tokenField = NSSecureTextField()
    private let pathField = NSTextField()
    private let browseButton = NSButton(title: "Choose…", target: nil, action: nil)
    private let saveButton = NSButton(title: "Add account", target: nil, action: nil)
    private let currentButton = NSButton(title: "Use current login", target: nil, action: nil)
    private let oauthButton = NSButton(title: "Configure OAuth…", target: nil, action: nil)
    private let signInButton = NSButton(title: "Sign in to Codex…", target: nil, action: nil)
    private let feedback = settingsCaption("")
    private let sourceHint = settingsCaption("")
    private let fileRow = NSStackView()
    private var states: [String: IntegrationState] = [:]
    private var statusLabels: [String: NSTextField] = [:]
    private var editing: IntegrationAccount?
    private var busy = false
    private var selected: IntegrationID { IntegrationID.allCases[max(0, provider.indexOfSelectedItem)] }

    init(settings: SettingsStore, onSignIn: @escaping () -> Void, onCredentialsChanged: @escaping (String) -> Void, onOAuthChanged: @escaping () -> Void) {
        self.settings = settings
        self.onSignIn = onSignIn
        self.onCredentialsChanged = onCredentialsChanged
        self.onOAuthChanged = onOAuthChanged
        super.init(frame: .zero)
        provider.addItems(withTitles: IntegrationID.allCases.map(\.name))
        provider.target = self
        provider.action = #selector(providerChanged)
        integrationToggle.target = self
        integrationToggle.action = #selector(integrationChanged)
        nameField.placeholderString = "Account name, e.g. Work or Personal"
        tokenField.placeholderString = "Token stored securely in Keychain"
        pathField.placeholderString = "Select an existing OAuth credential JSON file"
        nameField.font = .systemFont(ofSize: 12)
        tokenField.font = .systemFont(ofSize: 12)
        pathField.font = .systemFont(ofSize: 12)
        pathField.lineBreakMode = .byTruncatingMiddle
        for (button, action) in [(browseButton, #selector(browse)), (saveButton, #selector(save)),
                                 (currentButton, #selector(useCurrent)), (oauthButton, #selector(configureOAuth)), (signInButton, #selector(signIn))] {
            button.bezelStyle = .rounded
            button.target = self
            button.action = action
        }
        fileRow.setViews([pathField, browseButton], in: .leading)
        fileRow.orientation = .horizontal
        fileRow.spacing = 8
        pathField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let cancel = NSButton(title: "Cancel edit", target: self, action: #selector(cancelEdit))
        cancel.bezelStyle = .rounded
        let actions = NSStackView(views: [saveButton, cancel, flexibleSpacer(), currentButton])
        actions.spacing = 8
        let setup = NSStackView(views: [oauthButton, signInButton, flexibleSpacer()])
        setup.spacing = 8
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.documentView = document
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 8
        list.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(list)
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: document.topAnchor), list.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            list.widthAnchor.constraint(equalToConstant: 492), scroll.heightAnchor.constraint(equalToConstant: 142)
        ])
        let stack = NSStackView(views: [settingRow("Integration", control: provider), integrationToggle, scroll,
                                      nameField, tokenField, fileRow, actions, sourceHint, setup, feedback])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 20)
        ])
        for item in stack.arrangedSubviews { item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        reload()
    }

    required init?(coder: NSCoder) { nil }

    func updateStatuses(_ states: [String: IntegrationState]) {
        self.states = states
        for account in settings.accounts {
            let state = states[account.id]
            let text = !account.isEnabled || !settings.isIntegrationEnabled(account.integration) ? "Disabled" : state?.isRefreshing == true ? "Verifying…" : state?.message != nil ? "Needs attention" : state?.updatedAt != nil ? "Verified" : "Not checked"
            statusLabels[account.id]?.stringValue = text
            statusLabels[account.id]?.textColor = text == "Verified" ? .systemGreen : .secondaryLabelColor
            statusLabels[account.id]?.toolTip = state?.message ?? (account.source == .automatic ? "Uses the current local sign-in" : account.credentialPath)
        }
    }

    func reload() {
        for child in list.arrangedSubviews { list.removeArrangedSubview(child); child.removeFromSuperview() }
        statusLabels.removeAll()
        integrationToggle.state = settings.isIntegrationEnabled(selected) ? .on : .off
        let accounts = settings.accounts.filter { $0.integration == selected }
        for account in accounts {
            let toggle = NSButton(checkboxWithTitle: account.label, target: self, action: #selector(accountChanged(_:)))
            toggle.identifier = .init(account.id)
            toggle.state = account.isEnabled ? .on : .off
            toggle.lineBreakMode = .byTruncatingTail
            let status = settingsCaption("")
            status.setContentCompressionResistancePriority(.required, for: .horizontal)
            statusLabels[account.id] = status
            let edit = NSButton(title: "Edit", target: self, action: #selector(editAccount(_:)))
            let remove = NSButton(title: "Remove", target: self, action: #selector(removeAccount(_:)))
            for button in [edit, remove] { button.identifier = .init(account.id); button.controlSize = .small; button.bezelStyle = .rounded }
            let row = NSStackView(views: [toggle, flexibleSpacer(), status, edit, remove])
            row.orientation = .horizontal
            row.spacing = 6
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        if accounts.isEmpty { list.addArrangedSubview(settingsCaption("No accounts yet. Add one below.")) }
        document.setFrameSize(NSSize(width: 512, height: max(142, list.fittingSize.height)))
        tokenField.isHidden = !selected.acceptsAPIToken
        fileRow.isHidden = selected.acceptsAPIToken
        currentButton.isEnabled = !accounts.contains { $0.source == .automatic }
        oauthButton.isHidden = selected != .antigravity
        signInButton.isHidden = selected != .codex
        sourceHint.stringValue = selected.acceptsAPIToken
            ? "Each account has its own token and quota. Edit with a blank token to keep the existing one. GitHub requires a compatible Copilot token."
            : "Select a credential file from an existing sign-in for each account. OpenBar does not sign in or switch accounts in your provider app."
        updateStatuses(states)
    }

    @objc private func providerChanged() { guard !busy else { return }; cancelEdit(); reload() }
    @objc private func integrationChanged() { settings.setIntegration(selected, enabled: integrationToggle.state == .on); reload() }
    @objc private func signIn() { onSignIn() }
    @objc private func cancelEdit() { guard !busy else { return }; editing = nil; nameField.stringValue = ""; tokenField.stringValue = ""; pathField.stringValue = ""; saveButton.title = "Add account"; feedback.stringValue = "" }

    @objc private func browse() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { pathField.stringValue = url.path }
    }

    @objc private func editAccount(_ sender: NSButton) {
        guard !busy, let account = settings.accounts.first(where: { $0.id == sender.identifier?.rawValue }) else { return }
        editing = account
        nameField.stringValue = account.label
        pathField.stringValue = account.credentialPath ?? ""
        tokenField.stringValue = ""
        saveButton.title = "Save changes"
    }

    @objc private func accountChanged(_ sender: NSButton) {
        guard !busy else { reload(); return }
        var accounts = settings.accounts
        guard let index = accounts.firstIndex(where: { $0.id == sender.identifier?.rawValue }) else { return }
        accounts[index].isEnabled = sender.state == .on
        settings.accounts = accounts
        reload()
    }

    @objc private func useCurrent() {
        guard !busy else { return }
        var accounts = settings.accounts
        guard !accounts.contains(where: { $0.integration == selected && $0.source == .automatic }) else { return }
        if let index = accounts.firstIndex(where: { $0.id == IntegrationAccount.current(selected).id }) {
            accounts[index].source = .automatic
            accounts[index].credentialPath = nil
        } else {
            accounts.append(.current(selected))
        }
        settings.accounts = accounts
        settings.setIntegration(selected, enabled: true)
        reload()
    }

    @objc private func save() {
        guard !busy else { return }
        let label = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { feedback.stringValue = "Enter an account name."; return }
        guard !settings.accounts.contains(where: { $0.integration == selected && $0.id != editing?.id && $0.label.localizedCaseInsensitiveCompare(label) == .orderedSame }) else { feedback.stringValue = "Use a distinct name for this account."; return }
        if selected.acceptsAPIToken && token.isEmpty && editing == nil { feedback.stringValue = "Enter a token for this account."; return }
        let usesCurrent = editing?.id == IntegrationAccount.current(selected).id
        if !selected.acceptsAPIToken && path.isEmpty && editing?.source != .automatic && !usesCurrent { feedback.stringValue = "Choose this account's credential file."; return }
        var account = editing ?? IntegrationAccount(id: UUID().uuidString, integration: selected, label: label, source: selected.acceptsAPIToken ? .token : .file, credentialPath: nil, isEnabled: true)
        account.label = label
        if !selected.acceptsAPIToken && !path.isEmpty { account.source = .file; account.credentialPath = path }
        if !selected.acceptsAPIToken && path.isEmpty && usesCurrent { account.source = .automatic; account.credentialPath = nil }
        busy = true
        provider.isEnabled = false
        saveButton.isEnabled = false
        feedback.stringValue = "Saving…"
        Task { @MainActor in
            let result = await Task.detached { Result { if !token.isEmpty { try CredentialStore.saveConfiguredToken(token, for: account) } } }.value
            busy = false
            provider.isEnabled = true
            saveButton.isEnabled = true
            switch result {
            case .success:
                var accounts = settings.accounts
                if let index = accounts.firstIndex(where: { $0.id == account.id }) { accounts[index] = account } else { accounts.append(account) }
                settings.accounts = accounts
                onCredentialsChanged(account.id)
                settings.setIntegration(account.integration, enabled: true)
                cancelEdit()
                feedback.stringValue = "Saved. Checking this account's quota…"
                reload()
            case .failure(let error): feedback.stringValue = "Could not save to Keychain: \(error.localizedDescription)"
            }
        }
    }

    @objc private func removeAccount(_ sender: NSButton) {
        guard !busy, let account = settings.accounts.first(where: { $0.id == sender.identifier?.rawValue }) else { return }
        let alert = NSAlert()
        alert.messageText = "Remove \(account.label) from OpenBar?"
        alert.informativeText = "This removes its configuration and OpenBar's saved token. Existing sign-in files are not deleted."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        busy = true
        let previous = settings.accounts
        settings.accounts = previous.filter { $0.id != account.id }
        Task { @MainActor in
            let result = await Task.detached { Result { try CredentialStore.clearConfiguredToken(for: account) } }.value
            busy = false
            switch result {
            case .success: cancelEdit(); reload()
            case .failure(let error): settings.accounts = previous; reload(); feedback.stringValue = "Could not remove saved token: \(error.localizedDescription)"
            }
        }
    }

    @objc private func configureOAuth() {
        guard !busy else { return }
        let alert = NSAlert()
        alert.messageText = "Google OAuth client"
        alert.informativeText = "Stored locally in Keychain, never bundled or committed. Use the client belonging to the existing sign-in."
        let kind = NSPopUpButton()
        kind.addItems(withTitles: ["Antigravity", "Gemini"])
        let id = NSTextField()
        id.placeholderString = "OAuth client ID"
        let secret = NSSecureTextField()
        secret.placeholderString = "OAuth client secret"
        let accessory = NSStackView(views: [kind, id, secret])
        accessory.orientation = .vertical
        accessory.spacing = 8
        accessory.frame = NSRect(x: 0, y: 0, width: 340, height: 92)
        for field in [kind, id, secret] as [NSView] { field.widthAnchor.constraint(equalToConstant: 340).isActive = true }
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Save locally")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let client = GoogleOAuthClient(clientID: id.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), clientSecret: secret.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        let key = kind.indexOfSelectedItem == 0 ? "antigravity" : "gemini"
        secret.stringValue = ""
        Task { @MainActor in
            let result = await Task.detached { Result { try CredentialStore.saveGoogleOAuthClient(client, kind: key) } }.value
            switch result {
            case .success: feedback.stringValue = "OAuth client saved locally. Refreshing accounts…"; onOAuthChanged()
            case .failure(let error): feedback.stringValue = error.localizedDescription
            }
        }
    }
}

private final class AccountDocumentView: NSView {
    override var isFlipped: Bool { true }
}
