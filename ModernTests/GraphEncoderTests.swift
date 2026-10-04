//
//  GraphEncoderTests.swift
//  ModernTests
//
//  Ported from iTerm2XCTests/iTermCodingTests.m. Covers iTermEncoderGraphRecord
//  construction, equality and comparison, and iTermGraphEncoder output.
//

import XCTest
@testable import iTerm2SharedARC

final class GraphEncoderTests: XCTestCase {

    // MARK: - Helpers

    private func makeRecord(pod: [String: Any] = [:],
                            graphs: [iTermEncoderGraphRecord] = [],
                            generation: Int = 1,
                            key: String = "",
                            identifier: String = "",
                            rowid: Int? = 1) -> iTermEncoderGraphRecord {
        return iTermEncoderGraphRecord.withPODs(pod,
                                                graphs: graphs,
                                                generation: generation,
                                                key: key,
                                                identifier: identifier,
                                                rowid: rowid.map { NSNumber(value: $0) })
    }

    // MARK: - iTermEncoderGraphRecord construction

    func testGraphRecordWithChildrenExposesAllFields() {
        let pods1: [String: Any] = ["one": 1, "letter": "x"]
        let pods2: [String: Any] = ["one": 2, "letter": "y"]
        let data = Data("xyz".utf8)
        let pods3: [String: Any] = ["now": Date(timeIntervalSince1970: 1000000000),
                                    "data": data]
        let graphs = [
            makeRecord(pod: pods1, generation: 3, key: "k", identifier: "id1", rowid: 2),
            makeRecord(pod: pods2, generation: 5, key: "k", identifier: "id2", rowid: 3),
        ]
        let record = makeRecord(pod: pods3, graphs: graphs, generation: 7, key: "root", identifier: "", rowid: 1)

        XCTAssertEqual(record.pod as NSDictionary, pods3 as NSDictionary)
        XCTAssertEqual(record.graphRecords, graphs)
        XCTAssertEqual(record.generation, 7)
        XCTAssertEqual(record.key, "root")
        XCTAssertEqual(record.identifier, "")
        XCTAssertEqual(record.rowid, 1)
    }

    func testGraphRecordChildrenPointBackToParent() {
        let child = makeRecord(key: "k", identifier: "id1", rowid: 2)
        let record = makeRecord(graphs: [child], key: "root", rowid: 1)
        XCTAssertTrue(child.parent === record)
    }

    // MARK: - iTermGraphEncoder

    func testGraphEncoderProducesExpectedRecordTree() throws {
        let encoder = iTermGraphEncoder(key: "root", identifier: "", generation: 1)
        encoder.encode("red", forKey: "color")
        encoder.encode(NSNumber(value: 1), forKey: "count")
        encoder.encode(Data("abc".utf8), forKey: "blob")
        let date = Date(timeIntervalSince1970: 1000000000)
        encoder.encode(date, forKey: "date")
        _ = encoder.encodeChild(withKey: "left", identifier: "", generation: 2) { subencoder in
            subencoder.encode("bob", forKey: "name")
            return true
        }
        _ = encoder.encodeChild(withKey: "right", identifier: "", generation: 3) { subencoder in
            subencoder.encode(NSNumber(value: 23), forKey: "age")
            return true
        }

        let actual = try XCTUnwrap(encoder.record)

        let expectedPODs: [String: Any] = [
            "color": "red",
            "count": 1,
            "blob": Data("abc".utf8),
            "date": date,
        ]
        let expectedGraphs = [
            makeRecord(pod: ["name": "bob"], generation: 2, key: "left", identifier: "", rowid: nil),
            makeRecord(pod: ["age": 23], generation: 3, key: "right", identifier: "", rowid: nil),
        ]
        let expected = makeRecord(pod: expectedPODs, graphs: expectedGraphs, generation: 1, key: "root", identifier: "", rowid: nil)
        XCTAssertEqual(actual, expected)
    }

    func testGraphEncoderCommitsOnFirstRecordAccess() throws {
        let encoder = iTermGraphEncoder(key: "root", identifier: "", generation: 1)
        XCTAssertEqual(encoder.state, .live)
        _ = try XCTUnwrap(encoder.record)
        XCTAssertEqual(encoder.state, .committed)
    }

