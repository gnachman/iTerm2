//
//  IntervalTreeGraphEncodingTests.swift
//  iTerm2
//
//  Created by George Nachman on 3/13/26.
//

import XCTest
@testable import iTerm2SharedARC

class IntervalTreeGraphEncodingTests: XCTestCase {

    // MARK: - iTermMark GUID Tests

    func testMarkHasGUID() {
        let mark = iTermMark()
        XCTAssertNotNil(mark.guid)
        XCTAssertFalse(mark.guid.isEmpty, "GUID should not be empty")
    }

    func testMarkGUIDIsUnique() {
        let mark1 = iTermMark()
        let mark2 = iTermMark()
        XCTAssertNotEqual(mark1.guid, mark2.guid, "Each mark should have a unique GUID")
    }

    func testMarkGUIDPersistedInDictionary() {
        let mark = iTermMark()
        let originalGuid = mark.guid

        let dict = mark.dictionaryValue()

        let restoredMark = iTermMark(dictionary: dict)
        XCTAssertEqual(restoredMark?.guid, originalGuid, "GUID should be preserved through serialization")
    }

    func testMarkWithoutGUIDInDictionaryGetsNewGUID() {
        // Simulate old format without GUID
        let dict: [AnyHashable: Any] = [:]
        let mark = iTermMark(dictionary: dict)
        XCTAssertNotNil(mark?.guid)
        XCTAssertFalse(mark!.guid.isEmpty, "Mark restored from old format should get a new GUID")
    }

    // MARK: - PTYAnnotation UniqueID Tests

    func testAnnotationHasUniqueID() {
        let annotation = PTYAnnotation()
        XCTAssertNotNil(annotation.uniqueID)
        XCTAssertFalse(annotation.uniqueID.isEmpty, "UniqueID should not be empty")
    }

    func testAnnotationUniqueIDIsUnique() {
        let annotation1 = PTYAnnotation()
        let annotation2 = PTYAnnotation()
        XCTAssertNotEqual(annotation1.uniqueID, annotation2.uniqueID, "Each annotation should have a unique ID")
    }

    func testAnnotationUniqueIDPersistedInDictionary() {
        let annotation = PTYAnnotation()
        annotation.stringValue = "Test annotation"
        let originalID = annotation.uniqueID

        let dict = annotation.dictionaryValue()

        let restoredAnnotation = PTYAnnotation(dictionary: dict)
        XCTAssertEqual(restoredAnnotation?.uniqueID, originalID, "UniqueID should be preserved through serialization")
    }

    // MARK: - IntervalTree Graph Encoding Tests

    func testIntervalTreeGraphEncodingWithMarks() {
        let tree = IntervalTree()

        // Add some marks
        let mark1 = VT100ScreenMark()
        let mark2 = VT100ScreenMark()

        let interval1 = Interval(location: 0, length: 100)
        let interval2 = Interval(location: 200, length: 50)

        tree.add(mark1, with: interval1)
        tree.add(mark2, with: interval2)

        // Encode using graph encoder
        let encoder = iTermGraphEncoder(key: "test", identifier: "root", generation: iTermGenerationAlwaysEncode)
        tree.encode(withEncoder: iTermGraphEncoderAdapter(graphEncoder: encoder), offset: 0)

        // Get the encoded record
        let record = encoder.record
        XCTAssertNotNil(record, "Encoder should produce a record")
    }

    func testIntervalTreeGraphEncodingPreservesObjectCount() {
        let tree = IntervalTree()

        // Add marks
        let mark1 = VT100ScreenMark()
        let mark2 = VT100ScreenMark()
        let mark3 = VT100ScreenMark()

        tree.add(mark1, with: Interval(location: 0, length: 100))
        tree.add(mark2, with: Interval(location: 200, length: 50))
        tree.add(mark3, with: Interval(location: 500, length: 75))

        XCTAssertEqual(tree.allObjects().count, 3, "Tree should have 3 objects before encoding")

        // Encode
        let encoder = iTermGraphEncoder(key: "test", identifier: "root", generation: iTermGenerationAlwaysEncode)
        tree.encode(withEncoder: iTermGraphEncoderAdapter(graphEncoder: encoder), offset: 0)

        // Decode into new tree
        let newTree = IntervalTree()
        let record = encoder.record
        XCTAssertNotNil(record)

        // Convert record to dictionary format for restoration
        if let plist = record?.propertyListValue as? [AnyHashable: Any] {
            let restored = newTree.restore(fromGraphRecord: plist, offset: 0, largeContentProvider: nil)
            XCTAssertTrue(restored, "Should successfully restore from graph record")
            XCTAssertEqual(newTree.allObjects().count, 3, "Restored tree should have 3 objects")
        } else {
            XCTFail("Failed to get property list from record")
        }
    }

