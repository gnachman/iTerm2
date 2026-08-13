//
//  iTermTabGroupOrderingTests.swift
//  iTerm2XCTests
//
//  The canonical tab order must satisfy the pinned-prefix invariant FIRST and
//  group contiguity second. The regression this pins down: pinning a tab used
//  to be undone by the contiguity repair, which compacted group runs with no
//  regard for pinning and left a pinned tab stranded right of unpinned ones.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermTabGroupOrderingTests: XCTestCase {

    private func canonical(_ groupIDs: [String?], _ pinned: [Bool]) -> [Int] {
        return iTermTabGroupOrdering.canonicalOrder(groupIDs: groupIDs, pinned: pinned)
    }

    // The pin-action scenario: tabs A(G, pinned), C(pinned), B(G, unpinned).
    // A naive group compaction yields [A, B, C], stranding pinned C after
    // unpinned B. The canonical order must keep the pinned prefix [A, C].
    func testPinnedPrefixBeatsGroupContiguity() {
        XCTAssertEqual(canonical(["G", nil, "G"], [true, true, false]), [0, 1, 2])
    }

    // With no pinning, a split group compacts to its first member's position.
    func testSplitGroupCompacts() {
        XCTAssertEqual(canonical([nil, "G", nil, "G"], [false, false, false, false]),
                       [0, 1, 3, 2])
    }

    // An already-valid order is untouched (identity permutation).
    func testValidOrderIsIdentity() {
        XCTAssertEqual(canonical(["G", "G", nil], [false, false, false]), [0, 1, 2])
        XCTAssertEqual(canonical([nil, nil], [true, false]), [0, 1])
    }

    // Unpinned tabs ahead of pinned ones get partitioned behind them, without
    // reordering within either class.
    func testStablePartition() {
        // U, P, U, P -> P(1), P(3), U(0), U(2)
        XCTAssertEqual(canonical([nil, nil, nil, nil], [false, true, false, true]),
                       [1, 3, 0, 2])
    }

    // Dropping an unpinned group at the front of a bar whose first tab is
    // pinned: the group slides in right after the pinned prefix.
    func testGroupDroppedBeforePinnedTabLandsAfterIt() {
        // G1, G2, P -> P, G1, G2
        XCTAssertEqual(canonical(["G", "G", nil], [false, false, true]), [2, 0, 1])
    }

    // A group with pinned and unpinned members spans the boundary as two runs;
    // no tab crosses the pinned boundary.
    func testMixedPinnedGroupSpansBoundary() {
        // P(plain), G(pinned), G(unpinned), U(plain)
        XCTAssertEqual(canonical([nil, "G", "G", nil], [true, true, false, false]),
                       [0, 1, 2, 3])
    }

    // Groups compact independently within the pinned and unpinned classes.
    func testCompactionWithinEachClass() {
        // Pinned: G, x, G (split) / Unpinned: H, y, H (split)
        // -> pinned [G G x] wait: anchored at first member: G(0), G(2), x(1)
        XCTAssertEqual(canonical(["G", nil, "G", "H", nil, "H"],
                                 [true, true, true, false, false, false]),
                       [0, 2, 1, 3, 5, 4])
    }

    // The canonical order is idempotent: applying it to an already-canonical
    // arrangement returns the identity.
    func testIdempotent() {
        let groupIDs: [String?] = ["G", nil, "G", "H", "H", nil]
        let pinned = [true, true, false, false, false, false]
        let once = canonical(groupIDs, pinned)
        let reorderedIDs = once.map { groupIDs[$0] }
        let reorderedPinned = once.map { pinned[$0] }
        XCTAssertEqual(canonical(reorderedIDs, reorderedPinned),
                       Array(0..<groupIDs.count))
    }

    // ObjC bridge round-trip with NSNull for ungrouped.
    func testObjCBridge() {
        let result = iTermTabGroupOrdering.canonicalOrder(
            groupIDs: ["G", NSNull(), "G"] as [Any],
            pinned: [true, true, false] as [NSNumber])
        XCTAssertEqual(result, [0, 1, 2])
    }
}
