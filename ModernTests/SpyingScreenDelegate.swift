//
//  SpyingScreenDelegate.swift
//  iTerm2
//
//  Created for testing working directory flow.
//

import Foundation
@testable import iTerm2SharedARC

/// Records calls to VT100ScreenDelegate methods for test verification
class SpyingScreenDelegate: FakeSession {
    // Call records
    struct GetWorkingDirectoryCall {}
    struct PollLocalDirectoryOnlyCall {}
    struct LogWorkingDirectoryCall {
        let path: String?
        let line: Int64
    }
    struct CurrentDirectoryDidChangeCall {
        let path: String
    }
    struct PromptDidStartCall {
        let line: Int32
    }
    struct PromptDidEndCall {
        let mark: any VT100ScreenMarkReading
    }
    struct CommandDidChangeCall {
        let command: String
        let atPrompt: Bool
        let hadCommand: Bool
        let haveCommand: Bool
    }

    // MARK: - Configurable Return Values

    /// Value to return from screenGetWorkingDirectory polling.
    /// Set this to test scenarios where the poller returns an actual directory.
    var polledWorkingDirectory: String?

    // MARK: - Call Records

    private(set) var getWorkingDirectoryCalls: [GetWorkingDirectoryCall] = []
    private(set) var pollLocalDirectoryOnlyCalls: [PollLocalDirectoryOnlyCall] = []
    private(set) var logWorkingDirectoryCalls: [LogWorkingDirectoryCall] = []
    private(set) var currentDirectoryDidChangeCalls: [CurrentDirectoryDidChangeCall] = []
    private(set) var promptDidStartCalls: [PromptDidStartCall] = []
    private(set) var promptDidEndCalls: [PromptDidEndCall] = []
    private(set) var commandDidChangeCalls: [CommandDidChangeCall] = []

    func reset() {
        getWorkingDirectoryCalls.removeAll()
        pollLocalDirectoryOnlyCalls.removeAll()
        logWorkingDirectoryCalls.removeAll()
        currentDirectoryDidChangeCalls.removeAll()
        promptDidStartCalls.removeAll()
        promptDidEndCalls.removeAll()
        commandDidChangeCalls.removeAll()
    }

    // MARK: - Overrides

    override func screenGetWorkingDirectory(completion: @escaping (String?) -> Void) {
        getWorkingDirectoryCalls.append(GetWorkingDirectoryCall())
        completion(polledWorkingDirectory)
    }

    override func screenPollLocalDirectoryOnly() {
        pollLocalDirectoryOnlyCalls.append(PollLocalDirectoryOnlyCall())
    }

    override func screenLogWorkingDirectory(onAbsoluteLine line: Int64,
                                            remoteHost: (any VT100RemoteHostReading)?,
                                            withDirectory directory: String?,
                                            pushType: VT100ScreenWorkingDirectoryPushType,
                                            accepted: Bool) {
        logWorkingDirectoryCalls.append(LogWorkingDirectoryCall(path: directory, line: line))
    }

    override func screenCurrentDirectoryDidChange(to newPath: String?, remoteHost: (any VT100RemoteHostReading)?) {
        if let path = newPath {
            currentDirectoryDidChangeCalls.append(CurrentDirectoryDidChangeCall(path: path))
        }
    }

    override func screenPromptDidStart(atLine line: Int32) {
        promptDidStartCalls.append(PromptDidStartCall(line: line))
    }

    override func screenPromptDidEnd(withMark mark: any VT100ScreenMarkReading) {
        promptDidEndCalls.append(PromptDidEndCall(mark: mark))
    }

    override func screenCommandDidChange(to command: String,
                                         atPrompt: Bool,
                                         hadCommand: Bool,
                                         haveCommand: Bool) {
        commandDidChangeCalls.append(CommandDidChangeCall(command: command,
                                                          atPrompt: atPrompt,
                                                          hadCommand: hadCommand,
                                                          haveCommand: haveCommand))
    }

    // Mirror PTYSession.screenResizeResilientCoordinates: so primary-main
    // pool doppelganger RCs see the same converter the mutation-thread
    // pool got. Without this override main-pool doppelgangers miss every
    // primary-tree resize broadcast (production posts via PTYSession).
    override func screenResizeResilientCoordinates(_ convert: @escaping (VT100GridAbsCoord) -> VT100GridAbsCoord) {
        guard let screen else { return }
        let block: @convention(block) (VT100GridAbsCoord) -> VT100GridAbsCoord = { coord in
            convert(coord)
        }
        RCResizeNotification.post(guid: screen.immutableState.mainThreadPoolGuid,
                                  converter: block)
    }

    // Mirror PTYSession.screenResizeResilientCoordinatesForSavedTree:
    // so saved-tree doppelganger RCs see the alt-linebuffer-based resize
    // converter under tests. Re-wrap as @convention(block) — without that
    // the closure stored into userInfo is a Swift function, not an ObjC
    // block, and the cast in VT100GridAbsCoordByInvokingConverter crashes.
    override func screenResizeResilientCoordinates(forSavedTree convert: @escaping (VT100GridAbsCoord) -> VT100GridAbsCoord,
                                                   guid savedTreeMainGuid: String) {
        let block: @convention(block) (VT100GridAbsCoord) -> VT100GridAbsCoord = { coord in
            convert(coord)
        }
        RCResizeNotification.post(guid: savedTreeMainGuid, converter: block)
    }

    // Mirror PTYSession.screenDidShiftLinesAtAbsLine: repost the linesShifted
    // notification on the main-thread RC pool guid so doppelganger RCs see
    // fold/unfold/porthole shifts in tests (no real session in the way).
    override func screenDidShiftLines(atAbsLine absLine: Int64,
                                      by delta: Int64,
                                      mark: (any iTermWidthSavingMark)?,
                                      reason: iTermLinesShiftedReason,
                                      replacedRange: NSRange,
                                      converter: @escaping (VT100GridCoord) -> VT100GridCoord) {
        guard let screen else { return }
        var userInfo: [AnyHashable: Any] = [
            LinesShiftedNotification.absLineKey: NSNumber(value: absLine),
            LinesShiftedNotification.deltaKey: NSNumber(value: Int32(delta)),
            LinesShiftedNotification.reasonKey: NSNumber(value: reason.rawValue),
            LinesShiftedNotification.replacedRangeKey: NSValue(range: replacedRange),
            LinesShiftedNotification.converterKey: converter,
        ]
        if let mark {
            userInfo[LinesShiftedNotification.markKey] = mark
        }
        NotificationCenter.default.post(
            name: LinesShiftedNotification.name,
            object: screen.immutableState.mainThreadPoolGuid,
            userInfo: userInfo)
    }
}
