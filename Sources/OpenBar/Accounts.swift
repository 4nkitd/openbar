import Foundation

struct IntegrationAccount: Codable, Equatable, Identifiable {
    enum Source: String, Codable {
        case automatic
        case token
        case file
    }

    let id: String
    let integration: IntegrationID
    var label: String
    var source: Source
    var credentialPath: String?
    var isEnabled: Bool

    static func current(_ integration: IntegrationID) -> IntegrationAccount {
        IntegrationAccount(id: "default-\(integration.rawValue)", integration: integration,
                           label: integration == .githubCopilot ? "Default" : "Current login",
                           source: .automatic, credentialPath: nil, isEnabled: true)
    }

    var credentialURL: URL? {
        guard source == .file, let path = credentialPath else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    var tokenKey: String {
        id == Self.current(integration).id ? integration.rawValue : "account.\(id)"
    }

    var claudeCacheKey: String {
        id == Self.current(.claude).id ? "claude-oauth-cache" : "claude-oauth-cache.\(id)"
    }

    var ownedKeychainKeys: [String] {
        [tokenKey] + (integration == .claude ? [claudeCacheKey] : [])
    }
}

extension IntegrationID {
    var acceptsAPIToken: Bool { self == .openCodeGo || self == .githubCopilot }

    var openCodeProviderID: String? {
        switch self {
        case .codex: return "openai"
        case .claude: return "anthropic"
        case .openCodeGo: return "opencode-go"
        case .githubCopilot: return "github-copilot"
        case .xai: return "xai"
        case .antigravity: return nil
        }
    }
}
