//
//  BTreeNode.swift
//  BTree
//
//  Created by Károly Lőrentey on 2016-01-13.
//  Copyright © 2015–2017 Károly Lőrentey.
//

// `bTreeNodeSize` is the maximum size (in bytes) of the keys in a single, fully loaded B-tree node.
// This is related to the order of the B-tree, i.e., the maximum number of children of an internal node.
//
// Common sense indicates (and benchmarking verifies) that the fastest B-tree order depends on `strideof(key)`:
// doubling the size of the key roughly halves the optimal order. So there is a certain optimal overall node size that
// is independent of the key; this value is supposed to be that size.
//
// Obviously, the optimal node size depends on the hardware we're running on.
// Benchmarks performed on various systems (Apple A5X, A8X, A9; Intel Core i5 Sandy Bridge, Core i7 Ivy Bridge) 
// indicate that 16KiB is a good overall choice.
// (This may be related to the size of the L1 cache, which is frequently 16kiB or 32kiB.)
//
// It is not a good idea to use powers of two as the B-tree order, as that would lead to Array reallocations just before
// a node is split. A node size that's just below 2^n seems like a good choice.
internal let bTreeNodeSize = 16383

//MARK: BTreeNode definition

/// A node in an in-memory B-tree data structure, efficiently mapping `Comparable` keys to arbitrary values.
/// Iterating over the elements in a B-tree returns them in ascending order of their keys.
internal final class BTreeNode<Key: Comparable, Value> {
    typealias Iterator = BTreeIterator<Key, Value>
    typealias Element = Iterator.Element
    typealias Node = BTreeNode<Key, Value>

    /// FIXME: Allocate keys/values/children in a single buffer

    /// The elements stored in this node, sorted by key.
    internal var elements: Array<Element>
    /// An empty array (when this is a leaf), or `elements.count + 1` child nodes (when this is an internal node).
    internal var children: Array<BTreeNode>

    /// The number of elements in this B-tree.
    internal var count: Int

    /// The order of this B-tree. An internal node will have at most this many children.
    internal let _order: Int32
    /// The depth of this B-tree.
    internal let _depth: Int32

    internal var depth: Int { return numericCast(_depth) }
    internal var order: Int { return numericCast(_order) }

    internal init(order: Int, elements: Array<Element>, children: Array<BTreeNode>, count: Int) {
        assert(children.count == 0 || elements.count == children.count - 1)
        self._order = numericCast(order)
        self.elements = elements
        self.children = children
        self.count = count
        self._depth = (children.count == 0 ? 0 : children[0]._depth + 1)
        assert(children.firstIndex { $0._depth + (1 as Int32) != self._depth } == nil)
    }
}

//MARK: Convenience initializers

extension BTreeNode {
    static var defaultOrder: Int {
        return Swift.max(bTreeNodeSize / MemoryLayout<Element>.stride, 8)
    }

    convenience init(order: Int = Node.defaultOrder) {
        self.init(order: order, elements: [], children: [], count: 0)
    }

    internal convenience init(left: Node, separator: (Key, Value), right: Node) {
        assert(left.order == right.order)
        assert(left.depth == right.depth)
        self.init(
            order: left.order,
            elements: [separator],
            children: [left, right],
            count: left.count + 1 + right.count)
    }

    internal convenience init(node: BTreeNode, slotRange: CountableRange<Int>) {
        if node.isLeaf {
            let elements = Array(node.elements[slotRange])
            self.init(order: node.order, elements: elements, children: [], count: elements.count)
        }
        else if slotRange.count == 0 {
            let n = node.children[slotRange.lowerBound]
            self.init(order: n.order, elements: n.elements, children: n.children, count: n.count)
        }
        else {
            let elements = Array(node.elements[slotRange])
            let children = Array(node.children[slotRange.lowerBound ... slotRange.upperBound])
            let count = children.reduce(elements.count) { $0 + $1.count }
            self.init(order: node.order, elements: elements, children: children, count: count)
        }
    }
}

