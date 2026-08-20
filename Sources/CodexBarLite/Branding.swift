import AppKit

enum AppBranding {
    static let logoImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "CodexBarLiteLogo", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    /// The single pinned brand accent (#1475FC), taken from the logo's blue dot.
    static let accentColor = NSColor(srgbRed: 0x14 / 255, green: 0x75 / 255, blue: 0xFC / 255, alpha: 1)

    /// Semantic progress color: accent at calm usage, orange/red as limits approach.
    static func progressColor(forUsedPercent percent: Int) -> NSColor {
        if percent >= 90 { return .systemRed }
        if percent >= 80 { return .systemOrange }
        return accentColor
    }
}
