//
//  iTermTabGroupNestingTests.swift
//  ModernTests
//
//  Nested tab groups (one level deep): a sub-group's tabs must stay contiguous
//  inside its parent's run, and a dropped tab joins the deepest group both of
//  its neighbors share.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermTabGroupNestingTests: XCTestCase {

    private func canonical(_ groupIDs: [String?],
                           _ parentIDs: [String?],
                           _ pinned: [Bool]? = nil) -> [Int] {
        return iTermTabGroupOrdering.canonicalOrder(groupIDs: groupIDs,
                                                    parentIDs: parentIDs,
                                                    pinned: pinned ?? groupIDs.map { _ in false })
    }

    // MARK: - Canonical order

    // With no parents the nested variant is exactly the flat one.
    func testNoParentsMatchesFlatOrder() {
        let groups: [String?] = [nil, "G", nil, "G", "H", nil, "H"]
        XCTAssertEqual(canonical(groups, groups.map { _ in nil }),
                       iTermTabGroupOrdering.canonicalOrder(groupIDs: groups,
                                                            pinned: groups.map { _ in false }))
    }

    // A sub-group member stranded outside its parent's run is pulled back into
    // it: P-direct, loner, C (in P) -> P-direct, C, loner.
    func testStrandedSubgroupMemberJoinsParentRun() {
        XCTAssertEqual(canonical(["P", nil, "C"], [nil, nil, "P"]), [0, 2, 1])
    }

    // Inside the parent's run the sub-group's members are compacted at its
    // first member: C, P-direct, C -> C, C, P-direct.
    func testSubgroupCompactsInsideParent() {
        XCTAssertEqual(canonical(["C", "P", "C"], ["P", nil, "P"]), [0, 2, 1])
    }

    // A parent with no direct members is still one block through its
    // sub-groups: C(P), loner, D(P) -> C, D, loner.
    func testParentWithOnlySubgroupsIsOneBlock() {
        XCTAssertEqual(canonical(["C", nil, "D"], ["P", nil, "P"]), [0, 2, 1])
    }

    // Two sub-groups of the same parent interleaved: each becomes one run.
    func testInterleavedSubgroupsSeparate() {
        XCTAssertEqual(canonical(["C", "D", "C", "D"], ["P", "P", "P", "P"]), [0, 2, 1, 3])
    }

    // Valid nested orders are untouched, and the result is idempotent.
    func testValidNestedOrderIsIdentityAndIdempotent() {
        let groups: [String?] = [nil, "P", "C", "C", "P", "D", nil]
        let parents: [String?] = [nil, nil, "P", "P", nil, "P", nil]
        XCTAssertEqual(canonical(groups, parents), Array(0..<groups.count))

        let scrambled: [String?] = ["C", nil, "P", "D", "C", nil, "P"]
        let scrambledParents: [String?] = ["P", nil, nil, "P", "P", nil, nil]
        let once = canonical(scrambled, scrambledParents)
        let reordered = once.map { scrambled[$0] }
        let reorderedParents = once.map { scrambledParents[$0] }
        XCTAssertEqual(canonical(reordered, reorderedParents), Array(0..<scrambled.count))
    }

    // Pinning still wins: a pinned sub-group member stays in the pinned prefix.
    func testPinnedPrefixStillWins() {
        let order = canonical([nil, "C", "P"], [nil, "P", nil], [true, false, true])
        XCTAssertEqual(order, [0, 2, 1])
    }

    // MARK: - Drop resolution

    private func resolved(_ index: Int, _ order: [String?], _ parents: [String?]) -> String? {
        return iTermTabGroupContiguity.resolvedGroup(forTabAt: index, order: order, parents: parents)
    }

    // Between two members of a sub-group: join the sub-group.
    func testDropBetweenSubgroupMembersJoinsSubgroup() {
        XCTAssertEqual(resolved(1, ["C", nil, "C"], ["P", nil, "P"]), "C")
    }

    // Between a parent's direct member and its sub-group: join the parent.
    func testDropBetweenParentMemberAndSubgroupJoinsParent() {
        XCTAssertEqual(resolved(1, ["P", nil, "C"], [nil, nil, "P"]), "P")
        XCTAssertEqual(resolved(1, ["C", nil, "P"], ["P", nil, nil]), "P")
    }

    // Between two different sub-groups of one parent: join the parent.
    func testDropBetweenSiblingSubgroupsJoinsParent() {
        XCTAssertEqual(resolved(1, ["C", nil, "D"], ["P", nil, "P"]), "P")
    }

    // At the parent's edge: leave every group.
    func testDropAtParentEdgeLeaves() {
        XCTAssertNil(resolved(1, ["C", nil, nil], ["P", nil, nil]))
    }

    // Without parents the nested rule matches the flat one.
    func testFlatResolutionUnchanged() {
        let cases: [(Int, [String?])] = [(1, ["A", nil, "A"]), (1, ["A", nil, "B"]), (0, [nil, "A"]),
                                         (2, ["A", "A", nil])]
        for (index, order) in cases {
            XCTAssertEqual(resolved(index, order, order.map { _ in nil }),
                           iTermTabGroupContiguity.resolvedGroup(forTabAt: index, order: order))
        }
    }

    // MARK: - Keyboard move (Move Tab Left/Right)

    private func move(_ groups: [String?], _ parents: [String?], _ selected: Int, _ offset: Int) -> SingleTabMove? {
        return iTermTabGroupOrdering.nestedSingleTabMove(groupIDs: groups,
                                                         parentIDs: parents,
                                                         selectedIndex: selected,
                                                         offset: offset)
    }

    private func order(_ m: SingleTabMove?) -> [Int]? {
        return m?.order.map { $0.intValue }
    }

    // [S:a, S:b, x] with x selected, Move Left: x jumps the whole sub-group. A
    // plain swap would give [a, x, b], which the canonical order snaps back.
    func testDirectMemberJumpsSubgroupLeft() {
        let m = move(["S", "S", "P"], ["P", "P", nil], 2, -1)
        XCTAssertEqual(order(m), [2, 0, 1])
        XCTAssertEqual(m?.changesMembership, false)
    }

    func testDirectMemberJumpsSubgroupRight() {
        XCTAssertEqual(order(move(["P", "S", "S", "P"], [nil, "P", "P", nil], 0, 1)), [1, 2, 0, 3])
    }

    // Inside a sub-group, a step to another sub-group member is a swap.
    func testSwapWithinSubgroup() {
        XCTAssertEqual(order(move(["S", "S", "P"], ["P", "P", nil], 0, 1)), [1, 0, 2])
    }

    // At the sub-group's edge (next to a direct member of the parent) the tab
    // leaves the sub-group for the parent, in place.
    func testSubgroupEdgeLeavesToParent() {
        let m = move(["S", "S", "P"], ["P", "P", nil], 1, 1)
        XCTAssertEqual(m?.changesMembership, true)
        XCTAssertEqual(m?.newGroupID, "P")
        XCTAssertEqual(order(m), [0, 1, 2])
    }

    // Two direct members, or a neighbor outside the top-level group: not handled
    // here (the flat single-tab move applies).
    func testFallsBackOutsideNestedCases() {
        XCTAssertNil(move(["P", "P"], [nil, nil], 0, 1))
        XCTAssertNil(move(["S", nil], ["P", nil], 0, 1))
        XCTAssertNil(move([nil, nil], [nil, nil], 0, 1))
    }

    // MARK: - Group definition

    func testGroupCarriesParentIdentifier() {
        let child = iTermTabGroup(uniqueIdentifier: "C", name: "Child", color: .systemRed, parentIdentifier: "P")
        XCTAssertEqual(child.parentIdentifier, "P")
        let top = iTermTabGroup(uniqueIdentifier: "P", name: "Parent", color: .systemBlue)
        XCTAssertNil(top.parentIdentifier)
    }
}
