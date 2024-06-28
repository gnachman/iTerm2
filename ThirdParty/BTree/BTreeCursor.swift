//
//  BTreeCursor.swift
//  BTree
//
//  Created by Károly Lőrentey on 2016-02-12.
//  Copyright © 2015–2017 Károly Lőrentey.
//

extension BTree {
    //MARK: Cursors

    public typealias Cursor = BTreeCursor<Key, Value>

    /// Call `body` with a cursor at `offset` in this tree.
    ///
    /// - Warning: Do not rely on anything about `self` (the `BTree` that is the target of this method) during the
    ///   execution of body: it will not appear to have the correct value.
    ///   Instead, use only the supplied cursor to manipulate the tree.
    ///
    public mutating func withCursor<R>(atOffset offset: Int, body: (Cursor) throws -> R) rethrows -> R {
        precondition(offset >= 0 && offset <= count)
        makeUnique()
        let cursor = BTreeCursor(BTreeCursorPath(root: root, offset: offset))
        root = Node(order: self.order)
        defer { self.root = cursor.finish() }
        return try body(cursor)
    }

    /// Call `body` with a cursor at the start of this tree.
    ///
    /// - Warning: Do not rely on anything about `self` (the `BTree` that is the target of this method) during the
    ///   execution of body: it will not appear to have the correct value.
    ///   Instead, use only the supplied cursor to manipulate the tree.
    ///
    public mutating func withCursorAtStart<R>(_ body: (Cursor) throws -> R) rethrows -> R {
        return try withCursor(atOffset: 0, body: body)
    }

    /// Call `body` with a cursor at the end of this tree.
    ///
    /// - Warning: Do not rely on anything about `self` (the `BTree` that is the target of this method) during the
    ///   execution of body: it will not appear to have the correct value.
    ///   Instead, use only the supplied cursor to manipulate the tree.
    ///
    public mutating func withCursorAtEnd<R>(_ body: (Cursor) throws -> R) rethrows -> R {
        makeUnique()
        let cursor = BTreeCursor(BTreeCursorPath(endOf: root))
        root = Node(order: self.order)
        defer { self.root = cursor.finish() }
        return try body(cursor)
    }

    /// Call `body` with a cursor positioned on `key` in this tree.
    /// If there are multiple elements with the same key, `selector` indicates which matching element to find.
    ///
    /// - Warning: Do not rely on anything about `self` (the `BTree` that is the target of this method) during the
    ///   execution of body: it will not appear to have the correct value.
    ///   Instead, use only the supplied cursor to manipulate the tree.
    ///
    public mutating func withCursor<R>(onKey key: Key, choosing selector: BTreeKeySelector = .any, body: (Cursor) throws -> R) rethrows -> R {
        makeUnique()
        let cursor = BTreeCursor(BTreeCursorPath(root: root, key: key, choosing: selector))
        root = Node(order: self.order)
        defer { self.root = cursor.finish() }
        return try body(cursor)
    }

    /// Call `body` with a cursor positioned on `index` in this tree.
    ///
    /// - Warning: Do not rely on anything about `self` (the `BTree` that is the target of this method) during the
    ///   execution of body: it will not appear to have the correct value.
    ///   Instead, use only the supplied cursor to manipulate the tree.
    ///
    public mutating func withCursor<R>(at index: Index, body: (Cursor) throws -> R) rethrows -> R {
        index.state.expectRoot(root)
        makeUnique()
        let cursor = BTreeCursor(BTreeCursorPath(root: root, slotsFrom: index.state))
        root = Node(order: self.order)
        defer { self.root = cursor.finish() }
        return try body(cursor)
    }
}

/// A mutable path in a B-tree, holding strong references to nodes on the path.
/// This path variant supports modification of the tree itself.
///
/// To speed up operations inserting/removing individual elements from the tree, this path keeps the tree in a
/// special editing state, with element counts of nodes on the current path subtracted from their ancestors' counts.
/// The counts are restored when the path ascends back towards the root.
///
/// Because this preparation breaks the tree's invariants, there should not be references to the tree's root outside of
/// the cursor. Creating a `BTreeCursorPath` for a tree takes exclusive ownership of its root for the duration of the
/// editing. (I.e., until `finish()` is called.) If the root isn't uniquely held, you'll need to clone it before
/// creating a cursor path on it. (The path clones internal nodes on its own, as needed.)
///
internal struct BTreeCursorPath<Key: Comparable, Value>: BTreePath {
    typealias Tree = BTree<Key, Value>
    typealias Node = BTreeNode<Key, Value>
    typealias Element = (Key, Value)