//MARK: Uniqueness

extension BTreeNode {
    @discardableResult
    func makeChildUnique(_ index: Int) -> BTreeNode {
        guard !isKnownUniquelyReferenced(&children[index]) else { return children[index] }
        let clone = children[index].clone()
        children[index] = clone
        return clone
    }

    func clone() -> BTreeNode {
        return BTreeNode(order: order, elements: elements, children: children, count: count)
    }
}

//MARK: Basic limits and properties

extension BTreeNode {
    internal var maxChildren: Int { return order }
    internal var minChildren: Int { return (maxChildren + 1) / 2 }
    internal var maxKeys: Int { return maxChildren - 1 }
    internal var minKeys: Int { return minChildren - 1 }

    internal var isLeaf: Bool { return depth == 0 }
    internal var isTooSmall: Bool { return elements.count < minKeys }
    internal var isTooLarge: Bool { return elements.count > maxKeys }
    internal var isBalanced: Bool { return elements.count >= minKeys && elements.count <= maxKeys }
}

//MARK: Sequence

extension BTreeNode: Sequence {
    var isEmpty: Bool { return count == 0 }

    func makeIterator() -> Iterator {
        return BTreeIterator(BTreeStrongPath(root: self, offset: 0))
    }

    /// Call `body` on each element in self in the same order as a for-in loop.
    func forEach(_ body: (Element) throws -> ()) rethrows {
        if isLeaf {
            for element in elements {
                try body(element)
            }
        }
        else {
            for i in 0 ..< elements.count {
                try children[i].forEach(body)
                try body(elements[i])
            }
            try children[elements.count].forEach(body)
        }
    }

    /// A version of `forEach` that allows `body` to interrupt iteration by returning `false`.
    /// 
    /// - Returns: `true` iff `body` returned true for all elements in the tree.
    @discardableResult
    func forEach(_ body: (Element) throws -> Bool) rethrows -> Bool {
        if isLeaf {
            for element in elements {
                guard try body(element) else { return false }
            }
        }
        else {
            for i in 0 ..< elements.count {
                guard try children[i].forEach(body) else { return false }
                guard try body(elements[i]) else { return false }
            }
            guard try children[elements.count].forEach(body) else { return false }
        }
        return true
    }

}

//MARK: Slots

extension BTreeNode {
    internal func setElement(inSlot slot: Int, to element: Element) -> Element {
        let old = elements[slot]
        elements[slot] = element
        return old
    }

    internal func insert(_ element: Element, inSlot slot: Int) {
        elements.insert(element, at: slot)
        count += 1
    }

    internal func append(_ element: Element) {
        elements.append(element)
        count += 1
    }

    @discardableResult
    internal func remove(slot: Int) -> Element {
        count -= 1
        return elements.remove(at: slot)
    }

    /// Does one step toward looking up an element with `key`, returning the slot index of a direct match (if any), 
    /// and the slot index to use to continue descending.
    ///
    /// - Complexity: O(log(order))
    @inline(__always)
    internal func slot(of key: Key, choosing selector: BTreeKeySelector = .first) -> (match: Int?, descend: Int) {
        switch selector {
        case .first, .any:
            var start = 0
            var end = elements.count
            while start < end {
                let mid = start + (end - start) / 2
                if elements[mid].0 < key {
                    start = mid + 1
                }
                else {
                    end = mid
                }
            }
            return (start < elements.count && elements[start].0 == key ? start : nil, start)
        case .last:
            var start = -1
            var end = elements.count - 1
            while start < end {
                let mid = start + (end - start + 1) / 2
                if elements[mid].0 > key {
                    end = mid - 1
                }
                else {
                    start = mid
                }
            }
            return (start >= 0 && elements[start].0 == key ? start : nil, start + 1)
        case .after:
            var start = 0
            var end = elements.count
            while start < end {
                let mid = start + (end - start) / 2
                if elements[mid].0 <= key {
                    start = mid + 1
                }
                else {
                    end = mid
                }
            }
            return (start < elements.count ? start : nil, start)
        }
    }

