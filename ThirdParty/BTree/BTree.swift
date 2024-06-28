//
//  BTree.swift
//  BTree
//
//  Created by Károly Lőrentey on 2016-02-19.
//  Copyright © 2015–2017 Károly Lőrentey.
//

/// B-trees are search trees that provide an ordered key-value store with excellent performance characteristics.
public struct BTree<Key: Comparable, Value> {
    //MARK: Definition

    public typealias Element = (Key, Value)
    internal typealias Node = BTreeNode<Key, Value>

    /// The root node.
    internal var root: Node

    internal init(_ root: Node) {
        self.root = root
    }

    /// Initialize a new B-tree with no elements.
    /// The order of the tree is set automatically based on the size of `Element` type.
    public init() {
        self.init(order: Node.defaultOrder)
    }

    /// Initialize a new B-tree with no elements.
    ///
    /// - Parameter order: The maximum number of children for tree nodes.
    public init(order: Int) {
        self.root = Node(order: order)
    }

    /// The order of this tree, i.e., the maximum number of children for tree nodes.
    public var order: Int { return root.order }
    /// The depth of this tree. Depth starts at 0 for a tree that has a single root node.
    public var depth: Int { return root.depth }
}

public extension BTree {
    //MARK: Uniquing

    /// Return `true` iff this tree holds the only strong reference to its root node.
    internal var isUnique: Bool {
        mutating get {
            return isKnownUniquelyReferenced(&root)
        }
    }

    /// Clones the root node if others also hold strong references to it, preparing it for a mutation.
    /// You must call this before modifying anything in `root`.
    ///
    /// - SeeAlso: `BTreeNode.makeChildUnique(_:)` for the equi
    internal mutating func makeUnique() {
        guard !isUnique else { return }
        root = root.clone()
    }
}

extension BTree: Sequence {
    //MARK: Sequence
    
    public typealias Iterator = BTreeIterator<Key, Value>

    /// Returns true iff this tree has no elements.
    public var isEmpty: Bool { return root.count == 0 }

    /// Returns an iterator over the elements of this B-tree. Elements are sorted by key.
    public func makeIterator() -> Iterator {
        return Iterator(BTreeStrongPath(root: root, offset: 0))
    }

    /// Returns an iterator starting at a specific index.
    public func makeIterator(from index: Index) -> Iterator {
        index.state.expectRoot(root)
        return Iterator(BTreeStrongPath(root: root, slotsFrom: index.state))
    }

    /// Returns an iterator starting at a specific offset.
    public func makeIterator(fromOffset offset: Int) -> Iterator {
        return Iterator(BTreeStrongPath(root: root, offset: offset))
    }

    /// Returns an iterator starting at the element with the specified key.
    /// If the tree contains no such element, the generator is positioned on the first element with a larger key.
    /// If there are multiple elements with the same key, `selector` indicates which matching element to find.
    public func makeIterator(from key: Key, choosing selector: BTreeKeySelector = .any) -> Iterator {
        return Iterator(BTreeStrongPath(root: root, key: key, choosing: selector))
    }

    /// Call `body` on each element in self in the same order as a for-in loop.
    public func forEach(_ body: (Element) throws -> ()) rethrows {
        try root.forEach(body)
    }

    /// A version of `forEach` that allows `body` to interrupt iteration by returning `false`.
    ///
    /// - Returns: `true` iff `body` returned true for all elements in the tree.
    @discardableResult
    public func forEach(_ body: (Element) throws -> Bool) rethrows -> Bool {
        return try root.forEach(body)
    }
}

extension BTree: BidirectionalCollection {
    //MARK: CollectionType
    
    public typealias Index = BTreeIndex<Key, Value>
    public typealias SubSequence = BTree<Key, Value>

    /// The index of the first element of this tree. Elements are sorted by key.
    ///
    /// - Complexity: O(log(`count`))
    public var startIndex: Index {
        return Index(BTreeWeakPath(startOf: root))
    }

    /// The index after the last element of this tree. (Equals `startIndex` when the tree is empty.)
    ///
    /// - Complexity: O(1)
    public var endIndex: Index {
        return Index(BTreeWeakPath(endOf: root))
    }

    /// The number of elements in this tree.
    public var count: Int {
        return root.count
    }

