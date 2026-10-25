//
//  SharedCounterTests.swift
//  iTerm2
//
//  Process-wide counters that sessions' mutation queues use. With a mutation queue per session they
//  are called concurrently, so every value must still be handed out once.
//

import XCTest
@testable import iTerm2SharedARC

final class SharedCounterTests: XCTestCase {
    private func assertUniqueWhenConcurrent(_ allocate: @escaping () -> Int) {
        let values = MutableAtomicObject([Int]())
        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            var mine = [Int]()
            for _ in 0..<1000 {
                mine.append(allocate())
            }
            values.mutableAccess { $0.append(contentsOf: mine) }
        }
        let all = values.access { $0 }
        XCTAssertEqual(all.count, 16_000)
        XCTAssertEqual(Set(all).count, all.count, "A value was handed out twice")
    }

    func testButtonMarkIDsAreUniqueWhenConcurrent() {
        assertUniqueWhenConcurrent { ButtonMark.generateID() }
    }

    func testKittyImageSequenceNumbersAreUniqueWhenConcurrent() {
        let counter = KittyImageController.AutoincrementingNumber()
        assertUniqueWhenConcurrent { counter.allocate() }
    }
}
