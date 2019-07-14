//
//  TableViewController.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/7/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Cocoa

@objc(BFPTableViewControllerDelegate)
protocol TableViewControllerDelegate: NSObjectProtocol {
    func tableViewController(_ tableViewController: TableViewController,
                             didSelectFontWithName name: String)
    func tableViewControllerDataSources(_ tableViewController: TableViewController) -> [FontListDataSource]
}

@objc(BFPTableViewController)
public class TableViewController: NSViewController, FavoritesDataSourceDelegate, FontListTableViewDelegate, NSTableViewDataSource, NSTableViewDelegate, RecentsDataSourceDelegate {
    weak var delegate: TableViewControllerDelegate?
    private var systemFontDataSources: [FontListDataSource] = [SystemFontsDataSource()]
    private(set) var selectedName: String? = nil

    private let starColumnIdentifier = NSUserInterfaceItemIdentifier("star")
    private let checkmarkColumnIdentifier = NSUserInterfaceItemIdentifier("checkmark")
    private let fontnameColumnIdentifier = NSUserInterfaceItemIdentifier("fontname")
    private let tableView: NSTableView
    private let favorites = FavoritesDataSource()
    private let recents = RecentsDataSource()
    private let fixedPitch = SystemFontsDataSource(filter: .fixedPitch)
    private let variablePitch = SystemFontsDataSource(filter: .variablePitch)
    private var dirty = true
    private var internalDataSources: [FontListDataSource] = []
    private var dataSources: [FontListDataSource] {
        if dirty {
            dirty = false
            if let updatedDataSources = delegate?.tableViewControllerDataSources(self) {
                systemFontDataSources = updatedDataSources
            }
            let possibleDataSources: [FontListDataSource] = [ favorites, recents ] + systemFontDataSources
            for dataSource in possibleDataSources {
                dataSource.filter = internalFilter
            }
            internalDataSources = possibleDataSources.filter { (dataSource) -> Bool in
                return dataSource.names.count > 0
            }
            if internalDataSources.count < 2 {
                return internalDataSources
            }
            let penultimateIndex = internalDataSources.count - 1
            for index in stride(from: penultimateIndex, to: 0, by: -1) {
                internalDataSources.insert(SeparatorDataSource(), at: index)
            }
        }
        return internalDataSources
    }
    private var typicalHeight: CGFloat? = nil
    private var internalFilter: String = ""
    var filter: String {
        get {
            return internalFilter
        }
        set {
            if newValue != internalFilter {
                dirty = true
            }
            internalFilter = newValue
            tableView.reloadData()
        }
    }

    // MARK:- Initializers

    init(tableView: FontListTableView, delegate: TableViewControllerDelegate?) {
        self.tableView = tableView
        self.delegate = delegate

        super.init(nibName: nil, bundle: nil)

        favorites.delegate = self
        recents.delegate = self

        tableView.intercellSpacing = NSSize(width: 0, height: tableView.intercellSpacing.height)
        tableView.backgroundColor = NSColor.clear
        tableView.fontListDelegate = self
        let scrollView = tableView.enclosingScrollView!
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false

        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                                               object: scrollView,
                                               queue: nil) { [weak self] (notification) in
                                                self?.layOutTableView()
        }
        NotificationCenter.default.addObserver(forName: NSFont.fontSetChangedNotification,
                                               object: nil,
                                               queue: nil) { [weak self] (notification) in
                                                self?.fontSetDidChange()
        }
        layOutTableView()

        typicalHeight = newFontNameCell("X").fittingSize.height + 2
        tableView.delegate = self
        tableView.dataSource = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func fontSetDidChange() {
        for dataSource in dataSources {
            dataSource.reload()
        }
        tableView.reloadData()
    }

    // MARK:- Layout

    private func desiredTableViewFrame() -> CGRect {
        guard let scrollView = tableView.enclosingScrollView else {
            return tableView.frame
        }
        var frame = tableView.frame
        frame.size.width = scrollView.frame.size.width
        return frame
    }

