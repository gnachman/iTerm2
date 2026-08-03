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
        let f = formatter()
        if let date = f.date(from: core) { return date }   // bare "<timestamp>"
        // Labeled "<timestamp>-<label>". The timestamp is FIXED WIDTH, so parse
        // its prefix and let the label be anything after the separating hyphen -
        // digits and hyphens included (e.g. "nse2", "nse-1"). The earlier
        // letters-only rule silently failed to parse those, leaking the file from
        // pruning and the emailed export.
        let stampLength = f.string(from: Date(timeIntervalSince1970: 0)).count
        guard core.count > stampLength else { return nil }
        let separator = core.index(core.startIndex, offsetBy: stampLength)
        guard core[separator] == "-" else { return nil }
        return f.date(from: String(core[..<separator]))
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
