import SwiftUI

/// Icons panel: all third-party menu bar items collected here.
/// Click to show the icon's menu. No toggles — everything is auto-collected.
struct IconsPanel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if !appState.hasAccessibilityPermission {
                permissionView
            } else if appState.menuBarItems.isEmpty {
                scanningView
            } else {
                itemList
            }
        }
    }

    private var permissionView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Accessibility Access Needed")
                .font(.system(size: 14, weight: .medium))
            Text("Grant Accessibility access so MenuBarPilot can discover and click menu bar extras.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
            Button("Open Accessibility Settings") {
                appState.menuBarItemManager.requestAccessibilityPermission()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var scanningView: some View {
        VStack(spacing: 10) {
            Spacer()
            ProgressView().controlSize(.small)
            Text("Scanning menu bar...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var itemList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(appState.menuBarItems) { item in
                    IconRow(
                        item: item,
                        onTap: {
                            writeDebug("[IconClick] tap: pid=\(item.ownerPID) name=\(item.displayName)")
                            appState.showMenuBarItems()
                            // Close popover first
                            NotificationCenter.default.post(name: .closePopover, object: nil)

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                let pressed = pressMenuBarItem(item)
                                if !pressed {
                                    clickAtPoint(CGPoint(x: item.frame.midX, y: item.frame.midY))
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    appState.hideMenuBarItems()
                                }
                            }
                        }
                    )
                }
            }
            .padding(.vertical, 8)
        }
    }

    /// Simulate a left mouse click at a screen coordinate point.
    private func clickAtPoint(_ point: CGPoint) {
        let screenHeight = NSScreen.main?.frame.height ?? 982
        let cgPoint = CGPoint(x: point.x, y: screenHeight - point.y)

        guard let source = CGEventSource(stateID: .hidSystemState),
              let downEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: cgPoint, mouseButton: .left),
              let upEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: cgPoint, mouseButton: .left) else { return }

        downEvent.post(tap: .cghidEventTap)
        upEvent.post(tap: .cghidEventTap)
    }

    /// Use AXPress to directly activate a menu bar item via Accessibility API.
    /// More reliable than coordinate-based clicking.
    private func pressMenuBarItem(_ item: MenuBarItem) -> Bool {
        let el = AXUIElementCreateApplication(item.ownerPID)
        var value: AnyObject?
        let r = AXUIElementCopyAttributeValue(el, "AXExtrasMenuBar" as CFString, &value)
        guard r == .success, let bar = value else {
            writeDebug("  AXPress: no AXExtrasMenuBar for pid \(item.ownerPID)")
            return false
        }
        let barElement = unsafeBitCast(bar, to: AXUIElement.self)

        var children: AnyObject?
        AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)
        guard let kids = children as? [AXUIElement] else {
            writeDebug("  AXPress: no children")
            return false
        }

        writeDebug("  AXPress: found \(kids.count) children")

        let bestMatch = kids.min { lhs, rhs in
            abs(xPosition(for: lhs) - item.frame.minX) < abs(xPosition(for: rhs) - item.frame.minX)
        }

        if let bestMatch {
            let pressResult = AXUIElementPerformAction(bestMatch, "AXPress" as CFString)
            writeDebug("  AXPress: result=\(pressResult.rawValue)")
            return pressResult == .success
        }

        return false
    }

    private func xPosition(for element: AXUIElement) -> CGFloat {
        var pos: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pos) == .success,
              let pos else {
            return .greatestFiniteMagnitude
        }

        let value = unsafeBitCast(pos, to: AXValue.self)
        var point = CGPoint.zero
        AXValueGetValue(value, .cgPoint, &point)
        return point.x
    }
}

// Notification to close the popover from child views
extension Notification.Name {
    static let closePopover = Notification.Name("closePopover")
}

struct IconRow: View {
    let item: MenuBarItem
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                iconView

                Text(item.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isPressed ? Color.accentColor.opacity(0.15) :
                          isHovered ? Color.gray.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var iconView: some View {
        Group {
            if let captured = item.capturedImage, captured.isValid {
                Image(nsImage: captured)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let icon = item.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.dashed")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 22, height: 22)
    }
}

private func writeDebug(_ text: String) {
    PerfLogger.log(text)
}
