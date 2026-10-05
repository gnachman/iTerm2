//
//  IntervalTreeBasicsTests.swift
//  iTerm2
//
//  Ported from the legacy iTermIntervalTreeTest.m. Covers interval queries,
//  smallest-limit lookup, removal, and a seeded randomized consistency check.
//

import XCTest
@testable import iTerm2SharedARC

final class IntervalTreeBasicsTests: XCTestCase {
    private var tree = IntervalTree()
    private var obj1 = PTYAnnotation()
    private var obj2 = PTYAnnotation()
    private var obj3 = PTYAnnotation()
    private var obj4 = PTYAnnotation()
    private var obj5 = PTYAnnotation()
    private var obj6 = PTYAnnotation()
    private var obj7 = PTYAnnotation()

    override func setUp() {
        super.setUp()
        tree = IntervalTree()
        obj1 = PTYAnnotation()
        obj2 = PTYAnnotation()
        obj3 = PTYAnnotation()
        obj4 = PTYAnnotation()
        obj5 = PTYAnnotation()
        obj6 = PTYAnnotation()
        obj7 = PTYAnnotation()
    }

    // MARK: - Helpers

    private func makeInterval(_ location: Int64, _ length: Int64) -> Interval {
        return Interval(location: location, length: length)
    }

    private func identities(_ objects: [Any]?) -> Set<ObjectIdentifier> {
        return Set((objects ?? []).map { ObjectIdentifier($0 as AnyObject) })
    }

    private func assertObjects(in interval: Interval,
                               equal expected: [PTYAnnotation],
                               file: StaticString = #filePath,
                               line: UInt = #line) {
        let found = identities(tree.objects(in: interval))
        let wanted = Set(expected.map { ObjectIdentifier($0) })
        XCTAssertEqual(found, wanted,
                       "objects in [\(interval.location), \(interval.limit)) did not match",
                       file: file,
                       line: line)
    }

    // MARK: - Basic queries

    func testEmptyTreeHasNoObjectsInInterval() {
        XCTAssertEqual(tree.objects(in: makeInterval(0, 256)).count, 0)
        XCTAssertEqual(tree.count, 0)
    }

    func testOneEntryIsFoundOnlyWithinItsInterval() {
        tree.add(obj1, with: makeInterval(100, 50))

        assertObjects(in: makeInterval(0, 100), equal: [])
        assertObjects(in: makeInterval(150, 1000), equal: [])
        assertObjects(in: makeInterval(100, 1), equal: [obj1])
        assertObjects(in: makeInterval(125, 1), equal: [obj1])
        assertObjects(in: makeInterval(149, 1), equal: [obj1])
    }

    func testDisjointEntries() {
        tree.add(obj1, with: makeInterval(10, 2))
        tree.add(obj2, with: makeInterval(20, 2))

        assertObjects(in: makeInterval(0, 10), equal: [])
        assertObjects(in: makeInterval(10, 1), equal: [obj1])
        assertObjects(in: makeInterval(10, 2), equal: [obj1])
        assertObjects(in: makeInterval(11, 1), equal: [obj1])

        assertObjects(in: makeInterval(20, 1), equal: [obj2])
        assertObjects(in: makeInterval(20, 2), equal: [obj2])
        assertObjects(in: makeInterval(21, 1), equal: [obj2])

        assertObjects(in: makeInterval(10, 12), equal: [obj1, obj2])
        assertObjects(in: makeInterval(10, 11), equal: [obj1, obj2])
        assertObjects(in: makeInterval(10, 10), equal: [obj1])
        assertObjects(in: makeInterval(0, 30), equal: [obj1, obj2])
    }

    func testTwoEntriesWithSameInterval() {
        tree.add(obj1, with: makeInterval(10, 2))
        tree.add(obj2, with: makeInterval(10, 2))

        assertObjects(in: makeInterval(0, 10), equal: [])
        assertObjects(in: makeInterval(12, 10), equal: [])
        assertObjects(in: makeInterval(10, 1), equal: [obj1, obj2])
        assertObjects(in: makeInterval(10, 2), equal: [obj1, obj2])
        assertObjects(in: makeInterval(11, 1), equal: [obj1, obj2])
    }

