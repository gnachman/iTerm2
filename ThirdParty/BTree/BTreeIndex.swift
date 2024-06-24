//
//  BTreeIndex.swift
//  BTree
//
//  Created by Károly Lőrentey on 2016-02-11.
//  Copyright © 2015–2017 Károly Lőrentey.
//

/// An index into a collection that uses a B-tree for storage.
///
/// BTree indices belong to a specific tree instance. Trying to use them with any other tree
/// instance (including one holding the exact same elements, or one derived from a mutated version of the
/// original instance) will cause a runtime error.
///
/// This index satisfies `Collection`'s requirement for O(1) access, but
/// it is only suitable for read-only processing -- most tree mutations will 
/// invalidate all existing indexes.
///
/// - SeeAlso: `BTreeCursor` for an efficient way to modify a batch of values in a B-tree.
public struct BTreeIndex<Key: Comparable, Value> {
    typealias Node = BTreeNode<Key, Value>
    typealias State = BTreeWeakPath<Key, Value>

    internal private(set) var state: State

    internal init(_ state: State) {
        self.state = state
    }
    
    /// Advance to the next index.
    ///
    /// - Requires: self is valid and not the end index.
    /// - Complexity: Amortized O(1).
    mutating func increment() {
        state.moveForward()
    }
    
    /// Advance to the previous index.
    ///
    /// - Requires: self is valid and not the start index.
    /// - Complexity: Amortized O(1).
    mutating func decrement() {
        state.moveBackward()
    }

    /// Advance this index by `distance` elements.
    ///
    /// - Complexity: O(log(*n*)) where *n* is the number of elements in the tree.
    mutating func advance(by distance: Int) {
        state.move(toOffset: state.offset + distance)
    }

    @discardableResult
    mutating func advance(by distance: Int, limitedBy limit: BTreeIndex) -> Bool {
        let originalDistance = limit.state.offset - state.offset
        if (distance >= 0 && originalDistance >= 0 && distance > originalDistance)
            || (distance <= 0 && originalDistance <= 0 && distance < originalDistance) {
            self = limit
            return false
        }
        state.move(toOffset: state.offset + distance)
        return true
    }
}

extension BTreeIndex: Comparable {
    /// Return true iff `a` is equal to `b`.
    public static func ==(a: BTreeIndex, b: BTreeIndex) -> Bool {
        precondition(a.state.root === b.state.root, "Indices to different trees cannot be compared")
        return a.state.offset == b.state.offset
    }

    /// Return true iff `a` is less than `b`.
    public static func <(a: BTreeIndex, b: BTreeIndex) -> Bool {
        precondition(a.state.root === b.state.root, "Indices to different trees cannot be compared")
        return a.state.offset < b.state.offset
    }
}

/// A mutable path in a B-tree, holding weak references to nodes on the path.
/// This path variant does not support modifying the tree itself; it is suitable for use in indices.
///
/// After a path of this kind has been created, the original tree might mutated in a way that invalidates
/// the path, setting some of its weak references to nil, or breaking the consistency of its trail of slot indices.
/// The path checks for this during navigation, and traps if it finds itself invalidated.
///
internal struct BTreeWeakPath<Key: Comparable, Value>: BTreePath {
    typealias Node = BTreeNode<Key, Value>

    var _root: Weak<Node>
    var offset: Int

    var _path: [Weak<Node>]
    var _slots: [Int]
    var _node: Weak<Node>
    var slot: Int?

    init(root: Node) {
        self._root = Weak(root)
        self.offset = root.count
        self._path = []
        self._slots = []
        self._node = Weak(root)
        self.slot = nil
    }

    var root: Node {
        guard let root = _root.value else { invalid() }
        return root
    }
    var count: Int { return root.count }
    var length: Int { return _path.count + 1}

    var node: Node {
        guard let node = _node.value else { invalid() }
        return node
    }
    
    internal func expectRoot(_ root: Node) {
        expectValid(_root.value === root)
    }

    internal func expectValid(_ expression: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
        precondition(expression(), "Invalid BTreeIndex", file: file, line: line)
    }

    internal func invalid(_ file: StaticString = #file, line: UInt = #line) -> Never  {
        preconditionFailure("Invalid BTreeIndex", file: file, line: line)
    }

    mutating func popFromSlots() {
        assert(self.slot != nil)
        let node = self.node
        offset += node.count - node.offset(ofSlot: slot!)
        slot = nil
    }

    mutating func popFromPath() {
        assert(_path.count > 0 && slot == nil)
        let child = node
        _node = _path.removeLast()
        expectValid(node.children[_slots.last!] === child)
        slot = _slots.removeLast()
    }

    mutating func pushToPath() {
        assert(self.slot != nil)
        let child = node.children[slot!]
        _path.append(_node)
        _node = Weak(child)
        _slots.append(slot!)
        slot = nil
    }

    mutating func pushToSlots(_ slot: Int, offsetOfSlot: Int) {
        assert(self.slot == nil)
        offset -= node.count - offsetOfSlot
        self.slot = slot
    }

    func forEach(ascending: Bool, body: (Node, Int) -> Void) {
        if ascending {
            var child: Node? = node
            body(child!, slot!)
            for i in (0 ..< _path.count).reversed() {
                guard let node = _path[i].value else { invalid() }
                let slot = _slots[i]
                expectValid(node.children[slot] === child)
                child = node
                body(node, slot)
            }
        }
        else {
            for i in 0 ..< _path.count {
                guard let node = _path[i].value else { invalid() }
                let slot = _slots[i]
                expectValid(node.children[slot] === (i < _path.count - 1 ? _path[i + 1].value : _node.value))
                body(node, slot)
            }
            body(node, slot!)
        }
    }

    func forEachSlot(ascending: Bool, body: (Int) -> Void) {
        if ascending {
            body(slot!)
            _slots.reversed().forEach(body)
        }
        else {
            _slots.forEach(body)
            body(slot!)
        }
    }
}
