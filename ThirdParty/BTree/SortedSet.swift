//
//  SortedSet.swift
//  BTree
//
//  Created by Károly Lőrentey on 2016-02-25.
//  Copyright © 2016–2017 Károly Lőrentey.
//

/// A sorted collection of unique comparable elements.
/// `SortedSet` is like `Set` in the standard library, but it always keeps its elements in ascending order.
/// Lookup, insertion and removal of any element has logarithmic complexity.
///
/// `SortedSet` is a struct with copy-on-write value semantics, like Swift's standard collection types.
/// It uses an in-memory b-tree for element storage, whose individual nodes may be shared with other sorted sets.
/// Mutating a set whose storage is (partially or completely) shared requires copying of only O(log(`count`)) elements.
/// (Thus, mutation of shared `SortedSet`s may be cheaper than ordinary `Set`s, which need to copy all elements.)
///
/// Set operations on sorted sets (such as taking the union, intersection or difference) can take as little as
/// O(log(n)) time if the elements in the input sets aren't too interleaved.
///
/// - SeeAlso: `SortedBag`
public struct SortedSet<Element: Comparable>: SetAlgebra {
    internal typealias Tree = BTree<Element, Void>

    /// The b-tree that serves as storage.
    internal fileprivate(set) var tree: Tree

    fileprivate init(_ tree: Tree) {
        self.tree = tree
    }
}

extension SortedSet {
    //MARK: Initializers

    /// Create an empty set.
    public init() {
        self.tree = Tree()
    }

    /// Create a set from a finite sequence of items. The sequence need not be sorted.
    /// If the sequence contains duplicate items, only the last instance will be kept in the set.
    ///
    /// - Complexity: O(*n* * log(*n*)), where *n* is the number of items in the sequence.
    public init<S: Sequence>(_ elements: S) where S.Element == Element {
        self.init(Tree(sortedElements: elements.sorted().lazy.map { ($0, ()) }, dropDuplicates: true))
    }

    /// Create a set from a sorted finite sequence of items.
    /// If the sequence contains duplicate items, only the last instance will be kept in the set.
    ///
    /// - Complexity: O(*n*), where *n* is the number of items in the sequence.
    public init<S: Sequence>(sortedElements elements: S) where S.Element == Element {
        self.init(Tree(sortedElements: elements.lazy.map { ($0, ()) }, dropDuplicates: true))
    }

    /// Create a set with the specified list of items.
    /// If the array literal contains duplicate items, only the last instance will be kept.
    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }
}

extension SortedSet: BidirectionalCollection {
    //MARK: CollectionType

    public typealias Index = BTreeIndex<Element, Void>
    public typealias Iterator = BTreeKeyIterator<Element>
    public typealias SubSequence = SortedSet<Element>

    /// The index of the first element when non-empty. Otherwise the same as `endIndex`.
    ///
    /// - Complexity: O(log(`count`))
    public var startIndex: Index {
        return tree.startIndex
    }

    /// The "past-the-end" element index; the successor of the last valid subscript argument.
    ///
    /// - Complexity: O(1)
    public var endIndex: Index {
        return tree.endIndex
    }

    /// The number of elements in this set.
    public var count: Int {
        return tree.count
    }

    /// True iff this collection has no elements.
    public var isEmpty: Bool {
        return count == 0
    }

    /// Returns the element at the given index.
    ///
    /// - Requires: `index` originated from an unmutated copy of this set.
    /// - Complexity: O(1)
    public subscript(index: Index) -> Element {
        return tree[index].0
    }

    /// Return the subset consisting of elements in the given range of indexes.
    ///
    /// - Requires: The indices in `range` originated from an unmutated copy of this set.
    /// - Complexity: O(log(`count`))
    public subscript(range: Range<Index>) -> SortedSet<Element> {
        return SortedSet(tree[range])
    }

    /// Return an iterator over all elements in this map, in ascending key order.
    public func makeIterator() -> Iterator {
        return Iterator(tree.makeIterator())
    }

    /// Returns the successor of the given index.
    ///
    /// - Requires: `index` is a valid index of this set and it is not equal to `endIndex`.
    /// - Complexity: Amortized O(1).
    public func index(after index: Index) -> Index {
        return tree.index(after: index)
    }

