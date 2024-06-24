//
//  Map.swift
//  BTree
//
//  Created by Károly Lőrentey on 2015-12-17.
//  Copyright © 2015–2017 Károly Lőrentey.
//

/// An ordered mapping from comparable keys to arbitrary values. 
/// Works like `Dictionary`, but provides a well-defined ordering for its elements.
///
/// `Map` is a struct with copy-on-write value semantics, like Swift's standard collection types.
/// It uses an in-memory B-tree for element storage, whose individual nodes may be shared with other maps.
/// Modifying an element of a map whose storage is (partially or completely) shared requires copying of 
/// only O(log(`count`)) elements. (Thus, mutation of shared maps may be relatively cheaper than dictionaries, 
/// which need to clone all elements.)
///
/// Lookup, insertion and removal of individual key-value pairs in a map have logarithmic complexity.
/// This is in contrast to `Dictionary`'s best-case O(1) (worst-case O(n)) implementations for the same operations.
/// To make up for being typically slower, `Map` always keeps its elements in a well-defined order.
///
/// While independently looking up individual elements takes O(log(n)) time, batch operations on lots of elements
/// often complete faster than you might expect.
/// For example, iterating over a `Map` using the generator API requires O(n) time, just like a dictionary.
///
/// Due to its tree-based structure, `Map` is able to provide efficient implementations for several operations 
/// that would be slower with dictionaries.
///
public struct Map<Key: Comparable, Value> {
    // Typealiases
    internal typealias Tree = BTree<Key, Value>

    /// The B-tree that serves as storage.
    internal fileprivate(set) var tree: Tree

    fileprivate init(_ tree: Tree) {
        self.tree = tree
    }
}

extension Map {
    //MARK: Initializers

    /// Initialize an empty map.
    public init() {
        self.tree = Tree()
    }
}

extension Map {
    /// Initialize a new map from an unsorted sequence of elements, using a stable sort algorithm.
    ///
    /// If the sequence contains elements with duplicate keys, only the last element is kept in the map.
    ///
    /// - Complexity: O(*n* * log(*n*)) where *n* is the number of items in `elements`.
    public init<S: Sequence>(_ elements: S) where S.Element == Element {
        self.tree = Tree(elements, dropDuplicates: true)
    }

    /// Initialize a new map from a sorted sequence of elements.
    ///
    /// If the sequence contains elements with duplicate keys, only the last element is kept in the map.
    ///
    /// - Complexity: O(*n*) where *n* is the number of items in `elements`.
    public init<S: Sequence>(sortedElements elements: S) where S.Element == Element {
        self.tree = Tree(sortedElements: elements, dropDuplicates: true)
    }
}

extension Map: ExpressibleByDictionaryLiteral {
    /// Initialize a new map from the given elements.
    public init(dictionaryLiteral elements: (Key, Value)...) {
        self.tree = Tree(elements, dropDuplicates: true)
    }
}

extension Map: CustomStringConvertible {
    //MARK: Conversion to string
    
    /// A textual representation of this map.
    public var description: String {
        let contents = self.map { (key, value) -> String in
            let ks = String(reflecting: key)
            let vs = String(reflecting: value)
            return "\(ks): \(vs)"
        }
        return "[" + contents.joined(separator: ", ") + "]"
    }
}

extension Map: CustomDebugStringConvertible {
    /// A textual representation of this map, suitable for debugging.
    public var debugDescription: String {
        let contents = self.map { (key, value) -> String in
            let ks = String(reflecting: key)
            let vs = String(reflecting: value)
            return "\(ks): \(vs)"
        }
        return "[" + contents.joined(separator: ", ") + "]"
    }
}

extension Map: BidirectionalCollection {
    //MARK: CollectionType
    
    public typealias Index = BTreeIndex<Key, Value>
    public typealias Iterator = BTreeIterator<Key, Value>
    public typealias Element = (Key, Value)
    public typealias _Element = Element // For _IndexableBase
    public typealias SubSequence = Map<Key, Value>

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

    /// The number of (key, value) pairs in this map.
    public var count: Int {
        return tree.count
    }

    /// True iff this collection has no elements.
    public var isEmpty: Bool {
        return count == 0
    }

    /// Returns the (key, value) pair at the given index.
    ///
    /// - Requires: `index` originated from an unmutated copy of this map.
    /// - Complexity: O(1)
    public subscript(index: Index) -> Element {
        return tree[index]
    }

    /// Return a submap consisting of elements in the given range of indexes.
    ///
    /// - Requires: The indexes in `range` originated from an unmutated copy of this map.
    /// - Complexity: O(log(`count`))
    public subscript(range: Range<Index>) -> Map<Key, Value> {
        return Map(tree[range])
    }

