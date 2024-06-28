//
//  SortedBag.swift
//  BTree
//
//  Created by Károly Lőrentey on 2016-10-11.
//  Copyright © 2016–2017 Károly Lőrentey.
//

/// A sorted collection of comparable elements; also known as a multiset.
/// `SortedBag` is like a `SortedSet` except it can contain multiple members that are equal to each other.
/// Lookup, insertion and removal of any element has logarithmic complexity.
///
/// `SortedBag` stores duplicate elements in their entirety; it doesn't just count multiplicities.
/// This is an important feature when equal elements can be distinguished by identity comparison or some other means.
/// (If you're OK with just counting duplicates, use a `Map` or a `Dictionary` with the multiplicity as the value.)
///
/// `SortedBag` is a struct with copy-on-write value semantics, like Swift's standard collection types.
/// It uses an in-memory b-tree for element storage, whose individual nodes may be shared with other sorted sets or bags.
/// Mutating a bag whose storage is (partially or completely) shared requires copying of only O(log(`count`)) elements.
/// (Thus, mutation of shared `SortedBag`s may be cheaper than ordinary `Set`s, which need to copy all elements.)
///
/// Set operations on sorted bags (such as taking the union, intersection or difference) can take as little as
/// O(log(n)) time if the elements in the input bags aren't too interleaved.
///
/// - SeeAlso: `SortedSet`
public struct SortedBag<Element: Comparable>: SetAlgebra {
    internal typealias Tree = BTree<Element, Void>

    /// The b-tree that serves as storage.
    internal fileprivate(set) var tree: Tree

    fileprivate init(_ tree: Tree) {
        self.tree = tree
    }
}

extension SortedBag {
    //MARK: Initializers

    /// Create an empty bag.
    public init() {
        self.tree = Tree()
    }

    /// Create a bag that holds the same members as the specified sorted set.
    /// 
    /// Complexity: O(1); the new bag simply refers to the same storage as the set.
    public init(_ set: SortedSet<Element>) {
        self.tree = set.tree
    }

    /// Create a bag from a finite sequence of items. The sequence need not be sorted.
    /// If the sequence contains duplicate items, all of them are kept, in the same order.
    ///
    /// - Complexity: O(*n* * log(*n*)), where *n* is the number of items in the sequence.
    public init<S: Sequence>(_ elements: S) where S.Element == Element {
        self.init(Tree(sortedElements: elements.sorted().lazy.map { ($0, ()) }, dropDuplicates: false))
    }

    /// Create a bag from a sorted finite sequence of items.
    /// If the sequence contains duplicate items, all of them are kept.
    ///
    /// - Complexity: O(*n*), where *n* is the number of items in the sequence.
    public init<S: Sequence>(sortedElements elements: S) where S.Element == Element {
        self.init(Tree(sortedElements: elements.lazy.map { ($0, ()) }, dropDuplicates: false))
    }

    /// Create a bag with the specified list of items.
    /// If the array literal contains duplicate items, all of them are kept.
    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }
}

extension SortedBag: BidirectionalCollection {
    //MARK: CollectionType

    public typealias Index = BTreeIndex<Element, Void>
    public typealias Iterator = BTreeKeyIterator<Element>
    public typealias SubSequence = SortedBag<Element>

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

    /// The number of elements in this bag.
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

    /// Return the subbag consisting of elements in the given range of indexes.
    ///
    /// - Requires: The indices in `range` originated from an unmutated copy of this bag.
    /// - Complexity: O(log(`count`))
    public subscript(range: Range<Index>) -> SortedBag<Element> {
        return SortedBag(tree[range])
    }

    /// Return an iterator over all elements in this map, in ascending key order.
    public func makeIterator() -> Iterator {
        return Iterator(tree.makeIterator())
    }

    /// Returns the successor of the given index.
    ///
    /// - Requires: `index` is a valid index of this bag and it is not equal to `endIndex`.
    /// - Complexity: Amortized O(1).
    public func index(after index: Index) -> Index {
        return tree.index(after: index)
    }

    /// Replaces the given index with its successor.
    ///
    /// - Requires: `index` is a valid index of this bag and it is not equal to `endIndex`.
    /// - Complexity: Amortized O(1).
    public func formIndex(after index: inout Index) {
        tree.formIndex(after: &index)
    }

