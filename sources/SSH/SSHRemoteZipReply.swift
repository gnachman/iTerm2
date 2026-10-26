//
//  SSHRemoteZipReply.swift
//  iTerm2
//
//  Created by George Nachman on 10/26/26.
//

import Foundation

/// What framer.py's zip command reports: where it put the archive of a remote folder and
/// what it couldn't read and left out of it (F-721).
struct SSHRemoteZipReply: Equatable {
    /// The argument that asks the framer for a JSON reply that lists what it left out. A
    /// framer that predates it ignores it and replies with just the archive's path.
    static let reportSkippedArgument = "report-skipped"

    /// The archive's path on the remote host.
    var path: String
    /// How many files and folders couldn't be read and were left out of the archive.
    var skippedCount: Int
    /// The first few of them, relative to the zipped folder. Folders end in a slash.
    var skippedExamples: [String]

    private struct JSONReply: Decodable {
        var path: String
        var skipped: Int
        var examples: [String]?
    }

    init(path: String, skippedCount: Int = 0, skippedExamples: [String] = []) {
        self.path = path
        self.skippedCount = skippedCount
        self.skippedExamples = skippedExamples
    }

    /// Parses the framer's reply. A newer framer sends JSON; an older one sends the bare
    /// path, which can't begin with a brace since it is absolute.
    init(framerOutput: String) {
        if framerOutput.hasPrefix("{"),
           let data = framerOutput.data(using: .utf8),
           let json = try? JSONDecoder().decode(JSONReply.self, from: data) {
            self.init(path: json.path,
                      skippedCount: max(0, json.skipped),
                      skippedExamples: json.examples ?? [])
        } else {
            self.init(path: framerOutput)
        }
    }

    /// A sentence telling the user what was left out, or nil if nothing was.
    var skippedItemsNote: String? {
        guard skippedCount > 0 else {
            return nil
        }
        if skippedCount == 1, let name = skippedExamples.first {
            return String(localized: "SSHRemoteZip.OneItemSkipped",
                          defaultValue: "“\(name)” couldn’t be read and was left out.",
                          comment: "Shown when an SSH Integration folder download finished but one file or folder in it could not be read on the remote host and is missing from the download; the argument is its path relative to the downloaded folder")
        }
        if skippedCount == 2, skippedExamples.count >= 2 {
            let first = skippedExamples[0]
            let second = skippedExamples[1]
            return String(localized: "SSHRemoteZip.TwoItemsSkipped",
                          defaultValue: "“\(first)” and “\(second)” couldn’t be read and were left out.",
                          comment: "Shown when an SSH Integration folder download finished but two files or folders in it could not be read on the remote host and are missing from the download; the arguments are their paths relative to the downloaded folder")
        }
        let count = skippedCount
        let summary = String(localized: "SSHRemoteZip.ItemsSkipped",
                             defaultValue: "\(count) items couldn’t be read and were left out.",
                             comment: "Shown when an SSH Integration folder download finished but some files or folders in it could not be read on the remote host and are missing from the download; the argument is how many")
        guard let name = skippedExamples.first else {
            return summary
        }
        let example = String(localized: "SSHRemoteZip.SkippedExample",
                             defaultValue: "One of them is “\(name)”.",
                             comment: "Follows the sentence saying how many files or folders were left out of an SSH Integration folder download because they could not be read; the argument is the path of one of them relative to the downloaded folder")
        return summary + " " + example
    }
}
