//
//  TabContentEditorWindowControllerTests.swift
//  ModernTests
//
//  Drives the tab content editor sheet's controls and checks what it would
//  save.
//

import XCTest
@testable import iTerm2SharedARC

final class TabContentEditorWindowControllerTests: XCTestCase {
    // Window fitting waits until the current event is done, so it can't move
    // views under a click.
    private func drainMainQueue() {
        let expectation = XCTestExpectation(description: "main queue")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 30)
    }

    private func makeEditor(profile: [AnyHashable: Any] = [KEY_GUID: "me", KEY_SUBTITLE: "sub"]) -> TabContentEditorWindowController {
        let editor = TabContentEditorWindowController(profile: profile)
        _ = editor.window
        return editor
    }

    private func select(_ editor: TabContentEditorWindowController, _ identifier: String) {
        let row = TabContentLayout.defaultLayout.slots.firstIndex { $0.identifier == identifier }!
        editor.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    func testShowsTheLayout() {
        let editor = makeEditor()
        XCTAssertEqual(editor.tableView.numberOfRows, TabContentLayout.defaultLayout.slots.count)
        XCTAssertEqual(editor.tableView.selectedRow, 0)
        XCTAssertEqual(editor.textField.stringValue, "\\(tab.title)")
        XCTAssertGreaterThan(editor.previewView.height, 0)
        XCTAssertEqual(editor.previewView.lines.count, TabContentLayout.defaultLayout.slots.count)
    }

    func testSelectingALineShowsItsSettings() {
        let editor = makeEditor()
        select(editor, TabContentSlot.subtitleID)
        XCTAssertEqual(editor.textField.stringValue, "sub")
        XCTAssertEqual(editor.boldCheckbox.state, .off)
        XCTAssertEqual(editor.colorPopup.indexOfSelectedItem, 1, "subtitle defaults to dimmed")
        XCTAssertFalse(editor.resetButton.isEnabled)
    }

    func testCheckboxEditsBecomeProfileOverrides() {
        let editor = makeEditor()
        select(editor, TabContentSlot.directoryID)
        editor.boldCheckbox.performClick(nil)
        XCTAssertEqual(editor.overrides[TabContentSlot.directoryID] as? NSDictionary, ["bold": true] as NSDictionary)
        XCTAssertTrue(editor.resetButton.isEnabled)
        editor.resetButton.performClick(nil)
        XCTAssertNil(editor.overrides[TabContentSlot.directoryID])
        XCTAssertEqual(editor.boldCheckbox.state, .off)
    }

    func testTypingEditsTheLine() {
        let editor = makeEditor()
        select(editor, TabContentSlot.jobID)
        editor.textField.stringValue = "\\(user.task)"
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: editor.textField)
        XCTAssertEqual(editor.overrides[TabContentSlot.jobID] as? NSDictionary, ["text": "\\(user.task)"] as NSDictionary)
        XCTAssertEqual(editor.previewView.lines[3].text, "task")
    }

    func testSizeEditsTheGlobalLayout() {
        let editor = makeEditor()
        let before = editor.previewView.height
        editor.sizePopup.selectItem(at: 0)  // Large
        editor.sizePopup.sendAction(editor.sizePopup.action, to: editor.sizePopup.target)
        XCTAssertEqual(editor.layoutPropertyList.first?["size"] as? String, "large")
        XCTAssertGreaterThan(editor.previewView.height, before)
    }

    private func limit(_ editor: TabContentEditorWindowController, to lines: Int?) {
        if let lines {
            // As a click on the stepper would.
            editor.lineLimitField.stepper.integerValue = lines
            editor.lineLimitField.stepper.sendAction(editor.lineLimitField.stepper.action,
                                                     to: editor.lineLimitField.stepper.target)
        }
        let state: NSControl.StateValue = lines == nil ? .off : .on
        if editor.lineLimitCheckbox.state != state {
            editor.lineLimitCheckbox.performClick(nil)
        }
    }

    // The line limit is global, like the layout, and the preview shows it.
    // The field is used only while the checkbox is on.
    func testLineLimit() {
        let editor = makeEditor()
        XCTAssertEqual(editor.lineLimit, 0, "no limit")
        XCTAssertEqual(editor.lineLimitCheckbox.state, .off)
        XCTAssertFalse(editor.lineLimitField.isEnabled)
        XCTAssertFalse(editor.lineLimitChanged)
        let before = editor.previewView.height
        limit(editor, to: 1)
        XCTAssertTrue(editor.lineLimitField.isEnabled)
        XCTAssertEqual(editor.lineLimit, 1)
        XCTAssertTrue(editor.lineLimitChanged)
        XCTAssertLessThan(editor.previewView.height, before)
        limit(editor, to: nil)
        XCTAssertEqual(editor.lineLimit, 0)
        XCTAssertFalse(editor.lineLimitField.isEnabled)
    }

    // How many lines a line wraps to is a number field with a stepper.
    func testLinesField() {
        let editor = makeEditor()
        select(editor, TabContentSlot.directoryID)
        XCTAssertEqual(editor.linesField.value, 1)
        editor.linesField.stepper.integerValue = 2  // as a click on the stepper would
        editor.linesField.stepper.sendAction(editor.linesField.stepper.action, to: editor.linesField.stepper.target)
        XCTAssertEqual(editor.layoutPropertyList[2]["lines"] as? Int, 2)
    }

    // Whether rich content is on is the Window pane's checkbox, not the
    // sheet's. The sheet can be edited either way.
    func testEditableWhateverTheSwitch() {
        let editor = makeEditor(profile: [KEY_GUID: "me", KEY_SHOW_RICH_TAB_CONTENT: false])
        select(editor, TabContentSlot.directoryID)
        XCTAssertTrue(editor.tableView.isEnabled)
        XCTAssertTrue(editor.textField.isEnabled)
        XCTAssertTrue(editor.lineLimitCheckbox.isEnabled)
    }

    // The well changes the line only while its color is Custom: a color
    // dropped on it, or sent by a color panel left open, is ignored otherwise.
    func testColorWellChangesOnlyACustomColor() {
        let editor = makeEditor()
        select(editor, TabContentSlot.titleID)
        let shown = editor.colorWell.color
        editor.colorWell.color = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        editor.colorWell.sendAction(editor.colorWell.action, to: editor.colorWell.target)
        XCTAssertNil(editor.overrides[TabContentSlot.titleID], "Normal, so the well is off")
        XCTAssertEqual(editor.colorWell.color, shown, "and it shows the line's color again")

        editor.colorPopup.selectItem(at: 2)
        editor.colorPopup.sendAction(editor.colorPopup.action, to: editor.colorPopup.target)
        let blue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        editor.colorWell.color = blue
        editor.colorWell.sendAction(editor.colorWell.action, to: editor.colorWell.target)
        let stored = (editor.overrides[TabContentSlot.titleID] as? [String: Any])?["color"] as? NSDictionary
        XCTAssertEqual(stored?.colorValue()?.usingColorSpace(.sRGB)?.blueComponent ?? 0, 1, accuracy: 0.01)
    }

    // Separate light and dark colors are a choice for Custom only. Turning
    // them on shows a second well, for dark mode.
    func testSeparateColorsForLightAndDarkMode() {
        let editor = makeEditor()
        select(editor, TabContentSlot.titleID)
        XCTAssertFalse(editor.separateColorsCheckbox.isEnabled, "Normal has no colors to separate")
        XCTAssertTrue(editor.darkColorWell.isHidden)
        XCTAssertFalse(editor.darkColorWell.isEnabled)

        editor.colorPopup.selectItem(at: 2)
        editor.colorPopup.sendAction(editor.colorPopup.action, to: editor.colorPopup.target)
        XCTAssertTrue(editor.separateColorsCheckbox.isEnabled)
        XCTAssertTrue(editor.darkColorWell.isHidden)

        editor.separateColorsCheckbox.state = .on
        editor.separateColorsCheckbox.sendAction(editor.separateColorsCheckbox.action, to: editor.separateColorsCheckbox.target)
        XCTAssertFalse(editor.darkColorWell.isHidden)
        XCTAssertTrue(editor.darkColorWell.isEnabled)

        let blue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        editor.darkColorWell.color = blue
        editor.darkColorWell.sendAction(editor.darkColorWell.action, to: editor.darkColorWell.target)
        let fields = editor.overrides[TabContentSlot.titleID] as? [String: Any]
        XCTAssertEqual(fields?["separateColors"] as? Bool, true)
        let stored = fields?["darkColor"] as? NSDictionary
        XCTAssertEqual(stored?.colorValue()?.usingColorSpace(.sRGB)?.blueComponent ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(editor.previewView.lines[0].darkColor?.usingColorSpace(.sRGB)?.blueComponent ?? 0, 1, accuracy: 0.01)

        editor.colorPopup.selectItem(at: 0)
        editor.colorPopup.sendAction(editor.colorPopup.action, to: editor.colorPopup.target)
        XCTAssertFalse(editor.separateColorsCheckbox.isEnabled)
        XCTAssertEqual(editor.separateColorsCheckbox.state, .off)
        XCTAssertTrue(editor.darkColorWell.isHidden)
        XCTAssertNil(editor.overrides[TabContentSlot.titleID])
    }

    // A dark color sent while separate colors are off is ignored.
    func testDarkWellIgnoredWithoutSeparateColors() {
        let editor = makeEditor()
        select(editor, TabContentSlot.titleID)
        editor.colorPopup.selectItem(at: 2)
        editor.colorPopup.sendAction(editor.colorPopup.action, to: editor.colorPopup.target)
        editor.darkColorWell.color = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        editor.darkColorWell.sendAction(editor.darkColorWell.action, to: editor.darkColorWell.target)
        let fields = editor.overrides[TabContentSlot.titleID] as? [String: Any]
        XCTAssertNil(fields?["darkColor"])
        XCTAssertNil(fields?["separateColors"])
    }

    // Changes are reported so they can be shown in open windows right away,
    // once for a burst of changes rather than once each.
    func testChangesAreReportedOncePerBurst() {
        let editor = makeEditor()
        var reports = 0
        editor.changeHandler = { reports += 1 }
        select(editor, TabContentSlot.directoryID)
        editor.boldCheckbox.state = .on
        editor.boldCheckbox.sendAction(editor.boldCheckbox.action, to: editor.boldCheckbox.target)
        editor.sizePopup.selectItem(at: 0)
        editor.sizePopup.sendAction(editor.sizePopup.action, to: editor.sizePopup.target)
        XCTAssertEqual(reports, 0, "not until the current event is done")
        drainMainQueue()
        XCTAssertEqual(reports, 1)
    }

    // Once the sheet ends, a report still pending can't undo what its owner
    // did on Cancel.
    func testNoReportAfterTheSheetEnds() {
        let editor = makeEditor()
        var reports = 0
        editor.changeHandler = { reports += 1 }
        select(editor, TabContentSlot.directoryID)
        editor.boldCheckbox.state = .on
        editor.boldCheckbox.sendAction(editor.boldCheckbox.action, to: editor.boldCheckbox.target)
        editor.cancelButton.performClick(nil)
        drainMainQueue()
        XCTAssertEqual(reports, 0)
    }

    // The sheet is as tall as its content; only its width can change. The
    // preview grows and shrinks with the layout, and the sheet with it.
    func testWindowResizesOnlyHorizontally() throws {
        let editor = makeEditor()
        let window = try XCTUnwrap(editor.window)
        XCTAssertEqual(window.contentMaxSize.height, window.contentMinSize.height)
        XCTAssertGreaterThan(window.contentMaxSize.width, window.contentMinSize.width)
        let before = window.contentMinSize.height

        select(editor, TabContentSlot.directoryID)
        editor.linesField.stepper.integerValue = 3
        editor.linesField.stepper.sendAction(editor.linesField.stepper.action, to: editor.linesField.stepper.target)
        XCTAssertEqual(window.contentMinSize.height, before, "not until the current event is done")
        drainMainQueue()
        XCTAssertGreaterThan(window.contentMinSize.height, before)
        XCTAssertEqual(window.contentMaxSize.height, window.contentMinSize.height)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).height, window.contentMinSize.height)
    }

    // Notes wrap rather than widen the window, and a width change rewraps
    // them, so the height is measured again: shorter when wide, taller when
    // narrow.
    func testHeightFollowsTheWidth() throws {
        let editor = makeEditor()
        let window = try XCTUnwrap(editor.window)
        let contentView = try XCTUnwrap(window.contentView)
        func height(atWidth width: CGFloat) -> CGFloat {
            var frame = window.frame
            frame.size.width = width
            window.setFrame(frame, display: false)
            contentView.layoutSubtreeIfNeeded()
            XCTAssertEqual(window.contentMaxSize.height, window.contentMinSize.height, "width \(width)")
            return window.contentRect(forFrameRect: window.frame).height
        }
        let wide = height(atWidth: 1600)
        let narrow = height(atWidth: window.contentMinSize.width)
        XCTAssertLessThan(window.contentMinSize.width, 600, "notes wrap instead of setting the width")
        XCTAssertGreaterThan(narrow, wide, "narrow \(narrow) at \(window.contentMinSize.width), wide \(wide)")
    }

    // Removing a line while a number is being typed in Lines shows the next
    // line's number, and the typed one can't land on that line.
    func testRemovingWhileTypingInLinesShowsTheNextLine() throws {
        let editor = makeEditor()
        let window = try XCTUnwrap(editor.window)
        // The directory line, which will take the subtitle's place, wraps to 2.
        select(editor, TabContentSlot.directoryID)
        editor.linesField.stepper.integerValue = 2
        editor.linesField.stepper.sendAction(editor.linesField.stepper.action, to: editor.linesField.stepper.target)
        select(editor, TabContentSlot.subtitleID)
        XCTAssertTrue(window.makeFirstResponder(editor.linesField.textField))
        XCTAssertNotNil(editor.linesField.textField.currentEditor(), "precondition: editing")
        editor.linesField.textField.currentEditor()?.string = "3"
        editor.addRemoveControl.selectedSegment = 1
        editor.addRemoveControl.sendAction(editor.addRemoveControl.action, to: editor.addRemoveControl.target)
        XCTAssertNil(editor.linesField.textField.currentEditor())
        XCTAssertEqual(editor.linesField.textField.integerValue, 2, "the directory line, now selected")
        window.makeFirstResponder(nil)
        XCTAssertEqual(editor.layoutPropertyList[1]["lines"] as? Int, 2, "the typed number didn’t land on it")
    }

    // Adding a line while a number is being typed in Lines keeps the number,
    // on the line it was typed for.
    func testAddingWhileTypingInLinesKeepsTheNumber() throws {
        let editor = makeEditor()
        let window = try XCTUnwrap(editor.window)
        select(editor, TabContentSlot.directoryID)
        XCTAssertTrue(window.makeFirstResponder(editor.linesField.textField))
        XCTAssertNotNil(editor.linesField.textField.currentEditor(), "precondition: editing")
        editor.linesField.textField.currentEditor()?.string = "3"
        editor.addRemoveControl.selectedSegment = 0
        editor.commitPendingEdits()
        XCTAssertEqual(editor.layoutPropertyList[2]["lines"] as? Int, 3)
    }

    // Ending edits before + or − leaves the line list focused when nothing
    // was being typed, so arrow keys keep moving through the lines.
    func testCommittingKeepsTheListFocused() throws {
        let editor = makeEditor()
        let window = try XCTUnwrap(editor.window)
        XCTAssertTrue(window.makeFirstResponder(editor.tableView))
        editor.commitPendingEdits()
        XCTAssertTrue(window.firstResponder === editor.tableView)
    }

    // Notes take the sheet's width rather than wrapping in a narrow column.
    func testNotesUseTheWidth() throws {
        let editor = makeEditor()
        let window = try XCTUnwrap(editor.window)
        var frame = window.frame
        frame.size.width = 1400
        window.setFrame(frame, display: false)
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        func notes(_ view: NSView) -> [NSTextField] {
            return view.subviews.flatMap { sub -> [NSTextField] in
                let mine = (sub as? NSTextField).map { $0.stringValue.hasPrefix("Lines past") ? [$0] : [] } ?? []
                return mine + notes(sub)
            }
        }
        let note = try XCTUnwrap(notes(content).first)
        XCTAssertGreaterThan(note.frame.width, 600, "\(note.frame)")
    }

    // When the preview gets shorter, the window catches up after the current
    // event. Until then the line's settings must stay where they are rather
    // than spreading into the spare room.
    func testControlsStayPutWhileTheWindowCatchesUp() throws {
        let editor = makeEditor()
        let window = try XCTUnwrap(editor.window)
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        // On screen, since the window shrinks from the bottom.
        func sizeFrame() -> NSRect {
            return window.convertToScreen(editor.sizePopup.convert(editor.sizePopup.bounds, to: nil))
        }
        let before = sizeFrame()
        let previewHeight = editor.previewView.height
        limit(editor, to: 2)
        XCTAssertLessThan(editor.previewView.height, previewHeight, "precondition: the preview got shorter")
        content.layoutSubtreeIfNeeded()
        // Nothing stretches into the spare room: Auto Layout broke that tie
        // differently in the app, putting it between the line's settings.
        func ambiguous(_ view: NSView) -> [NSView] {
            return (view.hasAmbiguousLayout ? [view] : []) + view.subviews.flatMap { ambiguous($0) }
        }
        XCTAssertEqual(ambiguous(content), [])
        XCTAssertEqual(sizeFrame(), before)
        XCTAssertEqual(editor.previewView.frame.height, editor.previewView.height)
        let stack = try XCTUnwrap(content.subviews.first as? NSStackView)
        XCTAssertEqual(stack.frame.height, stack.fittingSize.height, accuracy: 0.5, "the spare room is below everything")
        drainMainQueue()
        content.layoutSubtreeIfNeeded()
        XCTAssertEqual(sizeFrame(), before, "and after the window shrinks, since its top edge stays put")
    }

    // Turning the limit on starts from how many lines the layout has now, so
    // it cuts nothing until lowered.
    func testLineLimitStartsFromTheCurrentLayout() {
        let editor = makeEditor()
        let before = editor.lineLimitField.value
        select(editor, TabContentSlot.directoryID)
        editor.linesField.stepper.integerValue = 2
        editor.linesField.stepper.sendAction(editor.linesField.stepper.action, to: editor.linesField.stepper.target)
        XCTAssertEqual(editor.lineLimitField.value, before + 1)
        editor.lineLimitCheckbox.performClick(nil)
        XCTAssertEqual(editor.lineLimit, before + 1)
    }

    // Every setting comes from the profile being edited.
    func testStartsFromTheProfile() {
        let layout = TabContentLayout(slots: [TabContentSlot(identifier: TabContentSlot.titleID, size: .large),
                                              TabContentSlot(identifier: TabContentSlot.jobID, size: .small)])
        let editor = makeEditor(profile: [KEY_GUID: "me", KEY_TAB_CONTENT_LAYOUT: layout.propertyList])
        XCTAssertEqual(editor.tableView.numberOfRows, 2)
        XCTAssertEqual(editor.sizePopup.indexOfSelectedItem, TabContentLineSize.allCases.firstIndex(of: .large))
        XCTAssertFalse(editor.layoutChanged)
    }

    // Size and wrapping are part of a line like everything else, so Reset to
    // Default puts them back too.
    func testResetRestoresTheSize() {
        let editor = makeEditor()
        select(editor, TabContentSlot.directoryID)
        XCTAssertFalse(editor.resetButton.isEnabled)
        editor.sizePopup.selectItem(at: TabContentLineSize.allCases.firstIndex(of: .large)!)
        editor.sizePopup.sendAction(editor.sizePopup.action, to: editor.sizePopup.target)
        XCTAssertTrue(editor.resetButton.isEnabled)
        editor.resetButton.performClick(nil)
        XCTAssertEqual(editor.sizePopup.indexOfSelectedItem, TabContentLineSize.allCases.firstIndex(of: .small))
        XCTAssertFalse(editor.layoutChanged)
        XCTAssertFalse(editor.resetButton.isEnabled)
    }

    // The preview shows only the lines within the limit, like a tab does. It
    // can't rely on its height to cut them: an empty line within the limit
    // collapses, and a line past the limit would move up into its place.
    func testPreviewShowsOnlyTheLinesWithinTheLimit() {
        let editor = makeEditor(profile: [KEY_GUID: "me", KEY_SUBTITLE: ""])
        limit(editor, to: 2)
        XCTAssertEqual(editor.previewView.lines.count, 2)
    }

    func testLineLimitStartsAtTheSavedLimit() {
        let editor = makeEditor(profile: [KEY_GUID: "me", KEY_TAB_CONTENT_MAXIMUM_LINES: 2])
        XCTAssertEqual(editor.lineLimitCheckbox.state, .on)
        XCTAssertEqual(editor.lineLimitField.value, 2)
        XCTAssertEqual(editor.lineLimit, 2)
    }

    // The Format menu switches a line between plain text and HTML, and the
    // preview draws it that way.
    func testFormatMenu() {
        let editor = makeEditor()
        select(editor, TabContentSlot.directoryID)
        XCTAssertEqual(editor.formatPopup.indexOfSelectedItem, 0, "plain text")
        let row = TabContentLayout.defaultLayout.slots.firstIndex { $0.identifier == TabContentSlot.directoryID }!
        XCTAssertFalse(editor.previewView.lines[row].html)
        editor.formatPopup.selectItem(at: 1)
        editor.formatPopup.sendAction(editor.formatPopup.action, to: editor.formatPopup.target)
        XCTAssertEqual(editor.overrides[TabContentSlot.directoryID] as? [String: Bool], ["html": true])
        XCTAssertTrue(editor.previewView.lines[row].html)

        select(editor, TabContentSlot.jobID)
        XCTAssertEqual(editor.formatPopup.indexOfSelectedItem, 1, "the job line is HTML by default")
    }

    // The + menu lists every preset, with the ones already in the layout
    // turned off, then Custom Line.
    func testAddMenuListsEveryPreset() {
        let editor = makeEditor()
        let menu = editor.makeAddMenu()
        let items = menu.items.filter { !$0.isSeparatorItem }
        let presets = TabContentEditorModel.presetGroups.flatMap { $0 }
        XCTAssertEqual(items.count, presets.count + 1)
        for item in items.dropLast() {
            let identifier = item.representedObject as? String
            let present = TabContentLayout.defaultLayout.slots.contains { $0.identifier == identifier }
            XCTAssertEqual(editor.validateMenuItem(item), !present, identifier ?? "")
        }
        XCTAssertTrue(editor.validateMenuItem(items.last!), "Custom Line")
    }

    // Removing the line being edited must not leave its text in the field,
    // where the next keystroke would write it into the line that took its place.
    func testRemovingWhileEditingShowsTheNextLine() {
        let editor = makeEditor()
        select(editor, TabContentSlot.subtitleID)
        XCTAssertTrue(editor.window!.makeFirstResponder(editor.textField))
        XCTAssertNotNil(editor.textField.currentEditor(), "precondition: editing")
        editor.addRemoveControl.selectedSegment = 1
        editor.addRemoveControl.sendAction(editor.addRemoveControl.action, to: editor.addRemoveControl.target)
        XCTAssertEqual(editor.tableView.selectedRow, 1, "precondition: the next line is selected")
        XCTAssertEqual(editor.textField.stringValue, "\\(path)")
    }

    func testProfileGUID() {
        XCTAssertEqual(makeEditor().profileGUID, "me")
    }

    // Choosing Custom starts from the line's current color, not whatever the
    // well last held (initially black, invisible on a dark tab bar).
    func testCustomColorStartsFromTheLinesColor() {
        let editor = makeEditor()
        select(editor, TabContentSlot.titleID)
        let leftover = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        editor.colorWell.color = leftover
        editor.colorPopup.selectItem(at: 2)
        editor.colorPopup.sendAction(editor.colorPopup.action, to: editor.colorPopup.target)
        let stored = (editor.overrides[TabContentSlot.titleID] as? [String: Any])?["color"] as? NSDictionary
        let color = try! XCTUnwrap(stored?.colorValue()?.usingColorSpace(.sRGB))
        XCTAssertNotEqual(color.redComponent - color.greenComponent, 1, accuracy: 0.01)
    }
}
