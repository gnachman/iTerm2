//
//  KittyModifyOtherKeysPrecedenceTests.swift
//  iTerm2
//
//  An app that enables the kitty keyboard protocol and then requests xterm's
//  modifyOtherKeys (CSI > 4 ; 2 m) must keep the kitty protocol. Claude Code
//  sends both requests in that order. kitty ignores XTMODKEYS (CSI > Ps ; Pv m)
//  and its reset (CSI > Ps n) entirely, so neither may touch the kitty flags.
//  Issue 13138.
//

import XCTest
@testable import iTerm2SharedARC

final class KittyModifyOtherKeysPrecedenceTests: XCTestCase {
    /// Feed each sequence separately so earlier changes settle before the next is parsed.
    private func harness(after sequences: [String]) -> TerminalTestHarness {
        let harness = TerminalTestHarness(width: 80, height: 24)
        for sequence in sequences {
            harness.send(Array(sequence.utf8))
            harness.sync()
        }
        return harness
    }

    /// CSI > flags u (push)
    private func push(_ value: Int) -> String {
        return "\u{1b}[>\(value)u"
    }

    /// CSI = flags ; mode u (set)
    private func set(_ value: Int, mode: Int) -> String {
        return "\u{1b}[=\(value);\(mode)u"
    }

    /// CSI < 1 u (pop)
    private let pop = "\u{1b}[<1u"

    /// CSI > resource ; value m (xterm XTMODKEYS)
    private func modifyKeys(resource: Int, value: Int) -> String {
        return "\u{1b}[>\(resource);\(value)m"
    }

    func testModifyOtherKeysAfterPushKeepsKittyFlags() {
        let h = harness(after: [push(1), modifyKeys(resource: 4, value: 2)])
        XCTAssertEqual(h.screen.terminalKeyReportingFlags,
                       VT100TerminalKeyReportingFlags.disambiguateEscape,
                       "CSI > 4 ; 2 m must not clear pushed kitty flags")
    }

    func testModifyOtherKeysBeforePushKeepsKittyFlags() {
        let h = harness(after: [modifyKeys(resource: 4, value: 2), push(1)])
        XCTAssertEqual(h.screen.terminalKeyReportingFlags,
                       VT100TerminalKeyReportingFlags.disambiguateEscape)
    }

    func testModifyOtherKeysAfterSetKeepsKittyFlags() {
        let h = harness(after: [set(1, mode: 1), modifyKeys(resource: 4, value: 2)])
        XCTAssertEqual(h.screen.terminalKeyReportingFlags,
                       VT100TerminalKeyReportingFlags.disambiguateEscape,
                       "CSI > 4 ; 2 m must not clear kitty flags set with CSI = u")
    }

    func testModifyCursorKeysAfterPushKeepsKittyFlags() {
        // Resource 1 (modifyCursorKeys) has nothing to do with the kitty protocol.
        let h = harness(after: [push(1), modifyKeys(resource: 1, value: 2)])
        XCTAssertEqual(h.screen.terminalKeyReportingFlags,
                       VT100TerminalKeyReportingFlags.disambiguateEscape,
                       "CSI > 1 ; 2 m must not clear pushed kitty flags")
    }

    func testModifyOtherKeysIsRecordedWhileKittyFlagsAreActive() {
        // modifyOtherKeys is remembered, so it takes effect once the app pops its kitty flags.
        let h = harness(after: [push(1), modifyKeys(resource: 4, value: 2)])
        XCTAssertEqual(h.screen.terminalSendModifiers?[4].intValue, 2)

        h.send(Array(pop.utf8))
        h.sync()
        XCTAssertEqual(h.screen.terminalKeyReportingFlags, [])
        XCTAssertEqual(h.screen.terminalSendModifiers?[4].intValue, 2)
    }

    func testResetModifyOtherKeysKeepsKittyFlags() {
        let h = harness(after: [push(1), modifyKeys(resource: 4, value: 2), "\u{1b}[>4n"])
        XCTAssertEqual(h.screen.terminalKeyReportingFlags,
                       VT100TerminalKeyReportingFlags.disambiguateEscape,
                       "CSI > 4 n must not clear pushed kitty flags")
        XCTAssertEqual(h.screen.terminalSendModifiers?[4].intValue, -1)
    }

    func testResetAllModifiersKeepsKittyFlags() {
        for reset in ["\u{1b}[>n", "\u{1b}[>m"] {
            let h = harness(after: [push(1), modifyKeys(resource: 4, value: 2), reset])
            XCTAssertEqual(h.screen.terminalKeyReportingFlags,
                           VT100TerminalKeyReportingFlags.disambiguateEscape,
                           "\(reset.debugDescription) must not clear pushed kitty flags")
            XCTAssertEqual(h.screen.terminalSendModifiers?[4].intValue, -1)
        }
    }

    func testModifyOtherKeysKeepsPushedStack() {
        // Two pushes, then modifyOtherKeys, then one pop must land on the first push.
        let h = harness(after: [push(1), push(3), modifyKeys(resource: 4, value: 2), pop])
        XCTAssertEqual(h.screen.terminalKeyReportingFlags,
                       VT100TerminalKeyReportingFlags.disambiguateEscape)
    }

    func testFullResetStillClearsKittyFlagsAndModifyOtherKeys() {
        let h = harness(after: [push(1), modifyKeys(resource: 4, value: 2), "\u{1b}c"])
        XCTAssertEqual(h.screen.terminalKeyReportingFlags, [])
        XCTAssertEqual(h.screen.terminalSendModifiers?[4].intValue, -1)
    }
}
