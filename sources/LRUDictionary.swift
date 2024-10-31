//
//  LRUDictionary.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/27/24.
//

import Foundation

@objc(iTermUntypedLRUDictionary)
class UntypedLRUDictionary: NSObject {
    private var impl: LRUDictionary<AnyHashable, Any>

    @objc(initWithMaximumSize:)
    init(maximumSize: Int) {
        impl = LRUDictionary(maximumSize: maximumSize)
    }

    @objc(addObjectWithKey:value:cost:)
    func insert(key: AnyHashable, value: Any, cost: Int) {
        _ = impl.insert(key: key, value: value, cost: cost)
    }

    @objc(removeObjectForKey:)
    func delete(forKey key: AnyHashable) {
        impl.delete(forKey: key)
    }

    @objc(objectForKey:)
    func object(forKey key: AnyHashable) -> Any? {
        impl[key]
    }

    @objc(removeAllObjects)
    func removeAllObjects() {
        impl.removeAll()
    }
}

// A dictionary that automatically evicts least-recently used value to keep the
// size under a cap.
struct LRUDictionary<Key: Hashable, Value> {
    private let evictionPolicy: LRUEvictionPolicy<Key>
    private var dict = [Key: Value]()

    init(maximumSize: Int) {
        evictionPolicy = LRUEvictionPolicy(maximumSize: maximumSize)
    }

    // Returns a list of evicted key-value pairs
    mutating func insert(key: Key, value: Value, cost: Int) -> [(Key, Value)] {
        delete(forKey: key)
        dict[key] = value
        var evictions = [(Key, Value)]()
        let keysToRemove = evictionPolicy.add(element: key, cost: cost)
        for keyToRemove in keysToRemove {
            evictions.append((keyToRemove, dict[keyToRemove]!))
            dict.removeValue(forKey: keyToRemove)
        }
        return evictions
    }

    mutating func delete(forKey key: Key) {
        evictionPolicy.delete(key)
        dict.removeValue(forKey: key)
    }

    subscript(_ key: Key) -> Value? {
        dict[key]
    }

    mutating func removeAll() {
        evictionPolicy.deleteAll()
        dict = [:]
    }

    var keys: [Key: Value].Keys {
        return dict.keys
    }
}

extension LRUDictionary: Sequence {
    func makeIterator() -> [Key: Value].Iterator {
        return dict.makeIterator()
    }
}

class LRUEvictionPolicy<Element: Hashable> {
    private struct Item {
        var element: Element
        var cost: Int
    }
    private var itemsByUse = DoublyLinkedList<Item>()
    private var nodesByKey = [Element: DLLNode<Item>]()
    private var totalCost = 0
    let maximumSize: Int

    init(maximumSize: Int) {
        self.maximumSize = maximumSize
    }

    func deleteAll() {
        itemsByUse = DoublyLinkedList<Item>()
        nodesByKey = [Element: DLLNode<Item>]()
        totalCost = 0
    }

    // Returns elements to evict
    func add(element: Element, cost: Int) -> Set<Element> {
        let item = Item(element: element, cost: cost)
        if nodesByKey[item.element] != nil {
            delete(item.element)
        }
        nodesByKey[item.element] = itemsByUse.append(item)
        totalCost += item.cost

        return evictIfNeeded()
    }

    func delete(_ element: Element) {
        guard let node = nodesByKey[element] else {
            return
        }
        totalCost -= node.value.cost
        nodesByKey.removeValue(forKey: element)
        itemsByUse.remove(node)
    }

    func bump(_ element: Element) {
        guard let node = nodesByKey[element] else {
            return
        }
        itemsByUse.remove(node)
        _ = itemsByUse.append(node.value)
    }

    private func evictIfNeeded() -> Set<Element> {
        DLog("Current cost is \(totalCost)/\(maximumSize)")
        var evictions = Set<Element>()
        while totalCost > maximumSize && nodesByKey.count > 1 {
            DLog("Evict \(itemsByUse.first!.value.element) with cost \(itemsByUse.first!.value.cost)")
            evictions.insert(itemsByUse.first!.value.element)
            delete(itemsByUse.first!.value.element)
        }
        DLog("Evictions complete. Current totalCost is \(totalCost)/\(maximumSize)")
        return evictions
    }

    func cost(for element: Element) -> Int? {
        return nodesByKey[element]?.value.cost
    }
}

