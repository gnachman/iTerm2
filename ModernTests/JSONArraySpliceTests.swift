//
//  JSONArraySpliceTests.swift
//  iTerm2 ModernTests
//
//  The verbatim byte-level array splice the blob send path uses to drop a chat's
//  frozen history into a request body a vendor builder produced, without
//  re-serializing. Pure bytes in, pure bytes out, so it is tested exactly:
//  position (start / middle / end / empty), multi-element inserts, verbatim
//  preservation of everything else, and string/depth awareness so commas and
//  brackets INSIDE string values or nested structures are never miscounted as
//  element boundaries.
//

import XCTest
@testable import iTerm2SharedARC

final class JSONArraySpliceTests: XCTestCase {

    private func splice(_ object: String, insert inner: String, key: String = "messages", after: Int) -> String? {
        JSONArraySplice.insert(Data(inner.utf8), intoArrayKey: key, of: Data(object.utf8), afterCount: after)
            .map { String(decoding: $0, as: UTF8.self) }
    }

    func test_insertAtStart() {
        XCTAssertEqual(splice(#"{"messages":[{"a":1},{"b":2}]}"#, insert: #"{"h":9}"#, after: 0),
                       #"{"messages":[{"h":9},{"a":1},{"b":2}]}"#)
    }

    func test_insertAfterFirst() {
        XCTAssertEqual(splice(#"{"messages":[{"a":1},{"b":2}]}"#, insert: #"{"h":9}"#, after: 1),
                       #"{"messages":[{"a":1},{"h":9},{"b":2}]}"#)
    }

    func test_insertAtEnd() {
        XCTAssertEqual(splice(#"{"messages":[{"a":1},{"b":2}]}"#, insert: #"{"h":9}"#, after: 2),
                       #"{"messages":[{"a":1},{"b":2},{"h":9}]}"#)
    }

    func test_insertIntoEmptyArray() {
        XCTAssertEqual(splice(#"{"messages":[]}"#, insert: #"{"h":9}"#, after: 0),
                       #"{"messages":[{"h":9}]}"#)
    }

    func test_insertMultipleElements() {
        XCTAssertEqual(splice(#"{"messages":[{"a":1}]}"#, insert: #"{"h":9},{"i":8}"#, after: 1),
                       #"{"messages":[{"a":1},{"h":9},{"i":8}]}"#)
    }

    /// Everything outside the target array must be preserved byte-for-byte, and the
    /// target key must be found among sibling keys.
    func test_preservesOtherKeysVerbatim() {
        XCTAssertEqual(
            splice(#"{"model":"m","messages":[{"a":1}],"max_tokens":5,"stream":false}"#,
                   insert: #"{"h":9}"#, after: 1),
            #"{"model":"m","messages":[{"a":1},{"h":9}],"max_tokens":5,"stream":false}"#)
    }

    /// Commas and brackets INSIDE a string value must not be counted as element
    /// boundaries, and escaped quotes must not end the string early.
    func test_stringAwareness_commasBracketsAndEscapesInValues() {
        let object = #"{"messages":[{"t":"a,b],[c and say \"hi\", ok"}]}"#
        XCTAssertEqual(splice(object, insert: #"{"h":9}"#, after: 1),
                       #"{"messages":[{"t":"a,b],[c and say \"hi\", ok"},{"h":9}]}"#)
    }

    /// Nested objects/arrays within an element must not have their inner commas
    /// counted as top-level boundaries.
    func test_depthAwareness_nestedStructures() {
        let object = #"{"messages":[{"content":[{"x":1},{"y":2}],"role":"user"},{"b":2}]}"#
        XCTAssertEqual(splice(object, insert: #"{"h":9}"#, after: 1),
                       #"{"messages":[{"content":[{"x":1},{"y":2}],"role":"user"},{"h":9},{"b":2}]}"#)
    }

    /// afterCount beyond the number of elements appends at the end (never drops or
    /// duplicates content).
    func test_afterCountBeyondElements_appendsAtEnd() {
        XCTAssertEqual(splice(#"{"messages":[{"a":1}]}"#, insert: #"{"h":9}"#, after: 5),
                       #"{"messages":[{"a":1},{"h":9}]}"#)
    }

    func test_emptyInner_returnsObjectUnchanged() {
        let object = #"{"messages":[{"a":1}]}"#
        XCTAssertEqual(JSONArraySplice.insert(Data(), intoArrayKey: "messages", of: Data(object.utf8), afterCount: 1),
                       Data(object.utf8))
    }

    func test_keyNotFound_returnsNil() {
        XCTAssertNil(splice(#"{"messages":[{"a":1}]}"#, insert: #"{"h":9}"#, key: "input", after: 0))
    }

    func test_worksForAnyArrayKey() {
        XCTAssertEqual(splice(#"{"contents":[{"a":1}]}"#, insert: #"{"h":9}"#, key: "contents", after: 0),
                       #"{"contents":[{"h":9},{"a":1}]}"#)
    }
}
