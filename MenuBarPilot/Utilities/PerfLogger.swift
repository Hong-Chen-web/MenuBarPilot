import Foundation

/// Lightweight async performance logger — writes to /tmp/mbp_perf.txt on a background queue.
/// Does NOT block the main thread.
enum PerfLogger {
    private static let queue = DispatchQueue(label: "com.mbp.perflogger", qos: .utility)
    private static let path = "/tmp/mbp_perf.txt"

    static func log(_ message: String) {
        let timestamp = DateFormatter.iso8601Formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        let lineData = line.data(using: .utf8) ?? Data()

        queue.async {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(lineData)
                handle.closeFile()
            } else {
                try? lineData.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    /// Report current memory footprint (resident & virtual) in MB.
    static func reportMemory(context: String) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let residentMB = Double(info.resident_size) / 1_048_576
            let virtualMB = Double(info.virtual_size) / 1_048_576
            log("[MEM] \(context) — resident: \(String(format: "%.1f", residentMB))MB, virtual: \(String(format: "%.1f", virtualMB))MB")
        }
    }
}

// MARK: - DateFormatter cache

private extension DateFormatter {
    static let iso8601Formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return f
    }()
}
