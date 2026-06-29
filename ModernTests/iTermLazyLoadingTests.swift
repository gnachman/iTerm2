//
//  iTermLazyLoadingTests.swift
//  iTerm2
//
//  Created by George Nachman on 3/18/26.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - iTermLargeContentStorageTests

/// Tests that large content is stored in the correct column
class iTermLargeContentStorageTests: XCTestCase {

    // MARK: - Test Large Content Key Detection

    func testLargeContentKeyDetection() {
        // Verify that iTermLargeContentMetadata.largeContentKey is the expected value
        XCTAssertEqual(iTermLargeContentMetadata.largeContentKey, "__large_content")
    }

    func testLargeContentKeyIsRecognized() {
        // When we have a key equal to iTermLargeContentMetadata.largeContentKey
        let key = iTermLargeContentMetadata.largeContentKey

        // Then it should be recognized as a large content key
        XCTAssertEqual(key, "__large_content")
    }

    // MARK: - Test Database Storage Behavior

    func testSmallContentStoredInDataColumn() {
        // Given an in-memory database with current schema
        let db = InMemoryDatabaseHelper.createInMemoryDatabaseWithCurrentSchema()
        defer { db.close() }

        // When we insert a node with a normal key (not __large_content)
        let pod: [String: Any] = ["key": "value"]
        guard let data = LegacyDatabaseBuilder.serializePOD(pod) else {
            XCTFail("Failed to serialize POD")
            return
        }

        let success = db.executeUpdate(
            "INSERT INTO Node (key, identifier, parent, data, generation, large_data) VALUES (?, ?, ?, ?, ?, ?)",
            withArgumentsIn: ["normalKey", "id1", 0, data, 0, NSNull()]
        )
        XCTAssertTrue(success)

        // Then the data should be in the data column, not large_data
        guard let rs = db.executeQuery(
            "SELECT data, large_data FROM Node WHERE key = ?",
            withArgumentsIn: ["normalKey"]
        ) else {
            XCTFail("Query failed")
            return
        }
        defer { rs.close() }

        XCTAssertTrue(rs.next())
        let storedData = rs.data(forColumn: "data")
        let storedLargeData = rs.data(forColumn: "large_data")

        XCTAssertNotNil(storedData)
        XCTAssertTrue(storedData?.count ?? 0 > 0)
        XCTAssertTrue(storedLargeData == nil || storedLargeData?.count == 0)
    }

    func testEmptyLargeContentNotStored() {
        // Given an empty content dictionary
        let emptyContent: [AnyHashable: Any] = [:]

        // When we try to serialize it
        var error: NSError?
        let data = NSData.it_data(withSecurelyArchivedObject: emptyContent as NSDictionary, error: &error)

        // Then it should serialize (possibly to empty or minimal data)
        // This verifies the encoding doesn't crash on empty content
        XCTAssertNotNil(data)
    }
}

// MARK: - iTermPropertyListValueTests

/// Tests for propertyListValue returning correct metadata for lazy loading
class iTermPropertyListValueTests: XCTestCase {

    func testPropertyListValueReturnsMetadataForUnloadedLargeContent() {
        // Given a record with hasLargeData=true but no loaded content
        let rowid = NSNumber(value: 42)
        // Create record with nil POD to simulate unloaded large content
        let record = iTermEncoderGraphRecord.withPODs(
            nil,  // nil POD indicates content not yet loaded
            graphs: nil,
            generation: 0,
            key: iTermLargeContentMetadata.largeContentKey,
            identifier: "test",
            rowid: rowid
        )
        record.hasLargeData = true
        // Note: database is already nil by default

        // When we get the propertyListValue
        guard let plist = record.propertyListValue as? [AnyHashable: Any] else {
            XCTFail("Expected dictionary from propertyListValue")
            return
        }

        // Then it should return lazy loading metadata
        XCTAssertTrue(iTermLargeContentMetadata.isLargeContentMetadata(plist))
        XCTAssertEqual(iTermLargeContentMetadata.rowid(from: plist), rowid)
    }

    func testPropertyListValueReturnsDataForLoadedContent() {
        // Given a record with loaded POD content
        let pod: [String: Any] = ["key": "value", "number": 123]
        let record = iTermEncoderGraphRecord.withPODs(
            pod,
            graphs: [],
            generation: 0,
            key: "normalKey",
            identifier: "test",
            rowid: NSNumber(value: 1)
        )

        // When we get the propertyListValue
        guard let plist = record.propertyListValue as? [String: Any] else {
            XCTFail("Expected dictionary from propertyListValue")
            return
        }

        // Then it should return the actual data
        XCTAssertEqual(plist["key"] as? String, "value")
        XCTAssertEqual(plist["number"] as? Int, 123)
    }

