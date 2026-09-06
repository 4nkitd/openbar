import Foundation
import ServiceManagement

enum UsageDisplayMode: String {
    case used
    case remaining
}

extension Notification.Name {
    static let codexBarSettingsDidChange = Notification.Name("CodexBarSettingsDidChange")
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

        static func integration(_ id: IntegrationID) -> String {
            "integration.\(id.rawValue).enabled"
        }
    }

    private let defaults = UserDefaults.standard

    private init() {
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
            Key.integration(.antigravity): false
        ])
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
        NotificationCenter.default.post(name: .codexBarSettingsDidChange, object: self)
    }
}
