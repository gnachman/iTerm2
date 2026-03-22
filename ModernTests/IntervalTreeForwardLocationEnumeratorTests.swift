//
//  IntervalTreeForwardLocationEnumeratorTests.swift
//  iTerm2
//
//  Created by George Nachman on 3/20/26.
//
//  Comprehensive tests for IntervalTree's forwardLocationEnumerator.
//

import XCTest
@testable import iTerm2SharedARC

final class IntervalTreeForwardLocationEnumeratorTests: XCTestCase {

    // MARK: - Empty Tree Tests

    func testEmptyTreeReturnsNil() {
        let tree = IntervalTree()
        let enumerator = tree.forwardLocationEnumerator(at: 0)

        let result = enumerator.nextObject()
        XCTAssertNil(result, "Empty tree should return nil")
    }

    func testEmptyTreeWithNonZeroStartReturnsNil() {
        let tree = IntervalTree()
        let enumerator = tree.forwardLocationEnumerator(at: 100)

        let result = enumerator.nextObject()
        XCTAssertNil(result, "Empty tree should return nil regardless of start position")
    }

    // MARK: - Single Object Tests

    func testSingleObjectAtZero() {
        let tree = IntervalTree()

        let ann = PTYAnnotation()
        ann.stringValue = "A"
        tree.add(ann, with: Interval(location: 0, length: 10))

        let enumerator = tree.forwardLocationEnumerator(at: 0)

        let batch1 = enumerator.nextObject() as? [Any]
        XCTAssertNotNil(batch1)
        XCTAssertEqual(batch1?.count, 1)
        XCTAssertEqual((batch1?.first as? PTYAnnotation)?.stringValue, "A")

        let batch2 = enumerator.nextObject()
        XCTAssertNil(batch2, "Should return nil after exhausting all objects")
    }

    func testSingleObjectStartingBefore() {
        let tree = IntervalTree()

        let ann = PTYAnnotation()
        ann.stringValue = "A"
        tree.add(ann, with: Interval(location: 100, length: 10))

        let enumerator = tree.forwardLocationEnumerator(at: 0)

        let batch1 = enumerator.nextObject() as? [Any]
        XCTAssertNotNil(batch1)
        XCTAssertEqual(batch1?.count, 1)
        XCTAssertEqual((batch1?.first as? PTYAnnotation)?.stringValue, "A")

        let batch2 = enumerator.nextObject()
        XCTAssertNil(batch2)
    }

    func testSingleObjectStartingAt() {
        let tree = IntervalTree()

        let ann = PTYAnnotation()
        ann.stringValue = "A"
        tree.add(ann, with: Interval(location: 100, length: 10))

        let enumerator = tree.forwardLocationEnumerator(at: 100)

        let batch1 = enumerator.nextObject() as? [Any]
        XCTAssertNotNil(batch1)
        XCTAssertEqual(batch1?.count, 1)
        XCTAssertEqual((batch1?.first as? PTYAnnotation)?.stringValue, "A")

        let batch2 = enumerator.nextObject()
        XCTAssertNil(batch2)
    }

    func testSingleObjectStartingAfter() {
        let tree = IntervalTree()

        let ann = PTYAnnotation()
        ann.stringValue = "A"
        tree.add(ann, with: Interval(location: 100, length: 10))

        let enumerator = tree.forwardLocationEnumerator(at: 101)

        let batch1 = enumerator.nextObject()
        XCTAssertNil(batch1, "Should return nil when starting after the only object")
    }

    // MARK: - Multiple Objects at Same Location Tests

    func testMultipleObjectsAtSameLocation() {
        let tree = IntervalTree()

        let ann1 = PTYAnnotation()
        ann1.stringValue = "A"
        tree.add(ann1, with: Interval(location: 50, length: 10))

        let ann2 = PTYAnnotation()
        ann2.stringValue = "B"
        tree.add(ann2, with: Interval(location: 50, length: 20))

        let ann3 = PTYAnnotation()
        ann3.stringValue = "C"
        tree.add(ann3, with: Interval(location: 50, length: 30))

        let enumerator = tree.forwardLocationEnumerator(at: 0)

        let batch1 = enumerator.nextObject() as? [Any]
        XCTAssertNotNil(batch1)
        XCTAssertEqual(batch1?.count, 3, "Should return all 3 objects at location 50")

        let names = Set((batch1 ?? []).compactMap { ($0 as? PTYAnnotation)?.stringValue })
        XCTAssertEqual(names, Set(["A", "B", "C"]))

        let batch2 = enumerator.nextObject()
        XCTAssertNil(batch2)
    }