    // MARK: - Overlapping entries

    //  11111
    // 2222
    func testOverlapSecondStartsBeforeAndEndsInsideFirst() {
        tree.add(obj1, with: makeInterval(10, 10))
        tree.add(obj2, with: makeInterval(5, 10))

        assertObjects(in: makeInterval(0, 5), equal: [])
        assertObjects(in: makeInterval(0, 30), equal: [obj1, obj2])
        assertObjects(in: makeInterval(0, 10), equal: [obj2])
        assertObjects(in: makeInterval(10, 5), equal: [obj1, obj2])
        assertObjects(in: makeInterval(15, 5), equal: [obj1])
        assertObjects(in: makeInterval(20, 5), equal: [])
    }

    //  11111
    //  222
    func testOverlapSecondSharesStartAndIsShorter() {
        tree.add(obj1, with: makeInterval(10, 10))
        tree.add(obj2, with: makeInterval(10, 5))

        assertObjects(in: makeInterval(0, 10), equal: [])
        assertObjects(in: makeInterval(10, 1), equal: [obj1, obj2])
        assertObjects(in: makeInterval(10, 10), equal: [obj1, obj2])
        assertObjects(in: makeInterval(15, 10), equal: [obj1])
        assertObjects(in: makeInterval(20, 10), equal: [])
    }

    //  11111
    //   222
    func testOverlapSecondStrictlyInsideFirst() {
        tree.add(obj1, with: makeInterval(10, 10))
        tree.add(obj2, with: makeInterval(12, 5))

        assertObjects(in: makeInterval(0, 10), equal: [])
        assertObjects(in: makeInterval(0, 100), equal: [obj1, obj2])
        assertObjects(in: makeInterval(0, 12), equal: [obj1])
        assertObjects(in: makeInterval(0, 13), equal: [obj1, obj2])
        assertObjects(in: makeInterval(12, 1), equal: [obj1, obj2])
        assertObjects(in: makeInterval(12, 10), equal: [obj1, obj2])
        assertObjects(in: makeInterval(17, 10), equal: [obj1])
        assertObjects(in: makeInterval(20, 10), equal: [])
    }

    //  11111
    //    222
    func testOverlapSecondSharesEndOfFirst() {
        tree.add(obj1, with: makeInterval(10, 10))
        tree.add(obj2, with: makeInterval(15, 5))

        assertObjects(in: makeInterval(0, 10), equal: [])
        assertObjects(in: makeInterval(0, 11), equal: [obj1])
        assertObjects(in: makeInterval(0, 16), equal: [obj1, obj2])
        assertObjects(in: makeInterval(15, 10), equal: [obj1, obj2])
        assertObjects(in: makeInterval(0, 100), equal: [obj1, obj2])
        assertObjects(in: makeInterval(20, 100), equal: [])
    }

    //  11111
    //     222
    func testOverlapSecondStartsInsideAndEndsAfterFirst() {
        tree.add(obj1, with: makeInterval(10, 10))
        tree.add(obj2, with: makeInterval(15, 10))

        assertObjects(in: makeInterval(0, 10), equal: [])
        assertObjects(in: makeInterval(0, 11), equal: [obj1])
        assertObjects(in: makeInterval(0, 20), equal: [obj1, obj2])
        assertObjects(in: makeInterval(0, 30), equal: [obj1, obj2])
        assertObjects(in: makeInterval(15, 30), equal: [obj1, obj2])
        assertObjects(in: makeInterval(20, 30), equal: [obj2])
        assertObjects(in: makeInterval(30, 30), equal: [])
    }

