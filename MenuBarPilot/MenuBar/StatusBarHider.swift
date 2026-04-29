import Cocoa

/// Hides third-party menu bar icons using Ice's technique:
/// An invisible NSStatusItem at position 1 (just left of our app icon at position 0)
/// expands to 10,000pt, pushing all third-party items to its left off screen.
///
/// Layout (left → right on screen):
/// [Third-party items...] [ControlItem(expanded 10,000pt)] [OurAppIcon(pos=0)] [SystemItems]
///
/// Reference: github.com/jordanbaird/Ice
@MainActor
class StatusBarHider {
    private var controlItem: NSStatusItem?
    private var isActive = false
    private var isTemporarilyShowing = false
    private var timer: Timer?

    // MARK: - Public

    func startHiding() {
        guard !isActive else { return }

        // Set preferred position BEFORE creating the status item (like Ice).
        // Position 1 = just left of our app icon (position 0).
        let hiderKey = "NSStatusItem Preferred Position MBPHider"
        // Always set to correct value (clear old wrong values)
        UserDefaults.standard.set(CGFloat(1), forKey: hiderKey)

        createControlItem()
        isActive = true

        // Expand after delay to let macOS position the item first
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.expand()
        }

        // Periodically re-apply to catch new/reappearing items
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isTemporarilyShowing else { return }
                self.expand()
            }
        }
    }

    func stopHiding() {
        guard isActive else { return }
        timer?.invalidate()
        timer = nil
        collapse()
        removeControlItem()
        isActive = false
    }

    func temporarilyShow() {
        isTemporarilyShowing = true
        collapse()
    }

    func reHide() {
        isTemporarilyShowing = false
        expand()
    }

    // MARK: - Control Item (Ice pattern)

    private func createControlItem() {
        let item = NSStatusBar.system.statusItem(withLength: 0)
        item.autosaveName = "MBPHider"

        if let button = item.button {
            button.image = nil
            button.title = ""
            button.isEnabled = false
            button.isBordered = false
            button.isHighlighted = false
            button.cell?.isEnabled = false
        }

        controlItem = item
    }

    private func expand() {
        guard let item = controlItem else { return }
        item.length = 10_000
    }

    
    private func collapse() {
        controlItem?.length = NSStatusItem.variableLength
    }

    private func removeControlItem() {
        if let item = controlItem {
            // Cache preferred position before removal (macOS deletes it on remove)
            let key = "NSStatusItem Preferred Position MBPHider"
            let cached = UserDefaults.standard.object(forKey: key) as? CGFloat
            NSStatusBar.system.removeStatusItem(item)
            controlItem = nil
            // Restore
            if let cached { UserDefaults.standard.set(cached, forKey: key) }
        }
    }
}
