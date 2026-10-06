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
}
