//
//  PSMTabGroupEnumeratorTests.swift
//  iTerm2XCTests
//
//  Chip cells live in the control's cells array but do not represent tabs.
//  These tests pin down the enumerators that must be chip-transparent: the
//  overflow menu (a chip must not become a blank, selectable menu item), the
//  visible-tab count (a sole tab in a one-tab group is still a solitary tab),
//  lastVisibleTab (a drop-target fallback must be a real tab), accessibility
//  (chips are not AX tabs), and the horizontal width computation (creating a
//  group must not silently disable fit-to-content sizing).
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabGroupEnumeratorTests: XCTestCase {
    private var control: PSMTabBarControl!
    private var items: [NSTabViewItem] = []

    override func setUp() {
        super.setUp()
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 600, height: 24))
        items = []
    }

    override func tearDown() {
        control = nil
        items = []
        super.tearDown()
    }

    private func tabCell(_ groupID: String?, label: String = "Tab") -> PSMTabBarCell {
        let cell = PSMTabBarCell(controlView: control)!
        cell.tabGroupIdentifier = groupID
        let item = NSTabViewItem(identifier: label as NSString)
        item.label = label
        items.append(item)
        cell.representedObject = item
        cell.bind(NSBindingName("title"), to: item, withKeyPath: "label", options: nil)
        return cell
    }

    private func chipCell(_ groupID: String) -> PSMTabBarCell {
        let cell = PSMTabBarCell(controlView: control)!
        cell.isTabGroupChip = true
        cell.tabGroupIdentifier = groupID
        return cell
    }

    private func setCells(_ cells: [PSMTabBarCell]) {
        control.cells().setArray(cells)
    }

    // MARK: - Overflow menu

    // A chip past the visible prefix must not become a menu item: it has no
    // representedObject, so selecting its (blank) item would call
    // -selectTabViewItem:nil.
    func testOverflowMenuSkipsChipCells() {
        setCells([tabCell(nil, label: "one"),
                  chipCell("A"),
                  tabCell("A", label: "two"),
                  tabCell("A", label: "three")])
        // One visible cell; the chip and both group members overflow.
        guard let menu = control.perform(Selector(("_setupCells:")), with: [100.0] as NSArray)?
            .takeUnretainedValue() as? NSMenu else {
            XCTFail("overflow menu was not built")
            return
        }
        let tabItems = menu.items.filter { $0.action != nil }
        XCTAssertEqual(tabItems.count, 2, "exactly the two overflowed tabs get menu items")
        for item in tabItems {
            XCTAssertNotNil(item.representedObject,
                            "menu item “\(item.title)” has no represented tab; selecting it would select nil")
            XCTAssertFalse(item.title.isEmpty)
        }
    }

    // MARK: - numberOfVisibleTabs

    // A window whose sole tab is in a one-tab group has ONE tab, not two.
    // (PseudoTerminal's solitary-tab drag-to-move-window conversion keys off
    // this count.)
    func testNumberOfVisibleTabsExcludesChips() {
        setCells([chipCell("A"), tabCell("A")])
        XCTAssertEqual(control.numberOfVisibleTabs(), 1)
    }

    func testNumberOfVisibleTabsStopsAtOverflowBoundary() {
        let overflowed = tabCell(nil, label: "hidden")
        overflowed.isInOverflowMenu = true
        setCells([tabCell(nil, label: "shown"), overflowed])
        XCTAssertEqual(control.numberOfVisibleTabs(), 1)
    }

    func testNumberOfVisibleTabsMixedChipsAndOverflow() {
        let overflowed = tabCell("A", label: "hidden")
        overflowed.isInOverflowMenu = true
        setCells([tabCell(nil, label: "shown"), chipCell("A"), tabCell("A", label: "member"), overflowed])
        XCTAssertEqual(control.numberOfVisibleTabs(), 2)
    }

    // MARK: - lastVisibleTab

    // When the visible prefix ends right after a chip (chip visible, its
    // members overflowed), the last visible TAB is the one before the chip.
    func testLastVisibleTabSkipsChipAtOverflowBoundary() {
        let first = tabCell(nil, label: "first")
        let chip = chipCell("A")
        let member = tabCell("A", label: "member")
        member.isInOverflowMenu = true
        setCells([first, chip, member])
        XCTAssertTrue(control.lastVisibleTab() === first)
    }

    func testLastVisibleTabWithoutOverflowSkipsTrailingChip() {
        let first = tabCell(nil, label: "first")
        let chip = chipCell("A")
        setCells([first, chip])
        XCTAssertTrue(control.lastVisibleTab() === first)
    }

    // MARK: - Accessibility

    func testAccessibilityTabsExcludeChips() {
        let chip = chipCell("A")
        let m1 = tabCell("A", label: "one")
        let m2 = tabCell(nil, label: "two")
        setCells([chip, m1, m2])
        let tabs = control.accessibilityTabs() as! [AnyObject]
        XCTAssertEqual(tabs.count, 2)
        XCTAssertFalse(tabs.contains(where: { $0 === chip.element }))
    }

    func testAccessibilityChildrenExcludeChips() {
        let chip = chipCell("A")
        let m1 = tabCell("A", label: "one")
        let m2 = tabCell(nil, label: "two")
        setCells([chip, m1, m2])
        let children = control.accessibilityChildren() as! [AnyObject]
        XCTAssertTrue(children.contains(where: { $0 === m1.element }))
        XCTAssertTrue(children.contains(where: { $0 === m2.element }))
        XCTAssertFalse(children.contains(where: { $0 === chip.element }),
                       "chip cells must not be published as accessibility tabs")
    }

    // MARK: - Fit-to-content widths with a group present

    // Creating a group must not silently disable “use tab widths that fit
    // their contents”: with plenty of room, two tabs with very different
    // title lengths keep different (desired) widths even when a chip cell
    // is present.
    func testFitToContentSurvivesGroupCreation() {
        control.sizeCellsToFit = true
        let short_ = tabCell("A", label: "ab")
        let long_ = tabCell("A", label: "a much longer tab title that wants real width")
        setCells([chipCell("A"), short_, long_])
        guard let widths = control.cellWidths(forHorizontalArrangementWithOverflow: false) else {
            XCTFail("no widths")
            return
        }
        XCTAssertEqual(widths.count, 3)
        let shortWidth = widths[1].doubleValue
        let longWidth = widths[2].doubleValue
        XCTAssertGreaterThan(longWidth, shortWidth,
                             "fit-to-content was ignored: tabs got uniform widths because a group exists")
    }

    // MARK: - Shared run enumeration

    private struct Run: Equatable {
        var groupID: String
        var memberCount: Int
        var rect: NSRect
    }

    private func runs() -> [Run] {
        var result: [Run] = []
        control.enumerateTabGroupRuns(rectForCell: nil) { chip, tabsRect, _, gid in
            var members = 0
            var seen = false
            for cell in self.control.cells() as! [PSMTabBarCell] {
                if cell === chip { seen = true; continue }
                if seen && !cell.isPlaceholder && !cell.isTabGroupChip &&
                    cell.tabGroupIdentifier == gid {
                    members += 1
                }
            }
            result.append(Run(groupID: gid, memberCount: members, rect: tabsRect))
        }
        return result
    }

    // Placeholders inside a run are transparent; the run's rect spans its
    // members, and a join end-slot is unioned in.
    func testRunEnumerationSpansPlaceholdersAndJoinSlots() {
        let m1 = tabCell("A", label: "one")
        m1.frame = NSRect(x: 40, y: 0, width: 100, height: 24)
        let ph = PSMTabBarCell(placeholderWithFrame: NSRect(x: 140, y: 0, width: 20, height: 24),
                               expanded: true, inControlView: control)!
        let m2 = tabCell("A", label: "two")
        m2.frame = NSRect(x: 160, y: 0, width: 100, height: 24)
        let joinSlot = PSMTabBarCell(placeholderWithFrame: NSRect(x: 260, y: 0, width: 30, height: 24),
                                     expanded: true, inControlView: control)!
        joinSlot.joinsTabGroupIdentifier = "A"
        let chip = chipCell("A")
        chip.frame = NSRect(x: 0, y: 0, width: 40, height: 24)
        setCells([chip, m1, ph, m2, joinSlot, tabCell(nil, label: "loner")])

        let found = runs()
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].groupID, "A")
        // The rect spans m1 through the join slot (40...290).
        XCTAssertEqual(found[0].rect.minX, 40)
        XCTAssertEqual(found[0].rect.maxX, 290)
    }

    // The dragged member's own drop slot carries the group id (dropping there
    // keeps membership), so the run rect must enclose it: the outline shrinks
    // smoothly as the slot collapses instead of snapping down at drag start
    // and visually contradicting the drop.
    func testRunEnumerationIncludesDraggedMembersOwnSlot() {
        let chip = chipCell("A")
        chip.frame = NSRect(x: 0, y: 0, width: 40, height: 24)
        let m1 = tabCell("A", label: "one")
        m1.frame = NSRect(x: 40, y: 0, width: 100, height: 24)
        // The dragged LAST member's slot: expanded, carries the gid.
        let ownSlot = PSMTabBarCell(placeholderWithFrame: NSRect(x: 140, y: 0, width: 100, height: 24),
                                    expanded: true, inControlView: control)!
        ownSlot.tabGroupIdentifier = "A"
        setCells([chip, m1, ownSlot, tabCell(nil, label: "loner")])

        let found = runs()
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].rect.maxX, 240,
                       "the run rect must span the dragged member's own slot, not stop at the last present member")
    }

    // A run ends at another chip or a different group id; chip cells with no
    // members produce no run.
    func testRunEnumerationStopsAtNextGroup() {
        setCells([chipCell("A"), tabCell("A", label: "a1"),
                  chipCell("B"), tabCell("B", label: "b1"), tabCell("B", label: "b2")])
        let found = runs()
        XCTAssertEqual(found.map(\.groupID), ["A", "B"])
    }

    // Overflowed cells end the run (their frames are meaningless).
    func testRunEnumerationStopsAtOverflow() {
        let hidden = tabCell("A", label: "hidden")
        hidden.isInOverflowMenu = true
        setCells([chipCell("A"), tabCell("A", label: "shown"), hidden])
        let found = runs()
        XCTAssertEqual(found.count, 1)
    }

    // MARK: - Membership push

    // The membership push must match cells to tabs by tab view item, never by
    // position: mid-drag the dragged tab's cell is replaced by a placeholder
    // (absent from the cells array) while the tab is still in the window, so
    // positional pairing shifts every later tab's group id by one. Regression:
    // dragging the last member of group A made the following one-tab group B
    // disappear (its cell was pushed A's id).
    func testMembershipPushMatchesByItemNotPosition() {
        let t1 = tabCell("A", label: "t1")
        let t2 = tabCell("A", label: "t2")
        let t3 = tabCell("A", label: "t3")   // being dragged; its cell is not in the bar
        let t4 = tabCell("B", label: "t4")
        _ = t3
        let ownSlot = PSMTabBarCell(placeholderWithFrame: NSRect(x: 0, y: 0, width: 0, height: 24),
                                    expanded: true, inControlView: control)!
        ownSlot.tabGroupIdentifier = "A"
        setCells([chipCell("A"), t1, t2, ownSlot, chipCell("B"), t4])

        // The window still has 4 tabs, in order [t1 A, t2 A, t3 A, t4 B].
        let identifiers: [Any] = ["A", "A", "A", "B"]
        let tabViewItems = [items[0], items[1], items[2], items[3]]
        control.setTabGroupIdentifiers(identifiers, for: tabViewItems)

        XCTAssertEqual(t4.tabGroupIdentifier, "B",
                       "t4 must keep group B; positional pairing would hand it the dragged tab's group A")
        XCTAssertEqual(t1.tabGroupIdentifier, "A")
        XCTAssertEqual(t2.tabGroupIdentifier, "A")
    }

    // The push still applies real changes (ungrouping every tab).
    func testMembershipPushAppliesChanges() {
        let t1 = tabCell("A", label: "t1")
        let t2 = tabCell("A", label: "t2")
        setCells([chipCell("A"), t1, t2])
        control.setTabGroupIdentifiers([NSNull(), NSNull()],
                                       for: [items[0], items[1]])
        XCTAssertNil(t1.tabGroupIdentifier)
        XCTAssertNil(t2.tabGroupIdentifier)
        // Chips are re-derived: none remain.
        XCTAssertFalse((control.cells() as! [PSMTabBarCell]).contains { $0.isTabGroupChip })
    }

    // MARK: - Group-run outset

    // The scrollable bar widens its trailing clip by the style's run outset so
    // a group pill isn't clipped; with no groups there is nothing to widen and
    // the clip must stay exactly at the viewport.
    func testGroupRunOutsetZeroWithoutChips() {
        setCells([tabCell(nil, label: "one"), tabCell(nil, label: "two")])
        XCTAssertEqual(control.effectiveTabGroupRunOutset(), 0)
    }

    func testGroupRunOutsetAppliesWithChips() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("only the Tahoe style has a group-run outset")
        }
        control.style = PSMTahoeTabStyle()
        setCells([chipCell("A"), tabCell("A", label: "one")])
        XCTAssertGreaterThan(control.effectiveTabGroupRunOutset(), 0)
    }
}