    /// Returns the predecessor of the given index.
    ///
    /// - Requires: `index` is a valid index of this bag and it is not equal to `startIndex`.
    /// - Complexity: Amortized O(1).
    public func index(before index: Index) -> Index {
        return tree.index(before: index)
    }

    /// Replaces the given index with its predecessor.
    ///
    /// - Requires: `index` is a valid index of this bag and it is not equal to `startIndex`.
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
    /// - Complexity: O(log(*count*)) where *count* is the number of elements in the bag.
    public func formIndex(_ i: inout Index, offsetBy n: Int) {
        tree.formIndex(&i, offsetBy: n)
    }

    /// Returns an index that is at the specified distance from the given index, unless that distance is beyond a given limiting index.
    ///
    /// - Requires: `index` and `limit` must be valid indices in this bag. The operation must not advance the index beyond `endIndex` or before `startIndex`.
    /// - Complexity: O(log(*count*)) where *count* is the number of elements in the bag.
    public func index(_ i: Index, offsetBy n: Int, limitedBy limit: Index) -> Index? {
        return tree.index(i, offsetBy: n, limitedBy: limit)
    }

    /// Offsets the given index by the specified distance, or so that it equals the given limiting index.
    ///
    /// - Requires: `index` and `limit` must be valid indices in this bag. The operation must not advance the index beyond `endIndex` or before `startIndex`.
    /// - Complexity: O(log(*count*)) where *count* is the number of elements in the bag.
    @discardableResult
    public func formIndex(_ i: inout Index, offsetBy n: Int, limitedBy limit: Index) -> Bool {
        return tree.formIndex(&i, offsetBy: n, limitedBy: limit)
    }

    /// Returns the distance between two indices.
    ///
    /// - Requires: `start` and `end` must be valid indices in this bag.
    /// - Complexity: O(1)
    public func distance(from start: Index, to end: Index) -> Int {
        return tree.distance(from: start, to: end)
    }
}

extension SortedBag {
    //MARK: Offset-based access

    /// If `member` is in this bag, return the offset of its first instance. Otherwise, return `nil`.
    ///
    /// - Complexity: O(log(`count`))
    public func offset(of member: Element) -> Int? {
        return tree.offset(forKey: member, choosing: .first)
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

    /// Returns the element at `offset` from the start of the bag.
    ///
    /// - Complexity: O(log(`count`))
    public subscript(offset: Int) -> Element {
        return tree.element(atOffset: offset).0
    }

    /// Returns the subbag containing elements in the specified range of offsets from the start of the bag.
    ///
    /// - Complexity: O(log(`count`))
    public subscript(offsetRange: Range<Int>) -> SortedBag<Element> {
        return SortedBag(tree.subtree(withOffsets: offsetRange))
    }
}

extension SortedBag {
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

extension SortedBag {
    //MARK: Extractions

    /// Return (the first instance of) the smallest element in the bag, or `nil` if the bag is empty.
    ///
    /// - Complexity: O(log(`count`))
    public var first: Element? { return tree.first?.0 }

    /// Return (the last instance of) the largest element in the bag, or `nil` if the bag is empty.
    ///
    /// - Complexity: O(log(`count`))
    public var last: Element? { return tree.last?.0 }

    /// Return the smallest element in the bag, or `nil` if the bag is empty. This is the same as `first`.
    ///
    /// - Complexity: O(log(`count`))
    public func min() -> Element? { return first }

    /// Return the largest element in the set, or `nil` if the set is empty. This is the same as `last`.
    ///
    /// - Complexity: O(log(`count`))
    public func max() -> Element? { return last }

    // Return a copy of this bag with the smallest element removed.
    /// If this bag is empty, the result is an empty bag.
    ///
    /// - Complexity: O(log(`count`))
    public func dropFirst() -> SortedBag {
        return SortedBag(tree.dropFirst())
    }

    /// Return a copy of this bag with the `n` smallest elements removed.
    /// If `n` exceeds the number of elements in the bag, the result is an empty bag.
    ///
    /// - Complexity: O(log(`count`))
    public func dropFirst(_ n: Int) -> SortedBag {
        return SortedBag(tree.dropFirst(n))
    }