    /// Return an iterator over all (key, value) pairs in this map, in ascending key order.
    public func makeIterator() -> Iterator {
        return tree.makeIterator()
    }

    /// Returns the successor of the given index.
    ///
    /// - Requires: `index` is a valid index of this map and it is not equal to `endIndex`.
    /// - Complexity: Amortized O(1).
    public func index(after index: Index) -> Index {
        return tree.index(after: index)
    }

    /// Replaces the given index with its successor.
    ///
    /// - Requires: `index` is a valid index of this map and it is not equal to `endIndex`.
    /// - Complexity: Amortized O(1).
    public func formIndex(after index: inout Index) {
        tree.formIndex(after: &index)
    }

    /// Returns the predecessor of the given index.
    ///
    /// - Requires: `index` is a valid index of this map and it is not equal to `startIndex`.
    /// - Complexity: Amortized O(1).
    public func index(before index: Index) -> Index {
        return tree.index(before: index)
    }

    /// Replaces the given index with its predecessor.
    ///
    /// - Requires: `index` is a valid index of this map and it is not equal to `startIndex`.
    /// - Complexity: Amortized O(1).
    public func formIndex(before index: inout Index) {
        tree.formIndex(before: &index)
    }

    /// Returns an index that is the specified distance from the given index.
    ///
    /// - Requires: `index` must be a valid index of this map.
    ///              If `n` is positive, it must not exceed the distance from `index` to `endIndex`.
    ///              If `n` is negative, it must not be less than the distance from `index` to `startIndex`.
    /// - Complexity: O(log(*count*)) where *count* is the number of elements in the map.
    public func index(_ i: Index, offsetBy n: Int) -> Index {
        return tree.index(i, offsetBy: n)
    }

    /// Offsets the given index by the specified distance.
    ///
    /// - Requires: `index` must be a valid index of this map.
    ///              If `n` is positive, it must not exceed the distance from `index` to `endIndex`.
    ///              If `n` is negative, it must not be less than the distance from `index` to `startIndex`.
    /// - Complexity: O(log(*count*)) where *count* is the number of elements in the map.
    public func formIndex(_ i: inout Index, offsetBy n: Int) {
        tree.formIndex(&i, offsetBy: n)
    }

    /// Returns an index that is the specified distance from the given index, unless that distance is beyond a given limiting index.
    ///
    /// - Requires: `index` and `limit` must be valid indices in this map. The operation must not advance the index beyond `endIndex` or before `startIndex`.
    /// - Complexity: O(log(*count*)) where *count* is the number of elements in the map.
    public func index(_ i: Index, offsetBy n: Int, limitedBy limit: Index) -> Index? {
        return tree.index(i, offsetBy: n, limitedBy: limit)
    }

    /// Offsets the given index by the specified distance, or so that it equals the given limiting index.
    ///
    /// - Requires: `index` and `limit` must be valid indices in this map. The operation must not advance the index beyond `endIndex` or before `startIndex`.
    /// - Complexity: O(log(*count*)) where *count* is the number of elements in the map.
    @discardableResult
    public func formIndex(_ i: inout Index, offsetBy n: Int, limitedBy limit: Index) -> Bool {
        return tree.formIndex(&i, offsetBy: n, limitedBy: limit)
    }

    /// Returns the distance between two indices.
    ///
    /// - Requires: `start` and `end` must be valid indices in this map.
    /// - Complexity: O(1)
    public func distance(from start: Index, to end: Index) -> Int {
        return tree.distance(from: start, to: end)
    }
}

extension Map {
    //MARK: Algorithms
    
    /// Call `body` on each element in `self` in ascending key order.
    ///
    /// - Complexity: O(`count`)
    public func forEach(_ body: (Element) throws -> ()) rethrows {
        try tree.forEach(body)
    }

    /// Return an `Array` containing the results of mapping `transform` over all elements in `self`.
    /// The elements are transformed in ascending key order.
    ///
    /// - Complexity: O(`count`)
    public func map<T>(_ transform: (Element) throws -> T) rethrows -> [T] {
        var result: [T] = []
        result.reserveCapacity(self.count)
        try self.forEach {
            result.append(try transform($0))
        }
        return result
    }

    /// Return an `Array` containing the concatenated results of mapping `transform` over `self`.
    ///
    /// - Complexity: O(`count`)
    public func flatMap<S: Sequence>(_ transform: (Element) throws -> S) rethrows -> [S.Element] {
        var result: [S.Element] = []
        try self.forEach { element in
            result.append(contentsOf: try transform(element))
        }
        return result
    }

    /// Return an `Array` containing the non-`nil` results of mapping `transform` over `self`.
    ///
    /// - Complexity: O(`count`)
    public func flatMap<T>(_ transform: (Element) throws -> T?) rethrows -> [T] {
        var result: [T] = []
        try self.forEach { element in
            if let t = try transform(element) {
                result.append(t)
            }
        }
        return result
    }