    /// Returns the element at `index`.
    ///
    /// - Complexity: O(1)
    public subscript(index: Index) -> Element {
        get {
            index.state.expectRoot(self.root)
            return index.state.element
        }
    }

    /// Returns a tree consisting of elements in the specified range of indexes.
    ///
    /// - Complexity: O(log(`count`))
    public subscript(range: Range<Index>) -> BTree<Key, Value> {
        get {
            return subtree(with: range)
        }
    }

    internal func checkIndex(_ index: Index) {
        index.state.expectRoot(self.root)
    }

    /// Returns the successor of the given index.
    ///
    /// - Requires: `index` is a valid index of this tree and it is not equal to `endIndex`.
    /// - Complexity: Amortized O(1).
    public func index(after index: Index) -> Index {
        checkIndex(index)
        var result = index
        result.increment()
        return result
    }

    /// Replaces the given index with its successor.
    ///
    /// - Requires: `index` is a valid index of this tree and it is not equal to `endIndex`.
    /// - Complexity: Amortized O(1).
    public func formIndex(after index: inout Index) {
        checkIndex(index)
        index.increment()
    }

    /// Returns the predecessor of the given index.
    ///
    /// - Requires: `index` is a valid index of this tree and it is not equal to `startIndex`.
    /// - Complexity: Amortized O(1).
    public func index(before index: Index) -> Index {
        checkIndex(index)
        var result = index
        result.decrement()
        return result
    }

    /// Replaces the given index with its predecessor.
    ///
    /// - Requires: `index` is a valid index of this tree and it is not equal to `startIndex`.
    /// - Complexity: Amortized O(1).
    public func formIndex(before index: inout Index) {
        checkIndex(index)
        index.decrement()
    }

    /// Returns an index that is the specified distance from the given index.
    ///
    /// - Requires: `index` must be a valid index of this tree.
    ///              If `n` is positive, it must not exceed the distance from `index` to `endIndex`. 
    ///              If `n` is negative, it must not be less than the distance from `index` to `startIndex`.
    /// - Complexity: O(log(*count*)) where *count* is the number of elements in the tree.
    public func index(_ i: Index, offsetBy n: Int) -> Index {
        checkIndex(i)
        var result = i
        result.advance(by: n)
        return result
    }

    /// Offsets the given index by the specified distance.
    ///
    /// - Requires: `index` must be a valid index of this tree.
    ///              If `n` is positive, it must not exceed the distance from `index` to `endIndex`.
    ///              If `n` is negative, it must not be less than the distance from `index` to `startIndex`.
    /// - Complexity: O(log(*count*)) where *count* is the number of elements in the tree.
    public func formIndex(_ i: inout Index, offsetBy n: Int) {
        checkIndex(i)
        i.advance(by: n)
    }

    /// Returns an index that is the specified distance from the given index, unless that distance is beyond a given limiting index.
    ///
    /// - Requires: `index` and `limit` must be valid indices of this tree. The operation must not advance the index beyond `endIndex` or before `startIndex`.
    /// - Complexity: O(log(*count*)) where *count* is the number of elements in the tree.
    public func index(_ i: Index, offsetBy n: Int, limitedBy limit: Index) -> Index? {
        checkIndex(i)
        checkIndex(limit)
        let d = self.distance(from: i, to: limit)
        if d > 0 ? d < n : d > n {
            return nil
        }
        var result = i
        result.advance(by: n)
        return result
    }

    /// Offsets the given index by the specified distance, or so that it equals the given limiting index.
    ///
    /// - Requires: `index` and `limit` must be valid indices of this tree. The operation must not advance the index beyond `endIndex` or before `startIndex`.
    /// - Complexity: O(log(*count*)) where *count* is the number of elements in the tree.
    @discardableResult
    public func formIndex(_ i: inout Index, offsetBy n: Int, limitedBy limit: Index) -> Bool {
        checkIndex(i)
        checkIndex(limit)
        return i.advance(by: n, limitedBy: limit)
    }


    /// Returns the distance between two indices.
    ///
    /// - Requires: `start` and `end` must be valid indices in this tree.
    /// - Complexity: O(1)
    public func distance(from start: Index, to end: Index) -> Int {
        checkIndex(start)
        checkIndex(end)
        return end.state.offset - start.state.offset
    }
}

