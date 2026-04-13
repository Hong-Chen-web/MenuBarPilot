import Cocoa

/// Represents a single menu bar icon discovered in the system menu bar.
struct MenuBarItem: Identifiable, Hashable {
    let id: String
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let frame: CGRect
    let appName: String
    let appIcon: NSImage?
    var displayName: String      // AXDescription or fallback
    var capturedImage: NSImage?  // Screenshot of the actual icon

    var section: MenuBarSection = .alwaysVisible

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// Sections in the menu bar for organizing icons.
enum MenuBarSection: String, CaseIterable {
    case alwaysVisible = "Always Visible"
    case hidden = "Hidden"
    case alwaysHidden = "Always Hidden"

    var systemImage: String {
        switch self {
        case .alwaysVisible: return "eye"
        case .hidden: return "eye.slash"
        case .alwaysHidden: return "eye.trianglebadge.exclamationmark"
        }
    }
}
