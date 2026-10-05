//
//  ShardMapRaceArbiterTests.swift
//  CompanionCore
//
//  The rules that pick a winner when the shard map is fetched from the primary
//  resolver and its mirrors at once, tested by feeding events in exact orders.
//  The primary is authoritative. A mirror can lag (GitHub Pages caches for ten
//  minutes), so its map only competes when the loader would adopt it.
//

import XCTest
@testable import CompanionProtocol

final class ShardMapRaceArbiterTests: XCTestCase {
    private func map(_ version: Int) -> ShardMap {
        ShardMap(version: version, ranges: [.init(low: 0, high: 65535, host: "v\(version).iterm2.com")])
    }

    /// Two sources: index 0 is the primary, index 1 the mirror. Like a cold
    /// loader (no map loaded) whose persisted floor is `floor`, so it adopts
    /// maps at or above it.
    private func arbiter(floor: Int? = nil) -> ShardMapRaceArbiter {
        ShardMapRaceArbiter(sourceCount: 2,
                            highestVersion: floor, hasCurrentMap: false)
    }

    private func winner(_ decision: ShardMapRaceArbiter.Decision) -> (version: Int, index: Int)? {
        if case let .win(map, index) = decision {
            return (map.version, index)
        }
        return nil
    }

    func testPrimaryWinsImmediately() {
        var a = arbiter()
        XCTAssertEqual(winner(a.handle(.map(map(3), index: 0)))?.index, 0)
    }

    func testPrimaryWinsEvenWhenNotNewerIfAMapIsLoaded() {
        // In steady state the primary usually serves the version already loaded.
        // That is the truth ("nothing changed"), so it must not wait on a mirror.
        var a = ShardMapRaceArbiter(sourceCount: 2,
                                    highestVersion: 10, hasCurrentMap: true)
        XCTAssertEqual(winner(a.handle(.map(map(10), index: 0)))?.version, 10)
    }

    func testPrimaryAtTheFloorWinsOnColdStart() {
        var a = arbiter(floor: 10)
        XCTAssertEqual(winner(a.handle(.map(map(10), index: 0)))?.version, 10)
    }

    func testStalePrimaryOnColdStartLetsAHeldMirrorWin() {
        // Floor v12, nothing loaded. The mirror's v12 arrives first and is held;
        // then a lagging primary edge serves v11, which refresh() would discard.
        var a = arbiter(floor: 12)
        XCTAssertEqual(a.handle(.map(map(12), index: 1)), .wait)
        XCTAssertEqual(winner(a.handle(.map(map(11), index: 0)))?.version, 12)
    }

    func testStalePrimaryOnColdStartLetsALaterMirrorWin() {
        var a = arbiter(floor: 12)
        XCTAssertEqual(a.handle(.map(map(11), index: 0)), .wait)
        XCTAssertFalse(a.primaryHasPriority)
        XCTAssertEqual(winner(a.handle(.map(map(12), index: 1)))?.version, 12)
    }

    func testStalePrimaryOnColdStartWithNothingBetterFailsAndSaysWhy() {
        var a = arbiter(floor: 12)
        XCTAssertEqual(a.rejection(of: map(11), from: 0), .outdatedMap(served: 11, latestSeen: 12))
        XCTAssertEqual(a.handle(.map(map(11), index: 0)), .wait)
        XCTAssertEqual(a.handle(.failed(URLError(.timedOut), index: 1, duration: 15)), .fail)
    }

    func testUsefulMirrorIsHeldUntilTheDelayElapses() {
        var a = arbiter()
        XCTAssertEqual(a.handle(.map(map(3), index: 1)), .wait)
        XCTAssertEqual(winner(a.handle(.delayElapsed))?.index, 1)
    }

    func testUsefulMirrorWinsWhenThePrimaryFails() {
        var a = arbiter()
        XCTAssertEqual(a.handle(.map(map(3), index: 1)), .wait)
        XCTAssertEqual(winner(a.handle(.failed(URLError(.timedOut), index: 0, duration: 1)))?.index, 1)
    }

    func testStaleMirrorDoesNotWinAfterTheDelay() {
        // Floor v10; the mirror lags at v9 and the primary is slow but healthy.
        var a = arbiter(floor: 10)
        XCTAssertEqual(a.handle(.map(map(9), index: 1)), .wait)
        XCTAssertEqual(a.handle(.delayElapsed), .wait)
        XCTAssertEqual(winner(a.handle(.map(map(10), index: 0)))?.version, 10)
    }

    func testStaleMirrorArrivingAfterTheDelayDoesNotWin() {
        var a = arbiter(floor: 10)
        XCTAssertEqual(a.handle(.delayElapsed), .wait)
        XCTAssertEqual(a.handle(.map(map(9), index: 1)), .wait)
        XCTAssertEqual(winner(a.handle(.map(map(10), index: 0)))?.version, 10)
    }

    func testStaleMirrorIsAFailedAttemptWhenNothingElseIsLeft() {
        // The primary is unreachable and the mirror is behind: there is no
        // up-to-date map, so the race fails and the mirror's copy is rejected.
        var a = arbiter(floor: 10)
        XCTAssertEqual(a.rejection(of: map(9), from: 1), .outdatedMap(served: 9, latestSeen: 10))
        XCTAssertEqual(a.handle(.map(map(9), index: 1)), .wait)
        XCTAssertEqual(a.handle(.failed(URLError(.timedOut), index: 0, duration: 15)), .fail)
    }

