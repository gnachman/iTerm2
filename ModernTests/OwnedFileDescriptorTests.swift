//
//  OwnedFileDescriptorTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

final class OwnedFileDescriptorTests: XCTestCase {
    // Records closes instead of closing anything real.
    private final class Closer {
        private let lock = NSLock()
        private var _closed = [Int32]()

        var closed: [Int32] {
            lock.lock()
            defer { lock.unlock() }
            return _closed
        }

        func close(_ fd: Int32) -> Int32 {
            lock.lock()
            _closed.append(fd)
            lock.unlock()
            return 0
        }
    }

    private let closer = Closer()

    private func make(_ fd: Int32 = 42) -> OwnedFileDescriptor {
        return OwnedFileDescriptor(fd, close: closer.close)
    }

    func testCloseClosesOnce() {
        let owned = make()
        XCTAssertEqual(owned.unsafeFileDescriptor, 42)
        owned.close()
        owned.close()
        XCTAssertEqual(closer.closed, [42])
        XCTAssertEqual(owned.unsafeFileDescriptor, -1)
    }

    // On Darwin the descriptor is released even when close(2) fails with EINTR, and its number may
    // already belong to someone else, so it must not be closed again.
    func testCloseInterruptedBySignalIsNotRetried() {
        var attempts = 0
        do {
            let owned = OwnedFileDescriptor(42, close: { _ in
                attempts += 1
                errno = EINTR
                return -1
            })
            owned.close()
            XCTAssertTrue(owned.isClosed)
            owned.close()
        }
        XCTAssertEqual(attempts, 1)
    }

    func testDeallocationClosesIfNotClosed() {
        do {
            _ = make()
        }
        XCTAssertEqual(closer.closed, [42])
    }

    func testDeallocationAfterCloseDoesNotCloseAgain() {
        do {
            let owned = make()
            owned.close()
        }
        XCTAssertEqual(closer.closed, [42])
    }

    func testNegativeDescriptorIsNeverClosed() {
        do {
            let owned = make(-1)
            XCTAssertNil(owned.lease())
            XCTAssertFalse(owned.withFileDescriptor { _ in XCTFail("Ran with no descriptor") })
            owned.close()
        }
        XCTAssertEqual(closer.closed, [])
    }

    func testLeaseDefersCloseUntilReleased() {
        let owned = make()
        let lease = owned.lease()
        XCTAssertEqual(lease?.fileDescriptor, 42)
        owned.close()
        XCTAssertEqual(closer.closed, [])
        XCTAssertEqual(owned.unsafeFileDescriptor, -1, "Closing is requested even though it is deferred")
        lease?.release()
        XCTAssertEqual(closer.closed, [42])
        lease?.release()
        XCTAssertEqual(closer.closed, [42])
    }

    func testDeallocatingALeaseReleasesIt() {
        let owned = make()
        var lease = owned.lease()
        owned.close()
        XCTAssertNotNil(lease)
        lease = nil
        XCTAssertEqual(closer.closed, [42])
    }

    func testCloseWaitsForEveryLease() {
        let owned = make()
        let first = owned.lease()
        let second = owned.lease()
        owned.close()
        first?.release()
        XCTAssertEqual(closer.closed, [])
        second?.release()
        XCTAssertEqual(closer.closed, [42])
    }

    // A lease keeps the descriptor open even after its owner lets go of the object, and the last
    // reference going away closes it.
    func testLeaseOutlivesOwner() {
        var lease: OwnedFileDescriptor.Lease?
        do {
            let owned = make()
            lease = owned.lease()
        }
        XCTAssertEqual(closer.closed, [])
        XCTAssertEqual(lease?.fileDescriptor, 42)
        lease = nil
        XCTAssertEqual(closer.closed, [42])
    }

    func testNoLeaseOrAccessAfterClose() {
        let owned = make()
        owned.close()
        XCTAssertNil(owned.lease())
        XCTAssertFalse(owned.withFileDescriptor { _ in XCTFail("Ran after close") })
    }

    func testWithFileDescriptorDefersClose() {
        let owned = make()
        var ran = false
        XCTAssertTrue(owned.withFileDescriptor { fd in
            ran = true
            XCTAssertEqual(fd, 42)
            owned.close()
            XCTAssertEqual(closer.closed, [], "Closed while in use")
        })
        XCTAssertTrue(ran)
        XCTAssertEqual(closer.closed, [42])
    }

    // However leases, accesses, and closes interleave, the descriptor is closed exactly once and
    // never while in use.
    func testConcurrentUseClosesOnceAndNeverWhileInUse() {
        for _ in 0..<200 {
            let closer = Closer()
            let inUse = MutableAtomicObject(0)
            var sawCloseWhileInUse = false
            let owned = OwnedFileDescriptor(7, close: { fd in
                if inUse.value > 0 {
                    sawCloseWhileInUse = true
                }
                return closer.close(fd)
            })
            DispatchQueue.concurrentPerform(iterations: 16) { i in
                if i == 8 {
                    owned.close()
                    return
                }
                if i % 2 == 0, let lease = owned.lease() {
                    inUse.mutate { $0 + 1 }
                    inUse.mutate { $0 - 1 }
                    lease.release()
                } else {
                    owned.withFileDescriptor { _ in
                        inUse.mutate { $0 + 1 }
                        inUse.mutate { $0 - 1 }
                    }
                }
            }
            XCTAssertEqual(closer.closed, [7])
            XCTAssertFalse(sawCloseWhileInUse)
        }
    }
}
