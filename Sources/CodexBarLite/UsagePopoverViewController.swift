import AppKit

enum PopoverState {
    case usage(CodexUsage, updatedAt: Date, warning: String?)
    case signedOut(signingIn: Bool)
    case failure(String)
}

/// Content of the status-item popover: header, hero usage ring, compact info
/// rows, secondary window block, and footer. Pure presentation — all data and
/// actions come from the app delegate.
final class UsagePopoverViewController: NSViewController {
    var actionsMenu: NSMenu?
    var onRefresh: (() -> Void)?
    var onSignIn: (() -> Void)?
    var onUseResetCredit: (() -> Void)?

    private let contentWidth: CGFloat = 320
    private let contentInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

    // Header
    private let logoView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "CodexBar Lite")
    private let planPill = PillLabel()
    private let overflowButton = NSButton()

    // Hero ring
    private let ringView = ProgressRingView()
    private let percentLabel = NSTextField(labelWithString: "–")
    private let usedCaptionLabel = NSTextField(labelWithString: "Used")

    // Primary info rows
    private let primaryGroup = RoundedGroupView()
    private let windowRow = InfoRow(symbol: "clock", title: "Usage window")
    private let resetInRow = InfoRow(symbol: "timer", title: "Resets in")
    private let resetAtRow = InfoRow(symbol: "calendar.badge.clock", title: "Reset time")
    private let creditsRow = InfoRow(symbol: "arrow.counterclockwise.circle", title: "Reset credits")
    private let resetCreditRow = NSView()
    private let resetCreditButton = NSButton()
    private var resetConfirmPending = false
    private var resetConfirmTimer: Timer?

    // Secondary block
    private let secondaryGroup = RoundedGroupView()
    private let secondaryRow = InfoRow(symbol: "gauge", title: "Secondary")
    private let secondaryBar = ThinBarView()
    private let secondaryResetRow = InfoRow(symbol: "timer", title: "Resets in")

    // Warning
    private let warningGroup = RoundedGroupView(insets: NSEdgeInsets(top: 9, left: 12, bottom: 9, right: 12))
    private let warningLabel = NSTextField(labelWithString: "")

    // Footer
    private let footerStack = NSStackView()
    private let updatedLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton()

    // Non-usage states
    private let statusStack = NSStackView()
    private let statusIcon = NSImageView()
    private let statusTitle = NSTextField(labelWithString: "")
    private let statusSubtitle = NSTextField(labelWithString: "")
    private let signInButton = NSButton(title: "Sign In…", target: nil, action: nil)
    private let spinner = NSProgressIndicator()

    private let usageStack = NSStackView()
    private let rootStack = NSStackView()
    private var currentState: PopoverState?
    private var hasRenderedUsage = false

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 400))
        self.view = view

        // NSPopover's own chrome is vibrant and samples whatever sits behind
        // the popover window (desktop wallpaper, windows underneath), so the
        // exact same content looks different depending on what's behind it.
        // Backing the content with an opaque, within-window effect view
        // pins it to a solid, consistent appearance.
        let background = NSVisualEffectView(frame: view.bounds)
        background.autoresizingMask = [.width, .height]
        background.material = .popover
        background.blendingMode = .withinWindow
        background.state = .active
        view.addSubview(background)

        buildHeader(into: view)
        buildHero()
        buildInfoGroups()
        buildStatusArea()
        buildFooter()

        rootStack.orientation = .vertical
        rootStack.alignment = .centerX
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: contentInsets.left),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -contentInsets.right),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: contentInsets.top),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -contentInsets.bottom)
        ])

        let headerRow = makeHeaderRow()
        rootStack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

        rootStack.addArrangedSubview(usageStack)
        usageStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

        rootStack.addArrangedSubview(statusStack)
        statusStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

        rootStack.addArrangedSubview(footerStack)
        footerStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

        preferredContentSize = NSSize(width: contentWidth, height: 400)
    }

    // MARK: - Building

    private func buildHeader(into view: NSView) {
        if let logo = AppBranding.logoImage {
            logoView.image = logo
        }
        logoView.wantsLayer = true
        logoView.layer?.cornerRadius = 5
        logoView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logoView.widthAnchor.constraint(equalToConstant: 22),
            logoView.heightAnchor.constraint(equalToConstant: 22)
        ])

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        logoView.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        overflowButton.isBordered = false
        overflowButton.image = Symbols.image("ellipsis.circle", pointSize: 16)
        overflowButton.contentTintColor = .secondaryLabelColor
        overflowButton.target = self
        overflowButton.action = #selector(overflowClicked)
        overflowButton.translatesAutoresizingMaskIntoConstraints = false
        overflowButton.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func makeHeaderRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.addArrangedSubview(logoView)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(planPill)
        row.addArrangedSubview(flexibleSpacer())
        row.addArrangedSubview(overflowButton)
        return row
    }

    private func buildHero() {
        ringView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            ringView.widthAnchor.constraint(equalToConstant: 156),
            ringView.heightAnchor.constraint(equalToConstant: 156)
        ])

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 32, weight: .semibold)
        usedCaptionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        usedCaptionLabel.textColor = .secondaryLabelColor

        let labelStack = NSStackView(views: [percentLabel, usedCaptionLabel])
        labelStack.orientation = .vertical
        labelStack.alignment = .centerX
        labelStack.spacing = 0
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        ringView.addSubview(labelStack)
        NSLayoutConstraint.activate([
            labelStack.centerXAnchor.constraint(equalTo: ringView.centerXAnchor),
            labelStack.centerYAnchor.constraint(equalTo: ringView.centerYAnchor)
        ])

        let heroContainer = NSView()
        heroContainer.translatesAutoresizingMaskIntoConstraints = false
        heroContainer.addSubview(ringView)
        NSLayoutConstraint.activate([
            ringView.centerXAnchor.constraint(equalTo: heroContainer.centerXAnchor),
            ringView.topAnchor.constraint(equalTo: heroContainer.topAnchor, constant: 4),
            ringView.bottomAnchor.constraint(equalTo: heroContainer.bottomAnchor)
        ])
        heroContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        usageStack.orientation = .vertical
        usageStack.alignment = .centerX
        usageStack.spacing = 12
        usageStack.addArrangedSubview(heroContainer)
        heroContainer.widthAnchor.constraint(equalTo: usageStack.widthAnchor).isActive = true
    }

    private func buildInfoGroups() {
        primaryGroup.addRow(windowRow)
        primaryGroup.addDivider(leadingInset: 24)
        primaryGroup.addRow(resetInRow)
        primaryGroup.addDivider(leadingInset: 24)
        primaryGroup.addRow(resetAtRow)
        primaryGroup.addDivider(leadingInset: 24)
        primaryGroup.addRow(creditsRow)
        primaryGroup.addDivider(leadingInset: 24)
        primaryGroup.addRow(buildResetCreditRow())

        secondaryGroup.addRow(secondaryRow)
        secondaryGroup.addDivider(leadingInset: 24)

        let barContainer = NSView()
        secondaryBar.translatesAutoresizingMaskIntoConstraints = false
        barContainer.addSubview(secondaryBar)
        NSLayoutConstraint.activate([
            secondaryBar.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor),
            secondaryBar.trailingAnchor.constraint(equalTo: barContainer.trailingAnchor),
            secondaryBar.centerYAnchor.constraint(equalTo: barContainer.centerYAnchor),
            secondaryBar.heightAnchor.constraint(equalToConstant: 4),
            barContainer.heightAnchor.constraint(equalToConstant: 14)
        ])
        secondaryGroup.addRow(barContainer)
        secondaryGroup.addDivider(leadingInset: 24)
        secondaryGroup.addRow(secondaryResetRow)

        warningLabel.font = .systemFont(ofSize: 12)
        warningLabel.textColor = .secondaryLabelColor
        warningLabel.maximumNumberOfLines = 2
        warningLabel.lineBreakMode = .byWordWrapping
        warningLabel.preferredMaxLayoutWidth = contentWidth - contentInsets.left - contentInsets.right - 44
        let warningRow = NSStackView()
        warningRow.orientation = .horizontal
        warningRow.alignment = .centerY
        warningRow.spacing = 8
        let warningIcon = Symbols.view("exclamationmark.triangle", pointSize: 13, weight: .medium, tint: .systemYellow)
        warningRow.addArrangedSubview(warningIcon)
        warningRow.addArrangedSubview(warningLabel)
        warningGroup.addRow(warningRow)

        for group in [primaryGroup, secondaryGroup, warningGroup] {
            group.translatesAutoresizingMaskIntoConstraints = false
            usageStack.addArrangedSubview(group)
            group.widthAnchor.constraint(equalTo: usageStack.widthAnchor).isActive = true
        }
    }

    private func buildResetCreditRow() -> NSView {
        let icon = Symbols.view("bolt.fill", pointSize: 13, weight: .regular, tint: .secondaryLabelColor)
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true

        let titleLabel = NSTextField(labelWithString: "Use reset credit")
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        resetCreditButton.bezelStyle = .rounded
        resetCreditButton.controlSize = .small
        resetCreditButton.title = "Use Reset"
        resetCreditButton.target = self
        resetCreditButton.action = #selector(resetCreditClicked)
        resetCreditButton.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [icon, titleLabel, flexibleSpacer(), resetCreditButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        resetCreditRow.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: resetCreditRow.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: resetCreditRow.trailingAnchor),
            row.topAnchor.constraint(equalTo: resetCreditRow.topAnchor, constant: 5),
            row.bottomAnchor.constraint(equalTo: resetCreditRow.bottomAnchor, constant: -5)
        ])

        return resetCreditRow
    }

    private func buildStatusArea() {
        statusStack.orientation = .vertical
        statusStack.alignment = .centerX
        statusStack.spacing = 8
        statusStack.edgeInsets = NSEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)

        statusIcon.imageScaling = .scaleProportionallyUpOrDown
        statusIcon.translatesAutoresizingMaskIntoConstraints = false

        statusTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        statusSubtitle.font = .systemFont(ofSize: 12)
        statusSubtitle.textColor = .secondaryLabelColor
        statusSubtitle.maximumNumberOfLines = 2
        statusSubtitle.alignment = .center

        signInButton.bezelStyle = .rounded
        signInButton.controlSize = .large
        signInButton.bezelColor = AppBranding.accentColor
        signInButton.contentTintColor = .white
        signInButton.target = self
        signInButton.action = #selector(signInClicked)

        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spinner.widthAnchor.constraint(equalToConstant: 20),
            spinner.heightAnchor.constraint(equalToConstant: 20)
        ])

        for view in [statusIcon, statusTitle, statusSubtitle, signInButton, spinner] {
            statusStack.addArrangedSubview(view)
        }
        statusStack.setCustomSpacing(12, after: statusSubtitle)
    }

    private func buildFooter() {
        updatedLabel.font = .systemFont(ofSize: 11)
        updatedLabel.textColor = .secondaryLabelColor

        refreshButton.isBordered = false
        refreshButton.image = Symbols.image("arrow.clockwise", pointSize: 13, weight: .medium)
        refreshButton.contentTintColor = .secondaryLabelColor
        refreshButton.toolTip = "Refresh"
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)

        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        footerStack.addArrangedSubview(updatedLabel)
        footerStack.addArrangedSubview(flexibleSpacer())
        footerStack.addArrangedSubview(refreshButton)
    }

    // MARK: - Updating

    func update(state: PopoverState, displayMode: UsageDisplayMode) {
        if !isViewLoaded { _ = view }
        currentState = state

        switch state {
        case .usage(let usage, let updatedAt, let warning):
            showUsage(usage, updatedAt: updatedAt, warning: warning, displayMode: displayMode)
        case .signedOut(let signingIn):
            showSignedOut(signingIn: signingIn)
        case .failure(let message):
            showFailure(message)
        }

        view.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(
            width: contentWidth,
            height: rootStack.fittingSize.height + contentInsets.top + contentInsets.bottom
        )
    }

    private func showUsage(_ usage: CodexUsage, updatedAt: Date, warning: String?, displayMode: UsageDisplayMode) {
        usageStack.isHidden = false
        statusStack.isHidden = true
        footerStack.isHidden = false
        spinner.stopAnimation(nil)

        planPill.text = usage.planType.uppercased()
        planPill.isHidden = false

        let primary = usage.rateLimit.primaryWindow
        let used = primary.usedPercent
        let shown = displayMode == .used ? used : 100 - used
        let ringColor = AppBranding.progressColor(forUsedPercent: used)
        let ringProgress = Double(max(0, min(100, shown))) / 100

        ringView.ringColor = ringColor
        ringView.setProgress(ringProgress, animated: hasRenderedUsage)
        percentLabel.stringValue = "\(shown)%"
        usedCaptionLabel.stringValue = displayMode == .used ? "Used" : "Remaining"
        usedCaptionLabel.textColor = ringColor
        hasRenderedUsage = true

        windowRow.value = windowLengthDescription(primary)
        if primary.usedPercent > 0 {
            resetInRow.value = formatDuration(secondsUntilReset(primary))
            resetAtRow.value = resetAtDescription(primary)
        } else {
            resetInRow.value = "Not started"
            resetAtRow.value = "Not started"
        }

        if let credits = usage.rateLimitResetCredits {
            creditsRow.value = "\(credits.availableCount)"
            creditsRow.isHidden = false
            resetCreditRow.isHidden = false
            resetConfirmTimer?.invalidate()
            resetConfirmTimer = nil
            resetConfirmPending = false
            resetCreditButton.title = "Use Reset"
            resetCreditButton.isEnabled = (credits.applicableAvailableCount ?? 0) > 0 && primary.usedPercent >= 100
        } else {
            creditsRow.isHidden = true
            resetCreditRow.isHidden = true
        }

        if let secondary = usage.rateLimit.secondaryWindow {
            secondaryGroup.isHidden = false
            let secondaryUsed = secondary.usedPercent
            secondaryRow.value = displayMode == .used ? "\(secondaryUsed)% used" : "\(100 - secondaryUsed)% left"
            secondaryBar.progress = secondaryUsed
            secondaryBar.barColor = AppBranding.progressColor(forUsedPercent: secondaryUsed)
            secondaryResetRow.value = secondaryUsed > 0
                ? formatDuration(secondsUntilReset(secondary))
                : "Not started"
        } else {
            secondaryGroup.isHidden = true
        }

        if let warning {
            warningGroup.isHidden = false
            warningLabel.stringValue = warning
        } else {
            warningGroup.isHidden = true
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        updatedLabel.stringValue = "Updated \(formatter.string(from: updatedAt))"
    }

    private func showSignedOut(signingIn: Bool) {
        usageStack.isHidden = true
        statusStack.isHidden = false
        footerStack.isHidden = true
        planPill.isHidden = true

        statusIcon.image = Symbols.image("person.crop.circle", pointSize: 30)
        statusIcon.contentTintColor = .secondaryLabelColor
        statusTitle.stringValue = signingIn ? "Signing in to Codex…" : "Codex login required"
        statusSubtitle.stringValue = signingIn
            ? "Finish login in Terminal. Status updates automatically."
            : "Sign in with the Codex CLI to see your usage."
        signInButton.title = "Sign In…"
        signInButton.isHidden = signingIn
        spinner.isHidden = !signingIn
        if signingIn { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    private func showFailure(_ message: String) {
        usageStack.isHidden = true
        statusStack.isHidden = false
        footerStack.isHidden = true
        planPill.isHidden = true

        statusIcon.image = Symbols.image("exclamationmark.triangle", pointSize: 28)
        statusIcon.contentTintColor = .systemYellow
        statusTitle.stringValue = "Couldn't load usage"
        statusSubtitle.stringValue = message
        signInButton.isHidden = false
        signInButton.title = "Try Again"
        spinner.isHidden = true
        spinner.stopAnimation(nil)
    }

    // MARK: - Actions

    @objc private func overflowClicked(_ sender: NSButton) {
        guard let menu = actionsMenu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 6), in: sender)
    }

    @objc private func refreshClicked() {
        onRefresh?()
    }

    @objc private func signInClicked() {
        if case .failure = currentState {
            onRefresh?()
        } else {
            onSignIn?()
        }
    }

    @objc private func resetCreditClicked() {
        if resetConfirmPending {
            resetConfirmTimer?.invalidate()
            resetConfirmTimer = nil
            resetConfirmPending = false
            resetCreditButton.isEnabled = false
            resetCreditButton.title = "Resetting…"
            onUseResetCredit?()
        } else {
            resetConfirmPending = true
            resetCreditButton.title = "Confirm?"
            resetConfirmTimer?.invalidate()
            resetConfirmTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.resetConfirmPending = false
                self.resetCreditButton.title = "Use Reset"
            }
        }
    }

    /// Shows a brief outcome message on the reset-credit button after a
    /// consume attempt. The delegate follows this with a `refresh()` that
    /// re-drives `showUsage`, which restores the button to its normal state.
    func showResetCreditResult(_ result: Result<ConsumeResetCreditsResponse, Error>) {
        resetConfirmTimer?.invalidate()
        resetConfirmTimer = nil
        resetConfirmPending = false

        switch result {
        case .success(let response):
            switch response.code {
            case "reset":
                resetCreditButton.title = "✓ Reset applied"
            case "nothing_to_reset":
                resetCreditButton.title = "Nothing to reset"
            case "no_credit":
                resetCreditButton.title = "No credits left"
            case "already_redeemed":
                resetCreditButton.title = "Already redeemed"
            default:
                resetCreditButton.title = response.code
            }
        case .failure:
            resetCreditButton.title = "Couldn't reset"
        }
    }

    // MARK: - Formatting

    private func secondsUntilReset(_ window: UsageWindow) -> Int {
        max(0, window.resetAt - Int(Date().timeIntervalSince1970))
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds <= 0 { return "0m" }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func windowLengthDescription(_ window: UsageWindow) -> String {
        guard let seconds = window.limitWindowSeconds, seconds > 0 else { return "Session" }
        if seconds % 86_400 == 0 { return "\(seconds / 86_400)-day" }
        if seconds % 3_600 == 0 { return "\(seconds / 3_600)-hour" }
        return "\(seconds / 60)m"
    }

    private func resetAtDescription(_ window: UsageWindow) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(window.resetAt))
        let formatter = DateFormatter()
        if date.timeIntervalSinceNow < 24 * 3_600 {
            formatter.timeStyle = .short
            formatter.dateStyle = .none
        } else {
            formatter.setLocalizedDateFormatFromTemplate("EEEjmm")
        }
        return formatter.string(from: date)
    }
}

/// Compact row: SF Symbol icon, title left, value right.
private final class InfoRow: NSView {
    private let valueLabel = NSTextField(labelWithString: "")

    var value: String {
        get { valueLabel.stringValue }
        set { valueLabel.stringValue = newValue }
    }

    init(symbol: String, title: String) {
        super.init(frame: .zero)

        let icon = Symbols.view(symbol, pointSize: 13, weight: .regular, tint: .secondaryLabelColor)
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [icon, titleLabel, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}
