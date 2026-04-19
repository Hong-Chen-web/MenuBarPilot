import Cocoa

enum ClaudeSessionActivator {
    static func activate(session: ClaudeSession) {
        let pid = session.pid
        PerfLogger.log("[ClaudeActivate] activate session pid=\(pid), cwd=\(session.cwd)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            var currentPID = pid
            for i in 0..<6 {
                if let app = NSRunningApplication(processIdentifier: currentPID) {
                    let bid = app.bundleIdentifier ?? "nil"
                    let policy = app.activationPolicy.rawValue
                    let name = app.localizedName ?? "nil"
                    PerfLogger.log("[ClaudeActivate] step \(i): pid=\(currentPID) bundle=\(bid) name=\(name) policy=\(policy)")

                    if app.bundleIdentifier != nil && app.activationPolicy == .regular {
                        PerfLogger.log("[ClaudeActivate] found GUI app: \(name) (\(bid))")
                        activateApp(app, bundleID: bid)
                        return
                    }
                } else {
                    PerfLogger.log("[ClaudeActivate] step \(i): pid=\(currentPID) — no NSRunningApplication")
                }

                guard let ppidStr = ShellRunner.run("ps -o ppid= -p \(currentPID) 2>/dev/null | tr -d ' '"),
                      let ppid = Int32(ppidStr), ppid > 1 else {
                    PerfLogger.log("[ClaudeActivate] step \(i): no parent for pid=\(currentPID), stopping walk")
                    break
                }
                PerfLogger.log("[ClaudeActivate] step \(i): parent of \(currentPID) is \(ppid)")
                currentPID = pid_t(ppid)
            }

            PerfLogger.log("[ClaudeActivate] fallback: trying pid=\(pid) directly")
            if let app = NSRunningApplication(processIdentifier: pid) {
                let bid = app.bundleIdentifier ?? ""
                activateApp(app, bundleID: bid)
            } else {
                PerfLogger.log("[ClaudeActivate] fallback: no app for pid=\(pid)")
            }
        }
    }

    private static func activateApp(_ app: NSRunningApplication, bundleID: String) {
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
            PerfLogger.log("[ClaudeActivate] using AppleScript for \(bundleID)")
            let result = ShellRunner.runScript(script)
            PerfLogger.log("[ClaudeActivate] AppleScript result: \(result ?? "nil")")
        } else {
            PerfLogger.log("[ClaudeActivate] using activate() for \(bundleID)")
            app.activate(options: [])
        }
    }
}

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
