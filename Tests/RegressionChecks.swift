import AppKit
import Foundation

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private final class CheckAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(description: message) }
}

private func json(_ value: String) -> Data { Data(value.utf8) }

private func sample(_ id: IntegrationID, account: String? = nil, used: Double = 27) -> ProviderUsage {
    ProviderUsage(
        id: id.rawValue + (account ?? ""), integration: id, name: id.name,
        accountLabel: account, plan: "Pro", sourceLabel: "First-party quota API",
        limits: [
            ProviderLimit(cadence: .session, label: nil, usedPercent: used, resetAt: Date().addingTimeInterval(7200)),
            ProviderLimit(cadence: .weekly, label: nil, usedPercent: 81, resetAt: Date().addingTimeInterval(172800))
        ], resetCredits: nil
    )
}

private actor FetchProbe {
    var calls: [String: Int] = [:]
    var gates: [String: CheckedContinuation<[ProviderUsage], Error>] = [:]

    func fetch(_ account: IntegrationAccount) async throws -> [ProviderUsage] {
        let id = account.id
        calls[id, default: 0] += 1
        return try await withCheckedThrowingContinuation { gates[id] = $0 }
    }

    func complete(_ id: String, _ result: Result<[ProviderUsage], Error>) {
        gates.removeValue(forKey: id)?.resume(with: result)
    }
}

