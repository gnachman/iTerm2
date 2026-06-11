// Best-effort file log at ~/Library/Logs/iterm2-keeper-adapter.log (stdout is JSON).

import Foundation

enum KeeperAdapterLog {
    static let defaultURL: URL = {
        let logsDir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Logs")
        let dir = logsDir ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("iterm2-keeper-adapter.log")
    }()

    static let isEnabled: Bool = {
        ProcessInfo.processInfo.environment["ITERM2_KEEPER_ADAPTER_LOG_DISABLED"] == nil
    }()

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // Synchronous so short-lived CLI processes do not drop lines on exit.
    private static let lock = NSLock()

    static func write(_ message: String) {
        guard isEnabled else { return }
        let stamp = formatter.string(from: Date())
        let line = "[\(stamp)] [\(getpid())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }
        if let handle = try? FileHandle(forWritingTo: defaultURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: defaultURL, options: .atomic)
        }
    }
}
