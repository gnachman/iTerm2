//
//  PSMTabDragSourceBarLockTests.swift
//  iTerm2XCTests
//
//  A tab drag stays locked to its source tab bar until the pointer moves well
//  away from the bar. While locked it can only reorder: leaving the bar is
//  deferred, and a release anywhere drops the tab back into the bar instead of
//  tearing it off into a new window.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabDragSourceBarLockTests: XCTestCase {
    private var window: NSWindow!
    private var tabView: NSTabView!
    private var control: PSMTabBarControl!
    private var dragDriver: FakeTabDragSessionDriver!
    private var savedDragDriver: PSMTabDragSessionDriver!

    // The bar spans y=376..400 in screen coordinates (the window's content sits at
    // the screen origin). Drags start from its vertical middle.
    private let startY: CGFloat = 388

    private var assistant: PSMTabDragAssistant {
        return PSMTabDragAssistant.shared()
    }

    override func setUp() {
        super.setUp()
        // Never arm a real NSDraggingSession; see FakeTabDragSessionDriver.
        savedDragDriver = assistant.dragSessionDriver
        dragDriver = FakeTabDragSessionDriver()
        assistant.dragSessionDriver = dragDriver
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                          styleMask: [.titled],
                          backing: .buffered,
                          defer: false)
        window.contentView?.wantsLayer = true
    }

    override func tearDown() {
        assistant.finishDrag()
        assistant.dragSessionDriver = savedDragDriver
        savedDragDriver = nil
        dragDriver = nil
        control = nil
        tabView = nil
        window = nil
        super.tearDown()
    }

    private func makeBar(tabCount: Int) {
        tabView = NSTabView(frame: NSRect(x: 0, y: 0, width: 600, height: 376))
        tabView.tabViewType = .noTabsNoBorder
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 376, width: 600, height: 24))
        // No delegate: the bar messages several "optional" delegate methods without
        // checking for them, and nothing here needs one. Without a delegate a drop
        // that isn't into the bar can only snap back, so a tab that lands in a new
        // slot proves the drop went into the bar.
        control.tabView = tabView
        tabView.delegate = control
        window.contentView?.addSubview(tabView)
        window.contentView?.addSubview(control)
        for i in 0..<tabCount {
            let item = NSTabViewItem(identifier: "tab \(i)" as NSString)
            item.label = "Tab \(i)"
            item.view = NSView()
            tabView.addTabViewItem(item)
        }
        control.updateWithoutAnimation()
    }

    private func startDraggingFirstTab() {
        let cell = control.cells().compactMap { $0 as? PSMTabBarCell }.first { !$0.isPlaceholder }!
        let pointInBar = NSPoint(x: cell.frame.midX, y: 12)
        let event = NSEvent.mouseEvent(with: .leftMouseDown,
                                       location: control.convert(pointInBar, to: nil),
                                       modifierFlags: [],
                                       timestamp: 0,
                                       windowNumber: window.windowNumber,
                                       context: nil,
                                       eventNumber: 0,
                                       clickCount: 1,
                                       pressure: 1)!
        assistant.startDragging(cell, fromTabBar: control, withMouseDownEvent: event)
        // AppKit's drag-began callback arms the threshold.
        let start = NSPoint(x: cell.frame.midX, y: startY)
        dragDriver.currentMouseLocation = start
        assistant.draggingBegan(at: start)
    }

    func testDragStaysLockedUntilPointerIsFarFromTheBar() {
        makeBar(tabCount: 3)
        startDraggingFirstTab()

        dragDriver.simulateMouseMove(to: NSPoint(x: 200, y: startY + 30))
        XCTAssertTrue(assistant.dragIsLockedToSourceTabBar,
                      "a 30pt vertical wobble is still a reorder")

        dragDriver.simulateMouseMove(to: NSPoint(x: 200, y: startY + 45))
        XCTAssertFalse(assistant.dragIsLockedToSourceTabBar)

        dragDriver.simulateMouseMove(to: NSPoint(x: 200, y: startY))
        XCTAssertFalse(assistant.dragIsLockedToSourceTabBar,
                       "once unlocked, coming back does not relock")
    }

    func testLeavingTheSourceBarWhileLockedIsDeferred() {
        makeBar(tabCount: 3)
        startDraggingFirstTab()

        dragDriver.simulateMouseMove(to: NSPoint(x: 200, y: startY - 30))
        control.draggingExited(nil)
        XCTAssertTrue(assistant.destinationTabBar() === control,
                      "the drop target left while the drag was still locked to the bar")

        dragDriver.simulateMouseMove(to: NSPoint(x: 200, y: startY - 45))
        XCTAssertNil(assistant.destinationTabBar(),
                     "the deferred exit was not replayed once the drag unlocked")
    }

    func testReleasingOffTheBarWhileLockedReordersInsteadOfTearingOff() {
        makeBar(tabCount: 3)
        let dragged = tabView.tabViewItem(at: 0)
        startDraggingFirstTab()

        // Drag toward the end of the bar, drifting below it.
        dragDriver.simulateMouseMove(to: NSPoint(x: 590, y: startY - 30))
        control.draggingExited(nil)
        dragDriver.simulateMouseMove(to: NSPoint(x: 595, y: startY - 30))
        assistant.calculateDragAnimation(forTabBar: control)

        // Nothing accepted the drop, so AppKit reports a failed drag.
        assistant.draggedImageEnded(at: NSPoint(x: 595, y: startY - 30), operation: [])

        XCTAssertFalse(assistant.isDragging())
        XCTAssertEqual(tabView.numberOfTabViewItems, 3)
        XCTAssertEqual(tabView.indexOfTabViewItem(dragged), 2,
                       "the tab should have been dropped into the slot it was tracking")
    }

    func testSingleTabDragIsNeverLocked() {
        makeBar(tabCount: 1)
        startDraggingFirstTab()

        dragDriver.simulateMouseMove(to: NSPoint(x: 200, y: startY + 5))
        XCTAssertFalse(assistant.dragIsLockedToSourceTabBar,
                       "a lone tab has nothing to reorder, so it must be free to leave")
    }
}
