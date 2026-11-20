//
//  KittyDnDResponseInjectionTests.swift
//  ModernTests
//
//  Security regression test for a control-character injection in the Kitty
//  drag-and-drop protocol (OSC 72), the same class as the Kitty image protocol
//  RCE in KittyImageResponseInjectionTests.
//
//  Several OSC 72 replies echo request-supplied values verbatim: a t=q query
//  reply echoes the request's "i", and error replies echo the raw "Y"/"y". The
//  OSC parser preserves every C0 control byte except BEL/CAN/SUB/ESC, so a
//  crafted request could smuggle a control character (for example ^O, which both
//  bash and zsh bind to a line-accepting action) into an echoed value. The reply
//  is written to the PTY input stream, so that control character would be
//  interpreted by the shell as typed input. The outbound sanitizer previously
//  stripped only CR/LF; it now strips every control character.
//

import XCTest
import AppKit
@testable import iTerm2SharedARC

@MainActor
final class KittyDnDResponseInjectionTests: XCTestCase {
    private final class Recorder {
        var reports: [String] = []
        func report(_ serialized: String) { reports.append(serialized) }
        var last: String? { reports.last }
    }

    private final class FakeEndpoint: KittyDnDEndpoint {
        var isRemoteHost = false
    }

    private final class FakeDragHost: KittyDnDDragHost {
        func beginDrag(_ offer: KittyDnDDragOffer) -> KittyDnDDragStartResult { .started }
        func cancelDrag() {}
        func clearPendingGesture() {}
        var hasLiveGesture: Bool { false }
    }

    private var recorder = Recorder()

    private func makeController() -> KittyDnDController {
        let r = recorder
        return KittyDnDController(ourMachineID: KittyDnDMachineID.hashed("us"),
                                 endpoint: FakeEndpoint(),
                                 dragHost: FakeDragHost()) { r.report($0) }
    }

    // Asserts the reply is a well-framed OSC 72 message with no control byte
    // other than the two framing ESCs (the OSC introducer and the ST terminator).
    private func assertNoInjection(_ message: String?, file: StaticString = #filePath, line: UInt = #line) {
        guard let message else {
            XCTFail("expected an OSC 72 reply", file: file, line: line)
            return
        }
        let escCount = message.unicodeScalars.filter { $0.value == 0x1b }.count
        XCTAssertEqual(escCount, 2, "only the framing ESCs may appear", file: file, line: line)
        for scalar in message.unicodeScalars where scalar.value != 0x1b {
            XCTAssertFalse(scalar.value < 0x20 || scalar.value == 0x7f || (scalar.value >= 0x80 && scalar.value <= 0x9f),
                           "no control character may appear in the reply (found 0x\(String(scalar.value, radix: 16)))",
                           file: file, line: line)
        }
    }

    // The query reply echoes the request's "i". A ^O embedded there must not reach
    // the shell. (handleInboundSequence takes the OSC content after "72;".)
    func testQueryEchoCannotInjectControlCharacter() {
        let controller = makeController()
        controller.handleInboundSequence("t=q:i=x&open -a Calculator&\u{0f}")
        assertNoInjection(recorder.last)
        // The visible command text is still present but defanged (no raw ^O/newline).
        XCTAssertEqual(recorder.last?.contains("open -a Calculator"), true)
    }

    // A spread of C0 controls and a TAB in the echoed "i", per the reported repro.
    func testQueryEchoStripsAssortedControls() {
        let controller = makeController()
        controller.handleInboundSequence("t=q:i=\u{0f}\u{04}\u{15}\u{09}payload")
        assertNoInjection(recorder.last)
    }
}
