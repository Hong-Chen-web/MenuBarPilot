import Foundation

/// Parses Claude Code session JSONL log files to determine state.
struct SessionLogParser {

    /// Represents a parsed line from the JSONL log
    struct LogEntry {
        let type: String
        let stopReason: String?
        let timestamp: Date?
        let isToolResult: Bool
        let isMeta: Bool
        let toolUseResult: Any? // present when this is a tool result response
        let toolNames: [String] // tool names from assistant content blocks

        init?(from json: [String: Any]) {
            guard let type = json["type"] as? String else { return nil }
            self.type = type
            self.isMeta = json["isMeta"] as? Bool ?? false
            self.toolUseResult = json["toolUseResult"]

            // Extract stop_reason from nested message object
            // Format: {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"},...}
            if let message = json["message"] as? [String: Any] {
                self.stopReason = message["stop_reason"] as? String

                // Extract tool names from message content blocks
                // Format: {"message":{"content":[{"type":"tool_use","name":"Read",...},...]}}
                if let content = message["content"] as? [[String: Any]] {
                    self.toolNames = content.compactMap { block in
                        guard (block["type"] as? String) == "tool_use" else { return nil }
                        return block["name"] as? String
                    }
                } else {
                    self.toolNames = []
                }
            } else {
                self.stopReason = nil
                self.toolNames = []
            }

            // Check if this is a tool result (user responding to a tool_use)
            // Format: {"type":"user","toolUseResult":{...},...}
            self.isToolResult = json["toolUseResult"] != nil

            if let ts = json["timestamp"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                self.timestamp = formatter.date(from: ts)
            } else {
                self.timestamp = nil
            }
        }
    }

    /// Parse the last N entries from a JSONL file
    static func parseLastEntries(from filePath: String, count: Int = 20) -> [LogEntry] {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return []
        }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        let lastLines = Array(lines.suffix(count))

        var entries: [LogEntry] = []
        for line in lastLines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entry = LogEntry(from: json) else {
                continue
            }
            entries.append(entry)
        }

        return entries
    }

    /// Determine the current state from the last entries.
    /// The list is in chronological order (oldest first).
    static func detectState(from entries: [LogEntry]) -> ClaudeSessionState {
        // Skip meta entries, look for the last meaningful one
        let meaningful = entries.filter { !$0.isMeta }
        guard let last = meaningful.last else {
            // No meaningful entries — session just started, idle
            return .idle
        }

        switch last.type {
        case "assistant":
            return detectAssistantState(last)

        case "user":
            // User just sent a message or tool result — Claude is working
            return .running

        case "attachment":
            return .running

        case "system", "permission-mode", "file-history-snapshot", "queue-operation":
            // Internal bookkeeping — check previous meaningful entry
            if meaningful.count >= 2 {
                let prev = meaningful[meaningful.count - 2]
                if prev.type == "assistant" {
                    return detectAssistantState(prev)
                } else if prev.type == "user" {
                    return .running
                }
            }
            return .idle

        default:
            return .idle
        }
    }

    /// Determine state from an assistant log entry.
    /// Only "needs attention" when Claude presents AskUserQuestion options.
    private static func detectAssistantState(_ entry: LogEntry) -> ClaudeSessionState {
        guard let stopReason = entry.stopReason else {
            // No stop reason — still streaming
            return .running
        }

        switch stopReason {
        case "tool_use":
            // Only needs attention for interactive tools that present options (1, 2, 3)
            if entry.toolNames.contains("AskUserQuestion") {
                return .waitingForInput
            }
            // Auto-executed tools (Read, Bash, Grep, Glob, etc.) — actively working
            return .running

        case "end_turn":
            // Claude finished its turn — idle
            return .idle

        default:
            return .running
        }
    }
}