    private func layOutTableView() {
        let frame = desiredTableViewFrame()
        tableView.frame = frame
        let starWidth = CGFloat(StarTableViewCell.width)
        let checkmarkWidth = starWidth - 10
        let desiredWidths = [
            starColumnIdentifier: starWidth,
            checkmarkColumnIdentifier: checkmarkWidth,
            fontnameColumnIdentifier: frame.size.width - starWidth - checkmarkWidth
        ]
        for (identifier, width) in desiredWidths {
            if let column = tableView.tableColumn(withIdentifier: identifier) {
                if identifier == starColumnIdentifier || identifier == checkmarkColumnIdentifier {
                    column.minWidth = width
                    column.maxWidth = width
                }
                column.width = width
            }
        }
    }

    @objc(viewDidLayout)
    public override func viewDidLayout() {
        layOutTableView()
        super.viewDidLayout()
    }

    // MARK:- API

    func select(name: String?) {
        guard let name = name else {
            if let oldName = selectedName {
                deselect(oldName)
            }
            return
        }

        recents.makeRecent(name)

        tableView.beginUpdates()
        var indexSet = IndexSet()
        let rows = rowsWithName(name)
        for row in rows {
            indexSet.insert(row)
        }
        if let selectedName = selectedName {
            let previousRows = rowsWithName(selectedName)
            for row in previousRows {
                indexSet.insert(row)
            }
        }
        selectedName = name // dataSource.names[index]
        tableView.reloadData(forRowIndexes: indexSet,
                             columnIndexes: IndexSet(integer: 0))
        tableView.endUpdates()

        delegate?.tableViewController(self, didSelectFontWithName: name)
    }

    func invalidateDataSources() {
        dirty = true
    }

    // MARK:- Model

    private func dataSourceForRow(_ row: Int) -> (FontListDataSource, Int)? {
        var i = 0;
        var offset = 0;
        for dataSource in dataSources {
            if dataSource.isSeparator {
                i += 1
            } else {
                assert(dataSource.names.count > 0)
                i += dataSource.names.count
            }
            if row < i {
                return (dataSource, row - offset)
            }
            offset = i
        }
        return nil
    }

    private func rowsWithName(_ name: String) -> [Int] {
        var result: [Int] = []
        var offset = 0
        for dataSource in dataSources {
            if dataSource.isSeparator {
                offset += 1
                continue
            }
            if let i = dataSource.names.firstIndex(of: name) {
                result.append(offset + i)
            }
            offset += dataSource.names.count
        }
        return result
    }

    private func nameForRow(_ row: Int) -> String? {
        guard let (dataSource, index) = dataSourceForRow(row) else {
            return nil
        }
        return dataSource.names[index]
    }

    private func firstRowForDataSource(_ target: FontListDataSource) -> Int? {
        var i = 0
        for dataSource in dataSources {
            if dataSource === target {
                return i
            }
            if dataSource.isSeparator {
                i += 1
            } else {
                i += dataSource.names.count
            }
        }
        return nil
    }

    private func deselect(_ oldName: String) {
        selectedName = nil
        let rows = rowsWithName(oldName)
        tableView.beginUpdates()
        var indexSet = IndexSet()
        for row in rows {
            indexSet.insert(row)
        }
        tableView.reloadData(forRowIndexes: indexSet,
                             columnIndexes: IndexSet(integer: 0))
    }

    // MARK:- Cell Creation

