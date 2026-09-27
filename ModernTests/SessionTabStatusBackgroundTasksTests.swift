//
//  SessionTabStatusBackgroundTasksTests.swift
//  ModernTests
//
//  The background-task count that cc-status parks in iTermSessionTabStatus
//  is RAM-only by design: it must round-trip through apply()/copyStatus()
//  but never reach disk via the arrangement dictionary.
//

import XCTest
@testable import iTerm2SharedARC

final class SessionTabStatusBackgroundTasksTests: XCTestCase {
    private func makeUpdate(count: Int?) -> VT100TabStatusUpdate {
        let update = VT100TabStatusUpdate()
        if let count {
            update.backgroundTasksPresence = .set
            update.backgroundTasks = count
        }
        return update
    }

    /// Returns how many iTermSessionTabStatusDidChange notifications `body`
    /// posts for `status`.
    private func notifications(from status: iTermSessionTabStatus, during body: () -> Void) -> Int {
        var count = 0
        let observer = NotificationCenter.default.addObserver(
            forName: iTermSessionTabStatus.didChangeNotificationName,
            object: status,
            queue: nil) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        body()
        return count
    }

    /// The count is bookkeeping for cc-status, not something the tab shows, so
    /// storing it is not a change: a change would repaint the tab, reload the
    /// Session Status tool and bump the recency that picks a workgroup's
    /// representative, for an update the user cannot see.
    func testApplyStoresCountWithoutReportingAChange() {
        let status = iTermSessionTabStatus(sessionID: "s")
        let posted = notifications(from: status) {
            XCTAssertFalse(status.apply(makeUpdate(count: 3)))
        }
        XCTAssertEqual(status.backgroundTasks, 3)
        XCTAssertEqual(posted, 0)
    }

    func testVisibleChangeAlongsideCountReportsAChange() {
        let status = iTermSessionTabStatus(sessionID: "s")
        let update = makeUpdate(count: 3)
        update.statusPresence = .set
        update.status = "working"
        let posted = notifications(from: status) {
            XCTAssertTrue(status.apply(update))
        }
        XCTAssertEqual(posted, 1)
    }

    func testApplyWithoutPresenceLeavesCount() {
        let status = iTermSessionTabStatus(sessionID: "s")
        _ = status.apply(makeUpdate(count: 2))
        let unrelated = VT100TabStatusUpdate()
        unrelated.statusPresence = .set
        unrelated.status = "idle"
        _ = status.apply(unrelated)
        XCTAssertEqual(status.backgroundTasks, 2)
    }

    func testApplySameCountReportsNoChange() {
        let status = iTermSessionTabStatus(sessionID: "s")
        _ = status.apply(makeUpdate(count: 2))
        XCTAssertFalse(status.apply(makeUpdate(count: 2)))
    }

    func testClearResetsCount() {
        let status = iTermSessionTabStatus(sessionID: "s")
        _ = status.apply(makeUpdate(count: 5))
        status.clear()
        XCTAssertEqual(status.backgroundTasks, 0)
    }

    func testCopyCarriesCount() {
        let status = iTermSessionTabStatus(sessionID: "s")
        _ = status.apply(makeUpdate(count: 4))
        XCTAssertEqual(status.copyStatus().backgroundTasks, 4)
    }

    // MARK: - Atomic delta

    private func makeDelta(_ delta: Int) -> VT100TabStatusUpdate {
        let update = VT100TabStatusUpdate()
        update.backgroundTasksDelta = NSNumber(value: delta)
        return update
    }

    func testDeltaAddsToCount() {
        let status = iTermSessionTabStatus(sessionID: "s")
        _ = status.apply(makeDelta(1))
        XCTAssertEqual(status.backgroundTasks, 1)
        _ = status.apply(makeDelta(1))
        XCTAssertEqual(status.backgroundTasks, 2)
        _ = status.apply(makeDelta(-1))
        XCTAssertEqual(status.backgroundTasks, 1)
    }

