import Foundation
import Security
import CryptoKit
import LocalAuthentication
import Darwin
import SQLite3

// Modified Swift adaptation of Headroom's HTTP adapters; see THIRD_PARTY_NOTICES.md.

enum IntegrationID: String, CaseIterable, Codable {
    case codex
    case claude
    case openCodeGo
    case githubCopilot
    case antigravity
    case xai

    var name: String {
        switch self {
        case .codex: return "OpenAI Codex"
        case .claude: return "Claude Code"
        case .openCodeGo: return "OpenCode Go"
        case .githubCopilot: return "GitHub Copilot"
        case .antigravity: return "Gemini Antigravity"
        case .xai: return "xAI Grok"
        }
    }

    var setupHint: String {
        switch self {
        case .codex: return "Sign in with codex login."
        case .claude: return "Sign in with Claude Code or OpenCode Anthropic OAuth."
        case .openCodeGo: return "Add an OpenCode Go API key below or sign in through OpenCode."
        case .githubCopilot: return "Add a GitHub token with Copilot access below."
        case .antigravity: return "Sign in with Antigravity or the OpenCode Antigravity plugin."
        case .xai: return "Sign in with OpenCode xAI OAuth or grok login."
        }
    }
}

enum UsageCadence: String, Codable {
    case session
    case daily
    case weekly
    case monthly

    var label: String {
        switch self {
        case .session: return "5-hour session"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

struct ProviderLimit: Codable {
    let cadence: UsageCadence
    let label: String?
    let usedPercent: Double
    let resetAt: Date?

    var displayLabel: String { label ?? cadence.label }
    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
}

struct ProviderUsage: Codable, Identifiable {
    let id: String
    let integration: IntegrationID
    let name: String
    let accountLabel: String?
    let plan: String
    let sourceLabel: String
    let limits: [ProviderLimit]
    let resetCredits: ResetCredits?
    var configurationID: String? = nil

    var primary: ProviderLimit { limits[0] }

    var limitingWindow: ProviderLimit { limits.max(by: { $0.usedPercent < $1.usedPercent }) ?? primary }
}

struct CodexAuth: Codable {
    var tokens: Tokens?
    var lastRefresh: String?

    struct Tokens: Codable {
        var accessToken: String?
        var refreshToken: String?
        var idToken: String?
        var accountID: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
            case accountID = "account_id"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tokens
        case lastRefresh = "last_refresh"
    }
}

struct ResetCredits: Codable {
    let availableCount: Int
    let applicableAvailableCount: Int?

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
        case applicableAvailableCount = "applicable_available_count"
    }
}

struct ConsumeResetCreditsResponse: Decodable {
    let code: String
    let windowsReset: Int

    enum CodingKeys: String, CodingKey {
        case code
        case windowsReset = "windows_reset"
    }
}

enum IntegrationError: LocalizedError {
    case notConfigured(String)
    case invalidResponse(String)
    case http(String, Int)
    case rateLimited(Date)
    case partial([ProviderUsage], String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message), .invalidResponse(let message): return message
        case .http(let provider, let status):
            if status == 401 || status == 403 { return "\(provider) access denied (HTTP \(status)). Check the token or sign in again." }
            return "\(provider) returned HTTP \(status)."
        case .rateLimited: return "Rate limited. Waiting before retrying."
        case .partial(_, let message): return message
        }
    }
}

