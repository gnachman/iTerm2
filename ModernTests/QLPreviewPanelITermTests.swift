//
//  QLPreviewPanelITermTests.swift
//  ModernTests
//
//  Characterization tests for the category QLPreviewPanel (iTerm):
//  +sharedPreviewPanelIfExists returns the shared panel when one exists and
//  nil otherwise, never creating it. Written against the Objective-C runtime
//  so they run unchanged against a Swift extension with the same selector.
//

import XCTest
import ObjectiveC
import Quartz
@testable import iTerm2SharedARC

final class QLPreviewPanelITermTests: XCTestCase {
    private let selector = NSSelectorFromString("sharedPreviewPanelIfExists")

    private func sharedPreviewPanelIfExists() -> AnyObject? {
        return (QLPreviewPanel.self as AnyObject).perform(selector)?.takeUnretainedValue()
    }

    func testSelectorAndEncoding() {
        guard let method = class_getClassMethod(QLPreviewPanel.self, selector),
              let encoding = method_getTypeEncoding(method) else {
            XCTFail("no method")
            return
        }
        XCTAssertEqual(String(cString: encoding), "@16@0:8")
    }

    // Nil while no shared panel exists, without creating one; once one exists
    // (made here by +sharedPreviewPanel, which does not order it in), that
    // very panel. Another test may already have created the shared panel, in
    // which case only the second half applies.
    func testReturnsTheSharedPanelOnlyWhenItExists() {
        if !QLPreviewPanel.sharedPreviewPanelExists() {
            XCTAssertNil(sharedPreviewPanelIfExists())
            XCTAssertFalse(QLPreviewPanel.sharedPreviewPanelExists())
        }
        guard let panel = QLPreviewPanel.shared() else {
            XCTFail("no shared panel")
            return
        }
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(QLPreviewPanel.sharedPreviewPanelExists())
        XCTAssertTrue(sharedPreviewPanelIfExists() === panel)
    }
}
