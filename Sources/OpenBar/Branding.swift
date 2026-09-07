import AppKit

enum AppBranding {
    static let name = "OpenBar"
    static let bundleIdentifier = "in.4nkitd.openbar"
    static let repositoryURL = URL(string: "https://github.com/4nkitd/openbar")!
    static let issuesURL = repositoryURL.appendingPathComponent("issues")
    static let legacyBundleIdentifier = "dev.vaibhav.codexbar"

    static let logoImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "OpenBarLogo", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    /// The single pinned brand accent (#1475FC), taken from the logo's blue dot.
    static let accentColor = NSColor(srgbRed: 0x14 / 255, green: 0x75 / 255, blue: 0xFC / 255, alpha: 1)

    static func providerImage(for integration: IntegrationID) -> NSImage? {
        let resource: (String, String)
        switch integration {
        case .codex: resource = ("ProviderCodex", "pdf")
        case .claude: resource = ("ProviderClaude", "svg")
        case .openCodeGo: resource = ("ProviderOpenCode", "svg")
        case .githubCopilot: resource = ("ProviderCopilot", "pdf")
        case .antigravity: resource = ("ProviderAntigravity", "png")
        case .xai: resource = ("ProviderXAI", "svg")
        }
        guard let url = Bundle.main.url(forResource: resource.0, withExtension: resource.1) else { return nil }
        let image = NSImage(contentsOf: url)
        if integration == .codex || integration == .githubCopilot || integration == .xai { image?.isTemplate = true }
        return image
    }

    /// Integration brand color associated with the provider application.
    static func brandColor(for integration: IntegrationID) -> NSColor {
        switch integration {
        case .codex:
            return NSColor(srgbRed: 0x10 / 255.0, green: 0xA3 / 255.0, blue: 0x7F / 255.0, alpha: 1)
        case .claude:
            return NSColor(srgbRed: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0, alpha: 1)
        case .openCodeGo:
            return NSColor(srgbRed: 0x9B / 255.0, green: 0x51 / 255.0, blue: 0xE0 / 255.0, alpha: 1)
        case .githubCopilot:
            return NSColor(srgbRed: 0x58 / 255.0, green: 0xA6 / 255.0, blue: 0xFF / 255.0, alpha: 1)
        case .antigravity:
            return NSColor(srgbRed: 0x42 / 255.0, green: 0x85 / 255.0, blue: 0xF4 / 255.0, alpha: 1)
        case .xai:
            return NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(srgbRed: 0.92, green: 0.92, blue: 0.92, alpha: 1)
                    : NSColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1)
            }
        }
    }

    /// Semantic progress color: brand color (or default accent) at calm usage, orange/red as limits approach.
    static func progressColor(forUsedPercent percent: Int, integration: IntegrationID? = nil) -> NSColor {
        if percent >= 90 { return criticalColor }
        if percent >= 80 { return warningColor }
        if let integration = integration {
            return brandColor(for: integration)
        }
        return accentColor
    }

    private static let warningColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .systemOrange : NSColor(srgbRed: 0.65, green: 0.29, blue: 0, alpha: 1)
    }

    private static let criticalColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .systemRed : NSColor(srgbRed: 0.75, green: 0.08, blue: 0.10, alpha: 1)
    }
}
