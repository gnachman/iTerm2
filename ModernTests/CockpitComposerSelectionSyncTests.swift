//
//  CockpitComposerSelectionSyncTests.swift
//  ModernTests
//
//  The cockpit keeps the composer's @-mention chips and the outline's row
//  selection in sync. A selection change used to replace every chip with
//  chips for the selected visible rows, so an @chip for a session whose row
//  was collapsed or filtered away vanished when the user clicked another
//  row, silently retargeting the typed command. A click now replaces only
//  chips the user could see and didn't select.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class CockpitComposerSelectionSyncTests: XCTestCase {
    private typealias Target = (token: String, name: String)

    private func tokens(_ targets: [Target]) -> [String] {
        return targets.map { $0.token }
    }

    // Composer “@TWO echo”, TWO's row inside a collapsed group, user clicks
    // ONE's row: the chip for TWO must survive alongside ONE.
    func testChipForHiddenRowSurvivesClickOnAnotherRow() {
        let result = CockpitWindowController.composerTargets(
            existing: [("two", "TWO")],
            selected: [("one", "ONE")],
            releasable: ["one", "three"])
        XCTAssertEqual(tokens(result), ["two", "one"])
        XCTAssertEqual(result.map { $0.name }, ["TWO", "ONE"])
    }

    // A chip for a row the user can see but didn't select is retargeted
    // away by the click.
    func testChipForVisibleUnselectedRowIsReplaced() {
        let result = CockpitWindowController.composerTargets(
            existing: [("one", "ONE")],
            selected: [("three", "THREE")],
            releasable: ["one", "three"])
        XCTAssertEqual(tokens(result), ["three"])
    }

    // A chip that is also selected appears once, in selection order.
    func testSelectedChipIsNotDuplicated() {
        let result = CockpitWindowController.composerTargets(
            existing: [("two", "TWO"), ("one", "ONE")],
            selected: [("one", "ONE"), ("three", "THREE")],
            releasable: ["one", "three"])
        XCTAssertEqual(tokens(result), ["two", "one", "three"])
    }

    // Deselecting everything keeps chips the user couldn't see.
    func testEmptySelectionKeepsOnlyHiddenChips() {
        let result = CockpitWindowController.composerTargets(
            existing: [("one", "ONE"), ("two", "TWO")],
            selected: [],
            releasable: ["one"])
        XCTAssertEqual(tokens(result), ["two"])
    }

    // Sessions contributed by a previously selected container row (e.g. a
    // collapsed workgroup) are releasable once the user clicks away from
    // it, even though their own rows are hidden, so they go too.
    func testChipsReleasedByDeselectedContainerAreReplaced() {
        let result = CockpitWindowController.composerTargets(
            existing: [("two", "TWO"), ("four", "FOUR"), ("six", "SIX")],
            selected: [("one", "ONE")],
            releasable: ["one", "two", "four"])
        XCTAssertEqual(tokens(result), ["six", "one"])
    }

    // When nothing about the chips changes, the result equals the existing
    // chips, so the caller can skip rewriting the composer.
    func testUnchangedSelectionYieldsSameChipSet() {
        let result = CockpitWindowController.composerTargets(
            existing: [("two", "TWO"), ("one", "ONE")],
            selected: [("one", "ONE")],
            releasable: ["one"])
        XCTAssertEqual(Set(tokens(result)), ["two", "one"])
    }

    // Rows on screen release their own targets; a row the user selected
    // before and has now deselected releases what it contributed (a
    // collapsed workgroup's hidden sessions) while it's on screen.
    func testReleasableTokensRule() {
        let releasable = CockpitWindowController.releasableTokens(
            visibleRows: [(identity: "ONE", ownTokens: ["one"]),
                          (identity: "W", ownTokens: []),
                          (identity: "V", ownTokens: [])],
            selected: ["ONE", "V"],
            lastSelection: ["W": ["two", "four"],
                            "V": ["five"],
                            "GONE": ["six"]])
        // W: visible and deselected, releases. V: still selected, keeps.
        // GONE: no longer on screen (hidden or removed), keeps.
        XCTAssertEqual(releasable, ["one", "two", "four"])
    }

    // A typed chip for a hidden session survives the click that releases
    // a previously selected container.
    func testHiddenTypedChipSurvivesReleaseOfContainer() {
        let releasable = CockpitWindowController.releasableTokens(
            visibleRows: [(identity: "ONE", ownTokens: ["one"]), (identity: "W", ownTokens: [])],
            selected: ["ONE"],
            lastSelection: ["W": ["four"]])
        let result = CockpitWindowController.composerTargets(
            existing: [("two", "TWO"), ("four", "FOUR")],
            selected: [("one", "ONE")],
            releasable: releasable)
        XCTAssertEqual(tokens(result), ["two", "one"])
    }

    // A refresh leaves the composer alone, except that chips whose target
    // went away (session, tab, or window closed) are dropped so the next
    // send doesn't fail on an unknown target.
    func testRefreshDropsOnlyUnresolvableChips() throws {
        let result = try XCTUnwrap(CockpitWindowController.composerTargetsDroppingUnresolvable(
            existing: [("two", "TWO"), ("dead", "DEAD"), ("one", "ONE")],
            isResolvable: { $0 != "dead" }))
        XCTAssertEqual(tokens(result), ["two", "one"])
    }

    // Returns nil when every chip still resolves, so the caller leaves
    // the composer (and its caret) untouched.
    func testRefreshWithAllChipsResolvableChangesNothing() {
        XCTAssertNil(CockpitWindowController.composerTargetsDroppingUnresolvable(
            existing: [("two", "TWO"), ("one", "ONE")],
            isResolvable: { _ in true }))
    }
}

// The refresh guard (isRefreshingOutline) only works if NSOutlineView
// reports the selection change from a moved row synchronously, while
// refresh() is still running, rather than later on the run loop. Pin
// that down.
@MainActor
final class CockpitOutlineMoveSelectionTests: XCTestCase {
    private final class Item {
        let name: String
        var children: [Item] = []
        init(_ name: String) { self.name = name }
    }

    private final class DataSource: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var roots: [Item] = []
        var selectionChanges = 0
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            return (item as? Item)?.children.count ?? roots.count
        }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            return (item as? Item)?.children[index] ?? roots[index]
        }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            return !((item as? Item)?.children.isEmpty ?? true)
        }
        func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
            return (item as? Item)?.name
        }
        func outlineViewSelectionDidChange(_ notification: Notification) {
            selectionChanges += 1
        }
    }

    func testMovingSelectedRowBetweenParentsReportsSelectionChangeSynchronously() throws {
        let outline = NSOutlineView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        outline.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c")))
        let source = DataSource()
        let working = Item("working")
        let done = Item("done")
        let one = Item("ONE")
        working.children = [one]
        done.children = [Item("THREE")]
        source.roots = [working, done]
        outline.dataSource = source
        outline.delegate = source
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
        outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: one)), byExtendingSelection: false)
        source.selectionChanges = 0

        working.children = []
        done.children.insert(one, at: 0)
        outline.beginUpdates()
        // refresh()'s applyDiff moves a row by removing it from the old
        // parent and inserting it under the new one.
        outline.removeItems(at: IndexSet(integer: 0), inParent: working, withAnimation: [])
        outline.insertItems(at: IndexSet(integer: 0), inParent: done, withAnimation: [])
        outline.endUpdates()

        // The move cleared ONE's selection and said so before returning,
        // which is when refresh() still has isRefreshingOutline set.
        XCTAssertGreaterThan(source.selectionChanges, 0)
        XCTAssertTrue(outline.selectedRowIndexes.isEmpty)
    }
}
