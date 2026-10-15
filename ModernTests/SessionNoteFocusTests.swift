//
//  SessionNoteFocusTests.swift
//  ModernTests
//
//  When a session note that holds keyboard focus goes away because a script hid or cleared it,
//  focus must go back to the terminal. Otherwise the window is left with no first responder and
//  every keystroke is dropped until the user clicks somewhere.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class SessionNoteFocusTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!
    private var session: PTYSession!

    override func setUp() {
        super.setUp()
        fixture = TerminalWindowTestFixture()
        session = fixture.terminal.currentSession()
    }

    override func tearDown() {
        fixture.close()
        fixture = nil
        session = nil
        super.tearDown()
    }

    private var firstResponder: NSResponder? {
        return fixture.window.firstResponder
    }

    // Shows the note the way the Edit Session Note command does, which focuses its text.
    private func showFocusedNote(text: String) {
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": text])!))
        session.textViewEditSessionNote()
        XCTAssertTrue(session.view!.isSessionNoteVisible)
        XCTAssertTrue(firstResponder is NSTextView)
        XCTAssertFalse(firstResponder === session.mainResponder)
    }

    func testClearingAFocusedNoteReturnsFocusToTheTerminal() {
        showFocusedNote(text: "start")

        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": ""])!))

        XCTAssertFalse(session.view!.isSessionNoteVisible)
        XCTAssertTrue(firstResponder === session.mainResponder)
    }

    func testHidingAFocusedNoteReturnsFocusToTheTerminal() {
        showFocusedNote(text: "start")

        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["visible": false])!))

        XCTAssertFalse(session.view!.isSessionNoteVisible)
        XCTAssertTrue(firstResponder === session.mainResponder)
    }

    func testTogglingAFocusedNoteClosedReturnsFocusToTheTerminal() {
        showFocusedNote(text: "start")

        session.textViewEditSessionNote()

        XCTAssertFalse(session.view!.isSessionNoteVisible)
        XCTAssertTrue(firstResponder === session.mainResponder)
    }

    // An emptied note hides itself when it loses focus. That happens while focus is moving to
    // whatever the user picked, so the note must not pull focus back to the terminal.
    func testEmptyNoteLosingFocusLetsFocusGoWhereTheUserPutIt() {
        let other = NSTextField(frame: NSRect(x: 0, y: 0, width: 50, height: 20))
        fixture.window.contentView?.addSubview(other)
        defer { other.removeFromSuperview() }
        showFocusedNote(text: "start")
        guard let noteTextView = firstResponder as? NSTextView else {
            XCTFail("Note is not focused")
            return
        }
        noteTextView.selectAll(nil)
        noteTextView.insertText("", replacementRange: noteTextView.selectedRange())
        XCTAssertEqual(session.sessionNoteModel?.text, "")

        XCTAssertTrue(fixture.window.makeFirstResponder(other))

        XCTAssertFalse(session.view!.isSessionNoteVisible)
        XCTAssertTrue(other.currentEditor() != nil)
        XCTAssertTrue(firstResponder === other.currentEditor())
    }

    // Hiding a note that does not have focus must leave focus where it is.
    func testHidingAnUnfocusedNoteLeavesFocusAlone() {
        let other = NSTextField(frame: NSRect(x: 0, y: 0, width: 50, height: 20))
        fixture.window.contentView?.addSubview(other)
        defer { other.removeFromSuperview() }
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "start", "visible": true])!))
        XCTAssertTrue(fixture.window.makeFirstResponder(other))
        let focused = firstResponder

        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["visible": false])!))

        XCTAssertFalse(session.view!.isSessionNoteVisible)
        XCTAssertTrue(firstResponder === focused)
    }
}