    /// Replaces the given index with its successor.
    ///
    /// - Requires: `index` is a valid index of this set and it is not equal to `endIndex`.
    /// - Complexity: Amortized O(1).
    public func formIndex(after index: inout Index) {
        tree.formIndex(after: &index)
    }

    /// Returns the predecessor of the given index.
    ///
    /// - Requires: `index` is a valid index of this set and it is not equal to `startIndex`.
    /// - Complexity: Amortized O(1).
    public func index(before index: Index) -> Index {
        return tree.index(before: index)
    }

    /// Replaces the given index with its predecessor.
    ///
    /// - Requires: `index` is a valid index of this set and it is not equal to `startIndex`.
    /// - Complexity: Amortized O(1).
    public func formIndex(before index: inout Index) {
        tree.formIndex(before: &index)
    }

    /// Returns an index that is at the specified distance from the given index.
    ///
    /// - Requires: `index` must be a valid index of this set.
    ///              If `n` is positive, it must not exceed the distance from `index` to `endIndex`.
    ///              If `n` is negative, it must not be less than the distance from `index` to `startIndex`.
    /// - Complexity: O(log(*count*)) where *count* is the number of elements in the set.
    public func index(_ i: Index, offsetBy n: Int) -> Index {
        return tree.index(i, offsetBy: n)
    }

    /// Offsets the given index by the specified distance.
    ///
    /// - Requires: `index` must be a valid index of this set.
    ///              If `n` is positive, it must not exceed the distance from `index` to `endIndex`.
    ///              If `n` is negative, it must not be less than the distance from `index` to `startIndex`.
    /// - Complexity: O(log(*count*)) where *count* is the number of elements in the set.
    public func formIndex(_ i: inout Index, offsetBy n: Int) {
        tree.formIndex(&i, offsetBy: n)
    }

    /// Returns an index that is at the specified distance from the given index, unless that distance is beyond a given limiting index.
    ///
    /// - Requires: `index` and `limit` must be valid indices in this set. The operation must not advance the index beyond `endIndex` or before `startIndex`.
    /// - Complexity: O(log(*count*)) where *count* is the number of elements in the set.
    public func index(_ i: Index, offsetBy n: Int, limitedBy limit: Index) -> Index? {
        return tree.index(i, offsetBy: n, limitedBy: limit)
    }

    /// Offsets the given index by the specified distance, or so that it equals the given limiting index.
    ///
    /// - Requires: `index` and `limit` must be valid indices in this set. The operation must not advance the index beyond `endIndex` or before `startIndex`.
    /// - Complexity: O(log(*count*)) where *count* is the number of elements in the set.
    @discardableResult
    public func formIndex(_ i: inout Index, offsetBy n: Int, limitedBy limit: Index) -> Bool {
        return tree.formIndex(&i, offsetBy: n, limitedBy: limit)
    }

    /// Returns the distance between two indices.
    ///
    /// - Requires: `start` and `end` must be valid indices in this set.
    /// - Complexity: O(1)
    public func distance(from start: Index, to end: Index) -> Int {
        return tree.distance(from: start, to: end)
    }
}

extension SortedSet {
    //MARK: Offset-based access

    /// Return the offset of `member`, if it is an element of this set. Otherwise, return `nil`.
    ///
    /// - Complexity: O(log(`count`))
    public func offset(of member: Element) -> Int? {
        return tree.offset(forKey: member)
    }

    /// Returns the offset of the element at `index`.
    ///
    /// - Complexity: O(log(`count`))
    public func index(ofOffset offset: Int) -> Index {
        return tree.index(ofOffset: offset)
    }

    /// Returns the index of the element at `offset`.
    ///
    /// - Requires: `offset >= 0 && offset < count`
    /// - Complexity: O(log(`count`))
    public func offset(of index: Index) -> Int {
        return tree.offset(of: index)
    }
    
    /// Returns the element at `offset` from the start of the set.
    ///
    /// - Complexity: O(log(`count`))
    public subscript(offset: Int) -> Element {
        return tree.element(atOffset: offset).0
    }

    /// Returns the subset containing elements in the specified range of offsets from the start of the set.
    ///
    /// - Complexity: O(log(`count`))
    public subscript(offsetRange: Range<Int>) -> SortedSet<Element> {
        return SortedSet(tree.subtree(withOffsets: offsetRange))
    }
}

