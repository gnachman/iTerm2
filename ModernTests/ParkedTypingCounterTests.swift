//
//  ParkedTypingCounterTests.swift
//  iTerm2 ModernTests
//
//  ParkedTypingCounter ref-counts outstanding turn-parks that cleared the typing
//  spinner, so the spinner turns OFF on the first park and back ON only when the
//  LAST park resolves. Approving one of two concurrent approval parks must not
//  restore the spinner while the other is still parked.
//

import XCTest
@testable import iTerm2SharedARC

final class ParkedTypingCounterTests: XCTestCase {
    func testFirstParkClears_lastResumeRestores() {
        var c = ParkedTypingCounter()
        XCTAssertTrue(c.park(), "first park turns the spinner off")
        XCTAssertFalse(c.park(), "a second concurrent park must not re-publish")
        XCTAssertFalse(c.resume(), "resuming one of two parks must not restore the spinner")
        XCTAssertTrue(c.resume(), "the last resume restores the spinner")
    }

    func testSequentialParksEachToggle() {
        var c = ParkedTypingCounter()
        XCTAssertTrue(c.park())
        XCTAssertTrue(c.resume())
        XCTAssertTrue(c.park())
        XCTAssertTrue(c.resume())
    }

    func testResumeWithoutParkIsNoOp() {
        var c = ParkedTypingCounter()
        XCTAssertFalse(c.resume())
        XCTAssertFalse(c.resume())
    }
}
