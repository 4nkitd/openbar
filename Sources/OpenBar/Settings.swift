import Foundation
import ServiceManagement

enum UsageDisplayMode: String {
    case used
    case remaining
}

extension Notification.Name {
    static let openBarSettingsDidChange = Notification.Name("OpenBarSettingsDidChange")
}

final class SettingsStore {
    static let shared = SettingsStore()

    private enum Key {
        static let refreshInterval = "refreshInterval"
        static let displayMode = "displayMode"
        static let checkForUpdates = "checkForUpdates"
        static let notifyAt80 = "notifyAt80"
        static let notifyAt90 = "notifyAt90"
        static let notifyWhenExhausted = "notifyWhenExhausted"
        static let notifyWhenReset = "notifyWhenReset"
        static let launchAtLogin = "launchAtLogin"
        static let didSetLaunchAtLoginDefault = "didSetLaunchAtLoginDefault"
        static let accounts = "integrationAccounts"
        static let importedOpenCodeV2 = "importedOpenCodeV2"

        static func integration(_ id: IntegrationID) -> String {
            "integration.\(id.rawValue).enabled"
        }
    }

    private let defaults = UserDefaults.standard

    private init() {
        if Bundle.main.bundleIdentifier == AppBranding.bundleIdentifier {
            let current = defaults.persistentDomain(forName: AppBranding.bundleIdentifier) ?? [:]
            let legacy = defaults.persistentDomain(forName: AppBranding.legacyBundleIdentifier) ?? [:]
            if current["didMigrateOpenBarPreferences"] as? Bool != true {
                let migrated = Self.migratedPreferences(current: current, legacy: legacy)
                defaults.setPersistentDomain(migrated, forName: AppBranding.bundleIdentifier)
            }
        }
        defaults.register(defaults: [
            Key.refreshInterval: 300.0,
            Key.displayMode: UsageDisplayMode.used.rawValue,
            Key.checkForUpdates: true,
            Key.notifyAt80: true,
            Key.notifyAt90: true,
            Key.notifyWhenExhausted: true,
            Key.notifyWhenReset: true,
            Key.launchAtLogin: true,
            Key.integration(.codex): true,
            Key.integration(.claude): false,
            Key.integration(.openCodeGo): false,
            Key.integration(.githubCopilot): false,
            Key.integration(.antigravity): false,
            Key.integration(.xai): false
        ])
    }

    static func migratedPreferences(current: [String: Any], legacy: [String: Any]) -> [String: Any] {
        var result = current
        let keys = [Key.refreshInterval, Key.displayMode, Key.checkForUpdates, Key.notifyAt80, Key.notifyAt90,
                    Key.notifyWhenExhausted, Key.notifyWhenReset, Key.launchAtLogin, Key.didSetLaunchAtLoginDefault]
            + IntegrationID.allCases.map(Key.integration)
        for key in keys where result[key] == nil { result[key] = legacy[key] }
        result["didMigrateOpenBarPreferences"] = true
        return result
    }

    var refreshInterval: TimeInterval {
        get { defaults.double(forKey: Key.refreshInterval) }
        set { set(newValue, forKey: Key.refreshInterval) }
    }

    var displayMode: UsageDisplayMode {
        get { UsageDisplayMode(rawValue: defaults.string(forKey: Key.displayMode) ?? "") ?? .used }
        set { set(newValue.rawValue, forKey: Key.displayMode) }
    }

    var checkForUpdates: Bool {
        get { defaults.bool(forKey: Key.checkForUpdates) }
        set { set(newValue, forKey: Key.checkForUpdates) }
    }

    var notifyAt80: Bool {
        get { defaults.bool(forKey: Key.notifyAt80) }
        set { set(newValue, forKey: Key.notifyAt80) }
    }

    var notifyAt90: Bool {
        get { defaults.bool(forKey: Key.notifyAt90) }
        set { set(newValue, forKey: Key.notifyAt90) }
    }

    var notifyWhenExhausted: Bool {
        get { defaults.bool(forKey: Key.notifyWhenExhausted) }
        set { set(newValue, forKey: Key.notifyWhenExhausted) }
    }

    var notifyWhenReset: Bool {
        get { defaults.bool(forKey: Key.notifyWhenReset) }
        set { set(newValue, forKey: Key.notifyWhenReset) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    var notificationsEnabled: Bool {
        notifyAt80 || notifyAt90 || notifyWhenExhausted || notifyWhenReset
    }

    var enabledIntegrations: [IntegrationID] {
        IntegrationID.allCases.filter(isIntegrationEnabled)
    }

    var accounts: [IntegrationAccount] {
        get {
            guard let data = defaults.data(forKey: Key.accounts) else { return IntegrationID.allCases.map(IntegrationAccount.current) }
            return (try? JSONDecoder().decode([IntegrationAccount].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            set(data, forKey: Key.accounts)
        }
    }

    var enabledAccounts: [IntegrationAccount] {
        accounts.filter { $0.isEnabled && isIntegrationEnabled($0.integration) }
    }

    static func importedOpenCodeAccounts(existing: [IntegrationAccount], available: Set<IntegrationID>, alreadyImported: Set<IntegrationID> = []) -> (accounts: [IntegrationAccount], enable: [IntegrationID]) {
        var accounts = existing
        var enable: [IntegrationID] = []
        for id in IntegrationID.allCases where available.contains(id) {
            let matches = accounts.filter { $0.integration == id }
            if matches.isEmpty {
                accounts.append(.current(id))
                enable.append(id)
            } else if !alreadyImported.contains(id), matches.allSatisfy({ $0.source == .automatic }) {
                enable.append(id)
            }
        }
        return (accounts, enable)
    }

    func importCompatibleOpenCodeAccounts() {
        let available = Set(IntegrationID.allCases.filter(CredentialStore.hasOpenCodeV2Credential(for:)))
        let already = Set((defaults.stringArray(forKey: Key.importedOpenCodeV2) ?? []).compactMap(IntegrationID.init(rawValue:)))
        let imported = Self.importedOpenCodeAccounts(existing: accounts, available: available, alreadyImported: already)
        for id in imported.enable { setIntegration(id, enabled: true) }
        if imported.accounts != accounts { accounts = imported.accounts }
        let recorded = already.union(imported.enable)
        if recorded != already {
            defaults.set(recorded.map(\.rawValue).sorted(), forKey: Key.importedOpenCodeV2)
        }
    }

    func isIntegrationEnabled(_ id: IntegrationID) -> Bool {
        defaults.bool(forKey: Key.integration(id))
    }

    func setIntegration(_ id: IntegrationID, enabled: Bool) {
        set(enabled, forKey: Key.integration(id))
    }

    func applyLaunchAtLoginDefaultIfNeeded() {
        guard !defaults.bool(forKey: Key.didSetLaunchAtLoginDefault) else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        do {
            try setLaunchAtLogin(true)
            defaults.set(true, forKey: Key.didSetLaunchAtLoginDefault)
        } catch {
            return
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }

        launchAtLogin = enabled
        notifyChanged()
    }

    private func set(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
        notifyChanged()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .openBarSettingsDidChange, object: self)
    }
}