extension SortedSet {
    //MARK: Algorithms

    /// Call `body` on each element in `self` in ascending order.
    public func forEach(_ body: (Element) throws -> Void) rethrows {
        return try tree.forEach { try body($0.0) }
    }

    /// Return an `Array` containing the results of mapping transform over `self`.
    public func map<T>(_ transform: (Element) throws -> T) rethrows -> [T] {
        return try tree.map { try transform($0.0) }
    }

    /// Return an `Array` containing the concatenated results of mapping `transform` over `self`.
    public func flatMap<S : Sequence>(_ transform: (Element) throws -> S) rethrows -> [S.Element] {
        return try tree.flatMap { try transform($0.0) }
    }

    /// Return an `Array` containing the non-`nil` results of mapping `transform` over `self`.
    public func flatMap<T>(_ transform: (Element) throws -> T?) rethrows -> [T] {
        return try tree.flatMap { try transform($0.0) }
    }

    /// Return an `Array` containing the elements of `self`, in ascending order, that satisfy the predicate `includeElement`.
    public func filter(_ includeElement: (Element) throws -> Bool) rethrows -> [Element] {
        var result: [Element] = []
        try tree.forEach { e -> () in
            if try includeElement(e.0) {
                result.append(e.0)
            }
        }
        return result
    }

    /// Return the result of repeatedly calling `combine` with an accumulated value initialized to `initial`
    /// and each element of `self`, in turn.
    /// I.e., return `combine(combine(...combine(combine(initial, self[0]), self[1]),...self[count-2]), self[count-1])`.
    public func reduce<T>(_ initialResult: T, _ nextPartialResult: (T, Element) throws -> T) rethrows -> T {
        return try tree.reduce(initialResult) { try nextPartialResult($0, $1.0) }
    }
}

extension SortedSet {
    //MARK: Extractions

    /// Return the smallest element in the set, or `nil` if the set is empty.
    ///
    /// - Complexity: O(log(`count`))
    public var first: Element? { return tree.first?.0 }

    /// Return the largest element in the set, or `nil` if the set is empty.
    ///
    /// - Complexity: O(log(`count`))
    public var last: Element? { return tree.last?.0 }

    /// Return the smallest element in the set, or `nil` if the set is empty.
    ///
    /// - Complexity: O(log(`count`))
    public func min() -> Element? { return first }

    /// Return the largest element in the set, or `nil` if the set is empty.
    ///
    /// - Complexity: O(log(`count`))
    public func max() -> Element? { return last }

    /// Return a copy of this set with the smallest element removed.
    /// If this set is empty, the result is an empty set.
    ///
    /// - Complexity: O(log(`count`))
    public func dropFirst() -> SortedSet {
        return SortedSet(tree.dropFirst())
    }

    /// Return a copy of this set with the `n` smallest elements removed.
    /// If `n` exceeds the number of elements in the set, the result is an empty set.
    ///
    /// - Complexity: O(log(`count`))
    public func dropFirst(_ n: Int) -> SortedSet {
        return SortedSet(tree.dropFirst(n))
    }

    /// Return a copy of this set with the largest element removed.
    /// If this set is empty, the result is an empty set.
    ///
    /// - Complexity: O(log(`count`))
    public func dropLast() -> SortedSet {
        return SortedSet(tree.dropLast())
    }

    /// Return a copy of this set with the `n` largest elements removed.
    /// If `n` exceeds the number of elements in the set, the result is an empty set.
    ///
    /// - Complexity: O(log(`count`))
    public func dropLast(_ n: Int) -> SortedSet {
        return SortedSet(tree.dropLast(n))
    }

    /// Returns a subset, up to `maxLength` in size, containing the smallest elements in this set.
    ///
    /// If `maxLength` exceeds the number of elements, the result contains all the elements of `self`.
    ///
    /// - Complexity: O(log(`count`))
    public func prefix(_  maxLength: Int) -> SortedSet {
        return SortedSet(tree.prefix(maxLength))
    }

    /// Returns a subset containing all members of this set at or before the specified index.
    ///
    /// - Complexity: O(log(`count`))
    public func prefix(through index: Index) -> SortedSet {
        return SortedSet(tree.prefix(through: index))
    }