    /// Return a copy of this bag with the largest element removed.
    /// If this bag is empty, the result is an empty bag.
    ///
    /// - Complexity: O(log(`count`))
    public func dropLast() -> SortedBag {
        return SortedBag(tree.dropLast())
    }

    /// Return a copy of this bag with the `n` largest elements removed.
    /// If `n` exceeds the number of elements in the bag, the result is an empty bag.
    ///
    /// - Complexity: O(log(`count`))
    public func dropLast(_ n: Int) -> SortedBag {
        return SortedBag(tree.dropLast(n))
    }

    /// Returns a subbag, up to `maxLength` in size, containing the smallest elements in this bag.
    ///
    /// If `maxLength` exceeds the number of elements, the result contains all the elements of `self`.
    ///
    /// - Complexity: O(log(`count`))
    public func prefix(_  maxLength: Int) -> SortedBag {
        return SortedBag(tree.prefix(maxLength))
    }

    /// Returns a subbag containing all members of this bag at or before the specified index.
    ///
    /// - Complexity: O(log(`count`))
    public func prefix(through index: Index) -> SortedBag {
        return SortedBag(tree.prefix(through: index))
    }

    /// Returns a subset containing all members of this bag less than or equal to the specified element
    /// (which may or may not be a member of this bag).
    ///
    /// - Complexity: O(log(`count`))
    public func prefix(through element: Element) -> SortedBag {
        return SortedBag(tree.prefix(through: element))
    }

    /// Returns a subbag containing all members of this bag before the specified index.
    ///
    /// - Complexity: O(log(`count`))
    public func prefix(upTo end: Index) -> SortedBag {
        return SortedBag(tree.prefix(upTo: end))
    }

    /// Returns a subbag containing all members of this bag less than the specified element
    /// (which may or may not be a member of this bag).
    ///
    /// - Complexity: O(log(`count`))
    public func prefix(upTo end: Element) -> SortedBag {
        return SortedBag(tree.prefix(upTo: end))
    }

    /// Returns a subbag, up to `maxLength` in size, containing the largest elements in this bag.
    ///
    /// If `maxLength` exceeds the number of members, the result contains all the elements of `self`.
    ///
    /// - Complexity: O(log(`count`))
    public func suffix(_ maxLength: Int) -> SortedBag {
        return SortedBag(tree.suffix(maxLength))
    }

    /// Returns a subbag containing all members of this bag at or after the specified index.
    ///
    /// - Complexity: O(log(`count`))
    public func suffix(from index: Index) -> SortedBag {
        return SortedBag(tree.suffix(from: index))
    }

    /// Returns a subset containing all members of this bag greater than or equal to the specified element
    /// (which may or may not be a member of this bag).
    ///
    /// - Complexity: O(log(`count`))
    public func suffix(from element: Element) -> SortedBag {
        return SortedBag(tree.suffix(from: element))
    }
}

extension SortedBag: CustomStringConvertible, CustomDebugStringConvertible {
    //MARK: Conversion to string

    /// A textual representation of this bag.
    public var description: String {
        let contents = self.map { String(reflecting: $0) }
        return "[" + contents.joined(separator: ", ") + "]"
    }

    /// A textual representation of this bag, suitable for debugging.
    public var debugDescription: String {
        return "SortedBag(" + description + ")"
    }
}

extension SortedBag {
    //MARK: Queries

    /// Return true if the bag contains `element`.
    ///
    /// - Complexity: O(log(`count`))
    public func contains(_ element: Element) -> Bool {
        return tree.value(of: element) != nil
    }

    /// Returns the multiplicity of `member` in this bag, i.e. the number of instances of `member` contained in the bag.
    /// Returns 0 if `member` is not an element.
    ///
    /// - Complexity: O(log(`count`))
    public func count(of member: Element) -> Int {
        var path = BTreeStrongPath(root: tree.root, key: member, choosing: .first)
        let start = path.offset
        path.move(to: member, choosing: .after)
        return path.offset - start
    }

    /// Returns the index of the first instance of a given member, or `nil` if the member is not present in the bag.
    ///
    /// - Complexity: O(log(`count`))
    public func index(of member: Element) -> BTreeIndex<Element, Void>? {
        return tree.index(forKey: member, choosing: .first)
    }

