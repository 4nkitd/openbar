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
    private var active: Set<IntegrationID> = []

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
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            header.heightAnchor.constraint(equalToConstant: 36),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            footer.heightAnchor.constraint(equalToConstant: 22),
            cards.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 16),
            cards.topAnchor.constraint(equalTo: document.topAnchor),
            cards.widthAnchor.constraint(equalToConstant: width - 32)
        ])
    }

    func update(states: [IntegrationID: IntegrationState], enabled: [IntegrationID], displayMode: UsageDisplayMode, active: Set<IntegrationID> = []) {
        if !isViewLoaded { _ = view }
        self.active = active
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
        for id in enabled {
            groups[id]?.update(states[id] ?? IntegrationState(), mode: displayMode)
            groups[id]?.setActive(active.contains(id))
        }
        let pending = enabled.filter { states[$0]?.isRefreshing == true }.count
        let warnings = enabled.filter { states[$0]?.message != nil }.count
        subtitle.stringValue = "\(enabled.count) integration\(enabled.count == 1 ? "" : "s") · percentage \(displayMode.rawValue)"
        footerLabel.stringValue = warnings > 0 ? "\(warnings) need attention" : "Direct from your providers"
        refreshButton.isEnabled = pending < enabled.count && !enabled.isEmpty
        resizeContent()
    }

    private func resizeContent() {
        let height = ceil(cards.fittingSize.height)
        document.setFrameSize(NSSize(width: width, height: height))
        let maxHeight = min(680, (view.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 760) - 50
        preferredContentSize = NSSize(width: width, height: min(maxHeight, max(170, height + 92)))
        view.layoutSubtreeIfNeeded()
    }

    func setActive(_ active: Set<IntegrationID>) {
        self.active = active
        for id in order { groups[id]?.setActive(active.contains(id)) }
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
    private let equalizer = ActivityEqualizerView()
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
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        let icon = NSImageView(image: AppBranding.providerImage(for: integration) ?? Symbols.image("square.stack.3d.up", pointSize: 18)!)
        icon.imageScaling = .scaleProportionallyUpOrDown
        if icon.image?.isTemplate == true { icon.contentTintColor = .labelColor }
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
        equalizer.color = AppBranding.brandColor(for: integration)
        equalizer.isHidden = true
        equalizer.setAccessibilityLabel("\(integration.name) in use")
        let header = NSStackView(views: [icon, name, flexibleSpacer(), equalizer, status, toggle])
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
            let attention = status?.message ?? (state.accountStatuses.isEmpty ? state.message : nil)
            rows[provider.id]?.update(provider, mode: mode, expanded: expanded,
                                     canReset: (status.map { $0.message == nil && !$0.isRefreshing } ?? (state.message == nil && !state.isRefreshing)),
                                     status: status, attention: attention)
        }
        status.stringValue = state.message != nil ? (state.providers.isEmpty ? "Unavailable" : "Check connection") : state.providers.count > 1 ? "\(state.providers.count) accounts" : state.providers.first?.plan ?? "Not checked"
        status.textColor = state.message == nil ? .secondaryLabelColor : .systemOrange
        toggle.isEnabled = !state.providers.isEmpty
        accounts.isHidden = state.providers.isEmpty
        warning.isHidden = state.message == nil && !state.providers.isEmpty && !expanded
        if let message = state.message {
            warning.stringValue = message
        } else if state.providers.isEmpty {
            warning.stringValue = integration.setupHint
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

    func setActive(_ active: Bool) {
        equalizer.isHidden = !active
        equalizer.setActive(active)
        rows.values.forEach { $0.setActive(active) }
    }

    func cancelReset() { rows.values.forEach { $0.cancelReset() } }
    func resetResult(_ result: Result<ConsumeResetCreditsResponse, Error>, accountID: String) {
        for provider in state.providers where provider.configurationID == accountID { rows[provider.id]?.resetResult(result) }
    }
}

private final class AccountQuotaView: NSStackView {
    var onReset: (() -> Void)?
    private let summary = LimitQuotaView()
    private let details = NSStackView()
    private let resetButton = NSButton(title: "Use reset credit", target: nil, action: nil)
    private var detailRows: [LimitQuotaView] = []
    private var confirming = false
    private var consuming = false
    private var resetEligible = false
    private var live = false
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
        for child in [summary, details] as [NSView] {
            addArrangedSubview(child)
            child.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        addArrangedSubview(resetButton)
    }

    required init?(coder: NSCoder) { nil }

    func update(_ provider: ProviderUsage, mode: UsageDisplayMode, expanded: Bool, canReset: Bool, status: AccountStatus?, attention: String? = nil) {
        let refreshing = status?.isRefreshing == true
        summary.setRefreshing(refreshing)
        summary.update(provider.limitingWindow, mode: mode, integration: provider.integration,
                       title: provider.accountLabel ?? provider.integration.name,
                       credits: provider.resetCredits?.applicableAvailableCount,
                       attention: refreshing ? nil : attention)
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
                if index < provider.limits.count {
                    row.setRefreshing(refreshing)
                    row.update(provider.limits[index], mode: mode, integration: provider.integration)
                } else {
                    row.setRefreshing(false)
                }
            }
        } else {
            detailRows.forEach { $0.setRefreshing(false) }
        }
        resetEligible = canReset && (provider.resetCredits?.applicableAvailableCount ?? 0) > 0 && provider.primary.usedPercent >= 100
        resetButton.isHidden = !expanded || provider.resetCredits == nil
        resetButton.isEnabled = resetEligible && !consuming
        if !resetEligible { cancelReset() }
        setActive(live)
    }

    func setActive(_ active: Bool) {
        live = active
        summary.setActive(active)
        detailRows.forEach { $0.setActive(active) }
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

private final class LimitQuotaView: NSView {
    private let name = quotaLabel("", size: 12, weight: .medium)
    private let value = quotaLabel("", size: 12, weight: .semibold)
    private let reset = quotaLabel("", size: 11)
    private let creditsLabel = quotaLabel("", size: 11, weight: .medium)
    private let creditGroup = NSStackView()
    private let attentionIcon = NSImageView(image: Symbols.image("exclamationmark.circle.fill", pointSize: 11)!)
    private let badge = NSStackView()
    private var progress: Double = 0
    private var usedPercent: Double = 0
    private var integration: IntegrationID = .codex
    private(set) var isActive = false
    private var isRefreshing = false
    private var shouldAnimate: Bool { window != nil && (isActive || isRefreshing) && !OpenCodeActivityMonitor.reduceMotion }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        name.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)
        reset.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let clock = NSImageView(image: Symbols.image("arrow.clockwise", pointSize: 11)!)
        let ticket = NSImageView(image: Symbols.image("ticket", pointSize: 12)!)
        for icon in [clock, ticket, attentionIcon] {
            icon.contentTintColor = icon === attentionIcon ? .systemOrange : .labelColor
            icon.widthAnchor.constraint(equalToConstant: 13).isActive = true
        }
        attentionIcon.isHidden = true
        attentionIcon.setAccessibilityElement(true)
        attentionIcon.setAccessibilityRole(.image)
        creditGroup.orientation = .horizontal
        creditGroup.spacing = 4
        creditGroup.addArrangedSubview(ticket)
        creditGroup.addArrangedSubview(creditsLabel)
        badge.orientation = .horizontal
        badge.alignment = .centerY
        badge.spacing = 5
        badge.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        for child in [attentionIcon, clock, reset, creditGroup] { badge.addArrangedSubview(child) }
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        reset.setContentCompressionResistancePriority(.required, for: .horizontal)
        creditsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = NSStackView(views: [name, value, flexibleSpacer(), badge])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).addClip()
        NSColor(white: dark ? 0.12 : 0.94, alpha: 1).setFill()
        bounds.fill()
        let filledPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: bounds.width * progress / 100, height: bounds.height),
                                      xRadius: 9, yRadius: 9)
        NSGraphicsContext.saveGraphicsState()
        let unfilledPath = NSBezierPath(rect: bounds)
        unfilledPath.append(filledPath)
        unfilledPath.windingRule = .evenOdd
        unfilledPath.addClip()
        NSColor(white: dark ? 0.26 : 0.82, alpha: 1).setStroke()
        let stripes = NSBezierPath()
        stripes.lineWidth = 1
        let crawl = shouldAnimate
            ? CGFloat(CACurrentMediaTime().truncatingRemainder(dividingBy: 1.1) / 1.1) * 6
            : 0
        for x in stride(from: -bounds.height + crawl, through: bounds.width, by: 6) {
            stripes.move(to: NSPoint(x: x, y: 0))
            stripes.line(to: NSPoint(x: x + bounds.height, y: bounds.height))
        }
        stripes.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let fill = AppBranding.progressColor(forUsedPercent: Int(usedPercent), integration: integration)
            .withAlphaComponent(dark ? (integration == .xai && usedPercent < 80 ? 0.4 : 0.65) : 0.3)
        if isActive || isRefreshing {
            let now = CACurrentMediaTime()
            let sweep = now.truncatingRemainder(dividingBy: 2.2) / 2.2
            let pulse = 0.5 + 0.5 * sin(sweep * 2 * .pi)
            if shouldAnimate {
                layer?.shadowColor = fill.cgColor
                layer?.shadowOffset = .zero
                layer?.shadowRadius = 8 + 6 * pulse
                layer?.shadowOpacity = Float(0.28 + 0.2 * pulse)
            } else {
                layer?.shadowOpacity = 0
            }
            fill.withAlphaComponent(fill.alphaComponent + (shouldAnimate ? 0.08 * pulse : 0.12)).setFill()
        } else {
            layer?.shadowOpacity = 0
            fill.setFill()
        }
        filledPath.fill()
        if shouldAnimate {
            NSGraphicsContext.saveGraphicsState()
            filledPath.addClip()
            let sweep = CACurrentMediaTime().truncatingRemainder(dividingBy: 2.2) / 2.2
            let span = max(36, bounds.width * 0.28)
            let travel = bounds.width + span
            let x = travel * sweep - span
            NSGradient(colors: [
                NSColor.white.withAlphaComponent(0),
                NSColor.white.withAlphaComponent(dark ? 0.28 : 0.45),
                NSColor.white.withAlphaComponent(0)
            ])?.draw(in: NSRect(x: x, y: 0, width: span, height: bounds.height), angle: 0)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor(white: dark ? 0.08 : 0.97, alpha: 0.94).setFill()
        NSBezierPath(roundedRect: convert(badge.bounds, from: badge), xRadius: 5, yRadius: 5).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        syncRedraw()
    }

    func setRefreshing(_ refreshing: Bool) {
        guard isRefreshing != refreshing else { return }
        isRefreshing = refreshing
        syncRedraw()
    }

    private func syncRedraw() {
        if shouldAnimate { ActivityRedraw.shared.add(self) }
        else { ActivityRedraw.shared.remove(self) }
        needsDisplay = true
    }

    func update(_ limit: ProviderLimit, mode: UsageDisplayMode, integration: IntegrationID,
                title: String? = nil, credits: Int? = nil, attention: String? = nil) {
        let shown = mode == .used ? limit.usedPercent : limit.remainingPercent
        name.stringValue = title ?? limit.displayLabel
        name.toolTip = name.stringValue
        value.stringValue = String(format: "%.0f%%", shown)
        value.toolTip = "Percentage \(mode.rawValue) · \(limit.displayLabel)"
        progress = shown
        usedPercent = limit.usedPercent
        self.integration = integration
        reset.stringValue = limit.resetAt.map { $0 <= Date() ? "Due" : QuotaText.reset($0).replacingOccurrences(of: "in ", with: "") } ?? "—"
        reset.toolTip = limit.resetAt.map { $0 <= Date() ? "Reset due; refresh to confirm" : "Resets \($0.description)" } ?? "Reset time unavailable"
        creditGroup.isHidden = credits == nil
        creditsLabel.stringValue = credits.map(String.init) ?? ""
        creditGroup.toolTip = credits.map { "\($0) reset credits available" }
        attentionIcon.isHidden = attention == nil
        attentionIcon.toolTip = attention
        attentionIcon.setAccessibilityLabel(attention)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(name.stringValue), \(value.stringValue) \(mode.rawValue), \(limit.displayLabel), \(reset.toolTip ?? "")" + (credits.map { ", \($0) reset credits available" } ?? "") + (isRefreshing ? ", updating" : "") + (attention.map { ", \($0)" } ?? ""))
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { ActivityRedraw.shared.remove(self) }
        else if shouldAnimate { ActivityRedraw.shared.add(self) }
    }
}