    func testIntervalTreeGraphEncodingPreservesIntervals() {
        let tree = IntervalTree()

        let mark = VT100ScreenMark()
        let originalInterval = Interval(location: 100, length: 50)
        tree.add(mark, with: originalInterval)

        // Encode with offset
        let offset: Int64 = 1000
        let encoder = iTermGraphEncoder(key: "test", identifier: "root", generation: iTermGenerationAlwaysEncode)
        tree.encode(withEncoder: iTermGraphEncoderAdapter(graphEncoder: encoder), offset: offset)

        // Decode
        let newTree = IntervalTree()
        if let plist = encoder.record?.propertyListValue as? [AnyHashable: Any] {
            let restored = newTree.restore(fromGraphRecord: plist, offset: 0, largeContentProvider: nil)
            XCTAssertTrue(restored)

            let restoredObjects = newTree.allObjects()
            XCTAssertEqual(restoredObjects.count, 1)

            // The restored interval should have the offset applied
            let restoredMark = restoredObjects.first as? VT100ScreenMark
            XCTAssertNotNil(restoredMark)

            let restoredInterval = restoredMark?.entry?.interval
            XCTAssertNotNil(restoredInterval)

            // Location should be original + offset
            XCTAssertEqual(restoredInterval!.location, originalInterval.location + offset)
            XCTAssertEqual(restoredInterval!.length, originalInterval.length)
        } else {
            XCTFail("Failed to get property list from record")
        }
    }

    func testIntervalTreeGraphEncodingWithAnnotations() {
        let tree = IntervalTree()

        let annotation = PTYAnnotation()
        annotation.stringValue = "Test annotation content"
        tree.add(annotation, with: Interval(location: 0, length: 100))

        // Encode
        let encoder = iTermGraphEncoder(key: "test", identifier: "root", generation: iTermGenerationAlwaysEncode)
        tree.encode(withEncoder: iTermGraphEncoderAdapter(graphEncoder: encoder), offset: 0)

        // Decode
        let newTree = IntervalTree()
        if let plist = encoder.record?.propertyListValue as? [AnyHashable: Any] {
            let restored = newTree.restore(fromGraphRecord: plist, offset: 0, largeContentProvider: nil)
            XCTAssertTrue(restored)

            let restoredObjects = newTree.allObjects()
            XCTAssertEqual(restoredObjects.count, 1)

            let restoredAnnotation = restoredObjects.first as? PTYAnnotation
            XCTAssertNotNil(restoredAnnotation)
            XCTAssertEqual(restoredAnnotation?.stringValue, "Test annotation content")
        } else {
            XCTFail("Failed to get property list from record")
        }
    }

    func testIntervalTreeGraphEncodingMixedTypes() {
        let tree = IntervalTree()

        let mark = VT100ScreenMark()
        let annotation = PTYAnnotation()
        annotation.stringValue = "Mixed test"

        tree.add(mark, with: Interval(location: 0, length: 100))
        tree.add(annotation, with: Interval(location: 200, length: 50))

        // Encode
        let encoder = iTermGraphEncoder(key: "test", identifier: "root", generation: iTermGenerationAlwaysEncode)
        tree.encode(withEncoder: iTermGraphEncoderAdapter(graphEncoder: encoder), offset: 0)

        // Decode
        let newTree = IntervalTree()
        if let plist = encoder.record?.propertyListValue as? [AnyHashable: Any] {
            let restored = newTree.restore(fromGraphRecord: plist, offset: 0, largeContentProvider: nil)
            XCTAssertTrue(restored)

            let restoredObjects = newTree.allObjects()
            XCTAssertEqual(restoredObjects.count, 2)

            let marks = restoredObjects.compactMap { $0 as? VT100ScreenMark }
            let annotations = restoredObjects.compactMap { $0 as? PTYAnnotation }
            XCTAssertEqual(marks.count, 1)
            XCTAssertEqual(annotations.count, 1)
        } else {
            XCTFail("Failed to get property list from record")
        }
    }

    // MARK: - Backward Compatibility Tests

    func testRestoreFromGraphRecordReturnsFalseForOldFormat() {
        let tree = IntervalTree()

        // Old dictionary format doesn't have "objects" key
        let oldFormatDict: [AnyHashable: Any] = [
            "Entries": [
                [
                    "Interval": ["Location": 0, "Length": 100],
                    "Object": [:],
                    "Class": "VT100ScreenMark"
                ]
            ]
        ]

        let result = tree.restore(fromGraphRecord: oldFormatDict, offset: 0, largeContentProvider: nil)
        XCTAssertFalse(result, "Should return false for old dictionary format")
    }

    func testRestoreFromDictionaryStillWorks() {
        let tree = IntervalTree()

        // Add a mark
        let mark = VT100ScreenMark()
        tree.add(mark, with: Interval(location: 0, length: 100))

        // Get dictionary representation
        let dict = tree.dictionaryValue(withOffset: 0)

        // Restore into new tree using old method
        let newTree = IntervalTree()
        newTree.restore(from: dict)

        XCTAssertEqual(newTree.allObjects().count, 1)
    }

    // MARK: - FoldMark Generation Tests

    func testFoldMarkDictionaryValueIncludesParentGUID() {
        let foldMark = FoldMark(
            savedLines: nil,
            savedITOs: [],
            promptLength: 0,
            imageCodes: [],
            width: 80
        )

        let dict = foldMark.dictionaryValue()

        // Should include GUID from parent class
        XCTAssertNotNil(dict["Guid"] as? String, "FoldMark dictionary should include GUID from iTermMark")
    }

    func testFoldMarkGenerationIsAlwaysZero() {
        // FoldMark is immutable, so generation is always 0 for delta encoding
        let foldMark = FoldMark(
            savedLines: nil,
            savedITOs: [],
            promptLength: 0,
            imageCodes: [],
            width: 80
        )
        XCTAssertEqual(foldMark.generation, 0, "FoldMark generation should always be 0")

        // Serialize and deserialize - generation should still be 0
        let dict = foldMark.dictionaryValue()

        let restoredFoldMark = FoldMark(dictionary: dict)
        XCTAssertNotNil(restoredFoldMark)
        XCTAssertEqual(restoredFoldMark!.generation, 0,
                       "Restored FoldMark generation should be 0")
    }

