//
//  NSNullITermTests.swift
//  ModernTests
//
//  Characterization tests for the category NSNull (iTerm): -it_jsonSafeValue
//  returns the receiver. NSObject (iTerm) implements the same selector the
//  same way; NSNull carries its own implementation. Written against the
//  Objective-C runtime interface so they run unchanged against a Swift
//  extension with the same selector.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class NSNullITermTests: XCTestCase {
    private let selector = NSSelectorFromString("it_jsonSafeValue")

    func testReturnsTheReceiver() {
        let result = NSNull().perform(selector)?.takeUnretainedValue()
        XCTAssertTrue(result === NSNull())
    }

    // NSNull has its own implementation, not only NSObject's.
    func testNSNullImplementsTheSelectorItself() {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(NSNull.self, &count) else {
            XCTFail("no method list")
            return
        }
        defer { free(methods) }
        let own = (0..<Int(count)).map { method_getName(methods[$0]) }
        XCTAssertTrue(own.contains(selector))
    }

    func testSelectorAndEncoding() {
        guard let method = class_getInstanceMethod(NSNull.self, selector),
              let encoding = method_getTypeEncoding(method) else {
            XCTFail("no method")
            return
        }
        XCTAssertEqual(String(cString: encoding), "@16@0:8")
    }

    // The callers: NSDictionary's and NSArray's -it_jsonSafeValue keep NSNull
    // values as they are.
    func testCollectionsKeepNullValues() {
        let dictionary = (["a": NSNull()] as NSDictionary).it_jsonSafeValue() as? NSDictionary
        XCTAssertTrue(dictionary?["a"] as AnyObject === NSNull())
        let array = ([NSNull()] as NSArray).it_jsonSafeValue() as? NSArray
        XCTAssertEqual(array?.count, 1)
        XCTAssertTrue(array?.firstObject as AnyObject === NSNull())
    }
}
