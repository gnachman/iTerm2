//
//  iTermGraphDeltaEncoderTests.swift
//  iTerm2
//
//  Created by George Nachman on 3/17/26.
//

import XCTest
@testable import iTerm2SharedARC

class iTermGraphDeltaEncoderTests: XCTestCase {

    // MARK: - Helper Methods

    /// Creates a record with optional children
    private func createRecord(
        key: String,
        identifier: String,
        generation: Int,
        rowid: NSNumber? = nil,
        children: [iTermEncoderGraphRecord] = []
    ) -> iTermEncoderGraphRecord {
        return iTermEncoderGraphRecord.withPODs(
            ["value": "\(key)_\(identifier)"],
            graphs: children,
            generation: generation,
            key: key,
            identifier: identifier,
            rowid: rowid
        )
    }

    // MARK: - Insert Tests

    func testEnumeratesInsertedNodes() {
        // Given a delta encoder with no previous revision (all inserts)
        let encoder = iTermGraphDeltaEncoder(previousRevision: nil)

        // When we encode some children
        _ = encoder.encodeChild(withKey: "child", identifier: "1", generation: 1) { child in
            child.encode("value1", forKey: "key")
            return true
        }
        _ = encoder.encodeChild(withKey: "child", identifier: "2", generation: 1) { child in
            child.encode("value2", forKey: "key")
            return true
        }

        // Then enumerating should show inserts (before=nil, after=record)
        var insertCount = 0
        var updateCount = 0
        var deleteCount = 0

        _ = encoder.enumerateRecords { before, after, parent, path, stop in
            if before == nil && after != nil {
                insertCount += 1
            } else if before != nil && after != nil {
                updateCount += 1
            } else if before != nil && after == nil {
                deleteCount += 1
            }
        }

        // Root + 2 children = 3 inserts
        XCTAssertEqual(insertCount, 3, "Should have 3 inserts (root + 2 children)")
        XCTAssertEqual(updateCount, 0, "Should have no updates")
        XCTAssertEqual(deleteCount, 0, "Should have no deletes")
    }

    // MARK: - Delete Tests

    func testEnumeratesDeletedNodes() {
        // Given a previous revision with children
        let child1 = createRecord(key: "child", identifier: "1", generation: 1, rowid: 10)
        let child2 = createRecord(key: "child", identifier: "2", generation: 1, rowid: 11)
        let previousRoot = createRecord(
            key: "",
            identifier: "",
            generation: 1,
            rowid: 1,
            children: [child1, child2]
        )

        // When we create an encoder and don't include child2
        let encoder = iTermGraphDeltaEncoder(previousRevision: previousRoot)
        _ = encoder.encodeChild(withKey: "child", identifier: "1", generation: 1) { child in
            child.encode("value1", forKey: "key")
            return true
        }
        // child2 is not encoded - it should be deleted

        // Then enumerating should show delete
        var deleteCount = 0
        var deletedIdentifiers: [String] = []

        _ = encoder.enumerateRecords { before, after, parent, path, stop in
            if before != nil && after == nil {
                deleteCount += 1
                deletedIdentifiers.append(before!.identifier)
            }
        }

        XCTAssertEqual(deleteCount, 1, "Should have 1 delete")
        XCTAssertTrue(deletedIdentifiers.contains("2"), "Child '2' should be deleted")
    }

    // MARK: - Update Tests

    func testEnumeratesUpdatedNodes() {
        // Given a previous revision
        let child1 = createRecord(key: "child", identifier: "1", generation: 1, rowid: 10)
        let previousRoot = createRecord(
            key: "",
            identifier: "",
            generation: 1,
            rowid: 1,
            children: [child1]
        )

        // When we create an encoder and update a child with higher generation
        let encoder = iTermGraphDeltaEncoder(previousRevision: previousRoot)
        _ = encoder.encodeChild(withKey: "child", identifier: "1", generation: 2) { child in
            child.encode("updated_value", forKey: "key")
            return true
        }

        // Then enumerating should show update (before and after both non-nil)
        var updateCount = 0
        var rootUpdateCount = 0

        _ = encoder.enumerateRecords { before, after, parent, path, stop in
            if before != nil && after != nil {
                if before!.key == "child" {
                    updateCount += 1
                    XCTAssertEqual(before!.generation, 1, "Before generation should be 1")
                    XCTAssertEqual(after!.generation, 2, "After generation should be 2")
                } else if before!.key == "" {
                    rootUpdateCount += 1
                }
            }
        }

        XCTAssertEqual(updateCount, 1, "Should have 1 child update")
        XCTAssertEqual(rootUpdateCount, 1, "Should have 1 root update")
    }

