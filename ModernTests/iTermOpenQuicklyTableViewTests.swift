//
//  iTermOpenQuicklyTableViewTests.swift
//  ModernTests
//
//  Characterization tests for iTermOpenQuicklyTableView, the table of the
//  Open Quickly window, named as a custom class in
//  iTermOpenQuicklyWindowController.xib. It never accepts first responder,
//  and an unmodified down arrow on the last row or up arrow on the first row
//  wraps the selection around; every other key goes to NSTableView. The
//  class is found by its runtime name, as nib loading finds it. Nothing is
//  put on screen: the tables have no window.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

private final class RowsDataSource: NSObject, NSTableViewDataSource {
    let rows: Int

    init(rows: Int) {
        self.rows = rows
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return rows
    }
}

final class iTermOpenQuicklyTableViewTests: XCTestCase {
    private let unitClassName = "iTermOpenQuicklyTableView"
    private let down = "\u{F701}"
    private let up = "\u{F700}"
    private var dataSources = [RowsDataSource]()

    private var tableClass: NSTableView.Type? {
        return NSClassFromString(unitClassName) as? NSTableView.Type
    }

    private func ownMethods(_ cls: AnyClass) -> [String: String] {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else {
            return [:]
        }
        defer { free(methods) }
        return Dictionary(uniqueKeysWithValues: (0..<Int(count)).map {
            (NSStringFromSelector(method_getName(methods[$0])),
             method_getTypeEncoding(methods[$0]).map { String(cString: $0) } ?? "")
        })
    }

    private func makeTable(_ cls: NSTableView.Type, rows: Int, selected: Int?) -> NSTableView {
        let table = cls.init(frame: NSRect(x: 0, y: 0, width: 100, height: 200))
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column")))
        let dataSource = RowsDataSource(rows: rows)
        dataSources.append(dataSource)
        table.dataSource = dataSource
        table.reloadData()
        if let selected {
            table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
        }
        return table
    }

    private func key(_ characters: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent? {
        let keyCode: UInt16 = characters == down ? 125 : 126
        return NSEvent.keyEvent(with: .keyDown,
                                location: .zero,
                                modifierFlags: flags,
                                timestamp: 0,
                                windowNumber: 0,
                                context: nil,
                                characters: characters,
                                charactersIgnoringModifiers: characters,
                                isARepeat: false,
                                keyCode: keyCode)
    }

    // The selected row after the key, for the class under test and for a
    // plain NSTableView set up the same way.
    private func selectedRows(rows: Int,
                              selected: Int?,
                              characters: String,
                              flags: NSEvent.ModifierFlags = []) -> (Int, Int)? {
        guard let cls = tableClass, let event = key(characters, flags) else {
            XCTFail("no class or event")
            return nil
        }
        let table = makeTable(cls, rows: rows, selected: selected)
        let plain = makeTable(NSTableView.self, rows: rows, selected: selected)
        table.keyDown(with: event)
        plain.keyDown(with: event)
        return (table.selectedRow, plain.selectedRow)
    }

    func testClassExistsUnderItsNameWithItsSuperclass() {
        guard let cls = tableClass else {
            XCTFail("no class")
            return
        }
        XCTAssertTrue(class_getSuperclass(cls) === NSTableView.self)
    }

    func testSelectorsAndEncodings() {
        guard let cls = tableClass else {
            XCTFail("no class")
            return
        }
        let methods = ownMethods(cls)
        XCTAssertEqual(methods["acceptsFirstResponder"], "B16@0:8")
        XCTAssertEqual(methods["keyDown:"], "v24@0:8@16")
    }

    func testDoesNotAcceptFirstResponder() {
        guard let cls = tableClass else {
            XCTFail("no class")
            return
        }
        XCTAssertFalse(cls.init(frame: .zero).acceptsFirstResponder)
    }

    func testTheNibMakesTheTableWithThisClass() {
        guard let nib = NSNib(nibNamed: "iTermOpenQuicklyWindowController", bundle: nil) else {
            XCTFail("no nib")
            return
        }
        var objects: NSArray?
        XCTAssertTrue(nib.instantiate(withOwner: nil, topLevelObjects: &objects))
        let windows = (objects as? [Any] ?? []).compactMap { $0 as? NSWindow }
        XCTAssertEqual(windows.count, 1)
        func tables(in view: NSView) -> [NSTableView] {
            return ((view as? NSTableView).map { [$0] } ?? []) + view.subviews.flatMap { tables(in: $0) }
        }
        let found = windows.first?.contentView.map { tables(in: $0) } ?? []
        XCTAssertEqual(found.map { NSStringFromClass(type(of: $0)) }, [unitClassName])
        XCTAssertFalse(windows.first?.isVisible ?? true)
    }

    func testDownArrowOnLastRowWrapsToFirst() {
        guard let (selected, plain) = selectedRows(rows: 3, selected: 2, characters: down) else {
            return
        }
        XCTAssertEqual(selected, 0)
        XCTAssertEqual(plain, 2)
    }

    func testUpArrowOnFirstRowWrapsToLast() {
        guard let (selected, plain) = selectedRows(rows: 3, selected: 0, characters: up) else {
            return
        }
        XCTAssertEqual(selected, 2)
        XCTAssertEqual(plain, 0)
    }

    func testSingleRowWrapsToItself() {
        XCTAssertEqual(selectedRows(rows: 1, selected: 0, characters: down)?.0, 0)
        XCTAssertEqual(selectedRows(rows: 1, selected: 0, characters: up)?.0, 0)
    }

    // Away from the ends, NSTableView moves the selection.
    func testArrowsInTheMiddleMoveAsNSTableViewDoes() {
        guard let (afterDown, plainDown) = selectedRows(rows: 3, selected: 1, characters: down),
              let (afterUp, plainUp) = selectedRows(rows: 3, selected: 1, characters: up) else {
            return
        }
        XCTAssertEqual(afterDown, plainDown)
        XCTAssertEqual(afterDown, 2)
        XCTAssertEqual(afterUp, plainUp)
        XCTAssertEqual(afterUp, 0)
    }

    func testShiftedArrowsDoNotWrap() {
        guard let (afterDown, plainDown) = selectedRows(rows: 3, selected: 2, characters: down, flags: .shift),
              let (afterUp, plainUp) = selectedRows(rows: 3, selected: 0, characters: up, flags: .shift) else {
            return
        }
        XCTAssertEqual(afterDown, plainDown)
        XCTAssertEqual(afterDown, 2)
        XCTAssertEqual(afterUp, plainUp)
        XCTAssertEqual(afterUp, 0)
    }

    func testNoSelectionGoesToNSTableView() {
        guard let (afterDown, plainDown) = selectedRows(rows: 3, selected: nil, characters: down),
              let (afterUp, plainUp) = selectedRows(rows: 3, selected: nil, characters: up) else {
            return
        }
        XCTAssertEqual(afterDown, plainDown)
        XCTAssertEqual(afterUp, plainUp)
    }

    func testEmptyTableGoesToNSTableView() {
        guard let (afterDown, plainDown) = selectedRows(rows: 0, selected: nil, characters: down) else {
            return
        }
        XCTAssertEqual(afterDown, plainDown)
        XCTAssertEqual(afterDown, -1)
    }
}