    /// A caller that loses track and decrements too often must not drive the
    /// count negative, which would then need extra increments before the tab
    /// could look busy again.
    func testDeltaClampsAtZero() {
        let status = iTermSessionTabStatus(sessionID: "s")
        _ = status.apply(makeUpdate(count: 1))
        _ = status.apply(makeDelta(-5))
        XCTAssertEqual(status.backgroundTasks, 0)
    }

    /// Assignment and addition in one update have no sensible meaning. The
    /// built-in function refuses the pair outright; if one ever reaches the
    /// model anyway, the explicit count is what takes effect.
    func testExplicitCountBeatsDelta() {
        let status = iTermSessionTabStatus(sessionID: "s")
        _ = status.apply(makeUpdate(count: 4))
        let both = makeUpdate(count: 9)
        both.backgroundTasksDelta = NSNumber(value: 100)
        _ = status.apply(both)
        XCTAssertEqual(status.backgroundTasks, 9)
    }

    func testClearBeatsDelta() {
        let status = iTermSessionTabStatus(sessionID: "s")
        _ = status.apply(makeUpdate(count: 4))
        let update = VT100TabStatusUpdate()
        update.backgroundTasksPresence = .cleared
        update.backgroundTasksDelta = NSNumber(value: 3)
        _ = status.apply(update)
        XCTAssertEqual(status.backgroundTasks, 0)
    }

    func testZeroDeltaReportsNoChange() {
        let status = iTermSessionTabStatus(sessionID: "s")
        _ = status.apply(makeUpdate(count: 2))
        XCTAssertFalse(status.apply(makeDelta(0)))
        XCTAssertEqual(status.backgroundTasks, 2)
    }

    /// The delta is a CLI argument and can be anything. A plain + traps on
    /// overflow and would take the app down; the count saturates instead.
    func testHugeDeltaSaturatesInsteadOfTrapping() {
        let status = iTermSessionTabStatus(sessionID: "s")
        _ = status.apply(makeUpdate(count: 1))
        _ = status.apply(makeDelta(Int.max))
        XCTAssertEqual(status.backgroundTasks, Int.max)
        _ = status.apply(makeDelta(Int.min))
        XCTAssertEqual(status.backgroundTasks, 0)
        _ = status.apply(makeDelta(Int.min))
        XCTAssertEqual(status.backgroundTasks, 0)
    }

    func testDescriptionShowsDelta() {
        XCTAssertTrue(makeDelta(-1).description.contains("background-tasks-delta=-1"),
                      makeDelta(-1).description)
    }

    // MARK: - Turn flag

    private func makeTurn(open: Bool) -> VT100TabStatusUpdate {
        let update = VT100TabStatusUpdate()
        update.turnOpenPresence = .set
        update.turnOpen = open
        return update
    }

    func testTurnOpenStartsUnknown() {
        XCTAssertNil(iTermSessionTabStatus(sessionID: "s").turnOpen)
    }

    func testTurnOpenRoundTrips() {
        let status = iTermSessionTabStatus(sessionID: "s")
        _ = status.apply(makeTurn(open: true))
        XCTAssertEqual(status.turnOpen, true)
        _ = status.apply(makeTurn(open: false))
        XCTAssertEqual(status.turnOpen, false)
        XCTAssertEqual(status.copyStatus().turnOpen, false)
        XCTAssertTrue(makeTurn(open: false).description.contains("turn-open=false"))
    }

    /// Like the count, the flag is invisible bookkeeping: a hook that only
    /// records it must not trigger a tab repaint or a Session Status reload.
    func testTurnOpenAloneDoesNotReportAChange() {
        let status = iTermSessionTabStatus(sessionID: "s")
        let posted = notifications(from: status) {
            XCTAssertFalse(status.apply(makeTurn(open: true)))
            XCTAssertFalse(status.apply(makeTurn(open: false)))
        }
        XCTAssertEqual(status.turnOpen, false)
        XCTAssertEqual(posted, 0)
    }

