import Cocoa
import UserNotifications

/// Manages macOS notifications for Claude Code state changes.
class ClaudeNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    var onSessionActivated: ((String) -> Void)?

    override init() {
        super.init()
        if UserDefaults.standard.object(forKey: "enableNotifications") as? Bool ?? true {
            Self.requestAuthorizationIfNeeded()
        }
        UNUserNotificationCenter.current().delegate = self
    }

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                PerfLogger.log("[ClaudeNotification] permission error: \(error)")
            } else {
                PerfLogger.log("[ClaudeNotification] authorization result granted=\(granted)")
            }
        }
    }

    func sendNotification(title: String, body: String, sessionId: String) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "enableNotifications") as? Bool ?? true else {
            clearNotification(sessionId: sessionId)
            return
        }

        Self.requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if defaults.object(forKey: "enableSound") as? Bool ?? true {
            content.sound = .default
        }
        content.userInfo = ["sessionId": sessionId]

        let request = UNNotificationRequest(
            identifier: "claude-\(sessionId)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                PerfLogger.log("[ClaudeNotification] send failed: \(error)")
            }
        }
    }

    func clearNotification(sessionId: String) {
        let identifier = "claude-\(sessionId)"
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // Show notification even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "enableNotifications") as? Bool ?? true else {
            completionHandler([])
            return
        }

        if defaults.object(forKey: "enableSound") as? Bool ?? true {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.banner])
        }
    }

    // Handle notification click - activate the terminal
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let sessionId = userInfo["sessionId"] as? String {
            DispatchQueue.main.async { [weak self] in
                self?.onSessionActivated?(sessionId)
            }
        }
        completionHandler()
    }
}
