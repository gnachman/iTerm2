//
//  VT100Screen+FoldForTesting.swift
//  ModernTests
//
//  Created by George Nachman on 11/5/26.
//

import Foundation
@testable import iTerm2SharedARC

extension VT100Screen {
    /// Main queue. Folds the lines in `range` of absolute lines on the mutation thread, leaving the
    /// first as the placeholder. Leaves copy mode first, as mutateAsynchronously(_:) does.
    func foldAbsLineRange(_ range: NSRange) {
        mutateAsynchronously { _, mutableState, _ in
            mutableState.foldAbsLineRange(range)
        }
    }
}