    /// Calculate the left fold of this map over `combine`:
    /// return the result of repeatedly calling `combine` with an accumulated value initialized to `initial`
    /// and each element of `self`, in turn. 
    ///
    /// I.e., return `combine(combine(...combine(combine(initial, self[0]), self[1]),...self[count-2]), self[count-1])`.
    ///
    /// - Complexity: O(`count`)
    public func reduce<T>(_ initialResult: T, _ nextPartialResult: (T, Element) throws -> T) rethrows -> T {
        var result = initialResult
        try self.forEach {
            result = try nextPartialResult(result, $0)
        }
        return result
    }
}

extension Map {
    //MARK: Dictionary-like methods

    /// A collection containing just the keys in this map, in ascending order.
    public var keys: LazyMapCollection<Map<Key, Value>, Key> {
        return self.lazy.map { $0.0 }
    }

    /// A collection containing just the values in this map, in order of ascending keys.
    public var values: LazyMapCollection<Map<Key, Value>, Value> {
        return self.lazy.map { $0.1 }
    }

    /// Provides access to the value for a given key. Nonexistent values are represented as `nil`.
    /// 
    /// - Complexity: O(log(`count`))
    public subscript(key: Key) -> Value? {
        get {
            return tree.value(of: key)
        }
        set(value) {
            if let value = value {
                updateValue(value, forKey: key)
            }
            else {
                removeValue(forKey: key)
            }
        }
    }

    /// Returns the index for the given key, or `nil` if the key is not present in this map.
    ///
    /// - Complexity: O(log(`count`))
    public func index(forKey key: Key) -> Index? {
        return tree.index(forKey: key)
    }

    /// Update the value stored in the map for the given key, or, if they key does not exist, add a new key-value pair to the map.
    /// Returns the value that was replaced, or `nil` if a new key-value pair was added.
    ///
    /// This method invalidates all existing indexes into `self`.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func updateValue(_ value: Value, forKey key: Key) -> Value? {
        return tree.insertOrReplace((key, value))?.1
    }

    /// Remove the key-value pair at `index` from this map.
    ///
    /// This method invalidates all existing indexes into `self`.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func remove(at index: Index) -> (key: Key, value: Value) {
        return tree.remove(at: index)
    }

    /// Remove a given key and the associated value from this map.
    /// Returns the value that was removed, or `nil` if the key was not present in the map.
    ///
    /// This method invalidates all existing indexes into `self`.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func removeValue(forKey key: Key) -> Value? {
        return tree.remove(key)?.1
    }

    /// Remove all elements from this map.
    ///
    /// This method invalidates all existing indexes into `self`.
    ///
    /// - Complexity: O(`count`)
    public mutating func removeAll() {
        tree = Tree()
    }
}

extension Map {
    //MARK: Offset-based access

    /// Returns the index of the element at `offset`.
    ///
    /// - Requires: `offset >= 0 && offset < count`
    /// - Complexity: O(log(`count`))
    public func index(ofOffset offset: Int) -> Index {
        return tree.index(ofOffset: offset)
    }

    /// Returns the offset of the element at `index`.
    ///
    /// - Complexity: O(log(`count`))
    public func offset(of index: Index) -> Int {
        return tree.offset(of: index)
    }

    /// Returns the offset of the element with the given key, or `nil` if there is no such element.
    ///
    /// - Complexity: O(log(`count`))
    public func offset(of key: Key) -> Int? {
        return tree.offset(forKey: key)
    }

    /// Return the element stored at `offset` in this map.
    ///
    /// - Complexity: O(log(`count`))
    public func element(atOffset offset: Int) -> Element {
        return tree.element(atOffset: offset)
    }

    /// Set the value of the element stored at `offset` in this map.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func updateValue(_ value: Value, atOffset offset: Int) -> Value {
        return tree.setValue(atOffset: offset, to: value)
    }

    /// Remove and return the (key, value) pair at the specified offset from the start of the map.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func remove(atOffset offset: Int) -> Element {
        return tree.remove(atOffset: offset)
    }

    /// Remove all (key, value) pairs in the specified offset range.
    ///
    /// - Complexity: O(log(`count`))
    public mutating func remove(atOffsets offsets: Range<Int>) {
        precondition(offsets.lowerBound >= 0 && offsets.upperBound <= count)
        tree.withCursor(atOffset: offsets.lowerBound) { cursor in
            cursor.remove(offsets.count)
        }
    }
}

extension Map {
    //MARK: Submaps

