import SwiftUI
import Combine

/// Tab selection for the main popover panel.
enum ActiveTab: String, CaseIterable {
    case icons = "Icons"
    case claude = "Claude Code"

    var systemImage: String {
        switch self {
        case .icons: return "circle.grid.2x2"
        case .claude: return "brain"
        }
    }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Tab State
    @Published var activeTab: ActiveTab = .icons

    // MARK: - Menu Bar Management
    @Published var menuBarItems: [MenuBarItem] = []
    @Published var hasAccessibilityPermission = false
    let statusHider = StatusBarHider()

    // MARK: - Claude Code Monitoring
    @Published var claudeSessions: [ClaudeSession] = []
    @Published var claudeNeedsAttention = false
    @Published var pendingAttentionCount = 0
    @Published var claudeIsWorking = false

    // MARK: - Settings
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("showMenuBarIcons") var showMenuBarIcons = true
    @AppStorage("showClaudeMonitor") var showClaudeMonitor = true
    @AppStorage("enableNotifications") var enableNotifications = true
    @AppStorage("enableSound") var enableSound = true

    // MARK: - Managers
    let menuBarItemManager = MenuBarItemManager()
    let claudeMonitor = ClaudeMonitorService()
    var cancellables = Set<AnyCancellable>()
    private var menuBarMonitoringActive = false
    private var claudeMonitoringActive = false

    init() {
        launchAtLogin = LaunchAtLogin.isEnabled
        setupBindings()
    }

    private func setupBindings() {
        menuBarItemManager.$discoveredItems
            .receive(on: RunLoop.main)
            .assign(to: &$menuBarItems)

        menuBarItemManager.$hasAccessibilityPermission
            .receive(on: RunLoop.main)
            .assign(to: &$hasAccessibilityPermission)

        claudeMonitor.$sessions
            .receive(on: RunLoop.main)
            .assign(to: &$claudeSessions)

        claudeMonitor.$needsAttention
            .receive(on: RunLoop.main)
            .assign(to: &$claudeNeedsAttention)

        claudeMonitor.$pendingCount
            .receive(on: RunLoop.main)
            .assign(to: &$pendingAttentionCount)

        // Track whether Claude is actively working
        claudeMonitor.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] sessions in
                let working = sessions.contains { s in
                    s.state == .running
                }
                self?.claudeIsWorking = working
            }
            .store(in: &cancellables)
    }

    func startMonitoring() {
        updateFeatureToggles()
    }

    func stopMonitoring() {
        stopMenuBarMonitoring()
        stopClaudeMonitoring()
    }

    /// Temporarily show hidden icons (before activating an app).
    func showMenuBarItems() {
        statusHider.temporarilyShow()
    }

    /// Re-hide icons after temporary show.
    func hideMenuBarItems() {
        statusHider.reHide()
    }

    func updateFeatureToggles() {
        if showMenuBarIcons {
            startMenuBarMonitoring()
        } else {
            stopMenuBarMonitoring()
        }

        if showClaudeMonitor {
            startClaudeMonitoring()
        } else {
            stopClaudeMonitoring()
        }

        if !showMenuBarIcons && activeTab == .icons {
            activeTab = showClaudeMonitor ? .claude : .icons
        } else if !showClaudeMonitor && activeTab == .claude {
            activeTab = showMenuBarIcons ? .icons : .claude
        }
    }

    private func startMenuBarMonitoring() {
        guard !menuBarMonitoringActive else { return }
        menuBarMonitoringActive = true
        menuBarItemManager.startDiscovering()
        statusHider.startHiding()
    }

    private func stopMenuBarMonitoring() {
        guard menuBarMonitoringActive else { return }
        menuBarMonitoringActive = false
        menuBarItemManager.stopDiscovering()
        statusHider.stopHiding()
    }

    private func startClaudeMonitoring() {
        guard !claudeMonitoringActive else { return }
        claudeMonitoringActive = true
        claudeMonitor.startMonitoring()
    }

    private func stopClaudeMonitoring() {
        guard claudeMonitoringActive else { return }
        claudeMonitoringActive = false
        claudeMonitor.stopMonitoring()
        claudeMonitor.clearSessions()
    }
}
