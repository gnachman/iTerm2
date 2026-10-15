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
    /// Generous on purpose: this only bounds a hang, and the suite runs under
    /// ASan with guard malloc, where a side effect can take far longer than it
    /// does in a normal build. A passing run does not spend it.
    private let sideEffectTimeout: TimeInterval = 30.0

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
        let delivered = expectation(description: "screenSetWindowFrame called")
        harness.delegate.onSetWindowFrame = { _ in delivered.fulfill() }

        harness.feedEscapeSequence(osc1337("SetWindowFrame=100;200;800;600"))
        harness.sync()
        wait(for: [delivered], timeout: sideEffectTimeout)

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
        let delivered = expectation(description: "screenSetWindowFrame called")
        harness.delegate.onSetWindowFrame = { _ in delivered.fulfill() }

        harness.feedEscapeSequence(osc1337("SetWindowFrame=-1440;-300;1280;1024"))
        harness.sync()
        wait(for: [delivered], timeout: sideEffectTimeout)

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

    /// QA finding F-059: payloads that are not exactly four finite numbers
    /// are ignored entirely. Each is followed by a valid frame and the test
    /// waits for that one, so only the valid frame may have been delivered.
    func testSetWindowFrameIgnoresMalformedPayloads() {
        let malformed = [
            "nan;nan;nan;nan",
            "1;2;3",
            "a;b;c;d",
            "1;2;3;4;5",
            "inf;0;800;600",
            "0;0;800;-inf",
            "100;200;800;",
            "100;200;800;600x",
        ]
        for payload in malformed {
            let harness = TerminalTestHarness()
            harness.delegate.windowResizePermission = .allowed
            harness.resetCalls()
            let delivered = expectation(description: "valid frame delivered after \(payload)")
            harness.delegate.onSetWindowFrame = { frame in
                if frame == NSRect(x: 1, y: 2, width: 300, height: 400) {
                    delivered.fulfill()
                }
            }

            harness.feedEscapeSequence(osc1337("SetWindowFrame=\(payload)"))
            harness.feedEscapeSequence(osc1337("SetWindowFrame=1;2;300;400"))
            harness.sync()
            wait(for: [delivered], timeout: sideEffectTimeout)

            XCTAssertEqual(harness.delegate.setWindowFrameCalls,
                           [NSRect(x: 1, y: 2, width: 300, height: 400)],
                           "payload \(payload)")
        }
    }

    func testParseAcceptsFiniteNumbers() {
        XCTAssertEqual(SetWindowFrameRequest.parse("100;200;800;600")?.rectValue,
                       NSRect(x: 100, y: 200, width: 800, height: 600))
        XCTAssertEqual(SetWindowFrameRequest.parse("-1.5; 2 ;0;-500")?.rectValue,
                       NSRect(x: -1.5, y: 2, width: 0, height: -500))
        XCTAssertEqual(SetWindowFrameRequest.parse("1e308;1e308;1e308;1e308")?.rectValue,
                       NSRect(x: 1e308, y: 1e308, width: 1e308, height: 1e308))
    }

    func testParseRejectsMalformedInput() {
        for payload in ["", "nan;nan;nan;nan", "1;2;3", "a;b;c;d", "1;2;3;4;5",
                        "inf;0;1;1", "1e999;0;1;1", "1;2;3;", "1;2;3;4x"] {
            XCTAssertNil(SetWindowFrameRequest.parse(payload), payload)
        }
    }

    // MARK: - Clamping

    private let primary = NSRect(x: 0, y: 0, width: 1440, height: 875)
    private let secondary = NSRect(x: 1440, y: -200, width: 1920, height: 1055)
    private let minSize = NSSize(width: 200, height: 100)

    private func clamp(_ frame: NSRect, screens: [NSRect]? = nil) -> NSRect {
        return SetWindowFrameRequest.clampedFrame(frame,
                                                  minSize: minSize,
                                                  screenFrames: (screens ?? [primary, secondary]).map { NSValue(rect: $0) })
    }

    private func assertReachable(_ frame: NSRect, file: StaticString = #filePath, line: UInt = #line) {
        let screens = [primary, secondary]
        XCTAssertTrue(frame.width >= minSize.width && frame.height >= minSize.height,
                      "\(frame) is smaller than the minimum", file: file, line: line)
        let union = screens.reduce(screens[0]) { $0.union($1) }
        XCTAssertTrue(frame.width <= union.width && frame.height <= union.height,
                      "\(frame) is bigger than the screens", file: file, line: line)
        XCTAssertTrue(screens.contains { screen in
            let overlap = frame.intersection(screen)
            return overlap.width >= 40 && frame.maxY <= screen.maxY && frame.maxY >= screen.minY + 40
        }, "\(frame) is not reachable on a screen", file: file, line: line)
    }

    /// A reasonable frame, including one spanning two screens, is unchanged.
    func testClampLeavesReasonableFramesAlone() {
        let frame = NSRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertEqual(clamp(frame), frame)
        let spanning = NSRect(x: 1000, y: 100, width: 1000, height: 600)
        XCTAssertEqual(clamp(spanning), spanning)
    }

    /// The QA inputs that used to produce a 0x0 or far-off-screen window.
    func testClampQAInputs() {
        let zero = clamp(NSRect(x: 0, y: 0, width: 0, height: 0))
        XCTAssertEqual(zero.size, minSize)
        assertReachable(zero)

        let negative = clamp(NSRect(x: 0, y: 0, width: -500, height: -500))
        XCTAssertEqual(negative.size, minSize)
        assertReachable(negative)

        assertReachable(clamp(NSRect(x: 1e308, y: 1e308, width: 1e308, height: 1e308)))
        assertReachable(clamp(NSRect(x: -1e308, y: -1e308, width: 1e308, height: 1e308)))

        let huge = clamp(NSRect(x: 100, y: 100, width: 100000, height: 100000))
        XCTAssertEqual(huge.width, primary.union(secondary).width)
        XCTAssertEqual(huge.height, primary.union(secondary).height)
        assertReachable(huge)
    }

    /// A window entirely off screen is moved onto the nearest screen, and one
    /// whose title bar is above the top of a screen is moved down.
    func testClampMovesUnreachableFramesOnScreen() {
        let offRight = clamp(NSRect(x: 50000, y: 100, width: 800, height: 600))
        assertReachable(offRight)
        XCTAssertTrue(offRight.intersects(secondary))

        let aboveTop = clamp(NSRect(x: 100, y: 500, width: 800, height: 600))
        XCTAssertEqual(aboveTop, NSRect(x: 100, y: 275, width: 800, height: 600))
    }

    /// With no screens only the minimum size is enforced.
    func testClampWithoutScreens() {
        XCTAssertEqual(clamp(NSRect(x: 5, y: 6, width: 0, height: 0), screens: []),
                       NSRect(x: 5, y: 6, width: 200, height: 100))
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