/// When the tree contains multiple elements with the same key, you can use a key selector to specify
/// which matching element you want to work with.
public enum BTreeKeySelector {
    /// Look for the first element that matches the key.
    ///
    /// Insertions with `.first` insert the new element before existing matches.
    /// Removals remove the first matching element.
    case first

    /// Look for the last element that matches the key.
    ///
    /// Insertions with `.last` insert the new element after existing matches.
    /// Removals remove the last matching element.
    case last

    /// Look for the first element that has a greater key.
    ///
    /// For insertions and removals, this works the same as `.last`.
    case after

    /// Accept any element that matches the key.
    /// This can be faster when there are lots of duplicate keys: the search may stop before reaching a leaf node.
    ///
    /// (This may also happen for distinct keys, but since the vast majority of elements are stored in leaf nodes,
    /// its effect is not very significant.)
    case any
}

public extension BTree {
    //MARK: Lookups

    /// Returns the first element in this tree, or `nil` if the tree is empty.
    ///
    /// - Complexity: O(log(`count`))
    var first: Element? {
        return root.first
    }

    /// Returns the last element in this tree, or `nil` if the tree is empty.
    ///
    /// - Complexity: O(log(`count`))
    var last: Element? {
        return root.last
    }

    /// Returns the element at `offset`.
    ///
    /// - Requires: `offset >= 0 && offset < count`
    /// - Complexity: O(log(`count`))
    func element(atOffset offset: Int) -> Element {
        precondition(offset >= 0 && offset < count)
        var offset = offset
        var node = root
        while !node.isLeaf {
            let slot = node.slot(atOffset: offset)
            if slot.match {
                return node.elements[slot.index]
            }
            let child = node.children[slot.index]
            offset -= slot.offset - child.count
            node = child
        }
        return node.elements[offset]
    }

    /// Returns the value of an element of this tree with the specified key, or `nil` if there is no such element.
    /// If there are multiple elements with the same key, `selector` indicates which matching element to find.
    ///
    /// - Complexity: O(log(`count`))
    func value(of key: Key, choosing selector: BTreeKeySelector = .any) -> Value? {
        switch selector {
        case .any:
            var node = root
            while true {
                let slot = node.slot(of: key, choosing: .first)
                if let m = slot.match {
                    return node.elements[m].1
                }
                if node.isLeaf {
                    break
                }
                node = node.children[slot.descend]
            }
            return nil
        default:
            var node = root
            var lastmatch: Value? = nil
            while true {
                let slot = node.slot(of: key, choosing: selector)
                if let m = slot.match {
                    lastmatch = node.elements[m].1
                }
                if node.isLeaf {
                    break
                }
                node = node.children[slot.descend]
            }
            return lastmatch
        }
    }

    /// Returns an index to an element in this tree with the specified key, or `nil` if there is no such element.
    /// If there are multiple elements with the same key, `selector` indicates which matching element to find.
    ///
    /// This method never returns `endIndex`.
    ///
    /// - Complexity: O(log(`count`))
    func index(forKey key: Key, choosing selector: BTreeKeySelector = .any) -> Index? {
        let path = BTreeWeakPath(root: root, key: key, choosing: selector)
        guard !path.isAtEnd && (selector == .after || path.key == key) else { return nil }
        return Index(path)
    }

    /// Returns an index that points to the position where a new element with the specified key would
    /// be inserted into this tree. This is useful for finding the nearest element above or below `key`.
    ///
    /// The returned index may be `endIndex` if the tree is empty or `key` is greater than or equal to the key of the largest element.
    ///
    /// - Complexity: O(log(`count`))
    func index(forInserting key: Key, at selector: BTreeKeySelector = .any) -> Index {
        let path = BTreeWeakPath(root: root, key: key, choosing: selector == .last ? .after : selector)
        return Index(path)
    }

