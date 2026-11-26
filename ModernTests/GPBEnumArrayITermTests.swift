//
//  GPBEnumArrayITermTests.swift
//  ModernTests
//
//  Characterization tests for the category GPBEnumArray (iTerm):
//  -it_contains: says whether any element's -valueAtIndex: equals the value.
//  -valueAtIndex: gives kGPBUnrecognizedEnumeratorValue for a raw value the
//  array's validation function rejects, so such a value is found only under
//  that name. Written against the Objective-C so they run unchanged against
//  a Swift extension with the same selector.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class GPBEnumArrayITermTests: XCTestCase {
    private let selector = NSSelectorFromString("it_contains:")

    // The array PTYSession reads: a prompt monitor request's modes.
    private func modes(_ values: [ITMPromptMonitorMode]) -> GPBEnumArray {
        let request = ITMPromptMonitorRequest()
        for value in values {
            request.modesArray.addValue(value.rawValue)
        }
        return request.modesArray
    }

    func testSelectorAndEncoding() {
        guard let method = class_getInstanceMethod(GPBEnumArray.self, selector),
              let encoding = method_getTypeEncoding(method) else {
            XCTFail("no method")
            return
        }
        XCTAssertEqual(String(cString: encoding), "B20@0:8i16")
    }

    func testEmptyArrayContainsNothing() {
        let array = modes([])
        XCTAssertFalse(array.it_contains(ITMPromptMonitorMode.prompt.rawValue))
        XCTAssertFalse(array.it_contains(0))
    }

    func testFindsEachElement() {
        let array = modes([.prompt, .commandEnd])
        XCTAssertTrue(array.it_contains(ITMPromptMonitorMode.prompt.rawValue))
        XCTAssertTrue(array.it_contains(ITMPromptMonitorMode.commandEnd.rawValue))
    }

    func testDoesNotFindAMissingValue() {
        let array = modes([.prompt, .commandEnd])
        XCTAssertFalse(array.it_contains(ITMPromptMonitorMode.commandStart.rawValue))
        XCTAssertFalse(array.it_contains(-1))
    }

    func testUnrecognizedRawValueIsFoundOnlyAsTheUnrecognizedValue() {
        let array = modes([.prompt])
        array.addRawValue(99)
        XCTAssertEqual(array.count, 2)
        XCTAssertFalse(array.it_contains(99))
        XCTAssertTrue(array.it_contains(Int32(kGPBUnrecognizedEnumeratorValue)))
    }

    func testArrayWithoutValidationFunction() {
        let array = GPBEnumArray(validationFunction: nil)
        array.addValue(7)
        array.addValue(Int32.min)
        XCTAssertTrue(array.it_contains(7))
        XCTAssertTrue(array.it_contains(Int32.min))
        XCTAssertFalse(array.it_contains(Int32.max))
    }
}