private final class ActivityEqualizerView: NSView {
    var color: NSColor = .white { didSet { needsDisplay = true } }
    private(set) var isActive = false

    override var intrinsicContentSize: NSSize { NSSize(width: 14, height: 11) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { nil }

    func setActive(_ active: Bool) {
        isActive = active
        if active, !OpenCodeActivityMonitor.reduceMotion { ActivityRedraw.shared.add(self) }
        else { ActivityRedraw.shared.remove(self) }
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { ActivityRedraw.shared.remove(self) }
        else if isActive, !OpenCodeActivityMonitor.reduceMotion { ActivityRedraw.shared.add(self) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let t = CACurrentMediaTime()
        let delays: [CGFloat] = [0.55, 0.2, 0.8]
        for index in 0..<3 {
            let scale: CGFloat
            if isActive, !OpenCodeActivityMonitor.reduceMotion {
                scale = 0.35 + 0.65 * (0.5 + 0.5 * sin((t * 2 + delays[index]) * .pi))
            } else {
                scale = 0.7
            }
            let height = bounds.height * scale
            let rect = NSRect(x: CGFloat(index) * 5, y: (bounds.height - height) / 2, width: 3, height: height)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
        }
    }
}

@MainActor
private final class ActivityRedraw {
    static let shared = ActivityRedraw()
    private var views = NSHashTable<NSView>.weakObjects()
    private var timer: Timer?

    func add(_ view: NSView) {
        views.add(view)
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 1.0 / 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func remove(_ view: NSView) {
        views.remove(view)
        if views.allObjects.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    private func tick() {
        for view in views.allObjects { view.needsDisplay = true }
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
