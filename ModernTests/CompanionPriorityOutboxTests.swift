//
//  CompanionPriorityOutboxTests.swift
//  iTerm2 ModernTests
//
//  The outbox must drain control ahead of media, preserve media order (no drops,
//  for the HEVC P-frame chain), and terminate on finish().
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionPriorityOutboxTests: XCTestCase {
    func testControlDrainsBeforeMedia() async {
        let outbox = CompanionPriorityOutbox<Int>()
        outbox.enqueueMedia(Data([1]))
        outbox.enqueueControl(42)
        outbox.enqueueMedia(Data([2]))

        // Control comes out first even though a media frame was enqueued earlier.
        guard case .control(let c) = await outbox.next() else { return XCTFail("expected control") }
        XCTAssertEqual(c, 42)
        guard case .media(let m1) = await outbox.next() else { return XCTFail("expected media") }
        XCTAssertEqual(m1, Data([1]))
        guard case .media(let m2) = await outbox.next() else { return XCTFail("expected media") }
        XCTAssertEqual(m2, Data([2]), "media order preserved")
    }

    func testMediaOrderPreserved() async {
        let outbox = CompanionPriorityOutbox<Int>()
        for i in 0..<5 { outbox.enqueueMedia(Data([UInt8(i)])) }
        for i in 0..<5 {
            guard case .media(let d) = await outbox.next() else { return XCTFail("expected media") }
            XCTAssertEqual(d, Data([UInt8(i)]))
        }
    }

    func testFinishedAfterDrain() async {
        let outbox = CompanionPriorityOutbox<Int>()
        outbox.enqueueControl(1)
        outbox.finish()
        guard case .control = await outbox.next() else { return XCTFail("expected control") }
        // Everything drained: next must report finished.
        guard case .finished = await outbox.next() else { return XCTFail("expected finished") }
    }

    func testAwaitsThenWakesOnEnqueue() async {
        let outbox = CompanionPriorityOutbox<Int>()
        // Consumer parks first; a later enqueue must wake it.
        let task = Task { () -> Int in
            guard case .control(let c) = await outbox.next() else { return -1 }
            return c
        }
        // Give the consumer a moment to park, then enqueue.
        await Task.yield()
        outbox.enqueueControl(7)
        let value = await task.value
        XCTAssertEqual(value, 7)
    }
}
