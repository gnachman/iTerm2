//
//  RestoredArrangementFrameGuardTests.swift
//  ModernTests
//
//  Decisions made by the guard that keeps a restored arrangement's window on its
//  display. Issue 13002.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class RestoredArrangementFrameGuardTests: XCTestCase {
    // The reporter's layout: built-in display, then right and left externals.
    private let screens = [NSRect(x: 0, y: 0, width: 1728, height: 1117),
                           NSRect(x: 840, y: 1117, width: 1920, height: 1080),
                           NSRect(x: -1080, y: 1117, width: 1920, height: 1080)]
    private let saved = NSRect(x: 840, y: 1117, width: 1920, height: 1050)
    private let displaced = NSRect(x: -1080, y: 1117, width: 1920, height: 1050)
    private let configuration: NSArray = ["three displays"]
    private var time: TimeInterval = 100

    private func makeGuard() -> RestoredArrangementFrameGuard {
        let frameGuard = RestoredArrangementFrameGuard(now: { [unowned self] in self.time })
        frameGuard.arm(frame: saved, screenConfiguration: configuration)
        return frameGuard
    }

    private func check(_ frameGuard: RestoredArrangementFrameGuard,
                       windowFrame: NSRect,
                       lastFrameSetByApp: NSRect? = nil,
                       configuration: NSArray? = nil) -> NSRect? {
        return frameGuard.frameToRestore(windowFrame: windowFrame,
                                         lastFrameSetByApp: lastFrameSetByApp ?? saved,
                                         screenFrames: screens,
                                         screenConfiguration: configuration ?? self.configuration)
    }

    func testPutsBackAMoveFromOutsideTheAppToAnotherDisplay() {
        let frameGuard = makeGuard()
        XCTAssertEqual(check(frameGuard, windowFrame: displaced), saved)
        XCTAssertTrue(frameGuard.isArmed)
    }

    func testIgnoresChangesThatStayOnTheSameDisplay() {
        let frameGuard = makeGuard()
        let nudged = saved.offsetBy(dx: 20, dy: -10)
        XCTAssertNil(check(frameGuard, windowFrame: nudged))
        XCTAssertTrue(frameGuard.isArmed)
    }

    func testStandsDownWhenTheAppMovedTheWindowItself() {
        let frameGuard = makeGuard()
        XCTAssertNil(check(frameGuard, windowFrame: displaced, lastFrameSetByApp: displaced))
        XCTAssertFalse(frameGuard.isArmed)
    }

    func testGivesUpAfterTheMaximumNumberOfReassertions() {
        let frameGuard = makeGuard()
        for _ in 0..<RestoredArrangementFrameGuard.maxReassertions {
            XCTAssertEqual(check(frameGuard, windowFrame: displaced), saved)
        }
        XCTAssertNil(check(frameGuard, windowFrame: displaced))
        XCTAssertFalse(frameGuard.isArmed)
    }

    func testStandsDownWhenTheDisplaysChange() {
        let frameGuard = makeGuard()
        XCTAssertNil(check(frameGuard, windowFrame: displaced, configuration: ["two displays"]))
        XCTAssertFalse(frameGuard.isArmed)
    }

    func testStandsDownWhenItsLifetimeEnds() {
        let frameGuard = makeGuard()
        time += RestoredArrangementFrameGuard.lifetime
        XCTAssertNil(check(frameGuard, windowFrame: displaced))
        XCTAssertFalse(frameGuard.isArmed)
    }

    func testDisarmedGuardDoesNothing() {
        let frameGuard = makeGuard()
        frameGuard.disarm(because: "test")
        XCTAssertNil(check(frameGuard, windowFrame: displaced))
    }

    func testDisplayIndexPicksTheDisplayHoldingMostOfTheFrame() {
        XCTAssertEqual(RestoredArrangementFrameGuard.displayIndex(for: saved, screenFrames: screens), 1)
        XCTAssertEqual(RestoredArrangementFrameGuard.displayIndex(for: displaced, screenFrames: screens), 2)
        let offEverything = NSRect(x: -5000, y: -5000, width: 100, height: 100)
        XCTAssertNil(RestoredArrangementFrameGuard.displayIndex(for: offEverything, screenFrames: screens))
    }
}
