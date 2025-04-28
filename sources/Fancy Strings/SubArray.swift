//
//  SubArray.swift
//  iTerm2
//
//  Created by George Nachman on 4/28/25.
//

/// This exists because ArraySlice is fucking stupid and doesn't get a start index of 0.
struct SubArray<Element>: RandomAccessCollection {
    private let base: [Element]
    private let bounds: Range<Int>

    /// - Parameters:
    ///   - base: the full array
    ///   - bounds: the subrange of `base` you wish to expose; must be a valid subrange.
    init(_ base: [Element], bounds: Range<Int>) {
        precondition(base.indices.contains(bounds.lowerBound)
                  && base.indices.contains(bounds.upperBound - 1),
                     "bounds out of range")
        self.base = base
        self.bounds = bounds
    }

    init(_ array: [Element]) {
        base = array
        bounds = 0..<base.count
    }

    /// Returns a zero-based slice of this SubArray.
    subscript(range: Range<Int>) -> SubArray<Element> {
        precondition(range.lowerBound >= 0 && range.upperBound <= count,
                     "SubArray range out of bounds: \(range)")
        let newLower = bounds.lowerBound + range.lowerBound
        let newUpper = bounds.lowerBound + range.upperBound
        return SubArray(base, bounds: newLower..<newUpper)
    }

    // MARK: RandomAccessCollection

    /// Always starts at zero
    var startIndex: Int { 0 }

    /// Always ends at count
    var endIndex: Int {
        bounds.count
    }

    /// Access by zero-based position
    subscript(position: Int) -> Element {
        it_assert(indices.contains(position), "Index \(position) out of bounds \(bounds)")
        return base[bounds.lowerBound + position]
    }

    /// Forward index
    func index(after i: Int) -> Int {
        i + 1
    }

    /// Backward index (from RandomAccessCollection)
    func index(before i: Int) -> Int {
        i - 1
    }
}

extension SubArray {
    /// Number of elements in the slice
    var count: Int { bounds.count }
}

extension SubArray: Equatable where Element: Equatable {
}
