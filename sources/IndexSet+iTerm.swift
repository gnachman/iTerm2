//
//  IndexSet+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 10/22/24.
//

extension IndexSet {
    subscript(_ subrange: Range<Int>) -> IndexSet {
        return self.intersection(IndexSet(integersIn: subrange))
    }

    init(ranges: [Range<Int>]) {
        self.init()
        for range in ranges {
            insert(integersIn: range)
        }
    }

    mutating func removeFirst() -> Element? {
        if let value = first {
            remove(value)
            return value
        }
        return nil
    }

    var enumeratedDescription: String {
        map { String($0) }.joined(separator: ", ")
    }
}

extension IndexSet {
    /// A sequence of (range, isMember) over `domain`, clipped to `domain`.
    func membership(in domain: Range<Int>) -> AnySequence<(Range<Int>, Bool)> {
        return AnySequence {
            // 1) Clip runs to only those that intersect `domain`
            var runs = rangeView.lazy
                .filter { $0.overlaps(domain) }
                .map { $0.clamped(to: domain) }
                .makeIterator()

            var cursor = domain.lowerBound
            var pendingRun: Range<Int>? = nil

            return AnyIterator {
                // Emit a pending run if one was deferred
                if let run = pendingRun {
                    pendingRun = nil
                    cursor = run.upperBound
                    return (run, true)
                }

                // Pull runs one by one
                while let run = runs.next() {
                    if cursor < run.lowerBound {
                        // Gap before this run
                        let gap = cursor..<run.lowerBound
                        pendingRun = run
                        cursor = run.lowerBound
                        return (gap, false)
                    }

                    if cursor < run.upperBound {
                        // Run (or remainder of it) at or after cursor
                        let subrun = cursor..<run.upperBound
                        cursor = run.upperBound
                        return (subrun, true)
                    }

                    // Otherwise run is entirely before cursor, so skip it
                }

                // Trailing gap after all runs
                guard cursor < domain.upperBound else {
                    return nil
                }
                let gap = cursor..<domain.upperBound
                cursor = domain.upperBound
                return (gap, false)
            }
        }
    }
}
