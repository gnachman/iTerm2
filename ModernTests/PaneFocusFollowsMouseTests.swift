//
//  PaneFocusFollowsMouseTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
private final class FakePane: NSObject, PaneFocusFollowsMousePane {
    let name: String
    let terminal = NSView()
    var views = [NSView]()

    init(_ name: String) {
        self.name = name
    }

    var focusFollowsMouseMainResponder: NSView? { terminal }

    override var description: String { name }
}

@MainActor
private final class FakeEnvironment: PaneFocusFollowsMouseEnvironment {
    struct Focus: Equatable {
        var pane: String
        var responder: NSResponder
        var evenIfInactive: Bool

        static func == (lhs: Focus, rhs: Focus) -> Bool {
            return lhs.pane == rhs.pane && lhs.responder === rhs.responder && lhs.evenIfInactive == rhs.evenIfInactive
        }
    }

    var isEnabled = true
    var includesSubviews = true
    var mouseButtonIsDown = false
    var currentEventIsMouseUp = false
    var stealKeyFocusEnabled = false
    var appIsActive = true
    var pointerLocation = NSPoint(x: 0, y: 0)
    var panes = [FakePane]()
    // Pane under each point, by x coordinate. Points not listed are over no pane.
    var paneAtX = [CGFloat: FakePane]()
    // The view that would take focus at each point. Points in a pane but not listed are over
    // something that can't take focus, like a title bar.
    var targetAtX = [CGFloat: NSView]()
    var focused: FakePane?
    var firstResponder: NSResponder?
    var unfocusable = Set<String>()
    var focuses = [Focus]()
    var steals = 0
    var releases = 0
    var pendingRebaselines = [() -> Void]()

    func pane(at screenPoint: NSPoint) -> PaneFocusFollowsMousePane? {
        return paneAtX[screenPoint.x]
    }

    func pane(containing view: NSView) -> PaneFocusFollowsMousePane? {
        return panes.first { pane in
            view === pane.terminal || pane.views.contains { view === $0 || view.isDescendant(of: $0) }
        }
    }

    var focusedPane: PaneFocusFollowsMousePane? { focused }

    func focusTarget(at screenPoint: NSPoint, in pane: PaneFocusFollowsMousePane) -> NSView? {
        return targetAtX[screenPoint.x]
    }

    func canFocus(_ pane: PaneFocusFollowsMousePane) -> Bool {
        return !unfocusable.contains((pane as! FakePane).name)
    }

    func focus(_ pane: PaneFocusFollowsMousePane, responder: NSResponder, evenIfInactive: Bool) {
        let fake = pane as! FakePane
        focuses.append(Focus(pane: fake.name, responder: responder, evenIfInactive: evenIfInactive))
        focused = fake
        firstResponder = responder
    }

    func stealKeyFocus() {
        steals += 1
    }

    func releaseKeyFocus() {
        releases += 1
    }

    func stolenKeyFocusDidChange(for pane: PaneFocusFollowsMousePane) {
    }

    func scheduleRebaseline(_ block: @escaping () -> Void) {
        pendingRebaselines.append(block)
    }

    func runPendingRebaselines() {
        let blocks = pendingRebaselines
        pendingRebaselines = []
        blocks.forEach { $0() }
    }
}

@MainActor
final class PaneFocusFollowsMouseTests: XCTestCase {
    private var env: FakeEnvironment!
    private var ffm: PaneFocusFollowsMouse!
    private var a: FakePane!
    private var b: FakePane!
    private var note: NSView!
    private var noteField: NSView!

    // Layout along the x axis:
    //   1, 1.5 = pane A's terminal
    //   2, 2.5 = A's note, whose text view takes focus
    //   4      = A's title bar, which can't take focus
    //   3      = pane B's terminal
    //   0      = no pane
    override func setUp() {
        super.setUp()
        env = FakeEnvironment()
        a = FakePane("A")
        b = FakePane("B")
        note = NSView()
        noteField = NSView()
        note.addSubview(noteField)
        a.views = [note]
        env.panes = [a, b]
        env.paneAtX = [1: a, 1.5: a, 2: a, 2.5: a, 4: a, 3: b]
        env.targetAtX = [1: a.terminal, 1.5: a.terminal, 2: noteField, 2.5: noteField, 3: b.terminal]
        ffm = PaneFocusFollowsMouse(environment: env)
    }

