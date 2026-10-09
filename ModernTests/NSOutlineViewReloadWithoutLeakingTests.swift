//
//  NSOutlineViewReloadWithoutLeakingTests.swift
//  iTerm2 ModernTests
//
//  -it_reloadDataWithoutLeaking must leave the outline view showing the data
//  source's current model, with expansion and selection kept by item, the way
//  -reloadData does. Whether it leaks disclosure buttons depends on display
//  cycles, which tests/outline-view-disclosure-button-leak.m covers.
//

import XCTest
@testable import iTerm2SharedARC

// Items are path strings: "3" is top-level item 3, "3/1" is its second child.
// Strings compare by value, so a reload that recreates items still matches.
// When `boxed` is set, items are instead wrapped in a fresh PathBox on every
// call. PathBox doesn't override isEqual:, so items never match across reloads.
private final class PathBox: NSObject {
    let path: String

    init(_ path: String) {
        self.path = path
    }
}

private final class PathDataSource: NSObject, NSOutlineViewDataSource {
    var topLevelCount = 4
    var childCount = 2
    var maxDepth = 3
    var boxed = false

    private func path(_ item: Any) -> String {
        return (item as? PathBox)?.path ?? (item as! String)
    }

    private func wrap(_ path: String) -> Any {
        return boxed ? PathBox(path) : path
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item else {
            return topLevelCount
        }
        return path(item).split(separator: "/").count < maxDepth ? childCount : 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item else {
            return wrap(String(index))
        }
        return wrap("\(path(item))/\(index)")
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return self.outlineView(outlineView, numberOfChildrenOfItem: item) > 0
    }
}

final class NSOutlineViewReloadWithoutLeakingTests: XCTestCase {
    private var dataSource: PathDataSource!
    private var outlineView: NSOutlineView!

    override func setUp() {
        super.setUp()
        dataSource = PathDataSource()
        outlineView = NSOutlineView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.dataSource = dataSource
        outlineView.reloadData()
    }

    override func tearDown() {
        outlineView.dataSource = nil
        outlineView = nil
        dataSource = nil
        super.tearDown()
    }

    private var rows: [String] {
        return (0..<outlineView.numberOfRows).map {
            let item = outlineView.item(atRow: $0)
            return (item as? PathBox)?.path ?? (item as! String)
        }
    }

    func testShowsGrownAndShrunkTopLevel() {
        XCTAssertEqual(rows, ["0", "1", "2", "3"])

        dataSource.topLevelCount = 6
        outlineView.reloadDataWithoutLeaking()
        XCTAssertEqual(rows, ["0", "1", "2", "3", "4", "5"])

        dataSource.topLevelCount = 2
        outlineView.reloadDataWithoutLeaking()
        XCTAssertEqual(rows, ["0", "1"])

        dataSource.topLevelCount = 0
        outlineView.reloadDataWithoutLeaking()
        XCTAssertEqual(rows, [])

        dataSource.topLevelCount = 1
        outlineView.reloadDataWithoutLeaking()
        XCTAssertEqual(rows, ["0"])
    }

    func testKeepsNestedExpansion() {
        outlineView.expandItem("1")
        outlineView.expandItem("1/0")
        XCTAssertEqual(rows, ["0", "1", "1/0", "1/0/0", "1/0/1", "1/1", "2", "3"])

        dataSource.topLevelCount = 3
        outlineView.reloadDataWithoutLeaking()

        XCTAssertEqual(rows, ["0", "1", "1/0", "1/0/0", "1/0/1", "1/1", "2"])
        XCTAssertTrue(outlineView.isItemExpanded("1"))
        XCTAssertTrue(outlineView.isItemExpanded("1/0"))
        XCTAssertFalse(outlineView.isItemExpanded("1/1"))
    }

    func testDropsExpansionOfItemsThatAreGone() {
        outlineView.expandItem("3")
        dataSource.topLevelCount = 2
        outlineView.reloadDataWithoutLeaking()
        dataSource.topLevelCount = 4
        outlineView.reloadDataWithoutLeaking()

        XCTAssertEqual(rows, ["0", "1", "2", "3"])
    }

    func testKeepsSelectionByItem() {
        outlineView.expandItem("0")
        outlineView.selectRowIndexes(IndexSet([outlineView.row(forItem: "0/1"),
                                               outlineView.row(forItem: "3")]),
                                     byExtendingSelection: false)

        // A third child of "0" pushes "3" down a row, so a selection kept by
        // row index would land on the wrong item.
        dataSource.topLevelCount = 5
        dataSource.childCount = 3
        outlineView.reloadDataWithoutLeaking()

        let selected = outlineView.selectedRowIndexes.map { outlineView.item(atRow: $0) as! String }
        XCTAssertEqual(selected, ["0/1", "3"])
    }

    func testRemembersExpansionUnderCollapsedParent() {
        outlineView.expandItem("1")
        outlineView.expandItem("1/0")
        outlineView.collapseItem("1")

        outlineView.reloadDataWithoutLeaking()
        XCTAssertEqual(rows, ["0", "1", "2", "3"])

        outlineView.expandItem("1")
        XCTAssertEqual(rows, ["0", "1", "1/0", "1/0/0", "1/0/1", "1/1", "2", "3"])
    }

    func testKeepsSelectedRowsWhenItemsCannotBeMatched() {
        dataSource.boxed = true
        outlineView.reloadData()
        outlineView.selectRowIndexes(IndexSet([1, 3]), byExtendingSelection: false)

        dataSource.topLevelCount = 3
        outlineView.reloadDataWithoutLeaking()

        // Like -reloadData: same row indexes, minus any past the end.
        XCTAssertEqual(outlineView.selectedRowIndexes, IndexSet([1]))
    }
}
