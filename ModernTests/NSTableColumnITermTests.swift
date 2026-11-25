//
//  NSTableColumnITermTests.swift
//  ModernTests
//
//  Characterization tests for the category NSTableColumn (iTerm):
//  -suggestedRowHeight is the height of [dataCell cellSizeForBounds:] for
//  bounds of the column's width and unbounded height, and 0 when dataCell is
//  nil. Written against the Objective-C runtime interface so they run
//  unchanged against a Swift extension with the same selector.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class NSTableColumnITermTests: XCTestCase {
    private let selector = NSSelectorFromString("suggestedRowHeight")

    // Through key-value coding, which sends the selector and boxes the
    // CGFloat it returns.
    private func suggestedRowHeight(_ column: NSTableColumn) -> CGFloat {
        guard let number = column.value(forKey: "suggestedRowHeight") as? NSNumber else {
            XCTFail("no value")
            return -1
        }
        return CGFloat(number.doubleValue)
    }

    func testDefaultTextCell() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        column.width = 100
        guard let cell = column.dataCell as? NSCell else {
            XCTFail("no cell")
            return
        }
        let expected = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: 100, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(expected, 0)
        XCTAssertEqual(suggestedRowHeight(column), expected)
    }

    // The height follows the cell's font and the column's width (a wrapping
    // cell needs more lines in a narrow column).
    func testFollowsTheCellAndTheWidth() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        let cell = NSTextFieldCell(textCell: "one two three four five six seven eight nine ten")
        cell.wraps = true
        cell.font = NSFont.systemFont(ofSize: 20)
        column.dataCell = cell
        column.width = 1000
        let wide = suggestedRowHeight(column)
        column.width = 40
        let narrow = suggestedRowHeight(column)
        XCTAssertEqual(wide, cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: 1000, height: CGFloat.greatestFiniteMagnitude)).height)
        XCTAssertEqual(narrow, cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: 40, height: CGFloat.greatestFiniteMagnitude)).height)
        XCTAssertGreaterThan(narrow, wide)
    }

    // The bounds passed are exactly (0, 0, width, CGFLOAT_MAX).
    func testPassesTheColumnWidthAndUnboundedHeight() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        let cell = RecordingCell(textCell: "")
        column.dataCell = cell
        column.width = 77
        XCTAssertEqual(suggestedRowHeight(column), 12.5)
        XCTAssertEqual(cell.bounds, [NSRect(x: 0, y: 0, width: 77, height: CGFloat.greatestFiniteMagnitude)])
    }

    // dataCell is declared id: the message goes to whatever object it is,
    // even one that is not an NSCell.
    func testDataCellThatIsNotACell() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        let cellLike = CellLike()
        column.dataCell = cellLike
        column.width = 33
        XCTAssertEqual(suggestedRowHeight(column), 7)
        XCTAssertEqual(cellLike.bounds, [NSRect(x: 0, y: 0, width: 33, height: CGFloat.greatestFiniteMagnitude)])
    }

    // A nil dataCell gives 0, as messaging nil did in the Objective-C.
    func testNilDataCellIsZero() {
        XCTAssertEqual(suggestedRowHeight(NilDataCellColumn.make()), 0)
    }

    func testSelectorAndEncoding() {
        guard let method = class_getInstanceMethod(NSTableColumn.self, selector),
              let encoding = method_getTypeEncoding(method) else {
            XCTFail("no method")
            return
        }
        XCTAssertEqual(String(cString: encoding), "d16@0:8")
    }
}

private final class RecordingCell: NSCell {
    var bounds = [NSRect]()

    override func cellSize(forBounds rect: NSRect) -> NSSize {
        bounds.append(rect)
        return NSSize(width: 3, height: 12.5)
    }
}

// Answers -cellSizeForBounds: without being an NSCell.
private final class CellLike: NSObject {
    var bounds = [NSRect]()

    @objc(cellSizeForBounds:)
    func cellSize(forBounds rect: NSRect) -> NSSize {
        bounds.append(rect)
        return NSSize(width: 2, height: 7)
    }

    // -[NSTableColumn setDataCell:] sends this.
    @objc(setControlView:)
    func setControlView(_ view: NSView?) {
    }
}

// An NSTableColumn whose -dataCell returns nil. Swift cannot write such an
// override, since the SDK declares the property nonnull, so the getter is
// replaced through the runtime, on this subclass only.
private final class NilDataCellColumn: NSTableColumn {
    private static let installNilGetter: Void = {
        let getter: @convention(block) (AnyObject) -> AnyObject? = { _ in nil }
        class_replaceMethod(NilDataCellColumn.self,
                            Selector(("dataCell")),
                            imp_implementationWithBlock(getter),
                            "@16@0:8")
    }()

    static func make() -> NilDataCellColumn {
        _ = installNilGetter
        let column = NilDataCellColumn(identifier: NSUserInterfaceItemIdentifier("nil"))
        column.width = 100
        return column
    }
}
