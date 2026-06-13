//
//  TerminalTestHarness.swift
//  iTerm2
//
//  Created for testing working directory flow.
//

import Foundation
import XCTest
@testable import iTerm2SharedARC

/// Test harness for terminal escape sequence processing.
/// Provides convenient setup for testing VT100Screen flow.
class TerminalTestHarness {
    let screen: VT100Screen
    let delegate: SpyingScreenDelegate

    init(width: Int = 80, height: Int = 24) {
        delegate = SpyingScreenDelegate()
        screen = VT100Screen()

        screen.delegate = delegate
        delegate.screen = screen

        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal?.termType = "xterm"
            self.screen.destructivelySetScreenWidth(Int32(width),
                                                    height: Int32(height),
                                                    mutableState: mutableState)
        })
    }

    /// Send OSC 7 working directory escape sequence
    func sendOSC7(path: String, host: String? = nil) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            if let host = host {
                mutableState.setWorkingDirectoryFromURLString("file://\(host)\(path)")
            } else {
                mutableState.setWorkingDirectoryFromURLString("file://\(path)")
            }
        })
    }

    /// Send shell integration: Set remote host (FinalTerm OSC 1337)
    func sendRemoteHost(user: String, host: String) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setRemoteHostFrom("\(user)@\(host)")
        })
    }

    /// Send shell integration: Set current directory (FinalTerm OSC 1337)
    func sendCurrentDirectory(path: String) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.currentDirectoryDidChange(to: path, completion: {})
        })
    }

    /// Send window title change escape sequence
    /// This triggers the directory polling logic
    func sendWindowTitle(_ title: String) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            // VT100ScreenMutableState conforms to VT100TerminalDelegate
            mutableState.terminalSetWindowTitle(title)
        })
    }

    // MARK: - FinalTerm / OSC 133 shell integration

    /// Send FinalTerm A (prompt start). Cursor position at call time is where the
    /// prompt mark is created. `freshLine:true` matches OSC 133;A; pass `false`
    /// to simulate OSC 133;P (no implicit CR+LF if cursor is mid-line). Pass a
    /// non-nil `aid` to simulate OSC 133;A;aid=<id> from an aid-emitting shell.
    func sendPromptStart(wasInCommand: Bool = false,
                         kind: VT100PromptKind = .initial,
                         freshLine: Bool = true,
                         aid: String? = nil) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalPromptDidStart(wasInCommand,
                                                kind: kind,
                                                freshLine: freshLine,
                                                aid: aid)
        })
    }

    /// Send FinalTerm B (command read start / prompt end). Cursor position at call time
    /// marks where the user's typed command begins.
    func sendCommandStart() {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalCommandDidStart()
        })
    }

    /// Send FinalTerm C (command read end / output start). Cursor position at call time
    /// marks where command output begins.
    func sendCommandEnd() {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalCommandDidEnd()
        })
    }

    /// Send FinalTerm D;<code> (return code). Pass `aid` to take the
    /// close-by-aid path (close the mark with that aid + cascade-close
    /// descendants); nil aid uses today's topmost-open behavior. Pass
    /// nil for `code` to simulate `D;aid=X` (no integer exit code) — the
    /// target mark closes but its hasCode stays false.
    func sendReturnCode(_ code: Int32?, aid: String? = nil) {
        let boxed: NSNumber? = code.map { NSNumber(value: $0) }
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalReturnCode(ofLastCommandWas: boxed, aid: aid)
        })
    }

    /// Send FinalTerm D-while-inCommand (the abort path). Drives the
    /// receiver directly because the parser's `inCommand_` state is
    /// VT100Terminal-internal and isn't reachable from this harness's
    /// other helpers.
    func sendAbort(aid: String? = nil) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalAbortCommand(withAid: aid)
        })
    }

    /// Append literal text at cursor.
    func appendText(_ text: String) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: text)
        })
    }

    /// Move cursor to a new line (CR+LF).
    func newline() {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendCarriageReturnLineFeed()
        })
    }

    // MARK: - State accessors for assertions

    /// The most recent mark that represents a command (may be running or finished).
    var lastCommandMark: (any VT100ScreenMarkReading)? {
        return screen.lastCommandMark()
    }

    /// The most recent prompt mark.
    var lastPromptMark: (any VT100ScreenMarkReading)? {
        return screen.lastPromptMark()
    }

    /// All VT100ScreenMarks currently in the interval tree.
    func allScreenMarks() -> [VT100ScreenMark] {
        var result: [VT100ScreenMark] = []
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            result = mutableState.intervalTree.allObjects().compactMap { $0 as? VT100ScreenMark }
        })
        return result
    }

    /// Synchronize threads and execute pending side effects
    func sync() {
        screen.performBlock(joinedThreads: { _, _, _ in })
    }

    /// Reset the delegate's call records
    func resetCalls() {
        delegate.reset()
    }

    /// Get the current working directory from the screen state
    var currentPath: String? {
        // Match VT100ScreenState.currentWorkingDirectory behavior (line 1328-1330)
        return screen.workingDirectory(onLine: screen.numberOfLines())
    }

    /// Check if shouldExpectWorkingDirectoryUpdates is set
    var expectsWorkingDirectoryUpdates: Bool {
        return screen.shouldExpectWorkingDirectoryUpdates()
    }
}
