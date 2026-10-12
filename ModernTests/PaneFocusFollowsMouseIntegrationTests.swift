//
//  PaneFocusFollowsMouseIntegrationTests.swift
//  ModernTests
//
//  Checks how the app environment finds the view that should take focus under the pointer, using
//  real session views. The test host has no key window and doesn't control which window is
//  frontmost, so these hit-test the fixture's window directly.
//

import XCTest
@testable import iTerm2SharedARC

private final class DeclaringView: NSView {
    let responder = NSView()

    override var it_focusFollowsMouseResponder: NSView? {
        return responder
    }
}

@MainActor
final class PaneFocusFollowsMouseIntegrationTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!
    private var session: PTYSession!
    private var sessionView: SessionView!

    override func setUp() {
        super.setUp()
        fixture = TerminalWindowTestFixture()
        session = fixture.terminal.currentSession()
        sessionView = session.view
    }

    override func tearDown() {
        fixture.close()
        fixture = nil
        super.tearDown()
    }

    // The focus target at the center of view, found the way the app does after its hit test.
    private func target(atCenterOf view: NSView) -> NSView? {
        guard let contentView = fixture.window.contentView else {
            it_fatalError("No content view")
        }
        let point = contentView.superview!.convert(fixture.center(of: view), from: nil)
        return PaneFocusFollowsMouseAppEnvironment.focusTarget(hitView: contentView.hitTest(point),
                                                               in: sessionView)
    }

    func testMainResponderIsTheSessionsMainResponder() {
        XCTAssertTrue(sessionView.focusFollowsMouseMainResponder === session.mainResponder)
    }

    func testViewsAreAttributedToTheirPane() {
        let real = PaneFocusFollowsMouseAppEnvironment()
        XCTAssertTrue(real.pane(containing: session.textview!) === sessionView)
        XCTAssertNil(real.pane(containing: NSView()))
    }

    func testTerminalTakesFocus() {
        XCTAssertTrue(target(atCenterOf: sessionView.scrollview) === session.mainResponder)
    }

    func testEditableTextFieldTakesFocus() {
        let panel = NSView(frame: NSRect(x: 10, y: 10, width: 200, height: 60))
        let field = NSTextField(frame: NSRect(x: 5, y: 5, width: 80, height: 20))
        panel.addSubview(field)
        sessionView.addSubview(belowFind: panel)
        XCTAssertTrue(target(atCenterOf: field) === field)
    }

    func testPanelBackgroundDoesNotTakeFocusUnlessItSaysSo() {
        let panel = NSView(frame: NSRect(x: 10, y: 10, width: 200, height: 60))
        sessionView.addSubview(belowFind: panel)
        XCTAssertNil(target(atCenterOf: panel))
    }

    func testPanelThatNamesAResponderGivesItFocus() {
        let panel = DeclaringView(frame: NSRect(x: 10, y: 10, width: 200, height: 60))
        sessionView.addSubview(belowFind: panel)
        XCTAssertTrue(target(atCenterOf: panel) === panel.responder)
    }

    func testAnyPartOfTheChatPanelFocusesItsInput() {
        let panel = ChatViewControllerRootView(frame: NSRect(x: 10, y: 10, width: 200, height: 200))
        let input = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        let transcript = NSView(frame: NSRect(x: 0, y: 40, width: 200, height: 160))
        panel.addSubview(input)
        panel.addSubview(transcript)
        panel.focusFollowsMouseResponderProvider = { input }
        sessionView.addSubview(belowFind: panel)
        XCTAssertTrue(target(atCenterOf: transcript) === input)
    }

    // NSSplitView widens its divider's hit area a few points into the panes beside it, so a hit
    // test there finds the split view. The pointer is still in the pane.
    func testPointBesideDividerIsInThePane() {
        let right = fixture.split(session, vertically: true)
        fixture.window.layoutIfNeeded()
        guard let rightView = right.view else {
            it_fatalError("No view")
        }
        let frame = rightView.convert(rightView.bounds, to: nil)
        let point = NSPoint(x: frame.minX + 1, y: frame.midY)
        XCTAssertTrue(PaneFocusFollowsMouseAppEnvironment.sessionView(atWindowPoint: point,
                                                                      in: fixture.window) === rightView)
    }

    func testDividerIsNotAPane() {
        let right = fixture.split(session, vertically: true)
        fixture.window.layoutIfNeeded()
        guard let rightView = right.view, let leftView = session.view else {
            it_fatalError("No view")
        }
        let leftFrame = leftView.convert(leftView.bounds, to: nil)
        let rightFrame = rightView.convert(rightView.bounds, to: nil)
        // Exactly on the divider, between the panes.
        let point = NSPoint(x: (leftFrame.maxX + rightFrame.minX) / 2, y: rightFrame.midY)
        XCTAssertGreaterThan(rightFrame.minX, leftFrame.maxX)
        XCTAssertNil(PaneFocusFollowsMouseAppEnvironment.sessionView(atWindowPoint: point,
                                                                     in: fixture.window))
    }

    // With stolen key focus the app isn't active and the window isn't key, but typing goes to
    // its first responder, so moving to another pane must still change it.
    func testFocusingWithStolenKeyFocusChangesFirstResponderOfNonKeyWindow() {
        let right = fixture.split(session, vertically: true)
        guard let rightView = right.view, let responder = right.mainResponder else {
            it_fatalError("No view")
        }
        fixture.window.makeFirstResponder(session.mainResponder)
        // Earlier tests can leave the fixture's window key. A window that isn't on screen isn't.
        fixture.window.orderOut(nil)
        XCTAssertFalse(fixture.window.isKeyWindow)
        PaneFocusFollowsMouseAppEnvironment().focus(rightView, responder: responder, evenIfInactive: true)
        XCTAssertTrue(fixture.window.firstResponder === responder)
    }

    // Collapsing hides the note's text. If it had focus, focus goes back to the terminal instead
    // of being left with the window, where typing goes nowhere.
    func testCollapsingAFocusedNoteFocusesTheTerminal() {
        let model = SessionNoteModel()
        model.text = "note"
        sessionView.showSessionNote(with: model)
        XCTAssertFalse(fixture.window.firstResponder === session.mainResponder)
        sessionView.setSessionNoteCollapsed(true)
        XCTAssertTrue(fixture.window.firstResponder === session.mainResponder)
    }

    func testCenterOfPaneIsInThePane() {
        XCTAssertTrue(PaneFocusFollowsMouseAppEnvironment.sessionView(atWindowPoint: fixture.center(of: sessionView),
                                                                      in: fixture.window) === sessionView)
    }

    func testLabelDoesNotTakeFocus() {
        let panel = NSView(frame: NSRect(x: 10, y: 10, width: 200, height: 60))
        let label = NSTextField(labelWithString: "Label")
        label.frame = NSRect(x: 5, y: 5, width: 80, height: 20)
        panel.addSubview(label)
        sessionView.addSubview(belowFind: panel)
        XCTAssertNil(target(atCenterOf: label))
    }

    func testFindBarNamesItsSearchField() {
        // MinimalFindView isn't visible to Swift.
        let findViewClass = NSClassFromString("MinimalFindView") as! NSView.Type
        let findView = findViewClass.init(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        let label = NSTextField(labelWithString: "Label")
        let searchField = NSSearchField(frame: NSRect(x: 10, y: 5, width: 100, height: 20))
        findView.addSubview(label)
        findView.addSubview(searchField)
        XCTAssertTrue(findView.it_focusFollowsMouseResponder === searchField)
    }
}
