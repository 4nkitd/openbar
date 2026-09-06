import AppKit

final class UsagePopoverViewController: NSViewController {
    var onRefresh: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onUseResetCredit: ((String) -> Void)?
    private let width: CGFloat = 376
    private let scroll = NSScrollView()
    private let document = FlippedQuotaView()
    private let cards = NSStackView()
    private let subtitle = quotaLabel("Only your enabled integrations", size: 11, secondary: true)
    private let footerLabel = quotaLabel("", size: 11, secondary: true)
    private let refreshButton = NSButton()
    private var groups: [IntegrationID: IntegrationGroupView] = [:]
    private var order: [IntegrationID] = []
    private var emptyView: NSView?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 200))
        let background = NSVisualEffectView(frame: view.bounds)
        background.autoresizingMask = [.width, .height]
        background.material = .popover
        background.blendingMode = .withinWindow
        background.state = .active
        view.addSubview(background)
        let title = quotaLabel(AppBranding.name, size: 16, weight: .semibold)
        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 3
        refreshButton.image = Symbols.image("arrow.clockwise", pointSize: 14)
        refreshButton.isBordered = false
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)
        refreshButton.toolTip = "Refresh eligible providers (⌘R). Retry delays still apply."
        refreshButton.setAccessibilityLabel("Refresh usage")
        let header = NSStackView(views: [heading, flexibleSpacer(), refreshButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        view.addSubview(scroll)
        cards.orientation = .vertical
        cards.alignment = .leading
        cards.spacing = 0
        cards.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(cards)

        let settings = NSButton(title: "Integrations…", target: self, action: #selector(settingsClicked))
        settings.isBordered = false
        settings.font = .systemFont(ofSize: 11, weight: .medium)
        settings.setAccessibilityLabel("Manage integrations in Settings")
        let footer = NSStackView(views: [footerLabel, flexibleSpacer(), settings])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footer)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            header.heightAnchor.constraint(equalToConstant: 40),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            footer.heightAnchor.constraint(equalToConstant: 22),
            cards.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 16),
            cards.topAnchor.constraint(equalTo: document.topAnchor),
            cards.widthAnchor.constraint(equalToConstant: width - 32)
        ])
    }

    func update(states: [IntegrationID: IntegrationState], enabled: [IntegrationID], displayMode: UsageDisplayMode) {
        if !isViewLoaded { _ = view }
        if order != enabled {
            for id in order where !enabled.contains(id) {
                if let group = groups.removeValue(forKey: id) { cards.removeArrangedSubview(group); group.removeFromSuperview() }
            }
            for (index, id) in enabled.enumerated() where groups[id] == nil {
                let group = IntegrationGroupView(integration: id)
                group.onResize = { [weak self] in self?.resizeContent() }
                group.onReset = { [weak self] id in self?.onUseResetCredit?(id) }
                groups[id] = group
                cards.insertArrangedSubview(group, at: min(index, cards.arrangedSubviews.count))
                group.widthAnchor.constraint(equalTo: cards.widthAnchor).isActive = true
            }
            order = enabled
        }
        if enabled.isEmpty && emptyView == nil {
            let title = quotaLabel("Choose the providers you use", size: 13, weight: .medium)
            let button = NSButton(title: "Set up integrations", target: self, action: #selector(settingsClicked))
            button.bezelStyle = .rounded
            let empty = NSStackView(views: [title, button])
            empty.orientation = .vertical
            empty.spacing = 12
            empty.edgeInsets = NSEdgeInsets(top: 24, left: 0, bottom: 24, right: 0)
            cards.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: cards.widthAnchor).isActive = true
            emptyView = empty
        } else if !enabled.isEmpty, let empty = emptyView {
            cards.removeArrangedSubview(empty)
            empty.removeFromSuperview()
            emptyView = nil
        }
        for id in enabled { groups[id]?.update(states[id] ?? IntegrationState(), mode: displayMode) }
        let pending = enabled.filter { states[$0]?.isRefreshing == true }.count
        let warnings = enabled.filter { states[$0]?.message != nil }.count
        subtitle.stringValue = "\(enabled.count) integration\(enabled.count == 1 ? "" : "s") · percentage \(displayMode.rawValue)"
        footerLabel.stringValue = pending > 0 ? "Updating \(pending) provider\(pending == 1 ? "" : "s")…" : warnings > 0 ? "\(warnings) need attention" : "Direct from your providers"
        refreshButton.isEnabled = pending < enabled.count && !enabled.isEmpty
        resizeContent()
    }

    private func resizeContent() {
        let height = ceil(cards.fittingSize.height)
        document.setFrameSize(NSSize(width: width, height: height))
        let maxHeight = min(680, (view.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 760) - 50
        preferredContentSize = NSSize(width: width, height: min(maxHeight, max(170, height + 104)))
        view.layoutSubtreeIfNeeded()
    }

    func cancelResetConfirmation() { groups[.codex]?.cancelReset() }
    func showResetCreditResult(_ result: Result<ConsumeResetCreditsResponse, Error>, accountID: String) { groups[.codex]?.resetResult(result, accountID: accountID) }
    @objc private func refreshClicked() { onRefresh?() }
    @objc private func settingsClicked() { onOpenSettings?() }
}

