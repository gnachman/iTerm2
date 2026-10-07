//
//  FloatingPaneCommandTests.swift
//  ModernTests
//
//  Menu commands for floats: keyboard move and resize, z-order, and hide and show.
//

import XCTest
@testable import iTerm2SharedARC

final class FloatingPaneCommandTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!
    private let floatFrame = NSRect(x: 60, y: 60, width: 300, height: 200)

    override func setUp() {
        super.setUp()
        fixture = TerminalWindowTestFixture()
        var frame = fixture.window.frame
        frame.size = NSSize(width: 900, height: 650)
        fixture.window.setFrame(frame, display: true)
    }

    override func tearDown() {
        fixture.close()
        fixture = nil
        super.tearDown()
    }

    private var tab: PTYTab {
        guard let tab = fixture.terminal.currentTab() else {
            it_fatalError("No tab")
        }
        return tab
    }

    private var terminal: PseudoTerminal {
        return fixture.terminal
    }

    private func pane(_ session: PTYSession) -> iTermFloatingPaneView {
        guard let pane = tab.floatingPane(for: session) else {
            it_fatalError("No pane")
        }
        return pane
    }

    /// Calls -[PseudoTerminal validateMenuItem:], which is not in its header.
    private func validate(_ item: NSMenuItem) -> Bool {
        let selector = NSSelectorFromString("validateMenuItem:")
        typealias Validate = @convention(c) (AnyObject, Selector, NSMenuItem) -> Bool
        let implementation = terminal.method(for: selector)
        return unsafeBitCast(implementation, to: Validate.self)(terminal, selector, item)
    }

    private func isEnabled(_ action: Selector) -> Bool {
        return validate(NSMenuItem(title: "", action: action, keyEquivalent: ""))
    }

    /// Performs an action that is not in PseudoTerminal's header.
    private func perform(_ name: String) {
        terminal.perform(NSSelectorFromString(name), with: nil)
    }

    // MARK: - Keyboard resize and move

    func testMoveDividerCommandsResizeTheActiveFloatByOneCell() {
        let float = fixture.addFloat(frame: floatFrame)
        tab.setActiveSession(float)
        let columns = float.columns
        let rows = float.rows
        XCTAssertTrue(isEnabled(NSSelectorFromString("movePaneDividerRight:")))

        perform("movePaneDividerRight:")
        XCTAssertEqual(float.columns, columns + 1)
        perform("movePaneDividerLeft:")
        XCTAssertEqual(float.columns, columns)
        perform("movePaneDividerDown:")
        XCTAssertEqual(float.rows, rows + 1)
        perform("movePaneDividerUp:")
        XCTAssertEqual(float.rows, rows)
    }

    func testMoveCommandsMoveTheActiveFloatByOneCell() {
        let float = fixture.addFloat(frame: floatFrame)
        tab.setActiveSession(float)
        guard let metrics = FloatingPaneLayout.metrics(for: float) else {
            XCTFail("No metrics")
            return
        }
        let start = pane(float).outlineFrame
        XCTAssertTrue(isEnabled(#selector(PseudoTerminal.moveFloatingPaneRight(_:))))

        terminal.moveFloatingPaneRight(nil)
        XCTAssertEqual(pane(float).outlineFrame.minX, start.minX + metrics.cellSize.width)
        terminal.moveFloatingPaneDown(nil)
        XCTAssertEqual(pane(float).outlineFrame.minY, start.minY - metrics.cellSize.height,
                       "down is toward smaller y in the unflipped container")
        terminal.moveFloatingPaneLeft(nil)
        terminal.moveFloatingPaneUp(nil)
        XCTAssertEqual(pane(float).outlineFrame, start)
    }

    func testFloatCommandsAreDisabledWhenATiledPaneIsActive() {
        fixture.addFloat(frame: floatFrame)
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        tab.setActiveSession(tiled)
        XCTAssertFalse(isEnabled(#selector(PseudoTerminal.moveFloatingPaneRight(_:))))
        XCTAssertFalse(isEnabled(#selector(PseudoTerminal.bringFloatingPaneToFront(_:))))
        XCTAssertTrue(isEnabled(#selector(PseudoTerminal.toggleFloatingPanesHidden(_:))))
    }

    func testSplitCommandsAreDisabledWhileAFloatIsActive() {
        let float = fixture.addFloat(frame: floatFrame)
        tab.setActiveSession(float)
        XCTAssertFalse(isEnabled(NSSelectorFromString("splitVertically:")))
        XCTAssertFalse(isEnabled(NSSelectorFromString("splitHorizontally:")))
    }

    // MARK: - Z-order

    func testBringToFrontAndSendToBack() {
        let back = fixture.addFloat(frame: floatFrame)
        let front = fixture.addFloat(frame: floatFrame.offsetBy(dx: 30, dy: 30))
        tab.setActiveSession(back)

        terminal.bringFloatingPaneToFront(nil)
        XCTAssertEqual(tab.floatingSessions(), [front, back])
        XCTAssertTrue(tab.realRootView?.subviews.last === pane(back))

        terminal.sendFloatingPaneToBack(nil)
        XCTAssertEqual(tab.floatingSessions(), [back, front])
        XCTAssertTrue(tab.realRootView?.subviews.last === pane(front))
        XCTAssertTrue(tab.realRootView?.subviews.first === tab.rootView, "floats stay above the tiled layout")
    }

    func testActivatingAFloatDoesNotRaiseIt() {
        let back = fixture.addFloat(frame: floatFrame)
        let front = fixture.addFloat(frame: floatFrame)
        tab.setActiveSession(back)
        XCTAssertEqual(tab.floatingSessions(), [back, front], "only a click or Bring to Front raises")
    }

    // MARK: - Hide and show

    func testHidingFloatsHidesThemAndMovesFocusToATiledPane() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let float = fixture.addFloat(frame: floatFrame)
        tab.setActiveSession(tiled)
        tab.setActiveSession(float)

        terminal.toggleFloatingPanesHidden(nil)
        XCTAssertTrue(tab.floatingPanesHidden)
        XCTAssertTrue(pane(float).isHidden)
        XCTAssertTrue(tab.activeSession === tiled, "focus goes to the most recently used visible session")
        XCTAssertEqual(tab.sessions(), [tiled, float], "hidden floats keep running")

        terminal.toggleFloatingPanesHidden(nil)
        XCTAssertFalse(tab.floatingPanesHidden)
        XCTAssertFalse(pane(float).isHidden)
    }

    func testActivatingAHiddenFloatShowsTheFloats() {
        let float = fixture.addFloat(frame: floatFrame)
        let other = fixture.addFloat(frame: floatFrame.offsetBy(dx: 20, dy: 20))
        tab.floatingPanesHidden = true
        tab.setActiveSession(float)
        XCTAssertFalse(tab.floatingPanesHidden)
        XCTAssertFalse(pane(float).isHidden)
        XCTAssertFalse(pane(other).isHidden)
    }

    func testAFloatAddedWhileHiddenStartsHidden() {
        fixture.addFloat(frame: floatFrame)
        tab.floatingPanesHidden = true
        let added = fixture.addFloat(frame: floatFrame)
        XCTAssertTrue(pane(added).isHidden)
    }

    func testHideMenuItemShowsItsState() {
        fixture.addFloat(frame: floatFrame)
        let item = NSMenuItem(title: "", action: #selector(PseudoTerminal.toggleFloatingPanesHidden(_:)), keyEquivalent: "")
        XCTAssertTrue(validate(item))
        XCTAssertEqual(item.state, .off)
        tab.floatingPanesHidden = true
        XCTAssertTrue(validate(item))
        XCTAssertEqual(item.state, .on)
    }

    func testHideIsDisabledWithoutFloats() {
        XCTAssertFalse(isEnabled(#selector(PseudoTerminal.toggleFloatingPanesHidden(_:))))
    }

    // MARK: - Hidden floats indicator

    func testTiledPanesIndicateHiddenFloats() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let second = fixture.split(tiled, vertically: true)
        let float = fixture.addFloat(frame: floatFrame)
        fixture.addFloat(frame: floatFrame)
        XCTAssertEqual(tiled.textViewNumberOfHiddenFloatingPanes(), 0, "nothing is hidden yet")

        tab.floatingPanesHidden = true
        XCTAssertEqual(tiled.textViewNumberOfHiddenFloatingPanes(), 2)
        XCTAssertEqual(second.textViewNumberOfHiddenFloatingPanes(), 2, "every tiled pane shows it")
        XCTAssertEqual(float.textViewNumberOfHiddenFloatingPanes(), 0, "a float never shows it")

        tab.floatingPanesHidden = false
        XCTAssertEqual(tiled.textViewNumberOfHiddenFloatingPanes(), 0)
    }

    func testHiddenFloatsIndicatorHelpTextHasTheCount() {
        let helper = iTermIndicatorsHelper()
        helper.hiddenFloatingPaneCount = 3
        let text = helper.helpTextForIndicator(withName: kiTermIndicatorHiddenFloatingPanes, sessionID: "x") ?? ""
        XCTAssertTrue(text.contains("3"), text)
    }

    func testTheIndicatorShowsWhatHappenedInHiddenFloats() {
        let saved = iTermPreferences.bool(forKey: kPreferenceKeyShowNewOutputIndicator)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyShowNewOutputIndicator)
        defer {
            iTermPreferences.setBool(saved, forKey: kPreferenceKeyShowNewOutputIndicator)
        }
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let float = fixture.addFloat(frame: floatFrame)
        tab.setActiveSession(tiled)
        tab.floatingPanesHidden = true
        XCTAssertEqual(tab.hiddenFloatingPanesActivity, .none, "nothing has happened since hiding")
        XCTAssertNil(tab.sessionHiddenFloatingPanesBadge())

        // Output after hiding.
        float.setValue(Date.timeIntervalSinceReferenceDate + 1, forKey: "lastOutputIgnoringOutputAfterResizing")
        tab.perform(NSSelectorFromString("updateLabelAttributes"))
        XCTAssertEqual(tab.hiddenFloatingPanesActivity, .newOutput)
        XCTAssertNotNil(tab.sessionHiddenFloatingPanesBadge())

        // A bell outranks new output.
        float.bell = true
        XCTAssertEqual(tab.hiddenFloatingPanesActivity, .bell)

        // Showing the floats clears it.
        float.bell = false
        tab.floatingPanesHidden = false
        XCTAssertEqual(tab.hiddenFloatingPanesActivity, .none)
        XCTAssertEqual(tab.sessionNumberOfHiddenFloatingPanes(), 0)
    }

    // MARK: - Docking

    func testDockMovesTheFloatIntoTheTiledLayout() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let float = fixture.addFloat(frame: floatFrame)
        tab.setActiveSession(float)
        XCTAssertTrue(isEnabled(NSSelectorFromString("dockFloatingPane:")))

        perform("dockFloatingPane:")

        XCTAssertEqual(tab.tiledSessions(), [tiled, float], "docked to the right of the tiled pane")
        XCTAssertTrue(tab.floatingPanes.isEmpty)
        XCTAssertTrue(tab.activeSession === float)
        XCTAssertTrue(float.view?.superview === tab.rootView)
    }

    func testTheIsFloatingVariableFollowsTheSession() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let float = fixture.addFloat(frame: floatFrame)
        let isFloating = { (session: PTYSession) in
            session.genericScope.value(forVariableName: iTermVariableKeySessionIsFloating) as? Bool
        }
        XCTAssertEqual(isFloating(float), true)
        XCTAssertEqual(isFloating(tiled), false)

        tab.setActiveSession(float)
        perform("dockFloatingPane:")
        XCTAssertEqual(isFloating(float), false)
    }

    func testDockIsDisabledForATiledPaneAndWhenLayoutIsLocked() {
        let float = fixture.addFloat(frame: floatFrame)
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        tab.setActiveSession(tiled)
        XCTAssertFalse(isEnabled(NSSelectorFromString("dockFloatingPane:")))
        tab.setActiveSession(float)
        perform("toggleLayoutLocked:")
        XCTAssertFalse(isEnabled(NSSelectorFromString("dockFloatingPane:")))
        perform("toggleLayoutLocked:")
    }

    // MARK: - Split selection

    func testPickingAPaneToMoveIntoHidesFloats() {
        let float = fixture.addFloat(frame: floatFrame)
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        terminal.setSplitSelectionMode(true, excludingSession: tiled, move: true)
        XCTAssertTrue(pane(float).isHidden, "floats would cover the panes to pick from")
        XCTAssertFalse(tab.floatingPanesHidden, "this is not the hide toggle")
        terminal.setSplitSelectionMode(false, excludingSession: tiled, move: true)
        XCTAssertFalse(pane(float).isHidden)
    }

    /// Moving a float to a split: the float being moved stays visible, because it shows which pane
    /// is moving and clicking it cancels. Other floats are hidden.
    func testPickingWhereToMoveAFloatKeepsThatFloatVisible() {
        let source = fixture.addFloat(frame: floatFrame)
        let other = fixture.addFloat(frame: NSRect(x: 300, y: 250, width: 200, height: 150))
        terminal.setSplitSelectionMode(true, excludingSession: source, move: true)
        XCTAssertFalse(pane(source).isHidden, "the float being moved is where to cancel")
        XCTAssertTrue(pane(other).isHidden)
        terminal.setSplitSelectionMode(false, excludingSession: source, move: true)
        XCTAssertFalse(pane(source).isHidden)
        XCTAssertFalse(pane(other).isHidden)
    }

    func testPickingAPaneToSwapWithKeepsFloatsVisible() {
        let float = fixture.addFloat(frame: floatFrame)
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        terminal.setSplitSelectionMode(true, excludingSession: tiled, move: false)
        XCTAssertFalse(pane(float).isHidden, "a float is a fair swap target")
        terminal.setSplitSelectionMode(false, excludingSession: tiled, move: false)
    }

    // MARK: - Swap

    /// Each takes the other's place: the tiled pane becomes a float with the old float's frame, and
    /// the float's split view still has no delegate (one made the tab refit it on every resize).
    func testSwappingAFloatWithATiledPaneKeepsTheFloatsFrame() {
        let float = fixture.addFloat(frame: floatFrame)
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let floatPane = pane(float)
        let frame = floatPane.outlineFrame
        tab.swapSession(float, with: tiled)

        XCTAssertTrue(tab.floatingSessions()?.first === tiled)
        XCTAssertTrue(tab.tiledSessions()?.first === float)
        XCTAssertTrue(tab.floatingPane(for: tiled) === floatPane)
        XCTAssertEqual(floatPane.outlineFrame.origin, frame.origin)
        XCTAssertEqual(floatPane.outlineFrame.width, frame.width, accuracy: CGFloat(tiled.textview?.charWidth ?? 10))
        XCTAssertEqual(floatPane.outlineFrame.height, frame.height, accuracy: CGFloat(tiled.textview?.lineHeight ?? 20))
        XCTAssertNil(floatPane.splitView.delegate)
    }

    // MARK: - Resize requests from the program

    func testAProgramResizingAFloatChangesItsGridAndNotTheWindow() {
        let float = fixture.addFloat(frame: floatFrame)
        let windowFrame = fixture.window.frame
        let columns = Int(float.columns) + 5
        let rows = Int(float.rows) + 3

        XCTAssertTrue(terminal.sessionInitiatedResize(float, width: Int32(columns), height: Int32(rows)))
        XCTAssertEqual(Int(float.columns), columns)
        XCTAssertEqual(Int(float.rows), rows)
        XCTAssertEqual(fixture.window.frame, windowFrame, "a float resizes within its tab")
        XCTAssertTrue(tab.realRootView?.bounds.contains(pane(float).outlineFrame) ?? false)
    }

    func testAProgramCannotMakeAFloatLargerThanItsTab() {
        let float = fixture.addFloat(frame: floatFrame)
        let maximum = tab.sessionMaximumFloatingGridSize(float)
        XCTAssertGreaterThan(maximum.width, CGFloat(float.columns))
        XCTAssertGreaterThan(maximum.height, CGFloat(float.rows))

        XCTAssertTrue(terminal.sessionInitiatedResize(float, width: 1000, height: 1000))
        XCTAssertEqual(CGFloat(float.columns), maximum.width)
        XCTAssertEqual(CGFloat(float.rows), maximum.height)
        XCTAssertTrue(tab.realRootView?.bounds.contains(pane(float).outlineFrame) ?? false)
    }

    func testTiledSessionsHaveNoFloatingMaximum() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        XCTAssertEqual(tab.sessionMaximumFloatingGridSize(tiled), .zero)
    }

    func testIncreaseHeightWithAFloatActsOnTheTiledLayout() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let float = fixture.addFloat(frame: floatFrame)
        let floatRows = float.rows
        let tiledRows = tiled.rows

        terminal.decreaseHeight(of: float)
        XCTAssertEqual(float.rows, floatRows, "the float is not resized")
        XCTAssertEqual(tiled.rows, tiledRows - 1, "the tiled session is")
    }

    // MARK: - Synthetic sessions

    func testAFloatShowingASyntheticSessionCannotBeResizedOrDocked() {
        let float = fixture.addFloat(frame: floatFrame)
        tab.setActiveSession(float)
        guard let synthetic = terminal.syntheticSession(for: float) else {
            XCTFail("No synthetic session")
            return
        }
        let floatPane = pane(float)
        let frame = floatPane.outlineFrame
        let grid = (float.columns, float.rows)
        tab.replaceActiveSession(withSyntheticSession: synthetic)
        XCTAssertTrue(tab.floatingPane(for: synthetic) === floatPane, "the synthetic session shows in the float")
        XCTAssertTrue(tab.activeSession === synthetic)

        XCTAssertFalse(isEnabled(#selector(PseudoTerminal.dockFloatingPane(_:))))
        perform("movePaneDividerRight:")
        XCTAssertEqual(floatPane.outlineFrame, frame, "the user cannot resize it")

        // Replay resizes the synthetic session to each recorded frame's size.
        XCTAssertTrue(terminal.sessionInitiatedResize(synthetic,
                                                     width: Int32(grid.0 - 4),
                                                     height: Int32(grid.1 - 2)))
        XCTAssertEqual(Int(synthetic.columns), Int(grid.0) - 4)

        terminal.perform(NSSelectorFromString("showLiveSession:inPlaceOf:"), with: float, with: synthetic)
        XCTAssertTrue(tab.floatingPane(for: float) === floatPane)
        XCTAssertEqual(float.columns, grid.0, "the float goes back to its own grid")
        XCTAssertEqual(float.rows, grid.1)
        XCTAssertEqual(floatPane.outlineFrame, frame)
        XCTAssertTrue(isEnabled(#selector(PseudoTerminal.dockFloatingPane(_:))))
    }

    // MARK: - Context menu

    private func item(_ menu: NSMenu?, _ action: String) -> NSMenuItem? {
        return menu?.items.first { $0.action == NSSelectorFromString(action) }
    }

    private func isEnabled(_ item: NSMenuItem?) -> Bool {
        guard let item, let target = item.target as? NSObject else {
            return false
        }
        let selector = NSSelectorFromString("validateMenuItem:")
        typealias Validate = @convention(c) (AnyObject, Selector, NSMenuItem) -> Bool
        return unsafeBitCast(target.method(for: selector), to: Validate.self)(target, selector, item)
    }

    private func choose(_ item: NSMenuItem?) {
        guard let item, let action = item.action else {
            XCTFail("No item")
            return
        }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    func testAFloatsContextMenuHasFloatItemsAndNoSplit() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let back = fixture.addFloat(frame: floatFrame)
        let front = fixture.addFloat(frame: floatFrame.offsetBy(dx: 40, dy: 40))
        let menu = back.textview?.titleBarMenu()

        XCTAssertFalse(isEnabled(item(menu, "splitTextViewVertically:")))
        XCTAssertFalse(isEnabled(item(menu, "splitTextViewHorizontally:")))
        XCTAssertTrue(isEnabled(item(menu, "dockFloatingPaneFromContextMenu:")))

        choose(item(menu, "bringFloatingPaneToFrontFromContextMenu:"))
        XCTAssertEqual(tab.floatingSessions(), [front, back])
        choose(item(menu, "sendFloatingPaneToBackFromContextMenu:"))
        XCTAssertEqual(tab.floatingSessions(), [back, front])

        // The menu acts on its own pane, not the active one.
        tab.setActiveSession(front)
        choose(item(menu, "dockFloatingPaneFromContextMenu:"))
        XCTAssertEqual(tab.tiledSessions(), [tiled, back])
        XCTAssertEqual(tab.floatingSessions(), [front])

        let tiledMenu = tiled.textview?.titleBarMenu()
        XCTAssertNil(item(tiledMenu, "dockFloatingPaneFromContextMenu:"))
        XCTAssertTrue(isEnabled(item(tiledMenu, "splitTextViewVertically:")))
    }

    // MARK: - Alert on Marks in Offscreen Sessions

    /// Calls -[PTYSession shouldAlert], which is private.
    private func shouldAlertOnMark(_ session: PTYSession) -> Bool {
        let selector = NSSelectorFromString("shouldAlert")
        typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(session.method(for: selector), to: Fn.self)(session, selector)
    }

    func testHiddenFloatsAreOffscreenForMarkAlerts() {
        let saved = iTermPreferences.bool(forKey: kPreferenceKeyAlertOnMarksInOffscreenSessions)
        defer {
            iTermPreferences.setBool(saved, forKey: kPreferenceKeyAlertOnMarksInOffscreenSessions)
            NotificationCenter.default.post(name: .iTermDidToggleAlertOnMarksInOffscreenSessions,
                                            object: nil)
        }
        iTermPreferences.setBool(true, forKey: kPreferenceKeyAlertOnMarksInOffscreenSessions)
        NotificationCenter.default.post(name: .iTermDidToggleAlertOnMarksInOffscreenSessions,
                                        object: nil)
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let second = fixture.split(tiled, vertically: true)
        let float = fixture.addFloat(frame: floatFrame)
        float.perform(NSSelectorFromString("enableOffscreenMarkAlertsIfNeeded"))

        tab.setActiveSession(second)
        tab.maximize()
        XCTAssertTrue(shouldAlertOnMark(tiled), "a pane behind a maximized one is offscreen")
        XCTAssertFalse(shouldAlertOnMark(float), "a float shows over a maximized pane")
        tab.perform(NSSelectorFromString("unmaximize"))

        tab.floatingPanesHidden = true
        XCTAssertTrue(shouldAlertOnMark(float), "a hidden float is offscreen")
        tab.floatingPanesHidden = false
        XCTAssertFalse(shouldAlertOnMark(float))
    }

    // MARK: - Find Cursor

    func testFindCursorHidesFloatsThatCoverTheCursor() {
        guard let tiled = tab.tiledSessions()?.first, let textview = tiled.textview,
              let container = tab.realRootView else {
            XCTFail("No tiled session")
            return
        }
        // The cursor is at the top left of the tiled pane. Cover it.
        let top = container.bounds.maxY
        let float = fixture.addFloat(frame: NSRect(x: 0, y: top - 200, width: 300, height: 200))
        tab.setActiveSession(tiled)

        textview.beginFindCursor(true)
        XCTAssertTrue(pane(float).isHidden, "a float over the cursor is hidden")
        XCTAssertFalse(tab.floatingPanesHidden, "the hide toggle is unchanged")
        textview.endFindCursor()
        XCTAssertFalse(pane(float).isHidden)
    }

    func testFindCursorLeavesFloatsThatDoNotCoverTheCursor() {
        guard let tiled = tab.tiledSessions()?.first, let textview = tiled.textview else {
            XCTFail("No tiled session")
            return
        }
        let float = fixture.addFloat(frame: floatFrame)
        tab.setActiveSession(tiled)

        textview.beginFindCursor(true)
        XCTAssertFalse(pane(float).isHidden)
        textview.endFindCursor()
    }

    // MARK: - Key binding action

    func testNewFloatingPaneKeyBindingAction() {
        guard let tiled = tab.tiledSessions()?.first,
              let guid = ProfileModel.sharedInstance().defaultProfile()?[KEY_GUID] as? String,
              let action = iTermKeyBindingAction.withAction(.ACTION_NEW_FLOATING_PANE_WITH_PROFILE,
                                                            parameter: guid,
                                                            escaping: .none,
                                                            applyMode: .currentSession) else {
            XCTFail("No profile")
            return
        }
        XCTAssertTrue(action.displayName.contains("Floating Pane"))
        tab.setActiveSession(tiled)

        let created = expectation(description: "float created")
        let observer = NotificationCenter.default.addObserver(forName: .iTermTabFloatingPanesDidChange,
                                                              object: tab,
                                                              queue: nil) { _ in
            created.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }
        tiled.perform(action, event: nil)
        wait(for: [created], timeout: 30)
        XCTAssertEqual(tab.floatingSessions()?.count, 1)
        XCTAssertEqual(tab.tiledSessions(), [tiled], "no split was made")
    }

    @MainActor
    func testNewFloatingPanePointerAction() {
        guard let tiled = tab.tiledSessions()?.first,
              let textview = tiled.textview,
              let guid = ProfileModel.sharedInstance().defaultProfile()?[KEY_GUID] as? String,
              let event = NSEvent.mouseEvent(with: .leftMouseUp,
                                             location: .zero,
                                             modifierFlags: [],
                                             timestamp: 0,
                                             windowNumber: fixture.window.windowNumber,
                                             context: nil,
                                             eventNumber: 0,
                                             clickCount: 1,
                                             pressure: 0) else {
            XCTFail("No profile")
            return
        }
        tab.setActiveSession(tiled)
        let created = expectation(description: "float created")
        let observer = NotificationCenter.default.addObserver(forName: .iTermTabFloatingPanesDidChange,
                                                              object: tab,
                                                              queue: nil) { _ in
            created.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }
        // PTYTextView adopts PointerControllerDelegate privately.
        guard let pointerDelegate = textview as AnyObject as? PointerControllerDelegate else {
            XCTFail("Not a pointer delegate")
            return
        }
        pointerDelegate.newFloatingPane(withProfile: guid, withEvent: event)
        wait(for: [created], timeout: 30)
        XCTAssertEqual(tab.floatingSessions()?.count, 1)
    }

    // MARK: - Open style

    func testTheFloatingPaneOpenStyleAddsAFloat() {
        guard let tiled = tab.tiledSessions()?.first,
              let profile = ProfileModel.sharedInstance().defaultProfile() else {
            XCTFail("No profile")
            return
        }
        let created = expectation(description: "float created")
        iTermSessionLauncher.launchBookmark(profile,
                                            in: terminal,
                                            style: .floatingPane,
                                            withURL: nil,
                                            hotkeyWindowType: .none,
                                            makeKey: false,
                                            canActivate: false,
                                            respectTabbingMode: false,
                                            index: nil,
                                            command: nil,
                                            makeSession: nil,
                                            didMakeSession: { _ in created.fulfill() },
                                            completion: nil)
        wait(for: [created], timeout: 30)
        XCTAssertEqual(tab.floatingSessions()?.count, 1)
        XCTAssertEqual(tab.tiledSessions(), [tiled])
        XCTAssertEqual(terminal.tabs()?.count, 1, "no new tab")
    }

    // MARK: - AppleScript

    func testAppleScriptHasACreateFloatingPaneCommand() {
        func code(_ string: String) -> FourCharCode {
            return string.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
        }
        let description = NSScriptSuiteRegistry.shared().commandDescription(withAppleEventClass: code("Itrm"),
                                                                            andAppleEventCode: code("cflp"))
        XCTAssertEqual(description?.commandName, "create floating pane")
        XCTAssertTrue(PTYSession.instancesRespond(to: NSSelectorFromString("handleCreateFloatingPane:")))
    }

    // MARK: - Shared background image

    func testTheSharedBackgroundImageSpansTheTabContainer() {
        let float = fixture.addFloat(frame: floatFrame)
        XCTAssertTrue(tab.sessionContainerView(float) === tab.realRootView,
                      "slices are computed against the whole tab, which floats can be anywhere in")
    }
}
