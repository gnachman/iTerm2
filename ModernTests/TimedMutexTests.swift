//
//  TimedMutexTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

final class TimedMutexTests: XCTestCase {
    func testSyncReturnsClosureResult() {
        let mutex = TimedMutex()
        XCTAssertEqual(mutex.sync { 42 }, 42)
    }

    func testTimedSyncSucceedsWhenUncontended() throws {
        let mutex = TimedMutex()
        XCTAssertEqual(try mutex.sync(timeout: 0) { 42 }, 42)
    }

    func testTimedSyncRethrowsClosureError() {
        struct Expected: Error {}
        let mutex = TimedMutex()
        XCTAssertThrowsError(try mutex.sync(timeout: 0) { throw Expected() }) { error in
            XCTAssertTrue(error is Expected)
        }
        // The lock must have been released.
        XCTAssertNoThrow(try mutex.sync(timeout: 0) { })
    }

    func testTimedSyncThrowsTimeoutWhileHeld() throws {
        let mutex = TimedMutex()
        let acquired = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            mutex.sync {
                acquired.signal()
                release.wait()
            }
            done.signal()
        }
        acquired.wait()

        // The holder can't release until we signal it, so this must time out.
        XCTAssertThrowsError(try mutex.sync(timeout: 0.01) { }) { error in
            XCTAssertTrue(error is TimedMutex.Timeout)
        }

        release.signal()
        done.wait()
        XCTAssertNoThrow(try mutex.sync(timeout: 0) { })
    }

    func testTimedSyncAcquiresOnceHolderReleases() throws {
        let mutex = TimedMutex()
        let acquired = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            mutex.sync {
                acquired.signal()
                release.wait()
            }
        }
        acquired.wait()
        release.signal()

        // The holder releases without depending on us, so a generous timeout succeeds.
        XCTAssertEqual(try mutex.sync(timeout: 60) { 7 }, 7)
    }
}
