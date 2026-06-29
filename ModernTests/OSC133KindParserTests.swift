//
//  OSC133KindParserTests.swift
//  iTerm2
//
//  Tests for VT100Terminal's OSC 133 `k=` (Semantic Prompt) argument parser.
//  Each test sends a synthetic byte stream through the real parser and
//  asserts on which `VT100PromptKind` the receiver was called with.
//
//  Per the consolidated plan (PR 1):
//   - `k=` absent or empty → .initial
//   - `k=i` → .initial
//   - `k=s` → .secondary
//   - `k=c` → .continuation
//   - `k=r` → .right
//   - `k=<other>` → .unknown
//   - other key=value tokens (aid, cl, redraw, click_events, future) are silently ignored
//   - `133;P` is dispatched the same way as `133;A`
//

import XCTest
@testable import iTerm2SharedARC

final class OSC133KindParserTests: XCTestCase {

    /// Drive the terminal parser with a synthetic OSC 133 byte stream and
    /// return the kind reported via the non-initial callback. Returns nil
    /// if no non-initial callback fired (the parser took the .initial path).
    private func observedKind(forOSC bytes: [UInt8]) -> VT100PromptKind? {
        let harness = TerminalTestHarness(width: 80, height: 24)
        let spy = PromptKindSpyDelegate()
        spy.screen = harness.screen
        harness.screen.delegate = spy

        bytes.withUnsafeBufferPointer { ptr in
            let chars = UnsafeMutablePointer<CChar>(
                mutating: UnsafeRawPointer(ptr.baseAddress!).assumingMemoryBound(to: CChar.self))
            harness.screen.threadedReadTask(chars, length: Int32(bytes.count))
        }
        harness.sync()

        return spy.observedKinds.last
    }


    // MARK: - Kind detection

    func test_A_noArg_isInitial() {
        // ESC ] 133 ; A BEL
        let bytes: [UInt8] = [0x1B, 0x5D, 0x31, 0x33, 0x33, 0x3B, 0x41, 0x07]
        XCTAssertNil(observedKind(forOSC: bytes),
                     "Bare 133;A must take the .initial path (no non-initial callback)")
    }

    func test_A_kEqualsI_isInitial() {
        let bytes = osc133Bytes(command: "A", args: ["k=i"])
        XCTAssertNil(observedKind(forOSC: bytes),
                     "k=i must take the .initial path")
    }

    func test_A_kEqualsS_isSecondary() {
        let bytes = osc133Bytes(command: "A", args: ["k=s"])
        XCTAssertEqual(observedKind(forOSC: bytes), .secondary)
    }

    func test_A_kEqualsC_isContinuation() {
        let bytes = osc133Bytes(command: "A", args: ["k=c"])
        XCTAssertEqual(observedKind(forOSC: bytes), .continuation)
    }

    func test_A_kEqualsR_isRight() {
        let bytes = osc133Bytes(command: "A", args: ["k=r"])
        XCTAssertEqual(observedKind(forOSC: bytes), .right)
    }

    func test_A_kEqualsX_routesAsInitial() {
        // Parser produces .unknown for an unrecognized k= value, but the
        // receiver folds .unknown into the .initial path so a typo or
        // future-kind byte can't silently hide a prompt from mark/nav.
        // The spy here observes only the non-initial dispatch, so a .unknown
        // routed-as-initial yields nil — and that's the assertion. The
        // parser-side test that .unknown is the produced kind lives in
        // PromptMarkExcludedSubrangeTests.test_unknownKind_routesAsInitial.
        let bytes = osc133Bytes(command: "A", args: ["k=x"])
        XCTAssertNil(observedKind(forOSC: bytes),
                     "k=x must route through the .initial path at the receiver")
    }

    func test_A_kEmpty_isInitial() {
        let bytes = osc133Bytes(command: "A", args: ["k="])
        XCTAssertNil(observedKind(forOSC: bytes),
                     "k= with empty value must default to .initial")
    }

    // MARK: - Other key=value tokens are ignored

    func test_aidIgnored_kStillParsed() {
        let bytes = osc133Bytes(command: "A", args: ["aid=foo", "k=s"])
        XCTAssertEqual(observedKind(forOSC: bytes), .secondary,
                       "aid= must not interfere with k= parsing")
    }

    func test_clIgnored_kStillParsed() {
        let bytes = osc133Bytes(command: "A", args: ["k=s", "cl=line"])
        XCTAssertEqual(observedKind(forOSC: bytes), .secondary,
                       "cl= must not interfere with k= parsing")
    }

    func test_unknownAttribute_kStillParsed() {
        let bytes = osc133Bytes(command: "A", args: ["futureArg=42", "k=c"])
        XCTAssertEqual(observedKind(forOSC: bytes), .continuation,
                       "Unknown attribute names must be silently skipped")
    }

    // MARK: - 'N' and 'P' dispatch like 'A'

    func test_N_kEqualsS_isSecondary() {
        let bytes = osc133Bytes(command: "N", args: ["k=s"])
        XCTAssertEqual(observedKind(forOSC: bytes), .secondary,
                       "133;N must dispatch the kind exactly like 133;A")
    }

    func test_N_noArg_isInitial() {
        let bytes = osc133Bytes(command: "N", args: [])
        XCTAssertNil(observedKind(forOSC: bytes),
                     "Bare 133;N must take the .initial path")
    }

    func test_P_kEqualsS_isSecondary() {
        let bytes = osc133Bytes(command: "P", args: ["k=s"])
        XCTAssertEqual(observedKind(forOSC: bytes), .secondary,
                       "133;P must dispatch the kind exactly like 133;A")
    }

    func test_P_noArg_isInitial() {
        let bytes = osc133Bytes(command: "P", args: [])
        XCTAssertNil(observedKind(forOSC: bytes),
                     "Bare 133;P must take the .initial path")
    }

    // MARK: - Helpers

    /// Build the byte stream for `ESC ] 133 ; <command> [; <arg>]... BEL`.
    private func osc133Bytes(command: String, args: [String]) -> [UInt8] {
        var s = "\u{1B}]133;\(command)"
        for a in args {
            s.append(";")
            s.append(a)
        }
        s.append("\u{07}")
        return Array(s.utf8)
    }
}

/// VT100ScreenDelegate stub that records every call to
/// `screenPromptOfNonInitialKindDidStart(_:)`. Inherits from FakeSession
/// (defined in VT100ScreenTests.swift) for no-op stubs on the rest of the
/// delegate surface.
private final class PromptKindSpyDelegate: FakeSession {
    var observedKinds: [VT100PromptKind] = []

    override func screenPromptOfNonInitialKindDidStart(_ kind: VT100PromptKind) {
        observedKinds.append(kind)
    }
}
