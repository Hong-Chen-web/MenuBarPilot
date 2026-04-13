import SwiftUI

/// Main panel view shown in the NSPopover.
struct StatusBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            tabBar
            Divider()

            Group {
                switch appState.activeTab {
                case .icons:
                    IconsPanel()
                case .claude:
                    ClaudeStatusPanel()
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.grid.2x2")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text("MenuBarPilot")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if appState.claudeNeedsAttention {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                    Text("\(appState.pendingAttentionCount)")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(.red))
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ActiveTab.allCases, id: \.self) { tab in
                Button {
                    appState.activeTab = tab
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 10))
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(appState.activeTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                    .foregroundStyle(appState.activeTab == tab ? Color.accentColor : Color.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.bar)
    }
}