    // MARK: - Full Tree Enumeration Tests

    func testEnumeratesEntireTreeSkipsUnchangedSubtrees() {
        // Given a previous revision with nested structure
        let grandchild = createRecord(key: "grandchild", identifier: "gc1", generation: 1, rowid: 100)
        let child1 = createRecord(key: "child", identifier: "1", generation: 1, rowid: 10, children: [grandchild])
        let child2 = createRecord(key: "child", identifier: "2", generation: 1, rowid: 11)
        let previousRoot = createRecord(
            key: "",
            identifier: "",
            generation: 1,
            rowid: 1,
            children: [child1, child2]
        )

        // When we create an encoder that matches the previous state (no changes)
        let encoder = iTermGraphDeltaEncoder(previousRevision: previousRoot)

        // Encode the same structure with same generations
        _ = encoder.encodeChild(withKey: "child", identifier: "1", generation: 1) { child in
            _ = child.encodeChild(withKey: "grandchild", identifier: "gc1", generation: 1) { grandchild in
                grandchild.encode("gcValue", forKey: "key")
                return true
            }
            return true
        }
        _ = encoder.encodeChild(withKey: "child", identifier: "2", generation: 1) { child in
            child.encode("value2", forKey: "key")
            return true
        }

        // Then enumeration should visit top-level nodes but skip recursing into unchanged subtrees
        var visitedPaths: [String] = []

        _ = encoder.enumerateRecords { before, after, parent, path, stop in
            visitedPaths.append(path)
        }

        // Should visit: root, child[1], child[2]
        // grandchild[gc1] is skipped because child[1]'s subtree is unchanged (same rowid + generation)
        XCTAssertEqual(visitedPaths.count, 3, "Should visit 3 nodes (skipping unchanged grandchild subtree)")
        XCTAssertTrue(visitedPaths.contains("root"), "Should visit root")
    }

    // MARK: - Generation Handling Tests

    func testAlwaysEncodeGenerationIsRecognized() {
        // Given a previous revision
        let child = createRecord(key: "child", identifier: "1", generation: 5, rowid: 10)
        let previousRoot = createRecord(
            key: "",
            identifier: "",
            generation: 1,
            rowid: 1,
            children: [child]
        )

        // When we encode with iTermGenerationAlwaysEncode
        let encoder = iTermGraphDeltaEncoder(previousRevision: previousRoot)
        _ = encoder.encodeChild(withKey: "child", identifier: "1", generation: iTermGenerationAlwaysEncode) { child in
            child.encode("forced_update", forKey: "key")
            return true
        }

        // Then the record is enumerated, flagged as always encoded, and keeps the saved generation.
        // The flag (not a changed generation) is what makes it get re-examined, and the stable
        // generation lets the database skip the row when its data is unchanged.
        var foundChild = false
        _ = encoder.enumerateRecords { before, after, parent, path, stop in
            if after?.key == "child" && after?.identifier == "1" {
                foundChild = true
                XCTAssertTrue(after!.alwaysEncoded)
                XCTAssertEqual(after!.generation, 5, "Generation should be kept from the previous revision")
                XCTAssertEqual(after!.pod["key"] as? String, "forced_update")
            }
        }

        XCTAssertTrue(foundChild, "Should find child node")
    }

    func testOlderGenerationGetsAFreshGenerationThatCannotCollide() {
        // Given a saved record whose generation is the newest one the shared counter handed out,
        // as it is right after the database raises the floor above the highest saved generation.
        let savedGeneration = iTermGenerationNext()
        let child = createRecord(key: "child", identifier: "1", generation: savedGeneration, rowid: 10)
        let previousRoot = createRecord(
            key: "",
            identifier: "",
            generation: 1,
            rowid: 1,
            children: [child]
        )

        // When the object still reports an older generation (e.g., it hasn't been restored yet).
        let encoder = iTermGraphDeltaEncoder(previousRevision: previousRoot)
        _ = encoder.encodeChild(withKey: "child", identifier: "1", generation: 0) { child in
            child.encode("unrestored", forKey: "key")
            return true
        }

        var writtenGeneration: Int?
        _ = encoder.enumerateRecords { before, after, parent, path, stop in
            if after?.key == "child" && after?.identifier == "1" {
                writtenGeneration = after!.generation
            }
        }

        // Then the written generation moves past the saved one, and the next generation the object
        // can get from the counter is different, so its next change isn't mistaken for this record.
        let written = try! XCTUnwrap(writtenGeneration)
        XCTAssertGreaterThan(written, savedGeneration)
        XCTAssertNotEqual(iTermGenerationNext(), written)
    }

