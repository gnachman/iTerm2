//
//  NSArrayITermCategoryTests.swift
//  ModernTests
//
//  Ported from iTerm2XCTests/iTermNSArrayCategoryTest.m. Covers the NSArray (iTerm) category.
//

import XCTest
@testable import iTerm2SharedARC

final class NSArrayITermCategoryTests: XCTestCase {

    // MARK: - objectsOfClasses:

    func testObjectsOfClasses_SingleClass() throws {
        let objects: NSArray = [NSNull(), 0, NSObject(), 1]
        let numbers = try XCTUnwrap(objects.objects(ofClasses: [NSNumber.self])) as NSArray
        XCTAssertEqual(numbers.count, 2)
        XCTAssertTrue(numbers.contains(0))
        XCTAssertTrue(numbers.contains(1))
    }

    func testObjectsOfClasses_MultipleClasses() throws {
        let objects: NSArray = [NSNull(), 0, NSObject(), 1]
        let numbersAndNull = try XCTUnwrap(objects.objects(ofClasses: [NSNumber.self, NSNull.self])) as NSArray
        XCTAssertEqual(numbersAndNull.count, 3)
        XCTAssertTrue(numbersAndNull.contains(0))
        XCTAssertTrue(numbersAndNull.contains(1))
        XCTAssertTrue(numbersAndNull.contains(NSNull()))
    }

    // MARK: - attributedComponentsJoinedByAttributedString:

    func testAttributedComponentsJoinedByAttributedString() {
        let attributes1: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white]
        let attributes2: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.black]
        let joinAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.red]

        let string1 = NSAttributedString(string: "one", attributes: attributes1)
        let string2 = NSAttributedString(string: "two", attributes: attributes2)
        let joiner = NSAttributedString(string: ",", attributes: joinAttributes)

        let array: NSArray = [string1, string2]
        let joined = array.attributedComponentsJoined(by: joiner)

        let expected = NSMutableAttributedString()
        expected.append(string1)
        expected.append(joiner)
        expected.append(string2)

        XCTAssertEqual(expected, joined)
    }

    // MARK: - mapWithBlock: and filteredArrayUsingBlock:

    func testMapWithBlock() {
        let input: NSArray = [1, 2, 3]
        let actual = input.map({ anObject in
            return NSNumber(value: ((anObject as? NSNumber)?.intValue ?? 0) * 2)
        }) as? [NSNumber]
        XCTAssertEqual(actual, [2, 4, 6])
    }

    func testFilteredArrayUsingBlock() {
        let input: NSArray = [1, 2, 3, 4]
        let actual = input.filteredArray({ anObject in
            return (((anObject as? NSNumber)?.intValue ?? 0) % 2) == 0
        }) as? [NSNumber]
        XCTAssertEqual(actual, [2, 4])
    }

    // MARK: - containsObjectBesides:

    func testContainsObjectBesides_EmptyArray() {
        let empty: NSArray = []
        XCTAssertFalse(empty.containsObjectBesides(1))
    }

    func testContainsObjectBesides_OneElement() {
        let oneElement: NSArray = [1]
        XCTAssertFalse(oneElement.containsObjectBesides(1))
        XCTAssertTrue(oneElement.containsObjectBesides(2))
    }

    func testContainsObjectBesides_TwoElements() {
        let twoElements: NSArray = [1, 2]
        XCTAssertTrue(twoElements.containsObjectBesides(0))
        XCTAssertTrue(twoElements.containsObjectBesides(1))
        XCTAssertTrue(twoElements.containsObjectBesides(2))
    }

    // MARK: - numbersAsHexStrings

    func testNumbersAsHexStrings() {
        let inputs: NSArray = [1, 17, 4294967295]
        XCTAssertEqual(inputs.numbersAsHexStrings(), "0x1 0x11 0xffffffff")
    }

    // MARK: - componentsJoinedWithOxfordComma

    func testComponentsJoinedWithOxfordComma_ZeroElements() {
        let input: NSArray = []
        XCTAssertEqual(input.componentsJoinedWithOxfordComma(), "")
    }

    func testComponentsJoinedWithOxfordComma_OneElement() {
        let input: NSArray = ["one"]
        XCTAssertEqual(input.componentsJoinedWithOxfordComma(), "one")
    }

    func testComponentsJoinedWithOxfordComma_TwoElements() {
        let input: NSArray = ["one", "two"]
        XCTAssertEqual(input.componentsJoinedWithOxfordComma(), "one and two")
    }

    func testComponentsJoinedWithOxfordComma_ThreeElements() {
        let input: NSArray = ["one", "two", "three"]
        XCTAssertEqual(input.componentsJoinedWithOxfordComma(), "one, two, and three")
    }

    func testComponentsJoinedWithOxfordComma_FourElements() {
        let input: NSArray = ["one", "two", "three", "four"]
        XCTAssertEqual(input.componentsJoinedWithOxfordComma(), "one, two, three, and four")
    }
}
