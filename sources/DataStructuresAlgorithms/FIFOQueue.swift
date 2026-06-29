//
//  FIFOQueue.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2025.
//

import Foundation

/// A simple FIFO queue with O(1) amortized enqueue and dequeue operations.
/// Uses an array with a start index to avoid shifting elements on dequeue.
///
/// Conforms to Sequence for easy iteration and standard library interoperability.
struct FIFOQueue<Element>: Sequence {
    private var storage: [Element] = []
    private var startIndex_: Int = 0

    /// Whether the queue is empty.
    var isEmpty: Bool {
        return startIndex_ >= storage.count
    }

    /// The number of elements in the queue.
    var count: Int {
        return storage.count - startIndex_
    }

    /// Returns the first element without removing it, or nil if empty.
    var first: Element? {
        guard startIndex_ < storage.count else { return nil }
        return storage[startIndex_]
    }

    /// Adds an element to the back of the queue. O(1) amortized.
    mutating func enqueue(_ element: Element) {
        storage.append(element)
    }

    /// Removes and returns the first element, or nil if empty. O(1) amortized.
    @discardableResult
    mutating func dequeue() -> Element? {
        guard startIndex_ < storage.count else { return nil }
        let element = storage[startIndex_]
        startIndex_ += 1
        compactIfNeeded()
        return element
    }

    /// Removes all elements from the queue.
    mutating func removeAll() {
        storage.removeAll()
        startIndex_ = 0
    }

    /// Reclaims memory when a significant portion has been consumed.
    /// This keeps memory usage bounded while maintaining O(1) dequeue.
    private mutating func compactIfNeeded() {
        // Compact when we've consumed more than half and at least 64 elements
        if startIndex_ > 64 && startIndex_ > storage.count / 2 {
            storage.removeFirst(startIndex_)
            startIndex_ = 0
        }
    }

    // MARK: - Sequence Conformance

    /// Returns an iterator over the queue's elements.
    /// Elements are yielded in FIFO order (first enqueued = first yielded).
    func makeIterator() -> Iterator {
        return Iterator(storage: storage, index: startIndex_)
    }

    struct Iterator: IteratorProtocol {
        private let storage: [Element]
        private var index: Int

        init(storage: [Element], index: Int) {
            self.storage = storage
            self.index = index
        }

        mutating func next() -> Element? {
            guard index < storage.count else { return nil }
            let element = storage[index]
            index += 1
            return element
        }
    }
}

// MARK: - ExpressibleByArrayLiteral

extension FIFOQueue: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: Element...) {
        self.storage = elements
        self.startIndex_ = 0
    }
}

// MARK: - CustomStringConvertible

extension FIFOQueue: CustomStringConvertible {
    var description: String {
        let elements = Array(self)
        return "FIFOQueue(\(elements))"
    }
}

// MARK: - Equatable (when Element is Equatable)

extension FIFOQueue: Equatable where Element: Equatable {
    static func == (lhs: FIFOQueue<Element>, rhs: FIFOQueue<Element>) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var lhsIterator = lhs.makeIterator()
        var rhsIterator = rhs.makeIterator()
        while let lhsElement = lhsIterator.next(), let rhsElement = rhsIterator.next() {
            if lhsElement != rhsElement {
                return false
            }
        }
        return true
    }
}
