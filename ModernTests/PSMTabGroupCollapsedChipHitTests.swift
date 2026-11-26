//
//  PSMTabGroupCollapsedChipHitTests.swift
//  iTerm2XCTests
//
//  -wantsMouseDownAtPoint: decides whether a mouse-down belongs to the tab bar
//  or starts a window drag (iTermTabBarControlView asks it). The members of a
//  collapsed group are hidden cells with zero-size frames placed at the chip's
//  origin, so a collapsed group at the end of the bar must not make the bar
//  think it ends where the chip begins. Otherwise a click on the chip drags the
//  window and the group never expands.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabGroupCollapsedChipHitTests: XCTestCase {
    private var window: NSWindow!
    private var control: PSMTabBarControl!
    private var items: [NSTabViewItem] = []

    override func setUp() {
        super.setUp()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                          styleMask: [.titled], backing: .buffered, defer: false)
    }

    override func tearDown() {
        items = []
        control = nil
        window = nil
        super.tearDown()
    }

    private func makeControl(vertical: Bool) {
        let frame = vertical ? NSRect(x: 0, y: 0, width: 400, height: 600)
                             : NSRect(x: 0, y: 576, width: 800, height: 24)
        control = PSMTabBarControl(frame: frame)
        control.orientation = vertical ? .verticalOrientation : .horizontalOrientation
        window.contentView?.addSubview(control)
    }

    private func tab(_ groupID: String?, collapsed: Bool, frame: NSRect) -> PSMTabBarCell {
        let cell = PSMTabBarCell(controlView: control)!
        cell.tabGroupIdentifier = groupID
        cell.isCollapsedHidden = collapsed
        let item = NSTabViewItem(identifier: (groupID ?? "-") as NSString)
        items.append(item)
        cell.representedObject = item
        cell.frame = frame
        return cell
    }

    private func chip(_ groupID: String, frame: NSRect) -> PSMTabBarCell {
        let cell = PSMTabBarCell(controlView: control)!
        cell.isTabGroupChip = true
        cell.tabGroupIdentifier = groupID
        cell.frame = frame
        return cell
    }

    // Vertical bar: [tab][chip G (collapsed)][m0 hidden][m1 hidden]. The hidden
    // members get zero-height frames at the chip's origin, as -_setupCells: lays
    // them out.
    func testVerticalClickOnTrailingCollapsedChipBelongsToTabBar() {
        makeControl(vertical: true)
        let chipFrame = NSRect(x: 0, y: 72, width: 400, height: 38)
        let hiddenFrame = NSRect(x: 0, y: 72, width: 0, height: 0)
        control.cells().setArray([
            tab(nil, collapsed: false, frame: NSRect(x: 0, y: 0, width: 400, height: 72)),
            chip("G", frame: chipFrame),
            tab("G", collapsed: true, frame: hiddenFrame),
            tab("G", collapsed: true, frame: hiddenFrame),
        ])

        XCTAssertTrue(control.wantsMouseDown(at: NSPoint(x: 100, y: 36)),
                      "a click on a tab belongs to the tab bar")
        XCTAssertTrue(control.wantsMouseDown(at: NSPoint(x: 100, y: 90)),
                      "a click on the collapsed chip must not drag the window")
        XCTAssertFalse(control.wantsMouseDown(at: NSPoint(x: 100, y: 300)),
                       "empty space below the chip still drags the window")
    }

    // Horizontal bar with the same shape. Hidden members sit past the chip, at
    // the next x origin.
    func testHorizontalClickOnTrailingCollapsedChipBelongsToTabBar() {
        makeControl(vertical: false)
        let hiddenFrame = NSRect(x: 182, y: 0, width: 0, height: 0)
        control.cells().setArray([
            tab(nil, collapsed: false, frame: NSRect(x: 0, y: 0, width: 120, height: 24)),
            chip("G", frame: NSRect(x: 121, y: 0, width: 60, height: 24)),
            tab("G", collapsed: true, frame: hiddenFrame),
            tab("G", collapsed: true, frame: hiddenFrame),
        ])

        XCTAssertTrue(control.wantsMouseDown(at: NSPoint(x: 150, y: 12)),
                      "a click on the collapsed chip must not drag the window")
        XCTAssertFalse(control.wantsMouseDown(at: NSPoint(x: 400, y: 12)),
                       "empty space right of the chip still drags the window")
    }

    // Every cell hidden would mean nothing is drawn: nothing claims the click.
    func testVerticalWithOnlyHiddenCellsDoesNotClaimClicks() {
        makeControl(vertical: true)
        control.cells().setArray([
            tab("G", collapsed: true, frame: .zero),
        ])
        XCTAssertFalse(control.wantsMouseDown(at: NSPoint(x: 100, y: 10)))
    }
}