    /// Return a submap consisting of elements in the specified range of indexes.
    ///
    /// - Complexity: O(log(`count`))
    public func submap(with range: Range<Index>) -> Map {
        return Map(tree.subtree(with: range))
    }

    /// Return a submap consisting of elements in the specified range of offsets.
    ///
    /// - Complexity: O(log(`count`))
    public func submap(withOffsets offsets: Range<Int>) -> Map {
        return Map(tree.subtree(withOffsets: offsets))
    }

    /// Return a submap consisting of all elements with keys greater than or equal to `start` but less than `end`.
    ///
    /// - Complexity: O(log(`count`))
    public func submap(from start: Key, to end: Key) -> Map {
        return Map(tree.subtree(from: start, to: end))
    }

    /// Return a submap consisting of all elements with keys greater than or equal to `start` but less than or equal to `end`.
    ///
    /// - Complexity: O(log(`count`))
    public func submap(from start: Key, through end: Key) -> Map {
        return Map(tree.subtree(from: start, through: end))
    }
}

extension Map {
    //MARK: Equivalence

    /// Return `true` iff `self` and `other` contain equivalent elements, using `isEquivalent` as the equivalence test.
    ///
    /// This method skips over shared subtrees when possible; this can drastically improve performance when the
    /// two maps are divergent mutations originating from the same value.
    ///
    /// - Requires: `isEquivalent` is an [equivalence relation].
    /// - Complexity:  O(`count`)
    ///
    /// [equivalence relation]: https://en.wikipedia.org/wiki/Equivalence_relation
    public func elementsEqual(_ other: Map, by isEquivalent: (Element, Element) throws -> Bool) rethrows -> Bool {
        return try tree.elementsEqual(other.tree, by: isEquivalent)
    }
}

extension Map where Value: Equatable {
    /// Return `true` iff `self` and `other` contain equivalent elements.
    ///
    /// This method skips over shared subtrees when possible; this can drastically improve performance when the
    /// two maps are divergent mutations originating from the same value.
    ///
    /// - Complexity:  O(`count`)
    public func elementsEqual(_ other: Map) -> Bool {
        return tree.elementsEqual(other.tree)
    }
    
    /// Return true iff `a` is equal to `b`.
    ///
    /// This function skips over shared subtrees when possible; this can drastically improve performance when the
    /// two maps are divergent mutations originating from the same value.
    public static func ==(a: Map, b: Map) -> Bool {
        return a.elementsEqual(b)
    }

    /// Return true iff `a` is not equal to `b`.
    public static func !=(a: Map, b: Map) -> Bool {
        return !(a == b)
    }
}

extension Map {
    //MARK: Merging

    /// Return a map that combines elements from `self` with those in `other`.
    /// If a key is included in both maps, the value from `other` is used.
    /// 
    /// This function links subtrees containing elements with distinct keys when possible;
    /// this can drastically improve performance when the keys of the two maps aren't too interleaved.
    ///
    /// - Complexity: O(`count`)
    public func merging(_ other: Map) -> Map {
        return Map(self.tree.union(other.tree, by: .groupingMatches))
    }

    /// Return a map that combines elements from `a` with those in `b`.
    /// If a key is included in both maps, the value from `b` is used.
    ///
    /// This function links subtrees containing elements with distinct keys when possible;
    /// this can drastically improve performance when the keys of the two maps aren't too interleaved.
    ///
    /// - Complexity: O(`count`)
    public static func +(a: Map, b: Map) -> Map {
        return a.merging(b)
    }
}

extension Map {
    //MARK: Including and excluding keys

    /// Return a map that contains all elements in `self` whose keys are in `keys`.
    ///
    /// - Complexity: O(`keys.count` * log(`count`))
    public func including(_ keys: SortedSet<Key>) -> Map {
        return Map(self.tree.intersection(sortedKeys: keys, by: .groupingMatches))
    }

    /// Return a map that contains all elements in `self` whose keys are in `keys`.
    ///
    /// - Complexity: O(*n* * log(`count`)) where *n* is the number of keys in `keys`.
    public func including<S: Sequence>(_ keys: S) -> Map where S.Element == Key {
        return including(SortedSet(keys))
    }

    /// Return a map that contains all elements in `self` whose keys are not in `keys`.
    ///
    /// - Complexity: O(`keys.count` * log(`count`))
    public func excluding(_ keys: SortedSet<Key>) -> Map {
        return Map(self.tree.subtracting(sortedKeys: keys, by: .groupingMatches))
    }

    /// Return a map that contains all elements in `self` whose keys are not in `keys`.
    ///
    /// - Complexity: O(*n* * log(`count`)) where *n* is the number of keys in `keys`.
    public func excluding<S: Sequence>(_ keys: S) -> Map where S.Element == Key {
        return excluding(SortedSet(keys))
    }
}
