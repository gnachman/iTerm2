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
    var markedTextLength = 0
    // Stands in for the text input system handling a keypress that went to Cocoa.
    var interpretKeyEvents: ((iTermKeyboardHandler, [NSEvent]) -> Void)?

    func keyboardHandler(_ keyboardhandler: iTermKeyboardHandler, shouldHandleKeyDown event: NSEvent) -> Bool {
        return true
    }

    func keyboardHandler(_ keyboardhandler: iTermKeyboardHandler,
                         load context: UnsafeMutablePointer<iTermKeyboardHandlerContext>,
                         for event: NSEvent) {
        var value = iTermKeyboardHandlerContext()
        value.autorepeatMode = true
        context.pointee = value
    }

    func keyboardHandler(_ keyboardhandler: iTermKeyboardHandler, interpretKeyEvents events: [NSEvent]) {
        interpretKeyEvents?(keyboardhandler, events)
    }

    func keyboardHandler(_ keyboardhandler: iTermKeyboardHandler, sendEventToController event: NSEvent) {
        actions.append(.sendEvent(keyCode: event.keyCode, characters: event.characters))
    }

    func keyboardHandlerMarkedTextRange(_ keyboardhandler: iTermKeyboardHandler) -> NSRange {
        return NSRange(location: cursorLocation, length: markedTextLength)
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

// macOS’s “Add period with double-space” reads the text before the cursor through
// -attributedSubstringForProposedRange:actualRange: and, when you press space after a space, asks
// the client (synchronously, while it handles the keypress) to replace that space with “. ”. The
// terminal must type a plain space instead. In vim the period repeats the last command. Issue
// 13123 and QA finding F-217: the app's NSAutomaticPeriodSubstitutionEnabled=NO default didn't
// reach NSSpellChecker when running with a custom user defaults suite.
final class KeyboardHandlerPeriodSubstitutionTests: XCTestCase {
    private var handler: iTermKeyboardHandler!
    private var delegate: FakeKeyboardHandlerDelegate!
    private var inputContext: NSTextInputContext!

    override func setUp() {
        super.setUp()
        delegate = FakeKeyboardHandlerDelegate()
        handler = iTermKeyboardHandler()
        handler.keyMapper = iTermStandardKeyMapper()
        handler.delegate = delegate
        inputContext = NSTextInputContext(client: NSTextView())
        // With either of these on, keypresses go to the real -[NSTextInputContext handleEvent:]
        // instead of the delegate's interpretKeyEvents.
        pinAdvancedSetting("ExperimentalKeyHandling", to: false)
        pinAdvancedSetting("EnableCharacterAccentMenu", to: false)
    }

    private var delete: FakeKeyboardHandlerDelegate.Action {
        return .sendEvent(keyCode: UInt16(kVK_Delete), characters: "\u{7f}")
    }

    private func keyEvent(_ characters: String, keyCode: Int) -> NSEvent {
        return NSEvent.keyEvent(with: .keyDown,
                                location: .zero,
                                modifierFlags: [],
                                timestamp: 0,
                                windowNumber: 0,
                                context: nil,
                                characters: characters,
                                charactersIgnoringModifiers: characters,
                                isARepeat: false,
                                keyCode: UInt16(keyCode))!
    }

    // Presses a key while the text input system inserts `text` with `replacementRange`.
    private func press(_ characters: String = " ",
                       keyCode: Int = kVK_Space,
                       inserting text: Any,
                       replacementRange: NSRange) {
        delegate.interpretKeyEvents = { handler, _ in
            handler.insertText(text, replacementRange: replacementRange)
        }
        handler.keyDown(keyEvent(characters, keyCode: keyCode), inputContext: inputContext)
    }

    func testDoubleSpacePeriodSubstitutionInsertsPlainSpace() {
        delegate.cursorLocation = 13
        delegate.charactersInReplacementRange = 1

        press(inserting: ". ", replacementRange: NSRange(location: 12, length: 1))

        XCTAssertEqual(delegate.actions, [.insert(" ")])
    }

    // In vim the space before the cursor isn't backspaced over, so “. ” would run the repeat
    // command.
    func testDoubleSpacePeriodSubstitutionInsertsPlainSpaceWhenNotBackspacing() {
        delegate.cursorLocation = 13
        delegate.charactersInReplacementRange = 0

        press(inserting: ". ", replacementRange: NSRange(location: 12, length: 1))

        XCTAssertEqual(delegate.actions, [.insert(" ")])
    }

    func testAttributedPeriodSubstitutionInsertsPlainSpace() {
        delegate.cursorLocation = 13
        delegate.charactersInReplacementRange = 1

        press(inserting: NSAttributedString(string: ". "),
              replacementRange: NSRange(location: 12, length: 1))

        XCTAssertEqual(delegate.actions, [.insert(" ")])
    }

    // Dictation or Voice Control can replace the space before the cursor with “. ” outside of a
    // keypress. That's what the user asked for.
    func testPeriodSpaceReplacementWithoutKeypressStillReplaces() {
        delegate.cursorLocation = 13
        delegate.charactersInReplacementRange = 1

        handler.insertText(". ", replacementRange: NSRange(location: 12, length: 1))

        XCTAssertEqual(delegate.actions, [delete, .insert(". ")])
    }

    // Only pressing space triggers the substitution.
    func testPeriodSpaceReplacementDuringOtherKeypressStillReplaces() {
        delegate.cursorLocation = 13
        delegate.charactersInReplacementRange = 1

        press("a",
              keyCode: kVK_ANSI_A,
              inserting: ". ",
              replacementRange: NSRange(location: 12, length: 1))

        XCTAssertEqual(delegate.actions, [delete, .insert(". ")])
    }

    func testPeriodSpaceWithoutReplacementRangeIsInsertedUnchanged() {
        delegate.cursorLocation = 13

        press(inserting: ". ", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertEqual(delegate.actions, [.insert(". ")])
    }

    // Replacing more than the one character before the cursor is something else, like a
    // correction.
    func testPeriodSpaceReplacingMoreThanOneCharacterStillReplaces() {
        delegate.cursorLocation = 13
        delegate.charactersInReplacementRange = 2

        press(inserting: ". ", replacementRange: NSRange(location: 11, length: 2))

        XCTAssertEqual(delegate.actions, [delete, delete, .insert(". ")])
    }

    // An input method committing marked text on space owns the replacement.
    func testPeriodSpaceReplacingMarkedTextIsNotTreatedAsSubstitution() {
        delegate.cursorLocation = 13
        delegate.markedTextLength = 1

        press(inserting: ". ", replacementRange: NSRange(location: 12, length: 1))

        XCTAssertEqual(delegate.actions, [.insert(". ")])
    }
}