    func testUnrelatedUpdateLeavesTurnOpen() {
        let status = iTermSessionTabStatus(sessionID: "s")
        _ = status.apply(makeTurn(open: true))
        _ = status.apply(makeDelta(1))
        XCTAssertEqual(status.turnOpen, true)
    }

    func testClearForgetsTurnOpen() {
        let status = iTermSessionTabStatus(sessionID: "s")
        _ = status.apply(makeTurn(open: true))
        status.clear()
        XCTAssertNil(status.turnOpen)
    }

    func testClearedTurnOpenBecomesUnknown() {
        let status = iTermSessionTabStatus(sessionID: "s")
        _ = status.apply(makeTurn(open: false))
        let update = VT100TabStatusUpdate()
        update.turnOpenPresence = .cleared
        let posted = notifications(from: status) {
            XCTAssertFalse(status.apply(update))
        }
        XCTAssertNil(status.turnOpen)
        XCTAssertEqual(posted, 0)
        XCTAssertTrue(update.description.contains("turn-open=cleared"), update.description)
    }

    /// A terminal reset goes through the static clear update rather than
    /// clear(). It wipes what is displayed, not what the hooks parked: a
    /// reset while a detached sub-agent runs must not make the parent's Stop
    /// read zero and report idle through live background work, and its later
    /// SubagentStop could not repair that. A stale flag is harmless here
    /// because a SubagentStop that finds nothing displayed changes nothing.
    func testStaticClearUpdateKeepsCountAndTurnOpen() {
        let status = iTermSessionTabStatus(sessionID: "s")
        let update = makeUpdate(count: 3)
        update.turnOpenPresence = .set
        update.turnOpen = false
        update.statusPresence = .set
        update.status = "working"
        _ = status.apply(update)
        XCTAssertTrue(status.apply(VT100TabStatusUpdate.clear))
        XCTAssertNil(status.statusText)
        XCTAssertEqual(status.backgroundTasks, 3)
        XCTAssertEqual(status.turnOpen, false)
    }

    // MARK: - Preconditions

    /// cc-status decides to write idle from a status it read a moment
    /// earlier. A prompt submitted in between reopens the turn, and an
    /// unconditional idle would then cover a running turn. The update carries
    /// the state it assumed, and iTerm2 drops it whole when that no longer
    /// holds.
    func testUpdateIsDroppedWhenTurnOpenPreconditionFails() {
        let status = iTermSessionTabStatus(sessionID: "s")
        let seed = makeTurn(open: true)
        seed.statusPresence = .set
        seed.status = "working"
        _ = status.apply(seed)

        let idle = VT100TabStatusUpdate()
        idle.statusPresence = .set
        idle.status = "idle"
        idle.detailPresence = .set
        idle.detail = "DONE"
        idle.requiredTurnOpen = NSNumber(value: false)
        let posted = notifications(from: status) {
            XCTAssertFalse(status.apply(idle))
        }
        XCTAssertEqual(status.statusText, "working")
        XCTAssertNil(status.detailText)
        XCTAssertEqual(posted, 0)
    }

    func testUpdateIsDroppedWhenBackgroundTasksPreconditionFails() {
        let status = iTermSessionTabStatus(sessionID: "s")
        _ = status.apply(makeUpdate(count: 1))
        let idle = VT100TabStatusUpdate()
        idle.statusPresence = .set
        idle.status = "idle"
        idle.requiredBackgroundTasks = NSNumber(value: 0)
        XCTAssertFalse(status.apply(idle))
        XCTAssertNil(status.statusText)
    }

