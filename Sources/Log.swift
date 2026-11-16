import Foundation

private let logQueue = DispatchQueue(label: "stanza.log")
private let maxLogBytes = 1_000_000
private let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Stanza.log")
private let logStamp: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return formatter
}()

/// Appends a line to ~/Library/Logs/Stanza.log and to stderr.
func log(_ message: String) {
    let now = Date()
    logQueue.async {
        let line = Data("\(logStamp.string(from: now))  \(message)\n".utf8)
        FileHandle.standardError.write(line)
        // Start over rather than grow without bound.
        let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? 0
        if size > maxLogBytes { try? FileManager.default.removeItem(at: logURL) }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            // First run: the file does not exist yet. If this also fails, stderr still has the line.
            try? line.write(to: logURL)
        }
    }
}
