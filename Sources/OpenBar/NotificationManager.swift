import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private struct WindowState: Codable {
        let usedPercent: Int
        let resetAt: TimeInterval?
    }

    private lazy var center = UNUserNotificationCenter.current()
    private let settings: SettingsStore
    private let defaults = UserDefaults.standard
    private var requestedAuthorization = false

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
        if Bundle.main.bundleURL.pathExtension == "app" { center.delegate = self }
    }

    func requestAuthorizationIfNeeded() {
        guard Bundle.main.bundleURL.pathExtension == "app", settings.notificationsEnabled, !requestedAuthorization else { return }
        requestedAuthorization = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func evaluate(_ providers: [ProviderUsage]) {
        for provider in providers {
            for limit in provider.limits {
                evaluate(limit, provider: provider.name + (provider.accountLabel.map { " / \($0)" } ?? ""), key: "\(provider.id).\(limit.cadence.rawValue).\(limit.displayLabel)")
            }
        }
    }

    private func evaluate(_ window: ProviderLimit, provider: String, key: String) {
        let stateKey = "notificationState.\(key)"
        let previous = defaults.data(forKey: stateKey).flatMap { try? JSONDecoder().decode(WindowState.self, from: $0) }
        let usedPercent = Int(window.usedPercent)
        let current = WindowState(usedPercent: usedPercent, resetAt: window.resetAt?.timeIntervalSince1970)

        if let previous {
            if settings.notifyWhenReset, let reset = current.resetAt, let oldReset = previous.resetAt, reset - oldReset > 60, usedPercent < previous.usedPercent {
                send(title: "\(provider) quota reset", body: "\(window.displayLabel) is back to \(100 - usedPercent)% remaining.", id: "\(key)-reset-\(current.resetAt ?? 0)")
            } else {
                notifyThreshold(80, previous: previous.usedPercent, current: usedPercent, provider: provider, window: window.displayLabel, key: key, enabled: settings.notifyAt80)
                notifyThreshold(90, previous: previous.usedPercent, current: usedPercent, provider: provider, window: window.displayLabel, key: key, enabled: settings.notifyAt90)
                notifyThreshold(100, previous: previous.usedPercent, current: usedPercent, provider: provider, window: window.displayLabel, key: key, enabled: settings.notifyWhenExhausted)
            }
        }

        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: stateKey)
        }
    }

    private func notifyThreshold(_ threshold: Int, previous: Int, current: Int, provider: String, window: String, key: String, enabled: Bool) {
        guard enabled, previous < threshold, current >= threshold else { return }
        let title = threshold == 100 ? "\(provider) quota exhausted" : "\(provider) usage reached \(threshold)%"
        let body = threshold == 100 ? "No quota remains in \(window)." : "\(100 - current)% remains in \(window)."
        send(title: title, body: body, id: "\(key)-\(threshold)-\(Date().timeIntervalSince1970)")
    }

    private func send(title: String, body: String, id: String) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