    /// Returns the offset of the first element in this tree with the specified key, or `nil` if there is no such element.
    /// If there are multiple elements with the same key, `selector` indicates which matching element to find.
    ///
    /// - Complexity: O(log(`count`))
    func offset(forKey key: Key, choosing selector: BTreeKeySelector = .any) -> Int? {
        var node = root
        var offset = 0
        var match: Int? = nil
        while !node.isLeaf {
            let slot = node.slot(of: key, choosing: selector)
            let child = node.children[slot.descend]
            if let m = slot.match {
                let p = node.offset(ofSlot: m)
                match = offset + p
                offset += p - (m == slot.descend ? node.children[m].count : 0)
            }
            else {
                offset += node.offset(ofSlot: slot.descend) - child.count
            }
            node = child
        }
        let slot = node.slot(of: key, choosing: selector)
        if let m = slot.match {
            return offset + m
        }
        return match
    }

    /// Returns the offset of the element at `index`.
    ///
    /// - Complexity: O(1)
    func offset(of index: Index) -> Int {
        index.state.expectRoot(root)
        return index.state.offset
    }

    /// Returns the index of the element at `offset`.
    ///
    /// - Requires: `offset >= 0 && offset <= count`
    /// - Complexity: O(log(`count`))
    func index(ofOffset offset: Int) -> Index {
        return Index(BTreeWeakPath(root: root, offset: offset))
    }
}


extension BTree {
    //MARK: Editing
    
    /// Edit the tree at a path that is to be discovered on the way down, ensuring that all nodes on the path are
    /// uniquely held by this tree. 
    /// This is a simple (but not easy, alas) interface that allows implementing basic editing operations using 
    /// recursion without adding a separate method on `BTreeNode` for each operation.
    ///
    /// Editing is split into two phases: the descent phase and the ascend phase. 
    ///
    /// - During descent, the `descend` closure is called repeatedly to get the next child slot to drill down into.
    ///   When the closure returns `nil`, the phase stops and the ascend phase begins.
    /// - During ascend, the `ascend` closure is called for each node for which `descend` returned non-nil, in reverse
    ///   order.
    ///
    /// - Parameter descend: A closure that, when given a node, returns the child slot toward which the editing should
    ///   continue descending, or `nil` if the descent should stop. The closure may set outside references to the 
    ///   node it gets, and may modify the node as it likes; however, it shouldn't modify anything in the tree outside
    ///   the node's subtree, and it should not set outside references to the node's descendants.
    /// - Parameter ascend: A closure that processes a step of ascending back towards the root. It receives a parent node
    ///   and the child slot from which this step is ascending. The closure may set outside references to the
    ///   node it gets, and may modify the subtree as it likes; however, it shouldn't modify anything in the tree outside
    ///   the node's subtree.
    internal mutating func edit(descend: (Node) -> Int?, ascend: (Node, Int) -> Void) {
        makeUnique()
        root.edit(descend: descend, ascend: ascend)
    }
}

extension BTreeNode {
    internal func edit(descend: (Node) -> Int?, ascend: (Node, Int) -> Void) {
        guard let slot = descend(self) else { return }
        do {
            let child = makeChildUnique(slot)
            child.edit(descend: descend, ascend: ascend)
        }
        ascend(self, slot)
    }
}

extension BTree {
    //MARK: Editing

    /// Set the value at `offset`, and return the value originally stored there.
    ///
    /// - Requires: `offset < count`
    /// - Note: When you need to perform multiple modifications on the same tree,
    ///   `BTreeCursor` provides an alternative interface that's often more efficient.
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func setValue(atOffset offset: Int, to value: Value) -> Value {
        precondition(offset >= 0 && offset < count)
        makeUnique()
        var pos = count - offset
        var old: Value? = nil
        edit(
            descend: { node in
                let slot = node.slot(atOffset: node.count - pos)
                if !slot.match {
                    // Continue descending.
                    pos -= node.count - slot.offset
                    return slot.index
                }
                old = node.elements[slot.index].1
                node.elements[slot.index].1 = value
                return nil
            },
            ascend: { node, slot in
            }
        )
        return old!
    }

    //MARK: Insertion
    
