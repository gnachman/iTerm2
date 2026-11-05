//
//  CommandOutput.swift
//  iTerm2
//
//  Created by George Nachman on 11/2/26.
//

import Foundation

// A finished (or aborted) command's output, captured on the mutation queue when the command ended.
// It is its own text data source holding copies of just the output's lines, so `startLine` and
// `lineCount` stay valid however far the live screen and the main thread's copy of it move on. Line
// numbers keep the screen's numbering as of the capture: lines before `startLine` read as empty, and
// `numberOfLines` is `startLine + lineCount`, like a screen whose grid the output filled. The remote
// host and working directory are those in effect on the command's line.
//
// At most `maxLines` lines are kept, the last ones, since this is captured for every command that
// ends and a command's output can run to millions of lines. `droppedLineCount` says how many
// leading lines were left out; `startLine` is the first kept line.
@objc(iTermCommandOutput)
class CommandOutput: NSObject, iTermTextDataSource {
    @objc static let maxLines: Int32 = 2000

    // MARK: - Consumers

    // Consumers of PTYCommandDidExitNotification that read the output register here while they
    // observe it, so a session captures output only when something will read its output. A consumer
    // registers the reference it observes the session by: its guid, or its stable ID, which
    // outlives the guid (see iTermSessionReferenceKeys). The mutation thread asks when a command
    // ends, so the registry is accessed atomically rather than confined to the main thread, and a
    // change is seen by the next command to end without any hand-off between threads. The counts
    // are how many consumers each reference has.
    private static let consumerCounts = MutableAtomicObject([String: Int]())

    // Whether any of `references` (a session's guid and stable ID) has a consumer. Any thread.
    @objc static func hasConsumers(forSessionReferences references: [String]) -> Bool {
        consumerCounts.access { counts in
            references.contains { counts[$0, default: 0] > 0 }
        }
    }

    // Registers a consumer of the output of the session reached by `reference`. The registration
    // lasts as long as the returned object. Any thread.
    static func addConsumer(forSessionReference reference: String) -> CommandOutputConsumer {
        consumerCounts.mutableAccess { counts in
            counts[reference, default: 0] += 1
        }
        return CommandOutputConsumer(sessionReference: reference)
    }

    fileprivate static func removeConsumer(forSessionReference reference: String) {
        consumerCounts.mutableAccess { counts in
            let count = counts[reference, default: 0]
            it_assert(count > 0, "Unbalanced removeConsumer")
            if count > 1 {
                counts[reference] = count - 1
            } else {
                counts.removeValue(forKey: reference)
            }
        }
    }

    // MARK: - Output

    @objc let startLine: Int32
    @objc let droppedLineCount: Int32
    @objc let remoteHost: VT100RemoteHostReading?
    @objc let workingDirectory: String?
    private let lines: [ScreenCharArray]
    private let _width: Int32
    private let overflow: Int64
    // What a line outside the output reads as. Text extraction probes the lines around the output
    // while range checking, so one shared line rather than one per probe.
    private let emptyLine: ScreenCharArray

    @objc var lineCount: Int32 {
        Int32(lines.count)
    }

    // `lines` are the output's lines, starting at line `startLine` of a screen `width` columns wide
    // whose scrollback overflow is `overflow`, with `droppedLineCount` lines of output before them
    // left out. They must not share memory with the live screen.
    @objc
    init(lines: [ScreenCharArray],
         startLine: Int32,
         droppedLineCount: Int32,
         width: Int32,
         overflow: Int64,
         remoteHost: VT100RemoteHostReading?,
         workingDirectory: String?) {
        it_assert(lines.count <= Int(CommandOutput.maxLines), "Too many lines captured")
        self.lines = lines
        self.startLine = startLine
        self.droppedLineCount = droppedLineCount
        _width = width
        self.overflow = overflow
        emptyLine = ScreenCharArray.emptyLine(ofLength: width)
        self.remoteHost = remoteHost
        self.workingDirectory = workingDirectory
    }

    private func line(_ line: Int32) -> ScreenCharArray? {
        let index = Int(line - startLine)
        guard lines.indices.contains(index) else {
            return nil
        }
        return lines[index]
    }

    // MARK: - iTermTextDataSource

    func width() -> Int32 {
        _width
    }

    func numberOfLines() -> Int32 {
        startLine + lineCount
    }

    func screenCharArray(forLine line: Int32) -> ScreenCharArray {
        self.line(line) ?? emptyLine
    }

    func screenCharArray(atScreenIndex index: Int32) -> ScreenCharArray {
        // A screen index is a grid row, and there is no grid here.
        it_fatalError("Command output has no screen rows")
    }

    func totalScrollbackOverflow() -> Int64 {
        overflow
    }

    func externalAttributeIndex(forLine y: Int32) -> iTermExternalAttributeIndexReading? {
        guard let line = line(y) else {
            return nil
        }
        return iTermImmutableMetadataGetExternalAttributesIndex(line.metadata)
    }

    func fetchLine(_ line: Int32, block: (ScreenCharArray) -> Any?) -> Any? {
        block(screenCharArray(forLine: line))
    }

    func date(forLine line: Int32) -> Date? {
        guard let line = self.line(line) else {
            return nil
        }
        let timestamp = line.metadata.timestamp
        if timestamp == 0 {
            return nil
        }
        return Date(timeIntervalSinceReferenceDate: timestamp)
    }

    func commandMark(at coord: VT100GridCoord,
                     mustHaveCommand: Bool,
                     range: UnsafeMutablePointer<VT100GridWindowedRange>?) -> VT100ScreenMarkReading? {
        nil
    }

    func metadata(onLine lineNumber: Int32) -> iTermImmutableMetadata {
        screenCharArray(forLine: lineNumber).metadata
    }

    func isFirstLine(ofBlock lineNumber: Int32) -> Bool {
        false
    }
}

// A consumer's registration with CommandOutput. It ends when this is released, which may happen on
// any thread, since a consumer's last reference can be dropped by a background completion.
final class CommandOutputConsumer {
    let sessionReference: String

    fileprivate init(sessionReference: String) {
        self.sessionReference = sessionReference
    }

    deinit {
        CommandOutput.removeConsumer(forSessionReference: sessionReference)
    }
}
