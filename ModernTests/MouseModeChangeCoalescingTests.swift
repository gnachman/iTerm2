//
//  MouseModeChangeCoalescingTests.swift
//  iTerm2
//
//  Regression tests for the mouse-mode-change side-effect flood that caused
//  multi-second main-thread hangs when navigating tmux sessions. tmux
//  re-asserts mouse mode on every session/window switch; each assertion used
//  to enqueue a heavyweight "mouse mode did change" side effect, and the
//  DECSET/DECRST handler fired the delegate twice per sequence (once via the
//  setter, once explicitly). See screenMouseModeDidChange -> updateCursor:
//  which recomputes terminal button frames by scanning marks.
//

import XCTest
@testable import iTerm2SharedARC

final class MouseModeChangeCoalescingTests: XCTestCase {
    // CSI ? 1000 h  (enable X11 mouse reporting)
    private let enableMouse1000: [UInt8] = [0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x30, 0x68]
    // CSI ? 1000 l  (disable X11 mouse reporting)
    private let disableMouse1000: [UInt8] = [0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x30, 0x6c]

    /// A single mouse-mode change fires the delegate exactly once, not twice.
    /// Before the fix, the DECSET handler fired terminalMouseModeDidChangeTo:
    /// both through the setter and again explicitly, doubling the work.
    func testSingleChangeFiresOnce() {
        let harness = TerminalTestHarness()
        harness.resetCalls()

        harness.feedEscapeSequence(enableMouse1000)
        harness.sync()

        XCTAssertEqual(harness.delegate.mouseModeDidChangeCount, 1,
                       "One real mouse-mode change should notify the delegate once")
    }

    /// Re-asserting the same mouse mode (what tmux does on every session
    /// switch) must not enqueue any side effect, because nothing changed.
    func testRedundantSameModeDoesNotFire() {
        let harness = TerminalTestHarness()

        // Establish mode 1000.
        harness.feedEscapeSequence(enableMouse1000)
        harness.sync()
        harness.resetCalls()

        // Re-assert the identical mode several times.
        for _ in 0..<5 {
            harness.feedEscapeSequence(enableMouse1000)
        }
        harness.sync()

        XCTAssertEqual(harness.delegate.mouseModeDidChangeCount, 0,
                       "Re-asserting an unchanged mouse mode must not fire the delegate")
    }

    /// A burst of redundant assertions with a couple of genuine changes mixed
    /// in fires only for the genuine changes. This models tmux navigation.
    func testBurstOfRedundantAssertionsCoalesces() {
        let harness = TerminalTestHarness()
        harness.resetCalls()

        // enable (change), enable x9 (no-op), disable (change), disable x9 (no-op)
        harness.feedEscapeSequence(enableMouse1000)
        for _ in 0..<9 {
            harness.feedEscapeSequence(enableMouse1000)
        }
        harness.feedEscapeSequence(disableMouse1000)
        for _ in 0..<9 {
            harness.feedEscapeSequence(disableMouse1000)
        }
        harness.sync()

        XCTAssertEqual(harness.delegate.mouseModeDidChangeCount, 2,
                       "Only the two genuine transitions (enable, disable) should fire")
    }

    /// Toggling between two real modes still notifies once per transition.
    func testRealTransitionsStillFire() {
        let harness = TerminalTestHarness()
        harness.resetCalls()

        harness.feedEscapeSequence(enableMouse1000)   // none -> 1000
        harness.feedEscapeSequence(disableMouse1000)  // 1000 -> none
        harness.feedEscapeSequence(enableMouse1000)   // none -> 1000
        harness.sync()

        XCTAssertEqual(harness.delegate.mouseModeDidChangeCount, 3,
                       "Each genuine transition should fire exactly once")
    }
}