    /// The root node in the tree that is being edited. Note that this isn't a valid B-tree while the cursor is active:
    /// each node on the current path has an invalid `count` field. (Other B-tree invariants are kept, though.)
    var root: Node

    /// The current count of elements in the tree. This is always kept up to date, while `root.count` is usually invalid.
    var count: Int

    /// The offset of the currently focused element in the tree.
    var offset: Int
    
    /// The current path in the tree that is being edited.
    ///
    /// Only the last node on the path has correct `count`; the element count of the currently focused descendant
    /// subtree is subtracted from each ancestor's count.
    /// I.e., `path[i].count = realCount(path[i]) - realCount(path[i+1])`.
    var _path: [Node]
    var node: Node

    /// The slots on the path to the currently focused part of the tree.
    var _slots: [Int]
    var slot: Int?

    init(root: Node) {
        self.root = root
        self.offset = root.count
        self.count = root.count
        self._path = []
        self.node = root
        self._slots = []
        self.slot = nil
    }

    var length: Int { return _path.count + 1}

    var element: Element {
        get { return node.elements[slot!] }
        set { node.elements[slot!] = newValue }
    }

    var key: Key {
        get { return node.elements[slot!].0 }
        set { node.elements[slot!].0 = newValue }
    }

    var value: Value {
        get { return node.elements[slot!].1 }
        set { node.elements[slot!].1 = newValue }
    }

    func setValue(_ value: Value) -> Value {
        precondition(!isAtEnd)
        let old = node.elements[slot!].1
        node.elements[slot!].1 = value
        return old
    }

    /// Invalidate this cursor.
    mutating func invalidate() {
        root = BTreeNode<Key, Value>(order: root.order)
        count = 0
        offset = 0
        _path = []
        node = root
        _slots = []
        slot = nil
    }

    mutating func popFromSlots() {
        assert(self.slot != nil)
        offset += node.count - node.offset(ofSlot: slot!)
        slot = nil
    }

    mutating func popFromPath() {
        assert(_path.count > 0 && slot == nil)
        let child = node
        node = _path.removeLast()
        node.count += child.count
        slot = _slots.removeLast()
    }

