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

    func testApplyStoresCount() {
        let status = iTermSessionTabStatus(sessionID: "s")
        XCTAssertTrue(status.apply(makeUpdate(count: 3)))
        XCTAssertEqual(status.backgroundTasks, 3)
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