    /// Returns a subset containing all members of this set less than or equal to the specified element
    /// (which may or may not be a member of this set).
    ///
    /// - Complexity: O(log(`count`))
    public func prefix(through element: Element) -> SortedSet {
        return SortedSet(tree.prefix(through: element))
    }

    /// Returns a subset containing all members of this set before the specified index.
    ///
    /// - Complexity: O(log(`count`))
    public func prefix(upTo end: Index) -> SortedSet {
        return SortedSet(tree.prefix(upTo: end))
    }

    /// Returns a subset containing all members of this set less than the specified element
    /// (which may or may not be a member of this set).
    ///
    /// - Complexity: O(log(`count`))
    public func prefix(upTo end: Element) -> SortedSet {
        return SortedSet(tree.prefix(upTo: end))
    }

    /// Returns a subset, up to `maxLength` in size, containing the largest elements in this set.
    ///
    /// If `maxLength` exceeds `self.count`, the result contains all the elements of `self`.
    ///
    /// - Complexity: O(log(`count`))
    public func suffix(_ maxLength: Int) -> SortedSet {
        return SortedSet(tree.suffix(maxLength))
    }

    /// Returns a subset containing all members of this set at or after the specified index.
    ///
    /// - Complexity: O(log(`count`))
    public func suffix(from index: Index) -> SortedSet {
        return SortedSet(tree.suffix(from: index))
    }

    /// Returns a subset containing all members of this set greater than or equal to the specified element
    /// (which may or may not be a member of this set).
    ///
    /// - Complexity: O(log(`count`))
    public func suffix(from element: Element) -> SortedSet {
        return SortedSet(tree.suffix(from: element))
    }
}

extension SortedSet: CustomStringConvertible, CustomDebugStringConvertible {
    //MARK: Conversion to string

    /// A textual representation of this set.
    public var description: String {
        let contents = self.map { String(reflecting: $0) }
        return "[" + contents.joined(separator: ", ") + "]"
    }

    /// A textual representation of this set, suitable for debugging.
    public var debugDescription: String {
        return "SortedSet(" + description + ")"
    }
}

extension SortedSet {
    //MARK: Queries

    /// Return true if the set contains `element`.
    ///
    /// - Complexity: O(log(`count`))
    public func contains(_ element: Element) -> Bool {
        return tree.value(of: element) != nil
    }

    /// Returns the index of a given member, or `nil` if the member is not present in the set.
    ///
    /// - Complexity: O(log(`count`))
    public func index(of member: Element) -> BTreeIndex<Element, Void>? {
        return tree.index(forKey: member)
    }

    /// Returns the index of the lowest member of this set that is strictly greater than `element`, or `nil` if there is no such element.
    ///
    /// This function never returns `endIndex`. (If it returns non-nil, the returned index can be used to subscript the set.)
    ///
    /// - Complexity: O(log(`count`))
    public func indexOfFirstElement(after element: Element) -> BTreeIndex<Element, Void>? {
        let index = tree.index(forInserting: element, at: .last)
        if tree.offset(of: index) == tree.count { return nil }
        return index
    }

    /// Returns the index of the lowest member of this set that is greater than or equal to `element`, or `nil` if there is no such element.
    ///
    /// This function never returns `endIndex`. (If it returns non-nil, the returned index can be used to subscript the set.)
    ///
    /// - Complexity: O(log(`count`))
    public func indexOfFirstElement(notBefore element: Element) -> BTreeIndex<Element, Void>? {
        let index = tree.index(forInserting: element, at: .first)
        if tree.offset(of: index) == tree.count { return nil }
        return index
    }

    /// Returns the index of the highest member of this set that is strictly less than `element`, or `nil` if there is no such element.
    ///
    /// This function never returns `endIndex`. (If it returns non-nil, the returned index can be used to subscript the set.)
    ///
    /// - Complexity: O(log(`count`))
    public func indexOfLastElement(before element: Element) -> BTreeIndex<Element, Void>? {
        var index = tree.index(forInserting: element, at: .first)
        if tree.offset(of: index) == 0 { return nil }
        tree.formIndex(before: &index)
        return index
    }