    //  11111
    // 2222222
    func testOverlapSecondContainsFirst() {
        tree.add(obj1, with: makeInterval(10, 10))  // [10, 20)
        tree.add(obj2, with: makeInterval(5, 20))   // [5, 25)

        assertObjects(in: makeInterval(0, 5), equal: [])
        assertObjects(in: makeInterval(0, 10), equal: [obj2])
        assertObjects(in: makeInterval(0, 15), equal: [obj1, obj2])
        assertObjects(in: makeInterval(0, 20), equal: [obj1, obj2])
        assertObjects(in: makeInterval(0, 25), equal: [obj1, obj2])
        assertObjects(in: makeInterval(0, 30), equal: [obj1, obj2])
        assertObjects(in: makeInterval(5, 5), equal: [obj2])
        assertObjects(in: makeInterval(5, 10), equal: [obj1, obj2])
        assertObjects(in: makeInterval(0, 100), equal: [obj1, obj2])
        assertObjects(in: makeInterval(25, 100), equal: [])
    }

    // MARK: - Tree balancing

    // The legacy tests only exercised these insertion orders for crashes; they
    // now also verify the tree stays consistent and complete.
    func testInsertionOrderCausingSplitKeepsTreeConsistent() {
        tree.add(obj1, with: makeInterval(10, 10))
        tree.add(obj2, with: makeInterval(8, 10))
        tree.add(obj3, with: makeInterval(9, 10))

        tree.sanityCheck()
        XCTAssertEqual(tree.count, 3)
        assertObjects(in: makeInterval(0, 100), equal: [obj1, obj2, obj3])
    }

    func testInsertionOrderCausingSkewKeepsTreeConsistent() {
        tree.add(obj1, with: makeInterval(10, 10))
        tree.add(obj2, with: makeInterval(12, 10))
        tree.add(obj3, with: makeInterval(11, 10))

        tree.sanityCheck()
        XCTAssertEqual(tree.count, 3)
        assertObjects(in: makeInterval(0, 100), equal: [obj1, obj2, obj3])
    }

    // MARK: - Limit queries

    func testObjectsWithSmallestLimitReturnsAllObjectsSharingThatLimit() {
        tree.add(obj1, with: makeInterval(1, 2))   // limit 3
        tree.add(obj2, with: makeInterval(2, 1))   // limit 3
        tree.add(obj3, with: makeInterval(9, 10))  // limit 19

        let objects = tree.objectsWithSmallestLimit()
        XCTAssertEqual(identities(objects), Set([ObjectIdentifier(obj1), ObjectIdentifier(obj2)]))
    }

    // MARK: - Removal

    func testRemoveObjectRegression() {
        tree.add(obj1, with: makeInterval(102, 7))
        tree.add(obj2, with: makeInterval(62, 3))
        tree.add(obj3, with: makeInterval(239, 2))
        tree.add(obj4, with: makeInterval(71, 10))
        tree.add(obj5, with: makeInterval(163, 66))
        tree.add(obj6, with: makeInterval(247, 8))
        tree.add(obj7, with: makeInterval(189, 15))

        XCTAssertTrue(tree.remove(obj3))
        tree.sanityCheck()
        XCTAssertEqual(tree.count, 6)
        XCTAssertFalse(tree.contains(obj3))
        assertObjects(in: makeInterval(0, 1000), equal: [obj1, obj2, obj4, obj5, obj6, obj7])
    }

    // MARK: - Seeded randomized consistency check