enum CredentialStore {
    // Retain the legacy service so existing saved tokens survive the app rename.
    private static let service = "dev.vaibhav.codexbar.integrations"
    static let googleOAuthService = "in.4nkitd.openbar.oauth"
    // LAContext does not suppress legacy Keychain ACL prompts on current macOS.
    // Use the still-exported legacy policy without linking to its deprecated SDK declaration.
    private static let backgroundKeychainAccess: Bool = {
        guard let handle = dlopen(nil, RTLD_LAZY) else { return false }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "SecKeychainSetUserInteractionAllowed") else { return false }
        let setInteraction = unsafeBitCast(symbol, to: (@convention(c) (UInt8) -> Int32).self)
        return setInteraction(0) == errSecSuccess
    }()

    static func configuredToken(for account: IntegrationAccount) -> String? {
        readKeychain(service: service, account: account.tokenKey)
    }

    static func saveConfiguredToken(_ token: String, for account: IntegrationAccount) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try writeKeychain(trimmed, service: service, account: account.tokenKey)
    }

    static func clearConfiguredToken(for account: IntegrationAccount) throws {
        for key in account.ownedKeychainKeys {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                       kSecAttrService as String: service, kSecAttrAccount as String: key]
            let result = SecItemDelete(query as CFDictionary)
            guard result == errSecSuccess || result == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        }
    }

    static func openCodeGoToken() -> String? {
        if let configured = configuredToken(for: .current(.openCodeGo)) { return configured }
        if let key = openCodeV2Access(for: .openCodeGo, oauth: false, key: true) { return key }
        let paths = [
            home(".local/share/opencode/auth.json"),
            home("Library/Application Support/opencode/auth.json")
        ]
        for path in paths {
            guard let object = jsonObject(at: path),
                  let entry = object["opencode-go"] as? [String: Any],
                  let key = entry["key"] as? String,
                  !key.isEmpty else { continue }
            return key
        }
        return nil
    }

    static func claudeCredentials(for account: IntegrationAccount) -> OAuthCredentials? {
        if account.source == .file {
            guard let url = account.credentialURL, let raw = try? String(contentsOf: url, encoding: .utf8),
                  let credentials = parseClaudeCredentials(raw) else { return nil }
            return cachedClaudeCredentials(for: credentials, key: account.claudeCacheKey)
        }
        if let raw = readKeychain(service: "Claude Code-credentials", account: NSUserName()),
           let credentials = parseClaudeCredentials(raw) {
            return cachedClaudeCredentials(for: credentials, key: account.claudeCacheKey)
        }
        if let raw = try? String(contentsOf: home(".claude/.credentials.json"), encoding: .utf8), let credentials = parseClaudeCredentials(raw) {
            return cachedClaudeCredentials(for: credentials, key: account.claudeCacheKey)
        }
        if let value = openCodeV2Value(for: .claude), let access = openCodeV2Access(value, oauth: true, key: false) {
            let credentials = OAuthCredentials(
                accessToken: access,
                refreshToken: nonEmptyString(value["refresh"] ?? value["refresh_token"]) ?? "",
                expiresAtMillis: number(value["expires"])?.int64Value ?? 0
            )
            return cachedClaudeCredentials(for: credentials, key: account.claudeCacheKey)
        }
        let paths = [
            home(".local/share/opencode/auth.json"),
            home("Library/Application Support/opencode/auth.json")
        ]
        for path in paths {
            guard let object = jsonObject(at: path),
                  let entry = object["anthropic"] as? [String: Any] else { continue }
            let credentials = OAuthCredentials(
                accessToken: entry["access"] as? String ?? "",
                refreshToken: entry["refresh"] as? String ?? "",
                expiresAtMillis: number(entry["expires"])?.int64Value ?? 0
            )
            if !credentials.accessToken.isEmpty || !credentials.refreshToken.isEmpty { return cachedClaudeCredentials(for: credentials, key: account.claudeCacheKey) }
        }
        return nil
    }

    private static func cachedClaudeCredentials(for source: OAuthCredentials, key: String) -> OAuthCredentials {
        guard let raw = readKeychain(service: service, account: key),
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["sourceFingerprint"] as? String == fingerprint(source.accessToken),
              var cached = parseClaudeCredentials(raw) else { return source }
        cached.sourceFingerprint = fingerprint(source.accessToken)
        return cached
    }

    static func cacheClaudeCredentials(_ credentials: OAuthCredentials, key: String) {
        let value: [String: Any] = [
            "sourceFingerprint": credentials.sourceFingerprint,
            "claudeAiOauth": [
                "accessToken": credentials.accessToken,
                "refreshToken": credentials.refreshToken,
                "expiresAt": credentials.expiresAtMillis
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let raw = String(data: data, encoding: .utf8) else { return }
        try? writeKeychain(raw, service: service, account: key)
    }

    static func antigravityAccounts(for account: IntegrationAccount) -> [GoogleCredentials] {
        if account.source == .file {
            guard let url = account.credentialURL, let value = jsonObject(at: url) else { return [] }
            return parseGoogleAccounts(value)
        }
        var accounts: [GoogleCredentials] = []
        var seen = Set<String>()
        if let raw = readKeychain(service: "gemini", account: "antigravity"),
           let value = decodeKeychainJSON(raw) {
            let token = value["token"] as? [String: Any] ?? value
            if let refresh = token["refresh_token"] as? String, !refresh.isEmpty {
                seen.insert(refresh)
                accounts.append(GoogleCredentials(
                    label: value["email"] as? String ?? "Account \(fingerprint(refresh).prefix(6))",
                    refreshToken: refresh,
                    accessToken: token["access_token"] as? String
                ))
            }
        }
        let paths = [
            home(".local/share/opencode/antigravity-accounts.json"),
            home(".config/opencode/antigravity-accounts.json"),
            home("Library/Application Support/opencode/antigravity-accounts.json")
        ]
        for path in paths {
            guard let object = jsonObject(at: path), let values = object["accounts"] as? [[String: Any]] else { continue }
            for value in values {
                guard let refresh = value["refreshToken"] as? String, !refresh.isEmpty, seen.insert(refresh).inserted else { continue }
                accounts.append(GoogleCredentials(
                    label: value["email"] as? String ?? "Account \(fingerprint(refresh).prefix(6))",
                    refreshToken: refresh,
                    accessToken: value["accessToken"] as? String
                ))
            }
        }
        let tokenFile = home(".gemini/antigravity-cli/antigravity-oauth-token")
        if let raw = try? String(contentsOf: tokenFile, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, seen.insert(trimmed).inserted {
                accounts.append(GoogleCredentials(label: "Antigravity CLI", refreshToken: trimmed, accessToken: nil))
            }
        }
        return accounts
    }

    static func parseGoogleAccounts(_ value: [String: Any]) -> [GoogleCredentials] {
        let values = value["accounts"] as? [[String: Any]] ?? [value]
        var seen = Set<String>()
        return values.compactMap { item in
            let token = item["token"] as? [String: Any] ?? item
            let refresh = token["refresh_token"] as? String ?? token["refreshToken"] as? String ?? ""
            let access = token["access_token"] as? String ?? token["accessToken"] as? String
            guard !refresh.isEmpty || access?.isEmpty == false, seen.insert(refresh.isEmpty ? access! : refresh).inserted else { return nil }
            return GoogleCredentials(label: item["email"] as? String ?? "Account \(fingerprint(refresh.isEmpty ? access! : refresh).prefix(6))", refreshToken: refresh, accessToken: access)
        }
    }

    static func googleOAuthClients() -> [GoogleOAuthClient] {
        ["antigravity", "gemini"].compactMap { account in
            guard let value = readKeychain(service: googleOAuthService, account: "client.\(account)"), let data = value.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(GoogleOAuthClient.self, from: data)
        }
    }

    static func saveGoogleOAuthClient(_ client: GoogleOAuthClient, kind: String) throws {
        guard ["antigravity", "gemini"].contains(kind), !client.clientID.isEmpty, !client.clientSecret.isEmpty else {
            throw IntegrationError.notConfigured("Both OAuth client ID and client secret are required.")
        }
        let raw = String(decoding: try JSONEncoder().encode(client), as: UTF8.self)
        try writeKeychain(raw, service: googleOAuthService, account: "client.\(kind)")
    }

    static func importGoogleOAuthClients(environment: [String: String]) throws -> Int {
        let clients = try GoogleOAuthClient.fromEnvironment(environment)
        for (kind, client) in clients { try saveGoogleOAuthClient(client, kind: kind) }
        return clients.count
    }

    static func githubToken(for account: IntegrationAccount) -> String? {
        if let configured = configuredToken(for: account) { return configured }
        guard account.source == .automatic else { return nil }
        return openCodeV2Access(for: .githubCopilot, oauth: true, key: true)
    }

    static func openCodeCodexTokens() -> CodexAuth.Tokens? {
        guard let value = openCodeV2Value(for: .codex),
              let access = openCodeV2Access(value, oauth: true, key: false) else { return nil }
        let metadata = value["metadata"] as? [String: Any]
        return CodexAuth.Tokens(
            accessToken: access,
            refreshToken: nonEmptyString(value["refresh"] ?? value["refresh_token"]),
            idToken: nil,
            accountID: nonEmptyString(metadata?["accountID"] ?? metadata?["account_id"])
        )
    }

    static func hasOpenCodeV2Credential(for integration: IntegrationID) -> Bool {
        switch integration {
        case .codex: return openCodeCodexTokens() != nil
        case .claude: return openCodeV2Access(for: .claude, oauth: true, key: false) != nil
        case .openCodeGo: return openCodeV2Access(for: .openCodeGo, oauth: false, key: true) != nil
        case .githubCopilot: return openCodeV2Access(for: .githubCopilot, oauth: true, key: true) != nil
        case .xai: return openCodeV2Access(for: .xai, oauth: true, key: false) != nil
        case .antigravity:
            if !antigravityAccounts(for: .current(.antigravity)).isEmpty { return true }
            for url in openCodeDatabaseURLs() {
                if let value = openCodeV2Value(provider: "google", database: url),
                   openCodeV2Access(value, oauth: true, key: false) != nil { return true }
            }
            return false
        }
    }

    static func xaiAccessToken(for account: IntegrationAccount) -> String? {
        if account.source == .file {
            guard let url = account.credentialURL else { return nil }
            return parseXaiAccessToken(at: url)
        }
        let paths = openCodeDatabaseURLs() + [
            home(".local/share/opencode/auth.json"),
            home("Library/Application Support/opencode/auth.json"),
            home(".grok/auth.json")
        ]
        for path in paths {
            if let token = parseXaiAccessToken(at: path) { return token }
        }
        return nil
    }

    static func parseXaiAccessToken(at url: URL) -> String? {
        if isSQLite(url) {
            if let value = openCodeV2Value(provider: "xai", database: url) {
                return openCodeV2Access(value, oauth: true, key: false) ?? parseXaiAccessToken(value)
            }
            return nil
        }
        guard let object = jsonObject(at: url) else { return nil }
        return parseXaiAccessToken(object)
    }

    static func parseOpenCodeCredentialValue(_ object: [String: Any]) -> String? {
        openCodeV2Access(object, oauth: true, key: false)
    }

    static func openCodeV2Access(_ object: [String: Any], oauth: Bool, key: Bool) -> String? {
        let type = (object["type"] as? String)?.lowercased()
        if oauth, type == "oauth" { return nonEmptyString(object["access"] ?? object["access_token"]) }
        if key, type == "key" || type == "api" { return nonEmptyString(object["key"]) }
        return nil
    }

    static func openCodeV2Access(for integration: IntegrationID, oauth: Bool, key: Bool) -> String? {
        guard let value = openCodeV2Value(for: integration) else { return nil }
        return openCodeV2Access(value, oauth: oauth, key: key)
    }

    static func openCodeV2Value(for integration: IntegrationID) -> [String: Any]? {
        guard let provider = integration.openCodeProviderID else { return nil }
        for url in openCodeDatabaseURLs() {
            if let value = openCodeV2Value(provider: provider, database: url) { return value }
        }
        return nil
    }

    static func parseXaiAccessToken(_ object: [String: Any]) -> String? {
        if let access = parseOpenCodeCredentialValue(object) { return access }
        for key in ["xai", "xai-oauth", "grok"] {
            guard let entry = object[key] as? [String: Any] else { continue }
            if let access = parseOpenCodeCredentialValue(entry) { return access }
            let type = (entry["type"] as? String)?.lowercased()
            if type == "api" || type == "key" { continue }
            if let access = nonEmptyString(entry["access"] ?? entry["access_token"]) { return access }
        }
        var oidc: String?
        var legacy: String?
        for (scope, value) in object {
            guard let entry = value as? [String: Any], let key = nonEmptyString(entry["key"]) else { continue }
            if scope.hasPrefix("https://auth.x.ai::") { oidc = key }
            else if scope == "https://accounts.x.ai/sign-in" || scope.contains("/sign-in") { legacy = key }
        }
        return oidc ?? legacy
    }

    static func openCodeV2Value(provider: String, database url: URL) -> [String: Any]? {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
            if db != nil { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }
        let sql = "SELECT value FROM credential WHERE integration_id = ? ORDER BY CASE WHEN active = 1 THEN 0 ELSE 1 END, time_updated DESC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, provider, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_text(statement, 0) else { continue }
            let raw = String(cString: bytes)
            guard let data = raw.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            return object
        }
        return nil
    }

    private static func openCodeDatabaseURLs() -> [URL] {
        [
            home(".local/share/opencode/opencode.db"),
            home("Library/Application Support/opencode/opencode.db")
        ]
    }

    private static func isSQLite(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let prefix = (try? handle.read(upToCount: 15)) ?? Data()
        return prefix == Data("SQLite format 3".utf8)
    }

    static func codexAuthURL() -> URL { home(".codex/auth.json") }

    static func readCodexAuth(at url: URL) throws -> CodexAuth {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CodexAuth.self, from: data)
    }

    static func saveCodexAuth(_ auth: CodexAuth, at url: URL) throws {
        let data = try updatedCodexAuth(Data(contentsOf: url), auth: auth)
        try writePrivateData(data, to: url)
    }

    static func updatedCodexAuth(_ data: Data, auth: CodexAuth) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var tokens = root["tokens"] as? [String: Any], let updated = auth.tokens,
              (tokens["account_id"] as? String) == updated.accountID else {
            throw IntegrationError.invalidResponse("Codex account changed during refresh. Try again.")
        }
        tokens["access_token"] = updated.accessToken
        tokens["refresh_token"] = updated.refreshToken
        tokens["id_token"] = updated.idToken
        root["tokens"] = tokens
        root["last_refresh"] = auth.lastRefresh
        return try JSONSerialization.data(withJSONObject: root)
    }

    private static func home(_ path: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path)
    }

    private static func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func parseClaudeCredentials(_ raw: String) -> OAuthCredentials? {
        guard let data = raw.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let value = root["claudeAiOauth"] as? [String: Any] ?? root["anthropic"] as? [String: Any] ?? root
        let credentials = OAuthCredentials(
            accessToken: value["accessToken"] as? String ?? value["access"] as? String ?? "",
            refreshToken: value["refreshToken"] as? String ?? value["refresh"] as? String ?? "",
            expiresAtMillis: number(value["expiresAt"] ?? value["expires"])?.int64Value ?? 0
        )
        return credentials.accessToken.isEmpty && credentials.refreshToken.isEmpty ? nil : credentials
    }

    private static func decodeKeychainJSON(_ raw: String) -> [String: Any]? {
        let decoded: String
        if raw.hasPrefix("go-keyring-base64:"),
           let data = Data(base64Encoded: String(raw.dropFirst("go-keyring-base64:".count))),
           let value = String(data: data, encoding: .utf8) {
            decoded = value
        } else {
            decoded = raw
        }
        guard let data = decoded.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func readKeychain(service: String, account: String) -> String? {
        guard backgroundKeychainAccess else { return nil }
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: context,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound && ProcessInfo.processInfo.arguments.contains("--diagnostics") {
            FileHandle.standardError.write(Data("Keychain read failed (OSStatus \(status)).\n".utf8))
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func writeKeychain(_ value: String, service: String, account: String) throws {
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = key
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus)) }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

struct OAuthCredentials {
    var accessToken: String
    var refreshToken: String
    var expiresAtMillis: Int64
    var sourceFingerprint = ""
}

struct GoogleCredentials {
    let label: String
    let refreshToken: String
    let accessToken: String?
}

struct GoogleOAuthClient: Codable {
    let clientID: String
    let clientSecret: String

    static func fromEnvironment(_ environment: [String: String]) throws -> [(String, GoogleOAuthClient)] {
        var clients: [(String, GoogleOAuthClient)] = []
        for kind in ["antigravity", "gemini"] {
            let prefix = kind.uppercased()
            let id = environment["\(prefix)_OAUTH_CLIENT_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let secret = environment["\(prefix)_OAUTH_CLIENT_SECRET"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if id.isEmpty && secret.isEmpty { continue }
            guard !id.isEmpty && !secret.isEmpty else { throw IntegrationError.notConfigured("Provide both \(prefix) OAuth client values.") }
            clients.append((kind, GoogleOAuthClient(clientID: id, clientSecret: secret)))
        }
        guard !clients.isEmpty else { throw IntegrationError.notConfigured("No Google OAuth client credentials were supplied for local setup.") }
        return clients
    }
}

private final class NoCredentialRedirects: NSObject, URLSessionTaskDelegate {
    // Do not replay OAuth form bodies or credentials to a redirected destination.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

actor IntegrationService {
    private let session: URLSession
    private var googleTokenCache: [String: (token: String, expiresAt: Date)] = [:]

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: NoCredentialRedirects(), delegateQueue: nil)
    }

    func fetch(_ account: IntegrationAccount) async throws -> [ProviderUsage] {
        guard account.source != .file || account.credentialURL != nil else { throw IntegrationError.notConfigured("Select a credential file for this account.") }
        do {
            let providers: [ProviderUsage]
            switch account.integration {
            case .codex: providers = [try await fetchCodex(account: account)]
            case .claude: providers = [try await fetchClaude(account: account)]
            case .openCodeGo: providers = [try await fetchOpenCodeGo(account: account)]
            case .githubCopilot: providers = [try await fetchGitHubCopilot(account: account)]
            case .antigravity: providers = try await fetchAntigravity(account: account)
            case .xai: providers = [try await fetchXai(account: account)]
            }
            return providers.map { attachAccount(account, to: $0) }
        } catch IntegrationError.partial(let providers, let message) {
            throw IntegrationError.partial(providers.map { attachAccount(account, to: $0) }, message)
        }
    }

    private func attachAccount(_ account: IntegrationAccount, to usage: ProviderUsage) -> ProviderUsage {
        ProviderUsage(id: account.id + ":" + usage.id, integration: usage.integration, name: usage.name,
                      accountLabel: account.label + (usage.accountLabel.map { " · \($0)" } ?? ""),
                      plan: usage.plan, sourceLabel: usage.sourceLabel, limits: usage.limits,
                      resetCredits: usage.resetCredits, configurationID: account.id)
    }

    func consumeCodexResetCredit(account: IntegrationAccount) async throws -> ConsumeResetCreditsResponse {
        guard account.integration == .codex else { throw IntegrationError.invalidResponse("Reset credits are only supported for Codex.") }
        let tokens = try await validCodexTokens(account: account)
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(tokens.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("codex-cli/0.11.0", forHTTPHeaderField: "User-Agent")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        if let accountID = tokens.accountID, !accountID.isEmpty { request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id") }
        request.httpBody = try JSONEncoder().encode(["redeem_request_id": UUID().uuidString])
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data, provider: "Codex")
        return try JSONDecoder().decode(ConsumeResetCreditsResponse.self, from: data)
    }

    private func fetchCodex(account: IntegrationAccount) async throws -> ProviderUsage {
        var tokens = try await validCodexTokens(account: account)
        let urls = [
            URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            URL(string: "https://chatgpt.com/backend-api/codex/usage")!
        ]
        for url in urls {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(tokens.accessToken ?? "")", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("codex-cli/0.11.0", forHTTPHeaderField: "User-Agent")
            request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
            if let accountID = tokens.accountID, !accountID.isEmpty { request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id") }
            do {
                var (data, response) = try await session.data(for: request)
                if (response as? HTTPURLResponse)?.statusCode == 401 {
                    tokens = try await validCodexTokens(account: account, forceRefresh: true)
                    request.setValue("Bearer \(tokens.accessToken ?? "")", forHTTPHeaderField: "Authorization")
                    (data, response) = try await session.data(for: request)
                }
                if (response as? HTTPURLResponse)?.statusCode == 404 { continue }
                try validate(response, data: data, provider: "Codex")
                return try parseCodex(data)
            } catch { throw error }
        }
        throw IntegrationError.invalidResponse("Codex usage API is unavailable.")
    }

    private func validCodexTokens(account: IntegrationAccount, forceRefresh: Bool = false) async throws -> CodexAuth.Tokens {
        if account.source != .file,
           !FileManager.default.isReadableFile(atPath: CredentialStore.codexAuthURL().path),
           let tokens = CredentialStore.openCodeCodexTokens(),
           let access = tokens.accessToken, !access.isEmpty {
            return tokens
        }
        return try await validCodexTokens(authURL: account.credentialURL ?? CredentialStore.codexAuthURL(), forceRefresh: forceRefresh)
    }

    private func validCodexTokens(authURL: URL, forceRefresh: Bool = false) async throws -> CodexAuth.Tokens {
        var auth: CodexAuth
        do {
            auth = try CredentialStore.readCodexAuth(at: authURL)
        } catch {
            throw IntegrationError.notConfigured("Codex is not signed in.")
        }
        guard var tokens = auth.tokens, let access = tokens.accessToken, !access.isEmpty else {
            throw IntegrationError.notConfigured("Codex is not signed in.")
        }
        if forceRefresh || (jwtExpiry(access)?.timeIntervalSinceNow ?? 3600) < 60,
           let refresh = tokens.refreshToken, !refresh.isEmpty {
            var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
                "grant_type": "refresh_token",
                "refresh_token": refresh
            ])
            let (data, response) = try await session.data(for: request)
            try validate(response, data: data, provider: "Codex OAuth")
            guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let refreshedAccess = value["access_token"] as? String else {
                throw IntegrationError.invalidResponse("Codex OAuth returned invalid credentials.")
            }
            tokens.accessToken = refreshedAccess
            tokens.refreshToken = value["refresh_token"] as? String ?? refresh
            tokens.idToken = value["id_token"] as? String ?? tokens.idToken
            auth.tokens = tokens
            auth.lastRefresh = ISO8601DateFormatter().string(from: Date())
            try Task.checkCancellation()
            try CredentialStore.saveCodexAuth(auth, at: authURL)
        }
        return tokens
    }

    func parseCodex(_ data: Data) throws -> ProviderUsage {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IntegrationError.invalidResponse("Codex usage response was not JSON.")
        }
        var limits: [ProviderLimit] = []
        appendCodexWindows(value["rate_limit"] as? [String: Any], label: nil, to: &limits)
        appendCodexWindows(value["code_review_rate_limit"] as? [String: Any], label: "Code review", to: &limits)
        for item in value["additional_rate_limits"] as? [[String: Any]] ?? [] {
            let label = item["limit_name"] as? String ?? item["metered_feature"] as? String
            appendCodexWindows(item["rate_limit"] as? [String: Any], label: label?.humanized, to: &limits)
        }
        guard !limits.isEmpty else { throw IntegrationError.invalidResponse("Codex returned no usage windows.") }
        let credits: ResetCredits?
        if let raw = value["rate_limit_reset_credits"], JSONSerialization.isValidJSONObject(raw),
           let creditData = try? JSONSerialization.data(withJSONObject: raw) {
            credits = try? JSONDecoder().decode(ResetCredits.self, from: creditData)
        } else {
            credits = nil
        }
        return ProviderUsage(
            id: IntegrationID.codex.rawValue,
            integration: .codex,
            name: IntegrationID.codex.name,
            accountLabel: nil,
            plan: planLabel(value["plan_type"] as? String),
            sourceLabel: "OpenAI Codex HTTP API",
            limits: limits,
            resetCredits: credits
        )
    }

    private func appendCodexWindows(_ value: [String: Any]?, label: String?, to limits: inout [ProviderLimit]) {
        guard let value else { return }
        for key in ["primary_window", "secondary_window"] {
            guard let window = value[key] as? [String: Any], let used = number(window["used_percent"])?.doubleValue else { continue }
            let seconds = number(window["limit_window_seconds"])?.doubleValue ?? 18_000
            let cadence: UsageCadence = seconds <= 21_600 ? .session : seconds <= 172_800 ? .daily : seconds <= 777_600 ? .weekly : .monthly
            limits.append(ProviderLimit(
                cadence: cadence,
                label: label.map { "\($0) · \(cadence.label)" },
                usedPercent: used.clampedPercent,
                resetAt: dateValue(window["reset_at"])
            ))
        }
    }

    private func fetchClaude(account: IntegrationAccount) async throws -> ProviderUsage {
        guard var credentials = CredentialStore.claudeCredentials(for: account) else {
            throw IntegrationError.notConfigured("Claude Code OAuth credentials were not found.")
        }
        if credentials.accessToken.isEmpty || (credentials.expiresAtMillis > 0 && Date(timeIntervalSince1970: Double(credentials.expiresAtMillis) / 1000).timeIntervalSinceNow < 60) {
            credentials = try await refreshClaude(credentials, cacheKey: account.claudeCacheKey)
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-cli/2.1.112 (external, sdk-cli)", forHTTPHeaderField: "User-Agent")
        var (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            credentials = try await refreshClaude(credentials, cacheKey: account.claudeCacheKey)
            request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
            (data, response) = try await session.data(for: request)
        }
        try validate(response, data: data, provider: "Claude")
        return try parseClaude(data)
    }

    func parseClaude(_ data: Data) throws -> ProviderUsage {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IntegrationError.invalidResponse("Claude returned invalid quota data.")
        }
        let windows: [(String, UsageCadence, String?)] = [
            ("five_hour", .session, nil), ("seven_day", .weekly, nil),
            ("seven_day_sonnet", .weekly, "Sonnet weekly"), ("seven_day_opus", .weekly, "Opus weekly")
        ]
        let limits = windows.compactMap { key, cadence, label -> ProviderLimit? in
            guard let window = object[key] as? [String: Any], let used = number(window["utilization"])?.doubleValue else { return nil }
            return ProviderLimit(cadence: cadence, label: label, usedPercent: used.clampedPercent, resetAt: dateValue(window["resets_at"]))
        }
        guard !limits.isEmpty else { throw IntegrationError.invalidResponse("Claude returned no quota windows.") }
        return ProviderUsage(
            id: IntegrationID.claude.rawValue,
            integration: .claude,
            name: IntegrationID.claude.name,
            accountLabel: nil,
            plan: "Subscription",
            sourceLabel: "Anthropic OAuth usage API",
            limits: limits,
            resetCredits: nil
        )
    }

    private func refreshClaude(_ credentials: OAuthCredentials, cacheKey: String) async throws -> OAuthCredentials {
        guard !credentials.refreshToken.isEmpty else { throw IntegrationError.notConfigured("Claude OAuth credentials expired.") }
        var request = URLRequest(url: URL(string: "https://claude.ai/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-cli/2.1.112 (external, sdk-cli)", forHTTPHeaderField: "User-Agent")
        request.httpBody = formData([
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
        ])
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data, provider: "Claude OAuth")
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = value["access_token"] as? String else {
            throw IntegrationError.invalidResponse("Claude OAuth returned invalid credentials.")
        }
        let refreshed = OAuthCredentials(
            accessToken: access,
            refreshToken: value["refresh_token"] as? String ?? credentials.refreshToken,
            expiresAtMillis: Int64(Date().timeIntervalSince1970 * 1000) + (number(value["expires_in"])?.int64Value ?? 28_800) * 1000,
            sourceFingerprint: credentials.sourceFingerprint.isEmpty ? fingerprint(credentials.accessToken) : credentials.sourceFingerprint
        )
        try Task.checkCancellation()
        CredentialStore.cacheClaudeCredentials(refreshed, key: cacheKey)
        return refreshed
    }

    private func fetchOpenCodeGo(account: IntegrationAccount) async throws -> ProviderUsage {
        let saved = account.source == .automatic ? CredentialStore.openCodeGoToken() : CredentialStore.configuredToken(for: account)
        guard let token = saved else {
            throw IntegrationError.notConfigured("OpenCode Go API key is not configured.")
        }
        let urls = [
            URL(string: "https://opencode.ai/zen/go/v1/usage")!,
            URL(string: "https://opencode.ai/api/v1/usage/plan")!
        ]
        var lastError: Error?
        for url in urls {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await session.data(for: request)
                try validate(response, data: data, provider: "OpenCode Go")
                return try parseOpenCodeGo(data)
            } catch {
                if case IntegrationError.rateLimited = error { throw error }
                if case IntegrationError.http(_, let status) = error, status != 404 { throw error }
                lastError = error
            }
        }
        throw lastError ?? IntegrationError.invalidResponse("OpenCode Go usage API is unavailable.")
    }

    func parseOpenCodeGo(_ data: Data) throws -> ProviderUsage {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IntegrationError.invalidResponse("OpenCode Go usage response was not JSON.")
        }
        let windows = value["windows"] as? [String: Any] ?? value["usage"] as? [String: Any]
        guard let windows else { throw IntegrationError.invalidResponse("OpenCode Go returned no usage windows.") }
        let definitions: [(String, UsageCadence)] = [("rolling", .session), ("weekly", .weekly), ("monthly", .monthly)]
        let limits = definitions.compactMap { key, cadence -> ProviderLimit? in
            guard let window = windows[key] as? [String: Any] else { return nil }
            let used = number(window["usage_percent"] ?? window["percent"])?.doubleValue
            guard let used else { return nil }
            let resetAt: Date?
            if let seconds = number(window["resets_in_seconds"])?.doubleValue, (0...315_360_000).contains(seconds) {
                resetAt = Date().addingTimeInterval(seconds)
            } else {
                resetAt = dateValue(window["resetsAt"] ?? window["resetAt"])
            }
            return ProviderLimit(cadence: cadence, label: nil, usedPercent: used.clampedPercent, resetAt: resetAt)
        }
        guard !limits.isEmpty else { throw IntegrationError.invalidResponse("OpenCode Go returned no usable limits.") }
        return ProviderUsage(
            id: IntegrationID.openCodeGo.rawValue,
            integration: .openCodeGo,
            name: IntegrationID.openCodeGo.name,
            accountLabel: nil,
            plan: (value["plan"] as? String ?? "Go").uppercased(),
            sourceLabel: "OpenCode Go HTTP API",
            limits: limits,
            resetCredits: nil
        )
    }

    private func fetchGitHubCopilot(account: IntegrationAccount) async throws -> ProviderUsage {
        guard let token = CredentialStore.githubToken(for: account) else {
            throw IntegrationError.notConfigured("GitHub token is not configured.")
        }
        var request = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/user")!)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data, provider: "GitHub Copilot")
        return try parseGitHubCopilot(data)
    }

    private func fetchXai(account: IntegrationAccount) async throws -> ProviderUsage {
        guard let token = CredentialStore.xaiAccessToken(for: account) else {
            throw IntegrationError.notConfigured("xAI SuperGrok OAuth credentials were not found.")
        }
        var request = URLRequest(url: URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OpenBar", forHTTPHeaderField: "User-Agent")
        request.setValue("grok-build", forHTTPHeaderField: "x-grok-client-surface")
        request.setValue("1.0.0", forHTTPHeaderField: "x-grok-client-version")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data, provider: "xAI")
        return try parseXai(data)
    }

    func parseXai(_ data: Data) throws -> ProviderUsage {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let config = value["config"] as? [String: Any] else {
            throw IntegrationError.invalidResponse("xAI credits response was not JSON.")
        }
        let period = config["currentPeriod"] as? [String: Any]
        let hasUsage = config["creditUsagePercent"] != nil
        let hasPeriod = period != nil && (period?["type"] != nil || period?["start"] != nil || period?["end"] != nil)
        guard hasUsage || hasPeriod else { throw IntegrationError.invalidResponse("xAI returned no SuperGrok quota window.") }
        let used: Double
        if hasUsage {
            guard let percent = number(config["creditUsagePercent"])?.doubleValue else {
                throw IntegrationError.invalidResponse("xAI returned an invalid usage percentage.")
            }
            used = percent.clampedPercent
        } else {
            used = 0
        }
        let type = (period?["type"] as? String)?.uppercased() ?? ""
        let cadence: UsageCadence = type.contains("WEEK") ? .weekly : type.contains("MONTH") ? .monthly : type.contains("DAY") ? .daily : .weekly
        return ProviderUsage(
            id: IntegrationID.xai.rawValue,
            integration: .xai,
            name: IntegrationID.xai.name,
            accountLabel: nil,
            plan: "SuperGrok",
            sourceLabel: "xAI Grok credits API",
            limits: [ProviderLimit(
                cadence: cadence,
                label: nil,
                usedPercent: used,
                resetAt: dateValue(period?["end"] ?? config["billingPeriodEnd"])
            )],
            resetCredits: nil
        )
    }

    func parseGitHubCopilot(_ data: Data) throws -> ProviderUsage {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let snapshots = value["quota_snapshots"] as? [String: Any],
              let premium = snapshots["premium_interactions"] as? [String: Any],
              let entitlement = number(premium["entitlement"])?.doubleValue,
              let remaining = number(premium["remaining"])?.doubleValue,
              entitlement > 0 else {
            throw IntegrationError.invalidResponse("GitHub returned no Copilot premium-request quota.")
        }
        let used = ((entitlement - remaining) / entitlement * 100).clampedPercent
        return ProviderUsage(
            id: IntegrationID.githubCopilot.rawValue,
            integration: .githubCopilot,
            name: IntegrationID.githubCopilot.name,
            accountLabel: nil,
            plan: planLabel(value["copilot_plan"] as? String),
            sourceLabel: "GitHub Copilot HTTP API",
            limits: [ProviderLimit(
                cadence: .monthly,
                label: "Premium requests",
                usedPercent: used,
                resetAt: dateValue(value["quota_reset_date_utc"] ?? value["quota_reset_date"] ?? value["limited_user_reset_date"])
            )],
            resetCredits: nil
        )
    }

    private func fetchAntigravity(account: IntegrationAccount) async throws -> [ProviderUsage] {
        let accounts = CredentialStore.antigravityAccounts(for: account)
        guard !accounts.isEmpty else { throw IntegrationError.notConfigured("Antigravity OAuth credentials were not found.") }
        var providers: [ProviderUsage] = []
        var errors: [String] = []
        for account in accounts {
            do {
                let token = try await googleAccessToken(for: account)
                let fetched: ProviderUsage
                do {
                    fetched = try await fetchAntigravityUsage(token: token)
                } catch IntegrationError.http(_, 401) {
                    let refreshed = try await googleAccessToken(for: account, forceRefresh: true)
                    fetched = try await fetchAntigravityUsage(token: refreshed)
                }
                var usage = fetched
                usage = ProviderUsage(
                    id: "antigravity:\(fingerprint(account.refreshToken))",
                    integration: usage.integration,
                    name: usage.name,
                    accountLabel: account.label,
                    plan: usage.plan,
                    sourceLabel: usage.sourceLabel,
                    limits: usage.limits,
                    resetCredits: nil
                )
                providers.append(usage)
            } catch {
                if case IntegrationError.rateLimited = error { throw error }
                try Task.checkCancellation()
                errors.append(error.localizedDescription)
            }
        }
        guard !providers.isEmpty else { throw IntegrationError.invalidResponse(errors.first ?? "Antigravity quota is unavailable.") }
        if !errors.isEmpty { throw IntegrationError.partial(providers, "\(errors.count) account(s) unavailable. \(errors[0])") }
        return providers
    }

    private func googleAccessToken(for account: GoogleCredentials, forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let cached = googleTokenCache[account.refreshToken], cached.expiresAt.timeIntervalSinceNow > 60 { return cached.token }
        if !forceRefresh, let token = account.accessToken, !token.isEmpty { return token }
        let environment = ProcessInfo.processInfo.environment
        let savedClients = CredentialStore.googleOAuthClients().map { ($0.clientID, $0.clientSecret) }
        if ProcessInfo.processInfo.arguments.contains("--diagnostics") {
            FileHandle.standardError.write(Data("Google OAuth: \(savedClients.count) local client configuration(s) available.\n".utf8))
        }
        let clients: [(String, String)] = savedClients + ["ANTIGRAVITY", "GEMINI"].compactMap { prefix in
            guard let id = environment["\(prefix)_OAUTH_CLIENT_ID"], !id.isEmpty,
                  let secret = environment["\(prefix)_OAUTH_CLIENT_SECRET"], !secret.isEmpty else { return nil }
            return (id, secret)
        }
        guard !clients.isEmpty else {
            throw IntegrationError.notConfigured("OAuth setup required. Open Integrations → Antigravity → Configure OAuth.")
        }
        for (clientID, clientSecret) in clients {
            try Task.checkCancellation()
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formData([
                "client_id": clientID,
                "client_secret": clientSecret,
                "grant_type": "refresh_token",
                "refresh_token": account.refreshToken
            ])
            let (data, response) = try await session.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 400 { continue }
            try validate(response, data: data, provider: "Google OAuth")
            guard
                  let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = value["access_token"] as? String else { continue }
            let expires = number(value["expires_in"])?.doubleValue ?? 3600
            googleTokenCache[account.refreshToken] = (token, Date().addingTimeInterval(expires))
            return token
        }
        throw IntegrationError.invalidResponse("Could not refresh Antigravity credentials.")
    }

    private func fetchAntigravityUsage(token: String) async throws -> ProviderUsage {
        let headers = [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json",
            "User-Agent": "antigravity",
            "X-Goog-Api-Client": "google-cloud-sdk vscode_cloudshelleditor/0.1",
            "Client-Metadata": "{\"ideType\":\"ANTIGRAVITY\",\"platform\":\"MACOS\",\"pluginType\":\"GEMINI\"}"
        ]
        let metadata: [String: Any] = ["metadata": ["ideType": "IDE_UNSPECIFIED", "platform": "PLATFORM_UNSPECIFIED", "pluginType": "GEMINI"]]
        let endpoints = ["https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal", "https://cloudcode-pa.googleapis.com/v1internal"]
        var lastError: Error?
        for endpoint in endpoints {
            do {
                let load = try await postJSON("\(endpoint):loadCodeAssist", headers: headers, body: metadata)
                let project = load["cloudaicompanionProject"] as? String
                let body: [String: Any] = project.map { ["project": $0] } ?? [:]
                do {
                    let summary = try await postJSON("\(endpoint):retrieveUserQuotaSummary", headers: headers, body: body)
                    return try parseAntigravitySummary(load: load, summary: summary)
                } catch {
                    if case IntegrationError.rateLimited = error { throw error }
                    if case IntegrationError.http(_, 401) = error { throw error }
                    try Task.checkCancellation()
                }
                let quota = try await postJSON("\(endpoint):retrieveUserQuota", headers: headers, body: body)
                return try parseAntigravityQuota(load: load, quota: quota)
            } catch {
                if case IntegrationError.rateLimited = error { throw error }
                if case IntegrationError.http(_, 401) = error { throw error }
                try Task.checkCancellation()
                lastError = error
            }
        }
        throw lastError ?? IntegrationError.invalidResponse("Antigravity quota is unavailable.")
    }

    func parseAntigravitySummary(load: [String: Any], summary: [String: Any]) throws -> ProviderUsage {
        guard let groups = summary["groups"] as? [[String: Any]] else { throw IntegrationError.invalidResponse("Antigravity returned no quota groups.") }
        var limits: [ProviderLimit] = []
        for group in groups {
            let groupName = group["displayName"] as? String ?? "Models"
            let prefix = groupName.localizedCaseInsensitiveContains("Gemini") ? "Gemini" : "Claude/GPT"
            for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                guard let remaining = number(bucket["remainingFraction"])?.doubleValue else { continue }
                let window = bucket["window"] as? String
                let cadence: UsageCadence
                switch window {
                case "5h", "5h0m0s", "18000s": cadence = .session
                case "weekly", "7d", "604800s": cadence = .weekly
                default: continue
                }
                limits.append(ProviderLimit(
                    cadence: cadence,
                    label: "\(prefix) \(cadence.label)",
                    usedPercent: (100 - remaining * 100).clampedPercent,
                    resetAt: dateValue(bucket["resetTime"] ?? bucket["reset_time"])
                ))
            }
        }
        guard !limits.isEmpty else { throw IntegrationError.invalidResponse("Antigravity returned no usable quota buckets.") }
        return antigravityProvider(load: load, limits: limits)
    }

    func parseAntigravityQuota(load: [String: Any], quota: [String: Any]) throws -> ProviderUsage {
        var buckets: [(String, Double, Date?)] = []
        collectRemainingFractions(quota, inheritedLabel: "Models", into: &buckets)
        if buckets.isEmpty { collectRemainingFractions(load, inheritedLabel: "Models", into: &buckets) }
        var seen = Set<String>()
        let limits = buckets.compactMap { label, remaining, reset -> ProviderLimit? in
            guard seen.insert(label).inserted else { return nil }
            return ProviderLimit(
                cadence: .daily,
                label: label.humanized,
                usedPercent: (100 - remaining * 100).clampedPercent,
                resetAt: reset
            )
        }
        guard !limits.isEmpty else { throw IntegrationError.invalidResponse("Antigravity returned no model quota.") }
        return antigravityProvider(load: load, limits: limits)
    }

    private func antigravityProvider(load: [String: Any], limits: [ProviderLimit]) -> ProviderUsage {
        let tier = ((load["currentTier"] as? [String: Any])?["name"] as? String)
            ?? ((load["planInfo"] as? [String: Any])?["planType"] as? String)
            ?? "Antigravity"
        return ProviderUsage(
            id: IntegrationID.antigravity.rawValue,
            integration: .antigravity,
            name: IntegrationID.antigravity.name,
            accountLabel: nil,
            plan: tier,
            sourceLabel: "Google Code Assist HTTP API",
            limits: limits,
            resetCredits: nil
        )
    }

    private func collectRemainingFractions(_ value: Any, inheritedLabel: String, into output: inout [(String, Double, Date?)]) {
        if let dictionary = value as? [String: Any] {
            let label = dictionary["modelId"] as? String ?? inheritedLabel
            if let remaining = number(dictionary["remainingFraction"])?.doubleValue {
                output.append((label, remaining, dateValue(dictionary["resetTime"] ?? dictionary["reset_time"])))
            }
            for (key, child) in dictionary {
                let next = ["quotaInfo", "quota", "models", "buckets"].contains(key) || dictionary["modelId"] != nil || inheritedLabel != "Models" ? label : key
                collectRemainingFractions(child, inheritedLabel: next, into: &output)
            }
        } else if let array = value as? [Any] {
            for child in array { collectRemainingFractions(child, inheritedLabel: inheritedLabel, into: &output) }
        }
    }

    private func postJSON(_ url: String, headers: [String: String], body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data, provider: "Google Code Assist")
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IntegrationError.invalidResponse("Google Code Assist response was not JSON.")
        }
        return value
    }

    func validate(_ response: URLResponse, data: Data, provider: String) throws {
        guard let http = response as? HTTPURLResponse else { throw IntegrationError.invalidResponse("\(provider) returned an invalid response.") }
        if http.statusCode == 429 {
            let retry = http.value(forHTTPHeaderField: "Retry-After")
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            let seconds = retry.flatMap(Double.init).flatMap { $0.isFinite && (0...31_536_000).contains($0) ? $0 : nil }
            let deadline = seconds.map { Date().addingTimeInterval(max(60, $0)) }
                ?? retry.flatMap { formatter.date(from: $0) } ?? Date().addingTimeInterval(300)
            throw IntegrationError.rateLimited(deadline)
        }
        guard (200..<300).contains(http.statusCode) else { throw IntegrationError.http(provider, http.statusCode) }
        if String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<html") == true {
            throw IntegrationError.invalidResponse("\(provider) returned an HTML challenge.")
        }
    }

    private func formData(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return fields.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&").data(using: .utf8) ?? Data()
    }
}

