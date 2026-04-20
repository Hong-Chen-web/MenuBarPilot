import SwiftUI
import Combine

@main
struct MenuBarPilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
    }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let appState = AppState.shared
    private var cancellables = Set<AnyCancellable>()
    private var animationFrame = 0
    private var animationTimer: Timer?
    private var globalClickMonitor: Any?
    private var shouldAnimateIcon = false

    // MARK: - Pre-rendered animation frame cache
    /// 20 frames × 3 colors (green, orange, red) = 60 cached images
    private var frameCache: [String: NSImage] = [:]
    private let animationColors: [NSColor] = [.systemGreen, .systemOrange, .systemRed]
    private let colorKeys: [String] = ["green", "orange", "red"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let iconKey = "NSStatusItem Preferred Position MBPIcon"
        if UserDefaults.standard.object(forKey: iconKey) == nil {
            UserDefaults.standard.set(CGFloat(0), forKey: iconKey)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: 120)
        statusItem.autosaveName = "MBPIcon"

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateIcon()

        // Pre-render all animation frames for all 3 colors
        preRenderAllFrames()

        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 500)
        popover.behavior = .transient
        popover.animates = true

        let rootView = StatusBarView()
            .environmentObject(appState)
        popover.contentViewController = NSHostingController(rootView: rootView)

        NotificationCenter.default.addObserver(
            self, selector: #selector(closePopover),
            name: .closePopover, object: nil
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.appState.startMonitoring()
        }

        Publishers.CombineLatest(appState.$claudeIsWorking, appState.$claudeNeedsAttention)
            .removeDuplicates { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshAnimationState()
                self?.updateIcon()
            }
            .store(in: &cancellables)

        appState.claudeMonitor.$latestAttentionEvent
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let self else { return }
                guard self.appState.showClaudeMonitor else { return }
                self.appState.activeTab = .claude
                PerfLogger.log("[ClaudeUI] auto-open popover for session \(event.sessionId.prefix(8))...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.showPopover()
                }
            }
            .store(in: &cancellables)
        refreshAnimationState()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    @objc private func closePopover() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        appState.isPanelVisible = false
        refreshAnimationState()
        popover.performClose(nil)
    }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }

        // Monitor clicks outside the popover to auto-close
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.closePopover()
        }

        appState.isPanelVisible = true
        refreshAnimationState()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
    }

    private func refreshAnimationState() {
        let shouldAnimate = appState.claudeIsWorking || appState.claudeNeedsAttention || appState.isPanelVisible
        guard shouldAnimate != shouldAnimateIcon else { return }

        shouldAnimateIcon = shouldAnimate
        animationTimer?.invalidate()
        animationTimer = nil

        guard shouldAnimate else {
            animationFrame = 0
            updateIcon()
            return
        }

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.animationFrame = (self.animationFrame + 1) % 20
                self.updateIcon()
            }
        }
    }

    // MARK: - Custom Robot Icon

    /// Pre-render all 60 frames (20 animation steps × 3 colors) once at startup.
    @MainActor private func preRenderAllFrames() {
        let start = CFAbsoluteTimeGetCurrent()
        let w: CGFloat = 116
        let h: CGFloat = 22

        for (colorIdx, color) in animationColors.enumerated() {
            let key = colorKeys[colorIdx]
            for frame in 0..<20 {
                let cacheKey = "\(key)-\(frame)"
                let image = NSImage(size: NSSize(width: w, height: h))
                image.lockFocus()

                guard let ctx = NSGraphicsContext.current?.cgContext else {
                    image.unlockFocus()
                    continue
                }

                // Pill background
                let pill = CGRect(x: 0, y: 0, width: w, height: h)
                ctx.addPath(CGPath(roundedRect: pill, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
                ctx.setFillColor(NSColor(white: 0.08, alpha: 1.0).cgColor)
                ctx.fillPath()

                ctx.setFillColor(color.cgColor)

                let px: CGFloat = 1.8
                let gridW = 9 * px
                let gridH = 3 * px
                let oy = (h - gridH) / 2
                let totalSteps: CGFloat = 20
                let step = CGFloat(frame % 20)
                let ox = step / totalSteps * (w - gridW)

                // Row 2 (top): ▐▛███▜▌ — 7 filled, offset by 1 col
                for c in 1...7 { fillPx(ctx, ox, oy, c, 2, px) }

                // Row 1 (mid): ▝▜█████▛▘ — 9 filled
                for c in 0...8 { fillPx(ctx, ox, oy, c, 1, px) }

                // Row 0 (bot): legs
                let legFrame = frame % 4
                switch legFrame {
                case 0:
                    fillPx(ctx, ox, oy, 0, 0, px)
                    fillPx(ctx, ox, oy, 1, 0, px)
                    fillPx(ctx, ox, oy, 7, 0, px)
                    fillPx(ctx, ox, oy, 8, 0, px)
                case 1:
                    fillPx(ctx, ox, oy, 3, 0, px)
                    fillPx(ctx, ox, oy, 4, 0, px)
                    fillPx(ctx, ox, oy, 5, 0, px)
                case 2:
                    fillPx(ctx, ox, oy, 0, 0, px)
                    fillPx(ctx, ox, oy, 1, 0, px)
                    fillPx(ctx, ox, oy, 7, 0, px)
                    fillPx(ctx, ox, oy, 8, 0, px)
                default:
                    fillPx(ctx, ox, oy, 3, 0, px)
                    fillPx(ctx, ox, oy, 4, 0, px)
                    fillPx(ctx, ox, oy, 5, 0, px)
                }

                image.unlockFocus()
                frameCache[cacheKey] = image
            }
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        PerfLogger.log("preRenderAllFrames: cached \(frameCache.count) frames in \(String(format: "%.1f", elapsed))ms")
    }

    @MainActor private func updateIcon() {
        guard let button = self.statusItem.button else { return }

        let colorKey: String
        if self.appState.claudeNeedsAttention {
            colorKey = "red"
        } else if self.appState.claudeIsWorking {
            colorKey = "orange"
        } else {
            colorKey = "green"
        }

        let cacheKey = "\(colorKey)-\(self.animationFrame)"

        if let cached = frameCache[cacheKey] {
            button.image = cached
        } else {
            // Fallback: render on-the-fly (shouldn't happen normally)
            let color: NSColor
            switch colorKey {
            case "red": color = .systemRed
            case "orange": color = .systemOrange
            default: color = .systemGreen
            }
            button.image = self.createRobotPill(color: color, frame: self.animationFrame)
        }
    }

    /// Robot body (unchanged, the user's original design):
    /// ▐▛███▜▌     row 2: 7 pixels offset 1
    /// ▝▜█████▛▘    row 1: 9 pixels full width
    /// Legs alternate between 4 frames for running effect.
    /// The whole robot shifts left/right to simulate movement across the pill.
    private func createRobotPill(color: NSColor, frame: Int) -> NSImage {
        let w: CGFloat = 116
        let h: CGFloat = 22
        let image = NSImage(size: NSSize(width: w, height: h))
        image.lockFocus()

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        // Pill background
        let pill = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
        ctx.setFillColor(NSColor(white: 0.08, alpha: 1.0).cgColor)
        ctx.fillPath()

        ctx.setFillColor(color.cgColor)

        let px: CGFloat = 1.8
        let gridW = 9 * px
        let gridH = 3 * px
        let oy = (h - gridH) / 2

        // Robot runs across the full pill width
        // 20 steps to traverse, frame wraps via % 20
        let totalSteps: CGFloat = 20
        let step = CGFloat(frame % 20)
        let ox = step / totalSteps * (w - gridW)

        // Row 2 (top): ▐▛███▜▌ — 7 filled, offset by 1 col
        for c in 1...7 { fillPx(ctx, ox, oy, c, 2, px) }

        // Row 1 (mid): ▝▜█████▛▘ — 9 filled
        for c in 0...8 { fillPx(ctx, ox, oy, c, 1, px) }

        // Row 0 (bot): legs — alternate for running animation
        let legFrame = frame % 4
        switch legFrame {
        case 0: // stride: legs spread
            fillPx(ctx, ox, oy, 0, 0, px)
            fillPx(ctx, ox, oy, 1, 0, px)
            fillPx(ctx, ox, oy, 7, 0, px)
            fillPx(ctx, ox, oy, 8, 0, px)
        case 1: // legs together
            fillPx(ctx, ox, oy, 3, 0, px)
            fillPx(ctx, ox, oy, 4, 0, px)
            fillPx(ctx, ox, oy, 5, 0, px)
        case 2: // stride: legs spread
            fillPx(ctx, ox, oy, 0, 0, px)
            fillPx(ctx, ox, oy, 1, 0, px)
            fillPx(ctx, ox, oy, 7, 0, px)
            fillPx(ctx, ox, oy, 8, 0, px)
        default: // legs together
            fillPx(ctx, ox, oy, 3, 0, px)
            fillPx(ctx, ox, oy, 4, 0, px)
            fillPx(ctx, ox, oy, 5, 0, px)
        }

        image.unlockFocus()
        return image
    }

    private func fillPx(_ ctx: CGContext, _ ox: CGFloat, _ oy: CGFloat,
                        _ col: Int, _ row: Int, _ px: CGFloat) {
        ctx.fill(CGRect(x: ox + CGFloat(col) * px,
                        y: oy + CGFloat(row) * px,
                        width: px - 0.2,
                        height: px - 0.2))
    }
}
