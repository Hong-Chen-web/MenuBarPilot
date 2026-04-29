import Cocoa
import Combine
import ApplicationServices

@MainActor
class MenuBarItemManager: ObservableObject {
    @Published var discoveredItems: [MenuBarItem] = []
    @Published var hasAccessibilityPermission = false

    private var timer: Timer?
    private let activePollingInterval: TimeInterval = 5.0
    private let backgroundPollingInterval: TimeInterval = 20.0
    private var currentRefreshID: Int?
    private var nextRefreshID = 0
    private var refreshRequestedWhileRunning = false
    private var isDiscovering = false
    private var panelVisible = false

    func startDiscovering() {
        guard timer == nil else {
            refreshItems()
            return
        }

        isDiscovering = true
        checkAccessibilityPermission()
        if !hasAccessibilityPermission {
            discoveredItems = []
            requestAccessibilityPermission()
        } else {
            refreshItems()
        }
        scheduleTimer()
    }

    func stopDiscovering() {
        isDiscovering = false
        timer?.invalidate()
        timer = nil
        currentRefreshID = nil
        refreshRequestedWhileRunning = false
        discoveredItems = []
    }

    func setPanelVisible(_ visible: Bool) {
        guard panelVisible != visible else { return }
        panelVisible = visible
        if timer != nil {
            scheduleTimer()
        }
        if visible {
            refreshItems()
        }
    }

    // MARK: - Permission

    func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Discovery

