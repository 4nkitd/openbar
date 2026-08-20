import AppKit

// MARK: - Symbol helpers

enum Symbols {
    static func image(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        return symbol?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
    }

    static func view(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .regular, tint: NSColor) -> NSImageView {
        let imageView = NSImageView(image: image(name, pointSize: pointSize, weight: weight) ?? NSImage())
        imageView.contentTintColor = tint
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentHuggingPriority(.required, for: .vertical)
        return imageView
    }
}

/// Spacer that always stretches first inside a stack view.
func flexibleSpacer() -> NSView {
    let view = NSView()
    view.setContentHuggingPriority(.init(1), for: .horizontal)
    view.setContentHuggingPriority(.init(1), for: .vertical)
    view.setContentCompressionResistancePriority(.init(1), for: .horizontal)
    view.setContentCompressionResistancePriority(.init(1), for: .vertical)
    return view
}

// MARK: - Progress ring

/// Circular usage ring: faint quaternary-label track + round-capped accent
/// arc, drawn from 12 o'clock clockwise. The accent is a CAShapeLayer so it
/// can tween smoothly via `setProgress(_:animated:)` during data refresh
/// without driving a continuous timer.
final class ProgressRingView: NSView {
    private var _progress: Double = 0

    var progress: Double {
        get { _progress }
        set {
            _progress = min(1, max(0, newValue))
            arcLayer.strokeEnd = CGFloat(_progress)
            updateAccessibilityValue()
        }
    }

    var ringColor: NSColor = AppBranding.accentColor {
        didSet { arcLayer.strokeColor = ringColor.cgColor }
    }

    var lineWidth: CGFloat = 11 {
        didSet {
            trackLayer.lineWidth = lineWidth
            arcLayer.lineWidth = lineWidth
            updatePaths()
        }
    }

    private let trackLayer = CAShapeLayer()
    private let arcLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        trackLayer.fillColor = NSColor.clear.cgColor
        trackLayer.strokeColor = NSColor.quaternaryLabelColor.cgColor
        trackLayer.lineCap = .round
        trackLayer.lineWidth = lineWidth
        layer?.addSublayer(trackLayer)

        arcLayer.fillColor = NSColor.clear.cgColor
        arcLayer.strokeColor = ringColor.cgColor
        arcLayer.lineCap = .round
        arcLayer.lineWidth = lineWidth
        arcLayer.strokeEnd = CGFloat(_progress)
        layer?.addSublayer(arcLayer)

        setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel("Codex usage")
        updateAccessibilityValue()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        updatePaths()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        trackLayer.strokeColor = NSColor.quaternaryLabelColor.cgColor
    }

    /// Set progress, optionally tweening the arc with a subtle ease-out.
    /// The popover calls this on refresh; the first render after load should
    /// pass `animated: false` so the user sees the actual value, not 0→value.
    func setProgress(_ value: Double, animated: Bool) {
        let v = min(1, max(0, value))
        if animated {
            let from = arcLayer.presentation()?.strokeEnd ?? arcLayer.strokeEnd
            if abs(from - CGFloat(v)) > 0.0005 {
                let anim = CABasicAnimation(keyPath: "strokeEnd")
                anim.fromValue = from
                anim.toValue = CGFloat(v)
                anim.duration = 0.32
                anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
                arcLayer.add(anim, forKey: "strokeEnd")
            }
        }
        progress = v
    }

    private func updatePaths() {
        let inset = lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return }
        let radius = min(rect.width, rect.height) / 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.path = CGPath(ellipseIn: rect, transform: nil)

        // Full circle from 12 o'clock, clockwise. `strokeEnd` (not the path
        // itself) reveals the progress fraction, so it can be tweened with a
        // CABasicAnimation on `strokeEnd` without re-tracing the path.
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let arcPath = CGMutablePath()
        let start = CGFloat.pi / 2
        arcPath.addArc(center: center, radius: radius, startAngle: start, endAngle: start - 2 * CGFloat.pi, clockwise: true)
        arcLayer.path = arcPath
        arcLayer.strokeEnd = CGFloat(_progress)
        CATransaction.commit()
    }

    private func updateAccessibilityValue() {
        setAccessibilityValue(NSNumber(value: Int(_progress * 100)))
    }
}

// MARK: - Rounded group container

/// Softly rounded tonal container for grouped rows. Depth comes from tonal
/// separation (drawn per-appearance), not shadows or borders.
final class RoundedGroupView: NSView {
    let stack = NSStackView()

    var cornerRadius: CGFloat = 10

    init(insets: NSEdgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12), spacing: CGFloat = 0) {
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.edgeInsets = insets
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func addRow(_ row: NSView) {
        stack.addArrangedSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: stack.edgeInsets.left),
            row.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -stack.edgeInsets.right)
        ])
    }

    func addDivider(leadingInset: CGFloat = 0) {
        let container = NSView()
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(divider)

        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leadingInset),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            divider.topAnchor.constraint(equalTo: container.topAnchor),
            divider.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        addRow(container)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
    }
}

// MARK: - Pill label

/// Small tonal chip (e.g. the plan badge in the popover header).
final class PillLabel: NSView {
    private let label = NSTextField(labelWithString: "")

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue; invalidateIntrinsicContentSize() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        path.fill()
    }
}

