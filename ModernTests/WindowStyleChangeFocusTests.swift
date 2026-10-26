//
//  WindowStyleChangeFocusTests.swift
//  ModernTests
//
//  Changing a window's style between one with a title bar and one without replaces the
//  NSWindow. The replacement used to be ordered front without becoming key or getting a first
//  responder, so typing went nowhere and Window menu items that act on the current window were
//  disabled until the user clicked it (QA findings F-139, F-154, F-040).
//
//  Whether a window can be key depends on the test host being the active app, which these tests
//  can't control, so the key-window check only runs when the original window was key. The first
//  responder doesn't depend on that, so it is always checked.
//

import XCTest
@testable import iTerm2SharedARC

final class WindowStyleChangeFocusTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!

    override func setUp() {
        super.setUp()
        fixture = TerminalWindowTestFixture()
    }

    override func tearDown() {
        fixture.close()
        fixture = nil
        super.tearDown()
    }

    private func change(to windowType: iTermWindowType, file: StaticString = #filePath, line: UInt = #line) {
        let terminal = fixture.terminal
        let oldWindow = fixture.window
        let wasKey = oldWindow.isKeyWindow
        terminal.change(to: windowType)
        let newWindow = fixture.window
        XCTAssertFalse(newWindow === oldWindow, "The window was not replaced", file: file, line: line)
        XCTAssertTrue(newWindow.firstResponder === terminal.currentSession()?.mainResponder,
                      "First responder is \(String(describing: newWindow.firstResponder))",
                      file: file, line: line)
        if wasKey {
            XCTAssertTrue(newWindow.isKeyWindow, "The replacement window is not key", file: file, line: line)
        }
    }

    func testRemovingTheTitleBarKeepsFocusInTheSession() {
        change(to: .WINDOW_TYPE_NO_TITLE_BAR)
    }

    func testCenteredNoTitleBarKeepsFocusInTheSession() {
        change(to: .WINDOW_TYPE_CENTERED_NO_TITLE_BAR)
    }

    /// Focus in another view that moves with the content view, such as the find bar, stays there
    /// rather than jumping to the session.
    func testFocusedTextFieldInTheContentViewKeepsFocus() throws {
        let terminal = fixture.terminal
        let contentView = try XCTUnwrap(fixture.window.contentView)
        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 100, height: 22))
        contentView.addSubview(field)
        defer { field.removeFromSuperview() }
        XCTAssertTrue(fixture.window.makeFirstResponder(field))
        let oldWindow = fixture.window
        terminal.change(to: .WINDOW_TYPE_NO_TITLE_BAR)
        let newWindow = fixture.window
        XCTAssertFalse(newWindow === oldWindow)
        let editor = newWindow.firstResponder as? NSTextView
        XCTAssertTrue(editor?.delegate === field,
                      "First responder is \(String(describing: newWindow.firstResponder))")
    }

    /// Moving focus back to a text field selects all of its text, so the next keystroke would
    /// replace the query instead of continuing it. The caret and selection survive (F-422).
    func testFocusedTextFieldKeepsItsSelection() throws {
        let terminal = fixture.terminal
        let contentView = try XCTUnwrap(fixture.window.contentView)
        let field = NSSearchField(frame: NSRect(x: 10, y: 10, width: 100, height: 22))
        field.stringValue = "ECHO"
        contentView.addSubview(field)
        defer { field.removeFromSuperview() }
        XCTAssertTrue(fixture.window.makeFirstResponder(field))
        let oldEditor = try XCTUnwrap(fixture.window.firstResponder as? NSTextView)
        oldEditor.setSelectedRange(NSRange(location: 2, length: 1))

        terminal.change(to: .WINDOW_TYPE_NO_TITLE_BAR)

        let editor = try XCTUnwrap(fixture.window.firstResponder as? NSTextView)
        XCTAssertTrue(editor.delegate === field)
        XCTAssertEqual(editor.string, "ECHO")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 1))
    }

    func testRestoringTheTitleBarKeepsFocusInTheSession() {
        change(to: .WINDOW_TYPE_NO_TITLE_BAR)
        change(to: .WINDOW_TYPE_NORMAL)
    }
}
