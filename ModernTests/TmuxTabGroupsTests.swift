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
}