    func testMultipleObjectsAtSameLocationWithZeroLength() {
        let tree = IntervalTree()

        // Two objects with zero length (point intervals)
        let ann1 = PTYAnnotation()
        ann1.stringValue = "A"
        tree.add(ann1, with: Interval(location: 50, length: 0))

        let ann2 = PTYAnnotation()
        ann2.stringValue = "B"
        tree.add(ann2, with: Interval(location: 50, length: 0))

        // One object with non-zero length
        let ann3 = PTYAnnotation()
        ann3.stringValue = "C"
        tree.add(ann3, with: Interval(location: 50, length: 100))

        let enumerator = tree.forwardLocationEnumerator(at: 0)

        let batch1 = enumerator.nextObject() as? [Any]
        XCTAssertNotNil(batch1)
        XCTAssertEqual(batch1?.count, 3, "Should return all 3 objects regardless of length")

        let names = Set((batch1 ?? []).compactMap { ($0 as? PTYAnnotation)?.stringValue })
        XCTAssertEqual(names, Set(["A", "B", "C"]))
    }

    // MARK: - Multiple Locations Tests

    func testMultipleLocationsInOrder() {
        let tree = IntervalTree()

        let ann1 = PTYAnnotation()
        ann1.stringValue = "A"
        tree.add(ann1, with: Interval(location: 10, length: 5))

        let ann2 = PTYAnnotation()
        ann2.stringValue = "B"
        tree.add(ann2, with: Interval(location: 20, length: 5))

        let ann3 = PTYAnnotation()
        ann3.stringValue = "C"
        tree.add(ann3, with: Interval(location: 30, length: 5))

        let enumerator = tree.forwardLocationEnumerator(at: 0)

        let batch1 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch1?.first as? PTYAnnotation)?.stringValue, "A")
        XCTAssertEqual((batch1?.first as? PTYAnnotation)?.entry?.interval.location, 10)

        let batch2 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch2?.first as? PTYAnnotation)?.stringValue, "B")
        XCTAssertEqual((batch2?.first as? PTYAnnotation)?.entry?.interval.location, 20)

        let batch3 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch3?.first as? PTYAnnotation)?.stringValue, "C")
        XCTAssertEqual((batch3?.first as? PTYAnnotation)?.entry?.interval.location, 30)

        let batch4 = enumerator.nextObject()
        XCTAssertNil(batch4)
    }

    func testMultipleLocationsAddedOutOfOrder() {
        let tree = IntervalTree()

        // Add in reverse order
        let ann3 = PTYAnnotation()
        ann3.stringValue = "C"
        tree.add(ann3, with: Interval(location: 30, length: 5))

        let ann1 = PTYAnnotation()
        ann1.stringValue = "A"
        tree.add(ann1, with: Interval(location: 10, length: 5))

        let ann2 = PTYAnnotation()
        ann2.stringValue = "B"
        tree.add(ann2, with: Interval(location: 20, length: 5))

        let enumerator = tree.forwardLocationEnumerator(at: 0)

        // Should still enumerate in location order
        let batch1 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch1?.first as? PTYAnnotation)?.entry?.interval.location, 10)

        let batch2 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch2?.first as? PTYAnnotation)?.entry?.interval.location, 20)

        let batch3 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch3?.first as? PTYAnnotation)?.entry?.interval.location, 30)
    }

    func testStartingFromMiddle() {
        let tree = IntervalTree()

        let ann1 = PTYAnnotation()
        ann1.stringValue = "A"
        tree.add(ann1, with: Interval(location: 10, length: 5))

        let ann2 = PTYAnnotation()
        ann2.stringValue = "B"
        tree.add(ann2, with: Interval(location: 20, length: 5))

        let ann3 = PTYAnnotation()
        ann3.stringValue = "C"
        tree.add(ann3, with: Interval(location: 30, length: 5))

        // Start at 20, should get B and C but not A
        let enumerator = tree.forwardLocationEnumerator(at: 20)

        let batch1 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch1?.first as? PTYAnnotation)?.stringValue, "B")

        let batch2 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch2?.first as? PTYAnnotation)?.stringValue, "C")

        let batch3 = enumerator.nextObject()
        XCTAssertNil(batch3)
    }

    func testStartingBetweenLocations() {
        let tree = IntervalTree()

        let ann1 = PTYAnnotation()
        ann1.stringValue = "A"
        tree.add(ann1, with: Interval(location: 10, length: 5))

        let ann2 = PTYAnnotation()
        ann2.stringValue = "B"
        tree.add(ann2, with: Interval(location: 20, length: 5))

        let ann3 = PTYAnnotation()
        ann3.stringValue = "C"
        tree.add(ann3, with: Interval(location: 30, length: 5))

        // Start at 15, between A and B - should get B and C
        let enumerator = tree.forwardLocationEnumerator(at: 15)

        let batch1 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch1?.first as? PTYAnnotation)?.stringValue, "B")

        let batch2 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch2?.first as? PTYAnnotation)?.stringValue, "C")

        let batch3 = enumerator.nextObject()
        XCTAssertNil(batch3)
    }

    func testStartingPastAllLocations() {
        let tree = IntervalTree()

        let ann1 = PTYAnnotation()
        ann1.stringValue = "A"
        tree.add(ann1, with: Interval(location: 10, length: 5))

        let ann2 = PTYAnnotation()
        ann2.stringValue = "B"
        tree.add(ann2, with: Interval(location: 20, length: 5))

        // Start at 100, past all objects
        let enumerator = tree.forwardLocationEnumerator(at: 100)

        let batch1 = enumerator.nextObject()
        XCTAssertNil(batch1, "Should return nil when starting past all objects")
    }

    // MARK: - Complex Tree Structure Tests

    func testLargeTreeWithManyLocations() {
        let tree = IntervalTree()

        // Add 100 objects at different locations
        for i in 0..<100 {
            let ann = PTYAnnotation()
            ann.stringValue = "obj\(i)"
            tree.add(ann, with: Interval(location: Int64(i * 10), length: 5))
        }

        let enumerator = tree.forwardLocationEnumerator(at: 0)

        var count = 0
        var previousLocation: Int64 = -1
        while let batch = enumerator.nextObject() as? [Any] {
            count += 1
            let location = (batch.first as? PTYAnnotation)?.entry?.interval.location ?? -1
            XCTAssertGreaterThan(location, previousLocation,
                                 "Locations should be strictly increasing")
            previousLocation = location
        }

        XCTAssertEqual(count, 100, "Should enumerate all 100 locations")
    }

    func testLargeTreeWithMultipleObjectsPerLocation() {
        let tree = IntervalTree()

        // Add 3 objects at each of 10 locations
        for loc in 0..<10 {
            for obj in 0..<3 {
                let ann = PTYAnnotation()
                ann.stringValue = "loc\(loc)_obj\(obj)"
                tree.add(ann, with: Interval(location: Int64(loc * 100), length: Int64(obj + 1) * 10))
            }
        }

        let enumerator = tree.forwardLocationEnumerator(at: 0)

        var locationCount = 0
        var totalObjectCount = 0
        while let batch = enumerator.nextObject() as? [Any] {
            locationCount += 1
            XCTAssertEqual(batch.count, 3, "Each location should have 3 objects")
            totalObjectCount += batch.count
        }

        XCTAssertEqual(locationCount, 10, "Should enumerate 10 locations")
        XCTAssertEqual(totalObjectCount, 30, "Should enumerate 30 total objects")
    }

    // MARK: - Edge Cases

    func testVeryLargeLocations() {
        let tree = IntervalTree()

        let ann1 = PTYAnnotation()
        ann1.stringValue = "A"
        tree.add(ann1, with: Interval(location: 1_000_000_000, length: 100))

        let ann2 = PTYAnnotation()
        ann2.stringValue = "B"
        tree.add(ann2, with: Interval(location: 2_000_000_000, length: 100))

        let enumerator = tree.forwardLocationEnumerator(at: 0)

        let batch1 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch1?.first as? PTYAnnotation)?.stringValue, "A")

        let batch2 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch2?.first as? PTYAnnotation)?.stringValue, "B")

        let batch3 = enumerator.nextObject()
        XCTAssertNil(batch3)
    }

    func testAdjacentLocations() {
        let tree = IntervalTree()

        // Locations that are adjacent (differ by 1)
        let ann1 = PTYAnnotation()
        ann1.stringValue = "A"
        tree.add(ann1, with: Interval(location: 100, length: 1))

        let ann2 = PTYAnnotation()
        ann2.stringValue = "B"
        tree.add(ann2, with: Interval(location: 101, length: 1))

        let ann3 = PTYAnnotation()
        ann3.stringValue = "C"
        tree.add(ann3, with: Interval(location: 102, length: 1))

        let enumerator = tree.forwardLocationEnumerator(at: 100)

        let batch1 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch1?.first as? PTYAnnotation)?.stringValue, "A")

        let batch2 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch2?.first as? PTYAnnotation)?.stringValue, "B")

        let batch3 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch3?.first as? PTYAnnotation)?.stringValue, "C")
    }

    func testOverlappingIntervals() {
        let tree = IntervalTree()

        // Intervals that overlap but have different start locations
        let ann1 = PTYAnnotation()
        ann1.stringValue = "A"
        tree.add(ann1, with: Interval(location: 0, length: 100))  // [0, 100)

        let ann2 = PTYAnnotation()
        ann2.stringValue = "B"
        tree.add(ann2, with: Interval(location: 50, length: 100))  // [50, 150)

        let ann3 = PTYAnnotation()
        ann3.stringValue = "C"
        tree.add(ann3, with: Interval(location: 75, length: 100))  // [75, 175)

        let enumerator = tree.forwardLocationEnumerator(at: 0)

        let batch1 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch1?.first as? PTYAnnotation)?.stringValue, "A")
        XCTAssertEqual((batch1?.first as? PTYAnnotation)?.entry?.interval.location, 0)

        let batch2 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch2?.first as? PTYAnnotation)?.stringValue, "B")
        XCTAssertEqual((batch2?.first as? PTYAnnotation)?.entry?.interval.location, 50)

        let batch3 = enumerator.nextObject() as? [Any]
        XCTAssertEqual((batch3?.first as? PTYAnnotation)?.stringValue, "C")
        XCTAssertEqual((batch3?.first as? PTYAnnotation)?.entry?.interval.location, 75)
    }

    // MARK: - Idempotency and State Tests

    func testEnumeratorExhaustion() {
        let tree = IntervalTree()

        let ann = PTYAnnotation()
        ann.stringValue = "A"
        tree.add(ann, with: Interval(location: 0, length: 10))

        let enumerator = tree.forwardLocationEnumerator(at: 0)

        _ = enumerator.nextObject()  // Get the object
        XCTAssertNil(enumerator.nextObject(), "Second call should return nil")
        XCTAssertNil(enumerator.nextObject(), "Third call should still return nil")
        XCTAssertNil(enumerator.nextObject(), "Subsequent calls should always return nil")
    }

    func testMultipleEnumeratorsOnSameTree() {
        let tree = IntervalTree()

        let ann1 = PTYAnnotation()
        ann1.stringValue = "A"
        tree.add(ann1, with: Interval(location: 10, length: 5))

        let ann2 = PTYAnnotation()
        ann2.stringValue = "B"
        tree.add(ann2, with: Interval(location: 20, length: 5))

        let enum1 = tree.forwardLocationEnumerator(at: 0)
        let enum2 = tree.forwardLocationEnumerator(at: 0)

        // Both should work independently
        let batch1a = enum1.nextObject() as? [Any]
        let batch1b = enum2.nextObject() as? [Any]

        XCTAssertEqual((batch1a?.first as? PTYAnnotation)?.stringValue, "A")
        XCTAssertEqual((batch1b?.first as? PTYAnnotation)?.stringValue, "A")

        let batch2a = enum1.nextObject() as? [Any]
        XCTAssertEqual((batch2a?.first as? PTYAnnotation)?.stringValue, "B")

        // enum2 should still be at A's position and return B next
        let batch2b = enum2.nextObject() as? [Any]
        XCTAssertEqual((batch2b?.first as? PTYAnnotation)?.stringValue, "B")
    }

    // MARK: - For-in Loop Tests

    func testForInLoopEnumeration() {
        let tree = IntervalTree()

        let ann1 = PTYAnnotation()
        ann1.stringValue = "A"
        tree.add(ann1, with: Interval(location: 10, length: 5))

        let ann2 = PTYAnnotation()
        ann2.stringValue = "B"
        tree.add(ann2, with: Interval(location: 20, length: 5))

        let ann3 = PTYAnnotation()
        ann3.stringValue = "C"
        tree.add(ann3, with: Interval(location: 30, length: 5))

        var names: [String] = []
        for batch in tree.forwardLocationEnumerator(at: 0) {
            if let objects = batch as? [Any] {
                for obj in objects {
                    if let ann = obj as? PTYAnnotation {
                        names.append(ann.stringValue)
                    }
                }
            }
        }

        XCTAssertEqual(names, ["A", "B", "C"])
    }

    // MARK: - Real-World Scenario Tests

    func testScenarioFromBugReport() {
        // Recreate the exact scenario from the bug report
        let tree = IntervalTree()

        // Location 0: objects with limits 0, 0, 79, 80, 67796
        let remoteHost1 = PTYAnnotation()
        remoteHost1.stringValue = "RemoteHost1"
        tree.add(remoteHost1, with: Interval(location: 0, length: 0))

        let remoteHost2 = PTYAnnotation()
        remoteHost2.stringValue = "RemoteHost2"
        tree.add(remoteHost2, with: Interval(location: 0, length: 0))

        let screenMark = PTYAnnotation()
        screenMark.stringValue = "ScreenMark"
        tree.add(screenMark, with: Interval(location: 0, length: 80))

        let foldMark = PTYAnnotation()
        foldMark.stringValue = "FoldMark"
        tree.add(foldMark, with: Interval(location: 0, length: 79))

        let workingDir = PTYAnnotation()
        workingDir.stringValue = "WorkingDirectory"
        tree.add(workingDir, with: Interval(location: 0, length: 67796))

        // Location 81
        let obj81a = PTYAnnotation()
        obj81a.stringValue = "81a"
        tree.add(obj81a, with: Interval(location: 81, length: 80))

        let obj81b = PTYAnnotation()
        obj81b.stringValue = "81b"
        tree.add(obj81b, with: Interval(location: 81, length: 80))

        let obj81c = PTYAnnotation()
        obj81c.stringValue = "81c"
        tree.add(obj81c, with: Interval(location: 81, length: 80))

        let enumerator = tree.forwardLocationEnumerator(at: 0)

        // First batch MUST contain all 5 objects at location 0
        let batch0 = enumerator.nextObject() as? [Any]
        XCTAssertNotNil(batch0)
        XCTAssertEqual(batch0?.count, 5,
                       "CRITICAL: First batch must contain ALL 5 objects at location 0, not just those with smallest limit")

        let names0 = Set((batch0 ?? []).compactMap { ($0 as? PTYAnnotation)?.stringValue })
        XCTAssertTrue(names0.contains("RemoteHost1"), "Missing RemoteHost1")
        XCTAssertTrue(names0.contains("RemoteHost2"), "Missing RemoteHost2")
        XCTAssertTrue(names0.contains("ScreenMark"), "Missing ScreenMark")
        XCTAssertTrue(names0.contains("FoldMark"), "Missing FoldMark")
        XCTAssertTrue(names0.contains("WorkingDirectory"), "Missing WorkingDirectory")

        // Second batch should be at location 81 with 3 objects
        let batch81 = enumerator.nextObject() as? [Any]
        XCTAssertNotNil(batch81)
        XCTAssertEqual(batch81?.count, 3)

        // Verify we're at location 81
        XCTAssertEqual((batch81?.first as? PTYAnnotation)?.entry?.interval.location, 81)
    }

    // MARK: - Different Object Types

    func testWithVT100ScreenMarks() {
        let tree = IntervalTree()

        // Use actual VT100ScreenMark objects
        let mark1 = VT100ScreenMark()
        mark1.name = "Mark1"
        tree.add(mark1, with: Interval(location: 0, length: 100))

        let mark2 = VT100ScreenMark()
        mark2.name = "Mark2"
        tree.add(mark2, with: Interval(location: 0, length: 50))

        let enumerator = tree.forwardLocationEnumerator(at: 0)
        let batch = enumerator.nextObject() as? [Any]

        XCTAssertEqual(batch?.count, 2, "Should return both marks at location 0")
    }

    // MARK: - Modification During Enumeration (Document Behavior)

    func testTreeModificationDuringEnumeration() {
        // This test documents current behavior - modifications during enumeration
        // may have undefined behavior, but we should at least not crash
        let tree = IntervalTree()

        let ann1 = PTYAnnotation()
        ann1.stringValue = "A"
        tree.add(ann1, with: Interval(location: 10, length: 5))

        let ann2 = PTYAnnotation()
        ann2.stringValue = "B"
        tree.add(ann2, with: Interval(location: 20, length: 5))

        let enumerator = tree.forwardLocationEnumerator(at: 0)

        _ = enumerator.nextObject()  // Get A

        // Add a new object - behavior is undefined but shouldn't crash
        let ann3 = PTYAnnotation()
        ann3.stringValue = "C"
        tree.add(ann3, with: Interval(location: 30, length: 5))

        // Should be able to continue without crashing
        _ = enumerator.nextObject()
    }
}