    private func newFontNameCell(_ value: String) -> NSTextField {
        let identifier = NSUserInterfaceItemIdentifier("FontNameTableViewCellIdentifier")
        if let textField = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            textField.font = NSFont(name: value, size: 12)
            textField.stringValue = value
            return textField
        }
        let textField: NSTextField = NSTextField()
        textField.textColor = NSColor.labelColor
        textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textField.isBezeled = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.drawsBackground = false
        textField.usesSingleLineMode = true
        textField.identifier = identifier
        textField.font = NSFont(name: value, size: 12)
        textField.stringValue = value
        textField.lineBreakMode = .byTruncatingTail
        return textField
    }

    private func newSeparatorCell() -> SeparatorTableViewCell {
        let identifier = NSUserInterfaceItemIdentifier("SeparatorTableViewCellIdentifier")
        if let separator = tableView.makeView(withIdentifier: identifier, owner: self) as? SeparatorTableViewCell {
            return separator
        }
        let separator = SeparatorTableViewCell()
        separator.identifier = identifier
        return separator
    }

    private func newStarCell(_ selected: Bool) -> StarTableViewCell {
        let identifier = NSUserInterfaceItemIdentifier("StarTableViewCellIdentifier")
        if let view = tableView.makeView(withIdentifier: identifier, owner: self) as? StarTableViewCell {
            view.selected = selected
            return view
        }
        let view = StarTableViewCell()
        view.selected = selected
        view.identifier = identifier
        return view
    }

    private func newCheckMarkCell(_ checked: Bool) -> NSTextField {
        let identifier = NSUserInterfaceItemIdentifier("FontNameTableViewCellIdentifier")
        if let textField = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            textField.stringValue = "✓"
            textField.alignment = .right
            return textField
        }
        let textField: NSTextField = NSTextField()
        textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textField.isBezeled = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.drawsBackground = false
        textField.usesSingleLineMode = true
        textField.identifier = identifier
        textField.stringValue = "✓"
        return textField
    }

    // MARK:- NSTableViewDataSource

    @objc(numberOfRowsInTableView:)
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return dataSources.map({ (dataSource) -> Int in
            if dataSource.isSeparator {
                return 1
            } else {
                return dataSource.names.count
            }
        }).reduce(0, { (sum, value) -> Int in
            return sum + value
        })
    }

    @objc(tableView:rowViewForRow:)
    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard let (dataSource, _) = dataSourceForRow(row) else {
            return nil
        }
        if dataSource.isSeparator {
            return newSeparatorCell()
        }
        return nil
    }

    @objc(tableView:viewForTableColumn:row:)
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let (dataSource, index) = dataSourceForRow(row) else {
            return nil
        }
        if (dataSource.isSeparator) {
            return nil
        }
        let name = dataSource.names[index]
        if let identifier = tableColumn?.identifier {
            if identifier == starColumnIdentifier {
                return newStarCell(favorites.names.contains(name))
            }
            if identifier == checkmarkColumnIdentifier {
                let cell = newCheckMarkCell(false)
                cell.isHidden = (selectedName != name)
                return cell
            }
        }

        return newFontNameCell(dataSource.names[index])
    }

    @objc(tableView:heightOfRow:)
    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let (dataSource, _) = dataSourceForRow(row) else {
            assert(false)
            return 0
        }
        if dataSource.isSeparator {
            return SeparatorTableViewCell.height
        }
        return typicalHeight!
    }

    @objc(tableView:shouldSelectRow:)
    public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard let (dataSource, _) = dataSourceForRow(row) else {
            assert(false)
            return false
        }
        return !dataSource.isSeparator
    }

    // MARK:- NSTableViewDelegate

    @objc(tableViewSelectionDidChange:)
    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        if row < 0 {
            return
        }
        tableView.deselectAll(nil)
        guard let (dataSource, _) = dataSourceForRow(row) else {
            return
        }
        guard (!dataSource.isSeparator) else {
            return
        }
        guard let name = nameForRow(row) else {
            return
        }

        select(name: name)
    }

    // MARK:- FontListTableViewDelegate

    func fontListTableView(_ fontListTableView: FontListTableView,
                           didToggleFavoriteForRow row: Int) {
        if let name = nameForRow(row) {
            favorites.toggleFavorite(name)
            var indexSet = IndexSet()
            for row in rowsWithName(name) {
                indexSet.insert(row)
            }
            tableView.beginUpdates()
            tableView.reloadData(forRowIndexes: indexSet,
                                 columnIndexes: IndexSet(integer: 2))
            tableView.endUpdates()
        }
    }

    // MARK:- FavoritesDataSourceDelegate
    func favoritesDataSource(_ dataSource: FavoritesDataSource,
                             didInsertRowAtIndex index: Int) {
        tableView.beginUpdates()
        var indexSet = IndexSet()
        if favorites.names.count == 1 {
            dirty = true
            // Insert row for the separator
            indexSet.insert(firstRowForDataSource(favorites)! + 1)
        }
        indexSet.insert(firstRowForDataSource(favorites)! + index)
        tableView.insertRows(at: indexSet, withAnimation: .slideDown)
        reloadFixedVariableAndRecentsWithName(favorites.names[index])
        tableView.endUpdates()
    }

    private func reloadFixedVariableAndRecentsWithName(_ name: String) {
        if let fixedPitchIndex = fixedPitch.names.firstIndex(of: name), let offset = firstRowForDataSource(fixedPitch) {
            tableView.reloadData(forRowIndexes: IndexSet(integer: fixedPitchIndex + offset),
                                 columnIndexes: IndexSet(integer: 2))
        }
        if let variablePitchIndex = variablePitch.names.firstIndex(of: name), let offset = firstRowForDataSource(variablePitch) {
            tableView.reloadData(forRowIndexes: IndexSet(integer: variablePitchIndex + offset),
                                 columnIndexes: IndexSet(integer: 2))
        }
        if let recentsIndex = variablePitch.names.firstIndex(of: name), let offset = firstRowForDataSource(recents) {
            tableView.reloadData(forRowIndexes: IndexSet(integer: recentsIndex + offset),
                                 columnIndexes: IndexSet(integer: 2))
        }
    }

    func favoritesDataSource(_ dataSource: FavoritesDataSource,
                             didDeleteRowAtIndex index: Int,
                             name: String) {
        tableView.beginUpdates()
        var indexSet = IndexSet()
        let firstRow = firstRowForDataSource(favorites)!
        indexSet.insert(firstRow + index)
        if favorites.names.count == 0 {
            indexSet.insert(firstRow + 1)
            dirty = true
        }
        tableView.removeRows(at: indexSet, withAnimation: .slideUp)
        reloadFixedVariableAndRecentsWithName(name)
        tableView.endUpdates()
    }

    // MARK:- RecentsDataSourceDelegate

    func recentsDataSourceDidChange(_ dataSource: RecentsDataSource,
                                    netAdditions: Int) {
        tableView.beginUpdates()
        if netAdditions == 0 {
            recentsDidChangeInPlace()
        } else if netAdditions == 1 {
            recentsDidAddRow()
        } else {
            assert(netAdditions == -1)
            recentsDidDeleteRow()
        }
        tableView.endUpdates()
    }

    private func recentsDidChangeInPlace() {
        let firstRow = firstRowForDataSource(recents)!
        tableView.reloadData(forRowIndexes: IndexSet(integersIn: firstRow..<(firstRow + recents.names.count)),
                             columnIndexes: IndexSet(integersIn: 0..<3))
    }

    private func recentsDidAddRow() {
        var indexSet = IndexSet()
        if recents.names.count == 1 {
            dirty = true
            // Insert row for separator
            indexSet.insert(firstRowForDataSource(recents)! + 1)
        }
        let firstRow = firstRowForDataSource(recents)!
        indexSet.insert(firstRow + recents.names.count - 1)

        // Insert the row and separator, if added.
        tableView.insertRows(at: indexSet, withAnimation: .slideDown)

        // Reload the other rows because everything shifts.
        tableView.reloadData(forRowIndexes: IndexSet(integersIn: firstRow..<(firstRow + recents.names.count)),
                             columnIndexes: IndexSet(integersIn: 0..<3))
    }

    private func recentsDidDeleteRow() {
        var indexSet = IndexSet()
        let firstRow = firstRowForDataSource(recents)!
        if recents.names.count == 0 {
            dirty = true
            indexSet.insert(firstRow)
            indexSet.insert(firstRow + 1)
        } else {
            indexSet.insert(firstRow)
        }
        tableView.removeRows(at: indexSet,
                             withAnimation: .slideUp)

        // Reload the other rows because everything may have shifted
        tableView.reloadData(forRowIndexes: IndexSet(integersIn: firstRow..<(firstRow + recents.names.count + 1)),
                             columnIndexes: IndexSet(integersIn: 0..<3))
    }
}
