//
//  iTermGraphDatabaseTests.swift
//  iTerm2
//
//  Created by George Nachman on 3/17/26.
//

import XCTest
@testable import iTerm2SharedARC

/// Tests for iTermGraphDatabase optimization infrastructure.
/// These tests verify the graph encoder and record behavior.
class iTermGraphDatabaseTests: XCTestCase {

    // MARK: - GraphEncoder Record Tests

    /// Test creating graph records directly
    func testGraphRecordCreation() {
        let record = iTermEncoderGraphRecord.withPODs(
            ["key": "value"],
            graphs: [],
            generation: 1,
            key: "testKey",
            identifier: "testId",
            rowid: NSNumber(value: 42)
        )

        XCTAssertEqual(record.key, "testKey")
        XCTAssertEqual(record.identifier, "testId")
        XCTAssertEqual(record.generation, 1)
        XCTAssertEqual(record.rowid?.intValue, 42)
        XCTAssertEqual(record.pod["key"] as? String, "value")
    }

    /// Test nested graph record creation
    func testNestedGraphRecordCreation() {
        let child = iTermEncoderGraphRecord.withPODs(
            [:],
            graphs: [],
            generation: 1,
            key: "child",
            identifier: "c1",
            rowid: NSNumber(value: 2)
        )

        let parent = iTermEncoderGraphRecord.withPODs(
            [:],
            graphs: [child],
            generation: 1,
            key: "",
            identifier: "",
            rowid: NSNumber(value: 1)
        )

        XCTAssertEqual(parent.graphRecords.count, 1)
        XCTAssertEqual(parent.childRecord(withKey: "child", identifier: "c1")?.rowid?.intValue, 2)
    }

    /// Test that eraseRowIDs works recursively
    func testEraseRowIDsRecursive() {
        let child = iTermEncoderGraphRecord.withPODs(
            [:],
            graphs: [],
            generation: 1,
            key: "child",
            identifier: "c1",
            rowid: NSNumber(value: 2)
        )

        let parent = iTermEncoderGraphRecord.withPODs(
            [:],
            graphs: [child],
            generation: 1,
            key: "",
            identifier: "",
            rowid: NSNumber(value: 1)
        )

        // Verify rowids exist
        XCTAssertNotNil(parent.rowid)
        XCTAssertNotNil(parent.graphRecords.first?.rowid)

        // Erase
        parent.eraseRowIDs()

        // Verify rowids are nil
        XCTAssertNil(parent.rowid)
        XCTAssertNil(parent.graphRecords.first?.rowid)
    }

    // MARK: - GraphEncoder Tests

