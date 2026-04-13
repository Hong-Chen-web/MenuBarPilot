import Cocoa
import UserNotifications

/// Manages macOS notifications for Claude Code state changes.
class ClaudeNotificationManager: NSObject, UNUserNotificationCenterDelegate {

    override init() {
        super.init()
        requestNotificationPermission()
        UNUserNotificationCenter.current().delegate = self
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    func sendNotification(title: String, body: String, sessionId: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["sessionId": sessionId]

        let request = UNNotificationRequest(
            identifier: "claude-\(sessionId)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
    }

    // Show notification even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Handle notification click - activate the terminal
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let sessionId = userInfo["sessionId"] as? String {
            activateTerminal(for: sessionId)
        }
        completionHandler()
    }

    private func activateTerminal(for sessionId: String) {
        // Try to activate Terminal.app
        let urls = [
            "file:///Applications/Terminal.app",
            "file:///Applications/iTerm.app",
            "file:///Applications/Warp.app"
        ]

        for urlString in urls {
            if let url = URL(string: urlString) {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                    if error == nil {
                        return // Successfully activated
                    }
                }
            }
        }
    }
}