private final class FlippedQuotaView: NSView {
    override var isFlipped: Bool { true }
}

private final class IntegrationGroupView: NSView {
    var onResize: (() -> Void)?
    var onReset: ((String) -> Void)?
    private let integration: IntegrationID
    private let stack = NSStackView()
    private let accounts = NSStackView()
    private let toggle = NSButton()
    private let status = quotaLabel("", size: 11, secondary: true)
    private let warning = NSTextField(wrappingLabelWithString: "")
    private var rows: [String: AccountQuotaView] = [:]
    private var ids: [String] = []
    private var expanded = false
    private var state = IntegrationState()
    private var mode: UsageDisplayMode = .used

    init(integration: IntegrationID) {
        self.integration = integration
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 0, bottom: 9, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        let icon = NSImageView(image: AppBranding.providerImage(for: integration) ?? Symbols.image("square.stack.3d.up", pointSize: 18)!)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .labelColor
        if integration == .openCodeGo {
            icon.wantsLayer = true
            icon.layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
            icon.layer?.cornerRadius = 4
        }
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let name = quotaLabel(integration == .antigravity ? "Antigravity" : integration.name, size: 13, weight: .semibold)
        name.setContentHuggingPriority(.required, for: .horizontal)
        toggle.image = Symbols.image("chevron.right", pointSize: 10, weight: .semibold)
        toggle.isBordered = false
        toggle.target = self
        toggle.action = #selector(toggleDetails)
        toggle.setAccessibilityLabel("Show \(integration.name) quota details")
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [icon, name, flexibleSpacer(), status, toggle])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        add(header)
        accounts.orientation = .vertical
        accounts.alignment = .leading
        accounts.spacing = 10
        add(accounts)
        warning.font = .systemFont(ofSize: 11)
        warning.textColor = .secondaryLabelColor
        warning.preferredMaxLayoutWidth = 344
        add(warning)
    }

    required init?(coder: NSCoder) { nil }

    private func add(_ child: NSView) {
        stack.addArrangedSubview(child)
        child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 0.5, width: bounds.width, height: 0.5).fill()
    }

    func update(_ state: IntegrationState, mode: UsageDisplayMode) {
        self.state = state
        self.mode = mode
        let next = state.providers.map(\.id)
        if ids != next {
            for id in ids where !next.contains(id) {
                if let row = rows.removeValue(forKey: id) { accounts.removeArrangedSubview(row); row.removeFromSuperview() }
            }
            for (index, provider) in state.providers.enumerated() where rows[provider.id] == nil {
                let row = AccountQuotaView()
                row.onReset = { [weak self] in self?.onReset?(provider.configurationID ?? IntegrationAccount.current(.codex).id) }
                rows[provider.id] = row
                accounts.insertArrangedSubview(row, at: min(index, accounts.arrangedSubviews.count))
                row.widthAnchor.constraint(equalTo: accounts.widthAnchor).isActive = true
            }
            ids = next
        }
        for provider in state.providers {
            let status = provider.configurationID.flatMap { state.accountStatuses[$0] }
            rows[provider.id]?.update(provider, mode: mode, expanded: expanded,
                                     canReset: (status.map { $0.message == nil && !$0.isRefreshing } ?? (state.message == nil && !state.isRefreshing)),
                                     status: status)
        }
        status.stringValue = state.isRefreshing ? "Updating…" : state.message != nil ? (state.providers.isEmpty ? "Unavailable" : "Check connection") : state.providers.count > 1 ? "\(state.providers.count) accounts" : state.providers.first?.plan ?? "Not checked"
        status.textColor = state.message == nil ? .secondaryLabelColor : .systemOrange
        toggle.isEnabled = !state.providers.isEmpty
        accounts.isHidden = state.providers.isEmpty
        warning.isHidden = state.message == nil && !state.providers.isEmpty && !expanded
        if let message = state.message {
            warning.stringValue = message
        } else if state.providers.isEmpty {
            warning.stringValue = state.isRefreshing ? "Reading quota from the provider…" : integration.setupHint
        } else {
            warning.stringValue = state.providers.first?.sourceLabel ?? ""
        }
    }

    @objc private func toggleDetails() {
        expanded.toggle()
        toggle.image = Symbols.image(expanded ? "chevron.down" : "chevron.right", pointSize: 10, weight: .semibold)
        toggle.setAccessibilityLabel("\(expanded ? "Hide" : "Show") \(integration.name) quota details")
        update(state, mode: mode)
        onResize?()
    }

    func cancelReset() { rows.values.forEach { $0.cancelReset() } }
    func resetResult(_ result: Result<ConsumeResetCreditsResponse, Error>, accountID: String) {
        for provider in state.providers where provider.configurationID == accountID { rows[provider.id]?.resetResult(result) }
    }
}