    func refreshItems() {
        guard isDiscovering else { return }

        if currentRefreshID != nil {
            refreshRequestedWhileRunning = true
            return
        }

        hasAccessibilityPermission = AXIsProcessTrusted()
        guard hasAccessibilityPermission else {
            discoveredItems = []
            return
        }

        let visible = panelVisible
        let ownPID = ProcessInfo.processInfo.processIdentifier
        nextRefreshID += 1
        let refreshID = nextRefreshID
        currentRefreshID = refreshID
        refreshRequestedWhileRunning = false

        // Snapshot app icons on main thread (NSRunningApplication.icon requires main)
        let runningApps = NSWorkspace.shared.runningApplications
        var appIconMap: [pid_t: NSImage] = [:]
        for app in runningApps {
            appIconMap[app.processIdentifier] = app.icon
        }

        // Run discovery on a background queue to avoid blocking main thread
        DispatchQueue.global(qos: .userInteractive).async {
            let start = CFAbsoluteTimeGetCurrent()

            let axItems = Self.discoverViaAccessibility()
            let cgWindows = Self.buildCGWindowMap()

            var items: [MenuBarItem] = []

            for ax in axItems {
                guard ax.pid != ownPID else { continue }

                let windowID = Self.findWindowID(for: ax.position, cgWindows: cgWindows, pid: ax.pid)
                let captured: NSImage? = visible
                    ? windowID.flatMap { Self.captureWindowImage(windowID: $0, frame: ax.frame) }
                    : nil

                let item = MenuBarItem(
                    id: "\(ax.pid)-\(Int(ax.position.x))",
                    windowID: windowID ?? 0,
                    ownerPID: ax.pid,
                    ownerName: ax.processName,
                    frame: ax.frame,
                    appName: ax.processName,
                    appIcon: appIconMap[ax.pid],
                    displayName: ax.name,
                    capturedImage: captured
                )
                items.append(item)
            }

            items.sort { $0.frame.origin.x < $1.frame.origin.x }

            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            PerfLogger.log("[DISCOVERY] refreshItems took \(String(format: "%.1f", elapsed))ms, found \(items.count) items")

            // Publish results on main thread
            DispatchQueue.main.async {
                guard self.currentRefreshID == refreshID else { return }
                self.currentRefreshID = nil
                defer {
                    if self.refreshRequestedWhileRunning && self.isDiscovering {
                        self.refreshItems()
                    }
                }

                guard self.isDiscovering else { return }

                self.hasAccessibilityPermission = AXIsProcessTrusted()
                guard self.hasAccessibilityPermission else {
                    self.discoveredItems = []
                    return
                }
                self.discoveredItems = items
            }
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = panelVisible ? activePollingInterval : backgroundPollingInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshItems()
            }
        }
    }

    // MARK: - AX Discovery

    private struct AXMenuItem {
        let name: String
        let identifier: String
        let position: CGPoint
        let size: CGSize
        var frame: CGRect { CGRect(origin: position, size: size) }
        let pid: pid_t
        let processName: String
    }

    nonisolated private static func discoverViaAccessibility() -> [AXMenuItem] {
        var results: [AXMenuItem] = []

        for app in NSWorkspace.shared.runningApplications {
            let el = AXUIElementCreateApplication(app.processIdentifier)
            var value: AnyObject?
            let r = AXUIElementCopyAttributeValue(el, "AXExtrasMenuBar" as CFString, &value)

            guard r == .success, let bar = value else { continue }
            let barElement = unsafeBitCast(bar, to: AXUIElement.self)

            var children: AnyObject?
            AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)
            guard let kids = children as? [AXUIElement] else { continue }

            for kid in kids {
                var desc: AnyObject?; AXUIElementCopyAttributeValue(kid, kAXDescriptionAttribute as CFString, &desc)
                var id: AnyObject?; AXUIElementCopyAttributeValue(kid, kAXIdentifierAttribute as CFString, &id)
                var pos: AnyObject?; AXUIElementCopyAttributeValue(kid, kAXPositionAttribute as CFString, &pos)
                var sz: AnyObject?; AXUIElementCopyAttributeValue(kid, kAXSizeAttribute as CFString, &sz)

                let point = pointValue(from: pos)
                let size = sizeValue(from: sz)

                // Only keep items in the menu bar area (y between 0 and 50 in AX coords)
                // x can be negative when pushed off screen by our hider
                guard point.y >= 0 && point.y < 50 else { continue }

                let descStr = desc as? String ?? ""
                let idStr = id as? String ?? ""
                let bundleID = app.bundleIdentifier ?? ""

                // Skip system items
                let isSystemItem = bundleID.hasPrefix("com.apple.") ||
                                   idStr.hasPrefix("com.apple.menuextra")
                guard !isSystemItem else { continue }

                let name = descStr.isEmpty ? (app.localizedName ?? "Unknown") : descStr
                let processName = app.localizedName ?? bundleID

                results.append(AXMenuItem(
                    name: name,
                    identifier: idStr,
                    position: point,
                    size: size,
                    pid: app.processIdentifier,
                    processName: processName
                ))
            }
        }

        return results
    }

    // MARK: - CGWindow Map

    nonisolated private static func buildCGWindowMap() -> [(windowID: CGWindowID, pid: pid_t, x: CGFloat)] {
        var map: [(windowID: CGWindowID, pid: pid_t, x: CGFloat)] = []

        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return map
        }

        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))

        for w in windowList {
            let layer = w[kCGWindowLayer as String] as? Int ?? -999
            guard layer == statusLevel else { continue }

            guard let windowID = w[kCGWindowNumber as String] as? CGWindowID,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t else { continue }

            if let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] {
                let x = bounds["X"] ?? 0
                map.append((windowID, pid, x))
            }
        }

        return map
    }

    nonisolated private static func findWindowID(for position: CGPoint, cgWindows: [(windowID: CGWindowID, pid: pid_t, x: CGFloat)], pid: pid_t) -> CGWindowID? {
        let candidates = cgWindows.filter { $0.pid == pid }
        let best = candidates.min(by: { abs($0.x - position.x) < abs($1.x - position.x) })
        return best?.windowID
    }

    // MARK: - Image Capture

    nonisolated private static func captureWindowImage(windowID: CGWindowID, frame: CGRect) -> NSImage? {
        let rect = CGRect(x: 0, y: 0, width: frame.width * 2, height: frame.height * 2)
        guard let cgImage = CGWindowListCreateImage(
            rect,
            .optionIncludingWindow,
            windowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: frame.width, height: frame.height))
    }

    // MARK: - Helpers

    nonisolated private static func pointValue(from object: AnyObject?) -> CGPoint {
        guard let object else { return .zero }
        let value = unsafeBitCast(object, to: AXValue.self)
        var point = CGPoint.zero
        AXValueGetValue(value, .cgPoint, &point)
        return point
    }

    nonisolated private static func sizeValue(from object: AnyObject?) -> CGSize {
        guard let object else { return .zero }
        let value = unsafeBitCast(object, to: AXValue.self)
        var size = CGSize.zero
        AXValueGetValue(value, .cgSize, &size)
        return size
    }
}
