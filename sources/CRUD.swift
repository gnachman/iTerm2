//
//  CRUD.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/14/23.
//
// Usage:
// Create a CompetentTableView and a segmented button with + and -.
// Create a CRUDTableViewController
// Implement CRUDDataProvider and CRUDTableViewControllerDelegate.
// Make yourself the delegate of the CRUDTableViewController.
// You own the data model and expose it through CRUDDataProvider APIs.
// Any change to the data model that *you* initiate (including adding, even if kicked off by
// `makeNew(completion:)`, since it is asynchrnous) must be wrapped in
// CRUDTableViewController.undoable { … } and a subsequent call to makeNew's completion block,
// `reload()` or `reloadAll()`. Client-initiated inserts and deletes haven't been implemented yet.

import Foundation

enum CRUDFormatted {
    case string(String)
}

enum CRUDType {
    case string
}

struct CRUDColumn {
    var type: CRUDType
}

protocol CRUDRow {
    func format(column: Int) -> CRUDFormatted
}

protocol CRUDDataProvider {
    var count: Int { get }
    subscript(_ index: Int) -> CRUDRow { get }
    func delete(_ indexes: IndexSet)
    // Returns the index of the added item on success or nil if nothing was added.
    func makeNew(completion: @escaping (Int) -> ())
}

struct CRUDSchema {
    var columns: [CRUDColumn]
    var dataProvider: CRUDDataProvider
}

protocol CRUDTableViewControllerDelegate: AnyObject {
    associatedtype CRUDState
    
    func crudTableSelectionDidChange(_ sender: CRUDTableViewController<Self>,
                                     selectedRows: IndexSet)

    func crudTextFieldDidChange(_ sender: CRUDTableViewController<Self>,
                                row: Int,
                                column: Int,
                                newValue: String)

    func crudDoubleClick(_ sender: CRUDTableViewController<Self>,
                         row: Int,
                         column: Int)

    var crudState: CRUDState { get set }
}

protocol CompetentTableViewDelegate: NSTableViewDelegate {
    func competentTableViewDeleteSelectedRows(_ sender: CompetentTableView)
}

@objc
class CompetentTableView: NSTableView {
    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    @objc
    override func selectAll(_ sender: Any?) {
        guard let dataSource else {
            return
        }
        guard let count = dataSource.numberOfRows?(in: self), count > 0 else {
            return
        }
        self.selectRowIndexes(IndexSet(0..<count), byExtendingSelection: false)
    }

    @objc
    override func deleteBackward(_ sender: Any?) {
        guard let delegate = delegate else {
            return
        }
        guard let specializedDelegate = delegate as? CompetentTableViewDelegate else {
            return
        }
        specializedDelegate.competentTableViewDeleteSelectedRows(self)
    }
}


class CRUDTableViewController<Delegate: CRUDTableViewControllerDelegate>: NSObject, CompetentTableViewDelegate, NSTableViewDataSource {
    private let tableView: NSTableView
    private let addRemove: NSSegmentedControl
    private let schema: CRUDSchema
    weak var delegate: Delegate?

    init(tableView: CompetentTableView, addRemove: NSSegmentedControl, schema: CRUDSchema) {
        self.tableView = tableView
        self.addRemove = addRemove
        self.schema = schema

        super.init()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(handleDoubleClick(_:))
        tableView.target = self
        addRemove.target = self
        addRemove.action = #selector(handleSegmentedControl(_:))
        updateEnabled()
    }

    // MARK: - API

    func reload() {
        tableView.reloadData()
    }

    func reload(row: Int) {
        tableView.reloadData(forRowIndexes: IndexSet(integer: row),
                             columnIndexes: IndexSet(0..<schema.columns.count))
    }

    private var inUndoable = false
    private struct FullState {
        var crudState: Delegate.CRUDState?
        var visibleRect: NSRect
        var selectedRows: IndexSet
    }