    /// Insert the specified element into the tree at `offset`.
    ///
    /// - Requires: The key of the supplied element does not violate the B-tree's ordering requirement.
    ///   (This is only verified in non-optimized builds.)
    /// - Note: When you need to perform multiple modifications on the same tree,
    ///   `BTreeCursor` provides an alternative interface that's often more efficient.
    /// - Complexity: O(log(`count`))
    public mutating func insert(_ element: Element, atOffset offset: Int) {
        precondition(offset >= 0 && offset <= count)
        makeUnique()
        var pos = count - offset
        var splinter: BTreeSplinter<Key, Value>? = nil
        var element = element
        edit(
            descend: { node in
                let slot = node.slot(atOffset: node.count - pos)
                assert(slot.index == 0 || node.elements[slot.index - 1].0 <= element.0)
                assert(slot.index == node.elements.count || node.elements[slot.index].0 >= element.0)
                if !slot.match {
                    // Continue descending.
                    pos -= node.count - slot.offset
                    return slot.index
                }
                if node.isLeaf {
                    // Found the insertion point. Insert, then start ascending.
                    node.insert(element, inSlot: slot.index)
                    if node.isTooLarge {
                        splinter = node.split()
                    }
                    return nil
                }
                // For internal nodes, put the new element in place of the old at the same offset,
                // then continue descending toward the next offset, inserting the old element.
                element = node.setElement(inSlot: slot.index, to: element)
                pos = node.children[slot.index + 1].count
                return slot.index + 1
            },
            ascend: { node, slot in
                node.count += 1
                if let s = splinter {
                    node.insert(s, inSlot: slot)
                    splinter = node.isTooLarge ? node.split() : nil
                }
            }
        )
        if let s = splinter {
            root = Node(left: root, separator: s.separator, right: s.node)
        }
    }

    /// Insert `element` into the tree as a new element.
    /// If the tree already contains elements with the same key, `selector` specifies where to put the new element.
    ///
    /// - Note: When you need to perform multiple modifications on the same tree,
    ///   `BTreeCursor` provides an alternative interface that's often more efficient.
    /// - Complexity: O(log(`count`))
    public mutating func insert(_ element: Element, at selector: BTreeKeySelector = .any) {
        makeUnique()
        let selector: BTreeKeySelector = (selector == .first ? .first : .after)
        var splinter: BTreeSplinter<Key, Value>? = nil
        edit(
            descend: { node in
                let slot = node.slot(of: element.0, choosing: selector)
                if !node.isLeaf {
                    return slot.descend
                }
                node.insert(element, inSlot: slot.descend)
                if node.isTooLarge {
                    splinter = node.split()
                }
                return nil
            },
            ascend: { node, slot in
                node.count += 1
                if let s = splinter {
                    node.insert(s, inSlot: slot)
                    splinter = node.isTooLarge ? node.split() : nil
                }
            }
        )
        if let s = splinter {
            root = Node(left: root, separator: s.separator, right: s.node)
        }
    }

    /// Insert `element` into the tree, replacing an element with the same key if there is one.
    /// If the tree already contains multiple elements with the same key, `selector` specifies which one to replace.
    ///
    /// - Note: When you need to perform multiple modifications on the same tree,
    ///   `BTreeCursor` provides an alternative interface that's often more efficient.
    /// - Returns: The element previously stored in the tree at the specified key.
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func insertOrReplace(_ element: Element, at selector: BTreeKeySelector = .any) -> Element? {
        let selector = (selector == .after ? .last : selector)
        makeUnique()
        var old: Element? = nil
        var match: (node: Node, slot: Int)? = nil
        var splinter: BTreeSplinter<Key, Value>? = nil
        edit(
            descend: { node in
                let slot = node.slot(of: element.0, choosing: selector)
                if node.isLeaf {
                    if let m = slot.match {
                        // We found the element we want to replace.
                        old = node.setElement(inSlot: m, to: element)
                        match = nil
                    }
                    else if old == nil && match == nil {
                        // The tree contains no matching elements; insert a new one.
                        node.insert(element, inSlot: slot.descend)
                        if node.isTooLarge {
                            splinter = node.split()
                        }
                    }
                    return nil
                }
                if let m = slot.match {
                    if selector == .any {
                        // When we don't care about which element to replace, we stop the descent at the first match.
                        old = node.setElement(inSlot: m, to: element)
                        return nil
                    }
                    // Otherwise remember this match and replace it during ascend if it's the last one.
                    match = (node, m)
                }
                return slot.descend
            },
            ascend: { node, slot in
                if let m = match {
                    // We're looking for the node that contains the last match.
                    if m.node === node {
                        // Found it; replace the matching element and cancel the search.
                        old = node.setElement(inSlot: m.slot, to: element)
                        match = nil
                    }
                }
                else if old == nil {
                    // We're ascending from an insertion.
                    node.count += 1
                    if let s = splinter {
                        node.insert(s, inSlot: slot)
                        splinter = node.isTooLarge ? node.split() : nil
                    }
                }
            }
        )
        if let s = splinter {
            root = Node(left: root, separator: s.separator, right: s.node)
        }
        return old
    }