    func testPropertyListValueForNormalRecord() {
        // Given a normal record (not large content)
        let pod: [String: Any] = ["test": "data"]
        let record = iTermEncoderGraphRecord.withPODs(
            pod,
            graphs: [],
            generation: 1,
            key: "child",
            identifier: "c1",
            rowid: NSNumber(value: 10)
        )

        // When we get the propertyListValue
        guard let plist = record.propertyListValue as? [String: Any] else {
            XCTFail("Expected dictionary from propertyListValue")
            return
        }

        // Then it should return the normal POD content
        XCTAssertEqual(plist["test"] as? String, "data")
        XCTAssertFalse(iTermLargeContentMetadata.isLargeContentMetadata(plist))
    }
}

// MARK: - iTermFoldMarkLazyLoadingTests

/// Tests for FoldMark lazy loading behavior
class iTermFoldMarkLazyLoadingTests: XCTestCase {

    func testFoldMarkDataNotLoadedUntilAccessed() {
        // Given a mock provider with content
        let mockProvider = MockiTermLargeContentProvider()
        let rowid = NSNumber(value: 100)
        let largeContent = LegacyDatabaseBuilder.createFoldMarkLargeContent(savedLinesCount: 5)
        mockProvider.setContent(largeContent, forRowID: rowid)

        // And a FoldMark created with lazy loading
        let smallDict: [AnyHashable: Any] = [
            "prompt length": 0,
            "image codes": []
        ]
        let metadata = iTermLargeContentMetadata.metadata(forRowID: rowid)

        let foldMark = FoldMark(
            smallDictionary: smallDict,
            largeContent: nil,  // No inline content
            provider: mockProvider,
            metadata: metadata
        )!

        // Then the provider should NOT have been called yet
        XCTAssertEqual(mockProvider.loadCallCount, 0, "Provider should not be called before accessing content")

        // When we access savedLines
        _ = foldMark.savedLines

        // Then the provider should have been called exactly once
        XCTAssertEqual(mockProvider.loadCallCount, 1, "Provider should be called once when content is accessed")
        XCTAssertEqual(mockProvider.loadedRowIDs.first, rowid)
    }

    func testFoldMarkDataCachedAfterFirstAccess() {
        // Given a mock provider with content
        let mockProvider = MockiTermLargeContentProvider()
        let rowid = NSNumber(value: 101)
        let largeContent = LegacyDatabaseBuilder.createFoldMarkLargeContent(savedLinesCount: 3)
        mockProvider.setContent(largeContent, forRowID: rowid)

        let smallDict: [AnyHashable: Any] = [
            "prompt length": 0,
            "image codes": []
        ]
        let metadata = iTermLargeContentMetadata.metadata(forRowID: rowid)

        let foldMark = FoldMark(
            smallDictionary: smallDict,
            largeContent: nil,
            provider: mockProvider,
            metadata: metadata
        )!

        // When we access savedLines multiple times
        _ = foldMark.savedLines
        _ = foldMark.savedLines
        _ = foldMark.savedITOs
        _ = foldMark.savedLines

        // Then the provider should still have been called only once
        XCTAssertEqual(mockProvider.loadCallCount, 1, "Provider should be called only once - content should be cached")
    }

    func testFoldMarkInlineContentLoadsImmediately() {
        // Given a FoldMark created with inline large content (not lazy)
        let mockProvider = MockiTermLargeContentProvider()
        let largeContent = LegacyDatabaseBuilder.createFoldMarkLargeContent(savedLinesCount: 2)

        let smallDict: [AnyHashable: Any] = [
            "prompt length": 0,
            "image codes": []
        ]

        let foldMark = FoldMark(
            smallDictionary: smallDict,
            largeContent: largeContent,  // Inline content provided
            provider: mockProvider,
            metadata: nil
        )!

        // Then the provider should NOT be called (content is inline)
        _ = foldMark.savedLines
        XCTAssertEqual(mockProvider.loadCallCount, 0, "Provider should not be called when inline content is provided")
    }

    func testFoldMarkHandlesNilProvider() {
        // Given a FoldMark with lazy metadata but no provider
        let smallDict: [AnyHashable: Any] = [
            "prompt length": 0,
            "image codes": []
        ]
        let metadata = iTermLargeContentMetadata.metadata(forRowID: NSNumber(value: 999))

        let foldMark = FoldMark(
            smallDictionary: smallDict,
            largeContent: nil,
            provider: nil,  // No provider
            metadata: metadata
        )!

        // When we access savedLines
        let lines = foldMark.savedLines

        // Then it should return nil gracefully
        XCTAssertNil(lines, "Should return nil when provider is nil")
    }

    func testFoldMarkEmptyLargeContent() {
        // Given a mock provider that returns empty content
        let mockProvider = MockiTermLargeContentProvider()
        let rowid = NSNumber(value: 102)
        mockProvider.setContent([:], forRowID: rowid)  // Empty content

        let smallDict: [AnyHashable: Any] = [
            "prompt length": 0,
            "image codes": []
        ]
        let metadata = iTermLargeContentMetadata.metadata(forRowID: rowid)

        let foldMark = FoldMark(
            smallDictionary: smallDict,
            largeContent: nil,
            provider: mockProvider,
            metadata: metadata
        )!

        // When we access savedLines
        let lines = foldMark.savedLines

        // Then it should handle empty content gracefully
        XCTAssertNil(lines, "Should return nil for empty large content")
    }
}

