//
//  iTermMutableOrderedSet.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/27/24.
//

import Cocoa

// The purpose of these classes is to expose SortedSet<T> to Objective C.
// I wish generics worked better with ObjC interop!
@objc
class iTermMutableOrderedSetImpl: NSObject {
    private struct Element: Comparable {
        var object: NSObject
        var compare: (NSObject, NSObject) -> ComparisonResult

        static func < (lhs: iTermMutableOrderedSetImpl.Element,
                       rhs: iTermMutableOrderedSetImpl.Element) -> Bool {
            return lhs.compare(lhs.object, rhs.object) == .orderedAscending
        }
        static func == (lhs: iTermMutableOrderedSetImpl.Element, rhs: iTermMutableOrderedSetImpl.Element) -> Bool {
            return lhs.compare(lhs.object, rhs.object) == .orderedSame
        }
    }
    private var sortedSet = SortedSet<Element>()
    @objc private(set) var compare: (NSObject, NSObject) -> ComparisonResult

    @objc(initWithComparator:)
    public init(compare: @escaping (NSObject, NSObject) -> ComparisonResult) {
        self.compare = compare
    }

    @objc public var count: Int {
        sortedSet.count
    }

    @objc(removeObjectAtIndex:)
    public func remove(at index: Int) {
        sortedSet.remove(at: sortedSet.index(sortedSet.startIndex, offsetBy: index))
    }

    @objc(containsObject:) public func contains(object: NSObject) -> Bool {
        return sortedSet.contains(Element(object: object, compare: compare))
    }

    // Returns true if it was added, false if it was already there.
    @discardableResult
    @objc(insertObject:) public func insert(object: NSObject) -> Bool {
        return sortedSet.insert(Element(object: object, compare: compare)).0
    }

    @objc subscript(_ i: Int) -> NSObject {
        return sortedSet[i].object
    }

    @objc var array: [NSObject] {
        return sortedSet.map { $0.object }
    }
}

@objc
extension iTermMutableOrderedSetImpl: NSFastEnumeration {
    func countByEnumerating(
        with state: UnsafeMutablePointer<NSFastEnumerationState>,
        objects buffer: AutoreleasingUnsafeMutablePointer<AnyObject?>,
        count len: Int) -> Int {
            withUnsafeMutablePointer(to: &state.pointee.extra.0) { ptr in
                state.pointee.mutationsPtr = ptr
            }
            state.pointee.itemsPtr = buffer
            if state.pointee.state < sortedSet.count && len > 0 {
                let i = state.pointee.state
                buffer.pointee = sortedSet[Int(i)].object
                state.pointee.state += 1
                return 1
            }
            return 0
        }
}
