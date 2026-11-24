//
//  KittyImageResponseInjectionTests.swift
//  ModernTests
//
//  Security regression test for the Kitty graphics protocol response-injection
//  RCE reported by Minseong Kim of NSHC Red Alert Labs.
//
//  A file-transmit command (t=f) that names a non-existent path lands in the
//  error path, which built its response from NSError.localizedDescription. That
//  description embeds the offending path verbatim, so a path containing literal
//  newlines produced a response with raw 0x0A bytes. The response is written to
//  the PTY's input stream, so those newlines were delivered to the shell as if
//  the user had typed the text between them, yielding command injection from
//  merely `cat`-ing a crafted file.
//
//  The fix strips C0 control characters (and DEL) from the free-text portion of
//  every Kitty response before it is framed and sent. These tests assert that a
//  crafted path can no longer smuggle a control character into the response, and
//  that ordinary error text is left readable.
//

import XCTest
import AppKit
@testable import iTerm2SharedARC

final class KittyImageResponseInjectionTests: XCTestCase {
    // KittyImageController.delegate is weak; keep it alive for the test's duration.
    private var delegates = [CapturingKittyDelegate]()

    private func makeControllerWithDelegate() -> (KittyImageController, CapturingKittyDelegate) {
        let delegate = CapturingKittyDelegate()
        delegates.append(delegate)
        let controller = KittyImageController()
        controller.delegate = delegate
        return (controller, delegate)
    }

    private func fileTransmitCommand(path: String) -> KittyImageCommand {
        let b64 = Data(path.utf8).base64EncodedString()
        // a=t transmit, t=f file medium, f=100 PNG, i=1 identifier, default (normal) verbosity.
        return KittyImageCommand("a=t,f=100,t=f,i=1;\(b64)")!
    }

    // The exploit: a non-existent path with embedded newlines and a command between them.
    func testNewlineInFilePathCannotInjectIntoResponse() {
        let (controller, delegate) = makeControllerWithDelegate()
        let path = "/tmp/x\nopen -a Calculator\nz"
        controller.execute(command: fileTransmitCommand(path: path))

        let message = delegate.lastMessage
        XCTAssertNotNil(message, "a non-existent file transmit should still produce an error response")
        guard let message else { return }

        XCTAssertFalse(message.unicodeScalars.contains { $0.value == 0x0a },
                       "the response must not contain a raw newline (LF), which the shell would execute")
        XCTAssertFalse(message.unicodeScalars.contains { $0.value == 0x0d },
                       "the response must not contain a raw carriage return (CR)")
        // Sanity: it is still a well-framed Kitty error response.
        XCTAssertTrue(message.hasPrefix("\u{1B}_G"), "response should keep its APC framing prefix")
        XCTAssertTrue(message.hasSuffix("\u{1B}\\"), "response should keep its ST terminator")
        XCTAssertTrue(message.contains("EBADF"), "response should report the transmit error")
    }

    // Belt and suspenders: an embedded ESC must not survive to start a new escape
    // sequence inside the payload (only the two framing ESCs are allowed).
    func testEmbeddedControlCharactersAreStripped() {
        let (controller, delegate) = makeControllerWithDelegate()
        // Null, ESC, bell, CR, LF, and DEL all embedded in the path.
        let path = "/tmp/a\u{00}b\u{1B}c\u{07}d\u{0D}e\u{0A}f\u{7F}g"
        controller.execute(command: fileTransmitCommand(path: path))

        guard let message = delegate.lastMessage else {
            XCTFail("expected an error response")
            return
        }
        // Exactly two ESCs: the framing prefix and the ST terminator, none in the payload.
        let escCount = message.unicodeScalars.filter { $0.value == 0x1b }.count
        XCTAssertEqual(escCount, 2, "no ESC may survive inside the response payload")
        for scalar in message.unicodeScalars where scalar.value != 0x1b {
            XCTAssertFalse(scalar.value < 0x20 || scalar.value == 0x7f,
                           "no control character may appear in the payload (found 0x\(String(scalar.value, radix: 16)))")
        }
    }

    // The fix must not mangle ordinary diagnostic text: printable characters,
    // including the colon and spaces an error message normally contains, survive.
    func testOrdinaryErrorTextIsPreserved() {
        let (controller, delegate) = makeControllerWithDelegate()
        // A plain, newline-free non-existent path.
        controller.execute(command: fileTransmitCommand(path: "/tmp/does-not-exist-\(UUID().uuidString)"))

        guard let message = delegate.lastMessage else {
            XCTFail("expected an error response")
            return
        }
        XCTAssertTrue(message.contains("EBADF:"), "the error code and its colon should be preserved verbatim")
    }

    // Replacing control characters is not enough: any attacker-chosen text that
    // reaches the prompt can be run with a single press of Enter, e.g. after a
    // semicolon. The error reply must be a fixed string that echoes nothing from
    // the request.
    private let injectedCommand = ";SL=$'\\x2f';cat ${SL}etc${SL}passwd;#"

    func testFileTransmitErrorDoesNotEchoPath() {
        let (controller, delegate) = makeControllerWithDelegate()
        controller.execute(command: fileTransmitCommand(path: "/tmp/x \(injectedCommand) z"))

        XCTAssertEqual(delegate.lastMessage, "\u{1B}_Gi=1;EBADF:Failed to read image file\u{1B}\\")
    }

    func testSharedMemoryTransmitErrorDoesNotEchoName() {
        let (controller, delegate) = makeControllerWithDelegate()
        let b64 = Data("x\(injectedCommand)".utf8).base64EncodedString()
        controller.execute(command: KittyImageCommand("a=t,f=100,t=s,i=1;\(b64)")!)

        XCTAssertEqual(delegate.lastMessage, "\u{1B}_Gi=1;EBADF:Failed to read shared memory\u{1B}\\")
    }
}

private final class CapturingKittyDelegate: NSObject, KittyImageControllerDelegate {
    var lastMessage: String?
    func kittyImageControllerReport(message: String) {
        lastMessage = message
    }
    func kittyImageControllerPlacementsDidChange() {}
    func kittyImageControllerCursorCoord() -> VT100GridAbsCoord {
        return VT100GridAbsCoord(x: 0, y: 0)
    }
    func kittyImageControllerMoveCursor(dx: Int, dy: Int) {}
    func kittyImageControllerCellSize() -> NSSize {
        return NSSize(width: 10, height: 20)
    }
    func kittyImageControllerScreenAbsLine() -> Int64 {
        return 0
    }
}