    func testNonArchivableArrayUnderAlwaysEncodedParentIsReencodedOnEverySave() {
        // An array that fails the trial secure archive is encoded as child nodes. Under an
        // always-encoded parent, those children must be re-encoded on every save too.
        func save(_ value: String, previous: iTermEncoderGraphRecord?) -> iTermEncoderGraphRecord {
            let encoder = iTermGraphDeltaEncoder(previousRevision: previous)
            _ = encoder.encodeChild(withKey: "parent", identifier: "", generation: iTermGenerationAlwaysEncode) { parent in
                parent.encode([GraphEncoderIgnoredObject(), value], key: "x")
                return true
            }
            return encoder.record!
        }
        func arrayValues(_ root: iTermEncoderGraphRecord) -> [String] {
            let parent = root.childRecord(withKey: "parent", identifier: "")
            let array = parent?.childRecord(withKey: "__array", identifier: "x")
            return (array?.graphRecords ?? []).compactMap { $0.pod["__arrayValue"] as? String }
        }

        // The database normally assigns rowids, and a previous revision must have them.
        var nextRowid = 1
        func assignRowids(_ record: iTermEncoderGraphRecord) {
            record.rowid = NSNumber(value: nextRowid)
            nextRowid += 1
            record.graphRecords.forEach { assignRowids($0) }
        }

        let first = save("a", previous: nil)
        XCTAssertEqual(arrayValues(first), ["a"])
        assignRowids(first)

        let second = save("b", previous: first)
        XCTAssertEqual(arrayValues(second), ["b"])
    }

    // MARK: - Baseline Enumeration Count Test

    func testEnumerationCountBaseline() {
        // Given a tree with many nodes
        var children: [iTermEncoderGraphRecord] = []
        for i in 0..<50 {
            let child = createRecord(key: "child", identifier: "\(i)", generation: 1, rowid: NSNumber(value: 10 + i))
            children.append(child)
        }
        let previousRoot = createRecord(
            key: "",
            identifier: "",
            generation: 1,
            rowid: 1,
            children: children
        )

        // When we update only one child
        let encoder = iTermGraphDeltaEncoder(previousRevision: previousRoot)
        for i in 0..<50 {
            // Only child 0 has a new generation
            let generation = (i == 0) ? 2 : 1
            _ = encoder.encodeChild(withKey: "child", identifier: "\(i)", generation: generation) { child in
                child.encode("value\(i)", forKey: "key")
                return true
            }
        }

        // Then enumeration visits all nodes (current behavior - no pruning)
        var visitCount = 0
        _ = encoder.enumerateRecords { before, after, parent, path, stop in
            visitCount += 1
        }

        // Currently visits all 51 nodes (root + 50 children)
        // After optimization, this should be much smaller
        XCTAssertEqual(visitCount, 51, "Baseline: should visit all 51 nodes")
    }

    // MARK: - Rowid Preservation Tests

    func testRowidPreservedOnUnchangedNodes() {
        // Given a previous revision with rowids
        let child = createRecord(key: "child", identifier: "1", generation: 1, rowid: 42)
        let previousRoot = createRecord(
            key: "",
            identifier: "",
            generation: 1,
            rowid: 1,
            children: [child]
        )

        // When we encode the same child (same generation = unchanged)
        let encoder = iTermGraphDeltaEncoder(previousRevision: previousRoot)
        _ = encoder.encodeChild(withKey: "child", identifier: "1", generation: 1) { child in
            child.encode("same_value", forKey: "key")
            return true
        }

        // Then the rowid should be preserved in the after record
        var afterRowid: NSNumber?
        _ = encoder.enumerateRecords { before, after, parent, path, stop in
            if after?.key == "child" && after?.identifier == "1" {
                afterRowid = after!.rowid
            }
        }

        XCTAssertEqual(afterRowid, 42, "Rowid should be preserved for unchanged node")
    }
}

// Not secure-codable, so an array containing it fails the trial archive and is encoded as child
// nodes. The encoder skips it.
private class GraphEncoderIgnoredObject: NSObject, iTermGraphEncodable {
    func graphEncoderShouldIgnore() -> Bool {
        return true
    }
}
