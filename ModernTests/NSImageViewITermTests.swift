//
//  NSImageViewITermTests.swift
//  ModernTests
//
//  Characterization tests for the category NSImageView (iTerm):
//  -it_setTintColor: sets contentTintColor, and nil clears it. Written against
//  the Objective-C runtime interface so they run unchanged against a Swift
//  extension with the same selector.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class NSImageViewITermTests: XCTestCase {
    private let selector = NSSelectorFromString("it_setTintColor:")

    func testSetsTheContentTintColor() {
        let imageView = NSImageView()
        imageView.contentTintColor = NSColor.red
        _ = imageView.perform(selector, with: NSColor.blue)
        XCTAssertEqual(imageView.contentTintColor, NSColor.blue)
    }

    func testNilClearsTheContentTintColor() {
        let imageView = NSImageView()
        imageView.contentTintColor = NSColor.red
        _ = imageView.perform(selector, with: nil)
        XCTAssertNil(imageView.contentTintColor)
    }

    func testSelectorAndEncoding() {
        guard let method = class_getInstanceMethod(NSImageView.self, selector),
              let encoding = method_getTypeEncoding(method) else {
            XCTFail("no method")
            return
        }
        XCTAssertEqual(String(cString: encoding), "v24@0:8@16")
    }
}
