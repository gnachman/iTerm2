//
//  LogFileNaming.swift
//  CompanionCore
//
//  Naming and retention for the on-device log files: each launch writes one file
//  named YYYY-MM-DD_HH-MM-SS.log (local time, POSIX/sortable), and old files are
//  pruned by the timestamp encoded in the name. Pure so the date math is tested
//  without touching the filesystem.
//

import Foundation

public enum LogFileNaming {
    public static let suffix = ".log"

    private static func formatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }

    /// The file name for a launch at `date`. Lexical order == chronological order.
    public static func fileName(for date: Date) -> String {
        formatter().string(from: date) + suffix
    }

    /// The instant encoded in a log file name, or nil if it is not one of ours.
    public static func date(from fileName: String) -> Date? {
        guard fileName.hasSuffix(suffix) else { return nil }
        return formatter().date(from: String(fileName.dropLast(suffix.count)))
    }

    /// The names whose encoded timestamp is older than `maxAgeDays` before `now`.
    /// Names that are not ours (do not parse) are never returned, so a prune pass
    /// only ever deletes log files it created.
    public static func expired(_ names: [String], now: Date, maxAgeDays: Int) -> [String] {
        let cutoff = now.addingTimeInterval(-Double(maxAgeDays) * 86_400)
        return names.filter { name in
            guard let d = date(from: name) else { return false }
            return d < cutoff
        }
    }
}
