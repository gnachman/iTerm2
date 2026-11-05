//
//  DoublyLinkedList.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/27/24.
//

import Foundation

class DLLNode<T> {
    var value: T
    fileprivate weak var prev: DLLNode?
    fileprivate(set) var next: DLLNode?

    init(value: T) {
        self.value = value
    }
}

class DoublyLinkedList<T> {
    private var head: DLLNode<T>?
    private var tail: DLLNode<T>?

    var first: DLLNode<T>? { head }

    func append(_ value: T) -> DLLNode<T> {
        let newNode = DLLNode(value: value)
        append(node: newNode)
        return newNode
    }

    // Moves a node of this list to the end without allocating, so a cache hit that bumps an
    // entry's recency costs no allocation.
    func moveToEnd(_ node: DLLNode<T>) {
        if tail === node {
            return
        }
        remove(node)
        append(node: node)
    }

    // `node` must not be in a list.
    private func append(node: DLLNode<T>) {
        if let tailNode = tail {
            node.prev = tailNode
            tailNode.next = node
        } else {
            head = node
        }
        tail = node
    }

    func remove(_ node: DLLNode<T>) {
        let prevNode = node.prev
        let nextNode = node.next

        if let prevNode = prevNode {
            prevNode.next = nextNode
        } else {
            head = nextNode
        }

        if let nextNode = nextNode {
            nextNode.prev = prevNode
        } else {
            tail = prevNode
        }

        node.prev = nil
        node.next = nil
    }
}
