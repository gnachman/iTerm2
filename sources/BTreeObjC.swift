//
//  BTreeObjC.swift
//  iTerm2
//
//  Created by George Nachman on 6/24/24.
//

import Cocoa

extension ComparableNSObject: Comparable {
    public static func < (lhs: ComparableNSObject, rhs: ComparableNSObject) -> Bool {
        return lhs.compare(rhs) == ComparisonResult.orderedAscending
    }
}

@objc
class iTermTypeErasedSortedBag: NSObject {
    private var items = SortedBag<ComparableNSObject>()
    private var _fastEnumerationStorage: UInt = 0
    @objc var count: Int { items.count }

    @objc(removeObjectsAtIndexes:)
    func remove(at indexes: IndexSet) {
        for index in indexes.reversed() {
            items.remove(at: items.index(ofOffset: index))
        }
    }

    @objc(containsObject:)
    func contains(object: ComparableNSObject) -> Bool {
        return items.contains(object)
    }

    @objc(firstIndexOfObject:comparator:)
    func firstIndex(of element: ComparableNSObject,
                    comparator: (ComparableNSObject, ComparableNSObject) -> Bool) -> Int {
        let i = arbitraryInsertionIndex(of: element, comparator: comparator)
        if i == count {
            return NSNotFound
        }
        if items[i] != element {
            return NSNotFound
        }
        return i;
    }

    // Comparator returns lhs < rhs
    @objc(arbitraryInsertionIndexOfObject:comparator:)
    func arbitraryInsertionIndex(of element: ComparableNSObject,
                                 comparator: (ComparableNSObject, ComparableNSObject) -> Bool) -> Int {
        var low = 0
        var high = count

        while low != high {
            let mid = low + (high - low) / 2
            if comparator(items[mid], element) {
                low = mid + 1
            } else {
                high = mid
            }
        }

        return low
    }

    // If element is already present, returns the index of the first instance. Otherwise, returns
    // the insertion index.
    @objc(firstInsertionIndexOfObject:comparator:)
    func firstInsertionIndex(of element: ComparableNSObject,
                             comparator: (ComparableNSObject, ComparableNSObject) -> Bool) -> Int {
        var low = arbitraryInsertionIndex(of: element, comparator: comparator)

        while low > 0 && items[low] == items[low - 1] {
            low -= 1
        }
        return low
    }

    // If element is already present, returns the index of the last instance. Otherwise, returns
    // the insertion index.
    @objc(lastInsertionIndexOfObject:comparator:)
    func lastInsertionIndex(of element: ComparableNSObject,
                            comparator: (ComparableNSObject, ComparableNSObject) -> Bool) -> Int {
        var low = arbitraryInsertionIndex(of: element, comparator: comparator)
        while low + 1 < count && items[low] == items[low + 1] {
            low += 1
        }
        return low
    }

    @objc(insertObject:)
    func insert(element: ComparableNSObject) {
        items.insert(element)
    }

    @objc subscript(_ i: Int) -> ComparableNSObject {
        return items[i]
    }

    @objc
    func removeAllObjects() {
        items.removeAll()
    }

    @objc(removeObjectsInRange:)
    func remove(in range: NSRange) {
        if let range = Range(range) {
            remove(at: IndexSet(integersIn: range))
        }
    }

    @objc
    func array() -> [ComparableNSObject] {
        return items.sorted()
    }

    @objc(lastObject) var last: ComparableNSObject? { items.last }
    @objc(firstObject) var first: ComparableNSObject? { items.first }
}


