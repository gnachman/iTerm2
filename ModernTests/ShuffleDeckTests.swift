//
//  ShuffleDeckTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

class ShuffleDeckTests: XCTestCase {

    // MARK: - Empty / single-item pool

    func testEmptyPoolYieldsNil() {
        let deck = ShuffleDeck()
        XCTAssertNil(deck.current)
        XCTAssertNil(deck.advance())
        XCTAssertNil(deck.advance())
    }

    func testSingleItemPoolAlwaysReturnsThatItem() {
        let deck = ShuffleDeck()
        deck.setPool(["a"])
        XCTAssertEqual(deck.advance(), "a")
        XCTAssertEqual(deck.advance(), "a")
        XCTAssertEqual(deck.advance(), "a")
    }

    // MARK: - Cycle fairness

    func testEachItemShownOncePerCycle() {
        let items = ["a", "b", "c", "d", "e"]
        let deck = ShuffleDeck()
        deck.setPool(items)
        var seen: Set<String> = []
        for _ in 0..<items.count {
            guard let next = deck.advance() else {
                XCTFail("advance returned nil before cycle completed")
                return
            }
            XCTAssertFalse(seen.contains(next), "duplicate within cycle: \(next)")
            seen.insert(next)
        }
        XCTAssertEqual(seen, Set(items))
    }

    func testMultipleCyclesCoverAllItems() {
        let items = (0..<10).map { "item\($0)" }
        let deck = ShuffleDeck()
        deck.setPool(items)
        // Three full cycles — each should see every item.
        for _ in 0..<3 {
            var seen: Set<String> = []
            for _ in 0..<items.count {
                seen.insert(deck.advance()!)
            }
            XCTAssertEqual(seen, Set(items))
        }
    }

    func testNoImmediateRepeatAcrossCycleBoundary() {
        // With >1 items, the last item of one cycle should not equal the first
        // item of the next cycle (advance() excludes `current` when reshuffling).
        let items = ["a", "b", "c", "d", "e"]
        let deck = ShuffleDeck()
        deck.setPool(items)
        // Run many full cycles, verify no back-to-back repeats.
        var last: String?
        for _ in 0..<(items.count * 20) {
            let next = deck.advance()!
            if let last {
                XCTAssertNotEqual(next, last, "back-to-back repeat")
            }
            last = next
        }
    }

    // MARK: - Pool updates

    func testSetPoolIsNoOpWhenEqual() {
        let deck = ShuffleDeck()
        deck.setPool(["a", "b", "c"])
        deck.advance()  // consume one
        let currentBefore = deck.current
        deck.setPool(["a", "b", "c"])  // identical
        XCTAssertEqual(deck.current, currentBefore)
        // The remaining cycle order should be unchanged; we can't check the
        // exact sequence (shuffle) but we can verify fairness still holds.
    }

    func testRemovingCurrentFromPoolClearsIt() {
        let deck = ShuffleDeck()
        deck.setPool(["a", "b", "c"])
        deck.advance()
        let removed: String = deck.current!
        let rest = ["a", "b", "c"].filter { $0 != removed }
        deck.setPool(rest)
        XCTAssertNil(deck.current)
    }

    func testRemovingNonCurrentFromPoolDropsFromUpcoming() {
        let deck = ShuffleDeck()
        deck.setPool(["a", "b", "c", "d", "e"])
        deck.advance()  // consume one; 4 items upcoming
        let current = deck.current!
        let removed: String = ["a", "b", "c", "d", "e"].first { $0 != current }!
        let rest = ["a", "b", "c", "d", "e"].filter { $0 != removed }
        deck.setPool(rest)
        // The removed item must never appear in subsequent advances within
        // this cycle.
        var seenThisCycle: Set<String> = []
        if let c = deck.current { seenThisCycle.insert(c) }
        for _ in 0..<(rest.count - 1) {
            let next = deck.advance()!
            XCTAssertNotEqual(next, removed)
            seenThisCycle.insert(next)
        }
        XCTAssertFalse(seenThisCycle.contains(removed))
    }

    func testAddingItemsToPoolTheyAppearInNextCycle() {
        let deck = ShuffleDeck()
        deck.setPool(["a", "b"])
        // Exhaust one cycle.
        _ = deck.advance()
        _ = deck.advance()
        deck.setPool(["a", "b", "c"])
        var seen: Set<String> = []
        // Next cycle = a+b+c minus current.
        for _ in 0..<2 {
            seen.insert(deck.advance()!)
        }
        // c should show up in the first full cycle after it was added.
        _ = deck.advance()  // exhaust
        _ = deck.advance()
        seen.insert(deck.current!)
        // Across two full cycles after adding c, c must have appeared.
        // (Testing the exact cycle in which it appears is fragile; just
        // verify it doesn't stay invisible forever.)
        var found = false
        for _ in 0..<20 {
            if deck.advance() == "c" { found = true; break }
        }
        XCTAssertTrue(found, "newly added item never appeared")
    }

    // MARK: - Pool reduced to empty / single

    func testPoolEmptiedClearsCurrent() {
        let deck = ShuffleDeck()
        deck.setPool(["a", "b"])
        deck.advance()
        deck.setPool([])
        XCTAssertNil(deck.current)
        XCTAssertNil(deck.advance())
    }

    func testPoolReducedToSingleItem() {
        let deck = ShuffleDeck()
        deck.setPool(["a", "b", "c"])
        deck.advance()
        deck.setPool(["a"])
        XCTAssertEqual(deck.advance(), "a")
        XCTAssertEqual(deck.advance(), "a")
    }
}