private final class AccountHTTPProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        let accountID = request.value(forHTTPHeaderField: "chatgpt-account-id")
        let personal = authorization == "Bearer personal-token" && accountID == "personal"
        let work = authorization == "Bearer work-token" && accountID == "work"
        let permitted = request.url?.host == "chatgpt.com" && (personal || work)
        let response = HTTPURLResponse(url: request.url!, statusCode: permitted ? 200 : 403, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        let body = json("{\"plan_type\":\"pro\",\"rate_limit\":{\"primary_window\":{\"used_percent\":\(personal ? 17 : 43),\"limit_window_seconds\":18000}}}")
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class XaiHTTPProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let authorized = request.url?.host == "cli-chat-proxy.grok.com"
            && request.value(forHTTPHeaderField: "Authorization") == "Bearer grok-oauth-token"
        let response = HTTPURLResponse(url: request.url!, statusCode: authorized ? 200 : 403, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        let body = json(#"{"config":{"creditUsagePercent":42,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-07-14T10:46:52Z"}}}"#)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
private struct RegressionChecks {
    @MainActor static func main() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let service = IntegrationService()
        let codex = try await service.parseCodex(json(#"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":27,"limit_window_seconds":18000,"reset_at":1788780000},"secondary_window":{"used_percent":81,"limit_window_seconds":604800,"reset_at":1789200000}},"additional_rate_limits":[{"limit_name":"spark","rate_limit":{"primary_window":{"used_percent":2,"limit_window_seconds":18000},"secondary_window":{"used_percent":8,"limit_window_seconds":604800}}}]}"#))
        try check(codex.limits.count == 4, "All Codex windows must be parsed")
        try check(codex.limitingWindow.usedPercent == 81, "Weekly exhaustion must not hide behind a healthy session")
        try check(codex.limits[2].displayLabel != codex.limits[3].displayLabel, "Custom windows need cadence labels")
        let claude = try await service.parseClaude(json(#"{"five_hour":{"utilization":15,"resets_at":"2026-10-01T01:00:00Z"},"seven_day":{"utilization":40,"resets_at":null},"seven_day_sonnet":null}"#))
        try check(claude.limits.map(\.usedPercent) == [15, 40], "Claude utilization is already a percentage")
        try check(claude.limits[1].resetAt == nil, "Missing reset must remain unknown")
        let go = try await service.parseOpenCodeGo(json(#"{"windows":{"rolling":{"usage_percent":65,"resets_in_seconds":7200},"weekly":{"usage_percent":30,"resets_in_seconds":432000},"monthly":{"usage_percent":12,"resets_in_seconds":1209600}}}"#))
        try check(go.limits.map(\.remainingPercent) == [35, 70, 88], "Go remaining quota must not be inverted")
        let alternate = try await service.parseOpenCodeGo(json(#"{"usage":{"rolling":{"percent":"25","resetsAt":"2026-10-01T00:00:00.000Z"}}}"#))
        try check(alternate.primary.usedPercent == 25 && alternate.primary.resetAt != nil, "Alternate Go schema")
        let xai = try await service.parseXai(json(#"{"config":{"creditUsagePercent":75,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-07-07T10:46:52.885620+00:00","end":"2026-07-14T10:46:52.885620+00:00"}}}"#))
        try check(xai.primary.usedPercent == 75 && xai.primary.cadence == .weekly && xai.primary.resetAt != nil, "xAI weekly credits percent and reset")
        let xaiZero = try await service.parseXai(json(#"{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-07-14T10:46:52Z"}}}"#))
        try check(xaiZero.primary.usedPercent == 0, "Omitted xAI percent with a period is unused, not missing")
        let xaiMonthly = try await service.parseXai(json(#"{"config":{"creditUsagePercent":"12","billingPeriodEnd":"2026-08-01T00:00:00Z","currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY"}}}"#))
        try check(xaiMonthly.primary.cadence == .monthly && xaiMonthly.primary.resetAt != nil, "xAI monthly period and billingPeriodEnd fallback")
        do {
            _ = try await service.parseXai(json(#"{"config":{"creditUsagePercent":"NaN"}}"#))
            throw CheckFailure(description: "Nonfinite xAI usage accepted")
        } catch is IntegrationError {}
        try check(CredentialStore.parseXaiAccessToken(["xai": ["type": "oauth", "access": "grok-oauth-token"]]) == "grok-oauth-token", "OpenCode xAI OAuth access")
        try check(CredentialStore.parseXaiAccessToken(["xai": ["type": "api", "key": "xai-inference"]]) == nil, "xAI inference keys are not SuperGrok quota")
        try check(CredentialStore.parseXaiAccessToken(["opencode-go": ["type": "api", "key": "go-key"], "anthropic": ["type": "oauth", "access": "claude"]]) == nil, "Must not take another provider's key from auth.json")
        try check(CredentialStore.parseXaiAccessToken(["https://auth.x.ai::openid profile": ["key": "grok-cli-token"]]) == "grok-cli-token", "Grok CLI OIDC auth.json")
        try check(CredentialStore.parseOpenCodeCredentialValue(["type": "oauth", "methodID": "device", "access": "v2-oauth", "refresh": "r"]) == "v2-oauth", "OpenCode V2 credential JSON")
        try check(CredentialStore.parseOpenCodeCredentialValue(["type": "key", "key": "xai-inference"]) == nil, "OpenCode V2 API keys are not SuperGrok quota")
        try check(CredentialStore.openCodeV2Access(["type": "key", "key": "go-key"], oauth: false, key: true) == "go-key", "OpenCode V2 Go API key")
        let seeded = SettingsStore.importedOpenCodeAccounts(existing: [.current(.codex)], available: [.xai, .openCodeGo, .githubCopilot, .codex])
        try check(Set(seeded.enable) == [.xai, .openCodeGo, .githubCopilot, .codex], "OpenCode V2 import enables missing and unused current-login providers")
        try check(seeded.accounts.contains(where: { $0.integration == .githubCopilot && $0.source == .automatic }), "GitHub Copilot current login is created from OpenCode V2")
        let already = SettingsStore.importedOpenCodeAccounts(existing: [.current(.xai)], available: [.xai], alreadyImported: [.xai])
        try check(already.enable.isEmpty && already.accounts.count == 1, "A completed OpenCode import is not repeated")
        let firstRun = SettingsStore.importedOpenCodeAccounts(existing: IntegrationID.allCases.map(IntegrationAccount.current), available: [.xai, .githubCopilot])
        try check(Set(firstRun.enable) == [.xai, .githubCopilot], "Current-login defaults are turned on when OpenCode V2 has them")
        let tokenAccount = IntegrationAccount(id: "gh", integration: .githubCopilot, label: "Work", source: .token, credentialPath: nil, isEnabled: false)
        let custom = SettingsStore.importedOpenCodeAccounts(existing: [tokenAccount], available: [.githubCopilot])
        try check(custom.enable.isEmpty && custom.accounts.count == 1, "Do not override a GitHub token account the user already added")
        let copilot = try await service.parseGitHubCopilot(json(#"{"copilot_plan":"individual_pro","quota_reset_date":"2026-10-01","quota_snapshots":{"chat":{"entitlement":-1,"remaining":-1},"premium_interactions":{"entitlement":1500,"remaining":-300}}}"#))
        try check(copilot.primary.remainingPercent == 0, "Overage must show exhausted, not negative remaining")
        try check(copilot.primary.resetAt != nil, "Copilot date-only reset")
        let load: [String: Any] = ["currentTier": ["name": "Pro"]]
        let summary: [String: Any] = ["groups": [["displayName": "Gemini Models", "buckets": [
            ["window": "5h", "remainingFraction": 0.92], ["window": "weekly", "remainingFraction": 0.78]
        ]]]]
        let google = try await service.parseAntigravitySummary(load: load, summary: summary)
        try check(google.limits.map(\.remainingPercent) == [92, 78], "Antigravity summary fractions")
        let fallback: [String: Any] = ["models": ["gemini-3-flash": ["quotaInfo": ["remainingFraction": 0.41]]]]
        let quota = try await service.parseAntigravityQuota(load: load, quota: fallback)
        try check(quota.primary.displayLabel == "Gemini 3 Flash", "Structural wrappers must not replace model labels")
        do {
            _ = try await service.parseOpenCodeGo(json(#"{"usage":{"rolling":{"percent":"NaN"}}}"#))
            throw CheckFailure(description: "Nonfinite usage accepted")
        } catch is IntegrationError {}
        let original = json(#"{"auth_mode":"chatgpt","unknown":{"keep":true},"tokens":{"access_token":"old","refresh_token":"r","account_id":"account","custom":"preserve"}}"#)
        let auth = CodexAuth(tokens: .init(accessToken: "new", refreshToken: "r2", idToken: nil, accountID: "account"), lastRefresh: "now")
        let merged = try JSONSerialization.jsonObject(with: CredentialStore.updatedCodexAuth(original, auth: auth)) as! [String: Any]
        try check(merged["auth_mode"] as? String == "chatgpt" && merged["unknown"] != nil, "Do not strip unknown Codex metadata")
        try check((merged["tokens"] as? [String: Any])?["custom"] as? String == "preserve", "Preserve unknown token fields")
        var switched = auth
        switched.tokens?.accountID = "another-account"
        do {
            _ = try CredentialStore.updatedCodexAuth(original, auth: switched)
            throw CheckFailure(description: "Concurrent account switch was overwritten")
        } catch is IntegrationError {}
        let retryResponse = HTTPURLResponse(url: URL(string: "https://api.github.com/copilot_internal/user")!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "900"])!
        do {
            try await service.validate(retryResponse, data: Data(), provider: "Copilot")
            throw CheckFailure(description: "Rate limit was accepted")
        } catch IntegrationError.rateLimited(let deadline) {
            try check(deadline.timeIntervalSinceNow > 895, "Parse Retry-After header")
        }
        print("PASS response parsers, malformed data, auth metadata preservation")
        let clients = try GoogleOAuthClient.fromEnvironment(["ANTIGRAVITY_OAUTH_CLIENT_ID": "fixture-id", "ANTIGRAVITY_OAUTH_CLIENT_SECRET": "fixture-secret"])
        try check(clients.count == 1 && clients[0].0 == "antigravity", "Local OAuth setup validates a complete client pair")
        do {
            _ = try GoogleOAuthClient.fromEnvironment(["GEMINI_OAUTH_CLIENT_ID": "fixture-id"])
            throw CheckFailure(description: "Incomplete client pair accepted")
        } catch IntegrationError.notConfigured {}

        let probe = FetchProbe()
        let codexAccount = IntegrationAccount.current(.codex)
        let claudeAccount = IntegrationAccount.current(.claude)
        let cache = QuotaCache(url: output.appendingPathComponent("test-cache-\(UUID().uuidString).json"))
        let store = QuotaStore(cache: cache) { try await probe.fetch($0) }
        var fresh = 0
        store.onFresh = { _ in fresh += 1 }
        store.setAccounts([codexAccount, claudeAccount])
        await store.restore()
        store.refresh()
        try await wait { await probe.calls.count == 2 }
        await probe.complete(codexAccount.id, .success([codex]))
        try await wait { store.states[codexAccount.id]?.isRefreshing == false }
        try check(store.states[claudeAccount.id]?.isRefreshing == true, "Fast provider must render before slow provider")
        try check(fresh == 1, "Fresh notification only")
        store.refresh()
        let codexCalls = await probe.calls[codexAccount.id]
        try check(codexCalls == 1, "Manual refresh must obey cooldown")
        store.setAccounts([codexAccount])
        await probe.complete(claudeAccount.id, .success([claude]))
        try await Task.sleep(nanoseconds: 20_000_000)
        try check(store.states[claudeAccount.id] == nil, "Disabled account's late response must be ignored")
        store.refresh(now: Date().addingTimeInterval(61))
        try await wait { await probe.calls[codexAccount.id] == 2 }
        let retryDate = Date().addingTimeInterval(1200)
        await probe.complete(codexAccount.id, .failure(IntegrationError.rateLimited(retryDate)))
        try await wait { store.states[codexAccount.id]?.isRefreshing == false }
        try check(store.states[codexAccount.id]?.updatedAt != nil && fresh == 1, "Network failure retains timestamp, never notifies from cache")
        try check(store.states[codexAccount.id]!.retryAt! >= retryDate, "Respect server Retry-After")
        store.credentialsChanged(codexAccount.id)
        try await wait { await probe.calls[codexAccount.id] == 3 }
        try check(store.states[codexAccount.id]?.providers.isEmpty == true, "Credential changes invalidate old account cache")
        await probe.complete(codexAccount.id, .success([codex]))
        try await wait { store.states[codexAccount.id]?.isRefreshing == false }
        let saved = await cache.load()
        try check(saved.allSatisfy { !$0.providers.isEmpty }, "Cache contains complete quota entries")
        print("PASS progressive refresh, cancellation, cooldown, backoff, credential invalidation")

        let personalPath = output.appendingPathComponent("personal-auth.json")
        let workPath = output.appendingPathComponent("work-auth.json")
        try writePrivateData(json(#"{"tokens":{"access_token":"personal-token","account_id":"personal"}}"#), to: personalPath)
        try writePrivateData(json(#"{"tokens":{"access_token":"work-token","account_id":"work"}}"#), to: workPath)
        let personal = IntegrationAccount(id: "personal", integration: .codex, label: "Personal", source: .file, credentialPath: personalPath.path, isEnabled: true)
        let work = IntegrationAccount(id: "work", integration: .codex, label: "Work", source: .file, credentialPath: workPath.path, isEnabled: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountHTTPProtocol.self]
        let isolatedService = IntegrationService(configuration: configuration)
        let personalUsage = try await isolatedService.fetch(personal)
        let workUsage = try await isolatedService.fetch(work)
        try check(personalUsage[0].primary.usedPercent == 17 && workUsage[0].primary.usedPercent == 43, "HTTP requests must use each account's credentials and account ID")
        try check(personalUsage[0].id != workUsage[0].id && workUsage[0].configurationID == work.id, "Quota identity must be account-scoped")
        let xaiAuthPath = output.appendingPathComponent("xai-auth.json")
        try writePrivateData(json(#"{"xai":{"type":"oauth","access":"grok-oauth-token"}}"#), to: xaiAuthPath)
        let xaiAccount = IntegrationAccount(id: "xai-personal", integration: .xai, label: "Grok", source: .file, credentialPath: xaiAuthPath.path, isEnabled: true)
        let xaiConfiguration = URLSessionConfiguration.ephemeral
        xaiConfiguration.protocolClasses = [XaiHTTPProtocol.self]
        let xaiService = IntegrationService(configuration: xaiConfiguration)
        let xaiUsage = try await xaiService.fetch(xaiAccount)
        try check(xaiUsage[0].primary.usedPercent == 42 && xaiUsage[0].configurationID == xaiAccount.id, "xAI HTTP must use the selected auth file")
        let xaiGoOnly = output.appendingPathComponent("opencode-go-only.json")
        try writePrivateData(json(#"{"opencode-go":{"type":"api","key":"go-key"}}"#), to: xaiGoOnly)
        let xaiWrongFile = IntegrationAccount(id: "xai-wrong", integration: .xai, label: "Wrong file", source: .file, credentialPath: xaiGoOnly.path, isEnabled: true)
        do {
            _ = try await xaiService.fetch(xaiWrongFile)
            throw CheckFailure(description: "xAI accepted a non-xAI credential file")
        } catch IntegrationError.notConfigured {}
        let xaiDB = output.appendingPathComponent("opencode.db")
        try writeOpenCodeCredentialDB(to: xaiDB, integration: "xai", value: #"{"type":"oauth","methodID":"device","access":"grok-oauth-token","refresh":"r"}"#)
        try check(CredentialStore.parseXaiAccessToken(at: xaiDB) == "grok-oauth-token", "OpenCode V2 sqlite xAI OAuth")
        let xaiDBAccount = IntegrationAccount(id: "xai-db", integration: .xai, label: "V2", source: .file, credentialPath: xaiDB.path, isEnabled: true)
        let xaiDBUsage = try await xaiService.fetch(xaiDBAccount)
        try check(xaiDBUsage[0].primary.usedPercent == 42, "xAI HTTP must use OpenCode V2 database credentials")
        let otherDB = output.appendingPathComponent("other.db")
        try writeOpenCodeCredentialDB(to: otherDB, integration: "opencode-go", value: #"{"type":"key","key":"go-key"}"#)
        try check(CredentialStore.parseXaiAccessToken(at: otherDB) == nil, "Must not read another integration from OpenCode sqlite")
        try check(personal.tokenKey != work.tokenKey && personal.claudeCacheKey != work.claudeCacheKey, "Secret and OAuth caches must be isolated")
        for integration in [IntegrationID.claude, .antigravity, .xai] {
            let missing = IntegrationAccount(id: UUID().uuidString, integration: integration, label: "Missing file", source: .file, credentialPath: output.appendingPathComponent(UUID().uuidString).path, isEnabled: true)
            do {
                _ = try await isolatedService.fetch(missing)
                throw CheckFailure(description: "Explicit file account fell back to another login")
            } catch IntegrationError.notConfigured {}
        }
        let claudeCleanup = IntegrationAccount.current(.claude)
        try check(claudeCleanup.ownedKeychainKeys == [claudeCleanup.tokenKey, claudeCleanup.claudeCacheKey], "Claude cleanup must include its OAuth cache")
        let multiProbe = FetchProbe()
        let multiStore = QuotaStore(cache: QuotaCache(url: output.appendingPathComponent(UUID().uuidString))) { try await multiProbe.fetch($0) }
        multiStore.setAccounts([personal, work])
        await multiStore.restore()
        multiStore.refresh()
        try await wait { await multiProbe.calls.count == 2 }
        await multiProbe.complete(work.id, .failure(IntegrationError.http("Codex", 403)))
        await multiProbe.complete(personal.id, .success(personalUsage))
        try await wait { multiStore.states[personal.id]?.isRefreshing == false && multiStore.states[work.id]?.isRefreshing == false }
        try check(multiStore.presentationStates[.codex]?.providers.count == 1, "A failed account must not hide another account")
        try check(multiStore.presentationStates[.codex]?.accountStatuses[work.id]?.message != nil, "Failed accounts retain separate status")
        multiStore.credentialsChanged(work.id)
        try check(multiStore.states[personal.id]?.providers.count == 1, "Editing Work must not clear Personal")
        try await wait { await multiProbe.calls[work.id] == 2 }
        multiStore.setAccounts([personal])
        await multiProbe.complete(work.id, .success(workUsage))
        try await Task.sleep(nanoseconds: 20_000_000)
        try check(multiStore.states[work.id] == nil, "Removed account must not reappear from a late response")
        let migrated = SettingsStore.migratedPreferences(current: ["displayMode": "used"], legacy: ["displayMode": "remaining", "integration.claude.enabled": true, "unrelated": "ignore"])
        try check(migrated["displayMode"] as? String == "used" && migrated["integration.claude.enabled"] as? Bool == true && migrated["unrelated"] == nil, "Rebrand migration preserves new choices and copies only known preferences")
        let oldCache = output.appendingPathComponent("old-cache.json")
        let newCache = output.appendingPathComponent("migrated-\(UUID().uuidString).json")
        try writePrivateData(JSONEncoder().encode([CachedQuota(integration: .codex, providers: [codex], updatedAt: Date())]), to: oldCache)
        let migrationCache = QuotaCache(url: newCache, legacyURL: oldCache)
        let migratedEntries = await migrationCache.load()
        try check(migratedEntries.count == 1 && FileManager.default.fileExists(atPath: oldCache.path) && FileManager.default.fileExists(atPath: newCache.path), "Cache migration copies readings without deleting legacy data")
        print("PASS multi-account HTTP credential routing, failure isolation, removal and rebrand migration")

        let app = NSApplication.shared
        let appDelegate = CheckAppDelegate()
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
        let controller = UsagePopoverViewController()
        let enabled = IntegrationID.allCases
        let providers = [codex, claude, go, copilot, google, xai]
        var states = Dictionary(uniqueKeysWithValues: zip(enabled, providers).map { ($0, IntegrationState(providers: [$1], updatedAt: Date())) })
        states[.antigravity]?.providers = [sample(.antigravity, account: "personal@example.test", used: 8), sample(.antigravity, account: "work@example.test", used: 12)]
        let start = ProcessInfo.processInfo.systemUptime
        controller.update(states: states, enabled: enabled, displayMode: .remaining)
        let firstRender = (ProcessInfo.processInfo.systemUptime - start) * 1000
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: controller.preferredContentSize), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.appearance = NSAppearance(named: .darkAqua)
        window.setContentSize(controller.preferredContentSize)
        window.orderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        try snapshot(controller.view, to: output.appendingPathComponent("popover-dark.png"))
        let before = Set(descendants(controller.view).map(ObjectIdentifier.init))
        var timings: [Double] = []
        for _ in 0..<100 {
            let start = ProcessInfo.processInfo.systemUptime
            controller.update(states: states, enabled: enabled, displayMode: .remaining)
            timings.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        let after = Set(descendants(controller.view).map(ObjectIdentifier.init))
        try check(before == after, "Repeated updates must reuse view identities")
        let toggles = descendants(controller.view).compactMap { $0 as? NSButton }.filter { $0.accessibilityLabel()?.hasPrefix("Show ") == true }
        for toggle in toggles { toggle.performClick(nil) }
        window.setContentSize(controller.preferredContentSize)
        window.contentView?.layoutSubtreeIfNeeded()
        let scroll = descendants(controller.view).compactMap { $0 as? NSScrollView }.first!
        try check(scroll.documentView!.frame.height > scroll.contentSize.height, "Expanded providers must scroll, not clip")
        try snapshot(controller.view, to: output.appendingPathComponent("popover-expanded.png"))
        for toggle in toggles { toggle.performClick(nil) }
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(controller.preferredContentSize)
        try snapshot(controller.view, to: output.appendingPathComponent("popover-light.png"))
        states[.claude]?.message = "Access denied. Sign in again."
        states[.claude]?.updatedAt = Date().addingTimeInterval(-3600)
        controller.update(states: states, enabled: enabled, displayMode: .used)
        let visibleStrings = descendants(controller.view).compactMap { ($0 as? NSTextField)?.stringValue }
        try check(!visibleStrings.contains(where: { $0.contains("Last success") || $0.contains("Saved usage") }), "Do not show fetch-age prose in the popover")
        window.setContentSize(controller.preferredContentSize)
        try snapshot(controller.view, to: output.appendingPathComponent("popover-error.png"))
        controller.update(states: [:], enabled: [], displayMode: .used)
        window.setContentSize(controller.preferredContentSize)
        try snapshot(controller.view, to: output.appendingPathComponent("popover-empty.png"))
        let preferences = SettingsWindowController(settings: .shared, onCheckForUpdates: {}, onSignIn: {}, onCredentialsChanged: { _ in }, onOAuthChanged: {}, canCheckForUpdates: { false })
        preferences.updateStatuses(store.states)
        preferences.show()
        preferences.window?.appearance = NSAppearance(named: .darkAqua)
        try snapshot(preferences.window!.contentView!, to: output.appendingPathComponent("settings-dark.png"))
        preferences.window?.orderOut(nil)
        print(String(format: "PASS native UI identity reuse + expansion/scroll + empty/error/light/dark; first render %.2fms, update p50 %.2fms, p95 %.2fms", firstRender, timings.sorted()[50], timings.sorted()[95]))
        window.orderOut(nil)
        withExtendedLifetime(appDelegate) {}
        print("ALL CHECKS PASSED")
    }

    @MainActor private static func wait(_ predicate: () async -> Bool) async throws {
        for _ in 0..<1000 {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw CheckFailure(description: "Timed out waiting for asynchronous check")
    }

    @MainActor private static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private static func writeOpenCodeCredentialDB(to url: URL, integration: String, value: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path]
        let input = Pipe()
        let err = Pipe()
        process.standardInput = input
        process.standardError = err
        try process.run()
        let escaped = value.replacingOccurrences(of: "'", with: "''")
        let sql = """
        CREATE TABLE credential (id TEXT, integration_id TEXT, label TEXT, value TEXT, connector_id TEXT, method_id TEXT, active INTEGER, time_created INTEGER, time_updated INTEGER);
        INSERT INTO credential VALUES ('cred_test','\(integration)','xAI','\(escaped)',NULL,'device',1,1,2);
        """
        try input.fileHandleForWriting.write(contentsOf: Data(sql.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        try check(process.terminationStatus == 0, "sqlite3 fixture failed")
    }

    @MainActor private static func snapshot(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CheckFailure(description: "No bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
