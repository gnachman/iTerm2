//
//  BTreeMerger.swift
//  BTree
//
//  Created by Károly Lőrentey on 2016-02-27.
//  Copyright © 2016–2017 Károly Lőrentey.
//

/// The matching strategy to use when comparing elements from two trees with duplicate keys.
public enum BTreeMatchingStrategy {

    /// Use a matching strategy appropriate for a set. I.e., match partition classes over key equality rather than individual keys.
    ///
    /// This strategy ignores the multiplicity of keys, and only consider whether a key is included in the two trees at all.
    /// E.g., a single element from one tree will be considered a match for any positive number of elements with the same key in
    /// the other tree.
    case groupingMatches

    /// Use a matching strategy appropriate for a multiset. I.e., try to establish a one-to-one correspondence between 
    /// elements from the two trees with equal keys.
    ///
    /// This strategy keeps track of the multiplicity of each key, and matches every element from one tree with 
    /// at most a single element with an equal key from the other tree. If a key has different multiplicities in 
    /// the two trees, duplicate elements above the lesser multiplicity will not be considered matching.
    case countingMatches
}

extension BTree {
    //MARK: Merging and set operations

    /// Merge elements from two trees into a new tree, and return it.
    ///
    /// - Parameter other: Any tree with the same order as `self`.
    ///
    /// - Parameter strategy:
    ///      When `.groupingMatches`, elements in `self` whose keys also appear in `other` are not included in the result.
    ///      If neither input tree had duplicate keys on its own, the result won't have any duplicates, either.
    ///
    ///      When `.countingMatches`, all elements in both trees are kept in the result, including ones with duplicate keys.
    ///      The result may have duplicate keys, even if the input trees only had unique-keyed elements.
    ///
    /// - Returns: A tree with elements from `self` with matching keys in `other` removed.
    ///
    /// - Note:
    ///     The elements of the two input trees may interleave and overlap in any combination.
    ///     However, if there are long runs of non-interleaved elements, parts of the input trees will be entirely
    ///     skipped instead of elementwise processing. This may drastically improve performance.
    ///
    ///     When `strategy == .groupingMatches`, this function also detects shared subtrees between the two trees,
    ///     and links them directly into the result when possible. (Otherwise matching keys are individually processed.)
    ///
    /// - Requires: `self.order == other.order`
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func union(_ other: BTree, by strategy: BTreeMatchingStrategy) -> BTree {
        var m = BTreeMerger(first: self, second: other)
        switch strategy {
        case .groupingMatches:
            while !m.done {
                m.copyFromFirst(.excludingOtherKey)
                m.copyFromSecond(.excludingOtherKey)
                m.copyCommonElementsFromSecond()
            }
        case .countingMatches:
            while !m.done {
                m.copyFromFirst(.includingOtherKey)
                m.copyFromSecond(.excludingOtherKey)
            }
        }
        m.appendFirst()
        m.appendSecond()
        return m.finish()
    }

