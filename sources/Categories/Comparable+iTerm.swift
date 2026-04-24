//
//  Comparable+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/7/26.
//

import Foundation

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