    private func move(to x: CGFloat) {
        env.pointerLocation = NSPoint(x: x, y: 0)
        ffm.pointerMoved()
    }

    // Focus changes made by something other than focus follows mouse (a click, the keyboard,
    // a menu item).
    private func externallyFocus(_ responder: NSView, in pane: FakePane) {
        env.focused = pane
        env.firstResponder = responder
        ffm.firstResponderDidChange(to: responder)
    }

    private func focus(_ pane: FakePane, _ responder: NSResponder, evenIfInactive: Bool = false) -> FakeEnvironment.Focus {
        return FakeEnvironment.Focus(pane: pane.name, responder: responder, evenIfInactive: evenIfInactive)
    }

    // MARK: - Whatever the pointer is over

    func testEnteringAPaneFocusesWhatIsUnderThePointer() {
        move(to: 1)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal)])
    }

    func testEnteringAPaneOverAPanelFocusesThePanel() {
        move(to: 2)
        XCTAssertEqual(env.focuses, [focus(a, noteField)])
    }

    func testMovingOntoAPanelFocusesIt() {
        move(to: 1)
        move(to: 2)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal), focus(a, noteField)])
    }

    func testMovingFromAPanelOntoTheTerminalFocusesTheTerminal() {
        move(to: 1)
        move(to: 2)
        move(to: 1)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal), focus(a, noteField), focus(a, a.terminal)])
    }

    func testMovingWithinOneTargetDoesNothing() {
        move(to: 1)
        move(to: 1.5)
        move(to: 2)
        move(to: 2.5)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal), focus(a, noteField)])
    }

    func testMovingToAnotherPaneFocusesIt() {
        move(to: 1)
        move(to: 3)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal), focus(b, b.terminal)])
    }

    func testDisabledDoesNothing() {
        env.isEnabled = false
        move(to: 1)
        move(to: 3)
        XCTAssertEqual(env.focuses, [])
    }

    func testUnfocusablePaneIsSkipped() {
        env.unfocusable = ["B"]
        move(to: 1)
        move(to: 3)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal)])
    }

    func testFieldEditorCountsAsTheTextFieldItEdits() {
        let field = NSTextField()
        note.addSubview(field)
        let fieldEditor = NSTextView()
        fieldEditor.isFieldEditor = true
        // AppKit puts the field editor inside the control it edits.
        field.addSubview(fieldEditor)
        env.targetAtX[2] = field
        move(to: 1)
        externallyFocus(fieldEditor, in: a)
        move(to: 2)
        // The field is already being edited, so focusing it again would select all of its text.
        XCTAssertEqual(env.focuses, [focus(a, a.terminal)])
    }

    // MARK: - Drags

    func testDraggingIntoAnotherPaneDoesNotFocusIt() {
        move(to: 1)
        env.mouseButtonIsDown = true
        move(to: 3)
        move(to: 2)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal)])
    }

    func testAfterADragEndsInAnotherPaneTheNextMoveFocusesIt() {
        move(to: 1)
        env.mouseButtonIsDown = true
        move(to: 3)
        env.mouseButtonIsDown = false
        move(to: 3)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal), focus(b, b.terminal)])
    }

    // The view where a drag started can take first responder again as the button is released,
    // with the pointer over another pane.
    func testFocusChangeOnReleaseOverAnotherPaneDoesNotCountAsEnteringIt() {
        env.includesSubviews = false
        move(to: 1)
        env.mouseButtonIsDown = true
        env.pointerLocation = NSPoint(x: 3, y: 0)
        env.mouseButtonIsDown = false
        env.currentEventIsMouseUp = true
        externallyFocus(a.terminal, in: a)
        env.currentEventIsMouseUp = false
        move(to: 3)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal), focus(b, b.terminal)])
    }

    func testClickReleasedInPlaceDoesNotRefocus() {
        move(to: 1)
        env.currentEventIsMouseUp = true
        externallyFocus(a.terminal, in: a)
        env.currentEventIsMouseUp = false
        move(to: 1.5)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal)])
    }

    // MARK: - Without subviews (pane-level only)

    func testWithoutSubviewsMovingOntoAPanelDoesNothing() {
        env.includesSubviews = false
        move(to: 1)
        move(to: 2)
        move(to: 1)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal)])
        XCTAssertFalse(ffm.wantsPointerMovement(for: a))
    }

    func testWithoutSubviewsEnteringAPaneRestoresItsLastFocusedView() {
        env.includesSubviews = false
        move(to: 3)
        externallyFocus(noteField, in: a)
        externallyFocus(b.terminal, in: b)
        move(to: 1)
        XCTAssertEqual(env.focuses, [focus(b, b.terminal), focus(a, noteField)])
    }

    func testWithoutSubviewsEnteringAPaneThatNeverHadFocusFocusesItsTerminal() {
        env.includesSubviews = false
        move(to: 3)
        move(to: 2)
        XCTAssertEqual(env.focuses, [focus(b, b.terminal), focus(a, a.terminal)])
    }

    // MARK: - Things that can't take focus

    func testMovingOverSomethingThatCantTakeFocusDoesNothing() {
        move(to: 2)
        move(to: 4)
        XCTAssertEqual(env.focuses, [focus(a, noteField)])
    }

    func testEnteringAPaneOverSomethingThatCantTakeFocusRestoresItsLastFocusedView() {
        move(to: 2)
        move(to: 3)
        move(to: 4)
        XCTAssertEqual(env.focuses, [focus(a, noteField), focus(b, b.terminal), focus(a, noteField)])
    }

    func testEnteringAPaneThatNeverHadFocusOverSomethingThatCantTakeFocusFocusesItsTerminal() {
        move(to: 3)
        move(to: 4)
        XCTAssertEqual(env.focuses, [focus(b, b.terminal), focus(a, a.terminal)])
    }

    func testRemovedPanelIsNotRestored() {
        move(to: 2)
        move(to: 3)
        a.views = []
        move(to: 4)
        XCTAssertEqual(env.focuses.last, focus(a, a.terminal))
    }

    func testLeavingTheFocusedPaneForANonPaneAreaAndReturningToTheSameTargetDoesNothing() {
        move(to: 1)
        move(to: 0)
        move(to: 1)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal)])
    }

    func testLeavingAnUnfocusedPaneForANonPaneAreaAndReturningFocusesIt() {
        move(to: 1)
        // The keyboard moves focus to B while the pointer stays in A.
        externallyFocus(b.terminal, in: b)
        move(to: 0)
        move(to: 1)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal), focus(a, a.terminal)])
    }

    // MARK: - Focus changes made elsewhere

    func testExternalFocusChangeIsNotUndoneWhileThePointerStaysOnTheSameTarget() {
        move(to: 1)
        externallyFocus(b.terminal, in: b)
        move(to: 1.5)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal)])
    }

    func testPanelOpenedByShortcutKeepsFocusUntilThePointerCrossesOntoSomethingElse() {
        move(to: 1)
        externallyFocus(noteField, in: a)
        move(to: 1.5)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal)])
        move(to: 4)
        move(to: 1)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal), focus(a, a.terminal)])
    }

    func testPanelOpenedUnderARestingPointerKeepsFocus() {
        move(to: 1)
        // The panel appears where the pointer already is.
        env.pointerLocation = NSPoint(x: 2, y: 0)
        externallyFocus(noteField, in: a)
        move(to: 2.5)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal)])
    }

    func testExternalFocusChangeIsReplacedWhenThePointerCrossesIntoAnotherPane() {
        move(to: 1)
        externallyFocus(b.terminal, in: b)
        move(to: 3)
        move(to: 1)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal), focus(a, a.terminal)])
    }

    func testPanelOpenedInAnotherPaneIsRestoredWhenEnteringOverSomethingThatCantTakeFocus() {
        move(to: 3)
        // The note opens in A by a menu item while the pointer is in B, and B's terminal is
        // focused again before the pointer reaches A.
        externallyFocus(noteField, in: a)
        externallyFocus(b.terminal, in: b)
        move(to: 4)
        XCTAssertEqual(env.focuses, [focus(b, b.terminal), focus(a, noteField)])
    }

    // MARK: - A still pointer

    func testLayoutChangeUnderAStillPointerDoesNotFocus() {
        move(to: 1)
        // A new split appears under the pointer, which hasn't moved.
        ffm.freeze()
        env.paneAtX[1] = b
        env.targetAtX[1] = b.terminal
        ffm.pointerMoved()
        XCTAssertEqual(env.focuses, [focus(a, a.terminal)])
    }

    func testAfterALayoutChangeMovingWithinTheNewPaneUnderThePointerDoesNotFocusIt() {
        move(to: 1)
        ffm.freeze()
        env.paneAtX[1] = b
        env.paneAtX[1.5] = b
        env.targetAtX[1] = b.terminal
        env.targetAtX[1.5] = b.terminal
        env.runPendingRebaselines()
        move(to: 1.5)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal)])
    }

    func testAfterALayoutChangeMovingIntoAnotherPaneFocuses() {
        move(to: 1)
        ffm.freeze()
        env.paneAtX[1] = b
        env.targetAtX[1] = b.terminal
        env.runPendingRebaselines()
        env.firstResponder = b.terminal
        move(to: 2)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal), focus(a, noteField)])
    }

    func testReturningToTheAppWithoutMovingDoesNotSwitchPanes() {
        move(to: 1)
        externallyFocus(b.terminal, in: b)
        env.appIsActive = false
        move(to: 3)
        env.appIsActive = true
        env.pointerLocation = NSPoint(x: 1, y: 0)
        ffm.appDidBecomeActive()
        ffm.pointerMoved()
        XCTAssertEqual(env.focuses, [focus(a, a.terminal)])
    }

    func testWhileInactiveWithoutStealingNothingHappens() {
        env.appIsActive = false
        move(to: 1)
        move(to: 3)
        XCTAssertEqual(env.focuses, [])
        XCTAssertEqual(env.steals, 0)
    }

    // MARK: - Stealing key focus

    func testStealingWhileInactiveFocusesThePane() {
        env.stealKeyFocusEnabled = true
        env.appIsActive = false
        move(to: 1)
        XCTAssertEqual(env.steals, 1)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal, evenIfInactive: true)])
        XCTAssertTrue(ffm.hasStolenKeyFocus(for: a))
    }

    func testStolenFocusIsKeptAcrossPanes() {
        env.stealKeyFocusEnabled = true
        env.appIsActive = false
        move(to: 1)
        move(to: 3)
        XCTAssertEqual(env.steals, 1)
        XCTAssertEqual(env.releases, 0)
        XCTAssertEqual(env.focuses, [focus(a, a.terminal, evenIfInactive: true),
                                     focus(b, b.terminal, evenIfInactive: true)])
        XCTAssertFalse(ffm.hasStolenKeyFocus(for: a))
        XCTAssertTrue(ffm.hasStolenKeyFocus(for: b))
    }

    func testStolenFocusIsReleasedOverNoPane() {
        env.stealKeyFocusEnabled = true
        env.appIsActive = false
        move(to: 1)
        move(to: 0)
        XCTAssertEqual(env.releases, 1)
        XCTAssertFalse(ffm.hasStolenKeyFocus(for: a))
    }

    func testReenteringTheSamePaneStealsAgain() {
        env.stealKeyFocusEnabled = true
        env.appIsActive = false
        move(to: 1)
        move(to: 0)
        // While inactive there is no key window, so nothing is first responder.
        env.firstResponder = nil
        move(to: 1)
        XCTAssertEqual(env.steals, 2)
        XCTAssertEqual(env.focuses.count, 2)
    }

    func testStolenFocusIsReleasedWhenDisabled() {
        env.stealKeyFocusEnabled = true
        env.appIsActive = false
        move(to: 1)
        env.isEnabled = false
        move(to: 3)
        XCTAssertEqual(env.releases, 1)
    }

    // MARK: - Aggressive activation

    func testFocusPaneUnderPointerFocusesEvenTheLastPane() {
        move(to: 1)
        externallyFocus(b.terminal, in: b)
        ffm.focusPaneUnderPointer()
        XCTAssertEqual(env.focuses, [focus(a, a.terminal), focus(a, a.terminal, evenIfInactive: true)])
    }

    // Switching Spaces can announce the new Space before the app becomes active.
    func testFocusPaneUnderPointerWorksWhileInactive() {
        move(to: 1)
        externallyFocus(b.terminal, in: b)
        env.appIsActive = false
        ffm.focusPaneUnderPointer()
        XCTAssertEqual(env.focuses.last, focus(a, a.terminal, evenIfInactive: true))
    }
}
