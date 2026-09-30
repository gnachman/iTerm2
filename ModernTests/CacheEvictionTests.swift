//
//  CacheEvictionTests.swift
//  iTerm2
//
//  Ported from the legacy iTermCacheTests.m. Exercises iTermCache's LRU
//  behavior (the leak test lives in ModernTests/iTermCacheTests.m).
//

import XCTest
@testable import iTerm2SharedARC

final class CacheEvictionTests: XCTestCase {
    private typealias Cache = iTermCache<NSString, NSNumber>

    private func makeCache(capacity: Int = 3) -> Cache {
        return Cache(capacity: capacity)
    }

    // The ObjC keyed subscript imports with an NSCopying key, so these helpers
    // keep the tests readable with plain string keys.
    private func set(_ cache: Cache, _ key: String, _ value: Int) {
        cache[key as NSString] = NSNumber(value: value)
    }

    private func get(_ cache: Cache, _ key: String) -> NSNumber? {
        return cache[key as NSString]
    }

    func testInsertedValuesCanBeRead() {
        let cache = makeCache()
        set(cache, "one", 1)
        set(cache, "two", 2)

        XCTAssertEqual(get(cache, "one"), 1)
        XCTAssertEqual(get(cache, "two"), 2)
    }

    func testExceedingCapacityEvictsLeastRecentlyInserted() {
        let cache = makeCache()
        set(cache, "one", 1)
        set(cache, "two", 2)
        set(cache, "three", 3)
        set(cache, "four", 4)

        XCTAssertNil(get(cache, "one"))
        XCTAssertEqual(get(cache, "two"), 2)
        XCTAssertEqual(get(cache, "three"), 3)
        XCTAssertEqual(get(cache, "four"), 4)
    }

    func testReadingPromotesEntryToMostRecentlyUsed() {
        let cache = makeCache()
        set(cache, "one", 1)
        set(cache, "two", 2)
        set(cache, "three", 3)

        // Promote one to MRU.
        XCTAssertEqual(get(cache, "one"), 1)

        // This should evict two, the LRU.
        set(cache, "four", 4)

        XCTAssertNil(get(cache, "two"))
        XCTAssertEqual(get(cache, "four"), 4)
        XCTAssertEqual(get(cache, "three"), 3)
        XCTAssertEqual(get(cache, "one"), 1)
    }

    func testReadingNeverAddedKeyReturnsNil() {
        let cache = makeCache()
        set(cache, "one", 1)
        XCTAssertNil(get(cache, "bogus"))
    }

    func testModifyingExistingKeyReplacesValueWithoutEvicting() {
        let cache = makeCache()
        set(cache, "one", 1)
        set(cache, "two", 2)
        set(cache, "three", 3)
        set(cache, "four", 4)

        set(cache, "three", 33)
        XCTAssertEqual(get(cache, "four"), 4)
        XCTAssertEqual(get(cache, "three"), 33)
        XCTAssertEqual(get(cache, "two"), 2)
    }
}
