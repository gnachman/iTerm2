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
    // CSI ? 1003 h  (enable any-event mouse reporting)
    private let enableMouse1003: [UInt8] = [0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x33, 0x68]

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

    /// Issue 13184: the side effect must see the new mode. PTYSession decides
    /// whether to track mouse-moved events from the main thread's copy of the
    /// mouse mode when this fires. If the side effect is drained before a sync
    /// (e.g., by a refresh that synced just before the mutation thread ran
    /// CSI ? 1003 h), a stale copy says reporting is off and motion is never
    /// reported.
    func testSideEffectSeesNewModeWhenDrainedBeforeSync() {
        let harness = TerminalTestHarness()
        harness.sync()
        harness.resetCalls()

        // Run the token on the mutation queue, as the pty path does, so the
        // main thread's state is not updated.
        let parser = VT100Parser()
        parser.encoding = String.Encoding.utf8.rawValue
        enableMouse1003.withUnsafeBufferPointer { buf in
            parser.putStreamData(buf.baseAddress, length: Int32(buf.count))
        }
        var vector = CVector()
        CVectorCreate(&vector, 100)
        _ = parser.addParsedTokens(to: &vector)
        iTermGCD.mutationQueue().sync {
            for i in 0..<CVectorCount(&vector) {
                let token = CVectorGetObject(&vector, i) as! VT100Token
                harness.screen.mutableState.terminal!.execute(token)
            }
        }
        CVectorDestroy(&vector)

        // Drain side effects from the main thread without syncing first, as
        // performLightweightBlockWithJoinedThreads does after its sync.
        harness.screen.mutableState.tokenExecutor.executeSideEffectsImmediately(syncFirst: false)

        // 3 is MOUSE_REPORTING_ALL_MOTION.
        XCTAssertEqual(harness.delegate.mouseModesSeenOnChange.map(\.rawValue),
                       [3],
                       "screenMouseModeDidChange must observe the mode that was just set")
    }
}
