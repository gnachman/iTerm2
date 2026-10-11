//
//  TmuxWorkgroupAdoptionTests.swift
//  iTerm2 ModernTests
//
//  When iTerm2 attaches to a tmux session, or learns that another client changed one, it reads the
//  workgroup state from tmux and decides, per instance: adopt it with the one matching local
//  workgroup, ask which of several matching workgroups to use, report that none match, remove an
//  instance whose leader is gone, or forget one adopted here whose record is gone.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxWorkgroupAdoptionTests: XCTestCase {
    private typealias A = TmuxWorkgroupAdoption
    private typealias S = TmuxWorkgroupState

    private let splitSettings = SplitSettings(orientation: .vertical, side: .trailingOrBottom, location: 0.5)

    private func config(_ id: String, _ kind: iTermWorkgroupSessionConfig.Kind, parent: String?,
                        mode: iTermWorkgroupSessionMode = .regular) -> iTermWorkgroupSessionConfig {
        var c = iTermWorkgroupSessionConfig(uniqueIdentifier: id, parentID: parent, kind: kind, profileGUID: nil,
                                            command: "", urlString: "", toolbarItems: [], displayName: id)
        c.mode = mode
        return c
    }

    // Positions: 0 root, 1 diff peer, 2 split, 3 tab.
    private func workgroup(_ id: String, prefix: String = "") -> iTermWorkgroup {
        return iTermWorkgroup(uniqueIdentifier: id, name: id, sessions: [
            config(prefix + "ROOT", .root, parent: nil),
            config(prefix + "DIFF", .peer, parent: prefix + "ROOT", mode: .diff),
            config(prefix + "SPLIT", .split(splitSettings), parent: prefix + "ROOT"),
            config(prefix + "TAB", .tab, parent: prefix + "ROOT"),
        ])
    }

    private func record(_ wg: iTermWorkgroup, base: String = "main") -> S.InstanceRecord {
        return S.InstanceRecord(workgroupID: wg.uniqueIdentifier, gitBase: base, skeleton: S.Skeleton(workgroup: wg)!)
    }

    private func tag(_ instance: String, _ position: Int) -> String {
        return S.PaneTag(instanceID: instance, position: position).encoded
    }

    private func derive(_ records: [String: S.InstanceRecord], panes: [S.Pane],
                        windows: [S.Window] = [S.Window(windowID: 1, parkedTag: nil)]) -> S.Derivation {
        return S.derive(panes: panes, windows: windows, instanceOptions: records.mapValues(\.encoded))
    }

    private var windowsWithAParkedOne: [S.Window] {
        return [S.Window(windowID: 1, parkedTag: nil),
                S.Window(windowID: 9, parkedTag: S.ParkedTag(instanceID: "I").encoded)]
    }

    private func adoption(_ workgroup: iTermWorkgroup, leader: Int, members: [String: Int] = [:],
                          peers: [String: Int] = [:], active: String) -> A.Step {
        return .adopt(A.Adoption(instanceID: "I", workgroup: workgroup, gitBase: "main", leaderPaneID: leader,
                                 memberPaneIDsByConfigID: members, peerPaneIDsByConfigID: peers,
                                 activeConfigID: active))
    }

    // MARK: - Parsing tmux's replies

    func testParseShowReply() {
        let r = record(workgroup("W")).encoded
        let reply = [
            "@hidden i_31",
            S.instanceOptionName(instanceID: "I1") + " " + r,
            S.instanceOptionName(instanceID: "I2") + " \"g_zz\"",
            "@iterm2_wg_lock l_31",
            "status on",
            "",
        ].joined(separator: "\n")
        XCTAssertEqual(A.instanceOptions(showReply: reply), ["I1": r, "I2": "\"g_zz\""])
    }

    func testParseListPanes() {
        let t = tag("I", 0)
        XCTAssertEqual(A.panes(listPanesReply: "%1 @2 80x24 \(t)\n%3 @2 40x10 \n%4 @5 1x2\n%6 @5 bad x\nbogus\n%x @2 80x24 \(t)\n"),
                       [S.Pane(paneID: 1, windowID: 2, tag: t, size: S.PaneSize(width: 80, height: 24)),
                        S.Pane(paneID: 3, windowID: 2, tag: nil, size: S.PaneSize(width: 40, height: 10)),
                        S.Pane(paneID: 4, windowID: 5, tag: nil, size: S.PaneSize(width: 1, height: 2)),
                        S.Pane(paneID: 6, windowID: 5, tag: "x", size: nil)])
    }

    func testParseListWindows() {
        let t = S.ParkedTag(instanceID: "I").encoded
        XCTAssertEqual(A.windows(listWindowsReply: "@1 \n@9 \(t)\n@x \(t)\n"),
                       [S.Window(windowID: 1, parkedTag: nil), S.Window(windowID: 9, parkedTag: t)])
    }

    // MARK: - Planning

    // One matching workgroup: adopt, mapping split and tab members and the parked peer by position.
    func testAdoptTheOnlyMatch() throws {
        let local = workgroup("LOCAL", prefix: "L-")
        let d = derive(["I": record(workgroup("REMOTE"))],
                       panes: [S.Pane(paneID: 1, windowID: 1, tag: tag("I", 0)),
                               S.Pane(paneID: 2, windowID: 1, tag: tag("I", 2)),
                               S.Pane(paneID: 3, windowID: 1, tag: tag("I", 3)),
                               S.Pane(paneID: 4, windowID: 9, tag: tag("I", 1))],
                       windows: windowsWithAParkedOne)
        XCTAssertEqual(A.plan(derivation: d, localWorkgroups: [local], adoptedHere: []),
                       [adoption(local, leader: 1, members: ["L-SPLIT": 2, "L-TAB": 3], peers: ["L-DIFF": 4],
                                 active: "L-ROOT")])
    }

    // The diff peer is in view and the leader parked: adopt with the peer active.
    func testAdoptWhileAPeerIsInView() throws {
        let local = workgroup("LOCAL", prefix: "L-")
        let d = derive(["I": record(workgroup("REMOTE"))],
                       panes: [S.Pane(paneID: 1, windowID: 9, tag: tag("I", 0)),
                               S.Pane(paneID: 4, windowID: 1, tag: tag("I", 1))],
                       windows: windowsWithAParkedOne)
        XCTAssertEqual(A.plan(derivation: d, localWorkgroups: [local], adoptedHere: []),
                       [adoption(local, leader: 1, peers: ["L-DIFF": 4], active: "L-DIFF")])
    }

    // A split that hosts peers of its own. Positions: 0 root, 1 split, 2 and 3 its peers.
    private func nestedWorkgroup(_ id: String, prefix: String = "") -> iTermWorkgroup {
        return iTermWorkgroup(uniqueIdentifier: id, name: id, sessions: [
            config(prefix + "ROOT", .root, parent: nil),
            config(prefix + "SPLIT", .split(splitSettings), parent: prefix + "ROOT"),
            config(prefix + "SP1", .peer, parent: prefix + "SPLIT"),
            config(prefix + "SP2", .peer, parent: prefix + "SPLIT"),
        ])
    }

    // A nested group's peers are tmux panes too, and adoption maps them, with the member of each
    // nested group that is in view. Here the split's first peer is in view in the split's place.
    func testAdoptsANestedPeerGroup() throws {
        let local = nestedWorkgroup("LOCAL", prefix: "L-")
        let d = derive(["I": record(nestedWorkgroup("REMOTE"))],
                       panes: [S.Pane(paneID: 1, windowID: 1, tag: tag("I", 0)),
                               S.Pane(paneID: 2, windowID: 9, tag: tag("I", 1)),
                               S.Pane(paneID: 3, windowID: 1, tag: tag("I", 2)),
                               S.Pane(paneID: 4, windowID: 10, tag: tag("I", 3))],
                       windows: windowsWithAParkedOne + [S.Window(windowID: 10, parkedTag: S.ParkedTag(instanceID: "I").encoded)])
        guard case .adopt(let adoption) = try XCTUnwrap(A.plan(derivation: d, localWorkgroups: [local], adoptedHere: []).first) else {
            return XCTFail("not adopted")
        }
        XCTAssertEqual(adoption.memberPaneIDsByConfigID, ["L-SPLIT": 2])
        XCTAssertEqual(adoption.peerPaneIDsByConfigID, ["L-SP1": 3, "L-SP2": 4])
        XCTAssertEqual(adoption.activeConfigID, "L-ROOT")
        XCTAssertEqual(adoption.nestedActiveConfigIDs, ["L-SPLIT": "L-SP1"])
    }

    // A peer with a split of its own: the editor can't make one, but an imported workgroup can
    // have it. Locally the split is never spawned, and in tmux it is never created either: the
    // instance is adopted without it and nothing counts its absence as something to repair.
    // Positions: 0 root, 1 peer, 2 the peer's split.
    func testAPeersOwnSplitIsNeitherExpectedNorRepaired() throws {
        func peerWithSplit(_ id: String, prefix: String = "") -> iTermWorkgroup {
            return iTermWorkgroup(uniqueIdentifier: id, name: id, sessions: [
                config(prefix + "ROOT", .root, parent: nil),
                config(prefix + "P1", .peer, parent: prefix + "ROOT"),
                config(prefix + "P1SPLIT", .split(splitSettings), parent: prefix + "P1"),
            ])
        }
        let local = peerWithSplit("LOCAL", prefix: "L-")
        let d = derive(["I": record(peerWithSplit("REMOTE"))],
                       panes: [S.Pane(paneID: 1, windowID: 1, tag: tag("I", 0)),
                               S.Pane(paneID: 4, windowID: 9, tag: tag("I", 1))],
                       windows: windowsWithAParkedOne)
        let instance = try XCTUnwrap(d.instances.first)
        XCTAssertEqual(instance.problems, [])
        XCTAssertNil(TmuxWorkgroupRepair.nextRepair(instance: instance, panes: [], sessionID: 3))
        XCTAssertEqual(A.plan(derivation: d, localWorkgroups: [local], adoptedHere: []),
                       [adoption(local, leader: 1, peers: ["L-P1": 4], active: "L-ROOT")])
    }

    func testSeveralMatchesWithTheOriginalAdoptsIt() {
        let original = workgroup("REMOTE")
        let other = workgroup("OTHER")
        let d = derive(["I": record(original)], panes: [S.Pane(paneID: 1, windowID: 1, tag: tag("I", 0))])
        XCTAssertEqual(A.plan(derivation: d, localWorkgroups: [other, original], adoptedHere: []),
                       [adoption(original, leader: 1, active: "ROOT")])
    }

    func testSeveralMatchesWithoutTheOriginalAsks() throws {
        let a = workgroup("A")
        let b = workgroup("B")
        let d = derive(["I": record(workgroup("REMOTE"))], panes: [S.Pane(paneID: 1, windowID: 1, tag: tag("I", 0))])
        let instance = try XCTUnwrap(d.instances.first)
        XCTAssertEqual(A.plan(derivation: d, localWorkgroups: [a, b], adoptedHere: []),
                       [.choose(instance: instance, candidates: [a, b])])
        XCTAssertEqual(A.adoptStep(instance: instance, workgroup: b), adoption(b, leader: 1, active: "ROOT"))
    }

    func testNoMatchIsReported() {
        let unrelated = iTermWorkgroup(uniqueIdentifier: "U", name: "U", sessions: [config("R", .root, parent: nil)])
        let d = derive(["I": record(workgroup("REMOTE"))], panes: [S.Pane(paneID: 1, windowID: 1, tag: tag("I", 0))])
        XCTAssertEqual(A.plan(derivation: d, localWorkgroups: [unrelated], adoptedHere: []), [.unmatched(instanceID: "I")])
    }

    // Already adopted (or entered) here: nothing to do.
    func testAlreadyAdoptedIsLeftAlone() {
        let d = derive(["I": record(workgroup("W"))], panes: [S.Pane(paneID: 1, windowID: 1, tag: tag("I", 0))])
        XCTAssertEqual(A.plan(derivation: d, localWorkgroups: [workgroup("W")], adoptedHere: ["I"]), [])
    }

    // The leader exited while no client was there to end the instance.
    func testLeaderGoneRemovesTheInstance() {
        let d = derive(["I": record(workgroup("W"))], panes: [S.Pane(paneID: 2, windowID: 1, tag: tag("I", 2))])
        XCTAssertEqual(A.plan(derivation: d, localWorkgroups: [workgroup("W")], adoptedHere: []),
                       [.removeFromServer(instanceID: "I")])
        XCTAssertEqual(A.plan(derivation: d, localWorkgroups: [], adoptedHere: ["I"]),
                       [.removeFromServer(instanceID: "I")])
    }

    // Adopted here, but another client ended it: forget it here, without touching the server.
    func testRecordGoneForgetsLocally() {
        let d = derive([:], panes: [])
        XCTAssertEqual(A.plan(derivation: d, localWorkgroups: [], adoptedHere: ["I"]), [.forget(instanceID: "I")])
    }

    // An interrupted removal left tags for an instance with no record: kill its members, but only
    // untag its leader, which is the user's own shell.
    func testOrphansAreCleanedUp() {
        let d = derive([:], panes: [S.Pane(paneID: 1, windowID: 1, tag: tag("GONE", 0)),
                                    S.Pane(paneID: 2, windowID: 1, tag: tag("GONE", 2)),
                                    S.Pane(paneID: 3, windowID: 1, tag: tag("GONE", 1))])
        XCTAssertEqual(A.plan(derivation: d, localWorkgroups: [], adoptedHere: []),
                       [.cleanUpOrphans(killPaneIDs: [2, 3], untagPaneIDs: [1])])
    }

    // A record another client's newer iTerm2 wrote is not ours to judge: never forgotten.
    func testUndecodableRecordIsNotForgotten() {
        let d = S.derive(panes: [], windows: [], instanceOptions: ["I": "g_ffff"])
        XCTAssertEqual(A.plan(derivation: d, localWorkgroups: [], adoptedHere: ["I"]), [])
    }
}
