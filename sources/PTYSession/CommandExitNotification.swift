//
//  CommandExitNotification.swift
//  iTerm2
//
//  Created by George Nachman on 11/3/26.
//

import Foundation

// What PTYCommandDidExitNotification reports about a command that ended, decoded for the consumers
// that save or send its output (AI Chat and Codecierge). The notification's userInfo has no type
// contract, so a post without the keys every command has decodes as nil instead of crashing an
// observer.
struct CommandExitNotification {
    let command: String
    // 0 when the command was aborted rather than exiting.
    let exitCode: Int32
    let directory: String?
    let remoteHost: VT100RemoteHostReading?
    let url: URL
    // The command's output as text, or nil when it wasn't captured because the command had no mark.
    // When only the last lines were kept, the text begins with a line saying how many were left out.
    let output: String?

    init?(userInfo: [AnyHashable: Any]) {
        guard let command = userInfo[PTYCommandDidExitUserInfoKeyCommand] as? String,
              let url = userInfo[PTYCommandDidExitUserInfoKeyURL] as? URL else {
            return nil
        }
        self.command = command
        self.url = url
        exitCode = (userInfo[PTYCommandDidExitUserInfoKeyExitCode] as? Int32) ?? 0
        directory = userInfo[PTYCommandDidExitUserInfoKeyDirectory] as? String
        remoteHost = userInfo[PTYCommandDidExitUserInfoKeyRemoteHost] as? VT100RemoteHostReading
        output = Self.outputText(userInfo)
    }

    // The line that heads a command's output when only its last lines were kept. The chat shows
    // it with the output as part of the command's message, so it is localized, with its number
    // agreement coming from the catalog's plural.
    static func omittedLinesNote(_ count: Int32) -> String {
        String(localized: "CommandExit.OmittedLinesNote",
               defaultValue: "[\(Int(count)) earlier lines of output omitted.]",
               comment: "Line shown above a command’s output when only its last lines were kept; the placeholder is how many lines were left out")
    }

    private static func outputText(_ userInfo: [AnyHashable: Any]) -> String? {
        guard let dataSource = userInfo[PTYCommandDidExitUserInfoKeyDataSource] as? iTermTextDataSource,
              let startLine = userInfo[PTYCommandDidExitUserInfoKeyStartLine] as? Int32,
              let lineCount = userInfo[PTYCommandDidExitUserInfoKeyLineCount] as? Int32 else {
            return nil
        }
        let extractor = iTermTextExtractor(dataSource: dataSource)
        let text = extractor.content(
            in: VT100GridWindowedRange(
                coordRange: VT100GridCoordRange(
                    start: VT100GridCoord(x: 0, y: startLine),
                    end: VT100GridCoord(x: 0, y: startLine + lineCount)),
                columnWindow: VT100GridRange(location: 0, length: 0)),
            attributeProvider: nil,
            nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
            pad: false,
            includeLastNewline: false,
            trimTrailingWhitespace: true,
            cappedAtSize: -1,
            truncateTail: false,
            continuationChars: nil,
            coords: nil,
            deduplicateDECDHL: true) as! String
        let droppedLineCount = (userInfo[PTYCommandDidExitUserInfoKeyDroppedLineCount] as? Int32) ?? 0
        if droppedLineCount > 0 {
            return omittedLinesNote(droppedLineCount) + "\n" + text
        }
        return text
    }
}