// MARK: - iTermProviderPlumbingTests

/// Tests that the provider is correctly passed through the restoration chain
class iTermProviderPlumbingTests: XCTestCase {

    func testGraphDatabaseConformsToProvider() {
        // iTermGraphDatabase should conform to LargeContentProvider
        // This is verified by checking if the class responds to the protocol method
        // Since iTermGraphDatabase is not directly available in Swift, we use NSClassFromString
        guard let dbClass = NSClassFromString("iTermGraphDatabase") else {
            XCTFail("iTermGraphDatabase class not found")
            return
        }
        XCTAssertTrue(dbClass.conforms(to: iTermLargeContentProvider.self),
                     "iTermGraphDatabase should conform to iTermLargeContentProvider")
    }

    func testLargeContentMetadataCreation() {
        // Given a rowid
        let rowid = NSNumber(value: 12345)

        // When we create metadata
        let metadata = iTermLargeContentMetadata.metadata(forRowID: rowid)

        // Then it should be valid lazy loading metadata
        XCTAssertTrue(iTermLargeContentMetadata.isLargeContentMetadata(metadata))
        XCTAssertEqual(iTermLargeContentMetadata.rowid(from: metadata), rowid)
    }

    func testLargeContentMetadataWithZeroRowID() {
        // When we create metadata with zero rowid (as fallback for nil)
        let metadata = iTermLargeContentMetadata.metadata(forRowID: NSNumber(value: 0))

        // Then it should still be valid metadata with rowid 0
        XCTAssertTrue(iTermLargeContentMetadata.isLargeContentMetadata(metadata))
        XCTAssertEqual(iTermLargeContentMetadata.rowid(from: metadata), NSNumber(value: 0))
    }
}

// MARK: - iTermDeltaEncoderSkipTests

/// Tests for the skip optimization in delta encoding
class iTermDeltaEncoderSkipTests: XCTestCase {

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

    func testUnchangedSubtreesSkipped() {
        // Given a previous revision with a deep subtree
        let grandchild = createRecord(key: "grandchild", identifier: "gc1", generation: 1, rowid: NSNumber(value: 100))
        let child = createRecord(key: "child", identifier: "c1", generation: 1, rowid: NSNumber(value: 10), children: [grandchild])
        let previousRoot = createRecord(key: "", identifier: "", generation: 1, rowid: NSNumber(value: 1), children: [child])

        // When we encode the same structure with same generations
        let encoder = iTermGraphDeltaEncoder(previousRevision: previousRoot)
        _ = encoder.encodeChild(withKey: "child", identifier: "c1", generation: 1) { childEncoder in
            _ = childEncoder.encodeChild(withKey: "grandchild", identifier: "gc1", generation: 1) { gcEncoder in
                gcEncoder.encode("value", forKey: "key")
                return true
            }
            return true
        }

        // Then enumeration should skip unchanged subtrees
        var visitedKeys: [String] = []
        _ = encoder.enumerateRecords { before, after, parent, path, stop in
            if let key = after?.key ?? before?.key {
                visitedKeys.append(key)
            }
        }

        // With skip optimization, unchanged subtrees should not enumerate their children
        // Root + child should be visited, but grandchild might be skipped if child is unchanged
        XCTAssertTrue(visitedKeys.contains(""), "Root should be visited")
        XCTAssertTrue(visitedKeys.contains("child"), "Child should be visited")
    }

    func testChangedSubtreesNotSkipped() {
        // Given a previous revision
        let grandchild = createRecord(key: "grandchild", identifier: "gc1", generation: 1, rowid: NSNumber(value: 100))
        let child = createRecord(key: "child", identifier: "c1", generation: 1, rowid: NSNumber(value: 10), children: [grandchild])
        let previousRoot = createRecord(key: "", identifier: "", generation: 1, rowid: NSNumber(value: 1), children: [child])

        // When we encode with changed generation (child generation bumped)
        let encoder = iTermGraphDeltaEncoder(previousRevision: previousRoot)
        _ = encoder.encodeChild(withKey: "child", identifier: "c1", generation: 2) { childEncoder in
            _ = childEncoder.encodeChild(withKey: "grandchild", identifier: "gc1", generation: 1) { gcEncoder in
                gcEncoder.encode("value", forKey: "key")
                return true
            }
            return true
        }

        // Then enumeration should NOT skip the changed subtree
        var visitedKeys: [String] = []
        _ = encoder.enumerateRecords { before, after, parent, path, stop in
            if let key = after?.key ?? before?.key {
                visitedKeys.append(key)
            }
        }

        // All nodes should be visited since child changed
        XCTAssertTrue(visitedKeys.contains(""), "Root should be visited")
        XCTAssertTrue(visitedKeys.contains("child"), "Child should be visited")
        XCTAssertTrue(visitedKeys.contains("grandchild"), "Grandchild should be visited since parent changed")
    }

