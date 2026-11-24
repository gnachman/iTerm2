//
//  PSMTabDragRefusedDropTests.swift
//  ModernTests
//
//  A tab bar can refuse drops while still letting its tabs be dragged out, as
//  during a tab bar search. A tab released over a bar that refuses it snaps
//  back rather than reordering or tearing off into a new window.
//

import XCTest
@testable import iTerm2SharedARC

private final class RefusingDropDelegate: NSObject, PSMTabBarControlDelegate {
    weak var refusingBar: PSMTabBarControl?
    var newWindowRequests = 0

    func tabView(_ tabView: NSTabView, updateStateFor tabViewItem: NSTabViewItem) {}

    func tabView(_ aTabView: NSTabView,
                 shouldDrop tabViewItem: NSTabViewItem,
                 inTabBar tabBarControl: PSMTabBarControl?,
                 moveSourceWindow: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        return tabBarControl == nil || tabBarControl !== refusingBar
    }

    func tabView(_ aTabView: NSTabView,
                 newTabBarForDraggedTabViewItem tabViewItem: NSTabViewItem,
                 at point: NSPoint) -> PSMTabBarControl? {
        newWindowRequests += 1
        return nil
    }

    func tabViewDragShouldExitWindow(_ tabView: NSTabView) -> Bool {
        return true
    }

    // The bar calls these without checking that they're implemented.
    func tabViewShouldAllowDrag(onAddTabButton tabView: NSTabView) -> Bool { false }
    func tabView(_ tabView: PSMTabBarControl, valueOfOption option: PSMTabBarControlOptionKey) -> Any? { nil }
    func tabViewDesiredTabBarHeight(_ tabView: NSTabView?) -> CGFloat { 24 }
    func tabViewShowsRichTabContent(_ tabView: NSTabView) -> Bool { false }
    func tabColor(for tabViewItem: NSTabViewItem) -> NSColor? { nil }
    func tabView(_ tabView: NSTabView, willRemove tabViewItem: NSTabViewItem) {}
    func tabView(_ tabView: NSTabView, willAdd tabViewItem: NSTabViewItem) {}
    func tabView(_ tabView: NSTabView, willInsert tabViewItem: NSTabViewItem, at index: Int32) {}
    func tabViewShouldDragWindow(_ tabView: NSTabView, event: NSEvent) -> Bool { false }
}

final class PSMTabDragRefusedDropTests: XCTestCase {
    private var window: NSWindow!
    private var tabView: NSTabView!
    private var control: PSMTabBarControl!
    private var delegate: RefusingDropDelegate!
    private var dragDriver: FakeTabDragSessionDriver!
    private var savedDragDriver: PSMTabDragSessionDriver!

    // The bar spans y=376..400 in screen coordinates.
    private let startY: CGFloat = 388

    private var assistant: PSMTabDragAssistant {
        return PSMTabDragAssistant.shared()
    }