private final class AccountQuotaView: NSStackView {
    var onReset: (() -> Void)?
    private let account = quotaLabel("", size: 11, weight: .medium)
    private let statusLabel = quotaLabel("", size: 10.5, secondary: true)
    private let summary = LimitQuotaView()
    private let details = NSStackView()
    private let resetButton = NSButton(title: "Use reset credit", target: nil, action: nil)
    private var detailRows: [LimitQuotaView] = []
    private var confirming = false
    private var consuming = false
    private var resetEligible = false
    private var confirmTimer: Timer?

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 8
        details.orientation = .vertical
        details.alignment = .leading
        details.spacing = 9
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small
        resetButton.target = self
        resetButton.action = #selector(resetClicked)
        for child in [account, summary, details] as [NSView] {
            addArrangedSubview(child)
            child.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        addArrangedSubview(resetButton)
        addArrangedSubview(statusLabel)
    }

    required init?(coder: NSCoder) { nil }

    func update(_ provider: ProviderUsage, mode: UsageDisplayMode, expanded: Bool, canReset: Bool, status: AccountStatus?) {
        account.stringValue = provider.accountLabel ?? ""
        account.toolTip = provider.accountLabel
        account.lineBreakMode = .byTruncatingMiddle
        account.isHidden = provider.accountLabel == nil
        statusLabel.isHidden = status?.message == nil && status?.isRefreshing != true
        statusLabel.stringValue = status?.isRefreshing == true ? "Refreshing…" : "Cached"
        statusLabel.toolTip = status?.message
        summary.update(provider.limitingWindow, mode: mode)
        details.isHidden = !expanded
        if expanded {
            while detailRows.count < provider.limits.count {
                let row = LimitQuotaView()
                detailRows.append(row)
                details.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: details.widthAnchor).isActive = true
            }
            for (index, row) in detailRows.enumerated() {
                row.isHidden = index >= provider.limits.count
                if index < provider.limits.count { row.update(provider.limits[index], mode: mode) }
            }
        }
        summary.isHidden = expanded
        resetEligible = canReset && (provider.resetCredits?.applicableAvailableCount ?? 0) > 0 && provider.primary.usedPercent >= 100
        resetButton.isHidden = !expanded || provider.resetCredits == nil
        resetButton.isEnabled = resetEligible && !consuming
        if !resetEligible { cancelReset() }
    }

    @objc private func resetClicked() {
        guard resetEligible, !consuming else { return }
        if confirming {
            cancelReset()
            consuming = true
            resetButton.title = "Resetting…"
            resetButton.isEnabled = false
            onReset?()
        } else {
            confirming = true
            resetButton.title = "Confirm reset"
            confirmTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in self?.cancelReset() }
        }
    }

    func cancelReset() {
        confirmTimer?.invalidate()
        confirmTimer = nil
        confirming = false
        if !consuming { resetButton.title = "Use reset credit" }
    }

    func resetResult(_ result: Result<ConsumeResetCreditsResponse, Error>) {
        consuming = false
        cancelReset()
        switch result {
        case .success(let response): resetButton.title = response.code == "reset" ? "Reset applied" : response.code.replacingOccurrences(of: "_", with: " ").capitalized
        case .failure: resetButton.title = "Reset failed. Try again"
        }
        resetButton.isEnabled = resetEligible
    }
}

private final class LimitQuotaView: NSStackView {
    private let name = quotaLabel("", size: 11, secondary: true)
    private let value = quotaLabel("", size: 12, weight: .semibold)
    private let reset = quotaLabel("", size: 10.5, secondary: true)
    private let bar = ThinBarView()

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 4
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        name.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [name, flexibleSpacer(), value])
        row.orientation = .horizontal
        row.spacing = 6
        for child in [row, bar, reset] as [NSView] {
            addArrangedSubview(child)
            child.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        bar.heightAnchor.constraint(equalToConstant: 5).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    func update(_ limit: ProviderLimit, mode: UsageDisplayMode) {
        let shown = mode == .used ? limit.usedPercent : limit.remainingPercent
        name.stringValue = limit.displayLabel
        name.toolTip = limit.displayLabel
        value.stringValue = String(format: "%.0f%% %@", shown, mode == .used ? "used" : "left")
        let color = AppBranding.progressColor(forUsedPercent: Int(limit.usedPercent))
        value.textColor = color
        bar.barColor = color
        bar.progress = shown
        bar.setAccessibilityLabel(limit.displayLabel + ", " + mode.rawValue)
        reset.stringValue = limit.resetAt.map { $0 <= Date() ? "Reset due; refresh to confirm" : "Resets \(QuotaText.reset($0))" } ?? "Reset time unavailable"
        reset.toolTip = limit.resetAt?.description
    }
}

private func quotaLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = secondary ? .secondaryLabelColor : .labelColor
    return label
}

private enum QuotaText {
    static func reset(_ date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        if seconds < 60 { return "in <1m" }
        if seconds < 3600 { return "in \(seconds / 60)m" }
        if seconds < 86400 { return "in \(seconds / 3600)h \((seconds % 3600) / 60)m" }
        return "in \(seconds / 86400)d \((seconds % 86400) / 3600)h"
    }

}
