//
//  WeakObserverListTests.swift
//  iTerm2 ModernTests
//
//  WeakObserverList is the subscribe-with-a-token list shared by the modal
//  alert registry and the main thread monitor.
//

import XCTest
import os
@testable import iTerm2SharedARC

final class WeakObserverListTests: XCTestCase {
    func testSubscribersAreCalledInOrderEachTime() {
        let list = WeakObserverList()
        let calls = OSAllocatedUnfairLock(initialState: [String]())
        let first = list.add { calls.withLock { $0.append("first") } }
        let second = list.add { calls.withLock { $0.append("second") } }
        XCTAssertFalse(list.isEmpty)
        list.notify()
        list.notify()
        XCTAssertEqual(calls.withLock { $0 }, ["first", "second", "first", "second"])
        _ = (first, second)
    }

    func testDroppingTheTokenUnsubscribes() {
        let list = WeakObserverList()
        let calls = OSAllocatedUnfairLock(initialState: 0)
        var token: AnyObject? = list.add { calls.withLock { $0 += 1 } }
        _ = token
        list.notify()
        token = nil
        list.notify()
        XCTAssertEqual(calls.withLock { $0 }, 1)
        XCTAssertTrue(list.isEmpty)
    }

    func testACallbackMaySubscribeWhileBeingNotified() {
        let list = WeakObserverList()
        let tokens = OSAllocatedUnfairLock(uncheckedState: [AnyObject]())
        let lateCalls = OSAllocatedUnfairLock(initialState: 0)
        let token = list.add {
            let late = list.add { lateCalls.withLock { $0 += 1 } }
            tokens.withLockUnchecked { $0.append(late) }
        }
        list.notify()  // must not deadlock
        XCTAssertEqual(lateCalls.withLock { $0 }, 0, "a subscriber added during a notification joins from the next one")
        list.notify()
        XCTAssertEqual(lateCalls.withLock { $0 }, 1)
        _ = token
    }
}
