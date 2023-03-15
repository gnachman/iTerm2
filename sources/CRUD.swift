//
//  CRUD.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/14/23.
//

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
    func crudTableSelectionDidChange(_ sender: CRUDTableViewController,
                                     selectedRows: IndexSet)

    func crudTextFieldDidChange(_ sender: CRUDTableViewController,
                                row: Int,
                                column: Int,
                                newValue: String)

    func crudDoubleClick(_ sender: CRUDTableViewController,
                         row: Int,
                         column: Int)
}

@objc
class CRUDTableViewController: NSObject, NSTableViewDelegate, NSTableViewDataSource {
    private let tableView: NSTableView
    private let addRemove: NSSegmentedControl
    private let schema: CRUDSchema
    weak var delegate: CRUDTableViewControllerDelegate?

    init(tableView: NSTableView, addRemove: NSSegmentedControl, schema: CRUDSchema) {
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
        schema.dataProvider.delete(indexes)
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

