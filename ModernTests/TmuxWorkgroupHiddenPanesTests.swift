//
//  TmuxWorkgroupHiddenPanesTests.swift
//  iTerm2 ModernTests
//
//  Panes in parked windows that no workgroup on this Mac can show: those of an instance it has not
//  adopted (no local match, declined, unreadable, or ended without cleaning up). The user is
//  offered to open them in tabs or stop them; each pane is then handled from a fresh snapshot
//  while the workgroup lock is held.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxWorkgroupHiddenPanesTests: XCTestCase {
    private typealias S = TmuxWorkgroupState
    private typealias C = TmuxWorkgroupCommands
    private typealias Hidden = TmuxWorkgroupHiddenPanes
    private typealias Release = TmuxWorkgroupHiddenPaneRelease

    private func config(_ id: String, _ kind: iTermWorkgroupSessionConfig.Kind, parent: String?) -> iTermWorkgroupSessionConfig {
        return iTermWorkgroupSessionConfig(uniqueIdentifier: id, parentID: parent, kind: kind, profileGUID: nil,
                                           command: "", urlString: "", toolbarItems: [], displayName: id)
    }

    // Positions: 0 root, 1 and 2 peers.
    private var record: String {
        let workgroup = iTermWorkgroup(uniqueIdentifier: "WG", name: "W", sessions: [
            config("ROOT", .root, parent: nil),
            config("P1", .peer, parent: "ROOT"),
            config("P2", .peer, parent: "ROOT"),
        ])
        return S.InstanceRecord(workgroupID: "WG", gitBase: "main", skeleton: S.Skeleton(workgroup: workgroup)!).encoded
    }

    private func tag(_ position: Int, of instanceID: String = "I") -> String {
        return S.PaneTag(instanceID: instanceID, position: position).encoded
    }

    private func parked(_ instanceID: String = "I") -> String {
        return S.ParkedTag(instanceID: instanceID).encoded
    }

    /// Replies to the snapshot's three queries. A pane is "%id @window WxH tag". `records` are
    /// instance IDs given a readable record; `unreadable` ones get one that isn't.
    private func snapshot(records: [String] = ["I"], unreadable: [String] = [],
                          panes: [String], windows: [String]) -> [String?] {
        let show = (records.map { S.instanceOptionName(instanceID: $0) + " " + record } +
                    unreadable.map { S.instanceOptionName(instanceID: $0) + " g_zz" }).joined(separator: "\n")
        return [show, panes.joined(separator: "\n"), windows.joined(separator: "\n")]
    }

    private func find(_ replies: [String?], adoptedHere: Set<String> = []) -> [Hidden.Group] {
        let panes = TmuxWorkgroupAdoption.panes(listPanesReply: replies[1]!)
        let windows = TmuxWorkgroupAdoption.windows(listWindowsReply: replies[2]!)
        let derivation = S.derive(panes: panes, windows: windows,
                                  instanceOptions: TmuxWorkgroupAdoption.instanceOptions(showReply: replies[0]!))
        return Hidden.find(panes: panes, windows: windows, derivation: derivation, adoptedHere: adoptedHere)
    }

    /// An instance with its leader in view and both peers parked.
    private var unadopted: [String?] {
        return snapshot(panes: ["%0 @1 80x24 \(tag(0))", "%1 @2 80x24 \(tag(1))", "%2 @3 80x24 \(tag(2))"],
                        windows: ["@1 ", "@2 \(parked())", "@3 \(parked())"])
    }

    // MARK: - Finding them

    // Peers of an instance not adopted here are hidden here, though another Mac may be using them.
    func testAnUnadoptedInstancesParkedPeersAreHidden() {
        XCTAssertEqual(find(unadopted),
                       [Hidden.Group(instanceID: "I", paneIDs: [1, 2], inUseElsewhere: true, leaderPaneID: 0)])
    }

    func testAnAdoptedInstancesParkedPeersAreNot() {
        XCTAssertEqual(find(unadopted, adoptedHere: ["I"]), [])
    }

    // An instance being removed takes its parked peers with it.
    func testAnInstanceWithNoLeaderIsLeftToBeRemoved() {
        XCTAssertEqual(find(snapshot(panes: ["%1 @2 80x24 \(tag(1))"], windows: ["@2 \(parked())"])), [])
    }

    // A parked window whose instance has ended: its untagged pane is hidden, and nobody else
    // can be using it. A tagged member there is killed by the orphan clean-up instead.
    func testAnEndedInstancesParkedWindowsAreHidden() {
        XCTAssertEqual(find(snapshot(records: [],
                                     panes: ["%4 @2 80x24 ", "%5 @3 80x24 \(tag(1, of: "X"))"],
                                     windows: ["@2 \(parked("X"))", "@3 \(parked("X"))"])),
                       [Hidden.Group(instanceID: "X", paneIDs: [4], inUseElsewhere: false, leaderPaneID: nil)])
    }

    // Another iTerm2's newer format: still in use there.
    func testAnUnreadableInstancesParkedPanesAreHidden() {
        XCTAssertEqual(find(snapshot(records: [], unreadable: ["U"],
                                     panes: ["%0 @1 80x24 ", "%7 @4 80x24 \(tag(1, of: "U"))"],
                                     windows: ["@1 ", "@4 \(parked("U"))"])),
                       [Hidden.Group(instanceID: "U", paneIDs: [7], inUseElsewhere: true, leaderPaneID: nil)])
    }

    // A member of an adopted instance in another's parked window is its binding's to bring out.
    func testAnAdoptedInstancesMemberInAnothersParkedWindowIsLeftToItsBinding() {
        let replies = snapshot(records: ["I", "J"],
                               panes: ["%0 @1 80x24 \(tag(0))", "%1 @2 80x24 \(tag(1))",
                                       "%3 @2 40x24 \(tag(1, of: "J"))", "%4 @5 80x24 \(tag(0, of: "J"))"],
                               windows: ["@1 ", "@2 \(parked())", "@5 "])
        XCTAssertEqual(find(replies, adoptedHere: ["J"]),
                       [Hidden.Group(instanceID: "I", paneIDs: [1], inUseElsewhere: true, leaderPaneID: 0)])
    }

    // MARK: - Opening and stopping them

    private func firstStep(_ choice: Release.Choice, paneIDs: [Int], _ replies: [String?]) -> Release.Action? {
        var r = Release(sessionID: 3, instanceID: "I", paneIDs: paneIDs, choice: choice, adoptedHere: [])
        XCTAssertEqual(r.start(), .snapshot(TmuxWorkgroupAdoption.queries(sessionID: 3)))
        return r.didSnapshot(replies)
    }

    // Untagged so no workgroup parks it again, and moved into an ordinary window, which every
    // client shows as a tab.
    func testOpeningAPaneAloneInItsWindow() {
        XCTAssertEqual(firstStep(.open, paneIDs: [1, 2], unadopted),
                       .repair([C.untagPane(paneID: 1)] +
                               C.bringOutPane(sessionID: 3, paneID: 1, windowID: 2, sharesWindow: false)))
    }

    func testOpeningAPaneThatSharesItsWindow() {
        let replies = snapshot(records: [], panes: ["%4 @2 80x24 ", "%5 @2 80x24 "], windows: ["@2 \(parked())"])
        XCTAssertEqual(firstStep(.open, paneIDs: [4, 5], replies),
                       .repair([C.untagPane(paneID: 4)] +
                               C.bringOutPane(sessionID: 3, paneID: 4, windowID: 2, sharesWindow: true)))
    }

    func testStopping() {
        XCTAssertEqual(firstStep(.stop, paneIDs: [1, 2], unadopted), .repair([C.killPane(1)]))
    }

    // Each pane is handled from a fresh snapshot; one another client brought out meanwhile, or one
    // that exited, is skipped, and panes that appeared since the offer are left for a new one.
    func testOnePanePerSnapshotOnlyThoseOffered() {
        var r = Release(sessionID: 3, instanceID: "I", paneIDs: [1, 2], choice: .stop, adoptedHere: [])
        _ = r.start()
        XCTAssertEqual(r.didSnapshot(unadopted), .repair([C.killPane(1)]))
        XCTAssertEqual(r.didRepair(), .snapshot(TmuxWorkgroupAdoption.queries(sessionID: 3)))
        let rest = snapshot(panes: ["%0 @1 80x24 \(tag(0))", "%2 @1 80x24 ", "%9 @6 80x24 \(tag(1))"],
                            windows: ["@1 ", "@6 \(parked())"])
        XCTAssertEqual(r.didSnapshot(rest), .finished(repairs: 1), "%2 is in view now; %9 was not offered")
    }

    func testFinishesAfterEachOfferedPane() {
        var r = Release(sessionID: 3, instanceID: "I", paneIDs: [1], choice: .stop, adoptedHere: [])
        _ = r.start()
        XCTAssertEqual(r.didSnapshot(unadopted), .repair([C.killPane(1)]))
        XCTAssertEqual(r.didRepair(), .finished(repairs: 1), "no more than one step per offered pane")
    }

    func testTmuxNotAnsweringAbandons() {
        var r = Release(sessionID: 3, instanceID: "I", paneIDs: [1], choice: .open, adoptedHere: [])
        _ = r.start()
        XCTAssertEqual(r.didSnapshot([nil, nil, nil]), .abandoned)
    }

    func testEventsOutOfTurnAreIgnored() {
        var r = Release(sessionID: 3, instanceID: "I", paneIDs: [1], choice: .open, adoptedHere: [])
        XCTAssertNil(r.didRepair())
        XCTAssertNil(r.didSnapshot(unadopted))
        _ = r.start()
        XCTAssertNil(r.start())
        XCTAssertNil(r.didRepair())
    }
}