    /// Return the slot of the element at `offset` in the subtree rooted at this node.
    internal func slot(atOffset offset: Int) -> (index: Int, match: Bool, offset: Int) {
        assert(offset >= 0 && offset <= count)
        if offset == count {
            return (index: elements.count, match: isLeaf, offset: count)
        }
        if isLeaf {
            return (offset, true, offset)
        }
        else if offset <= count / 2 {
            var p = 0
            for i in 0 ..< children.count - 1 {
                let c = children[i].count
                if offset == p + c {
                    return (index: i, match: true, offset: p + c)
                }
                if offset < p + c {
                    return (index: i, match: false, offset: p + c)
                }
                p += c + 1
            }
            let c = children.last!.count
            precondition(count == p + c, "Invalid B-Tree")
            return (index: children.count - 1, match: false, offset: count)
        }
        var p = count
        for i in (1 ..< children.count).reversed() {
            let c = children[i].count
            if offset == p - (c + 1) {
                return (index: i - 1, match: true, offset: offset)
            }
            if offset > p - (c + 1) {
                return (index: i, match: false, offset: p)
            }
            p -= c + 1
        }
        let c = children.first!.count
        precondition(p - c == 0, "Invalid B-Tree")
        return (index: 0, match: false, offset: c)
    }

    /// Return the offset of the element at `slot` in the subtree rooted at this node.
    internal func offset(ofSlot slot: Int) -> Int {
        let c = elements.count
        assert(slot >= 0 && slot <= c)
        if isLeaf {
            return slot
        }
        if slot == c {
            return count
        }
        if slot <= c / 2 {
            return children[0...slot].reduce(slot) { $0 + $1.count }
        }
        return count - children[slot + 1 ... c].reduce(c - slot) { $0 + $1.count }
    }

    /// Returns true iff the subtree at this node is guaranteed to contain the specified element 
    /// with `key` (if it exists).
    /// Returns false if the key falls into the first or last child subtree, so containment depends
    /// on the contents of the ancestors of this node.
    internal func contains(_ key: Key, choosing selector: BTreeKeySelector) -> Bool {
        let firstKey = elements.first!.0
        let lastKey = elements.last!.0
        if key < firstKey {
            return false
        }
        if key == firstKey && selector == .first {
            return false
        }
        if key > lastKey {
            return false
        }
        if key == lastKey && (selector == .last || selector == .after) {
            return false
        }
        return true
    }
}

//MARK: Lookups

extension BTreeNode {
    /// Returns the first element at or under this node, or `nil` if this node is empty.
    ///
    /// - Complexity: O(log(`count`))
    var first: Element? {
        var node = self
        while let child = node.children.first {
            node = child
        }
        return node.elements.first
    }

    /// Returns the last element at or under this node, or `nil` if this node is empty.
    ///
    /// - Complexity: O(log(`count`))
    var last: Element? {
        var node = self
        while let child = node.children.last {
            node = child
        }
        return node.elements.last
    }
}

//MARK: Splitting

internal struct BTreeSplinter<Key: Comparable, Value> {
    let separator: (Key, Value)
    let node: BTreeNode<Key, Value>
}

extension BTreeNode {
    typealias Splinter = BTreeSplinter<Key, Value>

    /// Split this node into two, removing the high half of the nodes and putting them in a splinter.
    ///
    /// - Returns: A splinter containing the higher half of the original node.
    internal func split() -> Splinter {
        assert(isTooLarge)
        return split(at: elements.count / 2)
    }

