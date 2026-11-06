//
//  TextViewPortholeBaseDirectoryTests.swift
//  iTerm2 ModernTests
//
//  A porthole saves the directory its text came from so that relative paths
//  (links, and Markdown images shown on click) still resolve after restoration.
//

import XCTest
@testable import iTerm2SharedARC

final class TextViewPortholeBaseDirectoryTests: XCTestCase {
    private func resolve(_ relative: String, againstSaved saved: Any?) -> String? {
        guard let base = TextViewPorthole.baseDirectory(fromSaved: saved) else {
            return nil
        }
        return URL(fileURLWithPath: relative, relativeTo: base).path
    }

    func testRelativePathResolvesInsideSavedDirectory() {
        XCTAssertEqual(resolve("img.png", againstSaved: "/Users/me/proj"), "/Users/me/proj/img.png")
    }

    func testSavedDirectoryWithSpaces() {
        XCTAssertEqual(resolve("img.png", againstSaved: "/Users/me/my proj"), "/Users/me/my proj/img.png")
    }

    func testMissingOrEmptyDirectory() {
        XCTAssertNil(TextViewPorthole.baseDirectory(fromSaved: nil))
        XCTAssertNil(TextViewPorthole.baseDirectory(fromSaved: ""))
        XCTAssertNil(TextViewPorthole.baseDirectory(fromSaved: NSNull()))
    }
}