    /// Return a tree with the same elements as `self` except those with matching keys in `other`.
    ///
    /// - Parameter other: Any tree with the same order as `self`.
    ///
    /// - Parameter strategy:
    ///      When `.groupingMatches`, all elements in `self` that have a matching key in `other` are removed.
    ///
    ///      When `.countingMatches`, for each key in `self`, only as many matching elements are removed as the key's multiplicity in `other`.
    ///
    /// - Returns: A tree with elements from `self` with matching keys in `other` removed.
    ///
    /// - Note:
    ///     The elements of the two input trees may interleave and overlap in any combination.
    ///     However, if there are long runs of non-interleaved elements, parts of the input trees will be entirely
    ///     skipped or linked into the result instead of elementwise processing. This may drastically improve performance.
    ///
    ///     This function also detects and skips over shared subtrees between the two trees.
    ///     (Keys that appear in both trees otherwise require individual processing.)
    ///
    /// - Requires: `self.order == other.order`
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `tree.count`)) in general.
    ///    - O(log(`self.count` + `tree.count`)) if there are only a constant amount of interleaving element runs.
    public func subtracting(_ other: BTree, by strategy: BTreeMatchingStrategy) -> BTree {
        var m = BTreeMerger(first: self, second: other)
        while !m.done {
            m.copyFromFirst(.excludingOtherKey)
            m.skipFromSecond(.excludingOtherKey)
            switch strategy {
            case .groupingMatches:
                m.skipCommonElements()
            case .countingMatches:
                m.skipMatchingNumberOfCommonElements()
            }
        }
        m.appendFirst()
        return m.finish()
    }


    /// Return a tree combining the elements of `self` and `other` except those whose keys can be matched in both trees.
    ///
    /// - Parameter other: Any tree with the same order as `self`.
    ///
    /// - Parameter strategy:
    ///      When `.groupingMatches`, all elements in both trees are removed whose key appears in both
    ///      trees, regardless of their multiplicities.
    ///
    ///      When `.countingMatches`, for each key, only as many matching elements are removed as the minimum of the
    ///        key's multiplicities in the two trees, leaving "extra" occurences from the "longer" tree in the result.
    ///
    /// - Returns: A tree combining elements of `self` and `other` except those whose keys can be matched in both trees.
    ///
    /// - Note:
    ///     The elements of the two input trees may interleave and overlap in any combination.
    ///     However, if there are long runs of non-interleaved elements, parts of the input trees will be entirely
    ///     linked into the result instead of elementwise processing. This may drastically improve performance.
    ///
    ///     This function also detects and skips over shared subtrees between the two trees.
    ///     (Keys that appear in both trees otherwise require individual processing.)
    ///
    /// - Requires: `self.order == other.order`
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func symmetricDifference(_ other: BTree, by strategy: BTreeMatchingStrategy) -> BTree {
        var m = BTreeMerger(first: self, second: other)
        while !m.done {
            m.copyFromFirst(.excludingOtherKey)
            m.copyFromSecond(.excludingOtherKey)
            switch strategy {
            case .groupingMatches:
                m.skipCommonElements()
            case .countingMatches:
                m.skipMatchingNumberOfCommonElements()
            }
        }
        m.appendFirst()
        m.appendSecond()
        return m.finish()
    }

    /// Return a tree with those elements of `other` whose keys are also included in `self`.
    ///
    /// - Parameter other: Any tree with the same order as `self`.
    ///
    /// - Parameter strategy:
    ///      When `.groupingMatches`, all elements in `other` are included that have matching keys
    ///      in `self`, regardless of multiplicities.
    ///
    ///      When `.countingMatches`, for each key, only as many matching elements from `other` are kept as 
    ///      the minimum of the key's multiplicities in the two trees.
    ///
    /// - Returns: A tree combining elements of `self` and `other` except those whose keys can be matched in both trees.
    ///
    /// - Note:
    ///      The elements of the two input trees may interleave and overlap in any combination.
    ///      However, if there are long runs of non-interleaved elements, parts of the input trees will be entirely
    ///      skipped instead of elementwise processing. This may drastically improve performance.
    ///
    ///      This function also detects shared subtrees between the two trees,
    ///      and links them directly into the result when possible.
    ///      (Keys that appear in both trees otherwise require individual processing.)
    ///
    /// - Requires: `self.order == other.order`
    ///
    /// - Complexity:
    ///    - O(min(`self.count`, `other.count`)) in general.
    ///    - O(log(`self.count` + `other.count`)) if there are only a constant amount of interleaving element runs.
    public func intersection(_ other: BTree, by strategy: BTreeMatchingStrategy) -> BTree {
        var m = BTreeMerger(first: self, second: other)
        while !m.done {
            m.skipFromFirst(.excludingOtherKey)
            m.skipFromSecond(.excludingOtherKey)
            switch strategy {
            case .groupingMatches:
                m.copyCommonElementsFromSecond()
            case .countingMatches:
                m.copyMatchingNumberOfCommonElementsFromSecond()
            }
        }
        return m.finish()
    }

    /// Return a tree that contains all elements in `self` whose key is not in the supplied sorted sequence.
    ///
    /// - Note:
    ///      The keys of `self` may interleave and overlap with `sortedKeys` in any combination.
    ///      However, if there are long runs of non-interleaved keys, parts of `self` will be entirely
    ///      skipped instead of elementwise processing. This may drastically improve performance.
    ///
    /// - Requires: `sortedKeys` is sorted in ascending order.
    /// - Complexity: O(*n* + `self.count`), where *n* is the number of keys in `sortedKeys`.
    public func subtracting<S: Sequence>(sortedKeys: S, by strategy: BTreeMatchingStrategy) -> BTree where S.Element == Key {
        if self.isEmpty { return self }

        var b = BTreeBuilder<Key, Value>(order: self.order)
        var lastKey: Key? = nil
        var path = BTreeStrongPath(startOf: self.root)
        outer: for key in sortedKeys {
            precondition(lastKey == nil || lastKey! <= key)
            lastKey = key
            while path.key < key {
                b.append(path.nextPart(until: .excluding(key)))
                if path.isAtEnd { break outer }
            }
            switch strategy {
            case .groupingMatches:
                while path.key == key {
                    path.nextPart(until: .including(key))
                    if path.isAtEnd { break outer }
                }
            case .countingMatches:
                if path.key == key {
                    path.moveForward()
                    if path.isAtEnd { break outer }
                }
            }
        }
        if !path.isAtEnd {
            b.append(path.element)
            b.appendWithoutCloning(path.suffix().root)
        }
        return BTree(b.finish())
    }

    /// Return a tree that contains all elements in `self` whose key is in the supplied sorted sequence.
    ///
    /// - Note:
    ///      The keys of `self` may interleave and overlap with `sortedKeys` in any combination.
    ///      However, if there are long runs of non-interleaved keys, parts of `self` will be entirely
    ///      skipped instead of elementwise processing. This may drastically improve performance.
    ///
    /// - Requires: `sortedKeys` is sorted in ascending order.
    /// - Complexity: O(*n* + `self.count`), where *n* is the number of keys in `sortedKeys`.
    public func intersection<S: Sequence>(sortedKeys: S, by strategy: BTreeMatchingStrategy) -> BTree where S.Element == Key {
        if self.isEmpty { return self }

        var b = BTreeBuilder<Key, Value>(order: self.order)
        var lastKey: Key? = nil
        var path = BTreeStrongPath(startOf: self.root)
        outer: for key in sortedKeys {
            precondition(lastKey == nil || lastKey! <= key)
            lastKey = key
            while path.key < key {
                path.nextPart(until: .excluding(key))
                if path.isAtEnd { break outer }
            }
            switch strategy {
            case .groupingMatches:
                while path.key == key {
                    b.append(path.nextPart(until: .including(key)))
                    if path.isAtEnd { break outer }
                }
            case .countingMatches:
                if path.key == key {
                    b.append(path.element)
                    path.moveForward()
                    if path.isAtEnd { break outer }
                }
            }
        }
        return BTree(b.finish())
    }
}