    /// Returns the index of the lowest member of this bag that is strictly greater than `element`, or `nil` if there is no such element.
    ///
    /// This function never returns `endIndex`. (If it returns non-nil, the returned index can be used to subscript the bag.)
    ///
    /// - Complexity: O(log(`count`))
    public func indexOfFirstElement(after element: Element) -> BTreeIndex<Element, Void>? {
        let index = tree.index(forInserting: element, at: .last)
        if tree.offset(of: index) == tree.count { return nil }
        return index
    }

    /// Returns the index of the lowest member of this bag that is greater than or equal to `element`, or `nil` if there is no such element.
    ///
    /// This function never returns `endIndex`. (If it returns non-nil, the returned index can be used to subscript the bag.)
    ///
    /// - Complexity: O(log(`count`))
    public func indexOfFirstElement(notBefore element: Element) -> BTreeIndex<Element, Void>? {
        let index = tree.index(forInserting: element, at: .first)
        if tree.offset(of: index) == tree.count { return nil }
        return index
    }

    /// Returns the index of the highest member of this bag that is strictly less than `element`, or `nil` if there is no such element.
    ///
    /// This function never returns `endIndex`. (If it returns non-nil, the returned index can be used to subscript the bag.)
    ///
    /// - Complexity: O(log(`count`))
    public func indexOfLastElement(before element: Element) -> BTreeIndex<Element, Void>? {
        var index = tree.index(forInserting: element, at: .first)
        if tree.offset(of: index) == 0 { return nil }
        tree.formIndex(before: &index)
        return index
    }

    /// Returns the index of the highest member of this bag that is less than or equal to `element`, or `nil` if there is no such element.
    ///
    /// This function never returns `endIndex`. (If it returns non-nil, the returned index can be used to subscript the bag.)
    ///
    /// - Complexity: O(log(`count`))
    public func indexOfLastElement(notAfter element: Element) -> BTreeIndex<Element, Void>? {
        var index = tree.index(forInserting: element, at: .last)
        if tree.offset(of: index) == 0 { return nil }
        tree.formIndex(before: &index)
        return index
    }
}

extension SortedBag {
    //MARK: Set comparions

    /// Return `true` iff `self` and `other` contain the same number of instances of all the same elements.
    ///
    /// This method skips over shared subtrees when possible; this can drastically improve performance when the
    /// two bags are divergent mutations originating from the same value.
    ///
    /// - Complexity:  O(`count`)
    public func elementsEqual(_ other: SortedBag<Element>) -> Bool {
        return self.tree.elementsEqual(other.tree, by: { $0.0 == $1.0 })
    }

    /// Returns `true` iff `a` contains the exact same elements as `b`, including multiplicities.
    ///
    /// This function skips over shared subtrees when possible; this can drastically improve performance when the
    /// two bags are divergent mutations originating from the same value.
    ///
    /// - Complexity: O(`count`)
    public static func ==(a: SortedBag<Element>, b: SortedBag<Element>) -> Bool {
        return a.elementsEqual(b)
    }

    /// Returns `true` iff no members in this bag are also included in `other`.
    ///
    /// The elements of the two input bags may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input bags may be skipped instead
    /// of elementwise processing, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func isDisjoint(with other: SortedBag<Element>) -> Bool {
        return tree.isDisjoint(with: other.tree)
    }

    /// Returns `true` iff all members in this bag are also included in `other`.
    ///
    /// The elements of the two input bags may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input bags may be skipped instead
    /// of elementwise processing, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func isSubset(of other: SortedBag<Element>) -> Bool {
        return tree.isSubset(of: other.tree, by: .countingMatches)
    }

    /// Returns `true` iff all members in this bag are also included in `other`, but the two bags aren't equal.
    ///
    /// The elements of the two input bags may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input bags may be skipped instead
    /// of elementwise processing, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func isStrictSubset(of other: SortedBag<Element>) -> Bool {
        return tree.isStrictSubset(of: other.tree, by: .countingMatches)
    }

    /// Returns `true` iff all members in `other` are also included in this bag.
    ///
    /// The elements of the two input bags may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input bags may be skipped instead
    /// of elementwise processing, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func isSuperset(of other: SortedBag<Element>) -> Bool {
        return tree.isSuperset(of: other.tree, by: .countingMatches)
    }

    /// Returns `true` iff all members in `other` are also included in this bag, but the two bags aren't equal.
    ///
    /// The elements of the two input bags may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input bags may be skipped instead
    /// of elementwise processing, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func isStrictSuperset(of other: SortedBag<Element>) -> Bool {
        return tree.isStrictSuperset(of: other.tree, by: .countingMatches)
    }
}