    /// Returns the index of the highest member of this set that is less than or equal to `element`, or `nil` if there is no such element.
    ///
    /// This function never returns `endIndex`. (If it returns non-nil, the returned index can be used to subscript the set.)
    ///
    /// - Complexity: O(log(`count`))
    public func indexOfLastElement(notAfter element: Element) -> BTreeIndex<Element, Void>? {
        var index = tree.index(forInserting: element, at: .last)
        if tree.offset(of: index) == 0 { return nil }
        tree.formIndex(before: &index)
        return index
    }
}

extension SortedSet {
    //MARK: Set comparions

    /// Return `true` iff `self` and `other` contain the same elements.
    ///
    /// This method skips over shared subtrees when possible; this can drastically improve performance when the
    /// two sets are divergent mutations originating from the same value.
    ///
    /// - Complexity:  O(`count`)
    public func elementsEqual(_ other: SortedSet<Element>) -> Bool {
        return self.tree.elementsEqual(other.tree, by: { $0.0 == $1.0 })
    }

    /// Returns `true` iff `a` contains the same elements as `b`.
    ///
    /// This function skips over shared subtrees when possible; this can drastically improve performance when the
    /// two sets are divergent mutations originating from the same value.
    ///
    /// - Complexity: O(`count`)
    public static func ==(a: SortedSet<Element>, b: SortedSet<Element>) -> Bool {
        return a.elementsEqual(b)
    }

    /// Returns `true` iff no members in this set are also included in `other`.
    ///
    /// The elements of the two input sets may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input sets will be simply
    /// linked into the result instead of copying, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func isDisjoint(with other: SortedSet<Element>) -> Bool {
        return tree.isDisjoint(with: other.tree)
    }

    /// Returns `true` iff all members in this set are also included in `other`.
    ///
    /// The elements of the two input sets may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input sets will be simply
    /// linked into the result instead of copying, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func isSubset(of other: SortedSet<Element>) -> Bool {
        return tree.isSubset(of: other.tree, by: .groupingMatches)
    }

    /// Returns `true` iff all members in this set are also included in `other`, but the two sets aren't equal.
    ///
    /// The elements of the two input sets may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input sets may be skipped instead
    /// of elementwise processing, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func isStrictSubset(of other: SortedSet<Element>) -> Bool {
        return tree.isStrictSubset(of: other.tree, by: .groupingMatches)
    }

    /// Returns `true` iff all members in `other` are also included in this set.
    ///
    /// The elements of the two input sets may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input sets may be skipped instead
    /// of elementwise processing, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func isSuperset(of other: SortedSet<Element>) -> Bool {
        return tree.isSuperset(of: other.tree, by: .groupingMatches)
    }

    /// Returns `true` iff all members in `other` are also included in this set, but the two sets aren't equal.
    ///
    /// The elements of the two input sets may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input sets may be skipped instead
    /// of elementwise processing, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func isStrictSuperset(of other: SortedSet<Element>) -> Bool {
        return tree.isStrictSuperset(of: other.tree, by: .groupingMatches)
    }
}

extension SortedSet {
    //MARK: Insertion

    /// Insert a member into the set if it is not already present.
    ///
    /// - Returns: `(true, newMember)` if `newMember` was not contained in the set.
    ///    If an element equal to `newMember` was already contained in the set, the method returns `(false, oldMember)`,
    ///    where `oldMember` is the element that was equal to `newMember`. In some cases, `oldMember` may be distinguishable
    ///    from `newMember` by identity comparison or some other means.
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func insert(_ newMember: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        guard let old = tree.insertOrFind((newMember, ())) else {
            return (true, newMember)
        }
        return (false, old.0)
    }

    /// Inserts the given element into the set unconditionally.
    ///
    /// If an element equal to `newMember` is already contained in the set,
    /// `newMember` replaces the existing element.
    ///
    /// - Parameter newMember: An element to insert into the set.
    /// - Returns: The element equal to `newMember` that was originally in the set, if exists; otherwise, `nil`.
    ///   In some cases, the returned element may be distinguishable from `newMember` by identity
    ///   comparison or some other means.
    @discardableResult
    public mutating func update(with newMember: Element) -> Element? {
        return tree.insertOrReplace((newMember, ()))?.0
    }
}

extension SortedSet {
    //MARK: Removal