enum BTreeLimit<Key: Comparable> {
    case including(Key)
    case excluding(Key)

    func match(_ key: Key) -> Bool {
        switch self {
        case .including(let limit):
            return key <= limit
        case .excluding(let limit):
            return key < limit
        }
    }
}

enum BTreeRelativeLimit {
    case includingOtherKey
    case excludingOtherKey

    func with<Key: Comparable>(_ key: Key) -> BTreeLimit<Key> {
        switch self {
        case .includingOtherKey:
            return .including(key)
        case .excludingOtherKey:
            return .excluding(key)
        }
    }
}

/// An abstraction for elementwise/subtreewise merging some of the elements from two trees into a new third tree.
///
/// Merging starts at the beginning of each tree, then proceeds in order from smaller to larger keys.
/// At each step you can decide which tree to merge elements/subtrees from next, until we reach the end of
/// one of the trees.
internal struct BTreeMerger<Key: Comparable, Value> {
    typealias Limit = BTreeLimit<Key>
    typealias Node = BTreeNode<Key, Value>

    private var a: BTreeStrongPath<Key, Value>
    private var b: BTreeStrongPath<Key, Value>
    private var builder: BTreeBuilder<Key, Value>

    /// This flag is set to `true` when we've reached the end of one of the trees.
    /// When this flag is set, you may further skips and copies will do nothing. 
    /// You may call `appendFirst` and/or `appendSecond` to append the remaining parts
    /// of whichever tree has elements left, or you may call `finish` to stop merging.
    internal var done: Bool

