//
//  SubStringCache.swift
//  StyleMap
//
//  Created by George Nachman on 4/18/25.
//

/// A size‑1 cache of the last (range→DeltaString) mapping.
struct SubStringCache {
    private var lastRange: NSRange?
    private var lastString: DeltaString?

    mutating func string(for range: NSRange, compute: () -> DeltaString) -> DeltaString {
        if let r = lastRange, r == range, let s = lastString {
            return s
        }
        let s = compute()
        lastRange = range
        lastString = s
        return s
    }

    mutating func clear() {
        lastRange = nil
        lastString = nil
    }

    mutating func invalidate(range: Range<Int>) {
        guard let lastRange, let lhs = Range(lastRange) else {
            return
        }

        if lhs.overlaps(range) {
            clear()
        }
    }
}

