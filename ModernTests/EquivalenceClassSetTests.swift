//
//  EquivalenceClassSetTests.swift
//  iTerm2
//
//  Ported from the legacy iTermEquivalenceClassSetTest.m.
//

import XCTest
@testable import iTerm2SharedARC

final class EquivalenceClassSetTests: XCTestCase {
    private let n1 = NSNumber(value: 10)
    private let n2 = NSNumber(value: 11)
    private let n3 = NSNumber(value: 12)
    private let n4 = NSNumber(value: 13)

    private func assertClass(of value: NSNumber,
                             in set: EquivalenceClassSet,
                             equals expected: Set<NSNumber>,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        let members = set.valuesEqual(to: value)
        XCTAssertNotNil(members, file: file, line: line)
        let actual = Set((members ?? []).compactMap { $0 as? NSNumber })
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    func testValuesEqualToEitherMemberReturnsBothMembers() {
        let set = EquivalenceClassSet()
        set.setValue(n1, equalToValue: n2)

        assertClass(of: n1, in: set, equals: [n1, n2])
        assertClass(of: n2, in: set, equals: [n1, n2])
    }

    func testValuesEqualToUnknownValueIsEmpty() {
        let set = EquivalenceClassSet()
        set.setValue(n1, equalToValue: n2)

        XCTAssertEqual(set.valuesEqual(to: n3)?.count ?? 0, 0)
    }

    func testAddingSamePairTwiceDoesNotDuplicate() {
        let set = EquivalenceClassSet()
        set.setValue(n1, equalToValue: n2)
        set.setValue(n1, equalToValue: n2)

        assertClass(of: n1, in: set, equals: [n1, n2])
    }

    func testTwoSeparateClassesStaySeparate() {
        let set = EquivalenceClassSet()
        set.setValue(n1, equalToValue: n2)
        set.setValue(n3, equalToValue: n4)

        assertClass(of: n1, in: set, equals: [n1, n2])
        assertClass(of: n3, in: set, equals: [n3, n4])
    }

    func testMergeClasses() {
        let set = EquivalenceClassSet()
        set.setValue(n1, equalToValue: n2)
        set.setValue(n3, equalToValue: n4)

        set.setValue(n1, equalToValue: n3)
        assertClass(of: n3, in: set, equals: [n1, n2, n3, n4])
        assertClass(of: n1, in: set, equals: [n1, n2, n3, n4])
    }

    func testGrowClass() {
        let set = EquivalenceClassSet()
        set.setValue(n1, equalToValue: n2)
        set.setValue(n1, equalToValue: n3)

        assertClass(of: n1, in: set, equals: [n1, n2, n3])
    }

    func testGrowClassReverseArgs() {
        let set = EquivalenceClassSet()
        set.setValue(n1, equalToValue: n2)
        set.setValue(n3, equalToValue: n1)

        assertClass(of: n1, in: set, equals: [n1, n2, n3])
    }

    func testRemoveValueShrinksClass() {
        let set = EquivalenceClassSet()
        set.setValue(n1, equalToValue: n2)
        set.setValue(n3, equalToValue: n1)
        set.removeValue(n2)

        assertClass(of: n1, in: set, equals: [n1, n3])
    }

    func testRemoveValueErasingSetLeavesNoClass() {
        let set = EquivalenceClassSet()
        set.setValue(n1, equalToValue: n2)
        set.removeValue(n2)

        XCTAssertNil(set.valuesEqual(to: n1))
    }
}
