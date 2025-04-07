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

extension Range where Bound == Int64 {
    /// Creates a Range<Int64> from an NSRange.
    /// If the NSRange’s bounds exceed Int64 limits, the upper bound is clamped to Int64.max.
    init(safe nsRange: NSRange) {
        // Clamp the NSRange’s location and length to Int64’s representable values.
        let lower = Int64(clamping: nsRange.location)
        let length = Int64(clamping: nsRange.length)
        // Use reportingOverflow to detect if the intended upper bound overflows.
        let (upper, overflow) = lower.addingReportingOverflow(length)
        // If there was overflow, use Int64.max; otherwise, use the computed upper bound.
        self = lower ..< (overflow ? Int64.max : upper)
    }
}
