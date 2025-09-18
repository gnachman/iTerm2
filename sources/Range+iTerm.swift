//
//  Range+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 10/22/24.
//

extension ClosedRange where Bound: Strideable, Bound.Stride: SignedInteger {
    init?(_ range: Range<Bound>) {
        guard !range.isEmpty, range.upperBound > range.lowerBound else {
            return nil
        }
        let inclusiveUpperBound = range.upperBound.advanced(by: -1)
        guard inclusiveUpperBound >= range.lowerBound else {
            return nil
        }
        self = range.lowerBound...inclusiveUpperBound
    }

    func clamping(_ value: Bound) -> Bound {
        return Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}

extension Range where Bound == Int {
    func intersection(_ other: Range<Int>) -> Range<Int>? {
        let lower = Swift.max(self.lowerBound, other.lowerBound)
        let upper = Swift.min(self.upperBound, other.upperBound)
        return lower < upper ? lower..<upper : nil
    }

    func contains(range: Range<Bound>) -> Bool {
        return lowerBound <= range.lowerBound && upperBound >= range.upperBound
    }
}

extension Range where Bound: Comparable {
     func contains(_ other: Range<Bound>) -> Bool {
        lowerBound <= other.lowerBound &&
        upperBound >= other.upperBound
    }
}

extension NSRange {
    func contains(_ other: Range<Int>) -> Bool {
        return lowerBound <= other.lowerBound && upperBound >= other.upperBound
    }

    func contains(_ other: NSRange) -> Bool {
        return lowerBound <= other.lowerBound && upperBound >= other.upperBound
    }
}
