import Foundation

struct IntegrationState {
    var providers: [ProviderUsage] = []
    var updatedAt: Date?
    var message: String?
    var isRefreshing = false
    var retryAt: Date?
    var failureCount = 0

    var status: String {
        if isRefreshing { return "Refreshing…" }
        if let message { return message }
        return updatedAt == nil ? "Not checked" : "Verified"
    }
}

struct CachedQuota: Codable {
    let integration: IntegrationID
    let providers: [ProviderUsage]
    let updatedAt: Date
}

actor QuotaCache {
    private let url: URL

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexBarLite/quotas-v2.json")) {
        self.url = url
    }

    func load() -> [CachedQuota] {
        guard let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([CachedQuota].self, from: data) else { return [] }
        return entries.filter { entry in
            !entry.providers.isEmpty && entry.providers.allSatisfy {
                $0.integration == entry.integration && !$0.limits.isEmpty && $0.limits.allSatisfy {
                    $0.usedPercent.isFinite && (0...100).contains($0.usedPercent) && ($0.resetAt.map { (0...253_402_300_799).contains($0.timeIntervalSince1970) } ?? true)
                }
            }
        }
    }

    func save(_ entries: [CachedQuota]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? writePrivateData(data, to: url)
    }
}

@MainActor
final class QuotaStore {
    private(set) var states: [IntegrationID: IntegrationState] = [:]
    private(set) var enabled: [IntegrationID] = []
    var onChange: (() -> Void)?
    var onFresh: (([ProviderUsage]) -> Void)?
    private var tasks: [IntegrationID: Task<Void, Never>] = [:]
    private var generations: [IntegrationID: UUID] = [:]
    private let fetch: (IntegrationID) async throws -> [ProviderUsage]
    private let cache: QuotaCache

    init(cache: QuotaCache = QuotaCache(), fetch: @escaping (IntegrationID) async throws -> [ProviderUsage]) {
        self.cache = cache
        self.fetch = fetch
    }

    func restore() async {
        for entry in await cache.load() where states[entry.integration] == nil {
            states[entry.integration] = IntegrationState(providers: entry.providers, updatedAt: entry.updatedAt, message: "Saved usage. Live check pending.", retryAt: entry.updatedAt.addingTimeInterval(entry.integration == .claude ? 300 : 60))
        }
        onChange?()
    }

    func setEnabled(_ integrations: [IntegrationID]) {
        for id in enabled where !integrations.contains(id) {
            tasks.removeValue(forKey: id)?.cancel()
            generations[id] = UUID()
            states[id]?.isRefreshing = false
        }
        enabled = integrations
        onChange?()
    }

    func credentialsChanged(_ id: IntegrationID) {
        tasks.removeValue(forKey: id)?.cancel()
        generations[id] = UUID()
        states[id] = IntegrationState()
        persist()
        onChange?()
        refresh(only: id)
    }

    func refresh(only: IntegrationID? = nil, now: Date = Date()) {
        for id in enabled where only == nil || id == only {
            guard tasks[id] == nil, (states[id]?.retryAt ?? .distantPast) <= now else { continue }
            let generation = UUID()
            generations[id] = generation
            states[id, default: IntegrationState()].isRefreshing = true
            tasks[id] = Task { [weak self, fetch] in
                let result: Result<[ProviderUsage], Error>
                do { result = .success(try await fetch(id)) } catch { result = .failure(error) }
                guard let self, !Task.isCancelled, self.generations[id] == generation, self.enabled.contains(id) else { return }
                self.tasks[id] = nil
                self.apply(result, to: id, now: Date())
            }
        }
        onChange?()
    }

    private func apply(_ result: Result<[ProviderUsage], Error>, to id: IntegrationID, now: Date) {
        var state = states[id] ?? IntegrationState()
        state.isRefreshing = false
        switch result {
        case .success(let providers):
            guard !providers.isEmpty, providers.allSatisfy({ !$0.limits.isEmpty }) else {
                apply(.failure(IntegrationError.invalidResponse("No usable quota returned.")), to: id, now: now)
                return
            }
            state.providers = providers
            state.updatedAt = now
            state.message = nil
            state.failureCount = 0
            // Manual refreshes also observe a minimum interval to avoid burning API quota.
            state.retryAt = now.addingTimeInterval(id == .claude ? 300 : 60)
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
        let entries = states.compactMap { id, state -> CachedQuota? in
            guard let date = state.updatedAt, !state.providers.isEmpty else { return nil }
            return CachedQuota(integration: id, providers: state.providers, updatedAt: date)
        }
        Task { await cache.save(entries) }
    }
}