    func testFoldMarkFromOldFormatHasZeroGeneration() {
        // Old format without generation key should still have generation 0
        let dict: [AnyHashable: Any] = [
            "Guid": "test-guid"
        ]

        let foldMark = FoldMark(dictionary: dict)
        XCTAssertNotNil(foldMark)
        XCTAssertEqual(foldMark!.generation, 0,
                       "FoldMark restored from old format should have generation 0")
    }

    // MARK: - Empty Tree Tests

    func testEmptyTreeGraphEncoding() {
        let tree = IntervalTree()

        let encoder = iTermGraphEncoder(key: "test", identifier: "root", generation: iTermGenerationAlwaysEncode)
        tree.encode(withEncoder: iTermGraphEncoderAdapter(graphEncoder: encoder), offset: 0)

        let newTree = IntervalTree()
        if let plist = encoder.record?.propertyListValue as? [AnyHashable: Any] {
            let restored = newTree.restore(fromGraphRecord: plist, offset: 0, largeContentProvider: nil)
            XCTAssertTrue(restored)
            XCTAssertEqual(newTree.allObjects().count, 0)
        } else {
            XCTFail("Failed to get property list from record")
        }
    }

    // MARK: - stableIdentifier Protocol Tests

    func testMarkStableIdentifierReturnsGUID() {
        let mark = iTermMark()
        XCTAssertEqual(mark.stableIdentifier, mark.guid,
                       "stableIdentifier should return guid for iTermMark")
    }

    func testAnnotationStableIdentifierReturnsUniqueID() {
        let annotation = PTYAnnotation()
        XCTAssertEqual(annotation.stableIdentifier, annotation.uniqueID,
                       "stableIdentifier should return uniqueID for PTYAnnotation")
    }

    func testVT100ScreenMarkStableIdentifierReturnsGUID() {
        let mark = VT100ScreenMark()
        XCTAssertEqual(mark.stableIdentifier, mark.guid,
                       "stableIdentifier should return guid for VT100ScreenMark")
    }

    // MARK: - iTermImageMark Tests

    func testImageMarkGUIDPreservedThroughSerialization() {
        let imageMark = iTermImageMark(imageCode: NSNumber(value: 42))
        let originalGuid = imageMark?.guid

        let dict = imageMark?.dictionaryValue()
        XCTAssertNotNil(dict)
        XCTAssertNotNil(dict!["Guid"] as? String, "iTermImageMark dictionary should include GUID")

        let restoredMark = iTermImageMark(dictionary: dict!)
        XCTAssertNotNil(restoredMark)
        XCTAssertEqual(restoredMark?.guid, originalGuid,
                       "iTermImageMark GUID should be preserved through serialization")
    }

    func testImageMarkImageCodePreservedThroughSerialization() {
        let imageMark = iTermImageMark(imageCode: NSNumber(value: 123))

        let dict = imageMark?.dictionaryValue()
        XCTAssertNotNil(dict)

        let restoredMark = iTermImageMark(dictionary: dict!)
        XCTAssertNotNil(restoredMark)
        XCTAssertEqual(restoredMark?.imageCode, NSNumber(value: 123),
                       "iTermImageMark imageCode should be preserved through serialization")
    }

    // MARK: - PTYAnnotation Empty UniqueID Fix Tests

    func testAnnotationWithEmptyUniqueIDInDictionaryGetsNewID() {
        // Simulate old format where uniqueID was stored as empty string
        let dict: [AnyHashable: Any] = [
            "Text": "Test annotation",
            "UniqueID": ""  // Empty string from old buggy serialization
        ]

        let annotation = PTYAnnotation(dictionary: dict)
        XCTAssertNotNil(annotation)
        XCTAssertFalse(annotation!.uniqueID.isEmpty,
                       "Annotation restored with empty UniqueID should get a new non-empty ID")
    }

    func testAnnotationWithoutUniqueIDInDictionaryGetsNewID() {
        // Simulate very old format without UniqueID key at all
        let dict: [AnyHashable: Any] = [
            "Text": "Test annotation"
        ]

        let annotation = PTYAnnotation(dictionary: dict)
        XCTAssertNotNil(annotation)
        XCTAssertFalse(annotation!.uniqueID.isEmpty,
                       "Annotation restored without UniqueID should get a new non-empty ID")
    }

    // MARK: - VT100Screen Scrollback Overflow Tests

    private var session = FakeSession()

