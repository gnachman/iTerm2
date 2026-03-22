//
//  IntervalTreeSmallestLocationBugTests.swift
//  iTerm2
//
//  Created by George Nachman on 3/20/26.
//
//  Tests demonstrating bugs in objectsWithSmallestLocation.
//

import XCTest
@testable import iTerm2SharedARC

final class IntervalTreeSmallestLocationBugTests: XCTestCase {

    /// Test that objectsWithSmallestLocation returns the object with the smallest
    /// interval location, NOT the smallest limit.
    ///
    /// Bug: In objectsWithSmallestLocationFromNode:, lines 778 and 790 call
    /// objectsWithSmallestLimitFromNode: instead of recursing with
    /// objectsWithSmallestLocationFromNode:. This causes the function to return
    /// objects with the smallest LIMIT rather than the smallest LOCATION when
    /// the tree has a left subtree with multiple nodes.
    func testObjectsWithSmallestLocationReturnsSmallestLocationNotSmallestLimit() {
        let tree = IntervalTree()

        // Create objects where smallest location has a large limit,
        // and another object has a smaller limit but larger location
        let annotations: [(String, Int64, Int64)] = [
            ("A", 1, 199),   // loc=1, limit=200 - smallest location
            ("B", 2, 3),     // loc=2, limit=5 - smallest limit
            ("C", 3, 97),    // loc=3, limit=100
            ("D", 4, 46),    // loc=4, limit=50
            ("E", 10, 10),   // loc=10, limit=20
            ("F", 20, 10),   // loc=20, limit=30
            ("G", 30, 10),   // loc=30, limit=40
            ("H", 100, 50),  // loc=100, limit=150
        ]

        for (name, loc, len) in annotations {
            let ann = PTYAnnotation()
            ann.stringValue = name
            tree.add(ann, with: Interval(location: loc, length: len))
        }

        let result = tree.objectsWithSmallestLocation()
        let name = (result?.first as? PTYAnnotation)?.stringValue
        let loc = (result?.first as? PTYAnnotation)?.entry?.interval.location

        // If the bug exists, this returns B (smallest limit=5) instead of A (smallest location=1)
        XCTAssertEqual(name, "A",
                       "Should return A with smallest location (1), not B with smallest limit (5)")
        XCTAssertEqual(loc, 1,
                       "Returned object should have location 1")
    }

    /// Test that objectsWithSmallestLocation returns ALL objects at the smallest
    /// location, not just those with the smallest limit.
    ///
    /// Bug: When multiple objects exist at the same location with different limits,
    /// objectsWithSmallestLocation only returns those with the smallest limit,
    /// instead of returning ALL objects at that location.
    ///
    /// This test recreates the scenario from the debugger:
    /// - Multiple objects at location 0 with limits: 0, 0, 79, 80, 67796
    /// - Expected: ALL 5 objects should be returned
    /// - Bug behavior: Only 2 objects (those with limit 0) are returned
    func testObjectsWithSmallestLocationReturnsAllObjectsAtSmallestLocation() {
        let tree = IntervalTree()

        // Create multiple objects at location 0 with different limits
        // This mirrors the real-world scenario:
        //   [0, 0) - VT100RemoteHost
        //   [0, 0) - VT100RemoteHost
        //   [0, 80) - VT100ScreenMark
        //   [0, 79) - iTermFoldMark
        //   [0, 67796) - VT100WorkingDirectory

        let ann1 = PTYAnnotation()
        ann1.stringValue = "A"
        tree.add(ann1, with: Interval(location: 0, length: 0))  // [0, 0)

        let ann2 = PTYAnnotation()
        ann2.stringValue = "B"
        tree.add(ann2, with: Interval(location: 0, length: 0))  // [0, 0)

        let ann3 = PTYAnnotation()
        ann3.stringValue = "C"
        tree.add(ann3, with: Interval(location: 0, length: 80))  // [0, 80)

        let ann4 = PTYAnnotation()
        ann4.stringValue = "D"
        tree.add(ann4, with: Interval(location: 0, length: 79))  // [0, 79)

        let ann5 = PTYAnnotation()
        ann5.stringValue = "E"
        tree.add(ann5, with: Interval(location: 0, length: 67796))  // [0, 67796)

        // Add objects at other locations to make the tree non-trivial
        let ann6 = PTYAnnotation()
        ann6.stringValue = "F"
        tree.add(ann6, with: Interval(location: 81, length: 80))  // [81, 161)

        let ann7 = PTYAnnotation()
        ann7.stringValue = "G"
        tree.add(ann7, with: Interval(location: 85, length: 15))  // [85, 100)

        let result = tree.objectsWithSmallestLocation()

        // Should return ALL 5 objects at location 0
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 5,
                       "Should return all 5 objects at location 0, not just those with smallest limit")