    /// Split this node into two at the key at index `median`, removing all elements at or above `median` 
    /// and putting them in a splinter.
    ///
    /// - Returns: A splinter containing the higher half of the original node.
    internal func split(at median: Int) -> Splinter {
        let count = elements.count
        let separator = elements[median]
        let node = BTreeNode(node: self, slotRange: median + 1 ..< count)
        elements.removeSubrange(median ..< count)
        if isLeaf {
            self.count = median
        }
        else {
            children.removeSubrange(median + 1 ..< count + 1)
            self.count = median + children.reduce(0, { $0 + $1.count })
        }
        assert(node.depth == self.depth)
        return Splinter(separator: separator, node: node)
    }

    internal func insert(_ splinter: Splinter, inSlot slot: Int) {
        elements.insert(splinter.separator, at: slot)
        children.insert(splinter.node, at: slot + 1)
    }
}

//MARK: Removal

extension BTreeNode {
    /// Reorganize the tree rooted at `self` so that the undersize child in `slot` is corrected.
    /// As a side effect of the process, `self` may itself become undersized, but all of its descendants
    /// become balanced.
    internal func fixDeficiency(_ slot: Int) {
        assert(!isLeaf && children[slot].isTooSmall)
        if slot > 0 && children[slot - 1].elements.count > minKeys {
            rotateRight(slot)
        }
        else if slot < children.count - 1 && children[slot + 1].elements.count > minKeys {
            rotateLeft(slot)
        }
        else if slot > 0 {
            // Collapse deficient slot into previous slot.
            collapse(slot - 1)
        }
        else {
            // Collapse next slot into deficient slot.
            collapse(slot)
        }
    }

    internal func rotateRight(_ slot: Int) {
        assert(slot > 0)
        makeChildUnique(slot)
        makeChildUnique(slot - 1)
        children[slot].elements.insert(elements[slot - 1], at: 0)
        if !children[slot].isLeaf {
            let lastGrandChildBeforeSlot = children[slot - 1].children.removeLast()
            children[slot].children.insert(lastGrandChildBeforeSlot, at: 0)

            children[slot - 1].count -= lastGrandChildBeforeSlot.count
            children[slot].count += lastGrandChildBeforeSlot.count
        }
        elements[slot - 1] = children[slot - 1].elements.removeLast()
        children[slot - 1].count -= 1
        children[slot].count += 1
    }
    
    internal func rotateLeft(_ slot: Int) {
        assert(slot < children.count - 1)
        makeChildUnique(slot)
        makeChildUnique(slot + 1)
        children[slot].elements.append(elements[slot])
        if !children[slot].isLeaf {
            let firstGrandChildAfterSlot = children[slot + 1].children.remove(at: 0)
            children[slot].children.append(firstGrandChildAfterSlot)

            children[slot + 1].count -= firstGrandChildAfterSlot.count
            children[slot].count += firstGrandChildAfterSlot.count
        }
        elements[slot] = children[slot + 1].elements.remove(at: 0)
        children[slot].count += 1
        children[slot + 1].count -= 1
    }

    internal func collapse(_ slot: Int) {
        assert(slot < children.count - 1)
        makeChildUnique(slot)
        let next = children.remove(at: slot + 1)
        children[slot].elements.append(elements.remove(at: slot))
        children[slot].count += 1
        children[slot].elements.append(contentsOf: next.elements)
        children[slot].count += next.count
        if !next.isLeaf {
            children[slot].children.append(contentsOf: next.children)
        }
        assert(children[slot].isBalanced)
    }
}

//MARK: Join

