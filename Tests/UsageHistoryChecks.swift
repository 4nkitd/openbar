import AppKit

private func usageCheck(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "UsageHistoryChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

private final class UsageHistoryHTTP: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let profile = request.url?.path == "/backend-api/wham/profiles/me"
        let stats = request.url?.path == "/api/experimental/session/stats"
        let authorized = profile
            ? request.value(forHTTPHeaderField: "Authorization") == "Bearer history-fixture" && request.value(forHTTPHeaderField: "chatgpt-account-id") == "history-account"
            : request.value(forHTTPHeaderField: "Authorization") == "Basic b3BlbmNvZGU6Zml4dHVyZQ=="
        let valid = authorized && (profile || stats)
        let body = profile ? #"{"stats":{"lifetime_tokens":987654321}}"# : UsageHistoryChecks.apiFixture
        let response = HTTPURLResponse(url: request.url!, statusCode: valid ? 200 : 401, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

enum UsageHistoryChecks {
    static let apiFixture = #"{"data":{"range":{"from":1767225600000,"to":1792195200000},"models":[{"model":{"id":"gpt-5.4","providerID":"openai"},"tokens":{"input":1000,"output":200,"reasoning":50,"cache":{"read":500,"write":100}},"cost":0},{"model":{"id":"private-model","providerID":"custom"},"tokens":{"input":100,"output":20,"reasoning":0,"cache":{"read":0,"write":0}},"cost":0},{"model":{"id":"server-priced","providerID":"custom"},"tokens":{"input":100,"output":20,"reasoning":0,"cache":{"read":0,"write":0}},"cost":1.25}]}}"#

    @MainActor static func run(output: URL) async throws -> UsageHistorySnapshot {
        let tokens = UsageTokens(input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000, cacheWrite: 1_000_000)
        try usageCheck(tokens.total == 4_000_000, "Token categories must be disjoint")
        try usageCheck(UsagePricing.estimate(model: "gpt-6-astra", tokens: tokens) == 73.5, "Published input/output/cache rates")
        try usageCheck(UsagePricing.estimate(model: "claude-sonnet-4-5-20250929", tokens: tokens) == 22.05, "Dated Claude model pricing")
        try usageCheck(UsagePricing.estimate(model: "unknown", tokens: tokens) == nil, "Unknown prices are not zero")
        try usageCheck(UsageHistoryParsing.count(true) == nil && UsageHistoryParsing.count(-1) == nil && UsageHistoryParsing.count(1.5) == nil, "Reject boolean, negative and fractional counts")
        let zeroLifetime = try UsageHistoryParsing.codexLifetime(Data(#"{"stats":{"lifetime_tokens":0}}"#.utf8))
        try usageCheck(zeroLifetime == 0, "A genuine zero API count is supported")
        do {
            _ = try UsageHistoryParsing.codexLifetime(Data(#"{"stats":{}}"#.utf8))
            throw NSError(domain: "Expected rejection", code: 1)
        } catch UsageHistoryError.invalidData {}

        var parser = LocalUsageParser(kind: .codex, fileID: "fixture")
        let lines = [
            #"{"type":"session_meta","payload":{"id":"fixture-session","timestamp":"2026-01-02T00:00:00Z"}}"#,
            #"{"type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
            #"{"timestamp":"2026-01-01T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}}}}"#,
            #"{"timestamp":"2026-01-03T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"cached_input_tokens":100,"output_tokens":30,"reasoning_output_tokens":20}}}}"#
        ]
        for line in lines { parser.consume(Data(line.utf8)) }
        parser.consume(Data(lines.last!.utf8))
        try usageCheck(parser.result.rows.count == 1 && parser.result.rows[0].tokens.total == 220, "Codex excludes inherited prefix and duplicate cumulative snapshots")
        try usageCheck(parser.result.rows[0].tokens.output == 20, "Codex reasoning is already in output and must not be charged twice")
        parser.consume(Data(#"{"type":"turn_context","payload":{"model":"unpriced-model"}}"#.utf8))
        parser.consume(Data(#"{"timestamp":"2026-01-04T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"cached_input_tokens":200,"output_tokens":50}}}}"#.utf8))
        try usageCheck(parser.result.rows.reduce(0) { $0 + $1.tokens.total } == 440, "Codex cumulative deltas follow model switches")
        try usageCheck(parser.result.rows.contains { $0.model == "unpriced-model" && $0.estimatedUSD == nil }, "Unpriced usage retains its tokens")

        let home = output.appendingPathComponent("usage-home")
        let active = home.appendingPathComponent(".codex/sessions/active.jsonl")
        let archived = home.appendingPathComponent(".codex/archived_sessions/copy.jsonl")
        try writePrivateData(Data((lines.joined(separator: "\n") + "\n").utf8), to: active)
        try writePrivateData(Data((lines.joined(separator: "\n") + "\n").utf8), to: archived)
        let claude = #"{"type":"assistant","timestamp":"2026-01-04T00:00:00Z","message":{"id":"message-a","model":"claude-sonnet-4-5","usage":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":200,"cache_creation_input_tokens":50}}}"#
        let claudePath = home.appendingPathComponent(".claude/projects/project/session.jsonl")
        try writePrivateData(Data((claude + "\n" + claude + "\n").utf8), to: claudePath)
        let serviceFile = home.appendingPathComponent("service.json")
        try writePrivateData(Data(#"{"url":"http://127.0.0.1:9","password":"fixture"}"#.utf8), to: serviceFile)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UsageHistoryHTTP.self]
        let service = UsageHistoryService(home: home, environment: [:], serviceFiles: [serviceFile], configuration: configuration)
        let local = try await service.localHistory()
        try usageCheck(local.tokens.total == 590, "Deduplicate Codex archive copies and Claude streaming message fragments")
        let cached = try await service.localHistory()
        try usageCheck(cached.tokens == local.tokens, "Cached scan does not accumulate totals twice")
        let complete = try await service.load()
        try usageCheck(complete.tokens.total == 2680, "Combine local logs and non-overlapping OpenCode API usage")
        try usageCheck(complete.unpricedTokens == 120, "Partial cost coverage counts unpriced tokens")
        try usageCheck(complete.rows.contains { $0.model == "server-priced" && $0.estimatedUSD == 1.25 }, "Keep the service's recorded cost estimate")
        try usageCheck(complete.rows.contains { $0.model == "gpt-5.4" && $0.source.hasPrefix("OpenCode") && $0.tokens.output == 250 }, "OpenCode reasoning is separate and included exactly once")
        let missing = UsageHistoryService(home: output.appendingPathComponent("empty-usage"), environment: [:], serviceFiles: [], configuration: configuration)
        let empty = try await missing.load()
        try usageCheck(empty.rows.isEmpty && empty.estimatedUSD == nil && empty.coverage.contains { $0.contains("unavailable") }, "Missing sources never create fake usage or free spend")

        let authPath = home.appendingPathComponent("codex-auth.json")
        try writePrivateData(Data(#"{"tokens":{"access_token":"history-fixture","account_id":"history-account"}}"#.utf8), to: authPath)
        let account = IntegrationAccount(id: "history", integration: .codex, label: "History fixture", source: .file, credentialPath: authPath.path, isEnabled: true)
        let integration = IntegrationService(configuration: configuration, environment: [:], googleOAuthClients: { [] }, saveGoogleOAuthClient: { _, _ in })
        let lifetime = try await integration.fetchCodexLifetime(account: account)
        try usageCheck(lifetime == 987654321, "Codex lifetime API routes the selected account's bearer and account header")
        var withAccount = complete
        withAccount.accountTotals = [UsageAccountTotal(label: "Codex · Personal", tokens: lifetime, status: "Provider-reported lifetime tokens. Not added to recorded usage.")]
        try usageCheck(withAccount.tokens == complete.tokens, "Account-wide figures never double-count local usage")

        var fixture = UsageHistorySnapshot()
        fixture.merge([
            UsageHistoryRow(source: "OpenCode / openai", model: "gpt-6-astra", tokens: UsageTokens(input: 18_400_000, output: 2_100_000, cacheRead: 91_800_000), estimatedUSD: 380.80),
            UsageHistoryRow(source: "Codex local", model: "gpt-6.1-sol", tokens: UsageTokens(input: 8_200_000, output: 940_000, cacheRead: 34_000_000), estimatedUSD: 29.20),
            UsageHistoryRow(source: "Claude local", model: "claude-opus-4-8", tokens: UsageTokens(input: 2_400_000, output: 610_000, cacheRead: 14_800_000, cacheWrite: 340_000), estimatedUSD: 36.775),
            UsageHistoryRow(source: "OpenCode / custom", model: "private-model", tokens: UsageTokens(input: 450_000, output: 35_000), estimatedUSD: nil)
        ])
        fixture.accountTotals = withAccount.accountTotals
        fixture.coverage = ["Codex: local active and archived sessions.", "Claude: local projects, deduplicated by message ID.", "OpenCode API: all history returned by the local service."]
        print("PASS usage history: local/API counters, deduplication, pricing, coverage and account isolation")
        return fixture
    }

    @MainActor static func screenshots(_ fixture: UsageHistorySnapshot, output: URL) throws {
        let controller = UsageHistoryViewController()
        controller.update(fixture, loading: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.orderFront(nil)
        for (appearance, name) in [(NSAppearance.Name.darkAqua, "usage-history-dark.png"), (.aqua, "usage-history-light.png")] {
            window.appearance = NSAppearance(named: appearance)
            controller.update(fixture, loading: false)
            try snapshot(controller.view, to: output.appendingPathComponent(name))
        }
        window.setContentSize(NSSize(width: 660, height: 540))
        window.appearance = NSAppearance(named: .darkAqua)
        try snapshot(controller.view, to: output.appendingPathComponent("usage-history-compact.png"))
        controller.update(UsageHistorySnapshot(coverage: ["OpenCode API unavailable.", "No local history found."]), loading: false)
        try snapshot(controller.view, to: output.appendingPathComponent("usage-history-empty.png"))
        controller.update(nil, loading: true)
        try snapshot(controller.view, to: output.appendingPathComponent("usage-history-loading.png"))
        window.orderOut(nil)
        print("PASS usage history: local/API counters, deduplication, pricing, coverage, account isolation and native screenshots")
    }

    @MainActor private static func snapshot(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw UsageHistoryError.unavailable }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.lockFocus()
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            view.bounds.fill()
            bitmap.draw(in: view.bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let opaque = NSBitmapImageRep(data: tiff),
              let data = opaque.representation(using: .png, properties: [:]) else { throw UsageHistoryError.unavailable }
        for y in 0..<opaque.pixelsHigh {
            for x in 0..<opaque.pixelsWide {
                try usageCheck(opaque.colorAt(x: x, y: y)?.alphaComponent == 1, "Usage screenshots must be opaque")
            }
        }
        try data.write(to: url)
    }
}