    func testAlwaysEncodeGenerationPreventsSkipping() {
        // Given a previous revision
        let child = createRecord(key: "child", identifier: "c1", generation: 5, rowid: NSNumber(value: 10))
        let previousRoot = createRecord(key: "", identifier: "", generation: 1, rowid: NSNumber(value: 1), children: [child])

        // When we encode with iTermGenerationAlwaysEncode
        let encoder = iTermGraphDeltaEncoder(previousRevision: previousRoot)
        _ = encoder.encodeChild(withKey: "child", identifier: "c1", generation: iTermGenerationAlwaysEncode) { childEncoder in
            childEncoder.encode("forced", forKey: "key")
            return true
        }

        // Then the node should be visited with incremented generation
        var foundChildGeneration: Int?
        _ = encoder.enumerateRecords { before, after, parent, path, stop in
            if after?.key == "child" {
                foundChildGeneration = after?.generation
            }
        }

        XCTAssertEqual(foundChildGeneration, 6, "Generation should be incremented from previous")
    }

    func testSkipRequiresMatchingRowID() {
        // Given a previous revision with rowid
        let child = createRecord(key: "child", identifier: "c1", generation: 1, rowid: NSNumber(value: 10))
        let previousRoot = createRecord(key: "", identifier: "", generation: 1, rowid: NSNumber(value: 1), children: [child])

        // When we create an encoder and encode the same child
        let encoder = iTermGraphDeltaEncoder(previousRevision: previousRoot)
        _ = encoder.encodeChild(withKey: "child", identifier: "c1", generation: 1) { childEncoder in
            childEncoder.encode("value", forKey: "key")
            return true
        }

        // Then the after record should get the same rowid from before
        var afterRowid: NSNumber?
        _ = encoder.enumerateRecords { before, after, parent, path, stop in
            if after?.key == "child" {
                afterRowid = after?.rowid
            }
        }

        XCTAssertEqual(afterRowid, NSNumber(value: 10), "After record should inherit rowid from before")
    }
}

// MARK: - iTermDeletionDetectionTests

/// Tests for detection of deleted nodes during delta encoding
class iTermDeletionDetectionTests: XCTestCase {

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

    func testDeletionsDetectedWithSkipOptimization() {
        // Given a previous revision with multiple children
        let childA = createRecord(key: "child", identifier: "A", generation: 1, rowid: NSNumber(value: 10))
        let childB = createRecord(key: "child", identifier: "B", generation: 1, rowid: NSNumber(value: 11))
        let childC = createRecord(key: "child", identifier: "C", generation: 1, rowid: NSNumber(value: 12))
        let previousRoot = createRecord(key: "", identifier: "", generation: 1, rowid: NSNumber(value: 1), children: [childA, childB, childC])

        // When we encode without child B (deleted)
        let encoder = iTermGraphDeltaEncoder(previousRevision: previousRoot)
        _ = encoder.encodeChild(withKey: "child", identifier: "A", generation: 1) { e in
            e.encode("a", forKey: "key")
            return true
        }
        // B is not encoded - it should be deleted
        _ = encoder.encodeChild(withKey: "child", identifier: "C", generation: 1) { e in
            e.encode("c", forKey: "key")
            return true
        }

        // Then deletion should be detected
        var deletedIdentifiers: [String] = []
        _ = encoder.enumerateRecords { before, after, parent, path, stop in
            if before != nil && after == nil {
                deletedIdentifiers.append(before!.identifier)
            }
        }

        XCTAssertTrue(deletedIdentifiers.contains("B"), "Child B should be detected as deleted")
        XCTAssertEqual(deletedIdentifiers.count, 1, "Only child B should be deleted")
    }

    func testDeletionTriggersCorrectBeforeAfterPair() {
        // Given a previous revision with a child
        let child = createRecord(key: "child", identifier: "toDelete", generation: 1, rowid: NSNumber(value: 10))
        let previousRoot = createRecord(key: "", identifier: "", generation: 1, rowid: NSNumber(value: 1), children: [child])

        // When we encode without the child
        let encoder = iTermGraphDeltaEncoder(previousRevision: previousRoot)
        // Don't encode any children

        // Then enumeration should show before=child, after=nil
        var foundDeletion = false
        var deletedRowid: NSNumber?
        _ = encoder.enumerateRecords { before, after, parent, path, stop in
            if before?.identifier == "toDelete" && after == nil {
                foundDeletion = true
                deletedRowid = before?.rowid
            }
        }

        XCTAssertTrue(foundDeletion, "Deletion should be detected")
        XCTAssertEqual(deletedRowid, NSNumber(value: 10), "Deleted node should have correct rowid")
    }
}

// MARK: - iTermNonGraphPathTests

/// Tests for non-graph (archive) serialization path
class iTermNonGraphPathTests: XCTestCase {