extension BTreeNode {
    /// Shift slots between `self` and `node` such that the number of elements in `self` becomes `target`.
    internal func shiftSlots(separator: Element, node: BTreeNode, target: Int) -> Splinter? {
        assert(self.depth == node.depth)

        let forward = target > self.elements.count
        let delta = abs(target - self.elements.count)
        if delta == 0 {
            return Splinter(separator: separator, node: node)
        }
        let lc = self.elements.count
        let rc = node.elements.count

        if (forward && delta >= rc + 1) || (!forward && delta >= lc + 1) {
            // Melt the entire right node into self.
            self.elements.append(separator)
            self.elements.append(contentsOf: node.elements)
            self.children.append(contentsOf: node.children)
            node.elements = []
            node.children = []
            self.count += 1 + node.count
            return nil
        }

        let rsep: Element
        if forward { // Transfer slots from right to left
            assert(lc + delta < self.order)
            assert(delta <= rc)

            rsep = node.elements[delta - 1]

            self.elements.append(separator)
            self.elements.append(contentsOf: node.elements.prefix(delta - 1))
            self.count += delta

            node.elements.removeFirst(delta)
            node.count -= delta

            if !self.isLeaf {
                let children = node.children.prefix(delta)
                let dc = children.reduce(0) { $0 + $1.count }
                self.children.append(contentsOf: children)
                self.count += dc

                node.children.removeFirst(delta)
                node.count -= dc
            }
        }
        else {
            // Transfer slots from left to right
            assert(rc + delta < node.order)
            assert(delta <= lc)

            rsep = self.elements[lc - delta]

            node.elements.insert(separator, at: 0)
            node.elements.insert(contentsOf: self.elements.suffix(delta - 1), at: 0)
            node.count += delta

            self.elements.removeSubrange(lc - delta ..< lc)
            self.count -= delta

            if !self.isLeaf {
                let children = self.children.suffix(delta)
                let dc = children.reduce(0) { $0 + $1.count }
                node.children.insert(contentsOf: children, at: 0)
                node.count += dc

                self.children.removeSubrange(lc + 1 - delta ..< lc + 1)
                self.count -= dc
            }
        }
        if node.children.count == 1 {
            return Splinter(separator: rsep, node: node.makeChildUnique(0))
        }
        return Splinter(separator: rsep, node: node)
    }

    func swapContents(with other: Node) {
        precondition(self._depth == other._depth)
        precondition(self._order == other._order)
        swap(&self.elements, &other.elements)
        swap(&self.children, &other.children)
        swap(&self.count, &other.count)
    }

    /// Create and return a new B-tree consisting of elements of `left`,`separator` and the elements of `right`,
    /// in this order.
    ///
    /// If you need to keep `left` and `right` intact, clone them before calling this function.
    ///
    /// - Requires: `l <= separator.0 && separator.0 <= r` for all keys `l` in `left` and all keys `r` in `right`.
    /// - Complexity: O(log(left.count + right.count))
    internal static func join(left: BTreeNode, separator: (Key, Value), right: BTreeNode) -> BTreeNode {
        precondition(left.order == right.order)

        let order = left.order
        let depthDelta = left.depth - right.depth
        let append = depthDelta >= 0
        
        let stock = append ? left : right
        let scion = append ? right : left
        // We'll graft the scion onto the stock.

        // First, find the insertion point, and preemptively update node counts on the way there.
        var path = [stock]
        var node = stock
        let c = scion.count
        for _ in 0 ..< abs(depthDelta) {
            node.count += c + 1
            node = node.makeChildUnique(append ? node.children.count - 1 : 0)
            path.append(node)
        }

        // Graft the scion into the stock by inserting the contents of its root into `node`.
        if !append { node.swapContents(with: scion) }
        assert(node.depth == scion.depth)
        let slotCount = node.elements.count + 1 + scion.elements.count
        let target = slotCount < order ? slotCount : slotCount / 2
        var splinter = node.shiftSlots(separator: separator, node: scion, target: target)
        if splinter != nil {
            assert(splinter!.node.isBalanced)
            path.removeLast()
            while let s = splinter, !path.isEmpty {
                let node = path.removeLast()
                node.insert(s, inSlot: append ? node.elements.count : 0)
                splinter = node.isTooLarge ? node.split() : nil
            }
            if let s = splinter {
                return BTreeNode(left: stock, separator: s.separator, right: s.node)
            }
        }
        return stock
    }
}