// MARK: - Thin progress bar

/// Compact linear bar used for the secondary window, subordinate to the hero ring.
final class ThinBarView: NSView {
    var progress = 0 {
        didSet { needsDisplay = true }
    }

    var barColor: NSColor = AppBranding.accentColor {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = bounds.insetBy(dx: 0, dy: 0.5)
        let track = NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2)
        NSColor.quaternaryLabelColor.setFill()
        track.fill()

        let width = bounds.width * CGFloat(min(100, max(0, progress))) / 100
        guard width > 0 else { return }

        let fillRect = NSRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
        barColor.setFill()
        fill.fill()
    }
}

// MARK: - Menu bar status icon

/// Visual state for the menu bar status item icon. `.empty` renders a dim logo
/// without the ring; `.usage` renders the ring + accent arc + inscribed logo.
enum StatusIconState: Equatable {
    case empty
    case usage(progress: Double, color: NSColor)

    static func == (lhs: StatusIconState, rhs: StatusIconState) -> Bool {
        switch (lhs, rhs) {
        case (.empty, .empty):
            return true
        case let (.usage(a, c1), .usage(b, c2)):
            return abs(a - b) < 0.001 && c1 == c2
        default:
            return false
        }
    }
}

/// Composes the menu bar status item image: a thin circular progress ring
/// with the CodexBar Lite logo inscribed inside. Rendered once per refresh
/// (no continuous animation). Light/dark-aware via NSColor.quaternaryLabelColor
/// for the ring track. Bitmap is generated at @2x for crisp Retina rendering;
/// the NSImage reports its logical point size so AppKit places it correctly.
enum StatusIconRenderer {
    /// Logical point size of the composited icon.
    static let iconSize = NSSize(width: 22, height: 22)
    private static let scale: CGFloat = 2
    private static let ringInset: CGFloat = 1.5
    private static let ringLineWidth: CGFloat = 2.0

    static func render(_ state: StatusIconState, logo: NSImage?) -> NSImage {
        let pixelWidth = Int(iconSize.width * scale)
        let pixelHeight = Int(iconSize.height * scale)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        ) else {
            return logo ?? NSImage(size: iconSize)
        }
        rep.size = iconSize

        let image = NSImage(size: iconSize)
        image.addRepresentation(rep)

        image.lockFocus()
        draw(state: state, logo: logo, bounds: NSRect(origin: .zero, size: iconSize))
        image.unlockFocus()

        return image
    }

    private static func draw(state: StatusIconState, logo: NSImage?, bounds: NSRect) {
        switch state {
        case .empty:
            drawEmpty(logo: logo, bounds: bounds)
        case let .usage(progress, color):
            drawUsage(progress: progress, color: color, logo: logo, bounds: bounds)
        }
    }

    private static func drawEmpty(logo: NSImage?, bounds: NSRect) {
        let logoSize = min(bounds.width, bounds.height) - 4
        let r = NSRect(
            x: bounds.midX - logoSize / 2,
            y: bounds.midY - logoSize / 2,
            width: logoSize,
            height: logoSize
        )
        drawLogo(in: r, logo: logo, alpha: 0.6, circular: true)
    }

    private static func drawUsage(progress: Double, color: NSColor, logo: NSImage?, bounds: NSRect) {
        let ringRect = bounds.insetBy(dx: ringInset, dy: ringInset)
        let radius = min(ringRect.width, ringRect.height) / 2 - ringLineWidth / 2
        let center = NSPoint(x: ringRect.midX, y: ringRect.midY)

        // Faint track
        let track = NSBezierPath(ovalIn: ringRect)
        track.lineWidth = ringLineWidth
        NSColor.quaternaryLabelColor.setStroke()
        track.stroke()

        // Accent arc from 12 o'clock clockwise.
        let p = min(1, max(0, progress))
        if p >= 0.9999 {
            let full = NSBezierPath(ovalIn: ringRect)
            full.lineWidth = ringLineWidth
            full.lineCapStyle = .round
            color.setStroke()
            full.stroke()
        } else if p > 0.001 {
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - 360 * p,
                clockwise: true
            )
            arc.lineWidth = ringLineWidth
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()
        }

        // Logo inscribed inside the ring.
        let logoSize = min(ringRect.width, ringRect.height) - ringLineWidth - 1.5
        let r = NSRect(
            x: center.x - logoSize / 2,
            y: center.y - logoSize / 2,
            width: logoSize,
            height: logoSize
        )
        drawLogo(in: r, logo: logo, alpha: 1.0, circular: true)
    }

    private static func drawLogo(in rect: NSRect, logo: NSImage?, alpha: CGFloat, circular: Bool) {
        guard let logo else { return }
        let clipPath: NSBezierPath = circular
            ? NSBezierPath(ovalIn: rect)
            : NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.18, yRadius: rect.height * 0.18)
        clipPath.addClip()
        logo.draw(
            in: rect,
            from: NSRect(origin: .zero, size: logo.size),
            operation: .sourceOver,
            fraction: alpha
        )
        NSGraphicsContext.current?.cgContext.resetClip()
    }
}