    override func setUp() {
        super.setUp()
        savedDragDriver = assistant.dragSessionDriver
        dragDriver = FakeTabDragSessionDriver()
        assistant.dragSessionDriver = dragDriver
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                          styleMask: [.titled],
                          backing: .buffered,
                          defer: false)
        window.contentView?.wantsLayer = true
        tabView = NSTabView(frame: NSRect(x: 0, y: 0, width: 600, height: 376))
        tabView.tabViewType = .noTabsNoBorder
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 376, width: 600, height: 24))
        control.tabView = tabView
        tabView.delegate = control
        delegate = RefusingDropDelegate()
        delegate.refusingBar = control
        control.delegate = delegate
        window.contentView?.addSubview(tabView)
        window.contentView?.addSubview(control)
        for i in 0..<3 {
            let item = NSTabViewItem(identifier: "tab \(i)" as NSString)
            item.label = "Tab \(i)"
            item.view = NSView()
            tabView.addTabViewItem(item)
        }
        control.updateWithoutAnimation()
    }

    override func tearDown() {
        assistant.finishDrag()
        window.orderOut(nil)
        assistant.dragSessionDriver = savedDragDriver
        savedDragDriver = nil
        dragDriver = nil
        control = nil
        delegate = nil
        tabView = nil
        window = nil
        super.tearDown()
    }

    private func startDraggingFirstTab() {
        startDraggingTab(at: 0)
    }

    private func startDraggingTab(at index: Int) {
        let cell = control.cells().compactMap { $0 as? PSMTabBarCell }.filter { !$0.isPlaceholder }[index]
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
        let start = NSPoint(x: cell.frame.midX, y: startY)
        dragDriver.currentMouseLocation = start
        assistant.draggingBegan(at: start)
    }

    private func tabDragInfo() -> NSDraggingInfo {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PSMTabDragRefusedDropTests"))
        pasteboard.clearContents()
        pasteboard.declareTypes([NSPasteboard.PasteboardType("com.iterm2.psm.controlitem")], owner: nil)
        // Every drag here starts in control, which is a tab drag's source.
        return TabDragInfoStub(pasteboard: pasteboard, source: control)
    }

    private func assertSnappedBack(_ dragged: NSTabViewItem, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(assistant.isDragging(), file: file, line: line)
        XCTAssertEqual(tabView.numberOfTabViewItems, 3, "not torn off", file: file, line: line)
        XCTAssertEqual(tabView.indexOfTabViewItem(dragged), 0, "not reordered", file: file, line: line)
        XCTAssertEqual(delegate.newWindowRequests, 0, file: file, line: line)
    }

    // Released inside the bar it came from, which refuses it.
    func testReleasingInARefusingSourceBarSnapsBack() {
        let dragged = tabView.tabViewItem(at: 0)
        startDraggingFirstTab()
        XCTAssertEqual(control.draggingEntered(tabDragInfo()), [])
        dragDriver.simulateMouseMove(to: NSPoint(x: 590, y: startY))
        XCTAssertEqual(control.draggingUpdated(tabDragInfo()), [])
        assistant.calculateDragAnimation(forTabBar: control)
        assistant.draggedImageEnded(at: NSPoint(x: 590, y: startY), operation: [])
        assertSnappedBack(dragged)
    }

    // A bar that refuses the tab doesn't open a gap for it, so it doesn't
    // look like a reorder is coming.
    func testARefusingSourceBarOpensNoGap() {
        startDraggingFirstTab()
        XCTAssertTrue(assistant.destinationTabBar() === control, "precondition")
        XCTAssertEqual(control.draggingUpdated(tabDragInfo()), [])
        XCTAssertNil(assistant.destinationTabBar())
    }

    // Released just off the bar while the drag is still locked to it, which
    // would normally reorder into the slot it was tracking.
    func testReleasingNearARefusingSourceBarSnapsBack() {
        let dragged = tabView.tabViewItem(at: 0)
        startDraggingFirstTab()
        dragDriver.simulateMouseMove(to: NSPoint(x: 590, y: startY - 30))
        control.draggingExited(nil)
        dragDriver.simulateMouseMove(to: NSPoint(x: 595, y: startY - 30))
        assistant.calculateDragAnimation(forTabBar: control)
        assistant.draggedImageEnded(at: NSPoint(x: 595, y: startY - 30), operation: [])
        assertSnappedBack(dragged)
    }

    // Dragged far away and back over the bar, which refuses it.
    func testComingBackOverARefusingBarSnapsBack() {
        let dragged = tabView.tabViewItem(at: 0)
        startDraggingFirstTab()
        dragDriver.simulateMouseMove(to: NSPoint(x: 200, y: startY - 100))
        control.draggingExited(nil)
        XCTAssertNil(assistant.destinationTabBar())
        dragDriver.simulateMouseMove(to: NSPoint(x: 200, y: startY))
        XCTAssertEqual(control.draggingEntered(tabDragInfo()), [])
        assistant.draggedImageEnded(at: NSPoint(x: 200, y: startY), operation: [])
        assertSnappedBack(dragged)
    }

    // Released far from any bar, it tears off as usual. This delegate makes
    // no new window, so the tab stays where it was.
    func testReleasingAwayFromTheBarTearsOff() {
        let dragged = tabView.tabViewItem(at: 0)
        startDraggingFirstTab()
        dragDriver.simulateMouseMove(to: NSPoint(x: 200, y: startY - 100))
        control.draggingExited(nil)
        assistant.draggedImageEnded(at: NSPoint(x: 200, y: startY - 100), operation: [])
        XCTAssertEqual(delegate.newWindowRequests, 1)
        XCTAssertEqual(tabView.numberOfTabViewItems, 3, "no window to move it to, so it isn't lost")
        XCTAssertEqual(tabView.indexOfTabViewItem(dragged), 0)
        assertCellsMatchTabs()
    }

    private func assertCellsMatchTabs(file: StaticString = #filePath, line: UInt = #line) {
        let cellItems = control.cells().compactMap { $0 as? PSMTabBarCell }
            .filter { !$0.isPlaceholder }
            .compactMap { $0.representedObject as? NSTabViewItem }
        XCTAssertEqual(cellItems.map { $0.label }, tabView.tabViewItems.map { $0.label },
                       "the bar's cells are in the tabs' order", file: file, line: line)
    }

    // A tab other than the first goes back to its own place among the cells.
    func testSnappingBackAMiddleTabKeepsTheCellsInOrder() {
        let dragged = tabView.tabViewItem(at: 1)
        startDraggingTab(at: 1)
        XCTAssertEqual(control.draggingEntered(tabDragInfo()), [])
        dragDriver.simulateMouseMove(to: NSPoint(x: 590, y: startY))
        assistant.calculateDragAnimation(forTabBar: control)
        assistant.draggedImageEnded(at: NSPoint(x: 590, y: startY), operation: [])
        XCTAssertEqual(tabView.indexOfTabViewItem(dragged), 1)
        assertCellsMatchTabs()
    }

    // While a drag is still locked to its own bar, another bar that would
    // refuse it isn't entered yet, so it can't turn a reorder into a snap back.
    func testARefusingBarDoesNotCancelALockedReorder() {
        let otherTabView = NSTabView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let other = PSMTabBarControl(frame: NSRect(x: 0, y: 300, width: 600, height: 24))
        other.tabView = otherTabView
        otherTabView.delegate = other
        other.delegate = delegate
        let item = NSTabViewItem(identifier: "other" as NSString)
        item.label = "Other"
        item.view = NSView()
        otherTabView.addTabViewItem(item)
        // The source bar takes drops; the other one refuses them.
        delegate.refusingBar = other

        let dragged = tabView.tabViewItem(at: 0)
        startDraggingFirstTab()
        dragDriver.simulateMouseMove(to: NSPoint(x: 590, y: startY - 30))
        control.draggingExited(nil)
        XCTAssertTrue(assistant.dragIsLockedToSourceTabBar)
        XCTAssertEqual(other.draggingEntered(tabDragInfo()), [])
        XCTAssertEqual(other.draggingUpdated(tabDragInfo()), [])
        dragDriver.simulateMouseMove(to: NSPoint(x: 595, y: startY - 30))
        assistant.calculateDragAnimation(forTabBar: control)
        assistant.draggedImageEnded(at: NSPoint(x: 595, y: startY - 30), operation: [])
        XCTAssertEqual(tabView.indexOfTabViewItem(dragged), 2, "reordered in its own bar")
    }

    // A refusal from one drag doesn't carry over to the next.
    func testARefusalEndsWithItsDrag() {
        startDraggingFirstTab()
        XCTAssertEqual(control.draggingEntered(tabDragInfo()), [])
        assistant.draggedImageEnded(at: NSPoint(x: 200, y: startY), operation: [])
        // A refusal left over from before the next drag starts.
        assistant.setRefusingTabBar(control)
        startDraggingFirstTab()
        dragDriver.simulateMouseMove(to: NSPoint(x: 200, y: startY - 100))
        // Leave the bar without the bar clearing its own refusal.
        assistant.draggingExitedTabBar(control)
        assistant.draggedImageEnded(at: NSPoint(x: 200, y: startY - 100), operation: [])
        XCTAssertEqual(delegate.newWindowRequests, 1, "tore off rather than snapping back")
    }

    // Right by its own bar, where a release snaps back too, the cursor says
    // so as well.
    func testRightByARefusingSourceBarShowsTheNotAllowedCursor() {
        startDraggingFirstTab()
        dragDriver.simulateMouseMove(to: NSPoint(x: 590, y: startY - 30))
        control.draggingExited(nil)
        dragDriver.simulateMouseMove(to: NSPoint(x: 595, y: startY - 30))
        XCTAssertEqual(NSCursor.current, NSCursor.operationNotAllowed)
        assistant.draggedImageEnded(at: NSPoint(x: 595, y: startY - 30), operation: [])
    }

    // A window's only tab has nowhere to go in its own bar, which declines
    // it, but that isn't a refusal: dragging it moves the window, so the
    // cursor doesn't say not-allowed.
    func testALoneTabIsNotRefused() {
        tabView.removeTabViewItem(tabView.tabViewItem(at: 2))
        tabView.removeTabViewItem(tabView.tabViewItem(at: 1))
        control.updateWithoutAnimation()
        startDraggingFirstTab()
        XCTAssertEqual(control.draggingUpdated(tabDragInfo()), [])
        XCTAssertNotEqual(NSCursor.current, NSCursor.operationNotAllowed)
        XCTAssertFalse(assistant.sourceTabBarRefusesDrop())
        assistant.draggedImageEnded(at: NSPoint(x: 200, y: startY), operation: [])
        XCTAssertEqual(delegate.newWindowRequests, 1, "tore off rather than snapping back")
    }

    // If the bar stops refusing mid-drag, as when a search ends, a release
    // right by it still finishes the drag.
    func testReleasingByABarThatStoppedRefusingFinishesTheDrag() {
        startDraggingFirstTab()
        XCTAssertEqual(control.draggingUpdated(tabDragInfo()), [])
        dragDriver.simulateMouseMove(to: NSPoint(x: 590, y: startY - 30))
        control.draggingExited(nil)
        delegate.refusingBar = nil
        dragDriver.simulateMouseMove(to: NSPoint(x: 595, y: startY - 30))
        assistant.calculateDragAnimation(forTabBar: control)
        XCTAssertEqual(NSCursor.current, NSCursor.operationNotAllowed, "a release here snaps back")
        let dragged = tabView.tabViewItem(at: 0)
        assistant.draggedImageEnded(at: NSPoint(x: 595, y: startY - 30), operation: [])
        assertSnappedBack(dragged)
    }

    // Over a bar that refuses the tab, the cursor says so, and goes back to
    // the closed hand when the drag leaves it.
    func testARefusingBarShowsTheNotAllowedCursor() {
        startDraggingFirstTab()
        XCTAssertEqual(control.draggingUpdated(tabDragInfo()), [])
        XCTAssertEqual(NSCursor.current, NSCursor.operationNotAllowed)
        dragDriver.simulateMouseMove(to: NSPoint(x: 200, y: startY - 200))
        control.draggingExited(tabDragInfo())
        dragDriver.simulateMouseMove(to: NSPoint(x: 205, y: startY - 200))
        XCTAssertEqual(NSCursor.current, NSCursor.closedHand)
        XCTAssertEqual(control.draggingUpdated(tabDragInfo()), [])
        assistant.draggedImageEnded(at: NSPoint(x: 200, y: startY), operation: [])
        XCTAssertNotEqual(NSCursor.current, NSCursor.operationNotAllowed, "not left behind")
    }
}

// Only the pasteboard matters to the tab bar's handling of a tab drag, and
// the source bar, whose tab view the bar passes to its delegate.
private final class TabDragInfoStub: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    private weak var source: PSMTabBarControl?

    init(pasteboard: NSPasteboard, source: PSMTabBarControl) {
        draggingPasteboard = pasteboard
        self.source = source
    }

    var draggingLocation: NSPoint { .zero }
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { source }
    var draggingSequenceNumber: Int { 0 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [],
                                for view: NSView?,
                                classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}
