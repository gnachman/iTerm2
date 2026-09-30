//
//  DoublyLinkedListBehaviorTests.swift
//  iTerm2
//
//  Ported from the legacy iTermDoublyLinkedListTests.m. Exercises the ObjC
//  iTermDoublyLinkedList (distinct from the Swift DoublyLinkedList covered by
//  DoublyLinkedListTests.swift).
//

import XCTest
@testable import iTerm2SharedARC

final class DoublyLinkedListBehaviorTests: XCTestCase {
    private func makeEntry(_ value: Int) -> iTermDoublyLinkedListEntry<NSNumber> {
        return iTermDoublyLinkedListEntry<NSNumber>(object: NSNumber(value: value))
    }

    func testPrependBuildsListInReverseInsertionOrder() {
        let dll = iTermDoublyLinkedList<NSNumber>()
        let e1 = makeEntry(1)
        let e2 = makeEntry(2)
        dll.prepend(e2)
        dll.prepend(e1)

        XCTAssertEqual(dll.count, 2)

        XCTAssertNil(dll.first?.dllPrevious)
        XCTAssertEqual(dll.first?.object, 1)
        XCTAssertEqual(dll.first?.dllNext?.object, 2)
        XCTAssertNil(dll.first?.dllNext?.dllNext)

        XCTAssertNil(dll.last?.dllNext)
        XCTAssertEqual(dll.last?.object, 2)
        XCTAssertEqual(dll.last?.dllPrevious?.object, 1)
        XCTAssertNil(dll.last?.dllPrevious?.dllPrevious)
    }

    func testRemoveFromTail() {
        let dll = iTermDoublyLinkedList<NSNumber>()
        let e1 = makeEntry(1)
        let e2 = makeEntry(2)
        dll.prepend(e2)
        dll.prepend(e1)

        dll.remove(e2)
        XCTAssertEqual(dll.count, 1)
        XCTAssertEqual(dll.first?.object, 1)
        XCTAssertNil(dll.first?.dllNext)
        XCTAssertNil(dll.first?.dllPrevious)

        XCTAssertEqual(dll.last?.object, 1)
        XCTAssertNil(dll.last?.dllPrevious)
        XCTAssertNil(dll.last?.dllNext)

        dll.remove(e1)
        XCTAssertEqual(dll.count, 0)
        XCTAssertNil(dll.first)
        XCTAssertNil(dll.last)
    }

    func testRemoveFromHead() {
        let dll = iTermDoublyLinkedList<NSNumber>()
        let e1 = makeEntry(1)
        let e2 = makeEntry(2)
        dll.prepend(e2)
        dll.prepend(e1)

        dll.remove(e1)
        XCTAssertEqual(dll.count, 1)
        XCTAssertEqual(dll.first?.object, 2)
        XCTAssertNil(dll.first?.dllNext)
        XCTAssertNil(dll.first?.dllPrevious)

        XCTAssertEqual(dll.last?.object, 2)
        XCTAssertNil(dll.last?.dllPrevious)
        XCTAssertNil(dll.last?.dllNext)

        dll.remove(e2)
        XCTAssertEqual(dll.count, 0)
        XCTAssertNil(dll.first)
        XCTAssertNil(dll.last)
    }

    func testRemoveMiddle() {
        let dll = iTermDoublyLinkedList<NSNumber>()
        let e1 = makeEntry(1)
        let e2 = makeEntry(2)
        let e3 = makeEntry(3)
        dll.prepend(e3)
        dll.prepend(e2)
        dll.prepend(e1)

        dll.remove(e2)
        XCTAssertEqual(dll.count, 2)
        XCTAssertEqual(dll.first?.object, 1)
        XCTAssertEqual(dll.first?.dllNext?.object, 3)
        XCTAssertNil(dll.first?.dllNext?.dllNext)
        XCTAssertNil(dll.first?.dllPrevious)

        XCTAssertEqual(dll.last?.object, 3)
        XCTAssertEqual(dll.last?.dllPrevious?.object, 1)
        XCTAssertNil(dll.last?.dllPrevious?.dllPrevious)
        XCTAssertNil(dll.last?.dllNext)
    }
}