    /// Remove the member from the set and return it if it was present.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func remove(_ element: Element) -> Element? {
        return tree.remove(element)?.0
    }

    /// Remove the member referenced by the given index.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func remove(at index: Index) -> Element {
        return tree.remove(at: index).0
    }

    /// Remove the member at the given offset.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func remove(atOffset offset: Int) -> Element {
        return tree.remove(atOffset: offset).0
    }


    /// Remove and return the smallest member in this set.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    mutating func removeFirst() -> Element {
        return tree.removeFirst().0
    }

    /// Remove the smallest `n` members from this set.
    ///
    /// - Complexity: O(log(`count`))
    mutating func removeFirst(_ n: Int) {
        tree.removeFirst(n)
    }

    /// Remove and return the smallest member in this set, or return `nil` if the set is empty.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func popFirst() -> Element? {
        return tree.popFirst()?.0
    }

    /// Remove and return the largest member in this set.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    mutating func removeLast() -> Element {
        return tree.removeLast().0
    }

    /// Remove the largest `n` members from this set.
    ///
    /// - Complexity: O(log(`count`))
    mutating func removeLast(_ n: Int) {
        tree.removeLast(n)
    }

    /// Remove and return the largest member in this set, or return `nil` if the set is empty.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func popLast() -> Element? {
        return tree.popLast()?.0
    }

    /// Remove all members from this set.
    public mutating func removeAll() {
        tree.removeAll()
    }
}

extension SortedSet {
    //MARK: Sorting

    /// Return an `Array` containing the members of this set, in ascending order.
    ///
    /// `SortedSet` already keeps its elements sorted, so this is equivalent to `Array(self)`.
    ///
    /// - Complexity: O(`count`)
    public func sorted() -> [Element] {
        // The set is already sorted.
        return Array(self)
    }
}

extension SortedSet {
    //MARK: Set operations

    /// Return a set containing all members in both this set and `other`.
    ///
    /// The elements of the two input sets may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input sets will be simply
    /// linked into the result instead of copying, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func union(_ other: SortedSet<Element>) -> SortedSet<Element> {
        return SortedSet(self.tree.union(other.tree, by: .groupingMatches))
    }

    /// Return a set consisting of all members in `other` that are also in this set.
    ///
    /// The elements of the two input sets may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input sets will be simply
    /// linked into the result instead of copying, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func intersection(_ other: SortedSet<Element>) -> SortedSet<Element> {
        return SortedSet(self.tree.intersection(other.tree, by: .groupingMatches))
    }

    /// Return a set consisting of members from `self` and `other` that aren't in both sets at once.
    ///
    /// The elements of the two input sets may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input sets will be simply
    /// linked into the result instead of copying, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func symmetricDifference(_ other: SortedSet<Element>) -> SortedSet<Element> {
        return SortedSet(self.tree.symmetricDifference(other.tree, by: .groupingMatches))
    }

    /// Add all members in `other` to this set.
    ///
    /// The elements of the two input sets may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input sets will be simply
    /// linked into the result instead of copying, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public mutating func formUnion(_ other: SortedSet<Element>) {
        self = self.union(other)
    }

    /// Remove all members from this set that are not included in `other`.
    ///
    /// The elements of the two input sets may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input sets will be simply
    /// linked into the result instead of copying, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public mutating func formIntersection(_ other: SortedSet<Element>) {
        self = other.intersection(self)
    }

    /// Replace `self` with a set consisting of members from `self` and `other` that aren't in both sets at once.
    ///
    /// The elements of the two input sets may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input sets will be simply
    /// linked into the result instead of copying, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public mutating func formSymmetricDifference(_ other: SortedSet<Element>) {
        self = self.symmetricDifference(other)
    }

    /// Return a set containing those members of this set that aren't also included in `other`.
    ///
    /// The elements of the two input sets may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input sets will be simply
    /// linked into the result instead of copying, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func subtracting(_ other: SortedSet) -> SortedSet {
        return SortedSet(self.tree.subtracting(other.tree, by: .groupingMatches))
    }

    /// Remove all members from this set that are also included in `other`.
    ///
    /// The elements of the two input sets may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input sets will be simply
    /// linked into the result instead of copying, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public mutating func subtract(_ other: SortedSet) {
        self = self.subtracting(other)
    }
}

extension SortedSet {
    //MARK: Interactions with ranges