    /// Find and return an element that has the same key as `element` if there is one, 
    /// or insert `element` in the tree and return nil.
    ///
    /// If the tree already contains multiple elements with the same key, `selector` specifies which one to return.
    ///
    /// - Note: When you need to perform multiple modifications on the same tree,
    ///   `BTreeCursor` provides an alternative interface that's often more efficient.
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func insertOrFind(_ element: Element, at selector: BTreeKeySelector = .any) -> Element? {
        let selector = (selector == .after ? .last : selector)
        makeUnique()
        var old: Element? = nil
        var match: (node: Node, slot: Int)? = nil
        var splinter: BTreeSplinter<Key, Value>? = nil
        edit(
            descend: { node in
                let slot = node.slot(of: element.0, choosing: selector)
                if node.isLeaf {
                    if let m = slot.match {
                        // We found the element we want.
                        old = node.elements[m]
                        match = nil
                    }
                    else if old == nil && match == nil {
                        // The tree contains no matching elements; insert a new one.
                        node.insert(element, inSlot: slot.descend)
                        if node.isTooLarge {
                            splinter = node.split()
                        }
                    }
                    return nil
                }
                if let m = slot.match {
                    if selector == .any {
                        // When we don't care about which element to find, we stop the descent at the first match.
                        old = node.elements[m]
                        return nil
                    }
                    // Otherwise remember this match and save it during ascend if it's the last one.
                    match = (node, m)
                }
                return slot.descend
            },
            ascend: { node, slot in
                if let m = match {
                    // We're looking for the node that contains the last match.
                    if m.node === node {
                        // Found it; cancel the search.
                        old = node.elements[m.slot]
                        match = nil
                    }
                }
                else if old == nil {
                    // We're ascending from an insertion.
                    node.count += 1
                    if let s = splinter {
                        node.insert(s, inSlot: slot)
                        splinter = node.isTooLarge ? node.split() : nil
                    }
                }
            }
        )
        if let s = splinter {
            root = Node(left: root, separator: s.separator, right: s.node)
        }
        return old
    }
}

extension BTree {
    //MARK: Removal
    
