import Foundation
import Combine

struct ClaudeAttentionEvent: Equatable, Identifiable {
    let id = UUID()
    let sessionId: String
}

/// Main service that monitors Claude Code sessions and detects when user attention is needed.
@MainActor
class ClaudeMonitorService: ObservableObject {
    @Published var sessions: [ClaudeSession] = []
    @Published var needsAttention: Bool = false
    @Published var pendingCount: Int = 0
    @Published var latestAttentionEvent: ClaudeAttentionEvent?

    private var fileWatchers: [String: DispatchSourceFileSystemObject] = [:]
    private var sessionDirectoryWatcher: DispatchSourceFileSystemObject?
    private var pollingTimer: Timer?
    private var logParseRevisions: [String: Int] = [:]
    private let sessionsDirectory: URL
    private var fastPollingActive = false
    private var acknowledgedAttentionSessionIDs = Set<String>()
    private let activePollingInterval: TimeInterval = 4.0
    private let idlePollingInterval: TimeInterval = 12.0

    private let notificationManager = ClaudeNotificationManager()

    init() {
        sessionsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions")
        notificationManager.onSessionActivated = { [weak self] sessionId in
            Task { @MainActor in
                self?.activateSession(sessionId: sessionId)
            }
        }
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
            pollingTimer = Timer.scheduledTimer(withTimeInterval: activePollingInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.pollSessions()
                }
            }
            log("switched to active polling (\(activePollingInterval)s)")
        } else if !hasActive && fastPollingActive {
            fastPollingActive = false
            pollingTimer?.invalidate()
            pollingTimer = Timer.scheduledTimer(withTimeInterval: idlePollingInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.pollSessions()
                }
            }
            log("switched to idle polling (\(idlePollingInterval)s)")
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

    func clearSessions() {
        sessions.removeAll()
        acknowledgedAttentionSessionIDs.removeAll()
        logParseRevisions.removeAll()
        pendingCount = 0
        needsAttention = false
        latestAttentionEvent = nil
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
            if dead {
                removeSessionArtifacts(sessionId: session.id)
                log("  removing dead session: pid=\(session.pid) cwd=\(session.cwd)")
            }
            return dead
        }
        log("handleSessionsDirectoryChange: sessions after=\(sessions.count) (removed \(before - sessions.count))")

        updateAttentionState()
    }

    // MARK: - Session Log Watching

    private func watchSessionLog(_ session: ClaudeSession, parseInitialState: Bool = true) {
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
        if parseInitialState {
            handleLogChange(sessionId: session.id)
        }
    }

    private func handleLogChange(sessionId: String) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
        let revision = nextLogParseRevision(for: sessionId)
        let logPath = session.logFilePath
        let pid = session.pid

        DispatchQueue.global(qos: .userInteractive).async {
            let entries = SessionLogParser.parseLastEntries(from: logPath, count: 50)
            let newState = SessionLogParser.detectState(from: entries)

            PerfLogger.log("[ClaudeMonitor] handleLogChange: pid=\(pid) parsed=\(entries.count) entries → \(newState.rawValue) rev=\(revision)")

            DispatchQueue.main.async {
                if self.applyParsedState(
                    sessionId: sessionId,
                    newState: newState,
                    revision: revision,
                    updateLastActivity: true
                ) {
                    self.updateAttentionState()
                    self.updatePollingSpeed()
                }
            }
        }
    }

    private func reasonForState(_ state: ClaudeSessionState) -> String {
        switch state {
        case .waitingForInput:
            return "Claude is waiting for your choice"
        default:
            return ""
        }
    }

    private func nextLogParseRevision(for sessionId: String) -> Int {
        let nextRevision = (logParseRevisions[sessionId] ?? 0) + 1
        logParseRevisions[sessionId] = nextRevision
        return nextRevision
    }

    @discardableResult
    private func applyParsedState(
        sessionId: String,
        newState: ClaudeSessionState,
        revision: Int,
        updateLastActivity: Bool
    ) -> Bool {
        guard logParseRevisions[sessionId] == revision else {
            log("discarding stale parse result: sessionId=\(sessionId.prefix(8))... rev=\(revision)")
            return false
        }
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return false }

        let session = sessions[idx]
        let previousState = session.state
        let waitingReason = newState.needsAttention ? reasonForState(newState) : nil
        let shouldUpdateActivity = updateLastActivity || previousState != newState
        let lastActivity = shouldUpdateActivity ? Date() : session.lastActivity

        if previousState != newState || shouldUpdateActivity || session.waitingReason != waitingReason {
            sessions[idx] = ClaudeSession(
                id: session.id,
                pid: session.pid,
                cwd: session.cwd,
                startedAt: session.startedAt,
                kind: session.kind,
                entrypoint: session.entrypoint,
                state: newState,
                lastActivity: lastActivity,
                waitingReason: waitingReason
            )
        }

        if !newState.needsAttention {
            acknowledgedAttentionSessionIDs.remove(session.id)
            notificationManager.clearNotification(sessionId: session.id)
        }

        if newState.needsAttention &&
            !previousState.needsAttention &&
            !acknowledgedAttentionSessionIDs.contains(session.id) {
            notificationManager.sendNotification(
                title: "Claude Code Needs Attention",
                body: reasonForState(newState) + " in \(session.cwd)",
                sessionId: session.id
            )
            latestAttentionEvent = ClaudeAttentionEvent(sessionId: session.id)
        }

        return true
    }

    // MARK: - Attention State

    private func updateAttentionState() {
        let attentionSessions = sessions.filter { $0.state.needsAttention }
        pendingCount = attentionSessions.count
        needsAttention = !attentionSessions.isEmpty
    }

    func markAttentionHandled(for sessionId: String) {
        acknowledgedAttentionSessionIDs.insert(sessionId)
        notificationManager.clearNotification(sessionId: sessionId)
        log("markAttentionHandled: sessionId=\(sessionId.prefix(8))...")
    }

    func activateSession(sessionId: String) {
        markAttentionHandled(for: sessionId)
        guard let session = sessions.first(where: { $0.id == sessionId }) else {
            log("activateSession: sessionId=\(sessionId.prefix(8))... not found")
            return
        }
        ClaudeSessionActivator.activate(session: session)
    }

    // MARK: - Polling Fallback

    private func startPolling() {
        // Poll every 5 seconds as a fallback for file watcher misses
        pollingTimer = Timer.scheduledTimer(withTimeInterval: idlePollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollSessions()
            }
        }
    }

    private func pollSessions() {
        let start = CFAbsoluteTimeGetCurrent()

        // Remove dead sessions
        let before = sessions.count
        sessions.removeAll { session in
            let dead = !session.isProcessAlive
            if dead {
                removeSessionArtifacts(sessionId: session.id)
            }
            return dead
        }
        if before != sessions.count {
            log("pollSessions: removed \(before - sessions.count) dead session(s), \(sessions.count) remaining")
        }

        // Re-discover sessions to catch any that were missed
        discoverExistingSessions()

        let snapshot = sessions.map { session in
            (
                id: session.id,
                path: session.logFilePath,
                revision: nextLogParseRevision(for: session.id)
            )
        }

        for item in snapshot {
            if fileWatchers[item.id] == nil,
               FileManager.default.fileExists(atPath: item.path),
               let idx = sessions.firstIndex(where: { $0.id == item.id }) {
                watchSessionLog(sessions[idx], parseInitialState: false)
            }
        }

        DispatchQueue.global(qos: .userInteractive).async {
            var updates: [(id: String, newState: ClaudeSessionState, revision: Int)] = []
            for item in snapshot {
                let entries = SessionLogParser.parseLastEntries(from: item.path, count: 20)
                let newState = SessionLogParser.detectState(from: entries)
                updates.append((id: item.id, newState: newState, revision: item.revision))
            }

            DispatchQueue.main.async {
                for update in updates {
                    _ = self.applyParsedState(
                        sessionId: update.id,
                        newState: update.newState,
                        revision: update.revision,
                        updateLastActivity: false
                    )
                }

                self.updateAttentionState()
                self.updatePollingSpeed()

                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                PerfLogger.log("[POLL] pollSessions took \(String(format: "%.1f", elapsed))ms, \(self.sessions.count) sessions")
            }
        }
    }

    private func removeSessionArtifacts(sessionId: String) {
        acknowledgedAttentionSessionIDs.remove(sessionId)
        logParseRevisions.removeValue(forKey: sessionId)
        notificationManager.clearNotification(sessionId: sessionId)
        fileWatchers[sessionId]?.cancel()
        fileWatchers.removeValue(forKey: sessionId)
    }
}
