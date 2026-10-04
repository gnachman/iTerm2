//
//  FrozenMainQueueTests.swift
//  iTerm2 ModernTests
//
//  Self-tests for the FrozenMainQueue harness and the loopback transport the
//  companion link tests are built on. These pin the facts the design relies on:
//  inside a modal run loop started from a main-queue callout, the main queue and
//  the main actor are frozen, while common-mode run loop blocks and background
//  work keep running.
//

import XCTest
import os
import CompanionProtocol
@testable import iTerm2SharedARC

final class FrozenMainQueueTests: XCTestCase {
    func testMainActorAndMainQueueAreFrozenButBackgroundWorkRuns() async throws {
        let mainActorRan = OSAllocatedUnfairLock(initialState: false)
        let mainQueueRan = OSAllocatedUnfairLock(initialState: false)
        let backgroundRan = OSAllocatedUnfairLock(initialState: false)

        try await FrozenMainQueue.run { freeze in
            Task { @MainActor in mainActorRan.withLock { $0 = true } }
            DispatchQueue.main.async { mainQueueRan.withLock { $0 = true } }
            await Task.detached { backgroundRan.withLock { $0 = true } }.value
            await freeze.waitForRunLoopPasses(5)
            XCTAssertTrue(backgroundRan.withLock { $0 })
            XCTAssertFalse(mainActorRan.withLock { $0 }, "@MainActor work must not run while frozen")
            XCTAssertFalse(mainQueueRan.withLock { $0 }, "main-queue blocks must not run while frozen")
        }

        // Once the modal loop ends, the queued work runs.
        await MainActor.run {}
        try await FrozenMainQueue.withFailsafe("queued main work to run after the freeze") {
            while !(mainActorRan.withLock { $0 } && mainQueueRan.withLock { $0 }) {
                await MainActor.run {}
                await Task.yield()
            }
        }
    }

    func testCommonModeRunLoopBlockRunsOnMainThreadWhileFrozen() async throws {
        let ranOnMain = OSAllocatedUnfairLock<Bool?>(initialState: nil)
        try await FrozenMainQueue.run { _ in
            let (done, doneContinuation) = AsyncStream<Void>.makeStream()
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                ranOnMain.withLock { $0 = Thread.isMainThread }
                doneContinuation.yield()
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
            try await FrozenMainQueue.withFailsafe("a common-modes run loop block") {
                for await _ in done { break }
            }
        }
        XCTAssertEqual(ranOnMain.withLock { $0 }, true)
    }

    func testSetupRunsOnMainInsideTheCalloutBeforeTheFreeze() async throws {
        let setupRanOnMain = OSAllocatedUnfairLock(initialState: false)
        try await FrozenMainQueue.run(setup: {
            setupRanOnMain.withLock { $0 = Thread.isMainThread }
        }) { _ in
            XCTAssertTrue(setupRanOnMain.withLock { $0 })
        }
    }

    func testFailsafeTimesOutInsteadOfHanging() async {
        do {
            try await FrozenMainQueue.withFailsafe("something that never happens", seconds: 0.05) {
                await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
            }
            XCTFail("expected a timeout")
        } catch {
            XCTAssertTrue(error is FrozenMainQueue.Timeout)
        }
    }
}

final class CompanionLoopbackTransportTests: XCTestCase {
    func testFramesArriveInOrderInBothDirections() async throws {
        let (a, b) = CompanionLoopbackTransport.makePair()
        try await a.send(Data([1]))
        try await a.send(Data([2]))
        try await b.send(Data([3]))
        let first = try await b.receive()
        let second = try await b.receive()
        let third = try await a.receive()
        XCTAssertEqual(first, Data([1]))
        XCTAssertEqual(second, Data([2]))
        XCTAssertEqual(third, Data([3]))
    }

    func testReceiveWaitsForALaterSend() async throws {
        let (a, b) = CompanionLoopbackTransport.makePair()
        let received = Task { try await b.receive() }
        try await a.send(Data([9]))
        let frame = try await FrozenMainQueue.withFailsafe("the waiting receive") { try await received.value }
        XCTAssertEqual(frame, Data([9]))
    }

    func testCloseDeliversQueuedFramesThenFailsBothEnds() async throws {
        let (a, b) = CompanionLoopbackTransport.makePair()
        try await a.send(Data([1]))
        await a.close()
        let frame = try await b.receive()
        XCTAssertEqual(frame, Data([1]), "a frame queued before the close is still delivered")
        for end in [a, b] {
            do {
                _ = try await end.receive()
                XCTFail("receive after close must throw")
            } catch {}
            do {
                try await end.send(Data([2]))
                XCTFail("send after close must throw")
            } catch {}
        }
    }

    func testCloseFailsAWaitingReceive() async throws {
        let (a, b) = CompanionLoopbackTransport.makePair()
        let received = Task { try await b.receive() }
        // Closing is safe whether or not the receive has parked yet: either
        // way it must throw rather than hang.
        await a.close()
        do {
            _ = try await FrozenMainQueue.withFailsafe("the waiting receive to fail") { try await received.value }
            XCTFail("receive must throw once the transport closes")
        } catch {
            XCTAssertFalse(error is FrozenMainQueue.Timeout, "receive hung instead of failing")
        }
    }
}
