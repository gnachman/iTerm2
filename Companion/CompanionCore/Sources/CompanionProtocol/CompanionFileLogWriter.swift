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
//  Each line is written with POSIX O_APPEND, so appends are ATOMIC ACROSS
//  PROCESSES (for writes under PIPE_BUF, which a log line always is). iOS can run
//  several NSE instances concurrently for bursty pushes; two overlapping
//  invocations share one -nse.log, and a seek-then-write pair (guarded only by an
//  intra-process lock) would let them clobber each other's lines - corrupting the
//  diagnostics exactly when something is going wrong. O_APPEND avoids that
//  without any cross-process lock.
//

import Foundation

public final class CompanionFileLogWriter: @unchecked Sendable {
    /// UserDefaults key (read from the App Group suite) shared with the app's
    /// logging toggle, so turning logging off in the app also silences the NSE.
    public static let enabledKey = "CompanionFileLoggingEnabled"
    private static let retentionDays = 14

    private let directory: URL
    private let label: String?
    private let isEnabled: () -> Bool
    private let now: () -> Date
    private let lock = NSLock()
    private var fileURL: URL?
    private var prunedAndOpened = false

    /// - label: tags this writer's file names (e.g. "nse") so they are
    ///   distinguishable from another writer's when gathered together.
    /// - now: injected clock (tests pin the per-launch file name).
    public init(directory: URL,
                label: String? = nil,
                now: @escaping () -> Date = { Date() },
                isEnabled: @escaping () -> Bool) {
        self.directory = directory
        self.label = label
        self.now = now
        self.isEnabled = isEnabled
    }

    /// Append one timestamped line. Opens the file with O_APPEND and writes once,
    /// so the append is atomic even against another process writing the same file
    /// (a concurrent NSE instance); a held handle would also need a close we
    /// can't guarantee on extension teardown.
    public func log(_ line: String) {
        guard isEnabled() else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let url = openIfNeeded(),
              let data = (timestamp() + " " + line + "\n").data(using: .utf8) else {
            return
        }
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        // One write() of a sub-PIPE_BUF buffer to an O_APPEND fd is appended
        // atomically: the kernel seeks to EOF and writes with no interleave, so
        // concurrent writers neither overwrite nor tear each other's lines.
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
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
        // Keep logs out of the user's backups (consistent with the app's own log
        // dir); content is counts/prefixes only, but no reason to back it up.
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        if !prunedAndOpened {
            prunedAndOpened = true
            let names = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
            for name in LogFileNaming.expired(names, now: now(), maxAgeDays: Self.retentionDays) {
                try? fm.removeItem(at: directory.appendingPathComponent(name))
            }
        }
        let url = directory.appendingPathComponent(LogFileNaming.fileName(for: now(), label: label))
        fileURL = url
        return url
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: now())
    }
}
