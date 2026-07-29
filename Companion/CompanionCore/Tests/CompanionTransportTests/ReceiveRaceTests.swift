//
//  ReceiveRaceTests.swift
//  CompanionCore
//
//  The read-vs-close race arbiter must not let a task act on its peer reference
//  before both are assigned: an unstructured Task can start on another thread
//  before `race.close = Task {...}` returns, so a winner could otherwise skip
//  cancelling a peer that was created moments later, leaking it forever. The gate
//  (ready()/start()) closes that window; these lock down its ordering contract.
//

import XCTest
@testable import CompanionTransport

final class ReceiveRaceTests: XCTestCase {
    func test_ready_returnsImmediatelyAfterStart() async {
        let race = ReceiveRace()
        race.start()
        // Must not hang: start() before ready() means the gate is already open.
        await race.ready()
    }

    func test_ready_unblocksWhenStartCalledLater() async {
        let race = ReceiveRace()
        // A waiter suspended in ready() must resume once start() opens the gate.
        async let waited: Void = race.ready()
        race.start()
        await waited
    }

    func test_multipleWaitersAllResumeOnStart() async {
        let race = ReceiveRace()
        async let a: Void = race.ready()
        async let b: Void = race.ready()
        async let c: Void = race.ready()
        race.start()
        _ = await (a, b, c)
    }

    func test_claimIsOneShot() {
        let race = ReceiveRace()
        XCTAssertTrue(race.claim(), "the first claim wins")
        XCTAssertFalse(race.claim(), "a second claim loses")
        XCTAssertFalse(race.claim())
    }
}