    /// Remove and return the first element.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func removeFirst() -> Element {
        return remove(atOffset: 0)
    }

    /// Remove and return the last element.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func removeLast() -> Element {
        return remove(atOffset: count - 1)
    }

    /// Remove and return the first element, or return `nil` if the tree is empty.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func popFirst() -> Element? {
        guard !isEmpty else { return nil }
        return remove(atOffset: 0)
    }

    /// Remove and return the first element, or return `nil` if the tree is empty.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func popLast() -> Element? {
        guard !isEmpty else { return nil }
        return remove(atOffset: count - 1)
    }

    /// Remove the first `n` elements from this tree.
    ///
    /// - Complexity: O(log(`count`) + `n`)
    public mutating func removeFirst(_ n: Int) {
        precondition(n >= 0 && n <= count)
        switch n {
        case 0: break
        case 1: removeFirst()
        case count: removeAll()
        default:
            self = suffix(count - n)
        }
    }

    /// Remove the last `n` elements from this tree.
    ///
    /// - Complexity: O(log(`count`) + `n`)
    public mutating func removeLast(_ n: Int) {
        precondition(n >= 0 && n <= count)
        switch n {
        case 0: break
        case 1: removeLast()
        case count: removeAll()
        default:
            self = prefix(count - n)
        }
    }

    /// Remove and return the element at the specified offset.
    ///
    /// - Note: When you need to perform multiple modifications on the same tree,
    ///   `BTreeCursor` provides an alternative interface that's often more efficient.
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func remove(atOffset offset: Int) -> Element {
        precondition(offset >= 0 && offset < count)
        makeUnique()
        var pos = count - offset
        var matching: (node: Node, slot: Int)? = nil
        var old: Element? = nil
        edit(
            descend: { node in
                let slot = node.slot(atOffset: node.count - pos)
                if !slot.match {
                    // No match yet; continue descending.
                    assert(!node.isLeaf)
                    pos -= node.count - slot.offset
                    return slot.index
                }
                if node.isLeaf {
                    // The offset we're looking for is in a leaf node; we can remove it directly.
                    old = node.remove(slot: slot.index)
                    return nil
                }
                // When the offset happens to fall in an internal node, remember the match and continue
                // removing the next offset (which is guaranteed to be in a leaf node).
                // We'll replace the removed element with this one during the ascend.
                matching = (node, slot.index)
                pos = node.children[slot.index + 1].count
                return slot.index + 1
            },
            ascend: { node, slot in
                node.count -= 1
                if let m = matching, m.node === node {
                    // We've removed the element at the next offset; put it back in place of the
                    // element we actually want to remove.
                    old = node.setElement(inSlot: m.slot, to: old!)
                    matching = nil
                }
                if node.children[slot].isTooSmall {
                    node.fixDeficiency(slot)
                }
            }
        )
        if root.children.count == 1 {
            assert(root.elements.count == 0)
            root = root.children[0]
        }
        return old!
    }

    /// Remove an element with the specified key, if it exists.
    /// If there are multiple elements with the same key, `selector` indicates which matching element to remove.
    ///
    /// - Returns: The removed element, or `nil` if there was no element with `key` in the tree.
    /// - Note: When you need to perform multiple modifications on the same tree,
    ///   `BTreeCursor` provides an alternative interface that's often more efficient.
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func remove(_ key: Key, at selector: BTreeKeySelector = .any) -> Element? {
        let selector = (selector == .after ? .last : selector)
        makeUnique()
        var old: Element? = nil
        var matching: (node: Node, slot: Int)? = nil
        edit(
            descend: { node in
                let slot = node.slot(of: key, choosing: selector)
                if node.isLeaf {
                    if let m = slot.match {
                        old = node.remove(slot: m)
                        matching = nil
                    }
                    else if matching != nil {
                        old = node.remove(slot: slot.descend == node.elements.count ? slot.descend - 1 : slot.descend)
                    }
                    return nil
                }
                if let m = slot.match {
                    matching = (node, m)
                }
                return slot.descend
            },
            ascend: { node, slot in
                if let o = old {
                    node.count -= 1
                    if let m = matching, m.node === node {
                        old = node.setElement(inSlot: m.slot, to: o)
                        matching = nil
                    }
                    if node.children[slot].isTooSmall {
                        node.fixDeficiency(slot)
                    }
                }
            }
        )
        if root.children.count == 1 {
            assert(root.elements.count == 0)
            root = root.children[0]
        }
        return old
    }

    /// Remove and return the element referenced by the given index.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public mutating func remove(at index: Index) -> Element {
        return withCursor(at: index) { cursor in
            return cursor.remove()
        }
    }

    /// Remove all elements from this tree.
    public mutating func removeAll() {
        root = Node(order: root.order)
    }
}

extension BTree {
    //MARK: Subtree extraction
    
    /// Returns a subtree containing the initial `maxLength` elements in this tree.
    ///
    /// If `maxLength` exceeds `self.count`, the result contains all the elements of `self`.
    ///
    /// - Complexity: O(log(`count`))
    public func prefix(_ maxLength: Int) -> BTree {
        precondition(maxLength >= 0)
        if maxLength == 0 {
            return BTree(order: order)
        }
        if maxLength >= count {
            return self
        }
        return BTreeStrongPath(root: root, offset: maxLength).prefix()
    }

    /// Returns a subtree containing all but the last `n` elements.
    /// If `n` exceeds the number of elements in the tree, the result is an empty tree.
    ///
    /// - Complexity: O(log(`count`))
    public func dropLast(_ n: Int) -> BTree {
        precondition(n >= 0)
        return prefix(Swift.max(0, count - n))
    }

    /// Returns a subtree containing all elements before the specified index.
    ///
    /// - Complexity: O(log(`count`))
    public func prefix(upTo end: Index) -> BTree {
        end.state.expectRoot(root)
        if end.state.isAtEnd {
            return self
        }
        return end.state.prefix()
    }

