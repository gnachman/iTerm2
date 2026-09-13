//
//  WindowFrameEscapeTests.swift
//  iTerm2
//
//  Tests for the OSC 1337 global-frame window codes: SetWindowFrame (move and
//  resize the window in global AppKit coordinates), ReportWindowFrame, and
//  ReportScreenFrames. These let a program place a window on any monitor without
//  the current-monitor-relative limitation of the XTWINOPS CSI 3;x;y t sequence.
//

import XCTest
@testable import iTerm2SharedARC

final class WindowFrameEscapeTests: XCTestCase {
    // ESC ] 1337 ; <payload> BEL
    private func osc1337(_ payload: String) -> [UInt8] {
        return Array("\u{1b}]1337;\(payload)\u{07}".utf8)
    }

    // MARK: - SetWindowFrame

    /// When window resizing is permitted, SetWindowFrame forwards the parsed
    /// global-coordinate rect to the delegate unchanged.
    func testSetWindowFrameWhenAllowed() {
        let harness = TerminalTestHarness()
        harness.delegate.windowResizePermission = .allowed
        harness.resetCalls()

        harness.feedEscapeSequence(osc1337("SetWindowFrame=100;200;800;600"))
        harness.sync()

        XCTAssertEqual(harness.delegate.setWindowFrameCalls.count, 1)
        XCTAssertEqual(harness.delegate.setWindowFrameCalls.first,
                       NSRect(x: 100, y: 200, width: 800, height: 600))
    }

    /// Negative origins (a monitor to the left of or below the primary display
    /// in AppKit's global space) round-trip correctly.
    func testSetWindowFrameAcceptsNegativeOrigin() {
        let harness = TerminalTestHarness()
        harness.delegate.windowResizePermission = .allowed
        harness.resetCalls()

        harness.feedEscapeSequence(osc1337("SetWindowFrame=-1440;-300;1280;1024"))
        harness.sync()

        XCTAssertEqual(harness.delegate.setWindowFrameCalls.first,
                       NSRect(x: -1440, y: -300, width: 1280, height: 1024))
    }

    /// Without resize permission the code is a no-op, mirroring the existing
    /// XTWINOPS move gate.
    func testSetWindowFrameWhenDeniedDoesNothing() {
        let harness = TerminalTestHarness()
        harness.delegate.windowResizePermission = .denied
        harness.resetCalls()

        harness.feedEscapeSequence(osc1337("SetWindowFrame=100;200;800;600"))
        harness.sync()

        XCTAssertTrue(harness.delegate.setWindowFrameCalls.isEmpty)
    }

    /// A malformed payload (wrong field count) is ignored rather than moving
    /// the window to a garbage frame.
    func testSetWindowFrameWithWrongArityIsIgnored() {
        let harness = TerminalTestHarness()
        harness.delegate.windowResizePermission = .allowed
        harness.resetCalls()

        harness.feedEscapeSequence(osc1337("SetWindowFrame=100;200;800"))
        harness.sync()

        XCTAssertTrue(harness.delegate.setWindowFrameCalls.isEmpty)
    }

    // MARK: - Report accessors

    /// The report accessors read straight from the (thread-safe) config
    /// snapshot, in global AppKit coordinates.
    func testReportAccessorsReadConfig() {
        let harness = TerminalTestHarness()
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            let config = VT100MutableScreenConfiguration()
            config.globalWindowFrame = NSRect(x: 10, y: 20, width: 30, height: 40)
            config.screenFrames = [
                NSValue(rect: NSRect(x: 0, y: 0, width: 1440, height: 900)),
                NSValue(rect: NSRect(x: 1440, y: 0, width: 1920, height: 1080)),
            ]
            mutableState.setConfig(config)

            XCTAssertEqual(mutableState.terminalWindowFrameInPoints(),
                           NSRect(x: 10, y: 20, width: 30, height: 40))
            let frames = mutableState.terminalScreenFramesInPoints()
            XCTAssertEqual(frames.count, 2)
            XCTAssertEqual(frames[1].rectValue,
                           NSRect(x: 1440, y: 0, width: 1920, height: 1080))
        })
    }
}