        // Verify all expected objects are present
        let names = Set((result ?? []).compactMap { ($0 as? PTYAnnotation)?.stringValue })
        XCTAssertTrue(names.contains("A"), "Should contain A [0, 0)")
        XCTAssertTrue(names.contains("B"), "Should contain B [0, 0)")
        XCTAssertTrue(names.contains("C"), "Should contain C [0, 80)")
        XCTAssertTrue(names.contains("D"), "Should contain D [0, 79)")
        XCTAssertTrue(names.contains("E"), "Should contain E [0, 67796)")
    }

    /// Test that forwardLocationEnumerator returns all objects at each location.
    func testForwardLocationEnumeratorReturnsAllObjectsAtEachLocation() {
        let tree = IntervalTree()

        // Objects at location 0 with different limits
        let ann1 = PTYAnnotation()
        ann1.stringValue = "A"
        tree.add(ann1, with: Interval(location: 0, length: 0))

        let ann2 = PTYAnnotation()
        ann2.stringValue = "B"
        tree.add(ann2, with: Interval(location: 0, length: 0))

        let ann3 = PTYAnnotation()
        ann3.stringValue = "C"
        tree.add(ann3, with: Interval(location: 0, length: 80))

        // Objects at location 81
        let ann4 = PTYAnnotation()
        ann4.stringValue = "D"
        tree.add(ann4, with: Interval(location: 81, length: 80))

        let enumerator = tree.forwardLocationEnumerator(at: 0)

        // First batch should contain ALL 3 objects at location 0
        let firstBatch = enumerator.nextObject() as? [Any]
        XCTAssertNotNil(firstBatch)
        XCTAssertEqual(firstBatch?.count, 3,
                       "First batch should contain all 3 objects at location 0")

        let firstNames = Set((firstBatch ?? []).compactMap { ($0 as? PTYAnnotation)?.stringValue })
        XCTAssertTrue(firstNames.contains("A"))
        XCTAssertTrue(firstNames.contains("B"))
        XCTAssertTrue(firstNames.contains("C"))

        // Second batch should contain the object at location 81
        let secondBatch = enumerator.nextObject() as? [Any]
        XCTAssertNotNil(secondBatch)
        XCTAssertEqual(secondBatch?.count, 1)
        XCTAssertEqual((secondBatch?.first as? PTYAnnotation)?.stringValue, "D")
    }

    /// Test that mirrors the exact tree structure from the bug report:
    /// - Location 0: 5 objects with limits 0, 0, 79, 80, 67796
    /// - Location 81: 3 objects
    /// - Location 85: 1 object
    /// - Location 67716: 2 objects
    /// - Location 67720: 1 object
    func testExactTreeStructureFromBugReport() {
        let tree = IntervalTree()

        // Location 0: 5 objects with different limits
        let obj0a = PTYAnnotation()
        obj0a.stringValue = "0a"
        tree.add(obj0a, with: Interval(location: 0, length: 0))  // [0, 0)

        let obj0b = PTYAnnotation()
        obj0b.stringValue = "0b"
        tree.add(obj0b, with: Interval(location: 0, length: 0))  // [0, 0)

        let obj0c = PTYAnnotation()
        obj0c.stringValue = "0c"
        tree.add(obj0c, with: Interval(location: 0, length: 80))  // [0, 80)

        let obj0d = PTYAnnotation()
        obj0d.stringValue = "0d"
        tree.add(obj0d, with: Interval(location: 0, length: 79))  // [0, 79)

        let obj0e = PTYAnnotation()
        obj0e.stringValue = "0e"
        tree.add(obj0e, with: Interval(location: 0, length: 67796))  // [0, 67796)

        // Location 81: 3 objects
        let obj81a = PTYAnnotation()
        obj81a.stringValue = "81a"
        tree.add(obj81a, with: Interval(location: 81, length: 80))  // [81, 161)

        let obj81b = PTYAnnotation()
        obj81b.stringValue = "81b"
        tree.add(obj81b, with: Interval(location: 81, length: 80))  // [81, 161)

        let obj81c = PTYAnnotation()
        obj81c.stringValue = "81c"
        tree.add(obj81c, with: Interval(location: 81, length: 80))  // [81, 161)

        // Location 85: 1 object
        let obj85 = PTYAnnotation()
        obj85.stringValue = "85"
        tree.add(obj85, with: Interval(location: 85, length: 15))  // [85, 100)

        // Location 67716: 2 objects
        let obj67716a = PTYAnnotation()
        obj67716a.stringValue = "67716a"
        tree.add(obj67716a, with: Interval(location: 67716, length: 80))  // [67716, 67796)

        let obj67716b = PTYAnnotation()
        obj67716b.stringValue = "67716b"
        tree.add(obj67716b, with: Interval(location: 67716, length: 80))  // [67716, 67796)

        // Location 67720: 1 object
        let obj67720 = PTYAnnotation()
        obj67720.stringValue = "67720"
        tree.add(obj67720, with: Interval(location: 67720, length: 15))  // [67720, 67735)

        // Test objectsWithSmallestLocation - should return ALL 5 at location 0
        let smallestLoc = tree.objectsWithSmallestLocation()
        XCTAssertEqual(smallestLoc?.count, 5,
                       "Should return all 5 objects at location 0")

        let names = Set((smallestLoc ?? []).compactMap { ($0 as? PTYAnnotation)?.stringValue })
        XCTAssertTrue(names.contains("0a"))
        XCTAssertTrue(names.contains("0b"))
        XCTAssertTrue(names.contains("0c"))
        XCTAssertTrue(names.contains("0d"))
        XCTAssertTrue(names.contains("0e"))

        // Test forwardLocationEnumerator
        let enumerator = tree.forwardLocationEnumerator(at: 0)

        // First batch: all 5 at location 0
        let batch0 = enumerator.nextObject() as? [Any]
        XCTAssertEqual(batch0?.count, 5,
                       "First enumeration should return all 5 objects at location 0")

        // Second batch: all 3 at location 81
        let batch81 = enumerator.nextObject() as? [Any]
        XCTAssertEqual(batch81?.count, 3,
                       "Second enumeration should return all 3 objects at location 81")

        // Third batch: 1 at location 85
        let batch85 = enumerator.nextObject() as? [Any]
        XCTAssertEqual(batch85?.count, 1)

        // Fourth batch: 2 at location 67716
        let batch67716 = enumerator.nextObject() as? [Any]
        XCTAssertEqual(batch67716?.count, 2)

        // Fifth batch: 1 at location 67720
        let batch67720 = enumerator.nextObject() as? [Any]
        XCTAssertEqual(batch67720?.count, 1)
    }
}
