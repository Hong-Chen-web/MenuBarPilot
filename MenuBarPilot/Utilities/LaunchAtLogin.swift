import Foundation
import ServiceManagement

/// Manages launch-at-login functionality using SMAppService (macOS 13+).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func enable() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            print("Failed to enable launch at login: \(error)")
        }
    }

    static func disable() {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            print("Failed to disable launch at login: \(error)")
        }
    }

    static func toggle(_ enabled: Bool) {
        if enabled {
            enable()
        } else {
            disable()
        }
    }
}
