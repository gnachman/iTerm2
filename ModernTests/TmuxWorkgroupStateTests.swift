//
//  TmuxWorkgroupStateTests.swift
//  iTerm2 ModernTests
//
//  A workgroup in a tmux Integration tab keeps its state on the tmux server, so every attached
//  iTerm2, on any Mac, sees the same thing: a record per instance holding the workgroup's shape (a
//  skeleton of kinds and modes, nothing private), a tag on every member pane naming its position in
//  that shape, and a tag on the hidden window holding inactive peers. Behavior always comes from
//  the attaching Mac's own workgroup whose skeleton is equal, so commands, names, profiles and
//  toolbars may differ between Macs. Which peer is visible is worked out from where the panes are,
//  never stored, so it cannot go stale.
//
//  Anything read from tmux may be attacker-controlled: a control sequence in untrusted output can
//  put iTerm2 into tmux Integration mode against a fake server, and what iTerm2 then sends is typed
//  into a real shell. So every value and every variable part of an option name is a fixed prefix
//  plus lowercase hex, as with @tab_colors and @it2_client_*, and nothing decoded is sent back raw.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxWorkgroupStateTests: XCTestCase {
    private typealias S = TmuxWorkgroupState
    private typealias Node = TmuxWorkgroupState.Skeleton.Node

    // MARK: - Fixtures

    private let instance = "INST-1"

    private func config(_ id: String,
                        _ kind: iTermWorkgroupSessionConfig.Kind,
                        parent: String?,
                        mode: iTermWorkgroupSessionMode = .regular,
                        command: String = "") -> iTermWorkgroupSessionConfig {
        var config = iTermWorkgroupSessionConfig(uniqueIdentifier: id, parentID: parent, kind: kind, profileGUID: nil,
                                                 command: command, urlString: "", toolbarItems: [], displayName: id)
        config.mode = mode
        return config
    }

    private var splitSettings: SplitSettings {
        SplitSettings(orientation: .vertical, side: .trailingOrBottom, location: 0.5)
    }

    // Positions: 0 root, 1 diff peer, 2 review peer, 3 split.
    private var workgroup: iTermWorkgroup {
        return iTermWorkgroup(uniqueIdentifier: "WG", name: "Claude Code", sessions: [
            config("ROOT", .root, parent: nil),
            config("DIFF", .peer, parent: "ROOT", mode: .diff),
            config("REVIEW", .peer, parent: "ROOT", mode: .codeReview),
            config("SPLIT", .split(splitSettings), parent: "ROOT"),
        ])
    }

    private var record: S.InstanceRecord {
        S.InstanceRecord(workgroupID: "WG", gitBase: "main", skeleton: S.Skeleton(workgroup: workgroup)!)
    }

    private func pane(_ id: Int, window: Int, _ position: Int?, instance: String? = nil) -> S.Pane {
        return S.Pane(paneID: id, windowID: window,
                      tag: position.map { S.PaneTag(instanceID: instance ?? self.instance, position: $0).encoded })
    }

    private func derive(panes: [S.Pane],
                        windows: [S.Window] = [S.Window(windowID: 1, parkedTag: nil),
                                               S.Window(windowID: 9, parkedTag: S.ParkedTag(instanceID: "INST-1").encoded),
                                               S.Window(windowID: 10, parkedTag: S.ParkedTag(instanceID: "INST-1").encoded),
                                               S.Window(windowID: 11, parkedTag: S.ParkedTag(instanceID: "INST-1").encoded)],
                        records: [String: String]? = nil) -> S.Derivation {
        return S.derive(panes: panes, windows: windows,
                        instanceOptions: records ?? [instance: record.encoded])
    }

    private func hex(_ string: String) -> String {
        return Data(string.utf8).map { String(format: "%02x", $0) }.joined()
    }

    /// A record value whose skeleton is the given JSON, as another client (or a fake server) might write it.
    private func rawRecord(skeleton: String) -> String {
        return "g_" + hex(#"{"v":1,"wg":"WG","base":"main","skel":"# + skeleton + "}")
    }

    private func assertSafe(_ value: String, prefix: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(value.range(of: "^" + prefix + "[0-9a-f]+$", options: .regularExpression),
                        value, file: file, line: line)
    }

    // MARK: - Skeleton

    func testSkeletonOfAWorkgroup() throws {
        let skeleton = try XCTUnwrap(S.Skeleton(workgroup: workgroup))
        XCTAssertEqual(skeleton.root, Node(kind: .root, mode: .regular, children: [
            Node(kind: .peer, mode: .diff, children: []),
            Node(kind: .peer, mode: .codeReview, children: []),
            Node(kind: .split, mode: .regular, children: []),
        ]))
        XCTAssertEqual(S.Skeleton.configIDsByPosition(in: workgroup), ["ROOT", "DIFF", "REVIEW", "SPLIT"])
    }

    // Children nest, so the skeleton is a tree and needs no parent pointers. Positions are a
    // pre-order walk with children in definition order.
    func testNestedSkeletonAndPositions() throws {
        let nested = iTermWorkgroup(uniqueIdentifier: "N", name: "N", sessions: [
            config("ROOT", .root, parent: nil),
            config("S1", .split(splitSettings), parent: "ROOT"),
            config("P1", .peer, parent: "ROOT", mode: .diff),
            config("S1P", .peer, parent: "S1", mode: .codeReview),
            config("S2", .split(splitSettings), parent: "S1"),
            config("T", .tab, parent: "ROOT"),
        ])
        let skeleton = try XCTUnwrap(S.Skeleton(workgroup: nested))
        XCTAssertEqual(skeleton.root, Node(kind: .root, mode: .regular, children: [
            Node(kind: .split, mode: .regular, children: [
                Node(kind: .peer, mode: .codeReview, children: []),
                Node(kind: .split, mode: .regular, children: []),
            ]),
            Node(kind: .peer, mode: .diff, children: []),
            Node(kind: .tab, mode: .regular, children: []),
        ]))
        XCTAssertEqual(S.Skeleton.configIDsByPosition(in: nested), ["ROOT", "S1", "S1P", "S2", "P1", "T"])
        XCTAssertEqual(skeleton.peerGroups, [S.Skeleton.PeerGroupShape(host: 0, members: [0, 4]),
                                             S.Skeleton.PeerGroupShape(host: 1, members: [1, 2])])
    }

    // What legitimately differs between Macs does not change the shape.
    func testSkeletonIgnoresPerMacDetails() {
        var other = workgroup
        other = iTermWorkgroup(uniqueIdentifier: "OTHER", name: "Renamed", sessions: other.sessions.map { c in
            var c = c
            c.command = "something else"
            c.perFileCommand = "per file"
            c.urlString = "https://example.com/"
            c.displayName = "Name " + c.uniqueIdentifier
            c.profileGUID = "SOME-PROFILE"
            c.toolbarItems = [.gitStatus]
            if case .split = c.kind {
                c.kind = .split(SplitSettings(orientation: .horizontal, side: .leadingOrTop, location: 0.2))
            }
            return c
        })
        XCTAssertEqual(S.Skeleton(workgroup: other), S.Skeleton(workgroup: workgroup))
    }

    // The same preset installed twice gets fresh UUIDs everywhere, and the same shape.
    func testSamePresetInstalledTwiceHasTheSameShape() {
        let a = WorkgroupPresets.buildCodingAgentPlusDiffPlusCodeReview()
        let b = WorkgroupPresets.buildCodingAgentPlusDiffPlusCodeReview()
        XCTAssertNotEqual(a.uniqueIdentifier, b.uniqueIdentifier)
        XCTAssertNotNil(S.Skeleton(workgroup: a))
        XCTAssertEqual(S.Skeleton(workgroup: a), S.Skeleton(workgroup: b))
    }

    func testShapeChanges() {
        let base = S.Skeleton(workgroup: workgroup)
        var sessions = workgroup.sessions
        sessions.swapAt(1, 2)  // review before diff: positions would cross, and the modes tell
        XCTAssertNotEqual(S.Skeleton(workgroup: iTermWorkgroup(uniqueIdentifier: "WG", name: "", sessions: sessions)), base)
        sessions = workgroup.sessions
        sessions[1].mode = .regular
        XCTAssertNotEqual(S.Skeleton(workgroup: iTermWorkgroup(uniqueIdentifier: "WG", name: "", sessions: sessions)), base)
        sessions = workgroup.sessions
        sessions[3].kind = .tab
        XCTAssertNotEqual(S.Skeleton(workgroup: iTermWorkgroup(uniqueIdentifier: "WG", name: "", sessions: sessions)), base)
        sessions = workgroup.sessions + [config("MORE", .peer, parent: "ROOT")]
        XCTAssertNotEqual(S.Skeleton(workgroup: iTermWorkgroup(uniqueIdentifier: "WG", name: "", sessions: sessions)), base)
    }

    // A local definition that breaks the workgroup invariants never matches anything.
    func testBrokenWorkgroupsHaveNoSkeleton() {
        let broken: [[iTermWorkgroupSessionConfig]] = [
            [],
            [config("A", .root, parent: nil), config("B", .root, parent: nil)],
            [config("A", .root, parent: nil), config("B", .peer, parent: "NOPE")],
            [config("A", .root, parent: nil), config("B", .split(splitSettings), parent: "C"),
             config("C", .split(splitSettings), parent: "B")],
            [config("A", .peer, parent: nil)],
            [config("A", .root, parent: nil), config("B", .root, parent: "A")],
            [config("A", .root, parent: nil), config("B", .peer, parent: "A"), config("C", .peer, parent: "B")],
            [config("A", .root, parent: nil), config("B", .peer, parent: "A"), config("B", .peer, parent: "A")],
        ]
        for sessions in broken {
            XCTAssertNil(S.Skeleton(workgroup: iTermWorkgroup(uniqueIdentifier: "W", name: "", sessions: sessions)),
                         "\(sessions.map(\.uniqueIdentifier))")
        }
    }

    // A peer may have non-peer children (only peers cannot host peers).
    func testPeerWithASplitChild() {
        let wg = iTermWorkgroup(uniqueIdentifier: "W", name: "", sessions: [
            config("A", .root, parent: nil), config("B", .peer, parent: "A"),
            config("C", .split(splitSettings), parent: "B"),
        ])
        XCTAssertNotNil(S.Skeleton(workgroup: wg))
    }

    // A stored skeleton is attacker-controlled: decoded strictly.
    func testStoredSkeletonsAreValidated() {
        XCTAssertNotNil(S.InstanceRecord(encoded: rawRecord(skeleton: #"{"k":"root","m":"regular"}"#)))
        XCTAssertNotNil(S.InstanceRecord(encoded: rawRecord(skeleton: #"{"k":"root","m":"regular","c":[{"k":"peer","m":"diff"}]}"#)))
        let bad = [
            #"{"k":"peer","m":"regular"}"#,
            #"{"k":"root","m":"regular","c":[{"k":"root","m":"regular"}]}"#,
            #"{"k":"root","m":"regular","c":[{"k":"peer","m":"regular","c":[{"k":"peer","m":"regular"}]}]}"#,
            #"{"k":"root","m":"regular","c":[{"k":"window","m":"regular"}]}"#,
            #"{"k":"root","m":"turbo"}"#,
            #"{"k":"root"}"#,
            #"{"m":"regular"}"#,
            #"[]"#,
        ]
        for skeleton in bad {
            XCTAssertNil(S.InstanceRecord(encoded: rawRecord(skeleton: skeleton)), skeleton)
        }
    }

    func testStoredSkeletonsAreBounded() {
        func nested(_ depth: Int) -> String {
            var json = #"{"k":"split","m":"regular"}"#
            for _ in 0..<depth {
                json = #"{"k":"split","m":"regular","c":["# + json + "]}"
            }
            return #"{"k":"root","m":"regular","c":["# + json + "]}"
        }
        XCTAssertNotNil(S.InstanceRecord(encoded: rawRecord(skeleton: nested(S.Skeleton.maximumDepth - 2))))
        XCTAssertNil(S.InstanceRecord(encoded: rawRecord(skeleton: nested(S.Skeleton.maximumDepth))))

        let leaf = #"{"k":"split","m":"regular"}"#
        let wide = { (count: Int) in
            #"{"k":"root","m":"regular","c":["# + Array(repeating: leaf, count: count).joined(separator: ",") + "]}"
        }
        XCTAssertNotNil(S.InstanceRecord(encoded: rawRecord(skeleton: wide(S.Skeleton.maximumNodeCount - 1))))
        XCTAssertNil(S.InstanceRecord(encoded: rawRecord(skeleton: wide(S.Skeleton.maximumNodeCount))))
    }

    // MARK: - Encoding

    func testRecordRoundTrips() throws {
        let decoded = try XCTUnwrap(S.InstanceRecord(encoded: record.encoded))
        XCTAssertEqual(decoded, record)
        assertSafe(record.encoded, prefix: "g_")
    }

    // Commands, names and anything else private never reach tmux.
    func testRecordHoldsNothingPrivate() throws {
        let secret = iTermWorkgroup(uniqueIdentifier: "WG", name: "SECRET-NAME", sessions: [
            config("ROOT", .root, parent: nil, command: "SECRET-COMMAND"),
        ])
        let encoded = S.InstanceRecord(workgroupID: "WG", gitBase: "main",
                                       skeleton: try XCTUnwrap(S.Skeleton(workgroup: secret))).encoded
        let json = String(decoding: try XCTUnwrap((String(encoded.dropFirst(2)) as NSString).dataFromHexValues()),
                          as: UTF8.self)
        XCTAssertFalse(json.contains("SECRET"), json)
        XCTAssertFalse(json.contains("ROOT"), json)
    }

    func testTagsRoundTrip() {
        let paneTag = S.PaneTag(instanceID: "I", position: 3)
        XCTAssertEqual(S.PaneTag(encoded: paneTag.encoded), paneTag)
        assertSafe(paneTag.encoded, prefix: "m_")
        let parkedTag = S.ParkedTag(instanceID: "I")
        XCTAssertEqual(S.ParkedTag(encoded: parkedTag.encoded), parkedTag)
        assertSafe(parkedTag.encoded, prefix: "p_")
    }

    // A code review or diff member is created waiting: its program starts later, when someone
    // starts the review or the diff has something to show. Whoever starts it clears the flag.
    func testWaitingTag() throws {
        let waiting = S.PaneTag(instanceID: "I", position: 2, waiting: true)
        XCTAssertEqual(S.PaneTag(encoded: waiting.encoded), waiting)
        assertSafe(waiting.encoded, prefix: "m_")
        XCTAssertNotEqual(waiting, S.PaneTag(instanceID: "I", position: 2))
        XCTAssertEqual(waiting.started, S.PaneTag(instanceID: "I", position: 2))
        XCTAssertEqual(S.PaneTag(encoded: "m_" + hex(#"{"v":1,"i":"I","n":2,"w":true}"#)), waiting)
        XCTAssertEqual(S.PaneTag(encoded: "m_" + hex(#"{"v":1,"i":"I","n":2,"w":false}"#)),
                       S.PaneTag(instanceID: "I", position: 2))
        XCTAssertNil(S.PaneTag(encoded: "m_" + hex(#"{"v":1,"i":"I","n":2,"w":1}"#)))
        // A started member's tag is what it was before waiting existed, so older clients read it.
        let started = S.PaneTag(instanceID: "I", position: 2).encoded
        let json = String(decoding: try XCTUnwrap((String(started.dropFirst(2)) as NSString).dataFromHexValues()),
                          as: UTF8.self)
        XCTAssertFalse(json.contains("\"w\""), json)
    }

    // IDs come from tmux, which may be a fake server. Whatever they contain, what we would send back
    // is prefix plus hex.
    func testHostileIDsEncodeSafely() {
        let hostile = "x\" ; run-shell 'evil' #{pane_id}\n\u{1b}]"
        let paneTag = S.PaneTag(instanceID: hostile, position: 0)
        assertSafe(paneTag.encoded, prefix: "m_")
        XCTAssertEqual(S.PaneTag(encoded: paneTag.encoded), paneTag)
        assertSafe(S.ParkedTag(instanceID: hostile).encoded, prefix: "p_")
        assertSafe(S.InstanceRecord(workgroupID: hostile, gitBase: hostile, skeleton: record.skeleton).encoded, prefix: "g_")
        assertSafe(S.instanceOptionName(instanceID: hostile), prefix: "@iterm2_wg_")
        XCTAssertEqual(S.instanceID(fromOptionName: S.instanceOptionName(instanceID: hostile)), hostile)
    }

    // Another client's newer format, or a hand edit, is not ours to interpret.
    func testGarbageAndNewerVersionsDoNotDecode() {
        for value in ["", "x", "g_", "g_zz", "g_7b7", "g_7B7D", "g_" + hex("{}"), "w_" + hex("{}"),
                      "m_" + hex(#"{"v":2,"i":"I","n":0}"#), "m_" + hex(#"{"v":1,"i":"I"}"#),
                      "m_" + hex(#"{"v":1,"i":"","n":0}"#), "m_" + hex(#"{"v":1,"i":"I","n":-1}"#),
                      "m_" + hex(#"{"v":1,"i":"I","n":"0"}"#), "m_" + hex(#"{"v":1,"i":"I","n":1.5}"#),
                      "1:I:C"] {
            XCTAssertNil(S.InstanceRecord(encoded: value), value)
            XCTAssertNil(S.PaneTag(encoded: value), value)
            XCTAssertNil(S.ParkedTag(encoded: value), value)
        }
        XCTAssertNil(S.InstanceRecord(encoded: "g_" + hex(#"{"v":2,"wg":"WG","base":"main","skel":{"k":"root","m":"regular"}}"#)))
        XCTAssertNil(S.ParkedTag(encoded: "p_" + hex(#"{"v":2,"i":"I"}"#)))
        XCTAssertNil(S.ParkedTag(encoded: "p_" + hex(#"{"v":1,"i":""}"#)))
        XCTAssertNotNil(S.ParkedTag(encoded: "p_" + hex(#"{"v":1,"i":"I"}"#)))
        XCTAssertNotNil(S.PaneTag(encoded: "m_" + hex(#"{"v":1,"i":"I","n":0}"#)))
    }

    // MARK: - Deriving an instance

    // The root in view, two peers parked in windows of their own, a split beside the root.
    func testOrdinaryInstance() throws {
        let result = derive(panes: [pane(1, window: 1, 0), pane(2, window: 1, 3),
                                    pane(3, window: 9, 1), pane(4, window: 10, 2),
                                    pane(5, window: 1, nil)])
        let i = try XCTUnwrap(result.instances.first)
        XCTAssertEqual(result.instances.count, 1)
        XCTAssertEqual(i.instanceID, instance)
        XCTAssertEqual(i.parkedWindowIDs, [9, 10, 11])
        XCTAssertEqual(i.paneForPosition, [0: 1, 3: 2, 1: 3, 2: 4])
        XCTAssertEqual(i.peerGroups, [S.PeerGroup(host: 0, members: [0, 1, 2], visible: 0, hidden: [1, 2])])
        XCTAssertEqual(i.missingPositions, [])
        XCTAssertEqual(i.problems, [])
    }

    // Members whose programs have not started are reported by position.
    func testWaitingMembers() throws {
        let waiting = S.Pane(paneID: 3, windowID: 9,
                             tag: S.PaneTag(instanceID: instance, position: 1, waiting: true).encoded)
        let i = try XCTUnwrap(derive(panes: [pane(1, window: 1, 0), waiting, pane(4, window: 10, 2)]).instances.first)
        XCTAssertEqual(i.waitingPositions, [1])
        XCTAssertEqual(i.paneForPosition, [0: 1, 1: 3, 2: 4])
        XCTAssertEqual(i.problems, [])
    }

    // A parked peer's window is pinned to the size of the slot it fills when shown, so a switch
    // resizes nothing. When the slot changes size (the user resized the window), each parked peer
    // whose size differs is pinned again.
    func testParkedPeersToResize() throws {
        func sized(_ id: Int, window: Int, _ position: Int, _ width: Int, _ height: Int) -> S.Pane {
            var p = pane(id, window: window, position)
            p.size = S.PaneSize(width: width, height: height)
            return p
        }
        let same = try XCTUnwrap(derive(panes: [sized(1, window: 1, 0, 80, 24), sized(3, window: 9, 1, 80, 24),
                                                sized(4, window: 10, 2, 80, 24)]).instances.first)
        XCTAssertEqual(same.parkedPeersToResize, [])

        let resized = try XCTUnwrap(derive(panes: [sized(1, window: 1, 0, 100, 30), sized(3, window: 9, 1, 80, 24),
                                                   sized(4, window: 10, 2, 100, 30)]).instances.first)
        XCTAssertEqual(resized.parkedPeersToResize, [S.Resize(paneID: 3, size: S.PaneSize(width: 100, height: 30))])

        // A peer in view is the slot: the root, parked, follows it.
        let switched = try XCTUnwrap(derive(panes: [sized(1, window: 9, 0, 80, 24), sized(3, window: 1, 1, 90, 20),
                                                    sized(4, window: 10, 2, 90, 20)]).instances.first)
        XCTAssertEqual(switched.parkedPeersToResize, [S.Resize(paneID: 1, size: S.PaneSize(width: 90, height: 20))])

        // No size for the slot, or nothing in view: nothing to go by.
        let unsized = try XCTUnwrap(derive(panes: [pane(1, window: 1, 0), sized(3, window: 9, 1, 80, 24)]).instances.first)
        XCTAssertEqual(unsized.parkedPeersToResize, [])
        let noneVisible = try XCTUnwrap(derive(panes: [sized(1, window: 9, 0, 80, 24),
                                                       sized(3, window: 10, 1, 60, 20)]).instances.first)
        XCTAssertEqual(noneVisible.parkedPeersToResize, [])
    }

    // The user switched to the diff peer: it is in view, and the root is parked in its place.
    func testSwitchedToAPeer() throws {
        let i = try XCTUnwrap(derive(panes: [pane(1, window: 9, 0), pane(3, window: 1, 1),
                                             pane(4, window: 10, 2), pane(2, window: 1, 3)]).instances.first)
        XCTAssertEqual(i.peerGroups.first?.visible, 1)
        XCTAssertEqual(i.peerGroups.first?.hidden, [0, 2])
        XCTAssertEqual(i.problems, [])
    }

    // A member with no pane yet (a code review peer not started) is to be created, not a problem.
    func testMemberWithoutAPaneIsMissing() throws {
        let i = try XCTUnwrap(derive(panes: [pane(1, window: 1, 0), pane(3, window: 9, 1)]).instances.first)
        XCTAssertEqual(i.missingPositions, [2, 3])
        XCTAssertEqual(i.peerGroups, [S.PeerGroup(host: 0, members: [0, 1, 2], visible: 0, hidden: [1])])
        XCTAssertEqual(i.problems, [])
    }

    // The root exited: the instance ends.
    func testLeaderGone() throws {
        let i = try XCTUnwrap(derive(panes: [pane(3, window: 9, 1), pane(4, window: 1, 2)]).instances.first)
        XCTAssertEqual(i.problems, [.leaderMissing])
    }

    // Two peers in view (a client died mid-switch): keep the host in view and report the
    // rest, so they can be parked again.
    func testTwoVisiblePeers() throws {
        let i = try XCTUnwrap(derive(panes: [pane(1, window: 1, 0), pane(3, window: 1, 1),
                                             pane(4, window: 9, 2)]).instances.first)
        XCTAssertEqual(i.peerGroups.first?.visible, 0)
        XCTAssertEqual(i.problems, [.extraVisiblePeers(host: 0, positions: [1])])
    }

    // Every peer parked: nothing to show until one is brought back; the host is preferred.
    func testNoVisiblePeer() throws {
        let i = try XCTUnwrap(derive(panes: [pane(1, window: 9, 0), pane(3, window: 10, 1)]).instances.first)
        XCTAssertNil(i.peerGroups.first?.visible)
        XCTAssertEqual(i.problems, [.noVisiblePeer(host: 0)])
    }

    // No parked windows (e.g. one was untagged by hand): every peer is in view.
    func testNoParkedWindows() throws {
        let i = try XCTUnwrap(derive(panes: [pane(1, window: 1, 0), pane(3, window: 2, 1)],
                                     windows: [S.Window(windowID: 1, parkedTag: nil),
                                               S.Window(windowID: 2, parkedTag: nil)]).instances.first)
        XCTAssertEqual(i.parkedWindowIDs, [])
        XCTAssertEqual(i.problems, [.extraVisiblePeers(host: 0, positions: [1])])
    }

    // A member in another instance's parked window is hidden from the user but not parked for this
    // instance: stranded, and neither visible nor hidden here.
    func testMemberInAnotherInstancesParkedWindowIsStranded() throws {
        let i = try XCTUnwrap(derive(panes: [pane(1, window: 1, 0), pane(3, window: 2, 1)],
                                     windows: [S.Window(windowID: 1, parkedTag: nil),
                                               S.Window(windowID: 2, parkedTag: S.ParkedTag(instanceID: "OTHER").encoded)])
            .instances.first)
        XCTAssertEqual(i.peerGroups, [S.PeerGroup(host: 0, members: [0, 1, 2], visible: 0, hidden: [])])
        XCTAssertEqual(i.problems, [.strandedInParkedWindow(paneID: 3)])
    }

    // Two panes claim one member: the lower pane id wins, the other is reported.
    func testDuplicateMember() throws {
        let i = try XCTUnwrap(derive(panes: [pane(1, window: 1, 0), pane(3, window: 9, 1),
                                             pane(7, window: 1, 1)]).instances.first)
        XCTAssertEqual(i.paneForPosition[1], 3)
        XCTAssertEqual(i.problems, [.duplicateMember(position: 1, paneID: 7)])
    }

    // A position the skeleton does not have (hand edit, or a fake server) is ignored, and reported.
    func testUnknownPosition() throws {
        let i = try XCTUnwrap(derive(panes: [pane(1, window: 1, 0), pane(8, window: 1, 4)]).instances.first)
        XCTAssertEqual(i.problems, [.unknownPosition(paneID: 8, position: 4)])
        XCTAssertNil(i.paneForPosition[4])
    }

    // Anything in this instance's parked windows that is not one of its parked peers would be
    // invisible forever: reported so it can be brought out into a tab.
    func testStrandedInParkedWindows() throws {
        let i = try XCTUnwrap(derive(panes: [pane(1, window: 1, 0), pane(3, window: 9, 1),
                                             pane(4, window: 10, 3),        // a split member
                                             pane(5, window: 10, 6),        // unknown position
                                             pane(6, window: 11, 1),        // duplicate
                                             pane(7, window: 11, nil),      // untagged
                                             pane(8, window: 11, 0, instance: "OTHER")]).instances.first)
        XCTAssertEqual(i.problems, [.unknownPosition(paneID: 5, position: 6),
                                    .duplicateMember(position: 1, paneID: 6),
                                    .strandedInParkedWindow(paneID: 4), .strandedInParkedWindow(paneID: 5),
                                    .strandedInParkedWindow(paneID: 6), .strandedInParkedWindow(paneID: 7),
                                    .strandedInParkedWindow(paneID: 8)])
    }

    // Each host with peers is its own group with its own visible member.
    func testNestedPeerGroups() throws {
        let nested = iTermWorkgroup(uniqueIdentifier: "N", name: "N", sessions: [
            config("ROOT", .root, parent: nil),
            config("P1", .peer, parent: "ROOT", mode: .diff),
            config("S1", .split(splitSettings), parent: "ROOT"),
            config("S1P", .peer, parent: "S1", mode: .codeReview),
        ])
        let nestedRecord = S.InstanceRecord(workgroupID: "N", gitBase: "main", skeleton: S.Skeleton(workgroup: nested)!)
        // Positions: 0 root, 1 P1, 2 S1, 3 S1P. Root's group shows P1; S1's group shows S1.
        let i = try XCTUnwrap(derive(panes: [pane(1, window: 9, 0), pane(2, window: 1, 1),
                                             pane(3, window: 1, 2), pane(4, window: 10, 3)],
                                     records: [instance: nestedRecord.encoded]).instances.first)
        XCTAssertEqual(i.peerGroups, [S.PeerGroup(host: 0, members: [0, 1], visible: 1, hidden: [0]),
                                      S.PeerGroup(host: 2, members: [2, 3], visible: 2, hidden: [3])])
        XCTAssertEqual(i.problems, [])
    }

    // Tags for an instance with no record are left by an interrupted removal (a member is never
    // tagged before its record exists). Leaders and members are told apart: an orphan member is
    // killed, an orphan leader is only untagged.
    func testOrphanTags() {
        let result = derive(panes: [pane(1, window: 1, 0, instance: "GONE"), pane(2, window: 1, 3, instance: "GONE"),
                                    pane(3, window: 9, 1, instance: "GONE")], records: [:])
        XCTAssertEqual(result.instances, [])
        XCTAssertEqual(result.orphanLeaderPaneIDs, [1])
        XCTAssertEqual(result.orphanMemberPaneIDs, [2, 3])
    }

    // An instance whose record cannot be read (another client's newer format) is left alone:
    // reported as such, never torn down.
    func testUndecodableRecordIsLeftAlone() {
        let result = derive(panes: [pane(1, window: 1, 0)], records: [instance: "g_ffff"])
        XCTAssertEqual(result.instances, [])
        XCTAssertEqual(result.undecodableInstanceIDs, [instance])
        XCTAssertEqual(result.orphanLeaderPaneIDs, [], "its panes belong to an instance we cannot read, not to none")
        XCTAssertEqual(result.orphanMemberPaneIDs, [])
    }

    // Two instances of one workgroup share a skeleton and are kept apart by instance ID.
    func testSeveralInstances() {
        let other = S.InstanceRecord(workgroupID: "WG", gitBase: "HEAD", skeleton: record.skeleton)
        let result = derive(panes: [pane(1, window: 1, 0), pane(2, window: 2, 0, instance: "INST-2")],
                            windows: [S.Window(windowID: 1, parkedTag: nil), S.Window(windowID: 2, parkedTag: nil)],
                            records: [instance: record.encoded, "INST-2": other.encoded])
        XCTAssertEqual(result.instances.map(\.instanceID), ["INST-1", "INST-2"])
        XCTAssertEqual(result.instances.map(\.record.gitBase), ["main", "HEAD"])
    }

    // MARK: - Matching a local workgroup

    func testMatchesTheOnlyLocalWorkgroupWithTheSameShape() {
        let unrelated = iTermWorkgroup(uniqueIdentifier: "U", name: "", sessions: [config("A", .root, parent: nil)])
        var edited = workgroup
        edited = iTermWorkgroup(uniqueIdentifier: "LOCAL", name: "Mine", sessions: edited.sessions.map { c in
            var c = c
            c.command = "edited"
            return c
        })
        XCTAssertEqual(S.match(record, among: [unrelated, edited]), .unique(edited))
    }

    func testSeveralWithTheSameShapePreferTheSameWorkgroup() {
        let a = iTermWorkgroup(uniqueIdentifier: "A", name: "", sessions: workgroup.sessions)
        let same = workgroup
        XCTAssertEqual(S.match(record, among: [a, same]), .unique(same))
        let b = iTermWorkgroup(uniqueIdentifier: "B", name: "", sessions: workgroup.sessions)
        XCTAssertEqual(S.match(record, among: [a, b]), .ambiguous([a, b]))
    }

    func testNoLocalWorkgroupWithTheShape() {
        XCTAssertEqual(S.match(record, among: []), .noMatch)
        let unrelated = iTermWorkgroup(uniqueIdentifier: "WG", name: "", sessions: [config("A", .root, parent: nil)])
        XCTAssertEqual(S.match(record, among: [unrelated]), .noMatch, "the same ID with a different shape is not a match")
    }

    // MARK: - Option names

    func testOptionNames() {
        XCTAssertEqual(S.instanceOptionName(instanceID: "I"), "@iterm2_wg_49")
        XCTAssertEqual(S.instanceID(fromOptionName: "@iterm2_wg_49"), "I")
        for name in ["@iterm2_wg", "@iterm2_wg_", "@iterm2_wg_parked", "@iterm2_wg_lock", "@iterm2_wg_lock_49",
                     "@iterm2_wg_4", "@iterm2_wg_4G", "@iterm2_wg_4A", "@hidden"] {
            XCTAssertNil(S.instanceID(fromOptionName: name), name)
        }
        XCTAssertEqual(S.paneOptionName, "@iterm2_wg")
        XCTAssertEqual(S.parkedOptionName, "@iterm2_wg_parked")
    }
}
