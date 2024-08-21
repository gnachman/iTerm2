//
//  DoublyLinkedList.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/27/24.
//

import Foundation

class DLLNode<T> {
    var value: T
    fileprivate var prev: DLLNode?
    fileprivate var next: DLLNode?

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
        if let tailNode = tail {
            newNode.prev = tailNode
            tailNode.next = newNode
        } else {
            head = newNode
        }
        tail = newNode
        return newNode
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
