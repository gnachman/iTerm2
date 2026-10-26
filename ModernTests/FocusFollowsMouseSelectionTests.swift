//
//  FocusFollowsMouseSelectionTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

/// F-038: when focus follows mouse returned focus to a find field, making it
/// first responder selected the whole query, so the next key replaced it.
@MainActor
final class FocusFollowsMouseSelectionTests: XCTestCase {
    func testCaretIsRestoredWhenFocusReturnsToATextField() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        let findField = NSTextField(frame: NSRect(x: 10, y: 10, width: 100, height: 22))
        let other = NSTextField(frame: NSRect(x: 150, y: 10, width: 100, height: 22))
        window.contentView?.addSubview(findField)
        window.contentView?.addSubview(other)
        findField.stringValue = "rst"

        XCTAssertTrue(window.makeFirstResponder(findField))
        let editor = try XCTUnwrap(findField.currentEditor())
        editor.selectedRange = NSRange(location: 3, length: 0)
        XCTAssertTrue(PaneFocusFollowsMouseAppEnvironment.textField(editedIn: window) === findField)

        // Focus moves away...
        PaneFocusFollowsMouseAppEnvironment.rememberSelection(in: window)
        XCTAssertTrue(window.makeFirstResponder(other))

        // ...and back. AppKit selects everything; the caret is then restored.
        XCTAssertTrue(window.makeFirstResponder(findField))
        PaneFocusFollowsMouseAppEnvironment.restoreSelection(of: findField)
        XCTAssertEqual(try XCTUnwrap(findField.currentEditor()).selectedRange, NSRange(location: 3, length: 0))
        window.close()
    }

    /// A selection saved before the text changed is not restored.
    func testStaleSelectionIsNotRestored() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        let findField = NSTextField(frame: NSRect(x: 10, y: 10, width: 100, height: 22))
        let other = NSTextField(frame: NSRect(x: 150, y: 10, width: 100, height: 22))
        window.contentView?.addSubview(findField)
        window.contentView?.addSubview(other)
        findField.stringValue = "rst"

        XCTAssertTrue(window.makeFirstResponder(findField))
        try XCTUnwrap(findField.currentEditor()).selectedRange = NSRange(location: 1, length: 0)
        PaneFocusFollowsMouseAppEnvironment.rememberSelection(in: window)
        XCTAssertTrue(window.makeFirstResponder(other))
        findField.stringValue = "rstuvw"

        XCTAssertTrue(window.makeFirstResponder(findField))
        let defaultSelection = try XCTUnwrap(findField.currentEditor()).selectedRange
        PaneFocusFollowsMouseAppEnvironment.restoreSelection(of: findField)
        XCTAssertEqual(try XCTUnwrap(findField.currentEditor()).selectedRange, defaultSelection)
        window.close()
    }
}