    /// Construct a new merger starting at the starts of the specified two trees.
    init(first: BTree<Key, Value>, second: BTree<Key, Value>) {
        precondition(first.order == second.order)
        self.a = BTreeStrongPath(startOf: first.root)
        self.b = BTreeStrongPath(startOf: second.root)
        self.builder = BTreeBuilder(order: first.order, keysPerNode: first.root.maxKeys)
        self.done = first.isEmpty || second.isEmpty
    }

    /// Stop merging and return the merged result.
    mutating func finish() -> BTree<Key, Value> {
        return BTree(builder.finish())
    }

    /// Append the rest of the first tree to the end of the result tree, jump to the end of the first tree, and
    /// set `done` to true.
    ///
    /// You may call this method even when `done` has been set to true by an earlier operation. It does nothing
    /// if the merger has already reached the end of the first tree.
    ///
    /// - Complexity: O(log(first.count))
    mutating func appendFirst() {
        if !a.isAtEnd {
            builder.append(a.element)
            builder.append(a.suffix().root)
            a.moveToEnd()
            done = true
        }
    }

    /// Append the rest of the second tree to the end of the result tree, jump to the end of the second tree, and
    /// set `done` to true.
    ///
    /// You may call this method even when `done` has been set to true by an earlier operation. It does nothing
    /// if the merger has already reached the end of the second tree.
    ///
    /// - Complexity: O(log(first.count))
    mutating func appendSecond() {
        if !b.isAtEnd {
            builder.append(b.element)
            builder.append(b.suffix().root)
            b.moveToEnd()
            done = true
        }
    }

    /// Copy elements from the first tree (starting at the current position) that are less than (or, when `limit`
    /// is `.includingOtherKey`, less than or equal to) the key in the second tree at its the current position.
    ///
    /// This method will link entire subtrees to the result whenever possible, which can considerably speed up the operation.
    ///
    /// This method does nothing if `done` has been set to `true` by an earlier operation. It sets `done` to true
    /// if it reaches the end of the first tree.
    ///
    /// - Complexity: O(*n*) where *n* is the number of elements copied.
    mutating func copyFromFirst(_ limit: BTreeRelativeLimit) {
        if !b.isAtEnd {
            copyFromFirst(limit.with(b.key))
        }
    }

    mutating func copyFromFirst(_ limit: Limit) {
        while !a.isAtEnd && limit.match(a.key) {
            builder.append(a.nextPart(until: limit))
        }
        if a.isAtEnd {
            done = true
        }
    }

    /// Copy elements from the second tree (starting at the current position) that are less than (or, when `limit`
    /// is `.includingOtherKey`, less than or equal to) the key in the first tree at its the current position.
    ///
    /// This method will link entire subtrees to the result whenever possible, which can considerably speed up the operation.
    ///
    /// This method does nothing if `done` has been set to `true` by an earlier operation. It sets `done` to true
    /// if it reaches the end of the second tree.
    ///
    /// - Complexity: O(*n*) where *n* is the number of elements copied.
    mutating func copyFromSecond(_ limit: BTreeRelativeLimit) {
        if !a.isAtEnd {
            copyFromSecond(limit.with(a.key))
        }
    }

    mutating func copyFromSecond(_ limit: Limit) {
        while !b.isAtEnd && limit.match(b.key) {
            builder.append(b.nextPart(until: limit))
        }
        if b.isAtEnd {
            done = true
        }
    }

    /// Skip elements from the first tree (starting at the current position) that are less than (or, when `limit`
    /// is `.includingOtherKey`, less than or equal to) the key in the second tree at its the current position.
    ///
    /// This method will jump over entire subtrees to the result whenever possible, which can considerably speed up the operation.
    ///
    /// This method does nothing if `done` has been set to `true` by an earlier operation. It sets `done` to true
    /// if it reaches the end of the first tree.
    ///
    /// - Complexity: O(*n*) where *n* is the number of elements skipped.
    mutating func skipFromFirst(_ limit: BTreeRelativeLimit) {
        if !b.isAtEnd {
            skipFromFirst(limit.with(b.key))
        }
    }

