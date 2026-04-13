import Foundation

/// Represents a Claude Code session discovered from ~/.claude/sessions/
struct ClaudeSession: Identifiable {
    let id: String  // sessionId
    let pid: pid_t
    let cwd: String
    let startedAt: Date
    let kind: String
    let entrypoint: String

    var state: ClaudeSessionState = .idle
    var lastActivity: Date?
    var waitingReason: String?

    /// Encoded path for the project directory
    /// e.g., /Users/chenhong/AI -> -Users-chenhong-AI
    var encodedCWD: String {
        cwd.map { $0 == "/" ? "-" : String($0) }.joined()
    }

    /// Path to the session JSONL log file
    var logFilePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects/\(encodedCWD)/\(id).jsonl")
            .path
    }

    /// Whether the process is still running
    var isProcessAlive: Bool {
        kill(pid, 0) == 0
    }
}

/// State of a Claude Code session
enum ClaudeSessionState: String {
    case idle = "Idle"
    case running = "Running"
    case waitingForInput = "Awaiting Input"
    case ended = "Ended"

    var systemImage: String {
        switch self {
        case .idle: return "moon.zzz"
        case .running: return "play.fill"
        case .waitingForInput: return "hand.raised.fill"
        case .ended: return "stop.fill"
        }
    }

    var color: String {
        switch self {
        case .idle: return "gray"
        case .running: return "green"
        case .waitingForInput: return "orange"
        case .ended: return "gray"
        }
    }

    var needsAttention: Bool {
        self == .waitingForInput
    }
}
