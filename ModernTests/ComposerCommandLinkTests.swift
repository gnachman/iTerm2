//
//  ComposerCommandLinkTests.swift
//  ModernTests
//
//  Cmd-hovering over the composer links the command under the mouse to an explanation. The
//  hovered character index is in the full text: prompt prefix, typed text, and the gray
//  autosuggestion. To find the command, the prefix is removed temporarily, and clearing the prefix
//  also clears the suggestion. An index that was in the suggestion was then past the end of the
//  shorter text, and paragraphRange(for:) threw “Range {17, 0} out of bounds; string length 3”.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class ComposerCommandLinkTests: XCTestCase {
    private var topLevelObjects: NSArray?
    private var textView: ComposerTextView!

    private func findComposer(in view: NSView) -> ComposerTextView? {
        if let composer = view as? ComposerTextView {
            return composer
        }
        for subview in view.subviews {
            if let composer = findComposer(in: subview) {
                return composer
            }
        }
        return nil
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        // The real composer text view comes from this nib; it has no other initializer.
        let nib = try XCTUnwrap(NSNib(nibNamed: "iTermStatusBarLargeComposerViewController",
                                      bundle: Bundle(for: ComposerTextView.self)))
        XCTAssertTrue(nib.instantiate(withOwner: nil, topLevelObjects: &topLevelObjects))
        let views = (topLevelObjects as? [Any] ?? []).compactMap { $0 as? NSView }
        textView = try XCTUnwrap(views.lazy.compactMap { self.findComposer(in: $0) }.first)
    }

    override func tearDown() {
        textView = nil
        topLevelObjects = nil
        super.tearDown()
    }

    func testHoverOverSuggestionWithPromptPrefixDoesNotThrow() throws {
        textView.string = "git"
        textView.prefix = NSMutableAttributedString(string: "$ ")
        XCTAssertEqual(textView.string, "$ git", "Precondition")
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.suggestion = " status --short"
        let length = (textView.string as NSString).length
        XCTAssertGreaterThan(length, "$ git".utf16.count, "Precondition: the suggestion is in the text")

        // An index in the middle of the suggestion, and one at the very end.
        for index in [length - 3, length] {
            XCTAssertNoThrow(try ObjCTry { _ = self.textView.characterRangeOfCommand(atCharacterIndex: index) },
                             "index \(index)")
        }
    }

    func testHoverOverTypedCommandStillFindsIt() throws {
        textView.string = "git status"
        textView.prefix = NSMutableAttributedString(string: "$ ")
        XCTAssertEqual(textView.string, "$ git status", "Precondition")
        let result = try XCTUnwrap(try ObjCTry { self.textView.characterRangeOfCommand(atCharacterIndex: 4) })
        XCTAssertEqual(result.1.trimmingCharacters(in: .whitespacesAndNewlines), "git status")
    }
}
