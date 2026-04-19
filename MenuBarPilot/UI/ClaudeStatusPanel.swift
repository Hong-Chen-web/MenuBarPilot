import SwiftUI

/// Panel showing Claude Code session status.
struct ClaudeStatusPanel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.claudeSessions.isEmpty {
                noSessionsView
            } else {
                sessionsList
            }
        }
    }

    private var noSessionsView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "brain")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.quaternary)

            VStack(spacing: 6) {
                Text("No Claude Code Sessions")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("Monitoring \(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions").path)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var sessionsList: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Summary bar
                HStack {
                    Text("\(appState.claudeSessions.count) session\(appState.claudeSessions.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    if appState.claudeNeedsAttention {
                        Text("\(appState.pendingAttentionCount) need\(appState.pendingAttentionCount == 1 ? "s" : "") attention")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                ForEach(appState.claudeSessions) { session in
                    ClaudeSessionRow(session: session)
                }
            }
            .padding(.bottom, 12)
        }
    }
}

struct ClaudeSessionRow: View {
    @EnvironmentObject var appState: AppState
    let session: ClaudeSession

    var body: some View {
        Button(action: activateSession) {
            HStack(spacing: 10) {
                // Status indicator dot
                ZStack {
                    Circle()
                        .fill(colorForState(session.state).opacity(0.15))
                        .frame(width: 34, height: 34)

                    Image(systemName: session.state.systemImage)
                        .font(.system(size: 14))
                        .foregroundStyle(colorForState(session.state))
                }

                // Session info
                VStack(alignment: .leading, spacing: 2) {
                    Text(shortenPath(session.cwd))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 4) {
                        Text(session.state.rawValue)
                            .font(.system(size: 10))
                            .foregroundStyle(colorForState(session.state))

                        if let lastActivity = session.lastActivity {
                            Text("·")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Text(lastActivity, style: .relative)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(session.state.needsAttention ? Color.orange.opacity(0.06) : Color.gray.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        session.state.needsAttention
                            ? Color.orange.opacity(0.25)
                            : Color.gray.opacity(0.1),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }

    /// Bring the terminal window running this Claude Code session to front.
    private func activateSession() {
        // Close popover first
        NotificationCenter.default.post(name: .closePopover, object: nil)
        appState.claudeMonitor.activateSession(sessionId: session.id)
    }

    private func colorForState(_ state: ClaudeSessionState) -> Color {
        switch state {
        case .idle: return .gray
        case .running: return .green
        case .waitingForInput: return .orange
        case .ended: return .gray
        }
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

private func writeDebug(_ text: String) {
    PerfLogger.log(text)
}