    // Deterministic 64-bit generator (SplitMix64) so the test is reproducible.
    private struct SeededGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        mutating func next(below bound: Int) -> Int {
            return Int(next() % UInt64(bound))
        }
    }

    private func randomInterval(_ generator: inout SeededGenerator) -> Interval {
        let location = generator.next(below: 255)
        var length = 0
        repeat {
            length = generator.next(below: 256 - location)
        } while length == 0
        return makeInterval(Int64(location), Int64(length))
    }

    private func expectedObjects(intersecting interval: Interval,
                                 in entries: [(interval: Interval, object: PTYAnnotation)]) -> Set<ObjectIdentifier> {
        return Set(entries.filter { interval.intersects($0.interval) }.map { ObjectIdentifier($0.object) })
    }

    // The legacy version ran 1000 iterations with unseeded rand() and was
    // disabled for being slow. This one uses a fixed seed and far fewer,
    // smaller iterations so it runs in well under a second.
    func testRandomTreeMatchesBruteForceQueries() {
        var generator = SeededGenerator(seed: 0x1234_5678_9ABC_DEF0)
        let iterations = 40
        let queriesPerIteration = 30

        for iteration in 0..<iterations {
            let entryCount = 2 + iteration
            tree = IntervalTree()
            var entries: [(interval: Interval, object: PTYAnnotation)] = []
            var limits: [Int64] = []

            for _ in 0..<entryCount {
                let interval = randomInterval(&generator)
                let object = PTYAnnotation()
                limits.append(interval.limit)
                tree.add(object, with: interval)
                entries.append((interval, object))
                XCTAssertEqual(tree.count, entries.count)
                tree.sanityCheck()
            }

            let sortedLimits = limits.sorted()
            guard let smallestLimit = sortedLimits.first, let largestLimit = sortedLimits.last else {
                XCTFail("No limits recorded")
                return
            }

            let largestLimitObject = tree.objectsWithLargestLimit()?.first
            XCTAssertEqual(largestLimitObject?.entry?.interval.limit, largestLimit,
                           "iteration \(iteration)")
            let smallestLimitObject = tree.objectsWithSmallestLimit()?.first
            XCTAssertEqual(smallestLimitObject?.entry?.interval.limit, smallestLimit,
                           "iteration \(iteration)")
            XCTAssertNil(tree.objectsWithLargestLimit(before: smallestLimit), "iteration \(iteration)")
            XCTAssertNil(tree.objectsWithSmallestLimit(after: largestLimit), "iteration \(iteration)")

            // Forward limit enumeration visits every object in nondecreasing limit order.
            var forwardIndex = 0
            let forwardEnumerator = tree.forwardLimitEnumerator()
            while forwardIndex < entryCount {
                guard let objects = forwardEnumerator.nextObject() as? [IntervalTreeImmutableObject],
                      !objects.isEmpty else {
                    XCTFail("Forward limit enumerator ran dry at index \(forwardIndex) in iteration \(iteration)")
                    break
                }
                for object in objects {
                    XCTAssertLessThan(forwardIndex, entryCount)
                    guard forwardIndex < entryCount else {
                        break
                    }
                    XCTAssertEqual(object.entry?.interval.limit, sortedLimits[forwardIndex],
                                   "iteration \(iteration)")
                    forwardIndex += 1
                }
            }
            XCTAssertEqual(forwardIndex, entryCount)

            // Reverse limit enumeration visits every object in nonincreasing limit order.
            var reverseIndex = entryCount - 1
            let reverseEnumerator = tree.reverseLimitEnumerator()
            while reverseIndex >= 0 {
                guard let objects = reverseEnumerator.nextObject() as? [IntervalTreeImmutableObject],
                      !objects.isEmpty else {
                    XCTFail("Reverse limit enumerator ran dry at index \(reverseIndex) in iteration \(iteration)")
                    break
                }
                for object in objects {
                    XCTAssertGreaterThanOrEqual(reverseIndex, 0)
                    guard reverseIndex >= 0 else {
                        break
                    }
                    XCTAssertEqual(object.entry?.interval.limit, sortedLimits[reverseIndex],
                                   "iteration \(iteration)")
                    reverseIndex -= 1
                }
            }
            XCTAssertEqual(reverseIndex, -1)

            // Interval queries agree with brute force.
            var intervalsToTest: [Interval] = []
            for _ in 0..<queriesPerIteration {
                let interval = randomInterval(&generator)
                intervalsToTest.append(interval)
                XCTAssertEqual(identities(tree.objects(in: interval)),
                               expectedObjects(intersecting: interval, in: entries),
                               "iteration \(iteration)")
            }

            // Remove a fifth of the entries, then re-run the same queries.
            let numberToDelete = entryCount / 5
            for _ in 0..<numberToDelete {
                let index = generator.next(below: entries.count)
                let entry = entries.remove(at: index)
                XCTAssertTrue(tree.remove(entry.object))
                XCTAssertEqual(tree.count, entries.count)
                tree.sanityCheck()
            }

            for interval in intervalsToTest {
                XCTAssertEqual(identities(tree.objects(in: interval)),
                               expectedObjects(intersecting: interval, in: entries),
                               "iteration \(iteration) after removal")
            }
        }
    }
}
