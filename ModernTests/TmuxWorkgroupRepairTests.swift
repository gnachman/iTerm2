//
//  TmuxWorkgroupRepairTests.swift
//  iTerm2 ModernTests
//
//  Repairing an instance's state on the tmux server, once its lock is held. A crash, a lost
//  connection, or someone working in tmux directly can leave a peer group with two members in
//  view or none, a pane stranded in a parked window, or tags that name no member. Each repair is
//  one command list, decided from a fresh snapshot, and the next snapshot shows what is left, so
//  several clients repairing at once, or a crash partway through, converge.
//
//  Nothing the user ran is killed: a pane that is not a member is untagged or moved into a window
//  of its own. Moving a pane that is alone in its window goes through a new window (a placeholder
//  swapped with it, then its old window closed), because tmux would otherwise keep the window and
//  clients would never see it come or go.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxWorkgroupRepairTests: XCTestCase {
    private typealias S = TmuxWorkgroupState
    private typealias C = TmuxWorkgroupCommands
    private typealias Repair = TmuxWorkgroupRepair

    private func config(_ id: String, _ kind: iTermWorkgroupSessionConfig.Kind, parent: String?) -> iTermWorkgroupSessionConfig {
        return iTermWorkgroupSessionConfig(uniqueIdentifier: id, parentID: parent, kind: kind, profileGUID: nil,
                                           command: "", urlString: "", toolbarItems: [], displayName: id)
    }

    // Positions: 0 root, 1 and 2 peers, 3 split.
    private var record: String {
        let workgroup = iTermWorkgroup(uniqueIdentifier: "WG", name: "W", sessions: [
            config("ROOT", .root, parent: nil),
            config("P1", .peer, parent: "ROOT"),
            config("P2", .peer, parent: "ROOT"),
            config("SPLIT", .split(SplitSettings(orientation: .vertical, side: .trailingOrBottom, location: 0.5)),
                   parent: "ROOT"),
        ])
        return S.InstanceRecord(workgroupID: "WG", gitBase: "main", skeleton: S.Skeleton(workgroup: workgroup)!).encoded
    }

    private func tag(_ position: Int) -> String {
        return S.PaneTag(instanceID: "I", position: position).encoded
    }

    private var parked: String { S.ParkedTag(instanceID: "I").encoded }

    /// Replies to the snapshot's three queries. A pane is "%id @window WxH tag".
    private func snapshot(panes: [String], windows: [String]) -> [String?] {
        let show = S.instanceOptionName(instanceID: "I") + " " + record
        return [show, panes.joined(separator: "\n"), windows.joined(separator: "\n")]
    }

    /// The repair a snapshot calls for, starting fresh.
    private func firstRepair(panes: [String], windows: [String]) -> Repair.Action? {
        var r = Repair(sessionID: 3, instanceID: "I")
        XCTAssertEqual(r.start(), .snapshot(TmuxWorkgroupAdoption.queries(sessionID: 3)))
        return r.didSnapshot(snapshot(panes: panes, windows: windows))
    }

    // MARK: - Nothing to do

    func testAHealthyInstanceNeedsNothing() {
        XCTAssertEqual(firstRepair(panes: ["%0 @1 80x24 \(tag(0))", "%1 @2 80x24 \(tag(1))", "%2 @3 80x24 \(tag(2))"],
                                   windows: ["@1 ", "@2 \(parked)", "@3 \(parked)"]),
                       .finished(repairs: 0))
    }

    // An instance whose leader is gone is being removed, not repaired.
    func testAnInstanceWithNoLeaderIsLeftToBeRemoved() {
        XCTAssertEqual(firstRepair(panes: ["%1 @2 80x24 \(tag(1))"], windows: ["@2 \(parked)"]),
                       .finished(repairs: 0))
    }

    func testAnInstanceThatIsGoneIsAbandoned() {
        var r = Repair(sessionID: 3, instanceID: "I")
        _ = r.start()
        XCTAssertEqual(r.didSnapshot(["", "", ""]), .abandoned)
        var s = Repair(sessionID: 3, instanceID: "I")
        _ = s.start()
        XCTAssertEqual(s.didSnapshot([nil, nil, nil]), .abandoned, "tmux could not answer")
    }

    // MARK: - Tags that name no member

    // The lower pane ID keeps the member; the other just stops claiming it.
    func testADuplicateMemberIsUntagged() {
        XCTAssertEqual(firstRepair(panes: ["%0 @1 80x24 \(tag(0))", "%1 @2 80x24 \(tag(1))", "%5 @1 40x24 \(tag(1))"],
                                   windows: ["@1 ", "@2 \(parked)"]),
                       .repair([C.untagPane(paneID: 5)]))
    }

    func testATagForAnUnknownPositionIsRemoved() {
        XCTAssertEqual(firstRepair(panes: ["%0 @1 80x24 \(tag(0))", "%7 @1 40x24 \(tag(9))"], windows: ["@1 "]),
                       .repair([C.untagPane(paneID: 7)]))
    }

    // MARK: - Two peers in view

    // A peer in view beside the leader (a client died mid-switch, or someone joined it there in
    // tmux) goes back to a parked window of its own, pinned to the slot it fills when shown.
    func testAnExtraPeerSharingAWindowIsBrokenOutAndParked() {
        XCTAssertEqual(firstRepair(panes: ["%0 @1 80x24 \(tag(0))", "%1 @1 40x24 \(tag(1))"], windows: ["@1 "]),
                       .repair(C.parkPane(sessionID: 3, instanceID: "I", paneID: 1, windowID: 1,
                                          sharesWindow: true, width: 80, height: 24)))
    }

    func testAnExtraPeerAloneInAWindowIsMovedIntoAParkedWindow() {
        XCTAssertEqual(firstRepair(panes: ["%0 @1 80x24 \(tag(0))", "%1 @4 90x30 \(tag(1))"], windows: ["@1 ", "@4 "]),
                       .repair(C.parkPane(sessionID: 3, instanceID: "I", paneID: 1, windowID: 4,
                                          sharesWindow: false, width: 80, height: 24)))
    }

    func testParkPaneCommands() {
        let end = "'$3:{end}'"
        XCTAssertEqual(C.parkPane(sessionID: 3, instanceID: "I", paneID: 5, windowID: 2,
                                  sharesWindow: true, width: 80, height: 24), [
            "break-pane -d -a -s %5 -t \(end)",
            "set -w -t \(end) @iterm2_wg_parked \(parked)",
            "resize-window -t \(end) -x 80 -y 24",
        ])
        XCTAssertEqual(C.parkPane(sessionID: 3, instanceID: "I", paneID: 5, windowID: 2,
                                  sharesWindow: false, width: 80, height: 24), [
            "new-window -d -a -t \(end) -P -F '#{pane_id}' " + C.encodedCommand(script: C.waitingScript),
            "set -w -t \(end) @iterm2_wg_parked \(parked)",
            "resize-window -t \(end) -x 80 -y 24",
            "swap-pane -d -t %5 -s \(end)",
            "kill-window -t @2",
        ])
    }

    // MARK: - No peer in view

    // The peer in view exited, so its slot is gone and every remaining member is parked. The host
    // comes back, in a tab of its own.
    func testWithNothingInViewTheHostIsBroughtOut() {
        XCTAssertEqual(firstRepair(panes: ["%0 @2 80x24 \(tag(0))", "%1 @3 80x24 \(tag(1))"],
                                   windows: ["@2 \(parked)", "@3 \(parked)"]),
                       .repair(C.bringOutPane(sessionID: 3, paneID: 0, windowID: 2, sharesWindow: false)))
    }

    func testBringOutCommands() {
        let end = "'$3:{end}'"
        XCTAssertEqual(C.bringOutPane(sessionID: 3, paneID: 5, windowID: 2, sharesWindow: true),
                       ["break-pane -d -a -s %5 -t \(end)"])
        XCTAssertEqual(C.bringOutPane(sessionID: 3, paneID: 5, windowID: 2, sharesWindow: false), [
            "new-window -d -a -t \(end) -P -F '#{pane_id}' " + C.encodedCommand(script: C.waitingScript),
            "swap-pane -d -t %5 -s \(end)",
            "kill-window -t @2",
        ])
    }

    // MARK: - Stranded panes

    // A split member in a parked window (someone moved it there in tmux) would never be seen.
    func testAMemberStrandedInAParkedWindowIsBroughtOut() {
        XCTAssertEqual(firstRepair(panes: ["%0 @1 80x24 \(tag(0))", "%1 @2 80x24 \(tag(1))", "%3 @2 40x24 \(tag(3))"],
                                   windows: ["@1 ", "@2 \(parked)"]),
                       .repair(C.bringOutPane(sessionID: 3, paneID: 3, windowID: 2, sharesWindow: true)))
    }

    // MARK: - One at a time

    // Each repair is followed by a fresh snapshot, which shows what is left.
    func testRepairsOneProblemPerSnapshot() {
        var r = Repair(sessionID: 3, instanceID: "I")
        _ = r.start()
        XCTAssertEqual(r.didSnapshot(snapshot(panes: ["%0 @1 80x24 \(tag(0))", "%5 @1 40x24 \(tag(9))", "%6 @1 40x24 \(tag(8))"],
                                              windows: ["@1 "])),
                       .repair([C.untagPane(paneID: 5)]))
        XCTAssertEqual(r.didRepair(), .snapshot(TmuxWorkgroupAdoption.queries(sessionID: 3)))
        XCTAssertEqual(r.didSnapshot(snapshot(panes: ["%0 @1 80x24 \(tag(0))", "%5 @1 40x24 ", "%6 @1 40x24 \(tag(8))"],
                                              windows: ["@1 "])),
                       .repair([C.untagPane(paneID: 6)]))
        _ = r.didRepair()
        XCTAssertEqual(r.didSnapshot(snapshot(panes: ["%0 @1 80x24 \(tag(0))"], windows: ["@1 "])),
                       .finished(repairs: 2))
    }

    // A server that never settles (or a fake one) can't keep a client repairing forever.
    func testStopsAfterTheLimit() {
        var r = Repair(sessionID: 3, instanceID: "I", limit: 2)
        _ = r.start()
        let broken = snapshot(panes: ["%0 @1 80x24 \(tag(0))", "%5 @1 40x24 \(tag(9))"], windows: ["@1 "])
        XCTAssertEqual(r.didSnapshot(broken), .repair([C.untagPane(paneID: 5)]))
        _ = r.didRepair()
        XCTAssertEqual(r.didSnapshot(broken), .repair([C.untagPane(paneID: 5)]))
        XCTAssertEqual(r.didRepair(), .finished(repairs: 2))
    }

    func testEventsOutOfTurnAreIgnored() {
        var r = Repair(sessionID: 3, instanceID: "I")
        XCTAssertNil(r.didRepair())
        XCTAssertNil(r.didSnapshot(["", "", ""]))
        _ = r.start()
        XCTAssertNil(r.start())
        XCTAssertNil(r.didRepair())
    }
}
