//
//  PTYTextViewTextReplacementCountTests.swift
//  ModernTests
//
//  When the text input system replaces text before the cursor, PTYTextView
//  decides how many backspaces to send. These drive a real PTYTextView over a
//  real VT100Screen so the count reflects actual cell contents: text that
//  wraps onto the cursor's row, and cells holding more than one UTF-16 unit
//  (an e with a combining acute accent is one cell but two UTF-16 units).
//

import XCTest
@testable import iTerm2SharedARC

final class PTYTextViewTextReplacementCountTests: XCTestCase {
    private var session: FakeSession!
    private var screen: VT100Screen!
    private var textView: PTYTextView!

    override func setUp() {
        super.setUp()
        session = FakeSession()
        screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal?.termType = "xterm"
            mutableState.terminal?.encoding = String.Encoding.utf8.rawValue
            self.screen.destructivelySetScreenWidth(10, height: 5, mutableState: mutableState)
        })
        textView = PTYTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        textView.dataSource = screen
    }

    private func feed(_ string: String) {
        screen.inject(string.data(using: .utf8)!)
        screen.performBlock(joinedThreads: { _, _, _ in })
    }

    // The NSTextInputClient location just after the cursor's cell.
    private var cursorLocation: Int {
        return textView.selectedRange().location
    }

    private func charactersToReplace(utf16Length: Int) -> Int {
        return textView.keyboardHandler(textView.keyboardHandler,
                                        numberOfCharactersToReplaceIn: NSRange(location: cursorLocation - utf16Length,
                                                                               length: utf16Length))
    }

    func testReplacementOnCursorRow() {
        feed("abc world")

        XCTAssertEqual(charactersToReplace(utf16Length: 5), 5)
    }

    func testReplacementCrossingSoftWrap() {
        // Width 10, so “world” wraps: “0123456wor” then “ld” with the cursor after it.
        feed("0123456world")

        XCTAssertEqual(charactersToReplace(utf16Length: 5), 5)
    }

    func testReplacementWithMultiUnitCellBeforeCursor() {
        // “aéb” is three cells and four UTF-16 units.
        feed("xae\u{301}b")

        XCTAssertEqual(charactersToReplace(utf16Length: 4), 3)
    }

    func testReplacementAfterMultiUnitCells() {
        // Each “é” is one cell and two UTF-16 units, so they push the text before the cursor past
        // a count of cells.
        feed("e\u{301}e\u{301}ab")

        XCTAssertEqual(charactersToReplace(utf16Length: 2), 2)
    }

    // Voice Control selects text through accessibility and inserts with no replacement range.
    private func charactersToReplaceForAccessibilitySelection(fromX startX: Int32, toX endX: Int32, y: Int32) -> Int? {
        textView.accessibilityHelperSetSelectedRange(VT100GridCoordRangeMake(startX, y, endX, y))
        var count = 0
        guard textView.keyboardHandler(textView.keyboardHandler,
                                       shouldInsertTextReplacingSelectedCharacters: &count) else {
            return nil
        }
        return count
    }

    func testAccessibilitySelectionEndingInWhitespaceCountsTheWhitespace() {
        feed("foo bar ")

        XCTAssertEqual(charactersToReplaceForAccessibilitySelection(fromX: 4, toX: 8, y: 0), 4)
    }

    func testAccessibilitySelectionWithMultiUnitCell() {
        feed("xae\u{301}b")

        XCTAssertEqual(charactersToReplaceForAccessibilitySelection(fromX: 1, toX: 4, y: 0), 3)
    }
}
