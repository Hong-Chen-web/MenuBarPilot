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

    /// Path to the project directory containing JSONL logs
    var projectDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects/\(encodedCWD)")
            .path
    }

    /// Path to the session JSONL log file.
    /// Scans the project directory for the most recently modified JSONL,
    /// since the filename may differ from sessionId (e.g. after /clear).
    var logFilePath: String {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: projectDirectory) else {
            // Fallback to sessionId-based path
            return (projectDirectory as NSString).appendingPathComponent("\(id).jsonl")
        }
        let jsonlFiles = files.filter { $0.hasSuffix(".jsonl") }
        let sorted = jsonlFiles.compactMap { name -> (String, Date)? in
            let path = (projectDirectory as NSString).appendingPathComponent(name)
            let modDate = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            return modDate.map { (path, $0) }
        }.sorted { $0.1 > $1.1 }
        return sorted.first?.0
            ?? (projectDirectory as NSString).appendingPathComponent("\(id).jsonl")
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
