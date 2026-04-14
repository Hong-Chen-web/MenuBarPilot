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

        let pid = session.pid
        writeDebug("[ClaudeClick] activateSession called, pid=\(pid), cwd=\(session.cwd)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Walk up the process tree to find a GUI app (terminal/editor)
            // Typical chain: claude -> node -> bash -> Terminal.app
            var currentPID = pid
            for i in 0..<6 {
                if let app = NSRunningApplication(processIdentifier: currentPID) {
                    let bid = app.bundleIdentifier ?? "nil"
                    let policy = app.activationPolicy.rawValue
                    let name = app.localizedName ?? "nil"
                    writeDebug("[ClaudeClick] step \(i): pid=\(currentPID) bundle=\(bid) name=\(name) policy=\(policy)")

                    if app.bundleIdentifier != nil && app.activationPolicy == .regular {
                        writeDebug("[ClaudeClick] FOUND GUI app: \(name) (\(bid))")
                        activateApp(app, bundleID: bid)
                        return
                    }
                } else {
                    writeDebug("[ClaudeClick] step \(i): pid=\(currentPID) — no NSRunningApplication")
                }

                // Go to parent process
                guard let ppidStr = ShellRunner.run("ps -o ppid= -p \(currentPID) 2>/dev/null | tr -d ' '"),
                      let ppid = Int32(ppidStr), ppid > 1 else {
                    writeDebug("[ClaudeClick] step \(i): no parent for pid=\(currentPID), stopping walk")
                    break
                }
                writeDebug("[ClaudeClick] step \(i): parent of \(currentPID) is \(ppid)")
                currentPID = pid_t(ppid)
            }

            // Fallback: try the session PID directly
            writeDebug("[ClaudeClick] fallback: trying pid=\(pid) directly")
            if let app = NSRunningApplication(processIdentifier: pid) {
                let bid = app.bundleIdentifier ?? ""
                activateApp(app, bundleID: bid)
            } else {
                writeDebug("[ClaudeClick] fallback: no app for pid=\(pid)")
            }
        }
    }

    /// Activate an app and bring its windows to front.
    /// Uses AppleScript for Terminal/iTerm/Warp since NSRunningApplication.activate()
    /// doesn't reliably bring their windows to front.
    private func activateApp(_ app: NSRunningApplication, bundleID: String) {
        let script: String?
        switch bundleID {
        case "com.apple.Terminal":
            script = """
            tell application "Terminal"
                activate
                set index of front window to 1
            end tell
            """
        case "com.googlecode.iterm2":
            script = """
            tell application "iTerm"
                activate
                select first window
            end tell
            """
        case "dev.warp.Warp-Stable":
            script = """
            tell application "Warp"
                activate
            end tell
            """
        default:
            script = nil
        }

        if let script {
            writeDebug("[ClaudeClick] using AppleScript for \(bundleID)")
            let result = ShellRunner.runScript(script)
            writeDebug("[ClaudeClick] AppleScript result: \(result ?? "nil")")
        } else {
            writeDebug("[ClaudeClick] using activate() for \(bundleID)")
            app.activate(options: .activateIgnoringOtherApps)
        }
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

/// Helper to run shell commands synchronously
private struct ShellRunner {
    static func run(_ command: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let result = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return result.isEmpty ? nil : result
        } catch {
            return nil
        }
    }

    /// Run an AppleScript directly via osascript (no shell quoting issues)
    static func runScript(_ source: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let result = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return result.isEmpty ? nil : result
        } catch {
            return nil
        }
    }
}
