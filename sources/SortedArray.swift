//
//  SortedArray.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/24/23.
//

import Foundation

@objc
protocol iTermSortedArrayReading: AnyObject {
    func findAtOrBefore(location desiredLocation: Int64) -> [NSObject]
}

func s<T>(_ value: Optional<T>) -> String {
    guard let value else {
        return "(nil)"
    }
    if let cdd = value as? CustomDebugStringConvertible {
        return cdd.debugDescription
    }
    if let obj = value as? NSObject {
        return obj.description
    }
    return "\(value)"
}

@objc(iTermSortedArray)
class iTermSortedArray: NSObject, iTermSortedArrayReading {
    private var impl: SortedArray<NSObject>

    override var description: String {
        impl.debugDescription
    }
    @objc(init)
    override init() {
        impl = SortedArray { return NSObject.object($0, isEqualTo: $1) }
        super.init()
    }

    @objc
    func findAtOrBefore(location desiredLocation: Int64) -> [NSObject] {
        return impl.findAtOrBefore(location: desiredLocation)
    }

    @objc
    func insert(object: NSObject, location: Int64) {
        impl.insert(object: object, location: location)
    }

    @objc
    func remove(object: NSObject, location: Int64) {
        impl.remove(entry: .init(value: object, location: location))
    }

    @objc
    func removeAll() {
        impl.removeAll()
    }
}

protocol NextProviding {
    mutating func nextItem() -> Any?
}

@objc(iTermSortedArrayEnumerator)
class iTermSortedArrayEnumerator: NSEnumerator {
    private var nextProvider: NextProviding

    init(nextProvider: NextProviding) {
        self.nextProvider = nextProvider
    }

    override func nextObject() -> Any? {
        return nextProvider.nextItem()
    }
}

// Holds an array of objects in sorted order.
class SortedArray<T>: CustomDebugStringConvertible {
    var debugDescription: String {
        return "<SortedArray count=\(s(count)) first=\(s(first))@\(s(firstLocation)) last=\(s(last))@\(s(lastLocation))"
    }
    struct Entry {
        var value: T
        var location: Int64
    }
    private var array: [Entry] = []

    // Compares two values for equality.
    private var equals: (T, T) -> Bool
    var count: Int { array.count }
    var isEmpty: Bool { count == 0 }
    var first: T? { array.first?.value }
    var firstLocation: Int64? { array.first?.location }
    var lastLocation: Int64? { array.last?.location }
    var last: T? { array.last?.value }

    init(equals: @escaping (T, T) -> Bool) {
        self.equals = equals
    }

    func removeAll() {
        array = []
    }

    private func firstIndexAtOrBefore(location desiredLocation: Int64) -> Int? {
        var start = 0
        var end = array.count - 1
        var mid = -1
        var index = -1

        while start <= end {
            mid = (start + end) / 2
            let midLocation = array[mid].location
            if midLocation > desiredLocation {
                end = mid - 1
            } else {
                // Found it
                start = mid + 1
                index = mid
            }
        }
        if index < 0 {
            return nil
        }
        // Go backward to the first with this location
        let l = array[index].location
        while index > 0 && index < array.count && array[index - 1].location == l {
            index -= 1
        }
        return index
    }

    private func firstIndexBefore(location desiredLocation: Int64) -> Int? {
        var start = 0
        var end = array.count - 1
        var mid = -1
        var index = -1

        while start <= end {
            mid = (start + end) / 2
            let midLocation = array[mid].location
            if midLocation >= desiredLocation {
                end = mid - 1
            } else {
                // Found it
                start = mid + 1
                index = mid
            }
        }
        if index < 0 {
            return nil
        }
        // Go backward to the first with this location
        let l = array[index].location
        while index > 0 && index < array.count && array[index - 1].location == l {
            index -= 1
        }
        return index
    }

    private func firstIndexAtOrAfter(location desiredLocation: Int64) -> Int? {
        var start = 0
        var end = array.count - 1
        var mid = -1
        var index = -1

        while start <= end {
            mid = (start + end) / 2
            let midLocation = array[mid].location
            if midLocation < desiredLocation {
                start = mid + 1
            } else {
                // Found it
                end = mid - 1
                index = mid
            }
        }
        if index < 0 {
            return nil
        }
        // Go backward to the first with this location
        let l = array[index].location
        while index > 0 && index < array.count && array[index - 1].location == l {
            index -= 1
        }
        return index
    }

    struct ForwardIterator: IteratorProtocol, NextProviding {
        private let array: [Entry]
        private var currentIndex: Int

        init(array: [Entry], currentIndex: Int) {
            self.array = array
            self.currentIndex = currentIndex
        }

