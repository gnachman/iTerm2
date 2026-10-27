//
//  CompanionAppNapBlockerTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionAppNapBlockerTests: XCTestCase {
    private final class FakeActivities {
        var begun = 0
        var ended = 0
        var outstanding: Int { begun - ended }
    }

    private func makeBlocker(_ fake: FakeActivities) -> CompanionAppNapBlocker {
        return CompanionAppNapBlocker(begin: {
            fake.begun += 1
            return NSObject()
        }, end: { _ in
            fake.ended += 1
        })
    }

    func testStartsWithNoActivity() {
        let fake = FakeActivities()
        _ = makeBlocker(fake)
        XCTAssertEqual(fake.begun, 0)
    }

    func testPairingBeginsActivity() {
        let fake = FakeActivities()
        let blocker = makeBlocker(fake)
        blocker.setPaired(true)
        XCTAssertEqual(fake.outstanding, 1)
    }

    func testRepeatedPairedDoesNotStackActivities() {
        let fake = FakeActivities()
        let blocker = makeBlocker(fake)
        blocker.setPaired(true)
        blocker.setPaired(true)
        XCTAssertEqual(fake.begun, 1)
    }

    func testUnpairingEndsActivity() {
        let fake = FakeActivities()
        let blocker = makeBlocker(fake)
        blocker.setPaired(true)
        blocker.setPaired(false)
        XCTAssertEqual(fake.begun, 1)
        XCTAssertEqual(fake.ended, 1)
    }

    func testUnpairingWhenNotPairedDoesNothing() {
        let fake = FakeActivities()
        let blocker = makeBlocker(fake)
        blocker.setPaired(false)
        XCTAssertEqual(fake.ended, 0)
    }

    func testRepairingBeginsAgain() {
        let fake = FakeActivities()
        let blocker = makeBlocker(fake)
        blocker.setPaired(true)
        blocker.setPaired(false)
        blocker.setPaired(true)
        XCTAssertEqual(fake.begun, 2)
        XCTAssertEqual(fake.outstanding, 1)
    }

    func testEndsTheTokenItBegan() {
        let token = NSObject()
        var endedToken: NSObjectProtocol?
        let blocker = CompanionAppNapBlocker(begin: { token },
                                             end: { endedToken = $0 })
        blocker.setPaired(true)
        blocker.setPaired(false)
        XCTAssertTrue(endedToken === token)
    }
}
