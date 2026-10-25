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

    // The "last made" caches behind these must never hand back an object made for other input.
    func testURLsMadeConcurrentlyMatchTheirInput() {
        let mismatches = MutableAtomicObject(0)
        DispatchQueue.concurrentPerform(iterations: 8) { i in
            for j in 0..<2000 {
                let expected = URL(string: "https://example.com/\(i)/\(j % 3)")!
                let url = iTermURL(url: expected, identifier: "\(i)", target: nil)
                let decoded = iTermURL(data: url.data, code: 0)
                let attribute = iTermExternalAttribute(havingUnderlineColor: false,
                                                       underlineColor: VT100TerminalColorValue(),
                                                       url: url,
                                                       blockIDList: nil,
                                                       controlCode: nil,
                                                       dualModeForeground: iTermDualModeColor(),
                                                       dualModeBackground: iTermDualModeColor())
                if url.url != expected || decoded?.url != expected || attribute?.url?.url != expected {
                    mismatches.mutableAccess { $0 += 1 }
                }
            }
        }
        XCTAssertEqual(mismatches.value, 0)
    }
}