    func undoable<T>(_ closure: () throws -> (T)) rethrows -> T {
        if inUndoable {
            return try closure()
        }

        precondition(!inUndoable)
        inUndoable = true
        defer {
            inUndoable = false
        }
        let undoManager = tableView.undoManager
        let savedState = delegate?.crudState
        let fullState = FullState(crudState: delegate?.crudState,
                                  visibleRect: tableView.visibleRect,
                                  selectedRows: tableView.selectedRowIndexes)
        undoManager?.beginUndoGrouping()
        undoManager?.registerUndo(withTarget: self, handler: { [weak self] crud in
            if let savedState = fullState.crudState {
                self?.undoable {
                    crud.delegate?.crudState = savedState
                }
            }
            DLog("\(self!.tableView.visibleRect) -> \(fullState.visibleRect)")
            self?.tableView.reloadData()
            self?.tableView.selectRowIndexes(fullState.selectedRows, byExtendingSelection: false)
            self?.tableView.scrollToVisible(fullState.visibleRect)
        })
        defer {
            if savedState != nil {
                undoManager?.endUndoGrouping()
            }
        }
        let result = try closure()
        return result
    }

    // MARK: - Private

    private func updateEnabled() {
        addRemove.setEnabled(true, forSegment: 0)
        addRemove.setEnabled(tableView.numberOfSelectedRows > 0, forSegment: 1)
    }

    private func add() {
        schema.dataProvider.makeNew() { [weak self] newIndex in
            self?.tableView.insertRows(at: IndexSet(integer: newIndex))
        }
    }

    private func removeSelected() {
        let indexes = tableView.selectedRowIndexes
        guard let firstIndex = indexes.min(), let lastIndex = indexes.max() else {
            return
        }
        let selectedRange = NSRange(firstIndex...lastIndex)
        if let visibleRows = tableView.rows(in: tableView.visibleRect).intersection(selectedRange),
           visibleRows.length > 0,
           let window = tableView.window {
            let rectInWindowCoords1 = tableView.convert(tableView.frameOfCell(atColumn: 0, row: visibleRows.lowerBound),
                                                       to: nil)
            let rectInWindowCoords2 = tableView.convert(tableView.frameOfCell(atColumn: 0, row: visibleRows.upperBound - 1),
                                                       to: nil)
            let rectInWindowCoords = rectInWindowCoords1.union(rectInWindowCoords2)
            let rect = window.convertToScreen(rectInWindowCoords)
            NSAnimationEffect.poof.show(centeredAt: NSPoint(x: rect.minX + tableView.bounds.width / 2.0, y: rect.midY),
                                        size: NSSize.zero)
        }
        undoable {
            schema.dataProvider.delete(indexes)
        }
        tableView.removeRows(at: indexes, withAnimation: .slideUp)
    }

    // MARK: - Actions

    @objc
    func handleSegmentedControl(_ sender: Any) {
        switch (sender as! NSSegmentedControl).selectedSegment {
        case 0:
            add()
        case 1:
            removeSelected()
        default:
            break
        }
    }

    func competentTableViewDeleteSelectedRows(_ sender: CompetentTableView) {
        if sender.selectedRowIndexes.isEmpty {
            return
        }
        removeSelected()
    }

    @objc
    func handleDoubleClick(_ sender: Any) {
        delegate?.crudDoubleClick(self, row: tableView.clickedRow, column: tableView.clickedColumn)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return schema.dataProvider.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateEnabled()
        delegate?.crudTableSelectionDidChange(self, selectedRows: tableView.selectedRowIndexes)
    }

    // MARK: -- NSTableViewDataSource

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else {
            return nil
        }
        let crudRow = schema.dataProvider[row]
        guard let columnIndex = tableView.tableColumns.firstIndex(of: tableColumn) else {
            return nil
        }
        switch crudRow.format(column: columnIndex) {
        case .string(let stringValue):
            let cell = tableView.newTableCellViewWithTextField(usingIdentifier: tableColumn.identifier.rawValue,
                                                               font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                                                               string: stringValue)
            cell.textField?.stringValue = stringValue
            return cell
        }
    }
}

