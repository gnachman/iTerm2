//
//  WatermarkStoreTests.swift
//  CompanionCore
//
//  The per-chat watermark's merge contract: monotonic (never lowers), keyed
//  independently per collapse token, missing -> first run, and order-independent
//  so concurrent advances converge on the max.
//

import XCTest
@testable import CompanionProtocol

private final class MemoryBacking: WatermarkBacking {
    var store: [String: Int64] = [:]
    func watermarkValue(forKey key: String) -> Int64? { store[key] }
    func setWatermarkValue(_ value: Int64, forKey key: String) { store[key] = value }
    func removeWatermarks(matchingPrefix prefix: String) {
        for key in store.keys where key.hasPrefix(prefix) { store[key] = nil }
    }
}

final class WatermarkStoreTests: XCTestCase {
    func testMissingIsNilOnFirstRun() {
        let store = WatermarkStore(backing: MemoryBacking())
        XCTAssertNil(store.watermark(forToken: "t"))
    }

    func testAdvanceSetsAndReads() {
        let store = WatermarkStore(backing: MemoryBacking())
        XCTAssertEqual(store.advance(token: "t", to: 42), 42)
        XCTAssertEqual(store.watermark(forToken: "t"), 42)
    }

    func testAdvanceNeverLowers() {
        let store = WatermarkStore(backing: MemoryBacking())
        store.advance(token: "t", to: 10)
        XCTAssertEqual(store.advance(token: "t", to: 5), 10, "a lower candidate must not lower the watermark")
        XCTAssertEqual(store.watermark(forToken: "t"), 10)
        XCTAssertEqual(store.advance(token: "t", to: 10), 10, "equal candidate is a no-op")
        XCTAssertEqual(store.advance(token: "t", to: 20), 20, "higher candidate advances")
        XCTAssertEqual(store.watermark(forToken: "t"), 20)
    }

    func testOrderIndependentConvergence() {
        let a = WatermarkStore(backing: MemoryBacking())
        a.advance(token: "t", to: 7)
        a.advance(token: "t", to: 5)
        let b = WatermarkStore(backing: MemoryBacking())
        b.advance(token: "t", to: 5)
        b.advance(token: "t", to: 7)
        XCTAssertEqual(a.watermark(forToken: "t"), 7)
        XCTAssertEqual(b.watermark(forToken: "t"), 7)
    }

    func testPerTokenIndependence() {
        let store = WatermarkStore(backing: MemoryBacking())
        store.advance(token: "a", to: 3)
        store.advance(token: "b", to: 9)
        XCTAssertEqual(store.watermark(forToken: "a"), 3)
        XCTAssertEqual(store.watermark(forToken: "b"), 9)
    }

    func testResetWipesAll() {
        let backing = MemoryBacking()
        backing.store["unrelated"] = 1   // not a watermark key; must survive
        let store = WatermarkStore(backing: backing)
        store.advance(token: "a", to: 3)
        store.advance(token: "b", to: 9)
        store.reset()
        XCTAssertNil(store.watermark(forToken: "a"))
        XCTAssertNil(store.watermark(forToken: "b"))
        XCTAssertEqual(backing.store["unrelated"], 1)
    }
}
