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
