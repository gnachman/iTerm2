//
//  TmuxKeyReportingModeTests.swift
//  iTerm2
//
//  In a tmux -CC pane the application's terminal is tmux, not iTerm2. tmux
//  forwards a pane's raw output to control clients verbatim, so iTerm2 sees the
//  app's kitty keyboard protocol requests even though they were addressed to
//  tmux. Acting on them leaves iTerm2 holding key reporting state that tmux does
//  not model and cannot report back, which is silently lost on detach.
//
//  These tests drive the real parser with kitty keyboard sequences and assert
//  that a tmux client ignores them while an ordinary session still honors them.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxKeyReportingModeTests: XCTestCase {
    /// A screen whose terminal is in tmux mode, as a tmux -CC pane's is, or not.
    private func makeHarness(isTmuxClient: Bool) -> TerminalTestHarness {
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.screen.performBlock(joinedThreads: { terminal, _, _ in
            terminal?.tmuxMode = isTmuxClient
        })
        return harness
    }

    /// Feed `bytes` to a fresh screen and return the resulting key reporting flags.
    private func flags(after bytes: [UInt8], isTmuxClient: Bool) -> VT100TerminalKeyReportingFlags {
        let harness = makeHarness(isTmuxClient: isTmuxClient)
        harness.send(bytes)
        harness.sync()
        return harness.screen.terminalKeyReportingFlags
    }

    /// CSI > flags u (push)
    private func push(_ value: Int) -> [UInt8] {
        return Array("\u{1b}[>\(value)u".utf8)
    }

    /// CSI = flags ; mode u (set)
    private func set(_ value: Int, mode: Int) -> [UInt8] {
        return Array("\u{1b}[=\(value);\(mode)u".utf8)
    }

    /// CSI < count u (pop)
    private var pop: [UInt8] {
        return Array("\u{1b}[<1u".utf8)
    }

    // MARK: - Ordinary sessions keep working

    func testPushIsHonoredOutsideTmux() {
        XCTAssertEqual(flags(after: push(1), isTmuxClient: false),
                       VT100TerminalKeyReportingFlags.disambiguateEscape,
                       "A normal session must honor CSI > 1 u")
    }

    func testSetIsHonoredOutsideTmux() {
        XCTAssertEqual(flags(after: set(1, mode: 1), isTmuxClient: false),
                       VT100TerminalKeyReportingFlags.disambiguateEscape,
                       "A normal session must honor CSI = 1 ; 1 u")
    }

    func testPopIsHonoredOutsideTmux() {
        // Each sequence is sent on its own so the flag change from the push has
        // settled before the pop is parsed.
        let harness = makeHarness(isTmuxClient: false)
        harness.send(push(1))
        harness.sync()
        XCTAssertEqual(harness.screen.terminalKeyReportingFlags,
                       VT100TerminalKeyReportingFlags.disambiguateEscape)

        harness.send(pop)
        harness.sync()
        XCTAssertEqual(harness.screen.terminalKeyReportingFlags,
                       [],
                       "A normal session must honor CSI < 1 u")
    }

    // MARK: - tmux -CC panes reject

    func testPushIsIgnoredInTmux() {
        XCTAssertEqual(flags(after: push(1), isTmuxClient: true),
                       [],
                       "A tmux pane must ignore CSI > 1 u: tmux owns the pane's key encoding")
    }

    func testSetIsIgnoredInTmux() {
        XCTAssertEqual(flags(after: set(1, mode: 1), isTmuxClient: true),
                       [],
                       "A tmux pane must ignore CSI = 1 ; 1 u")
    }

    func testAllFlagsAreIgnoredInTmux() {
        // Every bit the protocol defines, in one request.
        XCTAssertEqual(flags(after: push(31), isTmuxClient: true),
                       [],
                       "A tmux pane must ignore a request for every kitty flag")
    }

    func testPopIsIgnoredInTmux() {
        // The push was dropped, so the stack is empty and the pop must not
        // underflow into some other state.
        let harness = makeHarness(isTmuxClient: true)
        harness.send(push(1))
        harness.sync()
        harness.send(pop)
        harness.sync()
        XCTAssertEqual(harness.screen.terminalKeyReportingFlags,
                       [],
                       "A tmux pane must ignore CSI < 1 u")
    }

    // MARK: - What tmux reports

    func testPaneKeyModeParsing() {
        // Absent or unrecognized.
        XCTAssertNil(TmuxPaneKeyMode.mode(for: nil))
        XCTAssertNil(TmuxPaneKeyMode.mode(for: ""))
        XCTAssertNil(TmuxPaneKeyMode.mode(for: "Nonsense"))
        XCTAssertNil(TmuxPaneKeyMode.mode(for: "Kitty"))
        XCTAssertNil(TmuxPaneKeyMode.mode(for: "Kitty x"))
        XCTAssertNil(TmuxPaneKeyMode.mode(for: "Kitty  1"))
        XCTAssertNil(TmuxPaneKeyMode.mode(for: "Kitty 32"),
                     "A flag outside the protocol's range is safer ignored than half-applied")

        // What every tmux that has pane_key_mode reports.
        XCTAssertEqual(TmuxPaneKeyMode.mode(for: "VT10x")?.modifyOtherKeys, 0)
        XCTAssertEqual(TmuxPaneKeyMode.mode(for: "VT10x")?.kittyFlags, 0)
        XCTAssertEqual(TmuxPaneKeyMode.mode(for: "Ext 1")?.modifyOtherKeys, 1)
        XCTAssertEqual(TmuxPaneKeyMode.mode(for: "Ext 2")?.modifyOtherKeys, 2)

        // What only a tmux that tracks the Kitty protocol reports. tmux describes
        // these as mutually exclusive, so there is no modifyOtherKeys level.
        XCTAssertEqual(TmuxPaneKeyMode.mode(for: "Kitty 1")?.kittyFlags, 1)
        XCTAssertEqual(TmuxPaneKeyMode.mode(for: "Kitty 1")?.modifyOtherKeys, -1)
        XCTAssertEqual(TmuxPaneKeyMode.mode(for: "Kitty 9")?.kittyFlags, 9)
        XCTAssertEqual(TmuxPaneKeyMode.mode(for: "Kitty 0")?.kittyFlags, 0)
    }

    func testTmuxReportingKittyDoesNotTurnItOn() {
        // A tmux that tracks Kitty encodes the keys itself (we send them by name),
        // so its report is for display only and must never make us encode Kitty.
        let harness = makeHarness(isTmuxClient: true)
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.applyTmuxPaneKeyMode("Kitty 9")
        })
        harness.sync()
        XCTAssertEqual(harness.screen.terminalKeyReportingFlags, [])
    }

    func testFlagsCarriedIntoTmuxModeAreOff() {
        // Flags set before tmux mode was switched on (from a restored arrangement,
        // or from pane output parsed first) must not be used in a tmux pane.
        let harness = makeHarness(isTmuxClient: false)
        harness.send(push(1))
        harness.sync()
        XCTAssertEqual(harness.screen.terminalKeyReportingFlags, .disambiguateEscape)

        harness.screen.performBlock(joinedThreads: { terminal, _, _ in
            terminal?.tmuxMode = true
        })
        harness.sync()
        XCTAssertEqual(harness.screen.terminalKeyReportingFlags, [])
    }

    func testAttachAppliesModifyOtherKeysLevel() {
        let harness = makeHarness(isTmuxClient: true)
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.applyTmuxPaneKeyMode("Ext 2")
        })
        harness.sync()
        harness.screen.performBlock(joinedThreads: { terminal, _, _ in
            XCTAssertEqual(terminal?.sendModifiers[4] as? NSNumber, NSNumber(value: 2))
        })
    }

    func testAttachWithoutPaneKeyModeLeavesModifyOtherKeysAlone() {
        // tmux before 3.5 cannot tell us the modifyOtherKeys level, and a Kitty
        // value carries none, so neither may clobber what the pane already set.
        for value in ["", "Kitty 1"] {
            let harness = makeHarness(isTmuxClient: true)
            harness.send(Array("\u{1b}[>4;2m".utf8))
            harness.sync()

            harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
                mutableState.applyTmuxPaneKeyMode(value)
            })
            harness.sync()
            harness.screen.performBlock(joinedThreads: { terminal, _, _ in
                XCTAssertEqual(terminal?.sendModifiers[4] as? NSNumber, NSNumber(value: 2),
                               "pane_key_mode “\(value)” must not clear modifyOtherKeys")
            })
        }
    }

    func testPaneModifyOtherKeysStillClearsFlagsOutsideTmux() {
        // Outside tmux a modifyOtherKeys change deliberately clears the Kitty flags.
        let harness = makeHarness(isTmuxClient: false)
        harness.send(push(1))
        harness.sync()
        XCTAssertEqual(harness.screen.terminalKeyReportingFlags, .disambiguateEscape)

        harness.send(Array("\u{1b}[>4;2m".utf8))
        harness.sync()
        XCTAssertEqual(harness.screen.terminalKeyReportingFlags, [],
                       "Outside tmux a modifyOtherKeys change still clears the flags")
    }

    func testFullResetClearsFlagsOutsideTmux() {
        let harness = makeHarness(isTmuxClient: false)
        harness.send(push(1))
        harness.sync()
        XCTAssertEqual(harness.screen.terminalKeyReportingFlags, .disambiguateEscape)

        harness.send(Array("\u{1b}c".utf8))
        harness.sync()
        XCTAssertEqual(harness.screen.terminalKeyReportingFlags, [],
                       "Outside tmux a full reset still clears the flags")
    }

    // MARK: - The reason this matters

    func testShiftEnterIsNotKittyEncodedInTmux() {
        // The repro from issue 13076: before this gate, the pane encoded
        // Shift+Enter as CSI 13;2u until the first detach and as CR after it.
        // Nothing in a tmux pane may reach a nonzero flag state, because that is
        // what selects the modern key mapper.
        let harness = makeHarness(isTmuxClient: true)
        harness.send(push(1))
        harness.sync()
        XCTAssertEqual(harness.screen.terminalKeyReportingFlags, [])

        // ...and modifyOtherKeys, which tmux does model, is untouched by the gate.
        harness.send(Array("\u{1b}[>4;2m".utf8))
        harness.sync()
        harness.screen.performBlock(joinedThreads: { terminal, _, _ in
            let level = terminal?.sendModifiers[4] as? NSNumber
            XCTAssertEqual(level, NSNumber(value: 2),
                           "modifyOtherKeys must still be honored in a tmux pane")
        })
    }
}