    mutating func skipFromFirst(_ limit: Limit) {
        while !a.isAtEnd && limit.match(a.key) {
            a.nextPart(until: limit)
        }
        if a.isAtEnd {
            done = true
        }
    }

    /// Skip elements from the second tree (starting at the current position) that are less than (or, when `limit`
    /// is `.includingOtherKey`, less than or equal to) the key in the first tree at its the current position.
    ///
    /// This method will jump over entire subtrees to the result whenever possible, which can considerably speed up the operation.
    ///
    /// This method does nothing if `done` has been set to `true` by an earlier operation. It sets `done` to true
    /// if it reaches the end of the second tree.
    ///
    /// - Complexity: O(*n*) where *n* is the number of elements skipped.
    mutating func skipFromSecond(_ limit: BTreeRelativeLimit) {
        if !a.isAtEnd {
            skipFromSecond(limit.with(a.key))
        }
    }

    mutating func skipFromSecond(_ limit: Limit) {
        while !b.isAtEnd && limit.match(b.key) {
            b.nextPart(until: limit)
        }
        if b.isAtEnd {
            done = true
        }
    }

    /// Take the longest possible sequence of elements that share the same key in both trees; ignore elements from
    /// the first tree, but append elements from the second tree to the end of the result tree.
    ///
    /// This method does not care how many duplicate keys it finds for each key. For example, with
    /// `first = [0, 0, 1, 2, 2, 5, 6, 7]`, `second = [0, 1, 1, 1, 2, 2, 6, 8]`, it appends `[0, 1, 1, 1, 2, 2]`
    /// to the result, and leaves the first tree at `[5, 6, 7]` and the second at `[6, 8]`.
    ///
    /// This method recognizes nodes that are shared between the two trees, and links them to the result in one step.
    /// This can considerably speed up the operation.
    ///
    /// - Complexity: O(*n*) where *n* is the number of elements processed.
    mutating func copyCommonElementsFromSecond() {
        while !done && a.key == b.key {
            if a.node === b.node && a.node.isLeaf && a.slot == 0 && b.slot == 0 {
                /// We're at the first element of a shared subtree. Find the ancestor at which the shared subtree
                /// starts, and append it in a single step.
                ///
                /// It might happen that a shared node begins with a key that we've already fully processed in one of the trees.
                /// In this case, we cannot skip elementwise processing, since the trees are at different offsets in
                /// the shared subtree. The slot & leaf checks above & below ensure that this isn't the case.
                var key: Key
                var common: Node
                repeat {
                    key = a.node.last!.0
                    common = a.node
                    a.ascendOneLevel()
                    b.ascendOneLevel()
                } while !a.isAtEnd && !b.isAtEnd && a.node === b.node && a.slot == 0 && b.slot == 0
                builder.append(common)
                if !a.isAtEnd {
                    a.ascendToKey()
                    skipFromFirst(.including(key))
                }
                if !b.isAtEnd {
                    b.ascendToKey()
                    copyFromSecond(.including(key))
                }
                if a.isAtEnd || b.isAtEnd {
                    done = true
                }
            }
            else {
                // Process the next run of equal keys in both trees, skipping them in `first`, but copying them from `second`.
                // Note that we cannot leave matching elements in either tree, even if we reach the end of the other.
                let key = a.key
                skipFromFirst(.including(key))
                copyFromSecond(.including(key))
            }
        }
    }

