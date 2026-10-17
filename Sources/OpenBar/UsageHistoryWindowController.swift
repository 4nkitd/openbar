import AppKit

final class UsageHistoryWindowController: NSWindowController {
    let usageView = UsageHistoryViewController()

    init(onRefresh: @escaping () -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "OpenBar Usage"
        window.minSize = NSSize(width: 660, height: 480)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        usageView.onRefresh = onRefresh
        window.contentViewController = usageView
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class UsageHistoryViewController: NSViewController {
    var onRefresh: (() -> Void)?
    private let scroll = NSScrollView()
    private let document = UsageHistoryDocument()
    private let stack = NSStackView()
    private var contentWidth: NSLayoutConstraint?
    private var snapshot: UsageHistorySnapshot?
    private var loading = false
    private var showsDetails = false

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 740, height: 680))
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = document
        view.addSubview(scroll)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        contentWidth = stack.widthAnchor.constraint(equalToConstant: 692)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24), contentWidth!
        ])
        rebuild()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        contentWidth?.constant = max(580, scroll.contentSize.width - 48)
        document.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(scroll.contentSize.height, ceil(stack.fittingSize.height) + 48)))
    }

    func update(_ snapshot: UsageHistorySnapshot?, loading: Bool) {
        self.snapshot = snapshot
        self.loading = loading
        if !isViewLoaded { _ = view } else { rebuild() }
    }

    private func rebuild() {
        for child in stack.arrangedSubviews { stack.removeArrangedSubview(child); child.removeFromSuperview() }
        let title = label("Usage", size: 20, weight: .semibold)
        let refresh = NSButton(title: loading ? "Reading usage…" : "Refresh", target: self, action: #selector(refreshClicked))
        refresh.bezelStyle = .rounded
        refresh.isEnabled = !loading
        refresh.setAccessibilityLabel("Refresh recorded token usage and estimated API cost")
        add(horizontal([title, flexibleSpacer(), label("All recorded history", size: 12, secondary: true), refresh]))
        guard let snapshot else {
            add(label(loading ? "Reading local counters and available usage APIs…" : "Refresh to read usage on this Mac.", size: 14, secondary: true))
            view.needsLayout = true
            return
        }
        let tokens = snapshot.tokens
        let metrics = horizontal([
             metric(title: "Recorded tokens", value: Self.tokens(tokens.total), detail: tokens.total == 0 ? "No token records found" : "Local + OpenCode history"),
            metric(title: snapshot.unpricedTokens > 0 ? "Estimated API cost · partial" : "Estimated API cost", value: Self.money(snapshot.estimatedUSD),
                   detail: snapshot.unpricedTokens > 0 ? "USD estimate • \(Self.tokens(snapshot.unpricedTokens)) unpriced" : "USD estimate, not billed spend")
        ])
        metrics.distribution = .fillEqually
        metrics.spacing = 16
        add(metrics)
        let breakdown = horizontal([
            smallMetric("Input", tokens.input), smallMetric("Output + reasoning", tokens.output),
            smallMetric("Cache read", tokens.cacheRead), smallMetric("Cache write", tokens.cacheWrite)
        ])
        breakdown.distribution = .fillEqually
        add(breakdown)
        add(separator())

        let details = NSButton(title: "", target: self, action: #selector(toggleDetails))
        details.setAccessibilityLabel(showsDetails ? "Hide sources and account totals" : "Show sources and account totals")
        details.bezelStyle = .disclosure
        details.setButtonType(.onOff)
        details.state = showsDetails ? .on : .off
        add(horizontal([details, label("Sources & account totals", size: 11, secondary: true), flexibleSpacer()]))

        if showsDetails && !snapshot.accountTotals.isEmpty {
            add(label("Account-wide tokens", size: 14, weight: .semibold))
            add(label("Provider-reported lifetime totals. Kept separate because they overlap local history.", size: 11, secondary: true))
            for account in snapshot.accountTotals {
                add(horizontal([label(account.label, size: 12, weight: .medium), flexibleSpacer(),
                                label(account.tokens.map(Self.tokens) ?? "Unavailable", size: 16, weight: .semibold)]))
                add(label(account.status, size: 11, secondary: true))
            }
            add(separator())
        }

        let tokenHeading = label("Tokens", size: 11, secondary: true)
        tokenHeading.alignment = .right
        let costHeading = label("Est. USD", size: 11, secondary: true)
        costHeading.alignment = .right
        add(horizontal([label("Models", size: 13, weight: .semibold), flexibleSpacer(), fixed(tokenHeading, width: 90),
                         fixed(costHeading, width: 102)]))
        if snapshot.rows.isEmpty {
            add(label("No usage records yet. Expand Sources & account totals to see which sources were checked.", size: 13, secondary: true))
        }
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        for row in snapshot.rows {
            let identity = NSStackView(views: [label(row.model, size: 12, weight: .medium), label(row.source, size: 10, secondary: true)])
            identity.orientation = .vertical
            identity.alignment = .leading
            identity.spacing = 3
            identity.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let count = label(Self.tokens(row.tokens.total), size: 13, weight: .medium)
            count.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            count.alignment = .right
            count.toolTip = Self.exact(row.tokens.total) + " tokens"
            let cost = label(Self.money(row.estimatedUSD), size: 13)
            cost.alignment = .right
            cost.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            let line = horizontal([identity, flexibleSpacer(), fixed(count, width: 90), fixed(cost, width: 102)])
            line.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
            line.edgeInsets = NSEdgeInsets(top: 9, left: 0, bottom: 9, right: 0)
            rows.addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            let rule = separator()
            rows.addArrangedSubview(rule)
            rule.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        add(rows)
        add(separator())
        if showsDetails {
        add(label("Coverage & estimates", size: 13, weight: .semibold))
        if let first = snapshot.firstDate {
            add(label("Available records from \(first.formatted(date: .abbreviated, time: .omitted)). Updated \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened)).", size: 11, secondary: true))
        }
        for note in snapshot.coverage { add(label(note, size: 11, secondary: true)) }
        add(label("Costs use OpenCode's recorded estimates where available; otherwise standard short-context list rates checked 17 Oct 2026. Fast mode, long contexts, cache duration, tools, discounts and historical rate changes can differ. Unknown models are unpriced, never treated as free.", size: 11, secondary: true))
        add(label("Other provider APIs currently supply quotas, not lifetime token histories. This is recorded usage, not a complete lifetime total across devices. No prompts or responses are stored by this view.", size: 11, secondary: true))
        }
        view.needsLayout = true
    }

    private func add(_ child: NSView) {
        stack.addArrangedSubview(child)
        child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.isSelectable = true
        return field
    }

    private func horizontal(_ children: [NSView]) -> NSStackView {
        let row = NSStackView(views: children)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func fixed(_ child: NSView, width: CGFloat) -> NSView {
        child.widthAnchor.constraint(equalToConstant: width).isActive = true
        return child
    }

    private func metric(title: String, value: String, detail: String) -> NSView {
        let number = label(value, size: 28, weight: .medium)
        number.font = .monospacedDigitSystemFont(ofSize: 28, weight: .medium)
        let panel = NSStackView(views: [label(title, size: 12, weight: .medium), number, label(detail, size: 11, secondary: true)])
        panel.orientation = .vertical
        panel.alignment = .leading
        panel.spacing = 8
        panel.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        return panel
    }

    private func smallMetric(_ title: String, _ count: Double) -> NSView {
        let number = label(Self.tokens(count), size: 13, weight: .medium)
        number.toolTip = Self.exact(count) + " tokens"
        let group = NSStackView(views: [label(title, size: 10, secondary: true), number])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 5
        return group
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    static func exact(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
    static func tokens(_ value: Double) -> String {
        for (threshold, suffix) in [(1_000_000_000.0, "B"), (1_000_000.0, "M"), (1_000.0, "K")] where value >= threshold {
            return (value / threshold).formatted(.number.precision(.fractionLength(2))) + suffix
        }
        return exact(value)
    }
    static func money(_ value: Double?) -> String {
        guard let value else { return "Unavailable" }
        return value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
    }

    @objc private func refreshClicked() { onRefresh?() }
    @objc private func toggleDetails() { showsDetails.toggle(); rebuild() }
}

private final class UsageHistoryDocument: NSView {
    override var isFlipped: Bool { true }
}
