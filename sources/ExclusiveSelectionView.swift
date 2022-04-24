//
//  ExclusiveSelectionView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/22/22.
//

import Foundation

@objc class ExclusiveSelectionView: NSTextView {
    var didAcquireSelection: (() -> ())?
    private var removingSelection = false

    func removeSelection() {
        removingSelection = true
        setSelectedRange(NSRange(location: 0, length: 0))
        removingSelection = false
    }

    override func setSelectedRanges(_ ranges: [NSValue],
                                    affinity: NSSelectionAffinity,
                                    stillSelecting stillSelectingFlag: Bool) {
        if !removingSelection {
            didAcquireSelection?()
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
    }
}

