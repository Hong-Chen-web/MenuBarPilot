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

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.id == rhs.id
    }
}
