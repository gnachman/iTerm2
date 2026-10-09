//
//  NSTableView+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 3/25/25.
//

@objc
extension NSTableView {
    @objc(it_moveRowsFromSourceIndexes:toRowsBeginningAtIndex:)
    func moveRows(sourceIndexes: IndexSet, destinationIndex: Int) {
        beginUpdates()
        let sorted = sourceIndexes.sorted()
        let count = sorted.count

        // If moving upward, the destinationIndex is where the first moved row ends up.
        if let first = sorted.first, destinationIndex <= first {
            for (offset, originalIndex) in sorted.enumerated() {
                moveRow(at: originalIndex, to: destinationIndex + offset)
            }
        }
        else {
            // For downward moves, we interpret destinationIndex as the final index for the
            // first moved row. We calculate how many moving rows occur before destinationIndex.
            let countBefore = sorted.filter { $0 < destinationIndex }.count
            // When the moving rows are removed, the reduced array’s insertion index would be:
            let effectiveDestination = destinationIndex - countBefore
            // To have the block appear so that its first element lands at destinationIndex,
            // we process in descending order using an offset of countBefore.
            for (j, originalIndex) in sorted.reversed().enumerated() {
                // The desired final positions for the moving block are:
                //   first moved row: destinationIndex
                //   second: destinationIndex + 1, etc.
                // In the reduced array these correspond to indices
                //   effectiveDestination, effectiveDestination+1, …
                // However, since our destinationIndex was defined in the full table,
                // we add back countBefore.
                let target = effectiveDestination + countBefore + (count - 1 - j)
                moveRow(at: originalIndex, to: target)
            }
        }
        endUpdates()
    }
}

extension NSOutlineView {
    // A replacement for -reloadData that doesn't leak.
    //
    // Reloading the whole outline view (-reloadData, or -reloadItem:nil
    // reloadChildren:YES) permanently leaks a disclosure button for every
    // visible expandable row: -[NSOutlineView _makeOutlineControl] registers a
    // notification observer whose block strongly retains the button and is
    // never unregistered. Each stranded button also keeps the observer that
    // -[NSView _commonAwake] adds, so the default notification center grows by
    // two entries per button, and AppKit's teardown of every view in the app
    // gets slower as it grows. See tests/outline-view-disclosure-button-leak.m.
    //
    // The batch update API doesn't leak, so remove every top-level row and
    // insert the data source's current ones, then restore expansion,
    // selection, and the scroll position. This differs from -reloadData in a
    // few ways:
    //
    // - Expansion is restored by matching items with isEqual:, so items that
    //   the data source recreates on each reload must implement it. An
    //   expanded item under a collapsed parent stays expanded, where
    //   -reloadData forgets it.
    // - Selection follows the selected items, where -reloadData keeps the row
    //   indexes even when rows above them came or went. If none of the
    //   selected items can be found, as when items are recreated without
    //   isEqual:, it falls back to keeping the row indexes, as -reloadData does.
    // - The delegate hears about the restoration: it gets
    //   outlineViewSelectionDidChange: and outlineViewItemDidExpand:, which
    //   -reloadData doesn't send.
    @objc(it_reloadDataWithoutLeaking)
    func reloadDataWithoutLeaking() {
        var expandedItems = Set<AnyHashable>()
        var selectedItems = Set<AnyHashable>()
        let selectedRows = selectedRowIndexes
        // -numberOfChildrenOfItem: asks the data source, which may already
        // describe the new model, so count the rows the view has.
        var oldCount = 0
        for row in 0..<numberOfRows {
            if level(forRow: row) == 0 {
                oldCount += 1
            }
            guard let item = item(atRow: row) as? AnyHashable else {
                continue
            }
            if isItemExpanded(item) {
                expandedItems.insert(item)
            }
            if isRowSelected(row) {
                selectedItems.insert(item)
            }
        }
        let scrollOrigin = enclosingScrollView?.contentView.bounds.origin
        let newCount = dataSource?.outlineView?(self, numberOfChildrenOfItem: nil) ?? 0

        beginUpdates()
        removeItems(at: IndexSet(0..<oldCount), inParent: nil, withAnimation: [])
        insertItems(at: IndexSet(0..<newCount), inParent: nil, withAnimation: [])
        endUpdates()

        // Expanding a row adds its children below it, so walking rows in order
        // reaches nested items after their parents.
        var row = 0
        while row < numberOfRows {
            if let item = item(atRow: row) as? AnyHashable, expandedItems.contains(item) {
                expandItem(item)
            }
            row += 1
        }

        var selection = IndexSet()
        for row in 0..<numberOfRows {
            if let item = item(atRow: row) as? AnyHashable, selectedItems.contains(item) {
                selection.insert(row)
            }
        }
        if selection.isEmpty {
            selection = selectedRows.filteredIndexSet { $0 < numberOfRows }
        }
        selectRowIndexes(selection, byExtendingSelection: false)

        if let scrollOrigin, let clipView = enclosingScrollView?.contentView {
            clipView.setBoundsOrigin(scrollOrigin)
            enclosingScrollView?.reflectScrolledClipView(clipView)
        }
    }

    @objc
    func reloadPreservingExpansionAndScroll() {
        // Record expanded items by uniqueID
        var expandedIDs = Set<String>()
        for row in 0..<numberOfRows {
            if let item = self.item(atRow: row) as? iTermUniquelyIdentifiable,
               isItemExpanded(item) {
                expandedIDs.insert(item.stringUniqueIdentifier())
            }
        }

        // Record selected items by uniqueID
        var selectedIDs = Set<String>()
        for row in selectedRowIndexes {
            if let item = self.item(atRow: row) as? iTermUniquelyIdentifiable {
                selectedIDs.insert(item.stringUniqueIdentifier())
            }
        }

        // Record scroll position
        let scrollOrigin = enclosingScrollView?.contentView.bounds.origin ?? .zero

        reloadDataWithoutLeaking()

        // Recursively re-expand items whose stringUniqueIdentifier() is in the saved set.
        func expandItems(for item: Any?) {
            let count = dataSource?.outlineView?(self, numberOfChildrenOfItem: item) ?? 0
            for index in 0..<count {
                if let child = dataSource?.outlineView?(self, child: index, ofItem: item) as? iTermUniquelyIdentifiable {
                    if expandedIDs.contains(child.stringUniqueIdentifier()) {
                        expandItem(child)
                        expandItems(for: child)
                    }
                }
            }
        }
        expandItems(for: nil)

        // Restore scroll position
        if let clipView = enclosingScrollView?.contentView {
            clipView.setBoundsOrigin(scrollOrigin)
            enclosingScrollView?.reflectScrolledClipView(clipView)
        }

        // Restore selection by mapping stringUniqueIdentifier()s back to row indexes
        var newSelection = IndexSet()
        for row in 0..<numberOfRows {
            if let item = self.item(atRow: row) as? iTermUniquelyIdentifiable,
               selectedIDs.contains(item.stringUniqueIdentifier()) {
                newSelection.insert(row)
            }
        }
        selectRowIndexes(newSelection, byExtendingSelection: false)
    }
}
