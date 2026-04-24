//
//  RangeMap.swift
//  iTerm2
//
//  Created by George Nachman on 5/28/25.
//

struct RangeMap<Value>: Sequence {
    struct Entry {
        var range: Range<Int>
        var value: Value
    }

    private var entries: [Entry] = []
    var first: Entry? { entries.first }
    var last: Entry? { entries.last }

    var count: Int { entries.count }

    mutating func insert(range: Range<Int>, value: Value) {
        let newEntry = Entry(range: range, value: value)
        let insertionIndex = entries.binarySearch { $0.range.lowerBound < range.lowerBound }
        entries.insert(newEntry, at: insertionIndex)
    }

    subscript(_ key: Int) -> Entry? {
        let foundIndex = entries.binarySearch { $0.range.upperBound <= key }
        guard foundIndex != entries.endIndex, entries[foundIndex].range.contains(key) else {
            return nil
        }
        return entries[foundIndex]
    }

    func makeIterator() -> AnyIterator<Entry> {
        return AnyIterator<Entry>(entries.makeIterator())
    }

    func iterate(from key: Int) -> AnyIterator<Entry> {
        let start = entries.binarySearch { $0.range.lowerBound < key }
        return AnyIterator(entries[start...].makeIterator())
    }

    func reverseIterate(from key: Int) -> AnyIterator<Entry> {
        let start = entries.binarySearch { $0.range.upperBound <= key }
        var currentIndex = start
        return AnyIterator {
            guard currentIndex >= self.entries.startIndex else {
                return nil
            }
            defer { currentIndex = self.entries.index(before: currentIndex) }
            return self.entries[currentIndex]
        }
    }
}

extension RandomAccessCollection {
    func binarySearch(predicate: (Element) -> Bool) -> Index {
        var low = startIndex
        var high = endIndex
        while low != high {
            let mid = index(low, offsetBy: distance(from: low, to: high)/2)
            if predicate(self[mid]) {
                low = index(after: mid)
            } else {
                high = mid
            }
        }
        return low
    }
}
