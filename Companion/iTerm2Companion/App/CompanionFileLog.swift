//
//  CompanionFileLog.swift
//  iTerm2 Companion
//
//  Mirrors every companionLog line to a file on disk so a failure in the wild
//  (TestFlight) can be retrieved and emailed, since the unified log is otherwise
//  unreachable. Each launch opens a fresh file named YYYY-MM-DD_HH-MM-SS.log;
//  lines are buffered and appended on a background queue and flushed to disk
//  once a second; files older than the retention window are pruned at launch.
//  Enabled by default (so a crash is captured without opting in first); the
//  Settings screen can turn it off and email the files.
//

import Foundation
import CompanionProtocol

final class CompanionFileLog: @unchecked Sendable {
    static let shared = CompanionFileLog()

    private static let enabledKey = CompanionFileLogWriter.enabledKey
    private static let retentionDays = 14

    /// The toggle lives in the App Group suite so the NSE honors the same flag.
    private static var settingsDefaults: UserDefaults {
        UserDefaults(suiteName: CompanionSharedIdentifiers.appGroup) ?? .standard
    }

    /// The shared App Group Logs directory the NSE writes into (nil if the
    /// container is unavailable).
    private static var appGroupLogsDirectory: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CompanionSharedIdentifiers.appGroup)?
            .appendingPathComponent("Logs", isDirectory: true)
    }

    private let queue = DispatchQueue(label: "com.googlecode.iterm2.companion.filelog", qos: .utility)
    private var handle: FileHandle?
    private var buffer = Data()
    private var timer: DispatchSourceTimer?
    private var started = false

    private init() {}

    /// On by default: a problem in the wild should be captured without the user
    /// opting in first. Toggling rotates the writer immediately.
    var isEnabled: Bool {
        get {
            return Self.settingsDefaults.object(forKey: Self.enabledKey) as? Bool ?? true
        }
        set {
            Self.settingsDefaults.set(newValue, forKey: Self.enabledKey)
            queue.async {
                if newValue {
                    self.openIfNeeded()
                } else {
                    // Turning logging off discards the history: close the writer
                    // and delete the files on disk.
                    self.close()
                    self.deleteAll()
                }
            }
        }
    }

    /// Append one already-formatted line. Cheap for the caller: the work hops to
    /// a background queue; the disk write happens on the once-a-second flush.
    func log(_ line: String) {
        guard isEnabled else { return }
        queue.async {
            // Re-check on the queue: this block can be enqueued before a
            // toggle-off, so without it a straggler would buffer a line that
            // surfaces in a later session's file once logging is re-enabled.
            guard self.isEnabled else { return }
            self.openIfNeeded()
            self.buffer.append(Data((line + "\n").utf8))
        }
    }

    /// Flush pending lines synchronously, so the files are current before they
    /// are read (e.g. just before emailing).
    func flushNow() {
        queue.sync { self.flush() }
    }

    /// The on-disk log files, oldest first: the app's own plus the NSE's (in the
    /// shared App Group directory), so emailing includes both. Both directories
    /// use LogFileNaming, so file names sort chronologically across them.
    func logFileURLs() -> [URL] {
        var urls = CompanionFileLogWriter.logFileURLs(in: Self.logsDirectory)
        if let nse = Self.appGroupLogsDirectory {
            urls += CompanionFileLogWriter.logFileURLs(in: nse)
        }
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The outcome of building the emailable log archive.
    enum LogArchiveResult: Sendable {
        /// A ready-to-attach .zip at this URL.
        case archive(URL)
        /// There were no log files to archive (nothing to email).
        case empty
        /// Building the archive failed; the underlying error was logged.
        case failed
    }

    /// Flush pending lines and bundle every log file into a single .zip in a
    /// temp directory. One compressed archive gets through the mail composer
    /// where a handful of multi-megabyte text attachments do not. Safe to call
    /// off the main thread (the copy + zip can be slow for a large history) and
    /// distinguishes "no logs" from a real failure so the caller can tell the
    /// user which happened; a real failure is logged before returning.
    func makeLogArchive() -> LogArchiveResult {
        flushNow()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("iTerm2-Buddy-logs.zip")
        do {
            try CompanionLogArchive.write(files: logFileURLs(), to: destination)
            return .archive(destination)
        } catch CompanionLogArchive.ArchiveError.nothingToArchive {
            return .empty
        } catch {
            companionLog("Email Logs: could not build the log archive: \(error)")
            return .failed
        }
    }

    // MARK: - queue-only

    private func openIfNeeded() {
        guard !started else { return }
        // A log() call can pass its isEnabled guard, then get enqueued behind a
        // toggle-off (which sets the default synchronously, then enqueues close +
        // deleteAll). Re-check here so a straggler can't recreate a fresh file
        // after the user turned logging off and we deleted the history.
        guard isEnabled else { return }
        started = true
        let fm = FileManager.default
        var dir = Self.logsDirectory
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        prune()
        let url = dir.appendingPathComponent(LogFileNaming.fileName(for: Date(), label: "app"))
        fm.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.flush() }
        timer.resume()
        self.timer = timer
    }

    private func close() {
        flush()
        timer?.cancel()
        timer = nil
        try? handle?.close()
        handle = nil
        started = false
    }

    private func flush() {
        guard !buffer.isEmpty, let handle else { return }
        let data = buffer
        buffer.removeAll(keepingCapacity: true)
        try? handle.write(contentsOf: data)
        try? handle.synchronize() // flush to disk
    }

    private func prune() {
        let dir = Self.logsDirectory
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in LogFileNaming.expired(names, now: Date(), maxAgeDays: Self.retentionDays) {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    private func deleteAll() {
        let fm = FileManager.default
        // Both the app's own directory and the shared NSE directory, so turning
        // logging off clears all history. Only our own log files, never anything
        // else that may share the folder.
        for dir in [Self.logsDirectory, Self.appGroupLogsDirectory].compactMap({ $0 }) {
            let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in names where LogFileNaming.date(from: name) != nil {
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }

    private static var logsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
    }
}
