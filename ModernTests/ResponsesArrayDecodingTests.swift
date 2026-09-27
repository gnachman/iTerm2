//
//  ResponsesArrayDecodingTests.swift
//  iTerm2 ModernTests
//
//  Guards the [Any] JSON-decoding helper in ResponsesAPIResponse against a
//  stack-overflow that shipped: an array element of JSON `null` matched none
//  of the type branches, never advanced the unkeyed container, and drove the
//  nested-array branch to re-enter the same decode on the same container
//  until the stack overflowed. A live OpenAI response with a null inside an
//  array crashed the parser. These decode null-bearing arrays directly.
//

import XCTest
@testable import iTerm2SharedARC

final class ResponsesArrayDecodingTests: XCTestCase {

    // Decodes { "arr": [...] } through the KeyedDecodingContainer/[Any]
    // extension under test.
    private struct ArrayHolder: Decodable {
        let values: [Any]
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: JSONCodingKeys.self)
            values = try container.decode([Any].self,
                                          forKey: JSONCodingKeys(stringValue: "arr")!)
        }
    }

    private func decodeArray(_ json: String) throws -> [Any] {
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(ArrayHolder.self, from: data).values
    }

    func test_nullInsideArray_doesNotCrashAndIsPreserved() throws {
        // Pre-fix this input recursed forever on the null and overflowed.
        let values = try decodeArray(#"{"arr": [1, null, "x", true]}"#)
        XCTAssertEqual(values.count, 4)
        XCTAssertEqual(values[0] as? Int, 1)
        XCTAssertTrue(values[1] is NSNull)
        XCTAssertEqual(values[2] as? String, "x")
        XCTAssertEqual(values[3] as? Bool, true)
    }

    func test_nestedArraysAndObjectsWithNulls() throws {
        let values = try decodeArray(#"{"arr": [[2, null], {"k": 1}, null]}"#)
        XCTAssertEqual(values.count, 3)
        let nested = try XCTUnwrap(values[0] as? [Any])
        XCTAssertEqual(nested.count, 2)
        XCTAssertEqual(nested[0] as? Int, 2)
        XCTAssertTrue(nested[1] is NSNull)
        let dict = try XCTUnwrap(values[1] as? [String: Any])
        XCTAssertEqual(dict["k"] as? Int, 1)
        XCTAssertTrue(values[2] is NSNull)
    }

    func test_leadingAndTrailingNulls() throws {
        let values = try decodeArray(#"{"arr": [null, null, "a", null]}"#)
        XCTAssertEqual(values.count, 4)
        XCTAssertTrue(values[0] is NSNull)
        XCTAssertTrue(values[1] is NSNull)
        XCTAssertEqual(values[2] as? String, "a")
        XCTAssertTrue(values[3] is NSNull)
    }

    func test_emptyArray() throws {
        let values = try decodeArray(#"{"arr": []}"#)
        XCTAssertTrue(values.isEmpty)
    }
}