    /// Test basic encoding with graph encoder
    func testBasicEncoding() {
        let encoder = iTermGraphEncoder(
            key: "",
            identifier: "",
            generation: 1
        )

        encoder.encode("testValue", forKey: "testKey")
        encoder.encode(NSNumber(value: 42), forKey: "numberKey")

        let record = encoder.record
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.pod["testKey"] as? String, "testValue")
        XCTAssertEqual((record?.pod["numberKey"] as? NSNumber)?.intValue, 42)
    }

    /// Test child encoding with graph encoder
    func testChildEncoding() {
        let encoder = iTermGraphEncoder(
            key: "",
            identifier: "",
            generation: 1
        )

        let success = encoder.encodeChild(
            withKey: "child",
            identifier: "c1",
            generation: 1
        ) { childEncoder in
            childEncoder.encode("childValue", forKey: "childKey")
            return true
        }

        XCTAssertTrue(success)

        let record = encoder.record
        XCTAssertEqual(record?.graphRecords.count, 1)

        let child = record?.childRecord(withKey: "child", identifier: "c1")
        XCTAssertNotNil(child)
        XCTAssertEqual(child?.pod["childKey"] as? String, "childValue")
    }

    // MARK: - Data Serialization Tests

    /// Test that data serialization round-trips correctly
    func testDataSerializationRoundTrip() {
        let originalPod: [String: Any] = [
            "string": "hello",
            "number": NSNumber(value: 123),
            "array": [1, 2, 3],
            "nested": ["a": "b"]
        ]

        // Create record
        let record = iTermEncoderGraphRecord.withPODs(
            originalPod,
            graphs: [],
            generation: 1,
            key: "test",
            identifier: "t1",
            rowid: nil
        )

        // Serialize
        let data = record.data

        // Deserialize
        let restored = try? (data as NSData).it_unarchivedObjectOfBasicClasses() as? [String: Any]
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?["string"] as? String, "hello")
        XCTAssertEqual((restored?["number"] as? NSNumber)?.intValue, 123)
    }

    // MARK: - Generation Tests

    /// Test that iTermGenerationAlwaysEncode constant is accessible
    func testGenerationAlwaysEncodeConstant() {
        XCTAssertEqual(iTermGenerationAlwaysEncode, Int.max, "iTermGenerationAlwaysEncode should be NSIntegerMax")
    }

    /// Test record comparison
    func testRecordComparison() {
        let record1 = iTermEncoderGraphRecord.withPODs(
            [:],
            graphs: [],
            generation: 1,
            key: "a",
            identifier: "1",
            rowid: nil
        )

        let record2 = iTermEncoderGraphRecord.withPODs(
            [:],
            graphs: [],
            generation: 2,
            key: "a",
            identifier: "1",
            rowid: nil
        )

        let comparison = record1.compareGraphRecord(record2)
        XCTAssertEqual(comparison, .orderedAscending, "Lower generation should be ordered before higher")
    }

    /// Test child lookup with index
    func testChildLookupWithIndex() {
        var children: [iTermEncoderGraphRecord] = []
        for i in 0..<20 {
            let child = iTermEncoderGraphRecord.withPODs(
                ["value": i],
                graphs: [],
                generation: 1,
                key: "child",
                identifier: "\(i)",
                rowid: NSNumber(value: 10 + i)
            )
            children.append(child)
        }

        let parent = iTermEncoderGraphRecord.withPODs(
            [:],
            graphs: children,
            generation: 1,
            key: "",
            identifier: "",
            rowid: NSNumber(value: 1)
        )

        // Ensure index is built
        parent.ensureIndexOfGraphRecords()

        // Look up children
        for i in 0..<20 {
            let child = parent.childRecord(withKey: "child", identifier: "\(i)")
            XCTAssertNotNil(child)
            XCTAssertEqual((child?.pod["value"] as? Int), i)
        }
    }

    // MARK: - Deep Tree Tests

    /// Test deep tree structure creation and traversal
    func testDeepTreeStructure() {
        // Create a 3-level deep structure
        let grandchild = iTermEncoderGraphRecord.withPODs(
            ["level": 3],
            graphs: [],
            generation: 1,
            key: "grandchild",
            identifier: "gc1",
            rowid: NSNumber(value: 3)
        )

        let child = iTermEncoderGraphRecord.withPODs(
            ["level": 2],
            graphs: [grandchild],
            generation: 1,
            key: "child",
            identifier: "c1",
            rowid: NSNumber(value: 2)
        )

        let root = iTermEncoderGraphRecord.withPODs(
            ["level": 1],
            graphs: [child],
            generation: 1,
            key: "",
            identifier: "",
            rowid: NSNumber(value: 1)
        )

        // Verify structure
        XCTAssertEqual(root.graphRecords.count, 1)
        XCTAssertEqual(root.graphRecords.first?.graphRecords.count, 1)

        // Verify parent references
        let foundChild = root.childRecord(withKey: "child", identifier: "c1")
        XCTAssertNotNil(foundChild)

        let foundGrandchild = foundChild?.childRecord(withKey: "grandchild", identifier: "gc1")
        XCTAssertNotNil(foundGrandchild)
        XCTAssertEqual(foundGrandchild?.pod["level"] as? Int, 3)
    }
}
