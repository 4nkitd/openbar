import Foundation

struct IntegrationState {
    var providers: [ProviderUsage] = []
    var updatedAt: Date?
    var message: String?
    var isRefreshing = false
    var retryAt: Date?
    var failureCount = 0
    var accountStatuses: [String: AccountStatus] = [:]

    var status: String {
        if isRefreshing { return "Refreshing…" }
        if let message { return message }
        return updatedAt == nil ? "Not checked" : "Verified"
    }
}

struct AccountStatus {
    let label: String
    let message: String?
    let updatedAt: Date?
    let isRefreshing: Bool
}

struct CachedQuota: Codable {
    let integration: IntegrationID
    let providers: [ProviderUsage]
    let updatedAt: Date
    var accountID: String? = nil
}

actor QuotaCache {
    private let url: URL
    private let legacyURL: URL?

    init(url: URL? = nil, legacyURL: URL? = nil) {
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        self.url = url ?? support.appendingPathComponent("OpenBar/accounts-v1.json")
        self.legacyURL = legacyURL ?? (url == nil ? support.appendingPathComponent("CodexBarLite/quotas-v2.json") : nil)
    }

    func load() -> [CachedQuota] {
        let source = FileManager.default.fileExists(atPath: url.path) ? url : legacyURL ?? url
        guard let data = try? Data(contentsOf: source), let entries = try? JSONDecoder().decode([CachedQuota].self, from: data) else { return [] }
        let valid = entries.filter { entry in
            !entry.providers.isEmpty && entry.providers.allSatisfy {
                $0.integration == entry.integration && !$0.limits.isEmpty && $0.limits.allSatisfy {
                    $0.usedPercent.isFinite && (0...100).contains($0.usedPercent) && ($0.resetAt.map { (0...253_402_300_799).contains($0.timeIntervalSince1970) } ?? true)
                }
            }
        }
        if source != url { save(valid) }
        return valid
    }

    func save(_ entries: [CachedQuota]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? writePrivateData(data, to: url)
    }
}

@MainActor
final class QuotaStore {
    private(set) var states: [String: IntegrationState] = [:]
    private(set) var accounts: [IntegrationAccount] = []
    var onChange: (() -> Void)?
    var onFresh: (([ProviderUsage]) -> Void)?
    private var tasks: [String: Task<Void, Never>] = [:]
    private var generations: [String: UUID] = [:]
    private let fetch: (IntegrationAccount) async throws -> [ProviderUsage]
    private let cache: QuotaCache
    private var hasRestored = false

    init(cache: QuotaCache = QuotaCache(), fetch: @escaping (IntegrationAccount) async throws -> [ProviderUsage]) {
        self.cache = cache
        self.fetch = fetch
    }

    func restore() async {
        for entry in await cache.load() {
            let id = entry.accountID ?? IntegrationAccount.current(entry.integration).id
            guard states[id] == nil, generations[id] == nil, let account = accounts.first(where: { $0.id == id }) else { continue }
            let providers = entry.providers.map { usage -> ProviderUsage in
                var result = usage
                result.configurationID = id
                return result
            }
            states[id] = IntegrationState(providers: providers, updatedAt: entry.updatedAt, message: "Cached. Live check pending.", retryAt: entry.updatedAt.addingTimeInterval(account.integration == .claude ? 300 : 60))
        }
        hasRestored = true
        persist()
        onChange?()
    }

    var enabled: [IntegrationID] {
        IntegrationID.allCases.filter { id in accounts.contains { $0.integration == id } }
    }

    var presentationStates: [IntegrationID: IntegrationState] {
        var result: [IntegrationID: IntegrationState] = [:]
        for integration in enabled {
            let selected = accounts.filter { $0.integration == integration }
            var group = IntegrationState()
            var messages: [String] = []
            for account in selected {
                let state = states[account.id] ?? IntegrationState()
                group.providers += state.providers
                group.isRefreshing = group.isRefreshing || state.isRefreshing
                if let date = state.updatedAt { group.updatedAt = min(group.updatedAt ?? date, date) }
                if let message = state.message { messages.append("\(account.label): \(message)") }
                group.accountStatuses[account.id] = AccountStatus(label: account.label, message: state.message, updatedAt: state.updatedAt, isRefreshing: state.isRefreshing)
            }
            group.message = messages.isEmpty ? nil : messages.joined(separator: "\n")
            result[integration] = group
        }
        return result
    }

    func setAccounts(_ newAccounts: [IntegrationAccount]) {
        for old in accounts where !newAccounts.contains(old) {
            tasks.removeValue(forKey: old.id)?.cancel()
            generations[old.id] = UUID()
            states.removeValue(forKey: old.id)
        }
        var seen = Set<String>()
        accounts = newAccounts.filter { $0.isEnabled && seen.insert($0.id).inserted }
        persist()
        onChange?()
    }

    func credentialsChanged(_ id: String) {
        tasks.removeValue(forKey: id)?.cancel()
        generations[id] = UUID()
        states[id] = IntegrationState()
        persist()
        onChange?()
        refresh(only: id)
    }

    func refresh(only: String? = nil, now: Date = Date()) {
        for account in accounts where only == nil || account.id == only {
            let id = account.id
            guard tasks[id] == nil, (states[id]?.retryAt ?? .distantPast) <= now else { continue }
            let generation = UUID()
            generations[id] = generation
            states[id, default: IntegrationState()].isRefreshing = true
            tasks[id] = Task { [weak self, fetch] in
                let result: Result<[ProviderUsage], Error>
                do { result = .success(try await fetch(account)) } catch { result = .failure(error) }
                guard let self, !Task.isCancelled, self.generations[id] == generation, self.accounts.contains(where: { $0.id == id }) else { return }
                self.tasks[id] = nil
                self.apply(result, to: account, now: Date())
            }
        }
        onChange?()
    }

    private func apply(_ result: Result<[ProviderUsage], Error>, to account: IntegrationAccount, now: Date) {
        let id = account.id
        var state = states[id] ?? IntegrationState()
        state.isRefreshing = false
        switch result {
        case .success(let providers):
            guard !providers.isEmpty, providers.allSatisfy({ !$0.limits.isEmpty }) else {
                apply(.failure(IntegrationError.invalidResponse("No usable quota returned.")), to: account, now: now)
                return
            }
            state.providers = providers
            state.updatedAt = now
            state.message = nil
            state.failureCount = 0
            // Manual refreshes also observe a minimum interval to avoid burning API quota.
            state.retryAt = now.addingTimeInterval(account.integration == .claude ? 300 : 60)
            onFresh?(providers)
        case .failure(let error):
            state.failureCount = min(6, state.failureCount + 1)
            state.message = error.localizedDescription
            state.retryAt = now.addingTimeInterval(min(1800, 60 * pow(2, Double(state.failureCount - 1))))
            if case IntegrationError.rateLimited(let retryAt) = error { state.retryAt = max(state.retryAt!, retryAt) }
            if case IntegrationError.partial(let providers, _) = error {
                state.providers = providers
                state.updatedAt = now
                onFresh?(providers)
            }
        }
        states[id] = state
        if case .success = result { persist() }
        if case .failure(IntegrationError.partial) = result { persist() }
        onChange?()
    }

    private func persist() {
        guard hasRestored else { return }
        let entries = states.compactMap { id, state -> CachedQuota? in
            guard let date = state.updatedAt, !state.providers.isEmpty, let account = accounts.first(where: { $0.id == id }) else { return nil }
            return CachedQuota(integration: account.integration, providers: state.providers, updatedAt: date, accountID: id)
        }
        Task { await cache.save(entries) }
    }
}