    func testUpdateAppliesWhenPreconditionsHold() {
        let status = iTermSessionTabStatus(sessionID: "s")
        let seed = makeTurn(open: false)
        seed.statusPresence = .set
        seed.status = "working"
        _ = status.apply(seed)

        let idle = VT100TabStatusUpdate()
        idle.statusPresence = .set
        idle.status = "idle"
        idle.requiredTurnOpen = NSNumber(value: false)
        idle.requiredBackgroundTasks = NSNumber(value: 0)
        XCTAssertTrue(status.apply(idle))
        XCTAssertEqual(status.statusText, "idle")
    }

    /// A flag iTerm2 was never told is unknown, and unknown is not closed:
    /// the same rule cc-status applies when it reads the flag itself.
    func testUnknownTurnOpenFailsAClosedTurnPrecondition() {
        let status = iTermSessionTabStatus(sessionID: "s")
        let idle = VT100TabStatusUpdate()
        idle.statusPresence = .set
        idle.status = "idle"
        idle.requiredTurnOpen = NSNumber(value: false)
        XCTAssertFalse(status.apply(idle))
        XCTAssertNil(status.statusText)
    }

    /// The count and the flag are part of the update too, so a dropped update
    /// must not leave a delta or a flag behind.
    func testDroppedUpdateChangesNoBookkeeping() {
        let status = iTermSessionTabStatus(sessionID: "s")
        _ = status.apply(makeTurn(open: true))
        let update = makeDelta(1)
        update.turnOpenPresence = .set
        update.turnOpen = false
        update.requiredTurnOpen = NSNumber(value: false)
        XCTAssertFalse(status.apply(update))
        XCTAssertEqual(status.backgroundTasks, 0)
        XCTAssertEqual(status.turnOpen, true)
    }

    func testDescriptionShowsPreconditions() {
        let update = VT100TabStatusUpdate()
        update.requiredTurnOpen = NSNumber(value: false)
        update.requiredBackgroundTasks = NSNumber(value: 0)
        XCTAssertTrue(update.description.contains("if-turn-open=false"), update.description)
        XCTAssertTrue(update.description.contains("if-background-tasks=0"), update.description)
    }

    /// Like the count, the flag describes a program that dies with the
    /// session, so it must not be written to disk or come back on restore.
    func testArrangementDictionaryExcludesTurnOpen() {
        let status = iTermSessionTabStatus(sessionID: "s")
        let update = makeTurn(open: true)
        update.statusPresence = .set
        update.status = "working"
        _ = status.apply(update)
        guard let dict = status.arrangementDictionary() as? [String: Any] else {
            XCTFail("Expected an arrangement dictionary")
            return
        }
        for key in dict.keys {
            XCTAssertFalse(key.lowercased().contains("turn"), "Unexpected key \(key)")
        }
        let restored = iTermSessionTabStatus.fromArrangementDictionary(dict as NSDictionary,
                                                                       sessionID: "s2")
        XCTAssertNil(restored.turnOpen)
    }

    func testArrangementDictionaryExcludesCount() {
        // The privacy guarantee: the count is never encoded to disk. Give
        // the status a visible field so arrangementDictionary() returns a
        // dictionary at all, then check nothing in it reflects the count.
        let status = iTermSessionTabStatus(sessionID: "s")
        let update = makeUpdate(count: 7)
        update.statusPresence = .set
        update.status = "working"
        _ = status.apply(update)
        guard let dict = status.arrangementDictionary() as? [String: Any] else {
            XCTFail("Expected an arrangement dictionary")
            return
        }
        for (key, value) in dict {
            XCTAssertFalse(key.lowercased().contains("background"), "Unexpected key \(key)")
            XCTAssertFalse("\(value)".contains("7"), "Count leaked into \(key)")
        }
        // And a restore therefore comes back with zero.
        let restored = iTermSessionTabStatus.fromArrangementDictionary(dict as NSDictionary,
                                                                       sessionID: "s2")
        XCTAssertEqual(restored.backgroundTasks, 0)
    }
}
