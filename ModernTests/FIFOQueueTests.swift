//
//  FIFOQueueTests.swift
//  iTerm2
//
//  Created by George Nachman on 2025.
//

import XCTest
@testable import iTerm2SharedARC

class FIFOQueueTests: XCTestCase {

    // MARK: - Basic Operations

    func testEmptyQueue() {
        let queue = FIFOQueue<Int>()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.count, 0)
        XCTAssertNil(queue.first)
    }

    func testEnqueueSingleElement() {
        var queue = FIFOQueue<Int>()
        queue.enqueue(42)

        XCTAssertFalse(queue.isEmpty)
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.first, 42)
    }

    func testEnqueueMultipleElements() {
        var queue = FIFOQueue<Int>()
        queue.enqueue(1)
        queue.enqueue(2)
        queue.enqueue(3)

        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue.first, 1)
    }

    func testDequeueSingleElement() {
        var queue = FIFOQueue<Int>()
        queue.enqueue(42)

        let element = queue.dequeue()

        XCTAssertEqual(element, 42)
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.count, 0)
    }

    func testDequeueFromEmptyQueue() {
        var queue = FIFOQueue<Int>()

        let element = queue.dequeue()

        XCTAssertNil(element)
    }

    func testFIFOOrder() {
        var queue = FIFOQueue<Int>()
        queue.enqueue(1)
        queue.enqueue(2)
        queue.enqueue(3)

        XCTAssertEqual(queue.dequeue(), 1)
        XCTAssertEqual(queue.dequeue(), 2)
        XCTAssertEqual(queue.dequeue(), 3)
        XCTAssertNil(queue.dequeue())
    }

    func testInterleavedEnqueueDequeue() {
        var queue = FIFOQueue<String>()

        queue.enqueue("a")
        queue.enqueue("b")
        XCTAssertEqual(queue.dequeue(), "a")

        queue.enqueue("c")
        XCTAssertEqual(queue.dequeue(), "b")
        XCTAssertEqual(queue.dequeue(), "c")

        queue.enqueue("d")
        XCTAssertEqual(queue.dequeue(), "d")
        XCTAssertTrue(queue.isEmpty)
    }

    func testRemoveAll() {
        var queue = FIFOQueue<Int>()
        queue.enqueue(1)
        queue.enqueue(2)
        queue.enqueue(3)

        queue.removeAll()

        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.count, 0)
        XCTAssertNil(queue.dequeue())
    }

    // MARK: - Sequence Conformance

    func testIteration() {
        var queue = FIFOQueue<Int>()
        queue.enqueue(1)
        queue.enqueue(2)
        queue.enqueue(3)

        var result: [Int] = []
        for element in queue {
            result.append(element)
        }

        XCTAssertEqual(result, [1, 2, 3])
        // Iteration should not modify the queue
        XCTAssertEqual(queue.count, 3)
    }

    func testIterationAfterDequeue() {
        var queue = FIFOQueue<Int>()
        queue.enqueue(1)
        queue.enqueue(2)
        queue.enqueue(3)
        _ = queue.dequeue() // Remove 1

        var result: [Int] = []
        for element in queue {
            result.append(element)
        }

        XCTAssertEqual(result, [2, 3])
    }

    func testMapFilter() {
        var queue = FIFOQueue<Int>()
        queue.enqueue(1)
        queue.enqueue(2)
        queue.enqueue(3)
        queue.enqueue(4)

        let doubled = queue.map { $0 * 2 }
        let evens = queue.filter { $0 % 2 == 0 }

        XCTAssertEqual(doubled, [2, 4, 6, 8])
        XCTAssertEqual(evens, [2, 4])
    }

    func testReduce() {
        var queue = FIFOQueue<Int>()
        queue.enqueue(1)
        queue.enqueue(2)
        queue.enqueue(3)

        let sum = queue.reduce(0, +)

        XCTAssertEqual(sum, 6)
    }

    func testContains() {
        var queue = FIFOQueue<String>()
        queue.enqueue("apple")
        queue.enqueue("banana")

        XCTAssertTrue(queue.contains("apple"))
        XCTAssertTrue(queue.contains("banana"))
        XCTAssertFalse(queue.contains("cherry"))
    }

    // MARK: - ExpressibleByArrayLiteral

    func testArrayLiteralInitialization() {
        let queue: FIFOQueue<Int> = [1, 2, 3]

        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(Array(queue), [1, 2, 3])
    }

    func testEmptyArrayLiteral() {
        let queue: FIFOQueue<Int> = []

        XCTAssertTrue(queue.isEmpty)
    }

    // MARK: - Equatable

    func testEquality() {
        var queue1 = FIFOQueue<Int>()
        queue1.enqueue(1)
        queue1.enqueue(2)

        var queue2 = FIFOQueue<Int>()
        queue2.enqueue(1)
        queue2.enqueue(2)

        XCTAssertEqual(queue1, queue2)
    }

    func testInequalityDifferentElements() {
        var queue1 = FIFOQueue<Int>()
        queue1.enqueue(1)
        queue1.enqueue(2)

        var queue2 = FIFOQueue<Int>()
        queue2.enqueue(1)
        queue2.enqueue(3)

        XCTAssertNotEqual(queue1, queue2)
    }

    func testInequalityDifferentCounts() {
        var queue1 = FIFOQueue<Int>()
        queue1.enqueue(1)

        var queue2 = FIFOQueue<Int>()
        queue2.enqueue(1)
        queue2.enqueue(2)

        XCTAssertNotEqual(queue1, queue2)
    }

    func testEqualityAfterDequeue() {
        var queue1 = FIFOQueue<Int>()
        queue1.enqueue(1)
        queue1.enqueue(2)
        queue1.enqueue(3)
        _ = queue1.dequeue() // Remove 1

        var queue2 = FIFOQueue<Int>()
        queue2.enqueue(2)
        queue2.enqueue(3)

        XCTAssertEqual(queue1, queue2)
    }

    // MARK: - Memory Compaction

    func testCompactionOccurs() {
        var queue = FIFOQueue<Int>()

        // Enqueue many elements
        for i in 0..<200 {
            queue.enqueue(i)
        }

        // Dequeue most of them (should trigger compaction)
        for _ in 0..<150 {
            _ = queue.dequeue()
        }

        // Queue should still work correctly
        XCTAssertEqual(queue.count, 50)
        XCTAssertEqual(queue.dequeue(), 150)
        XCTAssertEqual(queue.dequeue(), 151)
    }

    func testLargeNumberOfOperations() {
        var queue = FIFOQueue<Int>()

        // Stress test: enqueue many, dequeue some, verify FIFO order
        for i in 0..<10000 {
            queue.enqueue(i)
        }

        // Dequeue half
        for _ in 0..<5000 {
            _ = queue.dequeue()
        }

        // Remaining should be 5000..9999 in order
        XCTAssertEqual(queue.count, 5000)

        for expected in 5000..<10000 {
            XCTAssertEqual(queue.dequeue(), expected)
        }

        XCTAssertTrue(queue.isEmpty)
    }

    // MARK: - Type Flexibility

    func testWithCustomType() {
        struct Point: Equatable {
            let x: Int
            let y: Int
        }

        var queue = FIFOQueue<Point>()
        queue.enqueue(Point(x: 1, y: 2))
        queue.enqueue(Point(x: 3, y: 4))

        XCTAssertEqual(queue.dequeue(), Point(x: 1, y: 2))
        XCTAssertEqual(queue.dequeue(), Point(x: 3, y: 4))
    }

    func testWithOptionalType() {
        var queue = FIFOQueue<Int?>()
        queue.enqueue(1)
        queue.enqueue(nil)
        queue.enqueue(3)

        XCTAssertEqual(queue.dequeue(), .some(1))
        XCTAssertEqual(queue.dequeue(), .some(nil))
        XCTAssertEqual(queue.dequeue(), .some(3))
        XCTAssertNil(queue.dequeue() as Any?)
    }

    // MARK: - Description

    func testDescription() {
        var queue = FIFOQueue<Int>()
        queue.enqueue(1)
        queue.enqueue(2)

        let description = queue.description

        XCTAssertTrue(description.contains("FIFOQueue"))
        XCTAssertTrue(description.contains("1"))
        XCTAssertTrue(description.contains("2"))
    }
}
