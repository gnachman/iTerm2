//
//  KeyboardHandlerReplacementRangeTests.swift
//  ModernTests
//
//  When the text input system replaces text that has already been sent to
//  the shell (for example, a Voice Control or dictation correction), the
//  keyboard handler must send one delete per replaced character before
//  inserting the new text. Otherwise the new text is appended after the old.
//

import XCTest
import Carbon.HIToolbox
@testable import iTerm2SharedARC

private final class FakeKeyboardHandlerDelegate: NSObject, iTermKeyboardHandlerDelegate {
    enum Action: Equatable {
        case sendEvent(keyCode: UInt16, characters: String?)
        case insert(String)
    }

    var actions = [Action]()
    var cursorLocation = 0
    var shouldInsert = true
    var charactersToReplace = 0
    var charactersInReplacementRange = 0

    func keyboardHandler(_ keyboardhandler: iTermKeyboardHandler, shouldHandleKeyDown event: NSEvent) -> Bool {
        return true
    }

    func keyboardHandler(_ keyboardhandler: iTermKeyboardHandler,
                         load context: UnsafeMutablePointer<iTermKeyboardHandlerContext>,
                         for event: NSEvent) {
    }

    func keyboardHandler(_ keyboardhandler: iTermKeyboardHandler, interpretKeyEvents events: [NSEvent]) {
    }

    func keyboardHandler(_ keyboardhandler: iTermKeyboardHandler, sendEventToController event: NSEvent) {
        actions.append(.sendEvent(keyCode: event.keyCode, characters: event.characters))
    }

    func keyboardHandlerMarkedTextRange(_ keyboardhandler: iTermKeyboardHandler) -> NSRange {
        return NSRange(location: cursorLocation, length: 0)
    }

    func keyboardHandler(_ keyboardhandler: iTermKeyboardHandler, insertText aString: String) {
        actions.append(.insert(aString))
    }

    func keyboardHandlerWindowNumber(_ keyboardhandler: iTermKeyboardHandler) -> Int {
        return 0
    }

    func keyboardHandler(_ keyboardhandler: iTermKeyboardHandler,
                         numberOfCharactersToReplaceIn range: NSRange) -> Int {
        return NSMaxRange(range) == cursorLocation ? charactersInReplacementRange : 0
    }

    func keyboardHandler(_ keyboardhandler: iTermKeyboardHandler, sendTmuxControlModeKeyEvent event: NSEvent) -> Bool {
        return false
    }

    func keyboardHandler(_ keyboardhandler: iTermKeyboardHandler,
                         shouldInsertTextReplacingSelectedCharacters count: UnsafeMutablePointer<Int>) -> Bool {
        count.pointee = charactersToReplace
        return shouldInsert
    }
}

final class KeyboardHandlerReplacementRangeTests: XCTestCase {
    private var handler: iTermKeyboardHandler!
    private var delegate: FakeKeyboardHandlerDelegate!

    override func setUp() {
        super.setUp()
        delegate = FakeKeyboardHandlerDelegate()
        handler = iTermKeyboardHandler()
        handler.keyMapper = iTermStandardKeyMapper()
        handler.delegate = delegate
    }

    private var delete: FakeKeyboardHandlerDelegate.Action {
        return .sendEvent(keyCode: UInt16(kVK_Delete), characters: "\u{7f}")
    }

    func testReplacementEndingAtCursorDeletesThenInserts() {
        delegate.cursorLocation = 13
        delegate.charactersInReplacementRange = 3

        handler.insertText("good", replacementRange: NSRange(location: 10, length: 3))

        XCTAssertEqual(delegate.actions, [delete, delete, delete, .insert("good")])
    }

    func testReplacementNotEndingAtCursorDoesNotDelete() {
        delegate.cursorLocation = 20

        handler.insertText("good", replacementRange: NSRange(location: 10, length: 3))

        XCTAssertEqual(delegate.actions, [.insert("good")])
    }

    func testNoReplacementRangeDoesNotDelete() {
        delegate.cursorLocation = 13

        handler.insertText("good", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertEqual(delegate.actions, [.insert("good")])
    }

    func testInsertionReplacingSelectionDeletesThenInserts() {
        delegate.charactersToReplace = 2

        handler.insertText("good", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertEqual(delegate.actions, [delete, delete, .insert("good")])
    }

    func testInsertionDroppedWhenSelectionCannotBeReplaced() {
        delegate.shouldInsert = false

        handler.insertText("good", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertEqual(delegate.actions, [])
    }

    // An emoji is two UTF-16 code units but one character, so it takes one backspace.
    func testReplacementDeletesCharactersNotCodeUnits() {
        delegate.cursorLocation = 12
        delegate.charactersInReplacementRange = 1

        handler.insertText("good", replacementRange: NSRange(location: 10, length: 2))

        XCTAssertEqual(delegate.actions, [delete, .insert("good")])
    }
}