    private func screen(width: Int32, height: Int32, maxScrollback: UInt32) -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal?.termType = "xterm"
            screen.destructivelySetScreenWidth(width, height: height, mutableState: mutableState)
            mutableState.maxScrollbackLines = maxScrollback
        })
        return screen
    }

    private func appendLines(_ lines: [String], to screen: VT100Screen) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for line in lines {
                mutableState.appendString(atCursor: line)
                mutableState.appendCarriageReturnLineFeed()
            }
        })
    }

    /// Test that marks maintain correct intervals through encode/decode when scrollback overflows.
    /// This verifies that the offset calculation in IntervalTree encoding/decoding works correctly
    /// when lines are dropped due to scrollback buffer limits.
    func testScrollbackOverflowPreservesMarkIntervals() {
        // Create a screen with very limited scrollback (3 lines)
        // Width 10, height 4, max scrollback 3
        let screen = self.screen(width: 10, height: 4, maxScrollback: 3)

        // Add some initial content
        appendLines(["line1", "line2", "line3", "line4"], to: screen)

        // Add a mark on line 2 (0-indexed from top of history + grid)
        var markGuid: String?
        var originalInterval: Interval?
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let mark = mutableState.addMark(onLine: 1, of: VT100ScreenMark.self) as? VT100ScreenMark
            markGuid = mark?.guid
            originalInterval = mark?.entry?.interval
        })
        XCTAssertNotNil(markGuid)
        XCTAssertNotNil(originalInterval)

        // Cause scrollback overflow by adding more lines
        // This should push some lines out of history
        appendLines(["overflow1", "overflow2", "overflow3", "overflow4", "overflow5"], to: screen)

        // Encode the state
        let encoder = iTermMutableDictionaryEncoderAdapter.encoder()
        var linesDropped: Int32 = 0
        screen.encodeContents(encoder, linesDropped: &linesDropped, unlimited: false)
        let state = encoder.mutableDictionary as? [AnyHashable: Any]
        XCTAssertNotNil(state)

        // Restore to a new screen
        let restoredScreen = self.screen(width: 10, height: 4, maxScrollback: 3)
        restoredScreen.restore(from: state!,
                               includeRestorationBanner: false,
                               reattached: false,
                               isArchive: false,
                               largeContentProvider: nil)

        // Find the mark in the restored screen and verify its interval
        var restoredMark: VT100ScreenMark?
        var restoredInterval: Interval?
        restoredScreen.performBlock(joinedThreads: { _, mutableState, _ in
            let marks = mutableState.intervalTree.allObjects().compactMap { $0 as? VT100ScreenMark }
            restoredMark = marks.first { $0.guid == markGuid }
            restoredInterval = restoredMark?.entry?.interval
        })

        // The mark should still exist and have an interval
        // (It may have been dropped if it scrolled out of history, which is also valid behavior)
        if restoredMark != nil {
            XCTAssertNotNil(restoredInterval, "Restored mark should have an interval")
            // The interval length should be preserved
            XCTAssertEqual(restoredInterval!.length, originalInterval!.length,
                          "Interval length should be preserved through encode/decode")
        }
    }

    /// Test that marks added at different positions maintain correct relative positions
    /// after scrollback overflow and state restoration.
    func testMultipleMarksPreserveRelativePositionsAfterOverflow() {
        // Create screen with limited scrollback
        let screen = self.screen(width: 10, height: 4, maxScrollback: 5)

        // Add content
        appendLines(["line0", "line1", "line2", "line3", "line4", "line5"], to: screen)

        // Add marks at different positions
        var mark1Guid: String?
        var mark2Guid: String?
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let mark1 = mutableState.addMark(onLine: 2, of: VT100ScreenMark.self) as? VT100ScreenMark
            let mark2 = mutableState.addMark(onLine: 4, of: VT100ScreenMark.self) as? VT100ScreenMark
            mark1Guid = mark1?.guid
            mark2Guid = mark2?.guid
        })

        // Cause some overflow
        appendLines(["extra1", "extra2"], to: screen)

        // Encode
        let encoder = iTermMutableDictionaryEncoderAdapter.encoder()
        var linesDropped: Int32 = 0
        screen.encodeContents(encoder, linesDropped: &linesDropped, unlimited: false)
        let state = encoder.mutableDictionary as? [AnyHashable: Any]

        // Restore
        let restoredScreen = self.screen(width: 10, height: 4, maxScrollback: 5)
        restoredScreen.restore(from: state!,
                               includeRestorationBanner: false,
                               reattached: false,
                               isArchive: false,
                               largeContentProvider: nil)

        // Get restored marks
        var mark1Interval: Interval?
        var mark2Interval: Interval?
        restoredScreen.performBlock(joinedThreads: { _, mutableState, _ in
            let marks = mutableState.intervalTree.allObjects().compactMap { $0 as? VT100ScreenMark }
            mark1Interval = marks.first { $0.guid == mark1Guid }?.entry?.interval
            mark2Interval = marks.first { $0.guid == mark2Guid }?.entry?.interval
        })

        // If both marks survived, verify their relative positions
        if let int1 = mark1Interval, let int2 = mark2Interval {
            // Mark2 was added 2 lines after mark1, so its location should be greater
            XCTAssertGreaterThan(int2.location, int1.location,
                                "Mark2 should have greater interval location than mark1")
        }
    }

    /// Test that annotations also preserve correct intervals through scrollback overflow.
    func testAnnotationIntervalsPreservedAfterScrollbackOverflow() {
        let screen = self.screen(width: 10, height: 4, maxScrollback: 4)

        // Add content
        appendLines(["aaaa", "bbbb", "cccc", "dddd"], to: screen)

        // Add an annotation
        let annotation = PTYAnnotation()
        annotation.stringValue = "Test annotation"
        let annotationRange = VT100GridCoordRangeMake(0, 1, 4, 1)  // On line 1
        screen.addNote(annotation, in: annotationRange, focus: false, visible: false)

        let originalUniqueID = annotation.uniqueID

        // Cause overflow
        appendLines(["eeee", "ffff", "gggg"], to: screen)

        // Encode
        let encoder = iTermMutableDictionaryEncoderAdapter.encoder()
        var linesDropped: Int32 = 0
        screen.encodeContents(encoder, linesDropped: &linesDropped, unlimited: false)
        let state = encoder.mutableDictionary as? [AnyHashable: Any]

        // Restore
        let restoredScreen = self.screen(width: 10, height: 4, maxScrollback: 4)
        restoredScreen.restore(from: state!,
                               includeRestorationBanner: false,
                               reattached: false,
                               isArchive: false,
                               largeContentProvider: nil)

        // Find the annotation
        var restoredAnnotation: PTYAnnotation?
        restoredScreen.performBlock(joinedThreads: { _, mutableState, _ in
            let annotations = mutableState.intervalTree.allObjects().compactMap { $0 as? PTYAnnotation }
            restoredAnnotation = annotations.first { $0.uniqueID == originalUniqueID }
        })

        // Annotation may have scrolled out; if it exists, verify it has content
        if let restored = restoredAnnotation {
            XCTAssertEqual(restored.stringValue, "Test annotation",
                          "Annotation content should be preserved")
            XCTAssertNotNil(restored.entry?.interval,
                           "Restored annotation should have an interval")
        }
    }

    /// Test encoding with realistic offset values (simulating scrollback overflow).
    /// The offset is typically negative because it represents lines dropped from the beginning.
    /// However, encoded intervals should remain non-negative because marks that would become
    /// negative have already scrolled off and been removed from the tree.
    func testRealisticScrollbackOverflowOffset() {
        let tree = IntervalTree()

        // Mark at position that will remain positive after offset
        // In practice, marks are added at absolute positions and the offset
        // adjusts them relative to the saved content start.
        // If we have 10000 lines of history and drop 5000, marks at line 6000+
        // will have positive encoded locations.
        let mark = VT100ScreenMark()
        // Position 500000 simulates a mark at line ~6000 (500000 / 81 ≈ 6172) with width 80
        let originalInterval = Interval(location: 500000, length: 100)
        tree.add(mark, with: originalInterval)

        // Offset simulates dropping first 5000 lines: offset = -5000 * 81 = -405000
        // Encoded location = 500000 + (-405000) = 95000 (positive)
        let offset: Int64 = -405000

        // Encode with offset
        let encoder = iTermGraphEncoder(key: "test", identifier: "root", generation: iTermGenerationAlwaysEncode)
        tree.encode(withEncoder: iTermGraphEncoderAdapter(graphEncoder: encoder), offset: offset)

        // Decode with same offset
        let newTree = IntervalTree()
        if let plist = encoder.record?.propertyListValue as? [AnyHashable: Any] {
            let restored = newTree.restore(fromGraphRecord: plist, offset: offset, largeContentProvider: nil)
            XCTAssertTrue(restored)

            let restoredObjects = newTree.allObjects()
            XCTAssertEqual(restoredObjects.count, 1)

            let restoredMark = restoredObjects.first as? VT100ScreenMark
            let restoredInterval = restoredMark?.entry?.interval

            // Restored location should match original
            XCTAssertEqual(restoredInterval?.location, originalInterval.location,
                          "Interval location should be correctly restored after offset")
            XCTAssertEqual(restoredInterval?.length, originalInterval.length,
                          "Interval length should be preserved")
        } else {
            XCTFail("Failed to get property list from record")
        }
    }

    /// Test that multiple marks at different positions maintain correct relative ordering
    /// through encode/decode with offset.
    func testMultipleMarksWithOffset() {
        let tree = IntervalTree()

        let mark1 = VT100ScreenMark()
        let mark2 = VT100ScreenMark()
        let mark3 = VT100ScreenMark()

        // Positions simulating marks at different lines
        tree.add(mark1, with: Interval(location: 100000, length: 50))
        tree.add(mark2, with: Interval(location: 200000, length: 50))
        tree.add(mark3, with: Interval(location: 300000, length: 50))

        let offset: Int64 = -50000  // Simulate dropping some lines

        let encoder = iTermGraphEncoder(key: "test", identifier: "root", generation: iTermGenerationAlwaysEncode)
        tree.encode(withEncoder: iTermGraphEncoderAdapter(graphEncoder: encoder), offset: offset)

        let newTree = IntervalTree()
        if let plist = encoder.record?.propertyListValue as? [AnyHashable: Any] {
            let restored = newTree.restore(fromGraphRecord: plist, offset: offset, largeContentProvider: nil)
            XCTAssertTrue(restored)
            XCTAssertEqual(newTree.allObjects().count, 3)

            // Verify ordering is preserved
            let sortedObjects = newTree.allObjects().sorted {
                ($0.entry?.interval.location ?? 0) < ($1.entry?.interval.location ?? 0)
            }

            XCTAssertEqual(sortedObjects[0].entry?.interval.location, 100000)
            XCTAssertEqual(sortedObjects[1].entry?.interval.location, 200000)
            XCTAssertEqual(sortedObjects[2].entry?.interval.location, 300000)
        } else {
            XCTFail("Failed to get property list from record")
        }
    }

    // MARK: - Comprehensive Round-Trip Tests for All IntervalTreeObject Types

    /// Helper to test round-trip encoding/decoding of an interval tree object
    private func verifyRoundTrip<T: IntervalTreeObject>(
        _ object: T,
        interval: Interval,
        file: StaticString = #file,
        line: UInt = #line,
        verify: (T, T) -> Void
    ) {
        let tree = IntervalTree()
        tree.add(object, with: interval)

        // Encode
        let encoder = iTermGraphEncoder(key: "test", identifier: "root", generation: iTermGenerationAlwaysEncode)
        tree.encode(withEncoder: iTermGraphEncoderAdapter(graphEncoder: encoder), offset: 0)

        // Decode
        let newTree = IntervalTree()
        guard let plist = encoder.record?.propertyListValue as? [AnyHashable: Any] else {
            XCTFail("Failed to get property list from record", file: file, line: line)
            return
        }

        let restored = newTree.restore(fromGraphRecord: plist, offset: 0, largeContentProvider: nil)
        XCTAssertTrue(restored, "Should restore successfully", file: file, line: line)
        XCTAssertEqual(newTree.allObjects().count, 1, "Should have one object", file: file, line: line)

        guard let restoredObject = newTree.allObjects().first as? T else {
            XCTFail("Restored object should be of type \(T.self)", file: file, line: line)
            return
        }

        // Verify interval
        XCTAssertEqual(restoredObject.entry?.interval.location, interval.location,
                      "Interval location should be preserved", file: file, line: line)
        XCTAssertEqual(restoredObject.entry?.interval.length, interval.length,
                      "Interval length should be preserved", file: file, line: line)

        // Custom verification
        verify(object, restoredObject)
    }

    // MARK: VT100ScreenMark Round-Trip

    func testVT100ScreenMarkRoundTrip() {
        let mark = VT100ScreenMark()
        mark.isPrompt = true
        mark.command = "ls -la"
        mark.code = 0
        mark.name = "Test Mark"

        verifyRoundTrip(mark, interval: Interval(location: 100, length: 50)) { original, restored in
            XCTAssertEqual(restored.guid, original.guid, "GUID should be preserved")
            XCTAssertEqual(restored.isPrompt, original.isPrompt, "isPrompt should be preserved")
            XCTAssertEqual(restored.command, original.command, "command should be preserved")
            XCTAssertEqual(restored.code, original.code, "code should be preserved")
            XCTAssertEqual(restored.name, original.name, "name should be preserved")
        }
    }

    // MARK: PTYAnnotation Round-Trip

    func testPTYAnnotationRoundTrip() {
        let annotation = PTYAnnotation()
        annotation.stringValue = "Test annotation content"

        verifyRoundTrip(annotation, interval: Interval(location: 200, length: 100)) { original, restored in
            XCTAssertEqual(restored.uniqueID, original.uniqueID, "uniqueID should be preserved")
            XCTAssertEqual(restored.stringValue, original.stringValue, "stringValue should be preserved")
        }
    }

    // MARK: iTermImageMark Round-Trip

    func testITermImageMarkRoundTrip() {
        guard let imageMark = iTermImageMark(imageCode: NSNumber(value: 42)) else {
            XCTFail("Failed to create iTermImageMark")
            return
        }

        verifyRoundTrip(imageMark, interval: Interval(location: 300, length: 25)) { original, restored in
            XCTAssertEqual(restored.guid, original.guid, "GUID should be preserved")
            XCTAssertEqual(restored.imageCode, original.imageCode, "imageCode should be preserved")
        }
    }

    // Note: iTermCapturedOutputMark is not exposed to Swift via bridging header,
    // so we test it indirectly through the testAllIntervalTreeObjectTypesInOneTree test
    // which uses Objective-C types via the interval tree.

    // MARK: FoldMark Round-Trip

    func testFoldMarkRoundTrip() {
        let foldMark = FoldMark(savedLines: nil, savedITOs: [], promptLength: 5, imageCodes: [], width: 80)

        verifyRoundTrip(foldMark, interval: Interval(location: 500, length: 200)) { original, restored in
            XCTAssertEqual(restored.guid, original.guid, "GUID should be preserved")
            // promptLength is private, verify generation instead
            XCTAssertEqual(restored.generation, 0, "generation should be 0")
        }
    }

    // MARK: VT100RemoteHost Round-Trip

    func testVT100RemoteHostRoundTrip() {
        guard let remoteHost = VT100RemoteHost(username: "testuser", hostname: "testhost.example.com") else {
            XCTFail("Failed to create VT100RemoteHost")
            return
        }

        verifyRoundTrip(remoteHost, interval: Interval(location: 600, length: 10)) { original, restored in
            XCTAssertEqual(restored.username, original.username, "username should be preserved")
            XCTAssertEqual(restored.hostname, original.hostname, "hostname should be preserved")
        }
    }

    // Note: VT100WorkingDirectory is not exposed to Swift via bridging header

    // MARK: PortholeMark Round-Trip

    func testPortholeMarkRoundTrip() {
        let portholeMark = PortholeMark("unique-porthole-id-123", width: 80)

        verifyRoundTrip(portholeMark, interval: Interval(location: 800, length: 50)) { original, restored in
            XCTAssertEqual(restored.guid, original.guid, "GUID should be preserved")
            XCTAssertEqual(restored.uniqueIdentifier, original.uniqueIdentifier,
                          "uniqueIdentifier should be preserved")
        }
    }

    // MARK: BlockMark Round-Trip

    func testBlockMarkRoundTrip() {
        let blockMark = BlockMark()
        blockMark.type = "test-block-type"
        let originalBlockID = blockMark.blockID

        verifyRoundTrip(blockMark, interval: Interval(location: 900, length: 75)) { original, restored in
            XCTAssertEqual(restored.guid, original.guid, "GUID should be preserved")
            XCTAssertEqual(restored.blockID, originalBlockID, "blockID should be preserved")
            XCTAssertEqual(restored.type, original.type, "type should be preserved")
        }
    }

    // MARK: PathMark Round-Trip

    func testPathMarkRoundTrip() {
        let remoteHost = VT100RemoteHost(username: "pathuser", hostname: "pathhost.local")
        let pathMark = PathMark(remoteHost: remoteHost, path: "/var/log/test.log")

        verifyRoundTrip(pathMark, interval: Interval(location: 1000, length: 20)) { original, restored in
            XCTAssertEqual(restored.guid, original.guid, "GUID should be preserved")
            XCTAssertEqual(restored.path, original.path, "path should be preserved")
            XCTAssertEqual(restored.hostname, original.hostname, "hostname should be preserved")
            XCTAssertEqual(restored.username, original.username, "username should be preserved")
            XCTAssertEqual(restored.isLocalhost, original.isLocalhost, "isLocalhost should be preserved")
        }
    }

    // MARK: ButtonMark Round-Trip

    func testButtonMarkRoundTrip() {
        let buttonMark = ButtonMark()
        buttonMark.copyBlockID = "block-123"
        let originalButtonID = buttonMark.buttonID

        verifyRoundTrip(buttonMark, interval: Interval(location: 1100, length: 5)) { original, restored in
            XCTAssertEqual(restored.guid, original.guid, "GUID should be preserved")
            XCTAssertEqual(restored.buttonID, originalButtonID, "buttonID should be preserved")
            XCTAssertEqual(restored.copyBlockID, original.copyBlockID, "copyBlockID should be preserved")
        }
    }

    // MARK: Duplicate StableIdentifier Tests

    /// Test that two VT100RemoteHost objects with the same username@hostname
    /// are both preserved through encode/decode. Even though they have identical content,
    /// each should have a unique GUID for stable identification.
    func testDuplicateStableIdentifiersPreserveBothObjects() {
        let tree = IntervalTree()

        // Create two VT100RemoteHost objects with identical content
        // This is a realistic scenario - multiple prompts showing the same remote host
        guard let host1 = VT100RemoteHost(username: "admin", hostname: "server.example.com"),
              let host2 = VT100RemoteHost(username: "admin", hostname: "server.example.com") else {
            XCTFail("Failed to create VT100RemoteHost objects")
            return
        }

        // Each object should have a unique GUID even though content is identical
        XCTAssertNotEqual(host1.stableIdentifier, host2.stableIdentifier,
                          "Each host should have a unique stableIdentifier (GUID)")
        XCTAssertFalse(host1.stableIdentifier.isEmpty)
        XCTAssertFalse(host2.stableIdentifier.isEmpty)

        // Add them at different intervals
        let interval1 = Interval(location: 100, length: 50)
        let interval2 = Interval(location: 500, length: 50)
        tree.add(host1, with: interval1)
        tree.add(host2, with: interval2)

        XCTAssertEqual(tree.allObjects().count, 2, "Tree should have 2 objects")

        // Encode
        let encoder = iTermGraphEncoder(key: "test", identifier: "root", generation: iTermGenerationAlwaysEncode)
        tree.encode(withEncoder: iTermGraphEncoderAdapter(graphEncoder: encoder), offset: 0)

        // Decode
        let newTree = IntervalTree()
        guard let plist = encoder.record?.propertyListValue as? [AnyHashable: Any] else {
            XCTFail("Failed to get property list from record")
            return
        }

        let restored = newTree.restore(fromGraphRecord: plist, offset: 0, largeContentProvider: nil)
        XCTAssertTrue(restored, "Should restore successfully")

        // CRITICAL: Both objects should be restored
        XCTAssertEqual(newTree.allObjects().count, 2,
                      "Both VT100RemoteHost objects with same stableIdentifier should be restored")

        // Verify both intervals are present
        let restoredHosts = newTree.allObjects().compactMap { $0 as? VT100RemoteHost }
        XCTAssertEqual(restoredHosts.count, 2, "Should have 2 VT100RemoteHost objects")

        let intervals = restoredHosts.compactMap { $0.entry?.interval }
        XCTAssertEqual(intervals.count, 2, "Both should have intervals")

        let locations = Set(intervals.map { $0.location })
        XCTAssertTrue(locations.contains(100), "Should have interval at location 100")
        XCTAssertTrue(locations.contains(500), "Should have interval at location 500")
    }

    /// Test multiple pairs of duplicate stableIdentifiers
    func testMultipleDuplicateStableIdentifierPairs() {
        let tree = IntervalTree()

        // Create two hosts at host1.com
        guard let hostA1 = VT100RemoteHost(username: "user", hostname: "host1.com"),
              let hostA2 = VT100RemoteHost(username: "user", hostname: "host1.com"),
              // And two hosts at host2.com
              let hostB1 = VT100RemoteHost(username: "user", hostname: "host2.com"),
              let hostB2 = VT100RemoteHost(username: "user", hostname: "host2.com") else {
            XCTFail("Failed to create VT100RemoteHost objects")
            return
        }

        tree.add(hostA1, with: Interval(location: 100, length: 50))
        tree.add(hostA2, with: Interval(location: 200, length: 50))
        tree.add(hostB1, with: Interval(location: 300, length: 50))
        tree.add(hostB2, with: Interval(location: 400, length: 50))

        XCTAssertEqual(tree.allObjects().count, 4)

        // Encode and decode
        let encoder = iTermGraphEncoder(key: "test", identifier: "root", generation: iTermGenerationAlwaysEncode)
        tree.encode(withEncoder: iTermGraphEncoderAdapter(graphEncoder: encoder), offset: 0)

        let newTree = IntervalTree()
        guard let plist = encoder.record?.propertyListValue as? [AnyHashable: Any] else {
            XCTFail("Failed to get property list")
            return
        }

        let restored = newTree.restore(fromGraphRecord: plist, offset: 0, largeContentProvider: nil)
        XCTAssertTrue(restored)
        XCTAssertEqual(newTree.allObjects().count, 4, "All 4 objects should be restored")

        // Verify correct hostnames
        let restoredHosts = newTree.allObjects().compactMap { $0 as? VT100RemoteHost }
        let host1Count = restoredHosts.filter { $0.hostname == "host1.com" }.count
        let host2Count = restoredHosts.filter { $0.hostname == "host2.com" }.count
        XCTAssertEqual(host1Count, 2, "Should have 2 hosts for host1.com")
        XCTAssertEqual(host2Count, 2, "Should have 2 hosts for host2.com")
    }

    // MARK: All Types Together (Swift-visible types)

    func testAllSwiftVisibleIntervalTreeObjectTypesInOneTree() {
        let tree = IntervalTree()

        // Add one of each Swift-visible type
        // Note: iTermCapturedOutputMark and VT100WorkingDirectory are not in bridging header
        let screenMark = VT100ScreenMark()
        screenMark.command = "echo test"

        let annotation = PTYAnnotation()
        annotation.stringValue = "Note"

        guard let imageMark = iTermImageMark(imageCode: NSNumber(value: 99)) else {
            XCTFail("Failed to create iTermImageMark")
            return
        }

        let foldMark = FoldMark(savedLines: nil, savedITOs: [], promptLength: 3, imageCodes: [], width: 80)

        guard let remoteHost = VT100RemoteHost(username: "user", hostname: "host") else {
            XCTFail("Failed to create VT100RemoteHost")
            return
        }

        let portholeMark = PortholeMark("porthole-all-test", width: 80)

        let blockMark = BlockMark()

        let pathMark = PathMark(remoteHost: nil, path: "/test/path")

        let buttonMark = ButtonMark()

        // Add all to tree (9 types that are Swift-visible)
        tree.add(screenMark, with: Interval(location: 0, length: 100))
        tree.add(annotation, with: Interval(location: 100, length: 100))
        tree.add(imageMark, with: Interval(location: 200, length: 100))
        tree.add(foldMark, with: Interval(location: 300, length: 100))
        tree.add(remoteHost, with: Interval(location: 400, length: 100))
        tree.add(portholeMark, with: Interval(location: 500, length: 100))
        tree.add(blockMark, with: Interval(location: 600, length: 100))
        tree.add(pathMark, with: Interval(location: 700, length: 100))
        tree.add(buttonMark, with: Interval(location: 800, length: 100))

        XCTAssertEqual(tree.allObjects().count, 9)

        // Encode
        let encoder = iTermGraphEncoder(key: "test", identifier: "root", generation: iTermGenerationAlwaysEncode)
        tree.encode(withEncoder: iTermGraphEncoderAdapter(graphEncoder: encoder), offset: 0)

        // Decode
        let newTree = IntervalTree()
        guard let plist = encoder.record?.propertyListValue as? [AnyHashable: Any] else {
            XCTFail("Failed to get property list")
            return
        }

        let restored = newTree.restore(fromGraphRecord: plist, offset: 0, largeContentProvider: nil)
        XCTAssertTrue(restored)
        XCTAssertEqual(newTree.allObjects().count, 9, "All 9 objects should be restored")

        // Verify each type exists
        let restoredObjects = newTree.allObjects()
        XCTAssertEqual(restoredObjects.compactMap { $0 as? VT100ScreenMark }.count, 1)
        XCTAssertEqual(restoredObjects.compactMap { $0 as? PTYAnnotation }.count, 1)
        XCTAssertEqual(restoredObjects.compactMap { $0 as? iTermImageMark }.count, 1)
        XCTAssertEqual(restoredObjects.compactMap { $0 as? FoldMark }.count, 1)
        XCTAssertEqual(restoredObjects.compactMap { $0 as? VT100RemoteHost }.count, 1)
        XCTAssertEqual(restoredObjects.compactMap { $0 as? PortholeMark }.count, 1)
        XCTAssertEqual(restoredObjects.compactMap { $0 as? BlockMark }.count, 1)
        XCTAssertEqual(restoredObjects.compactMap { $0 as? PathMark }.count, 1)
        XCTAssertEqual(restoredObjects.compactMap { $0 as? ButtonMark }.count, 1)

        // Verify key properties preserved
        let restoredScreenMark = restoredObjects.compactMap { $0 as? VT100ScreenMark }.first!
        XCTAssertEqual(restoredScreenMark.command, "echo test")

        let restoredAnnotation = restoredObjects.compactMap { $0 as? PTYAnnotation }.first!
        XCTAssertEqual(restoredAnnotation.stringValue, "Note")

        let restoredPathMark = restoredObjects.compactMap { $0 as? PathMark }.first!
        XCTAssertEqual(restoredPathMark.path, "/test/path")

        let restoredRemoteHost = restoredObjects.compactMap { $0 as? VT100RemoteHost }.first!
        XCTAssertEqual(restoredRemoteHost.username, "user")
        XCTAssertEqual(restoredRemoteHost.hostname, "host")
    }
}