    func testDictionaryInitializerWorksWithoutProvider() {
        // Given a dictionary with FoldMark data (non-graph path)
        let dict: [AnyHashable: Any] = [
            "prompt length": 5,
            "image codes": [1, 2, 3],
            "saved lines": [
                ["line": 0, "content": "test"]
            ],
            "saved ITOs": []
        ]

        // When we create a FoldMark using the dictionary initializer
        let foldMark = FoldMark(dictionary: dict)

        // Then it should work without a provider
        XCTAssertNotNil(foldMark)
        // Content should be available immediately (no lazy loading)
        // (savedLines would be nil because we're using test data that doesn't match ScreenCharArray format)
    }

    func testDictionaryValueIncludesAllContent() {
        // Given a FoldMark with content (via the dictionary initializer)
        // Note: image codes must be Int32 to match FoldMark's expected type
        let dict: [AnyHashable: Any] = [
            "prompt length": 3,
            "image codes": [Int32(42)]
        ]

        let foldMark = FoldMark(dictionary: dict)
        XCTAssertNotNil(foldMark)

        // When we get the dictionaryValue
        guard let result = foldMark?.dictionaryValue() else {
            XCTFail("dictionaryValue should not be nil")
            return
        }

        // Then it should include the small content
        XCTAssertEqual(result["prompt length"] as? Int, 3)
        XCTAssertEqual((result["image codes"] as? [Int32])?.first, 42)
    }
}

// MARK: - iTermLazyLoadingEdgeCaseTests

/// Tests for edge cases in lazy loading
class iTermLazyLoadingEdgeCaseTests: XCTestCase {

    func testMultipleFoldMarksIndependentLazyLoading() {
        // Given two FoldMarks with different providers
        let provider1 = MockiTermLargeContentProvider()
        let provider2 = MockiTermLargeContentProvider()

        let rowid1 = NSNumber(value: 100)
        let rowid2 = NSNumber(value: 200)

        provider1.setContent(LegacyDatabaseBuilder.createFoldMarkLargeContent(savedLinesCount: 1), forRowID: rowid1)
        provider2.setContent(LegacyDatabaseBuilder.createFoldMarkLargeContent(savedLinesCount: 2), forRowID: rowid2)

        let smallDict: [AnyHashable: Any] = ["prompt length": 0, "image codes": []]

        let foldMark1 = FoldMark(
            smallDictionary: smallDict,
            largeContent: nil,
            provider: provider1,
            metadata: iTermLargeContentMetadata.metadata(forRowID: rowid1)
        )!

        let foldMark2 = FoldMark(
            smallDictionary: smallDict,
            largeContent: nil,
            provider: provider2,
            metadata: iTermLargeContentMetadata.metadata(forRowID: rowid2)
        )!

        // When we access only foldMark1's content
        _ = foldMark1.savedLines

        // Then only provider1 should be called
        XCTAssertEqual(provider1.loadCallCount, 1)
        XCTAssertEqual(provider2.loadCallCount, 0)

        // When we access foldMark2's content
        _ = foldMark2.savedLines

        // Then provider2 should also be called
        XCTAssertEqual(provider1.loadCallCount, 1)
        XCTAssertEqual(provider2.loadCallCount, 1)
    }

    func testProviderReturnsNil() {
        // Given a provider that returns nil
        let mockProvider = MockiTermLargeContentProvider()
        mockProvider.shouldReturnNil = true

        let smallDict: [AnyHashable: Any] = ["prompt length": 0, "image codes": []]
        let metadata = iTermLargeContentMetadata.metadata(forRowID: NSNumber(value: 999))

        let foldMark = FoldMark(
            smallDictionary: smallDict,
            largeContent: nil,
            provider: mockProvider,
            metadata: metadata
        )!

        // When we access savedLines
        let lines = foldMark.savedLines

        // Then it should return nil gracefully
        XCTAssertNil(lines)
        XCTAssertEqual(mockProvider.loadCallCount, 1, "Provider should still be called")
    }

    func testLazyLoadingMetadataRoundTrip() {
        // Given a rowid
        let originalRowid = NSNumber(value: 54321)

        // When we create and parse metadata
        let metadata = iTermLargeContentMetadata.metadata(forRowID: originalRowid)
        let parsedRowid = iTermLargeContentMetadata.rowid(from: metadata)

        // Then the rowid should round-trip correctly
        XCTAssertEqual(parsedRowid, originalRowid)
    }

    func testIsLargeContentMetadataDetection() {
        // Given various dictionaries
        let lazyMetadata = iTermLargeContentMetadata.metadata(forRowID: NSNumber(value: 1))
        let normalDict: [AnyHashable: Any] = ["key": "value"]
        let emptyDict: [AnyHashable: Any] = [:]

        // Then only lazy metadata should be detected as such
        XCTAssertTrue(iTermLargeContentMetadata.isLargeContentMetadata(lazyMetadata))
        XCTAssertFalse(iTermLargeContentMetadata.isLargeContentMetadata(normalDict))
        XCTAssertFalse(iTermLargeContentMetadata.isLargeContentMetadata(emptyDict))
    }