    mutating func pushToPath() {
        assert(self.slot != nil)
        let parent = node
        _path.append(parent)
        node = parent.makeChildUnique(self.slot!)
        parent.count -= node.count
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
            body(node, slot!)
            for i in (0 ..< _path.count).reversed() {
                body(_path[i], _slots[i])
            }
        }
        else {
            for i in 0 ..< _path.count {
                body(_path[i], _slots[i])
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

    mutating func finish() -> Node {
        var childCount = self.node.count
        while !_path.isEmpty {
            let node = _path.removeLast()
            node.count += childCount
            childCount = node.count
        }
        assert(root.count == count)
        defer { invalidate() }
        return root
    }

    /// Restore B-tree invariants after a single-element insertion produced an oversize leaf node.
    fileprivate mutating func fixupAfterInsert() {
        guard node.isTooLarge else { return }

        _path.append(self.node)
        _slots.append(self.slot!)

        // Split nodes on the way to the root until we restore the B-tree's size constraints.
        var i = _path.count - 1
        while _path[i].isTooLarge {
            // Split path[i], which must have correct count.
            let left = _path[i]
            let slot = _slots[i]
            let splinter = left.split()
            let right = splinter.node
            if slot > left.elements.count {
                // Focused element is in the new branch; adjust self accordingly.
                _slots[i] = slot - left.elements.count - 1
                _path[i] = right
            }
            else if slot == left.elements.count && i == _path.count - 1 {
                // Focused element is the new separator; adjust self accordingly.
                _path.removeLast()
                _slots.removeLast()
            }

            if i > 0 {
                // Insert splinter into parent node and fix its count field.
                let parent = _path[i - 1]
                let pslot = _slots[i - 1]
                parent.insert(splinter, inSlot: pslot)
                parent.count += left.count + right.count + 1
                if slot > left.elements.count {
                    // Focused element is in the new branch; update parent slot accordingly.
                    _slots[i - 1] = pslot + 1
                }
                i -= 1
            }
            else {
                // Create new root node.
                self.root = BTreeNode<Key, Value>(left: left, separator: splinter.separator, right: right)
                _path.insert(self.root, at: 0)
                _slots.insert(slot > left.elements.count ? 1 : 0, at: 0)
            }
        }

        // Size constraints are now OK, but counts on path have become valid, so we need to restore
        // cursor state by subtracting focused children.
        while i < _path.count - 1 {
            _path[i].count -= _path[i + 1].count
            i += 1
        }

        node = _path.removeLast()
        slot = _slots.removeLast()
    }
}

/// A stateful editing interface for efficiently inserting/removing/updating a range of elements in a B-tree.
///
/// Creating a cursor over a tree takes exclusive ownership of it; the tree is in a transient invalid state
/// while the cursor is active. (In particular, element counts are not finalized until the cursor is deactivated.)
///
/// The cursor always focuses on a particular spot on the tree: either a particular element, or the empty spot after 
/// the last element. There are methods to move the cursor to the next or previous element, to modify the currently 
/// focused element, to insert a new element before the current position, and to remove the currently focused element
/// from the tree.
///
/// Note that the cursor does not verify that keys you insert/modify uphold tree invariants -- it is your responsibility
/// to guarantee keys remain in ascending order while you're working with the cursor.
///
/// Creating a cursor takes O(log(*n*)) steps; once the cursor has been created, the complexity of most manipulations
/// is amortized O(1). For example, appending *k* new elements without a cursor takes O(*k* * log(*n*)) steps;
/// using a cursor to do the same only takes O(log(*n*) + *k*).
public final class BTreeCursor<Key: Comparable, Value> {
    public typealias Element = (Key, Value)
    public typealias Tree = BTree<Key, Value>
    internal typealias Node = BTreeNode<Key, Value>
    internal typealias State = BTreeCursorPath<Key, Value>

    fileprivate var state: State

    /// The number of elements in the tree currently being edited.
    public var count: Int { return state.count }

    /// The offset of the currently focused element in the tree.
    ///
    /// - Complexity: O(1) for the getter, O(log(`count`)) for the setter.
    public var offset: Int {
        get {
            return state.offset
        }
        set {
            state.move(toOffset: newValue)
        }
    }

    //MARK: Simple properties

    /// Return true iff this is a valid cursor.
    internal var isValid: Bool { return state.isValid }
    /// Return true iff the cursor is focused on the initial element.
    public var isAtStart: Bool { return state.isAtStart }
    /// Return true iff the cursor is focused on the spot beyond the last element.
    public var isAtEnd: Bool { return state.isAtEnd }

    //MARK: Initializers

    internal init(_ state: BTreeCursorPath<Key, Value>) {
        self.state = state
    }

    //MARK: Finishing

    /// Finalize editing the tree and return it, deactivating this cursor.
    /// You'll need to create a new cursor to continue editing the tree.
    ///
    /// - Complexity: O(log(`count`))
    internal func finish() -> Node {
        return state.finish()
    }

    //MARK: Navigation

    /// Position the cursor on the next element in the B-tree.
    ///
    /// - Requires: `!isAtEnd`
    /// - Complexity: Amortized O(1)
    public func moveForward() {
        state.moveForward()
    }

    /// Position this cursor on the previous element in the B-tree.
    ///
    /// - Requires: `!isAtStart`
    /// - Complexity: Amortized O(1)
    public func moveBackward() {
        state.moveBackward()
    }

    /// Position this cursor on the start of the B-tree.
    ///
    /// - Complexity: O(log(`offset`))
    public func moveToStart() {
        state.moveToStart()
    }

    /// Position this cursor on the end of the B-tree, i.e., at the offset after the last element.
    ///
    /// - Complexity: O(log(`count` - `offset`))
    public func moveToEnd() {
        state.moveToEnd()
    }

    /// Move this cursor to the specified offset in the B-tree.
    ///
    /// - Complexity: O(log(*distance*)), where *distance* is the absolute difference between the desired and current
    ///   offsets.
    public func move(toOffset offset: Int) {
        state.move(toOffset: offset)
    }

    /// Move this cursor to an element with the specified key. 
    /// If there are no such elements, the cursor is moved to the first element after `key` (or at the end of tree).
    /// If there are multiple such elements, `selector` specifies which one to find.
    ///
    /// - Complexity: O(log(`count`))
    public func move(to key: Key, choosing selector: BTreeKeySelector = .any) {
        state.move(to: key, choosing: selector)
    }

    //MARK: Editing

    /// Get or replace the currently focused element.
    ///
    /// - Warning: Changing the key is potentially dangerous; it is the caller's responsibility to ensure that
    /// keys remain in ascending order. This is not verified at runtime.
    /// - Complexity: O(1)
    public var element: Element {
        get { return state.element }
        set { state.element = newValue }
    }

    /// Get or set the key of the currently focused element.
    ///
    /// - Warning: Changing the key is potentially dangerous; it is the caller's responsibility to ensure that
    /// keys remain in ascending order. This is not verified at runtime.
    /// - Complexity: O(1)
    public var key: Key {
        get { return state.key }
        set { state.key = newValue }
    }

    /// Get or set the value of the currently focused element.
    ///
    /// - Complexity: O(1)
    public var value: Value {
        get { return state.value }
        set { state.value = newValue }
    }

    /// Update the value stored at the cursor's current position and return the previous value.
    /// This method does not change the cursor's position.
    ///
    /// - Complexity: O(1)
    public func setValue(_ value: Value) -> Value {
        return state.setValue(value)
    }

    /// Insert a new element after the cursor's current position, and position the cursor on the new element.
    ///
    /// - Complexity: amortized O(1)
    public func insertAfter(_ element: Element) {
        precondition(!self.isAtEnd)
        state.count += 1
        if state.node.isLeaf {
            let slot = state.slot!
            state.node.insert(element, inSlot: slot + 1)
            state.slot = slot + 1
            state.offset += 1
        }
        else {
            moveForward()
            assert(state.node.isLeaf && state.slot == 0)
            state.node.insert(element, inSlot: 0)
        }
        state.fixupAfterInsert()
    }

    /// Insert a new element at the cursor's current offset, and leave the cursor positioned on the original element.
    ///
    /// - Complexity: amortized O(1)
    public func insert(_ element: Element) {
        precondition(self.isValid)
        state.count += 1
        if state.node.isLeaf {
            state.node.insert(element, inSlot: state.slot!)
        }
        else {
            moveBackward()
            assert(state.node.isLeaf && state.slot == state.node.elements.count - 1)
            state.node.append(element)
            state.slot = state.node.elements.count - 1
            state.offset += 1
        }
        state.fixupAfterInsert()
        moveForward()
    }

    /// Insert the contents of `tree` before the currently focused element, keeping the cursor's position on it.
    ///
    /// - Complexity: O(log(`count + tree.count`))
    public func insert(_ tree: Tree) {
        insert(tree.root)
    }

    /// Insert the contents of `node` before the currently focused element, keeping the cursor's position on it.
    ///
    /// - Complexity: O(log(`count + node.count`))
    internal func insert(_ node: Node) {
        insertWithoutCloning(node.clone())
    }

    /// Insert all elements in a sequence before the currently focused element, keeping the cursor's position on it.
    ///
    /// - Requires: `self.isValid` and `elements` is sorted by key.
    /// - Complexity: O(log(`count`) + *c*), where *c* is the number of elements in the sequence.
    public func insert<S: Sequence>(_ elements: S) where S.Element == Element {
        insertWithoutCloning(BTree(sortedElements: elements).root)
    }

    internal func insertWithoutCloning(_ root: Node) {
        precondition(isValid)
        let c = root.count
        if c == 0 { return }
        if c == 1 {
            insert(root.elements[0])
            return
        }
        if self.count == 0 {
            state = State(endOf: root)
            return
        }

        let offset = self.offset
        if offset == self.count {
            // Append
            moveBackward()
            let separator = remove()
            let j = Node.join(left: finish(), separator: separator, right: root)
            state = State(endOf: j)
        }
        else if offset == 0 {
            // Prepend
            let separator = remove()
            let j = Node.join(left: root, separator: separator, right: finish())
            state = State(root: j, offset: offset + c)
        }
        else {
            // Insert in middle
            moveBackward()
            let sep1 = remove()
            let (prefix, sep2, suffix) = state.split()
            state.invalidate()
            let t1 = Node.join(left: prefix.root, separator: sep1, right: root)
            let t2 = Node.join(left: t1, separator: sep2, right: suffix.root)
            state = State(root: t2, offset: offset + c)
        }
    }

    /// Remove and return the element at the cursor's current position, and position the cursor on its successor.
    ///
    /// - Complexity: O(log(`count`))
    @discardableResult
    public func remove() -> Element {
        precondition(!isAtEnd)
        let result = state.element
        if !state.node.isLeaf {
            // For internal nodes, remove the (leaf) predecessor instead, then put it back in place of the element
            // that we actually want to remove.
            moveBackward()
            let surrogate = remove()
            self.key = surrogate.0
            self.value = surrogate.1
            moveForward()
            return result
        }
        let targetOffset = self.offset
        state.node.elements.remove(at: state.slot!)
        state.node.count -= 1
        state.count -= 1
        state.popFromSlots()

        while state.node !== state.root && state.node.isTooSmall {
            state.popFromPath()
            let slot = state.slot!
            state.popFromSlots()
            state.node.fixDeficiency(slot)
        }
        while targetOffset != count && targetOffset == self.offset && state.node !== state.root {
            state.popFromPath()
            state.popFromSlots()
        }
        if state.node === state.root && state.node.elements.count == 0 && state.node.children.count == 1 {
            assert(state.length == 1 && state.slot == nil)
            state.root = state.node.makeChildUnique(0)
            state.node = state.root
        }
        state.descend(toOffset: targetOffset)
        return result
    }

    /// Remove `n` elements starting at the cursor's current position, and position the cursor on the successor of
    /// the last element that was removed.
    ///
    /// - Complexity: O(log(`count`))
    public func remove(_ n: Int) {
        precondition(isValid && n >= 0 && self.offset + n <= count)
        if n == 0 { return }
        if n == 1 { remove(); return }
        if n == count { removeAll(); return }

        let offset = self.offset

        if offset == 0 {
            state.move(toOffset: n - 1)
            state = State(startOf: state.suffix().root)
        }
        else if offset == count - n {
            state = State(endOf: state.prefix().root)
        }
        else {
            let left = state.prefix()
            state.move(toOffset: offset + n)
            let separator = state.element
            let right = state.suffix()
            state.invalidate()
            let j = Node.join(left: left.root, separator: separator, right: right.root)
            state = State(root: j, offset: offset)
        }
    }

    /// Remove all elements.
    ///
    /// - Complexity: O(log(`count`)) if nodes of this tree are shared with other trees; O(`count`) otherwise.
    public func removeAll() {
        state = State(startOf: Node(order: state.root.order))
    }

    /// Remove all elements before (and if `inclusive` is true, including) the current position, and
    /// position the cursor at the start of the remaining tree.
    ///
    /// - Complexity: O(log(`count`)) if nodes of this tree are shared with other trees; O(`count`) otherwise.
    public func removeAllBefore(includingCurrent inclusive: Bool) {
        if isAtEnd {
            assert(!inclusive)
            removeAll()
            return
        }
        if !inclusive {
            if isAtStart {
                return
            }
            moveBackward()
        }
        state = State(startOf: state.suffix().root)
    }

    /// Remove all elements before (and if `inclusive` is true, including) the current position, and
    /// position the cursor on the end of the remaining tree.
    ///
    /// - Complexity: O(log(`count`)) if nodes of this tree are shared with other trees; O(`count`) otherwise.
    public func removeAllAfter(includingCurrent inclusive: Bool) {
        if isAtEnd {
            assert(!inclusive)
            return
        }
        if !inclusive {
            moveForward()
            if isAtEnd {
                return
            }
        }
        if isAtStart {
            removeAll()
            return
        }
        state = State(endOf: state.prefix().root)
    }

    /// Extract `n` elements starting at the cursor's current position, and position the cursor on the successor of
    /// the last element that was removed.
    ///
    /// - Returns: The extracted elements as a new B-tree.
    /// - Complexity: O(log(`count`))
    public func extract(_ n: Int) -> Tree {
        precondition(isValid && n >= 0 && self.offset + n <= count)
        if n == 0 {
            return Tree(order: state.root.order)
        }
        if n == 1 {
            let element = remove()
            var tree = Tree(order: state.root.order)
            tree.insert(element)
            return tree
        }
        if n == count {
            let node = state.finish()
            state = State(startOf: Node(order: node.order))
            return Tree(node)
        }

        let offset = self.offset
        if offset == count - n {
            var split = state.split()
            state = State(root: split.prefix.root, offset: offset)
            split.suffix.insert(split.separator, atOffset: 0)
            return split.suffix
        }

        let (left, sep1, tail) = state.split()
        state = State(root: tail.root, offset: n - 1)
        var (mid, sep2, right) = state.split()
        state.invalidate()
        let j = Node.join(left: left.root, separator: sep2, right: right.root)
        state = State(root: j, offset: offset)
        mid.insert(sep1, atOffset: 0)
        return mid
    }
}