    /// Returns a subtree containing all elements whose key is less than `key`.
    ///
    /// - Complexity: O(log(`count`))
    public func prefix(upTo end: Key) -> BTree {
        let path = BTreeStrongPath(root: root, key: end, choosing: .first)
        if path.isAtEnd {
            return self
        }
        return path.prefix()
    }

    /// Returns a subtree containing all elements at or before the specified index.
    ///
    /// - Complexity: O(log(`count`))
    public func prefix(through stop: Index) -> BTree {
        return prefix(upTo: self.index(after: stop))
    }

    /// Returns a subtree containing all elements whose key is less than or equal to `key`.
    ///
    /// - Complexity: O(log(`count`))
    public func prefix(through stop: Key) -> BTree {
        let path = BTreeStrongPath(root: root, key: stop, choosing: .after)
        if path.isAtEnd {
            return self
        }
        return path.prefix()
    }

    /// Returns a tree containing the final `maxLength` elements in this tree.
    ///
    /// If `maxLength` exceeds `self.count`, the result contains all the elements of `self`.
    ///
    /// - Complexity: O(log(`count`))
    public func suffix(_ maxLength: Int) -> BTree {
        precondition(maxLength >= 0)
        if maxLength == 0 {
            return BTree(order: order)
        }
        if maxLength >= count {
            return self
        }
        return BTreeStrongPath(root: root, offset: count - maxLength - 1).suffix()
    }

    /// Returns a subtree containing all but the first `n` elements.
    /// If `n` exceeds the number of elements in the tree, the result is an empty tree.
    ///
    /// - Complexity: O(log(`count`))
    public func dropFirst(_ n: Int) -> BTree {
        precondition(n >= 0)
        return suffix(Swift.max(0, count - n))
    }

    /// Returns a subtree containing all elements at or after the specified index.
    ///
    /// - Complexity: O(log(`count`))
    public func suffix(from start: Index) -> BTree {
        start.state.expectRoot(root)
        if start.state.offset == 0 {
            return self
        }
        var state = start.state
        state.moveBackward()
        return state.suffix()
    }

    /// Returns a subtree containing all elements whose key is greater than or equal to `key`.
    ///
    /// - Complexity: O(log(`count`))
    public func suffix(from start: Key) -> BTree {
        var path = BTreeStrongPath(root: root, key: start, choosing: .first)
        if path.isAtStart {
            return self
        }
        path.moveBackward()
        return path.suffix()
    }

    /// Return a subtree consisting of elements in the specified range of indexes.
    ///
    /// - Complexity: O(log(`count`))
    public func subtree(with range: Range<Index>) -> BTree<Key, Value> {
        range.lowerBound.state.expectRoot(root)
        range.upperBound.state.expectRoot(root)
        let start = range.lowerBound.state.offset
        let end = range.upperBound.state.offset
        precondition(0 <= start && start <= end && end <= self.count)
        if start == end {
            return BTree(order: self.order)
        }
        if start == 0 {
            return prefix(upTo: range.upperBound)
        }
        return suffix(from: range.lowerBound).prefix(end - start)
    }

    /// Return a subtree consisting of elements in the specified range of offsets.
    ///
    /// - Complexity: O(log(`count`))
    public func subtree(withOffsets offsets: Range<Int>) -> BTree<Key, Value> {
        precondition(offsets.lowerBound >= 0 && offsets.upperBound <= count)
        if offsets.count == 0 {
            return BTree(order: order)
        }
        return dropFirst(offsets.lowerBound).prefix(offsets.count)
    }

    /// Return a subtree consisting of all elements with keys greater than or equal to `start` but less than `end`.
    ///
    /// - Complexity: O(log(`count`))
    public func subtree(from start: Key, to end: Key) -> BTree<Key, Value> {
        precondition(start <= end)
        return suffix(from: start).prefix(upTo: end)
    }

    /// Return a submap consisting of all elements with keys greater than or equal to `start` but less than or equal to `end`.
    ///
    /// - Complexity: O(log(`count`))
    public func subtree(from start: Key, through stop: Key) -> BTree<Key, Value> {
        precondition(start <= stop)
        return suffix(from: start).prefix(through: stop)
    }
}
