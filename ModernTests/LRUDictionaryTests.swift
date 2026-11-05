//
//  LRUDictionaryTests.swift
//  iTerm2
//
//  Created by George Nachman on 11/4/26.
//

import XCTest
@testable import iTerm2SharedARC

final class LRUDictionaryTests: XCTestCase {
    func testReadingKeepsAnEntryFromEviction() {
        var dict = LRUDictionary<String, Int>(maximumSize: 2)
        _ = dict.insert(key: "a", value: 1, cost: 1)
        _ = dict.insert(key: "b", value: 2, cost: 1)
        XCTAssertEqual(dict["a"], 1)
        let evicted = dict.insert(key: "c", value: 3, cost: 1)
        XCTAssertEqual(evicted.map { $0.0 }, ["b"], "b was used least recently")
        XCTAssertEqual(dict.peek("a"), 1)
        XCTAssertNil(dict.peek("b"))
        XCTAssertEqual(dict.peek("c"), 3)
    }

    func testPeekDoesNotCountAsAUse() {
        var dict = LRUDictionary<String, Int>(maximumSize: 2)
        _ = dict.insert(key: "a", value: 1, cost: 1)
        _ = dict.insert(key: "b", value: 2, cost: 1)
        XCTAssertEqual(dict.peek("a"), 1)
        let evicted = dict.insert(key: "c", value: 3, cost: 1)
        XCTAssertEqual(evicted.map { $0.0 }, ["a"], "a was inserted first and never used")
    }

    func testReadingAMissingKeyIsNil() {
        let dict = LRUDictionary<String, Int>(maximumSize: 2)
        XCTAssertNil(dict["a"])
        XCTAssertNil(dict.peek("a"))
    }

    // The ObjC wrapper's lookup is a use too.
    func testUntypedLookupCountsAsAUse() {
        let dict = UntypedLRUDictionary(maximumSize: 2)
        dict.insert(key: "a", value: 1, cost: 1)
        dict.insert(key: "b", value: 2, cost: 1)
        XCTAssertEqual(dict.object(forKey: "a") as? Int, 1)
        dict.insert(key: "c", value: 3, cost: 1)
        XCTAssertEqual(dict.object(forKey: "a") as? Int, 1)
        XCTAssertNil(dict.object(forKey: "b"), "b was used least recently")
    }
}
