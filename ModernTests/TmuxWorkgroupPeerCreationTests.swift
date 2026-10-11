//
//  TmuxWorkgroupPeerCreationTests.swift
//  iTerm2 ModernTests
//
//  Creating an instance's peers in tmux, once its lock is held: take a fresh snapshot, then create
//  only the requested peers it shows as missing, each complete in one command list (its parked
//  window, both tags, and the window pinned to the size of its group's visible slot). Whatever an
//  earlier attempt left, a crashed client included, is found by the snapshot, so creating is the
//  same at entry and on demand.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxWorkgroupPeerCreationTests: XCTestCase {
    private typealias S = TmuxWorkgroupState
    private typealias C = TmuxWorkgroupCommands
    private typealias Creation = TmuxWorkgroupPeerCreation

    private func config(_ id: String, _ kind: iTermWorkgroupSessionConfig.Kind, parent: String?,
                        mode: iTermWorkgroupSessionMode = .regular) -> iTermWorkgroupSessionConfig {
        var c = iTermWorkgroupSessionConfig(uniqueIdentifier: id, parentID: parent, kind: kind, profileGUID: nil,
                                            command: "", urlString: "", toolbarItems: [], displayName: id)
        c.mode = mode
        return c
    }

    // Positions: 0 root, 1 diff peer, 2 review peer, 3 split.
    private var workgroup: iTermWorkgroup {
        return iTermWorkgroup(uniqueIdentifier: "WG", name: "W", sessions: [
            config("ROOT", .root, parent: nil),
            config("DIFF", .peer, parent: "ROOT", mode: .diff),
            config("REVIEW", .peer, parent: "ROOT", mode: .codeReview),
            config("SPLIT", .split(SplitSettings(orientation: .vertical, side: .trailingOrBottom, location: 0.5)),
                   parent: "ROOT"),
        ])
    }

    private var record: String {
        S.InstanceRecord(workgroupID: "WG", gitBase: "main", skeleton: S.Skeleton(workgroup: workgroup)!).encoded
    }

    private func tag(_ position: Int) -> String {
        return S.PaneTag(instanceID: "I", position: position).encoded
    }

    /// Replies to the snapshot's three queries.
    private func snapshot(record: String?, panes: [String], windows: [String] = ["@1 "]) -> [String?] {
        let show = record.map { S.instanceOptionName(instanceID: "I") + " " + $0 } ?? ""
        return [show, panes.joined(separator: "\n"), windows.joined(separator: "\n")]
    }

    private let scripts = [1: "diff-script", 2: "review-script"]

    private func creation() -> Creation {
        return Creation(sessionID: 3, instanceID: "I", scriptsByPosition: scripts)
    }

    private func create(_ position: Int, width: Int = 60, height: Int = 40) -> Creation.Action {
        return .create(position: position,
                       commands: C.createParkedPeer(sessionID: 3, instanceID: "I", position: position,
                                                    width: width, height: height,
                                                    script: scripts[position]!,
                                                    waiting: true))
    }

    // A diff or code review peer runs nothing until it is started, so it is created waiting (its
    // placeholder script is what it runs meanwhile). A regular peer runs its command at once.
    func testDeferredModesStartWaiting() {
        XCTAssertTrue(S.startsWaiting(.diff))
        XCTAssertTrue(S.startsWaiting(.codeReview))
        XCTAssertFalse(S.startsWaiting(.regular))
    }

    // Both peers missing: each is created in turn, pinned to the leader's slot.
    func testCreatesEveryMissingPeer() {
        var c = creation()
        XCTAssertEqual(c.start(), .snapshot(TmuxWorkgroupAdoption.queries(sessionID: 3)))
        XCTAssertEqual(c.didSnapshot(snapshot(record: record, panes: ["%0 @1 60x40 \(tag(0))"])), create(1))
        XCTAssertEqual(c.didCreate(reply: "%5"), create(2))
        XCTAssertEqual(c.didCreate(reply: "%6"), .finished(created: [1: 5, 2: 6], failed: []))
    }

    // A crashed client already created one: only the other is created.
    func testCreatesOnlyWhatIsMissing() {
        var c = creation()
        _ = c.start()
        XCTAssertEqual(c.didSnapshot(snapshot(record: record,
                                              panes: ["%0 @1 60x40 \(tag(0))", "%5 @2 60x40 \(tag(1))"],
                                              windows: ["@1 ", "@2 " + S.ParkedTag(instanceID: "I").encoded])),
                       create(2))
        XCTAssertEqual(c.didCreate(reply: "%6"), .finished(created: [2: 6], failed: []))
    }

    func testNothingMissing() {
        var c = creation()
        _ = c.start()
        XCTAssertEqual(c.didSnapshot(snapshot(record: record, panes: ["%0 @1 60x40 \(tag(0))",
                                                                      "%5 @2 60x40 \(tag(1))",
                                                                      "%6 @3 60x40 \(tag(2))"])),
                       .finished(created: [:], failed: []))
    }

    // The slot is wherever the group's visible member is: here the diff peer is in view.
    func testPinsToTheVisibleMembersSize() {
        var c = creation()
        _ = c.start()
        XCTAssertEqual(c.didSnapshot(snapshot(record: record,
                                              panes: ["%0 @2 50x20 \(tag(0))", "%5 @1 70x30 \(tag(1))"],
                                              windows: ["@1 ", "@2 " + S.ParkedTag(instanceID: "I").encoded])),
                       create(2, width: 70, height: 30))
    }

    // Another client ended the instance meanwhile, or its record cannot be read: create nothing.
    func testInstanceGone() {
        var c = creation()
        _ = c.start()
        XCTAssertEqual(c.didSnapshot(snapshot(record: nil, panes: [])), .abandoned)
        var d = creation()
        _ = d.start()
        XCTAssertEqual(d.didSnapshot(snapshot(record: "g_ffff", panes: [])), .abandoned)
        var e = creation()
        _ = e.start()
        XCTAssertEqual(e.didSnapshot([nil, nil, nil]), .abandoned, "tmux could not answer")
    }

    // Only peers are created this way; anything else requested is ignored.
    func testOnlyPeers() {
        var c = Creation(sessionID: 3, instanceID: "I", scriptsByPosition: [3: "split-script", 9: "nothing"])
        _ = c.start()
        XCTAssertEqual(c.didSnapshot(snapshot(record: record, panes: ["%0 @1 60x40 \(tag(0))"])),
                       .finished(created: [:], failed: []))
    }

    // A peer tmux would not create is reported, and the rest still are.
    func testFailedCreationContinues() {
        var c = creation()
        _ = c.start()
        _ = c.didSnapshot(snapshot(record: record, panes: ["%0 @1 60x40 \(tag(0))"]))
        XCTAssertEqual(c.didCreate(reply: nil), create(2))
        XCTAssertEqual(c.didCreate(reply: "%6"), .finished(created: [2: 6], failed: [1]))
    }

    func testEventsOutOfTurnAreIgnored() {
        var c = creation()
        XCTAssertNil(c.didCreate(reply: "%5"))
        XCTAssertNil(c.didSnapshot([]))
        _ = c.start()
        XCTAssertNil(c.start())
        XCTAssertNil(c.didCreate(reply: "%5"))
    }
}
