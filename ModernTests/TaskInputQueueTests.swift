//
//  TaskInputQueueTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

final class TaskInputQueueTests: XCTestCase {
    // Reads up to `maxLength` bytes. Returns what was read and whether the queue reported its end.
    private func read(_ queue: TaskInputQueue, maxLength: Int) -> (Data, Bool) {
        var buffer = [UInt8](repeating: 0, count: maxLength)
        var endOfFile = ObjCBool(false)
        let count = buffer.withUnsafeMutableBytes { pointer in
            queue.read(into: pointer.baseAddress!, maxLength: maxLength, endOfFile: &endOfFile)
        }
        return (Data(buffer[0..<count]), endOfFile.boolValue)
    }

    func testReadsReturnAppendedBytesInOrder() {
        let queue = TaskInputQueue()
        queue.append(Data("abc".utf8))
        queue.append(Data("defg".utf8))

        var (data, endOfFile) = read(queue, maxLength: 2)
        XCTAssertEqual(data, Data("ab".utf8))
        XCTAssertFalse(endOfFile)
        // A read can span appends.
        (data, endOfFile) = read(queue, maxLength: 3)
        XCTAssertEqual(data, Data("cde".utf8))
        XCTAssertFalse(endOfFile)
        (data, endOfFile) = read(queue, maxLength: 100)
        XCTAssertEqual(data, Data("fg".utf8))
        XCTAssertFalse(endOfFile)
        XCTAssertFalse(queue.isReadable)
    }

    func testReadingAnEmptyQueueReturnsNothing() {
        let queue = TaskInputQueue()
        let (data, endOfFile) = read(queue, maxLength: 10)
        XCTAssertEqual(data, Data())
        XCTAssertFalse(endOfFile)
    }

    func testEmptyAppendIsIgnored() {
        let queue = TaskInputQueue()
        var calls = 0
        _ = queue.addReadabilityHandler {
            calls += 1
        }
        queue.append(Data())
        XCTAssertFalse(queue.isReadable)
        XCTAssertEqual(calls, 0)
    }

    // Closing a pane's queue discards what its task has not read. A task that reads it after that
    // sees the end of its input.
    func testCloseDiscardsUnreadBytesAndEndsInput() {
        let queue = TaskInputQueue()
        queue.append(Data("abc".utf8))
        queue.close()
        XCTAssertTrue(queue.isClosed)
        // Readable, so a reader finds out that it ended.
        XCTAssertTrue(queue.isReadable)

        let (data, endOfFile) = read(queue, maxLength: 10)
        XCTAssertEqual(data, Data())
        XCTAssertTrue(endOfFile)
    }

    func testAppendAfterCloseIsIgnored() {
        let queue = TaskInputQueue()
        queue.close()
        queue.append(Data("abc".utf8))
        let (data, endOfFile) = read(queue, maxLength: 10)
        XCTAssertEqual(data, Data())
        XCTAssertTrue(endOfFile)
    }

    func testReadabilityHandlerIsCalledOnAppendAndClose() {
        let queue = TaskInputQueue()
        var calls = 0
        let token = queue.addReadabilityHandler {
            calls += 1
        }
        queue.append(Data("a".utf8))
        XCTAssertEqual(calls, 1)
        queue.append(Data("b".utf8))
        XCTAssertEqual(calls, 2)
        queue.close()
        XCTAssertEqual(calls, 3)
        // Closing again changes nothing.
        queue.close()
        XCTAssertEqual(calls, 3)
        withExtendedLifetime(token) {}
    }

    func testRemovedHandlerIsNotCalled() {
        let queue = TaskInputQueue()
        var calls = 0
        let token = queue.addReadabilityHandler {
            calls += 1
        }
        queue.removeReadabilityHandler(token)
        queue.append(Data("a".utf8))
        queue.close()
        XCTAssertEqual(calls, 0)
    }

    // Many small chunks, read a few bytes at a time, come out whole and in order.
    func testManySmallChunks() {
        let queue = TaskInputQueue()
        var expected = Data()
        for i in 0..<1000 {
            let chunk = Data([UInt8(i & 0xff), UInt8((i >> 8) & 0xff), 0x2a])
            expected.append(chunk)
            queue.append(chunk)
        }
        var actual = Data()
        while queue.isReadable {
            let (data, endOfFile) = read(queue, maxLength: 7)
            XCTAssertFalse(endOfFile)
            actual.append(data)
        }
        XCTAssertEqual(actual, expected)
    }

