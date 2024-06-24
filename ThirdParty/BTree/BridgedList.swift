//
//  BridgedList.swift
//  BTree
//
//  Created by Károly Lőrentey on 2016-08-10.
//  Copyright © 2016–2017 Károly Lőrentey.
//

import Foundation

extension List where Element: AnyObject {
    /// Return a view of this list as an immutable `NSArray`, without copying elements.
    /// This is useful when you want to use `List` values in Objective-C APIs.
    /// 
    /// - Complexity: O(1)
    public var arrayView: NSArray {
        return BridgedList<Element>(self.tree)
    }
}

internal final class BridgedListEnumerator<Key: Comparable, Value>: NSEnumerator {
    var iterator: BTree<Key, Value>.Iterator
    init(iterator: BTree<Key, Value>.Iterator) {
        self.iterator = iterator
        super.init()
    }

    public override func nextObject() -> Any? {
        return iterator.next()?.1
    }
}

internal class BridgedList<Value>: NSArray {
    var tree = BTree<EmptyKey, Value>()

    convenience init(_ tree: BTree<EmptyKey, Value>) {
        self.init()
        self.tree = tree
    }
    
    public override func copy(with zone: NSZone? = nil) -> Any {
        return self
    }

    override var count: Int {
        return tree.count
    }

    public override func object(at index: Int) -> Any {
        return tree.element(atOffset: index).1
    }

    public override func objectEnumerator() -> NSEnumerator {
        return BridgedListEnumerator(iterator: tree.makeIterator())
    }

    public override func countByEnumerating(with state: UnsafeMutablePointer<NSFastEnumerationState>, objects buffer: AutoreleasingUnsafeMutablePointer<AnyObject?>, count len: Int) -> Int {
        precondition(MemoryLayout<(EmptyKey, Value)>.size == MemoryLayout<Value>.size)
        precondition(MemoryLayout<(EmptyKey, Value)>.stride == MemoryLayout<Value>.stride)
        precondition(MemoryLayout<(EmptyKey, Value)>.alignment == MemoryLayout<Value>.alignment)

        var s = state.pointee
        if s.state >= UInt(tree.count) {
            return 0
        }
        let path = BTreeStrongPath(root: tree.root, offset: Int(s.state))
        let node = path.node
        let slot = path.slot!
        if node.isLeaf {
            precondition(slot != node.elements.count)
            let c = node.elements.count - slot
            node.elements.withUnsafeBufferPointer { p in
                s.itemsPtr = AutoreleasingUnsafeMutablePointer<AnyObject?>(UnsafeMutablePointer(mutating: p.baseAddress!) + slot)
                s.state += UInt(c)
            }
            state.pointee = s
            return c
        }

        buffer.pointee = node.elements[slot].1 as AnyObject
        s.itemsPtr = buffer
        s.state += 1
        state.pointee = s
        return 1
    }
}
