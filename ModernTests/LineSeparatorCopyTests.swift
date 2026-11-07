//
//  LineSeparatorCopyTests.swift
//  iTerm2 ModernTests
//
//  Rendered Markdown uses U+2028 for line breaks inside a paragraph. Copied as
//  plain text, they must become newlines, or they paste into a shell as an
//  invisible character on one line.
//

import XCTest
import AppKit
@testable import iTerm2SharedARC

final class LineSeparatorCopyTests: XCTestCase {
    private let lineStyleKey = NSAttributedString.Key("swiftyMarkdownLineStyle")

    func testLineSeparatorsBecomeNewlinesOutsideCode() {
        let text = NSMutableAttributedString(attributedString: NSAttributedString(string: "a\u{2028}b\n",
                                                                                 attributes: [lineStyleKey: "body"]))
        text.append(NSAttributedString(string: "x\u{2028}y\u{2029}z", attributes: [lineStyleKey: "codeblock"]))
        // In code, the characters are the model's, so they're kept.
        XCTAssertEqual(text.plainTextForPasteboard, "a\nb\nx\u{2028}y\u{2029}z")
    }

    func testTextThatIsNotRenderedMarkdownIsUnchanged() {
        // A syntax-highlighted source file or a user's chat message, say.
        let text = NSAttributedString(string: "let s = \"a\u{2028}b\"")
        XCTAssertEqual(text.plainTextForPasteboard, "let s = \"a\u{2028}b\"")
    }

    func testCopyingASelectionFromAChatTextViewWritesNewlines() {
        assertCopyWritesNewlines(from: AutoSizingTextView())
    }

    // Codecierge suggestions are rendered Markdown in a plain ClickableTextView.
    func testCopyingASelectionFromAClickableTextViewWritesNewlines() {
        assertCopyWritesNewlines(from: ClickableTextView())
    }

    private func assertCopyWritesNewlines(from textView: NSTextView, file: StaticString = #filePath, line: UInt = #line) {
        textView.textStorage?.setAttributedString(NSAttributedString(string: "Run this:\u{2028}make clean",
                                                                     attributes: [lineStyleKey: "body"]))
        textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("LineSeparatorCopyTests-\(UUID().uuidString)"))
        defer {
            pasteboard.releaseGlobally()
        }
        pasteboard.clearContents()
        // This is what copy: does: one call per writable type, which for plain text is
        // the legacy NSStringPboardType rather than .string.
        XCTAssertTrue(textView.writeSelection(to: pasteboard, types: textView.writablePasteboardTypes), file: file, line: line)
        XCTAssertEqual(pasteboard.string(forType: .string), "Run this:\nmake clean", file: file, line: line)
    }
}