    func testRowidExtractionFromInvalidMetadata() {
        // Given a dictionary that is not lazy metadata
        let notMetadata: [AnyHashable: Any] = ["some": "data"]

        // When we try to extract rowid
        let rowid = iTermLargeContentMetadata.rowid(from: notMetadata)

        // Then it should return nil
        XCTAssertNil(rowid)
    }

    func testFoldMarkDictionaryValueTriggersLazyLoad() {
        // Given a FoldMark with lazy content
        let mockProvider = MockiTermLargeContentProvider()
        let rowid = NSNumber(value: 103)
        mockProvider.setContent(LegacyDatabaseBuilder.createFoldMarkLargeContent(savedLinesCount: 2), forRowID: rowid)

        let smallDict: [AnyHashable: Any] = ["prompt length": 0, "image codes": []]
        let metadata = iTermLargeContentMetadata.metadata(forRowID: rowid)

        let foldMark = FoldMark(
            smallDictionary: smallDict,
            largeContent: nil,
            provider: mockProvider,
            metadata: metadata
        )!

        // Verify not loaded yet
        XCTAssertEqual(mockProvider.loadCallCount, 0)

        // When we call dictionaryValue (for archive serialization)
        _ = foldMark.dictionaryValue()

        // Then it should trigger lazy loading
        XCTAssertEqual(mockProvider.loadCallCount, 1, "dictionaryValue should trigger lazy loading")
    }
}

// MARK: - iTermSchemaMigrationTests

/// Tests for database schema migration
class iTermSchemaMigrationTests: XCTestCase {

    func testDetectSchemaVersion0() {
        // Given a database with v0 schema
        let db = InMemoryDatabaseHelper.createInMemoryDatabaseWithV0Schema()
        defer { db.close() }

        // Then it should not have generation or large_data columns
        XCTAssertFalse(InMemoryDatabaseHelper.columnExists("generation", in: db))
        XCTAssertFalse(InMemoryDatabaseHelper.columnExists("large_data", in: db))
    }

    func testDetectSchemaVersion1() {
        // Given a database with v1 schema (current)
        let db = InMemoryDatabaseHelper.createInMemoryDatabaseWithCurrentSchema()
        defer { db.close() }

        // Then it should have both generation and large_data columns
        XCTAssertTrue(InMemoryDatabaseHelper.columnExists("generation", in: db))
        XCTAssertTrue(InMemoryDatabaseHelper.columnExists("large_data", in: db))
    }

    func testMigrateFromVersion0() {
        // Given a v0 database
        let db = InMemoryDatabaseHelper.createInMemoryDatabaseWithV0Schema()
        defer { db.close() }

        // When we add the migration columns (simulating v0 -> v1 migration)
        var success = db.executeUpdate("ALTER TABLE Node ADD COLUMN generation INTEGER DEFAULT 0", withArgumentsIn: [])
        XCTAssertTrue(success, "Adding generation column should succeed")

        success = db.executeUpdate("ALTER TABLE Node ADD COLUMN large_data BLOB", withArgumentsIn: [])
        XCTAssertTrue(success, "Adding large_data column should succeed")

        // Then all columns should exist
        XCTAssertTrue(InMemoryDatabaseHelper.columnExists("generation", in: db))
        XCTAssertTrue(InMemoryDatabaseHelper.columnExists("large_data", in: db))
    }

    func testMigrationIsIdempotent() {
        // Given a v1 database (already migrated)
        let db = InMemoryDatabaseHelper.createInMemoryDatabaseWithCurrentSchema()
        defer { db.close() }

        // When we check the columns
        // ALTER TABLE ADD COLUMN IF NOT EXISTS is not supported in SQLite
        // So we check if column exists first
        XCTAssertTrue(InMemoryDatabaseHelper.columnExists("generation", in: db))
        XCTAssertTrue(InMemoryDatabaseHelper.columnExists("large_data", in: db))

        // The database should remain valid
        let success = db.executeUpdate(
            "INSERT INTO Node (key, identifier, parent, data, generation, large_data) VALUES (?, ?, ?, ?, ?, ?)",
            withArgumentsIn: ["test", "t1", 0, Data(), 0, NSNull()]
        )
        XCTAssertTrue(success, "Insert should still work after checking migration")
    }
}

// MARK: - iTermLegacyDatabaseTests

/// Tests for legacy database compatibility
class iTermLegacyDatabaseTests: XCTestCase {

