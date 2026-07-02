//
//  CompanionStreamPacerTests.swift
//  iTerm2 ModernTests
//
//  Deterministic tests for the change-driven emission decision: emit only on
//  change, honor the frame-rate cap, coalesce bursts, and let a requested
//  keyframe bypass the cap. Time is injected, so nothing depends on wall clock.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionStreamPacerTests: XCTestCase {
    // 30 fps => ~0.0333s minimum interval.
    private func pacer() -> CompanionStreamPacer { CompanionStreamPacer(minInterval: 1.0 / 30.0) }

    func testNoEmitWhenNotDirty() {
        var p = pacer()
        XCTAssertNil(p.evaluate(now: 0))
        XCTAssertNil(p.evaluate(now: 100))
    }

    func testEmitsOnFirstChange() {
        var p = pacer()
        p.noteDirty()
        XCTAssertEqual(p.evaluate(now: 0), .init(keyframe: false))
    }

    func testCapSuppressesSecondFrameWithinInterval() {
        var p = pacer()
        p.noteDirty()
        XCTAssertNotNil(p.evaluate(now: 0))
        p.noteDirty()
        XCTAssertNil(p.evaluate(now: 0.01), "within the cap interval, a change must wait")
    }

    func testEmitsAgainAfterInterval() {
        var p = pacer()
        p.noteDirty()
        _ = p.evaluate(now: 0)
        p.noteDirty()
        XCTAssertEqual(p.evaluate(now: 0.05), .init(keyframe: false))
    }

    func testCoalescesBurstIntoOneFrame() {
        var p = pacer()
        p.noteDirty(); p.noteDirty(); p.noteDirty()
        XCTAssertNotNil(p.evaluate(now: 0))
        // The burst already emitted once; nothing new is pending.
        XCTAssertNil(p.evaluate(now: 1.0))
    }

    func testKeyframeRequestBypassesCap() {
        var p = pacer()
        p.noteDirty()
        _ = p.evaluate(now: 0)
        p.requestKeyframe()
        let emit = p.evaluate(now: 0.001)  // well within the cap interval
        XCTAssertEqual(emit, .init(keyframe: true), "a keyframe must not wait for the cap")
    }

    func testKeyframeRequestImpliesDirty() {
        var p = pacer()
        p.requestKeyframe()
        XCTAssertEqual(p.evaluate(now: 0), .init(keyframe: true),
                       "requesting a keyframe should emit even without a separate change")
    }

    func testStateResetsAfterEmit() {
        var p = pacer()
        p.requestKeyframe()
        _ = p.evaluate(now: 0)
        // After emitting, the keyframe flag and dirty are cleared.
        XCTAssertNil(p.evaluate(now: 1.0))
    }
}