private func number(_ value: Any?) -> NSNumber? {
    if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite { return number }
    if let string = value as? String, let double = Double(string), double.isFinite { return NSNumber(value: double) }
    return nil
}

private func nonEmptyString(_ value: Any?) -> String? {
    guard let string = value as? String else { return nil }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func fingerprint(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}

func writePrivateData(_ data: Data, to url: URL) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let temporary = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
    guard fm.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    defer { try? fm.removeItem(at: temporary) }
    guard rename(temporary.path, url.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}

private func dateValue(_ value: Any?) -> Date? {
    if let number = number(value) {
        let timestamp = number.doubleValue
        let seconds = timestamp > 1_000_000_000_000 ? timestamp / 1000 : timestamp
        guard (0...253_402_300_799).contains(seconds) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
    guard let string = value as? String else { return nil }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: string) { return date }
    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: string) { return date }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: string)
}

private func jwtExpiry(_ token: String) -> Date? {
    let parts = token.split(separator: ".")
    guard parts.count > 1 else { return nil }
    var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
    guard let data = Data(base64Encoded: payload),
          let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let expiration = number(value["exp"])?.doubleValue else { return nil }
    return Date(timeIntervalSince1970: expiration)
}

private func planLabel(_ value: String?) -> String {
    switch value?.lowercased() {
    case "pro", "prolite": return "Pro"
    case "plus": return "Plus"
    case "team", "business": return "Business"
    case "individual_pro": return "Pro"
    case "individual_free": return "Free"
    case "enterprise": return "Enterprise"
    case let value?: return value.humanized
    case nil: return "Subscription"
    }
}

private extension Double {
    var clampedPercent: Double { max(0, min(100, self)) }
}

private extension String {
    var humanized: String {
        split(whereSeparator: { $0 == "_" || $0 == "-" })
            .map { part in
                let lower = part.lowercased()
                if ["gpt", "api"].contains(lower) { return lower.uppercased() }
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }
}
