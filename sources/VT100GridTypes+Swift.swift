//
//  VT100GridTypes+Swift.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/27/24.
//

import Foundation

extension VT100GridAbsCoordRange {
    var width: Int32 {
        max(0, end.x - start.x)
    }
    var height: Int32 {
        Int32(clamping: max(0, end.y - start.y + 1))
    }
}
