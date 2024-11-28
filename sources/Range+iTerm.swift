//
//  Range+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 10/22/24.
//

extension ClosedRange where Bound: Strideable, Bound.Stride: SignedInteger {
    init?(_ range: Range<Bound>) {
        if range.isEmpty {
            return nil
        }
        self = range.lowerBound...(range.upperBound.advanced(by: -1))
    }

    func clamping(_ value: Bound) -> Bound {
        return Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