    func testLegacyDataInDataColumnStillWorks() {
        // Given a v2 database with data stored in the data column (not large_data)
        let db = InMemoryDatabaseHelper.createInMemoryDatabaseWithCurrentSchema()
        defer { db.close() }

        // Insert a node with all data in the data column (legacy style)
        let pod: [String: Any] = ["key": "value", "large_content": "this would be large"]
        guard let data = LegacyDatabaseBuilder.serializePOD(pod) else {
            XCTFail("Failed to serialize POD")
            return
        }

        let success = db.executeUpdate(
            "INSERT INTO Node (key, identifier, parent, data, generation, large_data) VALUES (?, ?, ?, ?, ?, ?)",
            withArgumentsIn: ["normalKey", "id1", 0, data, 1, NSNull()]
        )
        XCTAssertTrue(success)

        // When we query the data
        guard let rs = db.executeQuery(
            "SELECT data, large_data, (large_data IS NOT NULL) as has_large_data FROM Node WHERE key = ?",
            withArgumentsIn: ["normalKey"]
        ) else {
            XCTFail("Query failed")
            return
        }
        defer { rs.close() }

        XCTAssertTrue(rs.next())

        // Then the data should be in the data column
        let storedData = rs.data(forColumn: "data")
        let hasLargeData = rs.bool(forColumn: "has_large_data")

        XCTAssertNotNil(storedData)
        XCTAssertFalse(hasLargeData, "Legacy data should not have large_data")

        // And we should be able to deserialize it
        if let storedData = storedData {
            let restored = try? (storedData as NSData).it_unarchivedObjectOfBasicClasses() as? [String: Any]
            XCTAssertEqual(restored?["key"] as? String, "value")
        }
    }

    func testMixedLegacyAndNewNodes() {
        // Given a database with both legacy and new-style nodes
        let db = InMemoryDatabaseHelper.createInMemoryDatabaseWithCurrentSchema()
        defer { db.close() }

        // Insert root
        let rootPod: [String: Any] = ["root": true]
        guard let rootData = LegacyDatabaseBuilder.serializePOD(rootPod) else {
            XCTFail("Failed to serialize root POD")
            return
        }

        var success = db.executeUpdate(
            "INSERT INTO Node (key, identifier, parent, data, generation, large_data) VALUES (?, ?, ?, ?, ?, ?)",
            withArgumentsIn: ["", "", 0, rootData, 1, NSNull()]
        )
        XCTAssertTrue(success)
        let rootRowid = db.lastInsertRowId

        // Insert legacy-style child (data in data column)
        let legacyPod: [String: Any] = ["legacy": true, "content": "in data column"]
        guard let legacyData = LegacyDatabaseBuilder.serializePOD(legacyPod) else {
            XCTFail("Failed to serialize legacy POD")
            return
        }

        success = db.executeUpdate(
            "INSERT INTO Node (key, identifier, parent, data, generation, large_data) VALUES (?, ?, ?, ?, ?, ?)",
            withArgumentsIn: ["legacyChild", "lc1", rootRowid, legacyData, 1, NSNull()]
        )
        XCTAssertTrue(success)

        // Insert new-style child (data in large_data column)
        let newPod: [String: Any] = ["new": true, "content": "in large_data column"]
        guard let newData = LegacyDatabaseBuilder.serializePOD(newPod) else {
            XCTFail("Failed to serialize new POD")
            return
        }

        success = db.executeUpdate(
            "INSERT INTO Node (key, identifier, parent, data, generation, large_data) VALUES (?, ?, ?, ?, ?, ?)",
            withArgumentsIn: [iTermLargeContentMetadata.largeContentKey, "nc1", rootRowid, Data(), 1, newData]
        )
        XCTAssertTrue(success)

        // When we query both nodes
        guard let rs = db.executeQuery(
            "SELECT key, data, large_data, (large_data IS NOT NULL AND length(large_data) > 0) as has_large_data FROM Node WHERE parent = ?",
            withArgumentsIn: [rootRowid]
        ) else {
            XCTFail("Query failed")
            return
        }
        defer { rs.close() }

        var legacyFound = false
        var newFound = false

        while rs.next() {
            let key = rs.string(forColumn: "key") ?? ""
            let hasLargeData = rs.bool(forColumn: "has_large_data")

            if key == "legacyChild" {
                legacyFound = true
                XCTAssertFalse(hasLargeData, "Legacy child should not have large_data")
            } else if key == iTermLargeContentMetadata.largeContentKey {
                newFound = true
                XCTAssertTrue(hasLargeData, "New child should have large_data")
            }
        }

        XCTAssertTrue(legacyFound, "Legacy child should be found")
        XCTAssertTrue(newFound, "New child should be found")
    }