    // Removing one reader's handler leaves another's.
    func testRemovingAHandlerKeepsOthers() {
        let queue = TaskInputQueue()
        var first = 0
        var second = 0
        let token = queue.addReadabilityHandler {
            first += 1
        }
        _ = queue.addReadabilityHandler {
            second += 1
        }
        queue.removeReadabilityHandler(token)
        queue.append(Data("a".utf8))
        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 1)
    }

    // The handler may use the queue, since it is called without the queue's lock held.
    func testReadabilityHandlerCanUseTheQueue() {
        let queue = TaskInputQueue()
        var reentered = false
        _ = queue.addReadabilityHandler { [unowned queue] in
            guard !reentered else {
                return
            }
            reentered = true
            queue.append(Data("b".utf8))
        }
        queue.append(Data("a".utf8))
        let (data, _) = read(queue, maxLength: 10)
        XCTAssertEqual(data, Data("ab".utf8))
    }

    // MARK: Budget

    // Unread bytes count against the budget from when they are appended until they are read.
    func testUnreadBytesCountAgainstTheBudget() {
        let budget = ByteBudget(capacity: 100)
        let queue = TaskInputQueue()
        queue.budget = budget
        queue.append(Data("abcde".utf8))
        XCTAssertEqual(budget.inUse, 5)

        _ = read(queue, maxLength: 2)
        XCTAssertEqual(budget.inUse, 3)
        _ = read(queue, maxLength: 10)
        XCTAssertEqual(budget.inUse, 0)
    }

    // Closing discards unread bytes, so they no longer count.
    func testClosingGivesBackUnreadBytes() {
        let budget = ByteBudget(capacity: 100)
        let queue = TaskInputQueue()
        queue.budget = budget
        queue.append(Data("abcde".utf8))
        queue.close()
        XCTAssertEqual(budget.inUse, 0)
        queue.append(Data("fgh".utf8))
        XCTAssertEqual(budget.inUse, 0)
    }

    // A pane's session may learn its gateway's budget after output has been queued, and may later
    // have none. Unread bytes move with the change.
    func testChangingTheBudgetMovesUnreadBytes() {
        let first = ByteBudget(capacity: 100)
        let second = ByteBudget(capacity: 100)
        let queue = TaskInputQueue()
        queue.append(Data("ab".utf8))
        queue.budget = first
        XCTAssertEqual(first.inUse, 2)

        queue.append(Data("cde".utf8))
        queue.budget = second
        XCTAssertEqual(first.inUse, 0)
        XCTAssertEqual(second.inUse, 5)

        queue.budget = nil
        XCTAssertEqual(second.inUse, 0)
        _ = read(queue, maxLength: 10)
        XCTAssertEqual(second.inUse, 0)
    }

    func testClosingAfterChangingTheBudgetLeavesNothingCounted() {
        let first = ByteBudget(capacity: 100)
        let second = ByteBudget(capacity: 100)
        let queue = TaskInputQueue()
        queue.budget = first
        queue.append(Data("abc".utf8))
        queue.budget = second
        _ = read(queue, maxLength: 1)
        queue.close()
        XCTAssertEqual(first.inUse, 0)
        XCTAssertEqual(second.inUse, 0)
    }

    // However appends and reads interleave, nothing stays counted once the queue is closed.
    func testConcurrentUseLeavesNothingCounted() {
        let budget = ByteBudget(capacity: 1000)
        let queue = TaskInputQueue()
        queue.budget = budget
        let group = DispatchGroup()
        for i in 0..<4 {
            DispatchQueue.global().async(group: group) {
                for j in 0..<500 {
                    queue.append(Data(repeating: UInt8(i), count: 1 + j % 7))
                }
            }
        }
        DispatchQueue.global().async(group: group) {
            for _ in 0..<2000 {
                _ = self.read(queue, maxLength: 5)
            }
        }
        group.wait()
        queue.close()
        XCTAssertEqual(budget.inUse, 0)
    }
}
