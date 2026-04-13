import Cocoa

/// Private CoreGraphics APIs for menu bar window management.
/// Reference: Ice (github.com/jordanbaird/Ice)
enum PrivateAPI {

    @_silgen_name("CGSMainConnectionID")
    static func _mainConnectionID() -> Int32

    static var mainConnectionID: Int32 {
        _mainConnectionID()
    }

    /// Get the list of menu bar item window IDs for all processes.
    /// This is the key API that discovers individual NSStatusItem windows,
    /// including third-party ones not visible in CGWindowListCopyWindowInfo.
    @_silgen_name("CGSGetProcessMenuBarWindowList")
    static func _getMenuBarWindowList(
        _ cid: Int32,
        _ targetCID: Int32,
        _ count: Int32,
        _ list: UnsafeMutablePointer<CGWindowID>,
        _ outCount: inout Int32
    ) -> Int32

    /// Get the frame rect for a window ID.
    @_silgen_name("CGSGetScreenRectForWindow")
    static func _getScreenRectForWindow(_ cid: Int32, _ wid: Int32, _ rect: inout CGRect) -> Int32

    // MARK: - Menu Bar Window List

    /// Returns all menu bar item window IDs across all processes.
    static func getMenuBarWindowList() -> [CGWindowID] {
        // Start with a reasonable buffer size
        var count: Int32 = 64
        var list = [CGWindowID](repeating: 0, count: Int(count))
        var realCount: Int32 = 0

        let result = _getMenuBarWindowList(
            mainConnectionID,
            0,
            count,
            &list,
            &realCount
        )

        if result == 0, realCount > 0 {
            return Array(list.prefix(Int(realCount)))
        }
        return []
    }

    /// Get the frame for a specific window ID.
    static func getWindowFrame(windowID: CGWindowID) -> CGRect? {
        var rect = CGRect.zero
        let result = _getScreenRectForWindow(mainConnectionID, Int32(windowID), &rect)
        return result == 0 ? rect : nil
    }

    // MARK: - Window Movement

    /// Move a window to a new frame.
    @_silgen_name("CGSMoveWindow")
    static func _moveWindow(_ cid: Int32, _ wid: Int32, _ rect: inout CGRect) -> Int32

    /// Move a window to the specified rect. Returns true on success.
    static func moveWindow(windowID: CGWindowID, to rect: CGRect) -> Bool {
        var rect = rect
        let result = _moveWindow(mainConnectionID, Int32(windowID), &rect)
        return result == 0
    }
}