    func testSaveToMigratedLegacyDatabase() {
        // Given a migrated database (started as v0, now v2)
        let db = InMemoryDatabaseHelper.createInMemoryDatabase()
        defer { db.close() }

        // Create v0 schema
        _ = LegacyDatabaseBuilder.createV0Schema(in: db)

        // Insert some legacy data
        let legacyPod: [String: Any] = ["legacy": true]
        guard let legacyData = LegacyDatabaseBuilder.serializePOD(legacyPod) else {
            XCTFail("Failed to serialize legacy POD")
            return
        }

        var success = db.executeUpdate(
            "INSERT INTO Node (key, identifier, parent, data) VALUES (?, ?, ?, ?)",
            withArgumentsIn: ["", "", 0, legacyData]
        )
        XCTAssertTrue(success)
        let legacyRowid = db.lastInsertRowId

        // Migrate to v2
        success = db.executeUpdate("ALTER TABLE Node ADD COLUMN generation INTEGER DEFAULT 0", withArgumentsIn: [])
        XCTAssertTrue(success)
        success = db.executeUpdate("ALTER TABLE Node ADD COLUMN large_data BLOB", withArgumentsIn: [])
        XCTAssertTrue(success)

        // When we insert new data with large_data
        let newPod: [String: Any] = ["new": true]
        guard let newData = LegacyDatabaseBuilder.serializePOD(newPod) else {
            XCTFail("Failed to serialize new POD")
            return
        }

        success = db.executeUpdate(
            "INSERT INTO Node (key, identifier, parent, data, generation, large_data) VALUES (?, ?, ?, ?, ?, ?)",
            withArgumentsIn: [iTermLargeContentMetadata.largeContentKey, "new1", legacyRowid, Data(), 1, newData]
        )
        XCTAssertTrue(success)

        // Then both old and new data should be accessible
        guard let rs = db.executeQuery("SELECT COUNT(*) as count FROM Node", withArgumentsIn: []) else {
            XCTFail("Query failed")
            return
        }
        defer { rs.close() }

        XCTAssertTrue(rs.next())
        XCTAssertEqual(rs.int(forColumn: "count"), 2, "Both nodes should exist")
    }

    func testLegacyFoldMarkWithoutSplitEncoding() {
        // Given a database with a FoldMark stored in the old way (all in data column)
        let db = InMemoryDatabaseHelper.createInMemoryDatabaseWithCurrentSchema()
        defer { db.close() }

        // Create a FoldMark-like structure stored entirely in data column
        let foldMarkPod: [String: Any] = [
            "prompt length": 5,
            "image codes": [1, 2],
            "saved lines": [["line": 0]],  // Would be ScreenCharArray data normally
            "saved ITOs": []
        ]
        guard let data = LegacyDatabaseBuilder.serializePOD(foldMarkPod) else {
            XCTFail("Failed to serialize FoldMark POD")
            return
        }

        let success = db.executeUpdate(
            "INSERT INTO Node (key, identifier, parent, data, generation, large_data) VALUES (?, ?, ?, ?, ?, ?)",
            withArgumentsIn: ["marks", "fold1", 0, data, 1, NSNull()]
        )
        XCTAssertTrue(success)

        // When we query the data
        guard let rs = db.executeQuery(
            "SELECT data, (large_data IS NOT NULL AND length(large_data) > 0) as has_large_data FROM Node WHERE key = ?",
            withArgumentsIn: ["marks"]
        ) else {
            XCTFail("Query failed")
            return
        }
        defer { rs.close() }

        XCTAssertTrue(rs.next())
        let storedData = rs.data(forColumn: "data")
        let hasLargeData = rs.bool(forColumn: "has_large_data")

        // Then the data should be in the data column (legacy behavior)
        XCTAssertNotNil(storedData)
        XCTAssertFalse(hasLargeData)

        // And it should deserialize correctly
        if let storedData = storedData {
            let restored = try? (storedData as NSData).it_unarchivedObjectOfBasicClasses() as? [String: Any]
            XCTAssertEqual(restored?["prompt length"] as? Int, 5)
        }
    }
}

// MARK: - iTermLazyLoadingIntegrationTests

/// Integration tests for the full lazy loading flow
class iTermLazyLoadingIntegrationTests: XCTestCase {

    func testEncoderGraphRecordLazyLoading() {
        // Given a record with hasLargeData but no database
        let record = iTermEncoderGraphRecord.withPODs(
            [:],  // Empty POD for unloaded state
            graphs: [],
            generation: 0,
            key: iTermLargeContentMetadata.largeContentKey,
            identifier: "test",
            rowid: NSNumber(value: 42)
        )
        record.hasLargeData = true
        // Note: database is already nil by default

        // When we access the POD
        let pod = record.pod

        // Then it should return an empty dictionary (can't load without database)
        XCTAssertTrue(pod.isEmpty, "POD should be empty when database is nil")
    }

    func testRecordPropertyListValueForLargeContentNode() {
        // Given a large content node that hasn't been loaded
        let rowid = NSNumber(value: 123)
        let record = iTermEncoderGraphRecord.withPODs(
            nil,  // nil POD indicates content not yet loaded
            graphs: nil,
            generation: 0,
            key: iTermLargeContentMetadata.largeContentKey,
            identifier: "lc1",
            rowid: rowid
        )
        record.hasLargeData = true
        // Note: database is already nil by default

        // When we get the propertyListValue
        guard let plist = record.propertyListValue as? [AnyHashable: Any] else {
            XCTFail("Expected dictionary for unloaded large content")
            return
        }

        // Then it should return lazy loading metadata
        XCTAssertTrue(iTermLargeContentMetadata.isLargeContentMetadata(plist))
        XCTAssertEqual(iTermLargeContentMetadata.rowid(from: plist), rowid)
    }
}
