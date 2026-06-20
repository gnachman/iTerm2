//
//  LogFileNaming.swift
//  CompanionCore
//
//  Naming and retention for the on-device log files: each launch writes one file
//  named YYYY-MM-DD_HH-MM-SS[-label].log (local time, POSIX/sortable), and old
//  files are pruned by the timestamp encoded in the name. The optional label
//  (e.g. "app" / "nse") distinguishes the writer when both processes' files are
//  gathered together. Pure so the date math is tested without touching the
//  filesystem.
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

    /// The file name for a launch at `date`, optionally tagged with a writer
    /// `label` (e.g. "app" / "nse"). Lexical order == chronological order; the
    /// label only breaks ties between same-second files.
    public static func fileName(for date: Date, label: String? = nil) -> String {
        let stamp = formatter().string(from: date)
        if let label, !label.isEmpty {
            return "\(stamp)-\(label)\(suffix)"
        }
        return stamp + suffix
    }

    /// The instant encoded in a log file name, or nil if it is not one of ours.
    /// Accepts both the bare timestamp form and the "-label" form.
    public static func date(from fileName: String) -> Date? {
        guard fileName.hasSuffix(suffix) else { return nil }
        let core = String(fileName.dropLast(suffix.count))
        if let date = formatter().date(from: core) { return date }
        // Strip a trailing "-<label>" (the timestamp itself ends in a digit, so a
        // letters-only tail is unambiguously a label) and retry.
        if let dash = core.lastIndex(of: "-") {
            let tail = core[core.index(after: dash)...]
            if !tail.isEmpty, tail.allSatisfy({ $0.isLetter }) {
                return formatter().date(from: String(core[..<dash]))
            }
        }
        return nil
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