    private func warmArbiter(loaded version: Int) -> ShardMapRaceArbiter {
        ShardMapRaceArbiter(sourceCount: 2,
                            highestVersion: version, hasCurrentMap: true)
    }

    func testMirrorServingTheLoadedVersionWinsWhenThePrimaryFails() {
        // The primary is unreachable and the mirror serves the version already
        // loaded. That confirms the loaded map is current, exactly as the
        // primary's same answer would, so it is not an outdated copy.
        var a = warmArbiter(loaded: 10)
        XCTAssertEqual(a.handle(.map(map(10), index: 1)), .wait)
        XCTAssertEqual(winner(a.handle(.failed(URLError(.timedOut), index: 0, duration: 15)))?.version, 10)
    }

    func testMirrorServingTheLoadedVersionWinsAfterThePrimaryFailed() {
        var a = warmArbiter(loaded: 10)
        XCTAssertEqual(a.handle(.failed(URLError(.timedOut), index: 0, duration: 15)), .wait)
        XCTAssertEqual(winner(a.handle(.map(map(10), index: 1)))?.index, 1)
    }

    func testMirrorOlderThanTheLoadedMapIsOutdated() {
        var a = warmArbiter(loaded: 10)
        XCTAssertEqual(a.rejection(of: map(9), from: 1), .outdatedMap(served: 9, latestSeen: 10))
        XCTAssertEqual(a.handle(.map(map(9), index: 1)), .wait)
        XCTAssertEqual(a.handle(.failed(URLError(.timedOut), index: 0, duration: 15)), .fail)
    }

    func testMapsThatCanWinAreNotRejected() {
        let a = warmArbiter(loaded: 10)
        // The primary is the truth even when it is not newer.
        XCTAssertNil(a.rejection(of: map(9), from: 0))
        XCTAssertNil(a.rejection(of: map(10), from: 0))
        // A mirror confirming the loaded version, or serving a newer one.
        XCTAssertNil(a.rejection(of: map(10), from: 1))
        XCTAssertNil(a.rejection(of: map(11), from: 1))
    }

    func testHeldNewerMirrorBeatsAPrimaryWithNothingNew() {
        // After a stale-map rejection, v5 is loaded and known stale. The mirror
        // already answered v6; then a lagging primary edge answers v5. Taking
        // the primary's answer would send the caller back to the same host.
        var a = warmArbiter(loaded: 5)
        XCTAssertEqual(a.handle(.map(map(6), index: 1)), .wait)
        let won = winner(a.handle(.map(map(5), index: 0)))
        XCTAssertEqual(won?.version, 6)
        XCTAssertEqual(won?.index, 1)
    }

    func testPrimaryWithNothingNewBeatsAHeldMirrorThatOnlyConfirmsIt() {
        var a = warmArbiter(loaded: 5)
        XCTAssertEqual(a.handle(.map(map(5), index: 1)), .wait)
        XCTAssertEqual(winner(a.handle(.map(map(5), index: 0)))?.index, 0)
    }

    func testNewerPrimaryBeatsAHeldNewerMirror() {
        var a = warmArbiter(loaded: 5)
        XCTAssertEqual(a.handle(.map(map(6), index: 1)), .wait)
        XCTAssertEqual(winner(a.handle(.map(map(7), index: 0)))?.index, 0)
    }

    func testNewerMirrorReplacesAHeldOne() {
        var a = ShardMapRaceArbiter(sourceCount: 3,
                                    highestVersion: 10, hasCurrentMap: true)
        XCTAssertEqual(a.handle(.map(map(10), index: 1)), .wait)
        XCTAssertEqual(a.handle(.map(map(11), index: 2)), .wait)
        XCTAssertEqual(winner(a.handle(.delayElapsed))?.version, 11)
    }

    func testLonePrimaryBelowTheFloorOnColdStartFails() {
        // A fork or self-hosted resolver has no mirrors; it must fail the same
        // way, not hand back a map that would be ignored.
        var a = ShardMapRaceArbiter(sourceCount: 1,
                                    highestVersion: 12, hasCurrentMap: false)
        XCTAssertEqual(a.rejection(of: map(11), from: 0), .outdatedMap(served: 11, latestSeen: 12))
        XCTAssertEqual(a.handle(.map(map(11), index: 0)), .fail)
    }

    func testCancelledFetchCountsAsFailed() {
        // The Mac's plugin reloading mid-fetch ends the primary with a
        // cancellation. It counts as failed, so the mirror gets its chance.
        var a = arbiter()
        XCTAssertEqual(a.handle(.failed(URLError(.cancelled), index: 0, duration: 1)), .wait)
        XCTAssertFalse(a.primaryHasPriority)
        XCTAssertEqual(a.handle(.failed(URLError(.cannotFindHost), index: 1, duration: 2)), .fail)
    }

    func testFailsWhenEverySourceFails() {
        var a = arbiter()
        XCTAssertEqual(a.handle(.failed(URLError(.timedOut), index: 1, duration: 1)), .wait)
        XCTAssertEqual(a.handle(.failed(URLError(.timedOut), index: 0, duration: 2)), .fail)
    }
}
