//
//  KittyKeyboardScreenIndependenceTests.swift
//  iTerm2
//
//  The kitty keyboard protocol requires the main and alternate screens to keep
//  independent keyboard mode state. A CSI = flags u written while one screen's
//  stack is empty must not change the effective flags of the other screen.
//  Issue 13204.
//

import XCTest
@testable import iTerm2SharedARC

final class KittyKeyboardScreenIndependenceTests: XCTestCase {
    private func makeHarness() -> TerminalTestHarness {
        return TerminalTestHarness(width: 80, height: 24)
    }

    private func feed(_ harness: TerminalTestHarness, _ string: String) {
        harness.send(Array(string.utf8))
        harness.sync()
    }

    private func flags(_ harness: TerminalTestHarness) -> VT100TerminalKeyReportingFlags {
        return harness.screen.terminalKeyReportingFlags
    }

    private let allFlags: VT100TerminalKeyReportingFlags = VT100TerminalKeyReportingFlags(rawValue: 31)

    // MARK: - Set on an empty stack

    func testSetOnAlternateScreenDoesNotLeakToMainScreen() {
        // The reproduction from the issue.
        let harness = makeHarness()
        feed(harness, "\u{1b}[?1049h\u{1b}[=31u\u{1b}[?1049l")
        XCTAssertEqual(flags(harness), [],
                       "Flags set on the alternate screen must not affect the main screen")
    }

    func testSetOnMainScreenDoesNotLeakToAlternateScreen() {
        let harness = makeHarness()
        feed(harness, "\u{1b}[=31u")
        XCTAssertEqual(flags(harness), allFlags)
        feed(harness, "\u{1b}[?1049h")
        XCTAssertEqual(flags(harness), [],
                       "Flags set on the main screen must not affect the alternate screen")
        feed(harness, "\u{1b}[?1049l")
        XCTAssertEqual(flags(harness), allFlags,
                       "The main screen keeps its own flags across a trip to the alternate screen")
    }

    func testAlternateScreenKeepsItsOwnFlags() {
        let harness = makeHarness()
        feed(harness, "\u{1b}[?1049h\u{1b}[=1u\u{1b}[?1049l")
        feed(harness, "\u{1b}[=8u")
        XCTAssertEqual(flags(harness), .reportAllKeysAsEscapeCodes)
        feed(harness, "\u{1b}[?1049h")
        XCTAssertEqual(flags(harness), .disambiguateEscape)
    }

    func testQueryReportsOnlyTheCurrentScreensFlags() {
        let harness = makeHarness()
        feed(harness, "\u{1b}[?1049h\u{1b}[=31u\u{1b}[?1049l")
        feed(harness, "\u{1b}[?u")
        let report = harness.delegate.sentReports.last.map { String(decoding: $0, as: UTF8.self) }
        XCTAssertEqual(report, "\u{1b}[?0u")
    }

    // MARK: - Junie CLI sequence

    func testJunieSequenceRestoresMainScreen() {
        let harness = makeHarness()
        feed(harness, "\u{1b}[>u")
        feed(harness, "\u{1b}[=31u")
        feed(harness, "\u{1b}[?1049h")
        feed(harness, "\u{1b}[=31u")
        feed(harness, "\u{1b}[?1049l")
        feed(harness, "\u{1b}[=0u")
        feed(harness, "\u{1b}[<u")
        XCTAssertEqual(flags(harness), [],
                       "After the app pops its own mode the shell must get plain keys")
    }

    // MARK: - Toggle

    func testToggleOnAlternateScreenDoesNotLeakToMainScreen() {
        let harness = makeHarness()
        feed(harness, "\u{1b}[?1049h")
        harness.screen.performBlock(joinedThreads: { terminal, _, _ in
            terminal?.toggleKeyReportingFlag(.disambiguateEscape)
        })
        harness.sync()
        XCTAssertEqual(flags(harness), .disambiguateEscape)
        feed(harness, "\u{1b}[?1049l")
        XCTAssertEqual(flags(harness), [])
    }

    // MARK: - Saved state

    func testStateDictionaryRoundTripsBothScreens() {
        let source = makeHarness()
        feed(source, "\u{1b}[=8u\u{1b}[?1049h\u{1b}[=1u")
        var state: [AnyHashable: Any]?
        source.screen.performBlock(joinedThreads: { terminal, _, _ in
            state = terminal?.stateDictionary as? [AnyHashable: Any]
        })
        guard let state else {
            XCTFail("No state dictionary")
            return
        }

        let destination = makeHarness()
        destination.screen.performBlock(joinedThreads: { terminal, _, _ in
            terminal?.setStateFrom(state)
        })
        destination.sync()
        XCTAssertEqual(flags(destination), .reportAllKeysAsEscapeCodes,
                       "Main screen flags must be restored")
        feed(destination, "\u{1b}[?1049h")
        XCTAssertEqual(flags(destination), .disambiguateEscape,
                       "Alternate screen flags must be restored")
    }

    func testLegacyStateDictionaryRestoresMainScreenFlags() {
        // A dictionary saved before the alternate screen had its own base value.
        let source = makeHarness()
        feed(source, "\u{1b}[=8u")
        var state: [AnyHashable: Any]?
        source.screen.performBlock(joinedThreads: { terminal, _, _ in
            state = terminal?.stateDictionary as? [AnyHashable: Any]
        })
        guard var state else {
            XCTFail("No state dictionary")
            return
        }
        state.removeValue(forKey: "Alternate Key Reporting Flags")

        let destination = makeHarness()
        destination.screen.performBlock(joinedThreads: { terminal, _, _ in
            terminal?.setStateFrom(state)
        })
        destination.sync()
        XCTAssertEqual(flags(destination), .reportAllKeysAsEscapeCodes)
    }
}