    mutating func copyMatchingNumberOfCommonElementsFromSecond() {
        while !done && a.key == b.key {
            if a.node === b.node && a.node.isLeaf && a.slot == 0 && b.slot == 0 {
                /// We're at the first element of a shared subtree. Find the ancestor at which the shared subtree
                /// starts, and append it in a single step.
                ///
                /// It might happen that a shared node begins with a key that we've already fully processed in one of the trees.
                /// In this case, we cannot skip elementwise processing, since the trees are at different offsets in
                /// the shared subtree. The slot & leaf checks above & below ensure that this isn't the case.
                var common: Node
                repeat {
                    common = a.node
                    a.ascendOneLevel()
                    b.ascendOneLevel()
                } while !a.isAtEnd && !b.isAtEnd && a.node === b.node && a.slot == 0 && b.slot == 0
                builder.append(common)
                if !a.isAtEnd { a.ascendToKey() }
                if !b.isAtEnd { b.ascendToKey() }
                if a.isAtEnd || b.isAtEnd {
                    done = true
                }
            }
            else {
                // Copy one matching element from the second tree, then step forward.
                // TODO: Count the number of matching elements in a and link entire subtrees from b into the result when possible.
                builder.append(b.element)
                a.moveForward()
                b.moveForward()
                done = a.isAtEnd || b.isAtEnd
            }
        }
    }

    /// Ignore and jump over the longest possible sequence of elements that share the same key in both trees,
    /// starting at the current positions.
    ///
    /// This method does not care how many duplicate keys it finds for each key. For example, with
    /// `first = [0, 0, 1, 2, 2, 5, 6, 7]`, `second = [0, 1, 1, 1, 2, 2, 6, 8]`, it skips to
    /// `[5, 6, 7]` in the first tree, and `[6, 8]` in the second.
    ///
    /// This method recognizes nodes that are shared between the two trees, and jumps over them in one step.
    /// This can considerably speed up the operation.
    ///
    /// - Complexity: O(*n*) where *n* is the number of elements processed.
    mutating func skipCommonElements() {
        while !done && a.key == b.key {
            if a.node === b.node {
                /// We're inside a shared subtree. Find the ancestor at which the shared subtree
                /// starts, and append it in a single step.
                ///
                /// This variant doesn't care about where we're in the shared subtree.
                /// It assumes that if we ignore one set of common keys, we're ignoring all.
                var key: Key
                repeat {
                    key = a.node.last!.0
                    it_assert(a.slot == b.slot)
                    a.ascendOneLevel()
                    b.ascendOneLevel()
                    if a.isAtEnd || b.isAtEnd {
                        done = true
                    }
                } while !done && a.node === b.node
                if !a.isAtEnd {
                    a.ascendToKey()
                    skipFromFirst(.including(key))
                }
                if !b.isAtEnd {
                    b.ascendToKey()
                    skipFromSecond(.including(key))
                }
            }
            else {
                // Process the next run of equal keys in both trees, skipping them in both trees.
                // Note that we cannot leave matching elements in either tree, even if we reach the end of the other.
                let key = a.key
                skipFromFirst(.including(key))
                skipFromSecond(.including(key))
            }
        }
    }

    mutating func skipMatchingNumberOfCommonElements() {
        while !done && a.key == b.key {
            if a.node === b.node && a.node.isLeaf && a.slot == b.slot {
                /// We're at the first element of a shared subtree. Find the ancestor at which the shared subtree
                /// starts, and append it in a single step.
                ///
                /// It might happen that a shared node begins with a key that we've already fully processed in one of the trees.
                /// In this case, we cannot skip elementwise processing, since the trees are at different offsets in
                /// the shared subtree. The slot & leaf checks above & below ensure that this isn't the case.
                repeat {
                    a.ascendOneLevel()
                    b.ascendOneLevel()
                    if a.isAtEnd || b.isAtEnd {
                        done = true
                    }
                } while !done && a.node === b.node && a.slot == b.slot
                if !a.isAtEnd { a.ascendToKey() }
                if !b.isAtEnd { b.ascendToKey() }
            }
            else {
                // Skip one matching element from both trees.
                a.moveForward()
                b.moveForward()
                done = a.isAtEnd || b.isAtEnd
            }
        }
    }
}

internal enum BTreePart<Key: Comparable, Value> {
    case element((Key, Value))
    case node(BTreeNode<Key, Value>)
    case nodeRange(BTreeNode<Key, Value>, CountableRange<Int>)
}

