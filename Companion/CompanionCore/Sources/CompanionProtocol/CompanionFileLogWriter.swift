//
//  CompanionFileLogWriter.swift
//  CompanionCore
//
//  A simple, synchronous on-disk log writer suited to a SHORT-LIVED process: the
//  Notification Service Extension wakes, writes a handful of lines, and dies, so
//  unlike the app's long-lived buffered logger (CompanionFileLog) it needs no
//  flush timer or background queue - it just appends each line. Both write into
//  the shared App Group Logs directory and use LogFileNaming, so the app's
//  Settings "email logs" picks up the extension's files too and the lines
//  interleave chronologically.
//

import Foundation

public final class CompanionFileLogWriter: @unchecked Sendable {
    /// UserDefaults key (read from the App Group suite) shared with the app's
    /// logging toggle, so turning logging off in the app also silences the NSE.
    public static let enabledKey = "CompanionFileLoggingEnabled"
    private static let retentionDays = 14

    private let directory: URL
    private let isEnabled: () -> Bool
    private let lock = NSLock()
    private var fileURL: URL?
    private var prunedAndOpened = false

    public init(directory: URL, isEnabled: @escaping () -> Bool) {
        self.directory = directory
        self.isEnabled = isEnabled
    }

    /// Append one line (timestamped). Cheap enough for a process that logs a
    /// dozen lines; a held handle would only need a close we can't guarantee on
    /// extension teardown, so each line opens, appends, and closes.
    public func log(_ line: String) {
        guard isEnabled() else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let url = openIfNeeded(),
              let data = (Self.timestamp() + " " + line + "\n").data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: url) else {
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    /// This directory's log files, oldest first.
    public func logFileURLs() -> [URL] {
        Self.logFileURLs(in: directory)
    }

    /// The log files in `directory`, oldest first (names sort chronologically).
    /// Static so the app can enumerate the shared directory without a writer.
    public static func logFileURLs(in directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { LogFileNaming.date(from: $0) != nil }
            .sorted()
            .map { directory.appendingPathComponent($0) }
    }

    // MARK: - lock-held

    private func openIfNeeded() -> URL? {
        if let fileURL { return fileURL }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if !prunedAndOpened {
            prunedAndOpened = true
            let names = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
            for name in LogFileNaming.expired(names, now: Date(), maxAgeDays: Self.retentionDays) {
                try? fm.removeItem(at: directory.appendingPathComponent(name))
            }
        }
        let url = directory.appendingPathComponent(LogFileNaming.fileName(for: Date()))
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        fileURL = url
        return url
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
