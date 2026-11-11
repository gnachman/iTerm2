//
//  TmuxTabGroupsTests.swift
//  iTerm2 ModernTests
//
//  Tab groups of tmux tabs round-trip through the @tab_groups option's encoding.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxTabGroupsTests: XCTestCase {
    private let red = NSColor(fromHexString: "#ff0000")!

    func testEmptyEncodesToEmptyString() {
        XCTAssertEqual(iTermTmuxTabGroups.encode([:]), "")
        XCTAssertTrue(iTermTmuxTabGroups.decode("").isEmpty)
    }

    func testRoundTrip() {
        let memberships: [NSNumber: iTermTmuxTabGroupMembership] = [
            1: iTermTmuxTabGroupMembership(groupID: "A", name: "Build “server”", color: red, collapsed: true),
            2: iTermTmuxTabGroupMembership(groupID: "A", name: "Build “server”", color: red, collapsed: true),
            5: iTermTmuxTabGroupMembership(groupID: "B", name: nil, color: nil, collapsed: false),
        ]
        let decoded = iTermTmuxTabGroups.decode(iTermTmuxTabGroups.encode(memberships))
        XCTAssertEqual(Set(decoded.keys), [1, 2, 5])
        for windowID in [1, 2] as [NSNumber] {
            let membership = decoded[windowID]!
            XCTAssertEqual(membership.groupID, "A")
            XCTAssertEqual(membership.name, "Build “server”")
            XCTAssertEqual(membership.color?.hexString(), red.hexString())
            XCTAssertTrue(membership.collapsed)
        }
        XCTAssertEqual(decoded[5]!.groupID, "B")
        XCTAssertNil(decoded[5]!.name)
        XCTAssertNil(decoded[5]!.color)
        XCTAssertFalse(decoded[5]!.collapsed)
    }

    // The controller skips redundant saves by comparing encoded strings, so equal state must
    // encode identically regardless of dictionary order.
    func testEncodingIsDeterministic() {
        var memberships = [NSNumber: iTermTmuxTabGroupMembership]()
        for i in 0..<20 {
            memberships[NSNumber(value: i)] = iTermTmuxTabGroupMembership(
                groupID: "G\(i % 3)", name: "Group \(i % 3)", color: red, collapsed: false)
        }
        let first = iTermTmuxTabGroups.encode(memberships)
        let reordered = Dictionary(uniqueKeysWithValues: memberships.reversed())
        XCTAssertEqual(iTermTmuxTabGroups.encode(reordered), first)
    }

    func testMalformedInputDecodesToNothing() {
        XCTAssertTrue(iTermTmuxTabGroups.decode("not json").isEmpty)
        XCTAssertTrue(iTermTmuxTabGroups.decode("[1,2]").isEmpty)
    }

    func testTabReferencingUnknownGroupIsSkipped() {
        let decoded = iTermTmuxTabGroups.decode(#"{"groups":{"A":{"collapsed":false}},"tabs":{"1":"A","2":"Z","x":"A"}}"#)
        XCTAssertEqual(Set(decoded.keys), [1])
    }

    private func member(_ groupID: String) -> iTermTmuxTabGroupMembership {
        return iTermTmuxTabGroupMembership(groupID: groupID, name: groupID, color: nil, collapsed: false)
    }

    // An older iTerm2 moved window 3 out to its own window. The group stays where most of its
    // members are and window 3 leaves it.
    func testMemberMovedToAnotherWindowLeavesGroup() {
        let memberships: [NSNumber: iTermTmuxTabGroupMembership] = [1: member("A"), 2: member("A"), 3: member("A")]
        let windowOf: [NSNumber: String] = [1: "w1", 2: "w1", 3: "w2"]
        let confined = iTermTmuxTabGroups.confineEachGroupToOneWindow(memberships) { windowOf[$0] }
        XCTAssertEqual(Set(confined.keys), [1, 2])
    }

    func testTieGoesToWindowWithLowestWindowID() {
        let memberships: [NSNumber: iTermTmuxTabGroupMembership] = [4: member("A"), 7: member("A")]
        let windowOf: [NSNumber: String] = [4: "w2", 7: "w1"]
        let confined = iTermTmuxTabGroups.confineEachGroupToOneWindow(memberships) { windowOf[$0] }
        XCTAssertEqual(Set(confined.keys), [4])
    }

    func testGroupsInOneWindowAndUnknownWindowsAreUntouched() {
        let memberships: [NSNumber: iTermTmuxTabGroupMembership] = [
            1: member("A"), 2: member("A"), 3: member("B"), 4: member("B"), 9: member("A")]
        let windowOf: [NSNumber: String] = [1: "w1", 2: "w1", 3: "w2", 4: "w2"]
        let confined = iTermTmuxTabGroups.confineEachGroupToOneWindow(memberships) { windowOf[$0] }
        XCTAssertEqual(Set(confined.keys), [1, 2, 3, 4, 9])
    }

    // MARK: - Nesting (@tab_group_parents)

    func testParentsRoundTrip() {
        let parents = ["C": iTermTmuxTabGroupMembership(groupID: "P", name: "Parent “one”", color: red, collapsed: true)]
        let decoded = iTermTmuxTabGroups.decodeParents(iTermTmuxTabGroups.encodeParents(parents))
        XCTAssertEqual(Set(decoded.keys), ["C"])
        XCTAssertEqual(decoded["C"]!.groupID, "P")
        XCTAssertEqual(decoded["C"]!.name, "Parent “one”")
        XCTAssertEqual(decoded["C"]!.color?.hexString(), red.hexString())
        XCTAssertTrue(decoded["C"]!.collapsed)
        XCTAssertEqual(iTermTmuxTabGroups.encodeParents([:]), "")
    }

    func testMalformedParentsDecodeToNothing() {
        XCTAssertTrue(iTermTmuxTabGroups.decodeParents("not json").isEmpty)
        XCTAssertTrue(iTermTmuxTabGroups.decodeParents(#"{"C":{"name":"no id"}}"#).isEmpty)
        XCTAssertTrue(iTermTmuxTabGroups.decodeParents(#"{"C":{"id":"C"}}"#).isEmpty)
        // One bad entry doesn't cost the others.
        XCTAssertEqual(iTermTmuxTabGroups.decodeParents(#"{"C":{"id":"P"},"D":"junk","E":7}"#).keys.sorted(), ["C"])
    }

    // An older iTerm2 renamed, recolored and collapsed P, which has a direct member, so only
    // @tab_groups knows. The parent link takes that definition; a parent with no direct members
    // keeps its own.
    func testParentsAdoptDefinitionsFromTabGroups() {
        let parents = ["S": iTermTmuxTabGroupMembership(groupID: "P", name: "Work", color: red, collapsed: false),
                       "T": iTermTmuxTabGroupMembership(groupID: "Q", name: "Solo", color: red, collapsed: false)]
        let memberships: [NSNumber: iTermTmuxTabGroupMembership] = [
            0: member("S"),
            1: iTermTmuxTabGroupMembership(groupID: "P", name: "Play", color: .systemBlue, collapsed: true),
            2: member("T")]
        let adopted = iTermTmuxTabGroups.adoptDefinitions(parents, from: memberships)
        XCTAssertEqual(adopted["S"]!.groupID, "P")
        XCTAssertEqual(adopted["S"]!.name, "Play")
        XCTAssertEqual(adopted["S"]!.color?.hexString(), NSColor.systemBlue.hexString())
        XCTAssertTrue(adopted["S"]!.collapsed)
        XCTAssertEqual(adopted["T"]!.name, "Solo")
    }

    // An iTerm2 without nesting keeps reading @tab_groups as before: a sub-group's tabs are in
    // their own group, so they show up as an ordinary group.
    func testOlderReaderSeesSubgroupsAsGroups() {
        let memberships: [NSNumber: iTermTmuxTabGroupMembership] = [1: member("P"), 2: member("C")]
        let decoded = iTermTmuxTabGroups.decode(iTermTmuxTabGroups.encode(memberships))
        XCTAssertEqual(decoded[1]!.groupID, "P")
        XCTAssertEqual(decoded[2]!.groupID, "C")
    }

    // An older iTerm2 ungrouped sub-group D's tabs, so nothing references D any more.
    func testPruneDropsParentsOfVanishedSubgroups() {
        let parents = ["C": member("P"), "D": member("P")]
        let memberships: [NSNumber: iTermTmuxTabGroupMembership] = [1: member("P"), 2: member("C")]
        XCTAssertEqual(Set(iTermTmuxTabGroups.prune(parents, memberships: memberships).keys), ["C"])
    }

    func testPruneDropsTwoLevelNesting() {
        let parents = ["C": member("P"), "P": member("Q")]
        let memberships: [NSNumber: iTermTmuxTabGroupMembership] = [1: member("P"), 2: member("C")]
        XCTAssertEqual(Set(iTermTmuxTabGroups.prune(parents, memberships: memberships).keys), ["P"])
    }

    // An older iTerm2 moved sub-group D to another window. The parent stays with its direct
    // member and D becomes top-level.
    func testSubgroupInAnotherWindowLosesParent() {
        let parents = ["C": member("P"), "D": member("P")]
        let memberships: [NSNumber: iTermTmuxTabGroupMembership] = [1: member("P"), 2: member("C"), 3: member("D")]
        let windowOf: [NSNumber: String] = [1: "w1", 2: "w1", 3: "w2"]
        let confined = iTermTmuxTabGroups.confineEachParentToOneWindow(parents, memberships: memberships) { windowOf[$0] }
        XCTAssertEqual(Set(confined.keys), ["C"])
    }

    func testParentWithOnlySubgroupsInOneWindowIsKept() {
        let parents = ["C": member("P"), "D": member("P")]
        let memberships: [NSNumber: iTermTmuxTabGroupMembership] = [2: member("C"), 3: member("D")]
        let windowOf: [NSNumber: String] = [2: "w1", 3: "w1"]
        let confined = iTermTmuxTabGroups.confineEachParentToOneWindow(parents, memberships: memberships) { windowOf[$0] }
        XCTAssertEqual(Set(confined.keys), ["C", "D"])
    }

    // The parent's direct member is in one window and more of its sub-group's tabs are in
    // another. The parent stays with its direct member, so the sub-group becomes top-level
    // rather than the parent living in two windows.
    func testParentStaysWithItsDirectMembers() {
        let parents = ["S": member("P")]
        let memberships: [NSNumber: iTermTmuxTabGroupMembership] = [1: member("P"), 2: member("S"), 3: member("S")]
        let windowOf: [NSNumber: String] = [1: "X", 2: "Y", 3: "Y"]
        let confined = iTermTmuxTabGroups.confineEachParentToOneWindow(parents, memberships: memberships) { windowOf[$0] }
        XCTAssertTrue(confined.isEmpty)
    }

    // Sub-groups decide only when the parent has no direct members.
    func testParentWithoutDirectMembersGoesWithMostSubgroupTabs() {
        let parents = ["S": member("P"), "T": member("P")]
        let memberships: [NSNumber: iTermTmuxTabGroupMembership] = [1: member("S"), 2: member("T"), 3: member("T")]
        let windowOf: [NSNumber: String] = [1: "X", 2: "Y", 3: "Y"]
        let confined = iTermTmuxTabGroups.confineEachParentToOneWindow(parents, memberships: memberships) { windowOf[$0] }
        XCTAssertEqual(Set(confined.keys), ["T"])
    }
}
