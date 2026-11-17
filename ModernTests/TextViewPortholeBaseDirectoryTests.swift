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

    // MARK: - Base directory from the imgcat'ed document's name

    private func base(prompt: String?, name: String?, existing: Set<String>) -> String? {
        return MarkdownImageLoader.baseDirectory(promptDirectory: prompt,
                                                 documentName: name,
                                                 fileExists: { existing.contains($0) })
    }

    func testDocumentInSubdirectoryUsesItsDirectory() {
        XCTAssertEqual(base(prompt: "/Users/me", name: "qa-md/test.md", existing: ["/Users/me/qa-md/test.md"]),
                       "/Users/me/qa-md")
    }

    func testDocumentInParentDirectory() {
        XCTAssertEqual(base(prompt: "/Users/me/a", name: "../b/README.md", existing: ["/Users/me/b/README.md"]),
                       "/Users/me/b")
    }

    func testAbsoluteDocumentPathUsesItsDirectory() {
        XCTAssertEqual(base(prompt: "/tmp", name: "/Users/me/docs/x.md", existing: ["/Users/me/docs/x.md"]),
                       "/Users/me/docs")
        XCTAssertEqual(base(prompt: nil, name: "/Users/me/docs/x.md", existing: ["/Users/me/docs/x.md"]),
                       "/Users/me/docs")
    }

    func testBareNameOrNoNameUsesPromptDirectory() {
        XCTAssertEqual(base(prompt: "/Users/me", name: "test.md", existing: []), "/Users/me")
        XCTAssertEqual(base(prompt: "/Users/me", name: nil, existing: []), "/Users/me")
    }

    /// When the name doesn't lead to a file (the command changed directory
    /// before running imgcat, say), keep the prompt's directory.
    func testMissingDocumentFallsBackToPromptDirectory() {
        XCTAssertEqual(base(prompt: "/Users/me", name: "qa-md/test.md", existing: []), "/Users/me")
    }

    func testRelativeNameWithoutPromptDirectory() {
        XCTAssertNil(base(prompt: nil, name: "qa-md/test.md", existing: ["/qa-md/test.md"]))
    }
}
