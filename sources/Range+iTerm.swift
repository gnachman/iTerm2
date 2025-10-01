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

extension Range where Bound == Int64 {
    // Safely convert NSRange to Range<Int64>, validating that the conversion won't overflow
    // or produce an invalid range. NSRange uses NSUInteger (UInt64) for both location and length.
    // When negative signed integers are cast to NSUInteger, they wrap to huge positive values.
    // This can cause Range.init(_: NSRange) to overflow or create invalid ranges where
    // lowerBound > upperBound.
    init?(safe nsrange: NSRange) {
        // Check for NSNotFound sentinel value
        guard nsrange.location != NSNotFound,
              nsrange.length != NSNotFound else {
            return nil
        }

        // Check if location fits in Int64
        guard nsrange.location <= Int64.max,
              let location = Int64(exactly: nsrange.location) else {
            return nil
        }

        // Check if length fits in Int64
        guard nsrange.length <= Int64.max,
              let length = Int64(exactly: nsrange.length) else {
            return nil
        }

        // Check that location + length doesn't overflow
        let (upperBound, overflow) = location.addingReportingOverflow(length)
        guard !overflow, upperBound >= location else {
            return nil
        }

        self = location..<upperBound
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