    /// Return the count of elements in this set that are in `range`.
    ///
    /// - Complexity: O(log(`self.count`))
    public func count(elementsIn range: Range<Element>) -> Int {
        var path = BTreeStrongPath(root: tree.root, key: range.lowerBound, choosing: .first)
        let lowerOffset = path.offset
        path.move(to: range.upperBound, choosing: .first)
        return path.offset - lowerOffset
    }

    /// Return the count of elements in this set that are in `range`.
    ///
    /// - Complexity: O(log(`self.count`))
    public func count(elementsIn range: ClosedRange<Element>) -> Int {
        var path = BTreeStrongPath(root: tree.root, key: range.lowerBound, choosing: .first)
        let lowerOffset = path.offset
        path.move(to: range.upperBound, choosing: .after)
        return path.offset - lowerOffset
    }

    /// Return a set consisting of all members in `self` that are also in `range`.
    ///
    /// - Complexity: O(log(`self.count`))
    public func intersection(elementsIn range: Range<Element>) -> SortedSet<Element> {
        return self.suffix(from: range.lowerBound).prefix(upTo: range.upperBound)
    }

    /// Return a set consisting of all members in `self` that are also in `range`.
    ///
    /// - Complexity: O(log(`self.count`))
    public func intersection(elementsIn range: ClosedRange<Element>) -> SortedSet<Element> {
        return self.suffix(from: range.lowerBound).prefix(through: range.upperBound)
    }

    /// Remove all members from this set that are not included in `range`.
    ///
    /// - Complexity: O(log(`self.count`))
    public mutating func formIntersection(elementsIn range: Range<Element>) {
        self = self.intersection(elementsIn: range)
    }

    /// Remove all members from this set that are not included in `range`.
    ///
    /// - Complexity: O(log(`self.count`))
    public mutating func formIntersection(elementsIn range: ClosedRange<Element>) {
        self = self.intersection(elementsIn: range)
    }

    /// Remove all elements in `range` from this set.
    ///
    /// - Complexity: O(log(`self.count`))
    public mutating func subtract(elementsIn range: Range<Element>) {
        tree.withCursor(onKey: range.upperBound, choosing: .first) { cursor in
            let upperOffset = cursor.offset
            cursor.move(to: range.lowerBound, choosing: .first)
            cursor.remove(upperOffset - cursor.offset)
        }
    }

    /// Remove all elements in `range` from this set.
    ///
    /// - Complexity: O(log(`self.count`))
    public mutating func subtract(elementsIn range: ClosedRange<Element>) {
        tree.withCursor(onKey: range.upperBound, choosing: .after) { cursor in
            let upperOffset = cursor.offset
            cursor.move(to: range.lowerBound, choosing: .first)
            cursor.remove(upperOffset - cursor.offset)
        }
    }

    /// Return a set containing those members of this set that aren't also included in `range`.
    ///
    /// - Complexity: O(log(`self.count`))
    public mutating func subtracting(elementsIn range: Range<Element>) -> SortedSet<Element> {
        var copy = self
        copy.subtract(elementsIn: range)
        return copy
    }

    /// Return a set containing those members of this set that aren't also included in `range`.
    ///
    /// - Complexity: O(log(`self.count`))
    public mutating func subtracting(elementsIn range: ClosedRange<Element>) -> SortedSet<Element> {
        var copy = self
        copy.subtract(elementsIn: range)
        return copy
    }
}

extension SortedSet where Element: Strideable {
    //MARK: Shifting

    /// Shift the value of all elements starting at `start` by `delta`.
    /// For a positive `delta`, this shifts elements to the right, creating an empty gap in `start ..< start + delta`.
    /// For a negative `delta`, this shifts elements to the left, removing any elements in the range `start + delta ..< start` that were previously in the set.
    ///
    /// - Complexity: O(`self.count`). The elements are modified in place.
    public mutating func shift(startingAt start: Element, by delta: Element.Stride) {
        guard delta != 0 else { return }
        tree.withCursor(onKey: start) { cursor in
            if delta < 0 {
                let offset = cursor.offset
                cursor.move(to: start.advanced(by: delta))
                cursor.remove(offset - cursor.offset)
            }
            while !cursor.isAtEnd {
                cursor.key = cursor.key.advanced(by: delta)
                cursor.moveForward()
            }
        }
    }
}
