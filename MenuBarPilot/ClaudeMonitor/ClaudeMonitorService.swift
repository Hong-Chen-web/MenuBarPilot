import Foundation
import Combine

/// Main service that monitors Claude Code sessions and detects when user attention is needed.
@MainActor
class ClaudeMonitorService: ObservableObject {
    @Published var sessions: [ClaudeSession] = []
    @Published var needsAttention: Bool = false
    @Published var pendingCount: Int = 0

    private var fileWatchers: [String: DispatchSourceFileSystemObject] = [:]
    private var sessionDirectoryWatcher: DispatchSourceFileSystemObject?
    private var pollingTimer: Timer?
    private let sessionsDirectory: URL
    private var fastPollingActive = false

    private let notificationManager = ClaudeNotificationManager()

    init() {
        sessionsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions")
    }

    // MARK: - Debug Logging

    private func log(_ message: String) {
        PerfLogger.log("[ClaudeMonitor] \(message)")
    }

    // MARK: - Start / Stop

    func startMonitoring() {
        discoverExistingSessions()
        watchSessionsDirectory()
        startPolling()
    }

    /// Switch to fast polling (every 2s) when at least one session is running.
    @MainActor private func updatePollingSpeed() {
        let hasActive = sessions.contains { $0.state == .running || $0.state == .idle }
        if hasActive && !fastPollingActive {
            fastPollingActive = true
            pollingTimer?.invalidate()
            pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.pollSessions()
                }
            }
            log("switched to fast polling (2s)")
        } else if !hasActive && fastPollingActive {
            fastPollingActive = false
            pollingTimer?.invalidate()
            pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.pollSessions()
                }
            }
            log("switched to slow polling (5s)")
        }
    }

    func stopMonitoring() {
        fileWatchers.values.forEach { $0.cancel() }
        fileWatchers.removeAll()
        sessionDirectoryWatcher?.cancel()
        sessionDirectoryWatcher = nil
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Session Discovery

    private func discoverExistingSessions() {
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            log("discoverExistingSessions: failed to read sessions directory")
            return
        }

        let jsonFiles = files.filter { $0.pathExtension == "json" }
        log("discoverExistingSessions: found \(jsonFiles.count) session file(s), currently tracking \(sessions.count)")

        for file in jsonFiles {
            loadSession(from: file)
        }

        updateAttentionState()
    }

    private func loadSession(from url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            log("loadSession: FAILED to read \(url.lastPathComponent)")
            return
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log("loadSession: FAILED to parse JSON from \(url.lastPathComponent), size=\(data.count) bytes, content=\(String(data: data.prefix(200), encoding: .utf8) ?? "nil")")
            return
        }
        guard let pid = json["pid"] as? pid_t else {
            log("loadSession: FAILED to extract pid from \(url.lastPathComponent), pid raw=\(json["pid"] ?? "nil")")
            return
        }
        guard let sessionId = json["sessionId"] as? String,
              let cwd = json["cwd"] as? String,
              let startedAt = json["startedAt"] as? Double else {
            log("loadSession: FAILED to extract required fields from \(url.lastPathComponent), sessionId=\(json["sessionId"] ?? "nil"), cwd=\(json["cwd"] ?? "nil"), startedAt=\(json["startedAt"] ?? "nil")")
            return
        }

        // Skip if already tracked
        guard !sessions.contains(where: { $0.id == sessionId }) else {
            log("loadSession: already tracking \(sessionId) pid=\(pid)")
            return
        }

        let session = ClaudeSession(
            id: sessionId,
            pid: pid,
            cwd: cwd,
            startedAt: Date(timeIntervalSince1970: startedAt / 1000),
            kind: json["kind"] as? String ?? "interactive",
            entrypoint: json["entrypoint"] as? String ?? "cli"
        )

        // Check if process is alive
        let alive = session.isProcessAlive
        log("loadSession: pid=\(pid) sessionId=\(sessionId.prefix(8))... cwd=\(cwd) alive=\(alive) logPath=\(session.logFilePath)")

        if alive {
            // Determine initial state: running if alive, unknown otherwise
            var aliveSession = session
            aliveSession.state = .idle
            sessions.append(aliveSession)
            watchSessionLog(aliveSession)
        }
    }

    // MARK: - Directory Watching

    private func watchSessionsDirectory() {
        let fd = open(sessionsDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.handleSessionsDirectoryChange()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        sessionDirectoryWatcher = source
        source.resume()
    }

    private func handleSessionsDirectoryChange() {
        log("handleSessionsDirectoryChange: triggered, sessions before=\(sessions.count)")

        // Re-discover sessions
        discoverExistingSessions()

        // Remove sessions whose processes have died
        let before = sessions.count
        sessions.removeAll { session in
            let dead = !session.isProcessAlive
            if dead { log("  removing dead session: pid=\(session.pid) cwd=\(session.cwd)") }
            return dead
        }
        log("handleSessionsDirectoryChange: sessions after=\(sessions.count) (removed \(before - sessions.count))")

        updateAttentionState()
    }

    // MARK: - Session Log Watching

    private func watchSessionLog(_ session: ClaudeSession) {
        let logPath = session.logFilePath
        let fm = FileManager.default

        // If log file doesn't exist yet, skip file watcher setup.
        // pollSessions will retry later once the file appears.
        guard fm.fileExists(atPath: logPath) else {
            log("watchSessionLog: log file NOT found for pid=\(session.pid) at \(logPath)")
            return
        }

        // Already watching this session's log
        guard fileWatchers[session.id] == nil else {
            log("watchSessionLog: already watching pid=\(session.pid)")
            return
        }

        let fd = open(logPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.handleLogChange(sessionId: session.id)
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        fileWatchers[session.id] = source
        source.resume()

        // Parse initial state
        handleLogChange(sessionId: session.id)
    }

    private func handleLogChange(sessionId: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let session = sessions[index]

        let entries = SessionLogParser.parseLastEntries(from: session.logFilePath, count: 50)
        let newState = SessionLogParser.detectState(from: entries)

        // Log last few entries for debugging
        let lastTypes = entries.suffix(5).map { "\($0.type)" + ($0.toolNames.isEmpty ? "" : "(\($0.toolNames.joined(separator: ",")))") }.joined(separator: " → ")
        log("handleLogChange: pid=\(session.pid) parsed=\(entries.count) entries → \(newState.rawValue) | tail: \(lastTypes)")

        let oldState = session.state
        sessions[index] = ClaudeSession(
            id: session.id,
            pid: session.pid,
            cwd: session.cwd,
            startedAt: session.startedAt,
            kind: session.kind,
            entrypoint: session.entrypoint,
            state: newState,
            lastActivity: Date(),
            waitingReason: newState.needsAttention ? reasonForState(newState) : nil
        )

        // Notify if state changed to needing attention
        if newState.needsAttention && !oldState.needsAttention {
            notificationManager.sendNotification(
                title: "Claude Code Needs Attention",
                body: reasonForState(newState) + " in \(session.cwd)",
                sessionId: session.id
            )
        }

        updateAttentionState()
        updatePollingSpeed()
    }

    private func reasonForState(_ state: ClaudeSessionState) -> String {
        switch state {
        case .waitingForInput:
            return "Claude is waiting for your choice"
        default:
            return ""
        }
    }

    // MARK: - Attention State

    private func updateAttentionState() {
        let attentionSessions = sessions.filter { $0.state.needsAttention }
        pendingCount = attentionSessions.count
        needsAttention = !attentionSessions.isEmpty
    }

    // MARK: - Polling Fallback

    private func startPolling() {
        // Poll every 5 seconds as a fallback for file watcher misses
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollSessions()
            }
        }
    }

    private func pollSessions() {
        let start = CFAbsoluteTimeGetCurrent()

        // Remove dead sessions
        let before = sessions.count
        sessions.removeAll { !$0.isProcessAlive }
        if before != sessions.count {
            log("pollSessions: removed \(before - sessions.count) dead session(s), \(sessions.count) remaining")
        }

        // Re-discover sessions to catch any that were missed (e.g. file was being written when first detected)
        discoverExistingSessions()

        // Re-check session logs
        for i in sessions.indices {
            let entries = SessionLogParser.parseLastEntries(from: sessions[i].logFilePath, count: 20)
            let newState = SessionLogParser.detectState(from: entries)

            // Retry file watcher setup if the log file now exists but wasn't watched before
            if fileWatchers[sessions[i].id] == nil {
                let fm = FileManager.default
                if fm.fileExists(atPath: sessions[i].logFilePath) {
                    watchSessionLog(sessions[i])
                }
            }

            if sessions[i].state != newState {
                let oldState = sessions[i].state
                sessions[i] = ClaudeSession(
                    id: sessions[i].id,
                    pid: sessions[i].pid,
                    cwd: sessions[i].cwd,
                    startedAt: sessions[i].startedAt,
                    kind: sessions[i].kind,
                    entrypoint: sessions[i].entrypoint,
                    state: newState,
                    lastActivity: Date(),
                    waitingReason: newState.needsAttention ? reasonForState(newState) : nil
                )

                if newState.needsAttention && !oldState.needsAttention {
                    notificationManager.sendNotification(
                        title: "Claude Code Needs Attention",
                        body: reasonForState(newState) + " in \(sessions[i].cwd)",
                        sessionId: sessions[i].id
                    )
                }
            }
        }

        updateAttentionState()
        updatePollingSpeed()

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        PerfLogger.log("[POLL] pollSessions took \(String(format: "%.1f", elapsed))ms, \(sessions.count) sessions")
    }
}
