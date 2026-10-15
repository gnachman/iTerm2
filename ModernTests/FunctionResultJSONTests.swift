//
//  FunctionResultJSONTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

final class FunctionResultJSONTests: XCTestCase {
    /// F-128: a built-in function that returns NSNull (None) must produce the
    /// JSON "null", not an empty result that makes the Python client raise.
    func testNullResultIsJSONNull() {
        XCTAssertEqual(iTermAPIHelper.jsonResult(forFunctionValue: NSNull()), "null")
    }

    func testOtherResultsAreUnchanged() {
        XCTAssertEqual(iTermAPIHelper.jsonResult(forFunctionValue: NSNumber(value: 3)), "3")
        XCTAssertEqual(iTermAPIHelper.jsonResult(forFunctionValue: "hi"), "\"hi\"")
    }
}
