//
//  TabContentEditSessionTests.swift
//  ModernTests
//
//  Changes in the tab content editor apply to the profile as they're made,
//  so open windows show them, and Cancel puts the profile back.
//

import XCTest
@testable import iTerm2SharedARC

final class TabContentEditSessionTests: XCTestCase {
    // A profile's stored values. A key that isn't here isn't set.
    private var stored: [String: Any] = [:]
    private var writes = 0

    private func makeSession(_ editor: TabContentEditorWindowController) -> TabContentEditSession {
        return TabContentEditSession(editor: editor,
                                     read: { [unowned self] key in self.stored[key] },
                                     write: { [unowned self] changes, removals in
                                         self.writes += 1
                                         for (key, value) in changes {
                                             self.stored[key] = value
                                         }
                                         for key in removals {
                                             self.stored.removeValue(forKey: key)
                                         }
                                     })
    }

    private func makeEditor() -> TabContentEditorWindowController {
        var profile: [AnyHashable: Any] = [KEY_GUID: "me"]
        for (key, value) in stored {
            profile[key] = value
        }
        let editor = TabContentEditorWindowController(profile: profile)
        _ = editor.window
        return editor
    }

    private func select(_ editor: TabContentEditorWindowController, _ identifier: String) {
        let row = editor.layoutPropertyList.firstIndex { $0["id"] as? String == identifier }!
        editor.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private func makeBold(_ editor: TabContentEditorWindowController, _ identifier: String) {
        select(editor, identifier)
        editor.boldCheckbox.state = .on
        editor.boldCheckbox.sendAction(editor.boldCheckbox.action, to: editor.boldCheckbox.target)
    }

    // Opening the editor and applying without changing anything writes
    // nothing, so a profile that never set these keeps following defaults.
    func testNothingChangedWritesNothing() {
        stored = [KEY_SUBTITLE: "sub"]
        let editor = makeEditor()
        let session = makeSession(editor)
        session.apply()
        XCTAssertEqual(writes, 0)
        XCTAssertNil(stored[KEY_TAB_CONTENT_LINES])
        XCTAssertNil(stored[KEY_TAB_CONTENT_LAYOUT])
        XCTAssertNil(stored[KEY_TAB_CONTENT_MAXIMUM_LINES])
    }

    func testApplyWritesTheChange() {
        let editor = makeEditor()
        let session = makeSession(editor)
        makeBold(editor, TabContentSlot.directoryID)
        session.apply()
        let lines = stored[KEY_TAB_CONTENT_LINES] as? [String: Any]
        XCTAssertEqual((lines?[TabContentSlot.directoryID] as? [String: Any])?["bold"] as? Bool, true)
        XCTAssertNil(stored[KEY_TAB_CONTENT_LAYOUT], "the layout didn't change")
    }

    // Cancel puts back what was stored, and removes what wasn't.
    func testRevertRestoresTheOriginalValues() {
        stored = [KEY_SUBTITLE: "sub", KEY_TAB_CONTENT_MAXIMUM_LINES: 3]
        let editor = makeEditor()
        let session = makeSession(editor)
        makeBold(editor, TabContentSlot.directoryID)
        editor.lineLimitCheckbox.state = .off
        editor.lineLimitCheckbox.sendAction(editor.lineLimitCheckbox.action, to: editor.lineLimitCheckbox.target)
        // Another line, so the bold one's override stays.
        select(editor, TabContentSlot.jobID)
        editor.addRemoveControl.selectedSegment = 1
        editor.addRemoveControl.sendAction(editor.addRemoveControl.action, to: editor.addRemoveControl.target)
        session.apply()
        XCTAssertNotNil(stored[KEY_TAB_CONTENT_LINES])
        XCTAssertNotNil(stored[KEY_TAB_CONTENT_LAYOUT])
        XCTAssertEqual(stored[KEY_TAB_CONTENT_MAXIMUM_LINES] as? Int, 0)

        session.revert()
        XCTAssertNil(stored[KEY_TAB_CONTENT_LINES])
        XCTAssertNil(stored[KEY_TAB_CONTENT_LAYOUT])
        XCTAssertEqual(stored[KEY_TAB_CONTENT_MAXIMUM_LINES] as? Int, 3)
        XCTAssertEqual(stored[KEY_SUBTITLE] as? String, "sub")
    }

    // A change undone in the editor goes back to the stored value, not an
    // explicit copy of it.
    func testUndoingAChangeInTheEditorRestoresTheStoredValue() {
        let editor = makeEditor()
        let session = makeSession(editor)
        makeBold(editor, TabContentSlot.directoryID)
        session.apply()
        editor.boldCheckbox.state = .off
        editor.boldCheckbox.sendAction(editor.boldCheckbox.action, to: editor.boldCheckbox.target)
        session.apply()
        XCTAssertNil(stored[KEY_TAB_CONTENT_LINES])
    }

    func testSubtitleEditsApply() {
        stored = [KEY_SUBTITLE: "old"]
        let editor = makeEditor()
        let session = makeSession(editor)
        select(editor, TabContentSlot.subtitleID)
        editor.textField.stringValue = "new"
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: editor.textField)
        session.apply()
        XCTAssertEqual(stored[KEY_SUBTITLE] as? String, "new")
        session.revert()
        XCTAssertEqual(stored[KEY_SUBTITLE] as? String, "old")
    }
}
