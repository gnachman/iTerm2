//
//  iTermTabGroupNestingRulesTests.swift
//  ModernTests
//
//  Making an existing group a sub-group of another, or top-level.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermTabGroupNestingRulesTests: XCTestCase {
    // Each tab is "-" (ungrouped), "G" (in top-level group G), or "P/C" (in
    // sub-group C of P).
    private func split(_ tabs: [String]) -> ([String?], [String?]) {
        var groupIDs = [String?]()
        var parentIDs = [String?]()
        for tab in tabs {
            let parts = tab.split(separator: "/").map(String.init)
            if tab == "-" {
                groupIDs.append(nil)
                parentIDs.append(nil)
            } else if parts.count == 2 {
                groupIDs.append(parts[1])
                parentIDs.append(parts[0])
            } else {
                groupIDs.append(parts[0])
                parentIDs.append(nil)
            }
        }
        return (groupIDs, parentIDs)
    }

    private func refusal(_ group: String, in parent: String?, _ tabs: [String]) -> iTermTabGroupNesting.Refusal? {
        let (groupIDs, parentIDs) = split(tabs)
        return iTermTabGroupNesting.refusal(nesting: group, in: parent, groupIDs: groupIDs, parentIDs: parentIDs)
    }

    private func order(_ group: String, to parent: String?, _ tabs: [String]) -> [String] {
        let (groupIDs, parentIDs) = split(tabs)
        return iTermTabGroupNesting.order(moving: group, to: parent, groupIDs: groupIDs, parentIDs: parentIDs).map { tabs[$0] }
    }

    func testTopLevelGroupMayNestInAnother() {
        XCTAssertNil(refusal("A", in: "B", ["A", "A", "B"]))
    }

    func testSubgroupMayMoveToAnotherParent() {
        XCTAssertNil(refusal("C", in: "B", ["P/C", "P", "B"]))
    }

    func testAnyGroupMayBecomeTopLevel() {
        XCTAssertNil(refusal("C", in: nil, ["P/C", "P"]))
    }

    func testRefusesMissingGroups() {
        XCTAssertEqual(refusal("X", in: "B", ["A", "B"]), .noSuchGroup)
        XCTAssertEqual(refusal("A", in: "X", ["A", "B"]), .noSuchParent)
    }

    func testRefusesNestingInItself() {
        XCTAssertEqual(refusal("A", in: "A", ["A"]), .sameGroup)
    }

    func testRefusesSubgroupAsParent() {
        XCTAssertEqual(refusal("A", in: "C", ["A", "P/C"]), .parentIsSubgroup)
    }

    func testRefusesGroupWithSubgroups() {
        XCTAssertEqual(refusal("P", in: "B", ["P", "P/C", "B"]), .groupHasSubgroups)
    }

    func testParentWithOnlySubgroupTabsCountsAsExisting() {
        XCTAssertNil(refusal("A", in: "P", ["A", "P/C"]))
    }

    // A group whose tabs are all in its sub-groups still exists as the group
    // being moved: making it top-level is a no-op, and nesting it is refused for
    // having sub-groups.
    func testGroupWithOnlySubgroupTabsMayBeMoved() {
        XCTAssertNil(refusal("P", in: nil, ["P/C", "B"]))
        XCTAssertEqual(refusal("P", in: "B", ["P/C", "B"]), .groupHasSubgroups)
        XCTAssertEqual(order("P", to: nil, ["P/C", "B"]), ["P/C", "B"])
    }

    func testNestingMovesGroupToEndOfParentRun() {
        XCTAssertEqual(order("A", to: "P", ["A", "-", "P", "P/C", "-"]),
                       ["-", "P", "P/C", "A", "-"])
    }

    func testMakingTopLevelMovesGroupPastOldParent() {
        XCTAssertEqual(order("C", to: nil, ["P", "P/C", "P", "-"]),
                       ["P", "P", "P/C", "-"])
    }

    func testTopLevelGroupMadeTopLevelStaysPut() {
        XCTAssertEqual(order("A", to: nil, ["A", "-"]), ["A", "-"])
    }

    // MARK: - Depth violations

    private func violations(_ tabs: [String]) -> [String] {
        let (groupIDs, parentIDs) = split(tabs)
        return iTermTabGroupNesting.groupsViolatingNestingDepth(groupIDs: groupIDs, parentIDs: parentIDs)
    }

    func testValidNestingHasNoViolations() {
        XCTAssertEqual(violations(["P", "P/C", "P/D", "-", "S", "S/T"]), [])
    }

    // The field report: Q was both a parent (of F) and a sub-group of S.
    func testGroupThatIsBothParentAndSubgroupViolates() {
        XCTAssertEqual(violations(["Q/F", "Q/F", "S", "S/Q", "-"]), ["Q"])
    }

    // A parent with no direct tabs appears only as a parent id.
    func testParentWithoutDirectTabsStillCounts() {
        XCTAssertEqual(violations(["S", "S/Q", "Q/F"]), ["Q"])
    }

    func testGroupNestedInItselfViolates() {
        XCTAssertEqual(violations(["G/G", "-"]), ["G"])
    }

    func testEachViolatorIsReportedOnceInTabOrder() {
        XCTAssertEqual(violations(["A/B", "B/C", "A/B", "C/D", "B/C"]), ["B", "C"])
    }

    // Applies the planned repairs and renders the tabs as "parent/group".
    private func repaired(_ tabs: [String]) -> [String] {
        let (groupIDs, initialParents) = split(tabs)
        var parentIDs = initialParents
        for repair in iTermTabGroupNesting.nestingDepthRepairs(groupIDs: groupIDs, parentIDs: parentIDs) {
            for i in groupIDs.indices where groupIDs[i] == repair.groupID {
                parentIDs[i] = repair.newParentID
            }
        }
        XCTAssertEqual(iTermTabGroupNesting.groupsViolatingNestingDepth(groupIDs: groupIDs, parentIDs: parentIDs), [])
        return zip(groupIDs, parentIDs).map { groupID, parentID in
            guard let groupID else { return "-" }
            return parentID.map { "\($0)/\(groupID)" } ?? groupID
        }
    }

    func testValidNestingNeedsNoRepair() {
        let (groupIDs, parentIDs) = split(["P", "P/C", "-", "S/T"])
        XCTAssertTrue(iTermTabGroupNesting.nestingDepthRepairs(groupIDs: groupIDs, parentIDs: parentIDs).isEmpty)
    }

    func testViolatorBecomesTopLevelWhenItsParentHasDirectTabs() {
        XCTAssertEqual(repaired(["Q/F", "Q/F", "S", "S/Q", "-"]),
                       ["Q/F", "Q/F", "S", "Q", "-"])
    }

    func testViolatorBecomesTopLevelWhenItsParentHasAnotherSubgroup() {
        XCTAssertEqual(repaired(["S/Q", "Q/F", "S/R"]),
                       ["Q", "Q/F", "S/R"])
    }

    // S has no direct tabs and Q is its only sub-group, so promoting Q would
    // leave no tab carrying S's name and color. F moves up under S instead.
    func testLastSubgroupOfParentWithoutDirectTabsKeepsTheParentAlive() {
        XCTAssertEqual(repaired(["S/Q", "Q/F", "Q/F"]),
                       ["S/Q", "S/F", "S/F"])
    }

    func testGroupNestedInItselfBecomesTopLevel() {
        XCTAssertEqual(repaired(["G/G", "-"]), ["G", "-"])
    }

    // C first moves up under A to keep A alive, then A has B as well, so C
    // can go top-level with D under it.
    func testChainIsFlattenedWithoutLosingAnyGroup() {
        XCTAssertEqual(repaired(["A/B", "B/C", "C/D"]),
                       ["A/B", "C", "C/D"])
    }
}