extension SortedBag {
    //MARK: Insertion

    /// Unconditionally insert a new member into the bag, adding another instance if the member was already present.
    ///
    /// The new member is inserted after its existing instances, if any. (This is important when equal members can
    /// be distinguished by identity comparison or some other means.)
    ///
    /// - Note: `SetAlgebra` requires `insert` to do nothing and return `(false, member)` if the set already contains 
    ///    a matching element. `SortedBag` ignores this requirement and always inserts a new copy of the specified element.
    ///
    /// - Parameter newMember: An element to insert into the set.
    ///
    /// - Returns: `(true, newMember)` to satisfy the syntactic requirements of the `SetAlgebra` protocol.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func insert(_ newMember: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        tree.insert((newMember, ()), at: .after)
        return (true, newMember)
    }

    /// Unconditionally insert a new member into the bag, adding another instance if the member was already present.
    ///
    /// The new member is inserted before its existing instances, if any. (This is important when equal members can
    /// be distinguished by identity comparison or some other means.)
    ///
    /// - Note: `SetAlgebra` requires `update` to replace and return an existing member if the set already contains
    ///    a matching element. `SortedBag` ignores this requirement and always inserts a new copy of the specified element.
    ///
    /// - Parameter newMember: An element to insert into the set.
    ///
    /// - Returns: Always returns `nil`, to satisfy the syntactic requirements of the `SetAlgebra` protocol.
    @discardableResult
    public mutating func update(with newMember: Element) -> Element? {
        tree.insert((newMember, ()), at: .first)
        return nil
    }
}

extension SortedBag {
    //MARK: Removal

    /// Remove and return the first instance of `member` from the bag, or return `nil` if the bag contains no instances of `member`.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func remove(_ member: Element) -> Element? {
        return tree.remove(member, at: .first)?.0
    }

    /// Remove all instances of `member` from the bag.
    ///
    /// - Complexity: O(log(`count`))
    public mutating func removeAll(_ member: Element) {
        guard let endOffset = tree.offset(forKey: member, choosing: .last) else { return }
        tree.withCursor(onKey: member, choosing: .first) { cursor in
            cursor.remove(1 + endOffset - cursor.offset)
        }
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


    /// Remove and return the smallest member in this bag.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    mutating func removeFirst() -> Element {
        return tree.removeFirst().0
    }

    /// Remove the smallest `n` members from this bag.
    ///
    /// - Complexity: O(log(`count`))
    mutating func removeFirst(_ n: Int) {
        tree.removeFirst(n)
    }

    /// Remove and return the smallest member in this bag, or return `nil` if the bag is empty.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func popFirst() -> Element? {
        return tree.popFirst()?.0
    }

    /// Remove and return the largest member in this bag.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    mutating func removeLast() -> Element {
        return tree.removeLast().0
    }

    /// Remove the largest `n` members from this bag.
    ///
    /// - Complexity: O(log(`count`))
    mutating func removeLast(_ n: Int) {
        tree.removeLast(n)
    }

    /// Remove and return the largest member in this bag, or return `nil` if the bag is empty.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func popLast() -> Element? {
        return tree.popLast()?.0
    }

    /// Remove all members from this bag.
    public mutating func removeAll() {
        tree.removeAll()
    }
}

extension SortedBag {
    //MARK: Sorting

    /// Return an `Array` containing the members of this bag, in ascending order.
    ///
    /// `SortedSet` already keeps its elements sorted, so this is equivalent to `Array(self)`.
    ///
    /// - Complexity: O(`count`)
    public func sorted() -> [Element] {
        // The bag is already sorted.
        return Array(self)
    }
}

extension SortedBag {
    //MARK: Set operations

