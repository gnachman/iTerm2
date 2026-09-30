//
//  SetStatusProgressArgumentTests.swift
//  ModernTests
//
//  The progress ring on the tab is normally drawn by the program itself through OSC 9;4. Codex
//  CLI does not draw it, so its hook used to write the escape sequence to the agent's tty, which
//  meant finding that tty (a Darwin-only walk up the process tree) and is impossible when the
//  hook runs in-process for a remote host. The hook already knows which session it is reporting
//  on, so the ring is now an argument of the status update, applied by iTerm2 through the same
//  path the terminal's OSC 9;4 handler uses.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class SetStatusProgressArgumentTests: XCTestCase {
    func testRunningBecomesAnIndeterminateRing() throws {
        let update = try SetStatusBuiltInFunction.update(from: ["progress": "running"])
        XCTAssertEqual(update.progressPresence, .set)
        XCTAssertEqual(update.progress, .indeterminate)
    }

    func testStoppedStopsTheRing() throws {
        let update = try SetStatusBuiltInFunction.update(from: ["progress": "stopped"])
        XCTAssertEqual(update.progressPresence, .set)
        XCTAssertEqual(update.progress, .stopped)
    }

    func testOmittedProgressLeavesTheRingAlone() throws {
        let update = try SetStatusBuiltInFunction.update(from: ["status": "working"])
        XCTAssertEqual(update.progressPresence, .notSet)
    }

    func testUnknownProgressIsRefused() {
        XCTAssertThrowsError(try SetStatusBuiltInFunction.update(from: ["progress": "spinning"]))
    }

    // The update reaches the screen's progress state, which is what the tab bar draws and what
    // the tab status controller listens to for the end of an operation.
    func testApplyingProgressUpdatesTheScreen() throws {
        let session = PTYSession(synthetic: false)!
        let running = try SetStatusBuiltInFunction.update(from: ["progress": "running"])
        session.screenSetTabStatus(running)
        XCTAssertEqual(screenProgress(of: session), .indeterminate)

        let stopped = try SetStatusBuiltInFunction.update(from: ["progress": "stopped"])
        session.screenSetTabStatus(stopped)
        XCTAssertEqual(screenProgress(of: session), .stopped)
    }

    private func screenProgress(of session: PTYSession) -> VT100ScreenProgress {
        var progress = VT100ScreenProgress.stopped
        // Joining the threads drains the mutation queue, so the update has landed by the time
        // the block runs.
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            progress = mutableState.progress
        })
        return progress
    }
}
