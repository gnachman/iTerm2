//
//  PSMTabGroupDragTests.swift
//  iTerm2XCTests
//
//  Live drag-start tests for the group-block drag path. Unlike
//  PSMTabGroupCellTests (which exercises pure cell-list helpers), these drive
//  the real -[PSMTabDragAssistant startDraggingGroupWithChip:members:...]
//  entry point end to end, so they catch crashes in the setup + snapshot +
//  placeholder-distribution path that the helper tests cannot reach. Run under
//  the ModernTests ASan build to surface memory corruption precisely.
//

import XCTest
@testable import iTerm2SharedARC

// A chip cell that records whether its -frame was ever read while it was no
// longer in the control's cell list. The field crash was exactly that: the
// base -distributePlaceholdersInTabBar: strips chips (freeing a chip the MRR
// drag code holds unretained), and the group variant then read [chip frame].
// By holding a strong ref to this subclass the test avoids the use-after-free
// itself and instead asserts the ordering the fix guarantees, deterministically
// (no reliance on freed-memory state, so it is not flaky).
private final class ObservingChipCell: PSMTabBarCell {
    weak var observedControl: PSMTabBarControl?
    var frameReadAfterStrip = false
    override var frame: NSRect {
        get {
            if let control = observedControl, !control.cells().contains(self) {
                frameReadAfterStrip = true
            }
            return super.frame
        }
        set { super.frame = newValue }
    }
}

final class PSMTabGroupDragTests: XCTestCase {
    private var window: NSWindow!
    private var control: PSMTabBarControl!

    override func setUp() {
        super.setUp()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                          styleMask: [.titled],
                          backing: .buffered,
                          defer: false)
        // Mirror the real tab bar: iTerm2 windows are layer-backed, which routes
        // -cacheDisplayInRect: (the group drag-image snapshot) down a different
        // path than a plain view.
        window.contentView?.wantsLayer = true
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 376, width: 600, height: 24))
        window.contentView?.addSubview(control)
    }

    override func tearDown() {
        // Make sure a failed/aborted drag doesn't leak assistant state into the
        // next test.
        PSMTabDragAssistant.shared().finishDrag()
        control = nil
        window = nil
        super.tearDown()
    }

    // Keep strong refs to the bound tab view items for the test's lifetime.
    private var items: [NSTabViewItem] = []

    // Build a bar whose member cells carry the two live-cell traits the drag
    // snapshot touches: the KVO "title <- label" binding and an indicator
    // subview parented to the control. Cells are hand-built (there is no public
    // -addTabViewItem:) and framed by hand since there's no live layout pass.
    private func makeGroupedBar() -> (chip: PSMTabBarCell, members: [PSMTabBarCell]) {
        let cells = NSMutableArray()
        var x: CGFloat = 0
        func makeTab(_ groupID: String?, _ label: String) -> PSMTabBarCell {
            let cell = PSMTabBarCell(controlView: control)!
            cell.tabGroupIdentifier = groupID
            let item = NSTabViewItem(identifier: label as NSString)
            item.label = label
            items.append(item)
            cell.representedObject = item
            cell.bind(NSBindingName("title"), to: item, withKeyPath: "label", options: nil)
            control.addSubview(cell.indicator)  // live cells park their indicator here
            cell.frame = NSRect(x: x, y: 0, width: 120, height: 24)
            x += 120
            cells.add(cell)
            return cell
        }

        let chip = ObservingChipCell(controlView: control)!
        chip.observedControl = control
        chip.isTabGroupChip = true
        chip.tabGroupIdentifier = "A"
        chip.frame = NSRect(x: x, y: 0, width: 40, height: 24)
        x += 40
        cells.insert(chip, at: 0)

        let m0 = makeTab("A", "Member 0")
        let m1 = makeTab("A", "Member 1")
        _ = makeTab(nil, "Loner")

        control.cells().setArray(cells as [AnyObject])
        return (chip, [m0, m1])
    }

    private func mouseDownEvent(at point: NSPoint) -> NSEvent {
        let inWindow = control.convert(point, to: nil)
        return NSEvent.mouseEvent(with: .leftMouseDown,
                                  location: inWindow,
                                  modifierFlags: [],
                                  timestamp: 0,
                                  windowNumber: window.windowNumber,
                                  context: nil,
                                  eventNumber: 0,
                                  clickCount: 1,
                                  pressure: 1)!
    }

    // Drives the full group-drag start (snapshot + placeholder distribution).
    //
    // NOTE ON COVERAGE: the field crash here was a use-after-free -- the base
    // -distributePlaceholdersInTabBar: strips chip cells from the control, which
    // (PSMTabBarCell being ARC) deallocated the `chip` argument because the MRR
    // drag callers hold it unretained; the group variant then read [chip frame].
    // This ARC (Swift) test cannot reproduce that specific UAF: passing `chip` as
    // an argument retains it for the call's duration, masking the dangling ref.
    // It still guards the path against crashes and, via the width assertion below,
    // locks in that the group placeholder spans the whole run -- which only holds
    // if runFrame is computed from a live chip frame.
    func testStartDraggingGroupSpansTheWholeRun() {
        let (chip, members) = makeGroupedBar()
        let event = mouseDownEvent(at: NSPoint(x: 20, y: 12))  // over the chip
        PSMTabDragAssistant.shared().startDraggingGroup(withChip: chip,
                                                        members: members,
                                                        fromTabBar: control,
                                                        withMouseDownEvent: event)
        XCTAssertTrue(PSMTabDragAssistant.shared().isDragging())
        // The drop-slot placeholder for the group is the drag's target cell; it
        // must span the run: chip leading edge (0) through the last member's
        // trailing edge (chip 40 + member 120 + member 120 = 280).
        guard let target = PSMTabDragAssistant.shared().targetCell() else {
            XCTFail("no target cell after starting a group drag")
            return
        }
        XCTAssertTrue(target.isPlaceholder)
        // The slot opened to the whole group's width (chip 40 + 120 + 120 = 280),
        // not a single tab's (120). Layout applies a small leading inset, so
        // compare loosely rather than to an exact frame.
        XCTAssertGreaterThan(target.frame.width, 200)
    }

    // Regression guard for the field use-after-free: the group drag must read the
    // chip's frame (to size the run's drop slot) BEFORE the base placeholder
    // distribution strips chip cells from the control. If that order is reversed,
    // the chip has been removed from the cell list (and, in production, freed) by
    // the time its frame is read.
    func testChipFrameIsReadBeforeChipsAreStripped() {
        let (chip, members) = makeGroupedBar()
        let observing = chip as! ObservingChipCell
        let event = mouseDownEvent(at: NSPoint(x: 20, y: 12))
        PSMTabDragAssistant.shared().startDraggingGroup(withChip: chip,
                                                        members: members,
                                                        fromTabBar: control,
                                                        withMouseDownEvent: event)
        XCTAssertFalse(observing.frameReadAfterStrip,
                       "chip.frame was read after the chip was stripped from the control -- this is the use-after-free")
    }
}