    /// Return a bag containing all members from both this bag and `other`.
    /// The result contains all elements of duplicate members from both bags.
    ///
    /// Elements from `other` follow matching elements from `this` in the result.
    ///
    /// The elements of the two input bags may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input bags will be simply
    /// linked into the result instead of copying, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(`self.count` + `other.count`) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func union(_ other: SortedBag<Element>) -> SortedBag<Element> {
        return SortedBag(self.tree.union(other.tree, by: .countingMatches))
    }

    /// Add all members in `other` to this bag, also keeping all existing instances already in `self`.
    ///
    /// The elements of the two input bags may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input sets will be simply
    /// linked into the result instead of copying, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(`self.count` + `other.count`) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public mutating func formUnion(_ other: SortedBag<Element>) {
        self = self.union(other)
    }

    /// Return a set consisting of all members in `other` that are also in this bag.
    /// For duplicate members, only as many instances from `other` are kept in the result that appear in `self`.  
    ///
    /// The elements of the two input sets may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input sets will be simply
    /// linked into the result instead of copying, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func intersection(_ other: SortedBag<Element>) -> SortedBag<Element> {
        return SortedBag(self.tree.intersection(other.tree, by: .countingMatches))
    }

    /// Remove all members from this bag that are not also included in `other`.
    /// For duplicate members, only as many instances from `self` are kept that appear in `other`.
    ///
    /// The elements of the two input sets may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input sets will be simply
    /// linked into the result instead of copying, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public mutating func formIntersection(_ other: SortedBag<Element>) {
        self = other.intersection(self)
    }

    /// Return a bag containing those members of this bag that aren't also included in `other`.
    /// For duplicate members whose multiplicity exceeds that of matching members in `other`, the extra members are
    /// kept in the result.
    ///
    /// The elements of the two input bags may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input bags will be simply
    /// linked into the result instead of copying, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func subtracting(_ other: SortedBag) -> SortedBag {
        return SortedBag(self.tree.subtracting(other.tree, by: .countingMatches))
    }

    /// Remove all members from this bag that are also included in `other`.
    /// For duplicate members whose multiplicity exceeds that of matching members in `other`, 
    /// the extra members aren't removed.
    ///
    /// The elements of the two input bags may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input bags will be simply
    /// linked into the result instead of copying, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public mutating func subtract(_ other: SortedBag) {
        self = self.subtracting(other)
    }

    /// Return a bag consisting of members from `self` and `other` that aren't in both bags at once.
    /// For members whose multiplicity is different in the two bags, the last *d* members from the bag with the 
    /// greater multiplicity is kept in the result (where *d* is the absolute difference of multiplicities).
    ///
    /// The elements of the two input bags may be freely interleaved.
    /// However, if there are long runs of non-interleaved elements, parts of the input bags will be simply
    /// linked into the result instead of copying, which can drastically improve performance.
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func symmetricDifference(_ other: SortedBag<Element>) -> SortedBag<Element> {
        return SortedBag(self.tree.symmetricDifference(other.tree, by: .countingMatches))
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
    public mutating func formSymmetricDifference(_ other: SortedBag<Element>) {
        self = self.symmetricDifference(other)
    }
}

extension SortedBag {
    //MARK: Interactions with ranges

    /// Return the count of elements in this bag that are in `range`.
    ///
    /// - Complexity: O(log(`self.count`))
    public func count(elementsIn range: Range<Element>) -> Int {
        var path = BTreeStrongPath(root: tree.root, key: range.lowerBound, choosing: .first)
        let lowerOffset = path.offset
        path.move(to: range.upperBound, choosing: .first)
        return path.offset - lowerOffset
    }

    /// Return the count of elements in this bag that are in `range`.
    ///
    /// - Complexity: O(log(`self.count`))
    public func count(elementsIn range: ClosedRange<Element>) -> Int {
        var path = BTreeStrongPath(root: tree.root, key: range.lowerBound, choosing: .first)
        let lowerOffset = path.offset
        path.move(to: range.upperBound, choosing: .after)
        return path.offset - lowerOffset
    }

    /// Return a bag consisting of all members in `self` that are also in `range`.
    ///
    /// - Complexity: O(log(`self.count`))
    public func intersection(elementsIn range: Range<Element>) -> SortedBag<Element> {
        return self.suffix(from: range.lowerBound).prefix(upTo: range.upperBound)
    }