extension BTreePart {
    var count: Int {
        switch self {
        case .element:
            return 1
        case .node(let node):
            return node.count
        case .nodeRange(let parent, let range):
            var count = range.count
            if !parent.isLeaf {
                for i in range.lowerBound ... range.upperBound {
                    count += parent.children[i].count
                }
            }
            return count
        }
    }
}

extension BTreeBuilder {
    mutating func append(_ part: BTreePart<Key, Value>) {
        switch part {
        case .element(let element):
            self.append(element)
        case .node(let node):
            self.append(node)
        case .nodeRange(let node, let range):
            self.appendWithoutCloning(Node(node: node, slotRange: range))
        }
    }
}

internal extension BTreeStrongPath {
    typealias Limit = BTreeLimit<Key>

    /// The parent of `node` and the slot of `node` in its parent, or `nil` if `node` is the root node.
    private var parent: (Node, Int)? {
        guard !_path.isEmpty else { return nil }
        return (_path.last!, _slots.last!)
    }

    /// The key following the `node` at the same slot in its parent, or `nil` if there is no such key.
    private var parentKey: Key? {
        guard let parent = self.parent else { return nil }
        guard parent.1 < parent.0.elements.count else { return nil }
        return parent.0.elements[parent.1].0
    }

    /// Move sideways `n` slots to the right, skipping over subtrees along the way.
    mutating func skipForward(_ n: Int) {
        if !node.isLeaf {
            for i in 0 ..< n {
                let s = slot! + i
                offset += node.children[s + 1].count
            }
        }
        offset += n
        slot! += n
        if offset != count {
            ascendToKey()
        }
    }

    /// Remove the deepest path component, leaving the path at the element following the node that was previously focused,
    /// or the spot after all elements if the node was the rightmost child.
    mutating func ascendOneLevel() {
        if length == 1 {
            offset = count
            slot = node.elements.count
            return
        }
        popFromSlots()
        popFromPath()
    }

    /// If this path got to a slot at the end of a node but it hasn't reached the end of the tree yet,
    /// ascend to the ancestor that holds the key corresponding to the current offset.
    mutating func ascendToKey() {
        it_assert(!isAtEnd)
        while slot == node.elements.count {
            slot = nil
            popFromPath()
        }
    }

    /// Return the next part in this tree that consists of elements less than `key`. If `inclusive` is true, also
    /// include elements matching `key`.
    /// The part returned is either a single element, or a range of elements in a node, including their associated subtrees.
    ///
    /// - Requires: The current position is not at the end of the tree, and the current key is matching the condition above.
    /// - Complexity: O(log(*n*)) where *n* is the number of elements in the returned part.
    @discardableResult
    mutating func nextPart(until limit: Limit) -> BTreePart<Key, Value> {
        it_assert(!isAtEnd && limit.match(self.key))

        // Find furthest ancestor whose entire leftmost subtree is guaranteed to consist of matching elements.
        it_assert(!isAtEnd)
        var includeLeftmostSubtree = false
        if slot == 0 && node.isLeaf {
            while slot == 0, let pk = parentKey, limit.match(pk) {
                popFromSlots()
                popFromPath()
                includeLeftmostSubtree = true
            }
        }
        if !includeLeftmostSubtree && !node.isLeaf {
            defer { moveForward() }
            return .element(self.element)
        }

        // Find range of matching elements in `node`.
        it_assert(limit.match(self.key))
        let startSlot = slot!
        var endSlot = startSlot + 1
        while endSlot < node.elements.count && limit.match(node.elements[endSlot].0) {
            endSlot += 1
        }

        // See if we can include the subtree following the last matching element.
        // This is a log(n) check but it's worth it.
        let includeRightmostSubtree = node.isLeaf || limit.match(node.children[endSlot].last!.0)
        if includeRightmostSubtree {
            defer { skipForward(endSlot - startSlot) }
            return .nodeRange(node, startSlot ..< endSlot)
        }
        // If the last subtree has non-matching elements, leave off `endSlot - 1` from the returned range.
        if endSlot == startSlot + 1 {
            let n = node.children[slot!]
            return .node(n)
        }
        defer { skipForward(endSlot - startSlot - 1) }
        return .nodeRange(node, startSlot ..< endSlot - 1)
    }
}
