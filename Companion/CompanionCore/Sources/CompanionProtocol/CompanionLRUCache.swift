//
//  CompanionLRUCache.swift
//  CompanionProtocol
//
//  A small bounded least-recently-used cache. The phone's scrollback tile cache
//  used an unbounded dictionary, so a long history browse could accumulate images
//  without limit. This caps the entry count and evicts the least-recently-used
//  entry when full, while still supporting the key-range pruning the tile cache
//  needs when scrollback is trimmed (something NSCache cannot express).
//
//  Not thread-safe: callers use it from a single isolation domain (the app's main
//  actor). Access order is O(n) in the entry count, which is fine at the modest
//  capacities used here.
//

import Foundation

public final class CompanionLRUCache<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    /// Keys in access order, least-recently-used first, most-recently-used last.
    private var order: [Key] = []
    private let capacity: Int

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    public var count: Int { storage.count }

    public subscript(key: Key) -> Value? {
        get {
            guard let value = storage[key] else { return nil }
            touch(key)
            return value
        }
        set {
            if let newValue {
                storage[key] = newValue
                touch(key)
                evictIfNeeded()
            } else {
                remove(key)
            }
        }
    }

    /// Remove everything.
    public func removeAll() {
        storage.removeAll()
        order.removeAll()
    }

    /// Remove every entry whose key satisfies `predicate` (e.g. tiles below the new
    /// oldest available line after scrollback was trimmed).
    public func removeAll(where predicate: (Key) -> Bool) {
        for key in storage.keys where predicate(key) {
            remove(key)
        }
    }

    private func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
    }

    private func remove(_ key: Key) {
        guard storage.removeValue(forKey: key) != nil else { return }
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
    }

    private func evictIfNeeded() {
        while storage.count > capacity, let oldest = order.first {
            order.removeFirst()
            storage.removeValue(forKey: oldest)
        }
    }
}