    /// Return a bag consisting of all members in `self` that are also in `range`.
    ///
    /// - Complexity: O(log(`self.count`))
    public func intersection(elementsIn range: ClosedRange<Element>) -> SortedBag<Element> {
        return self.suffix(from: range.lowerBound).prefix(through: range.upperBound)
    }

    /// Remove all members from this bag that are not included in `range`.
    ///
    /// - Complexity: O(log(`self.count`))
    public mutating func formIntersection(elementsIn range: Range<Element>) {
        self = self.intersection(elementsIn: range)
    }

    /// Remove all members from this bag that are not included in `range`.
    ///
    /// - Complexity: O(log(`self.count`))
    public mutating func formIntersection(elementsIn range: ClosedRange<Element>) {
        self = self.intersection(elementsIn: range)
    }

    /// Remove all elements in `range` from this bag.
    ///
    /// - Complexity: O(log(`self.count`))
    public mutating func subtract(elementsIn range: Range<Element>) {
        tree.withCursor(onKey: range.upperBound, choosing: .first) { cursor in
            let upperOffset = cursor.offset
            cursor.move(to: range.lowerBound, choosing: .first)
            cursor.remove(upperOffset - cursor.offset)
        }
    }

    /// Remove all elements in `range` from this bag.
    ///
    /// - Complexity: O(log(`self.count`))
    public mutating func subtract(elementsIn range: ClosedRange<Element>) {
        tree.withCursor(onKey: range.upperBound, choosing: .after) { cursor in
            let upperOffset = cursor.offset
            cursor.move(to: range.lowerBound, choosing: .first)
            cursor.remove(upperOffset - cursor.offset)
        }
    }

    /// Return a bag containing those members of this bag that aren't also included in `range`.
    ///
    /// - Complexity: O(log(`self.count`))
    public mutating func subtracting(elementsIn range: Range<Element>) -> SortedBag<Element> {
        var copy = self
        copy.subtract(elementsIn: range)
        return copy
    }

    /// Return a bag containing those members of this bag that aren't also included in `range`.
    ///
    /// - Complexity: O(log(`self.count`))
    public mutating func subtracting(elementsIn range: ClosedRange<Element>) -> SortedBag<Element> {
        var copy = self
        copy.subtract(elementsIn: range)
        return copy
    }
}

extension SortedBag where Element: Strideable {
    //MARK: Shifting

    /// Shift the value of all elements starting at `start` by `delta`.
    /// For a positive `delta`, this shifts elements to the right, creating an empty gap in `start ..< start + delta`.
    /// For a negative `delta`, this shifts elements to the left, removing any elements in the range `start + delta ..< start` that were previously in the bag.
    ///
    /// - Complexity: O(`self.count`). The elements are modified in place.
    public mutating func shift(startingAt start: Element, by delta: Element.Stride) {
        guard delta != 0 else { return }
        tree.withCursor(onKey: start, choosing: .first) { cursor in
            if delta < 0 {
                let offset = cursor.offset
                cursor.move(to: start.advanced(by: delta), choosing: .first)
                cursor.remove(offset - cursor.offset)
            }
            while !cursor.isAtEnd {
                cursor.key = cursor.key.advanced(by: delta)
                cursor.moveForward()
            }
        }
    }

    /// Shift the value of all elements starting at index `start` by `delta`.
    ///
    /// This variant does not ever remove elements from the bag; if `delta` is negative, its absolute value
    /// must not be greater than the difference between the element at `start` and the element previous to it (if any).
    ///
    /// - Requires: `start == self.startIndex || self[self.index(before: startIndex)] <= self[index] + delta
    /// - Complexity: O(`self.count`). The elements are modified in place.
    public mutating func shift(startingAt start: Index, by delta: Element.Stride) {
        guard delta != 0, tree.offset(of: start) != count else { return }
        tree.withCursor(at: start) { cursor in
            if delta < 0 && !cursor.isAtStart {
                let k = cursor.key.advanced(by: delta)
                cursor.moveBackward()
                precondition(cursor.key <= k)
                cursor.moveForward()
            }
            while !cursor.isAtEnd {
                cursor.key = cursor.key.advanced(by: delta)
                cursor.moveForward()
            }
        }
    }

}