        mutating func next() -> T? {
            guard currentIndex < array.count else {
                return nil
            }
            defer {
                currentIndex += 1
            }
            return array[currentIndex].value
        }

        mutating func nextItem() -> Any? {
            return next()
        }
    }

    func itemsFrom(location startLocation: Int64) -> ForwardIterator {
        let startIndex = firstIndexAtOrAfter(location: startLocation) ?? array.count
        return ForwardIterator(array: array, currentIndex: startIndex)
    }

    func findAtOrBefore(location desiredLocation: Int64) -> [T] {
        if var index = firstIndexAtOrBefore(location: desiredLocation) {
            // Add all until we get past the desired location
            var result = [T]()
            while index < array.count && array[index].location <= desiredLocation {
                result.append(array[index].value)
                index += 1
            }
            return result
        } else {
            return []
        }
    }

    func findBefore(location desiredLocation: Int64) -> [T] {
        if var index = firstIndexBefore(location: desiredLocation) {
            // Add all until we get past the desired location
            var result = [T]()
            while index < array.count && array[index].location < desiredLocation {
                result.append(array[index].value)
                index += 1
            }
            return result
        } else {
            return []
        }
    }

    func removeUpTo(location: Int64) {
        let firstIndexToKeep = (0..<array.count).first { i in
            let l = array[i].location
            return l > location
        }
        guard let firstIndexToKeep else {
            array = []
            return
        }
        array.removeSubrange(0..<firstIndexToKeep)
    }

    func insert(object: T, location: Int64) {
        if let last = array.last, location >= last.location {
            // Optimized path for append
            array.append(Entry(value: object, location: location))
            return
        }
        var start = 0
        var end = array.count
        var mid: Int

        while start < end {
            mid = (start + end) / 2
            let midLocation = array[mid].location
            if midLocation < location {
                start = mid + 1
            } else {
                end = mid
            }
        }
        array.insert(Entry(value: object, location: location), at: start)
    }

    func remove(entries: [Entry]) {
        array.remove(at: indexes(entries: entries))
    }

    private func indexes(entries: [Entry]) -> IndexSet {
        guard !isEmpty else {
            return IndexSet()
        }
        let sortedEntries = entries.sorted { lhs, rhs in
            lhs.location < rhs.location
        }
        guard let entry = sortedEntries.first else {
            return IndexSet()
        }
        let firstLocation = entry.location
        // i is an index into array which will increase monotonically as we search for sortedEntries[tupleIndex].
        guard var i = firstIndexAtOrAfter(location: firstLocation) else {
            return IndexSet()
        }
        var indexesToRemove = IndexSet()
        // tupleIndex is an index into sortedEntries which increases monotonically.
        var entryIndex = 0
        var linearSearchCount = 0
        let maximumLinearSearchIterations = 7
        while i < array.count && entryIndex < sortedEntries.count {
            // Check if we can remove array[i] to eliminate the object at desiredSortedLocations[tupleIndex]
            let desiredEntry = sortedEntries[entryIndex]
            // currentObject is what we're considering removing.
            let currentEntry = array[i]
            let currentLocation = currentEntry.location
            if currentLocation > desiredEntry.location {
                // Failed to find the desired object.
                entryIndex += 1
                continue
            } 
            if currentLocation == desiredEntry.location {
                // Search all entries with this location until we find the one for this object.
                var temp = i
                var found = false
                while temp < array.count && array[temp].location == currentLocation {
                    if equals(array[temp].value, desiredEntry.value) {
                        found = true
                        break
                    }
                    temp += 1
                }
                if found {
                    indexesToRemove.insert(temp)
                    if temp == i {
                        i += 1
                    }
                }
                entryIndex += 1
                linearSearchCount = 0
                continue
            }
            it_assert(currentLocation < desiredEntry.location)
            if linearSearchCount > maximumLinearSearchIterations {
                // Give up and do a binary search.
                guard let nextIndex = firstIndexAtOrAfter(location: desiredEntry.location) else {
                    break
                }
                i = nextIndex
                linearSearchCount = 0
                continue
            }

            // Linear search forwards.
            i += 1
            linearSearchCount += 1
        }
        return indexesToRemove
    }

    func remove(entry: Entry) {
        let desiredLocation = entry.location
        if var i = firstIndexAtOrBefore(location: desiredLocation) {
            if let first = array.first, first.location > desiredLocation {
                // Optimization for trying to remove one before the first.
                return
            }
            while i < array.count {
                defer {
                    i += 1
                }
                let l = array[i].location
                if l > desiredLocation {
                    return
                }
                if l == desiredLocation && equals(array[i].value, entry.value) {
                    array.remove(at: i)
                    return
                }
            }
        }
    }
}
