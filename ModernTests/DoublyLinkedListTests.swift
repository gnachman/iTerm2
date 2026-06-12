//
//  DoublyLinkedListTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

final class DoublyLinkedListTests: XCTestCase {

    // DLLNode declares both prev and next as strong references, so every
    // adjacent pair forms a retain cycle. When a list with 2+ nodes is
    // dropped without first being drained via remove(_:), every node — and
    // every value it holds — leaks.
    func testListReleasesValuesWhenDropped() {
        final class Probe {
            let id: Int
            init(_ id: Int) { self.id = id }
        }
        weak var w1: Probe?
        weak var w2: Probe?
        weak var w3: Probe?
        autoreleasepool {
            let dll = DoublyLinkedList<Probe>()
            let a = Probe(1)
            let b = Probe(2)
            let c = Probe(3)
            w1 = a
            w2 = b
            w3 = c
            _ = dll.append(a)
            _ = dll.append(b)
            _ = dll.append(c)
        }
        XCTAssertNil(w1, "head value leaked — list retained it via prev/next cycle")
        XCTAssertNil(w2, "middle value leaked — list retained it via prev/next cycle")
        XCTAssertNil(w3, "tail value leaked — list retained it via prev/next cycle")
    }
}

final class LRUEvictionPolicyTests: XCTestCase {

    // bump(_:) calls itemsByUse.remove(node) and then
    // itemsByUse.append(node.value) but discards the new node and never
    // updates nodesByKey. After a bump, nodesByKey[element] still points at
    // the old, list-detached node. The next mutation that looks the element
    // up — re-insert via add(_:cost:), or delete(_:) — operates on the stale
    // node, which corrupts the list's head/tail and changes which element
    // gets treated as the LRU on the next eviction.
    func testBumpFollowedByReinsertPreservesLRUOrder() {
        let p = LRUEvictionPolicy<String>(maximumSize: 100)
        _ = p.add(element: "a", cost: 30)
        _ = p.add(element: "b", cost: 30)
        p.bump("a")                           // a is MRU, b is LRU
        _ = p.add(element: "a", cost: 30)     // re-insert a; a stays MRU, b stays LRU
        let evictions = p.add(element: "c", cost: 50)  // total=110, exactly one eviction needed
        XCTAssertEqual(evictions, Set(["b"]),
                       "expected the LRU (b) to evict; got \(evictions)")
    }
}