    func testEncodeDictionaryRoundTripsThroughPropertyListValue() throws {
        let encoder = iTermGraphEncoder(key: "root", identifier: "", generation: 1)
        let date = Date(timeIntervalSince1970: 1000000000)
        let dict: [String: Any] = [
            "string": "STRING",
            "number": 123,
            "data": Data("123".utf8),
            "date": date,
            "array": [
                "string1",
                "string2",
                "date",
                ["foo": "bar"],
                [1, 2, 3],
                NSNull(),
            ] as [Any],
        ]
        encoder.encode(dict, withKey: "root", generation: 1)
        let record = try XCTUnwrap(encoder.record)

        let plist = try XCTUnwrap(record.propertyListValue as? NSDictionary)
        XCTAssertEqual(plist["root"] as? NSDictionary, dict as NSDictionary)
    }

    func testImplicitDictionaryValueFlattensChildrenWithoutIdentifiers() throws {
        let encoder = iTermGraphEncoder(key: "ignored", identifier: "", generation: 1)
        encoder.encode("string", forKey: "key")
        _ = encoder.encodeChild(withKey: "dict", identifier: "", generation: 1) { subencoder in
            subencoder.encode("foo", forKey: "bar")
            return true
        }
        let expected: NSDictionary = [
            "key": "string",
            "dict": ["bar": "foo"],
            // Children with a nonzero generation and no identifier get their
            // generation injected next to them so consumers can migrate.
            "dict" + iTermEncoderGraphRecordGenerationKeySuffix: 1,
        ]
        let record = try XCTUnwrap(encoder.record)
        XCTAssertEqual(record.propertyListValue as? NSDictionary, expected)
    }

    func testImplicitDictionaryValueOmitsGenerationForGenerationZeroChild() throws {
        let encoder = iTermGraphEncoder(key: "ignored", identifier: "", generation: 1)
        _ = encoder.encodeChild(withKey: "dict", identifier: "", generation: 0) { subencoder in
            subencoder.encode("foo", forKey: "bar")
            return true
        }
        let expected: NSDictionary = ["dict": ["bar": "foo"]]
        let record = try XCTUnwrap(encoder.record)
        XCTAssertEqual(record.propertyListValue as? NSDictionary, expected)
    }

    // MARK: - compareGraphRecord

    func testCompareGraphRecordOrdersByGeneration() {
        let lhs = makeRecord(generation: 1, rowid: 2)
        let rhs = makeRecord(generation: 2, rowid: 3)
        XCTAssertEqual(lhs.compareGraphRecord(rhs), .orderedAscending)
        XCTAssertEqual(rhs.compareGraphRecord(lhs), .orderedDescending)
    }

    func testCompareGraphRecordIgnoresRowID() {
        let lhs = makeRecord(generation: 1, rowid: 2)
        let rhs = makeRecord(generation: 1, rowid: 1)
        XCTAssertEqual(lhs.compareGraphRecord(rhs), .orderedSame)
    }

    // MARK: - Equality

    func testGraphRecordIsEqualToItself() {
        let lhs = makeRecord()
        XCTAssertEqual(lhs, lhs)
        XCTAssertTrue(lhs.isEqual(lhs))
    }

    func testGraphRecordIsNotEqualToNilOrOtherClass() {
        let lhs = makeRecord()
        XCTAssertFalse(lhs.isEqual(nil))
        XCTAssertFalse(lhs.isEqual(NSNumber(value: 123)))
    }

    func testGraphRecordEqualityConsidersKey() {
        XCTAssertNotEqual(makeRecord(key: ""), makeRecord(key: "x"))
    }

    func testGraphRecordEqualityConsidersPOD() {
        XCTAssertNotEqual(makeRecord(pod: [:]), makeRecord(pod: ["xk": "xy"]))
    }

    func testGraphRecordEqualityConsidersChildren() {
        let lhs = makeRecord()
        XCTAssertNotEqual(lhs, makeRecord(graphs: [lhs]))
    }

    func testGraphRecordEqualityConsidersGeneration() {
        XCTAssertNotEqual(makeRecord(generation: 1), makeRecord(generation: 2))
    }

    func testGraphRecordEqualityConsidersIdentifier() {
        XCTAssertNotEqual(makeRecord(identifier: ""), makeRecord(identifier: "bogus"))
    }

    func testGraphRecordEqualityConsidersRowID() {
        XCTAssertNotEqual(makeRecord(rowid: 1), makeRecord(rowid: 2))
    }

    func testGraphRecordEqualityIgnoresChildOrder() {
        let a = makeRecord(key: "k", identifier: "a", rowid: 2)
        let b = makeRecord(key: "k", identifier: "b", rowid: 3)
        XCTAssertEqual(makeRecord(graphs: [a, b]), makeRecord(graphs: [b, a]))
    }
}
