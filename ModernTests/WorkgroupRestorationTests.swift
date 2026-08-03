//
//  WorkgroupRestorationTests.swift
//  ModernTests
//
//  Created by George Nachman on 6/4/26.
//
//  Covers reconstructing a workgroup from saved arrangement state
//  (adopting already-restored sessions instead of spawning fresh).
//

import XCTest
@testable import iTerm2SharedARC

final class WorkgroupRestorationTests: WorkgroupEntryTestBase {

    // configID -> fresh synthetic session for each peer child of root.
    private func makePeerSessions(_ wg: iTermWorkgroup) -> [String: PTYSession] {
        let root = wg.root!
        var result: [String: PTYSession] = [:]
        for cfg in wg.sessions where cfg.parentID == root.uniqueIdentifier {
            if case .peer = cfg.kind {
                result[cfg.uniqueIdentifier] = PTYSession(synthetic: false)!
            }
        }
        return result
    }

    // MARK: - adopt wiring

    func test_adopt_wiresPeerPortAndRegistersController() {
        let wg = WGFix.wgRootWithPeers(n: 2)
        let root = wg.root!
        let peers = makePeerSessions(wg)
        let inst = iTermWorkgroupController.instance.adopt(
            workgroup: wg,
            leader: leader,
            instanceUniqueIdentifier: "wg-test",
            activeIdentifier: root.uniqueIdentifier,
            gitBase: CCGitBaseSelectorItem.defaultBase,
            peerSessionsByConfigID: peers,
            nonPeerSessionsByConfigID: [:])
        defer { iTermWorkgroupController.instance.exit(on: leader) }

        XCTAssertNotNil(inst)
        // Controller resolves the leader to this instance.
        XCTAssertTrue(
            iTermWorkgroupController.instance.workgroupInstance(on: leader) === inst)
        // Peer port maps every configID to its session.
        XCTAssertTrue(inst!.peerPort.session(forIdentifier: root.uniqueIdentifier) === leader)
        for (id, s) in peers {
            XCTAssertTrue(inst!.peerPort.session(forIdentifier: id) === s,
                          "peer \(id) should resolve to its adopted session")
        }
        XCTAssertEqual(inst!.peerPort.activeSessionIdentifier, root.uniqueIdentifier)
        XCTAssertEqual(inst!.peerPort.leaderIdentifier, root.uniqueIdentifier)
        // Back-pointers on every member.
        XCTAssertTrue(leader.workgroupInstance === inst)
        for s in peers.values {
            XCTAssertTrue(s.workgroupInstance === inst)
            XCTAssertTrue(s.peerPort === inst!.peerPort)
        }
    }

    // MARK: - idempotency

    func test_adopt_idempotent() {
        let wg = WGFix.wgRootWithPeers(n: 1)
        let root = wg.root!
        let peers = makePeerSessions(wg)
        let a = iTermWorkgroupController.instance.adopt(
            workgroup: wg, leader: leader, instanceUniqueIdentifier: "wg-1",
            activeIdentifier: root.uniqueIdentifier,
            gitBase: CCGitBaseSelectorItem.defaultBase,
            peerSessionsByConfigID: peers, nonPeerSessionsByConfigID: [:])
        let b = iTermWorkgroupController.instance.adopt(
            workgroup: wg, leader: leader, instanceUniqueIdentifier: "wg-2",
            activeIdentifier: root.uniqueIdentifier,
            gitBase: CCGitBaseSelectorItem.defaultBase,
            peerSessionsByConfigID: peers, nonPeerSessionsByConfigID: [:])
        defer { iTermWorkgroupController.instance.exit(on: leader) }
        XCTAssertNotNil(a)
        XCTAssertTrue(a === b, "Re-adopting on the same leader is a no-op")
    }

    // MARK: - anchor != leader

    func test_adopt_anchorIsNonLeaderPeer() {
        let wg = WGFix.wgRootWithPeers(n: 2)
        let peers = makePeerSessions(wg)
        let anchorID = peers.keys.sorted().first!
        let inst = iTermWorkgroupController.instance.adopt(
            workgroup: wg, leader: leader, instanceUniqueIdentifier: "wg-test",
            activeIdentifier: anchorID,
            gitBase: CCGitBaseSelectorItem.defaultBase,
            peerSessionsByConfigID: peers, nonPeerSessionsByConfigID: [:])
        defer { iTermWorkgroupController.instance.exit(on: leader) }

        XCTAssertNotNil(inst)
        XCTAssertEqual(inst!.peerPort.activeSessionIdentifier, anchorID)
        // Controller keyed by leader resolves even though the visible
        // member is a non-leader peer.
        XCTAssertTrue(
            iTermWorkgroupController.instance.workgroupInstance(on: leader) === inst)
        // Leader / active resolve to the right sessions.
        XCTAssertTrue(inst!.peerPort.leaderSession === leader)
        XCTAssertTrue(inst!.peerPort.activeSession === peers[anchorID])
    }

    // MARK: - non-peer children

    func test_adopt_registersNonPeerChildren() {
        let wg = WGFix.wgRootWithSplits(n: 1, splitItems: [.reload(nil)])
        let root = wg.root!
        let split = wg.sessions.first {
            if case .split = $0.kind { return true }; return false
        }!
        let splitSession = PTYSession(synthetic: false)!
        let inst = iTermWorkgroupController.instance.adopt(
            workgroup: wg, leader: leader, instanceUniqueIdentifier: "wg-test",
            activeIdentifier: root.uniqueIdentifier,
            gitBase: CCGitBaseSelectorItem.defaultBase,
            peerSessionsByConfigID: [:],
            nonPeerSessionsByConfigID: [split.uniqueIdentifier: splitSession])
        defer { iTermWorkgroupController.instance.exit(on: leader) }

        XCTAssertNotNil(inst)
        XCTAssertTrue(splitSession.workgroupInstance === inst,
                      "Non-peer child should get the workgroup back-pointer")
        // Its toolbar resolves through the instance (auto-injected .name
        // makes this non-empty even for a bare reload config).
        XCTAssertFalse(inst!.toolbarItems(for: splitSession).isEmpty,
                       "Adopted non-peer child should expose its toolbar")
    }

    // MARK: - exit resolves to leader

    // After restore (or any time a non-leader peer is the focused
    // session), Exit Workgroup acts on that peer. The controller is
    // keyed by the leader, so it must resolve member -> leader.
    func test_exit_viaNonLeaderPeerTearsDownWorkgroup() {
        let wg = WGFix.wgRootWithPeers(n: 2)
        let peers = makePeerSessions(wg)
        let anchorID = peers.keys.sorted().first!
        let peerSession = peers[anchorID]!
        let inst = iTermWorkgroupController.instance.adopt(
            workgroup: wg, leader: leader, instanceUniqueIdentifier: "wg-test",
            activeIdentifier: anchorID,
            gitBase: CCGitBaseSelectorItem.defaultBase,
            peerSessionsByConfigID: peers, nonPeerSessionsByConfigID: [:])
        XCTAssertNotNil(inst)
        // Lookup resolves through the focused peer.
        XCTAssertTrue(
            iTermWorkgroupController.instance.workgroupInstance(on: peerSession) === inst)
        // Exit acting on the peer tears down the whole workgroup.
        iTermWorkgroupController.instance.exit(on: peerSession)
        XCTAssertNil(iTermWorkgroupController.instance.workgroupInstance(on: leader))
        XCTAssertNil(iTermWorkgroupController.instance.workgroupInstance(on: peerSession))
    }

    // MARK: - not-started deferred peers are spawned fresh

    // A peer with no restored session (e.g. a Code Review / Diff peer
    // that was never started, so reconstruct skips deserializing it) must
    // be spawned fresh via the spawner, not dropped — that's how it comes
    // back with its prompt/waiting overlay.
    func test_adopt_spawnsFreshForPeerWithoutRestoredSession() {
        let wg = WGFix.wgRootWithPeers(n: 2)
        let root = wg.root!
        let peers = makePeerSessions(wg)
        let providedID = peers.keys.sorted().first!
        let missingID = peers.keys.sorted().last!
        let inst = iTermWorkgroupController.instance.adopt(
            workgroup: wg, leader: leader, instanceUniqueIdentifier: "wg-test",
            activeIdentifier: root.uniqueIdentifier,
            gitBase: CCGitBaseSelectorItem.defaultBase,
            peerSessionsByConfigID: [providedID: peers[providedID]!],
            nonPeerSessionsByConfigID: [:],
            spawner: spawner)
        defer { iTermWorkgroupController.instance.exit(on: leader) }

        XCTAssertNotNil(inst)
        // Provided peer is adopted as-is.
        XCTAssertTrue(inst!.peerPort.session(forIdentifier: providedID) === peers[providedID])
        // Missing peer is spawned fresh and wired into the port.
        let spawned = spawner.session(forConfigID: missingID)
        XCTAssertNotNil(spawned, "Not-started peer should be spawned fresh")
        XCTAssertTrue(inst!.peerPort.session(forIdentifier: missingID) === spawned)
        // The mode switcher still covers both peers (peerConfigs include all).
        XCTAssertEqual(inst!.peerPort.peerCount, 1 + 2)
    }

    // Regression: a restored (reattached) code-review peer must get
    // BOTH its mode tag AND its raw command template restored.
    // codeReviewRawCommand is not persisted on the session arrangement,
    // and reload of a code-review peer keys off it
    // (workgroupNavigationDidTapReload) to re-present the prompt
    // overlay. If adopt() restored the mode but left the command nil,
    // reload fell through to a plain restart that silently reran the
    // last prompt with no panel.
    func test_adopt_restoresCodeReviewRawCommandForReattachedPeer() {
        let root = WGFix.makeRoot()
        let reviewCommand = "claude '\\(codeReviewPrompt)'"
        let peer = WGFix.makePeer(parentID: root.uniqueIdentifier,
                                  displayName: "Review",
                                  command: reviewCommand,
                                  mode: .codeReview)
        let wg = WGFix.wrap(name: "wgCodeReviewPeer", sessions: [root, peer])
        let peerSession = PTYSession(synthetic: false)!
        let inst = iTermWorkgroupController.instance.adopt(
            workgroup: wg, leader: leader, instanceUniqueIdentifier: "wg-test",
            activeIdentifier: root.uniqueIdentifier,
            gitBase: CCGitBaseSelectorItem.defaultBase,
            peerSessionsByConfigID: [peer.uniqueIdentifier: peerSession],
            nonPeerSessionsByConfigID: [:])
        defer { iTermWorkgroupController.instance.exit(on: leader) }

        XCTAssertNotNil(inst)
        XCTAssertTrue(inst!.peerPort.session(forIdentifier: peer.uniqueIdentifier) === peerSession)
        XCTAssertEqual(peerSession.workgroupSessionMode, .codeReview)
        // The fix: the raw template is restored so reload can re-present
        // the prompt overlay instead of restarting the last prompt.
        XCTAssertEqual(peerSession.codeReviewRawCommand, reviewCommand)
    }

    // encodeState must flag a member that is sitting on a pre-launch
    // overlay (here simulated via a pending diff launch) so restore knows
    // to re-create it fresh instead of adopting a stray shell.
    func test_encodeState_marksNotStartedPeerPending() {
        let wg = WGFix.wgRootWithPeers(n: 1)
        let peers = makePeerSessions(wg)
        let peerID = peers.keys.first!
        peers[peerID]!.pendingDiffLaunch = { }   // not-started deferred peer
        let inst = iTermWorkgroupController.instance.adopt(
            workgroup: wg, leader: leader, instanceUniqueIdentifier: "wg-test",
            activeIdentifier: wg.root!.uniqueIdentifier,
            gitBase: CCGitBaseSelectorItem.defaultBase,
            peerSessionsByConfigID: peers, nonPeerSessionsByConfigID: [:])
        defer { iTermWorkgroupController.instance.exit(on: leader) }
        XCTAssertNotNil(inst)

        let state = iTermWorkgroupRestoration.encodeState(forSession: leader,
                                                          includeContents: false)!
        let members = state[iTermWorkgroupRestoration.Key.members] as! [[AnyHashable: Any]]
        let m = members.first {
            ($0[iTermWorkgroupRestoration.Key.configID] as? String) == peerID
        }!
        XCTAssertEqual(m[iTermWorkgroupRestoration.Key.pending] as? Bool, true,
                       "A not-started deferred peer must be flagged pending")
    }

    // MARK: - trigger suppression bookkeeping

    func test_isRestoring_trueForEveryInvolvedGUIDWhilePending() {
        let anchor = PTYSession(synthetic: false)!
        let member1 = UUID().uuidString
        let member2 = UUID().uuidString
        let nonPeerGUID = UUID().uuidString
        let descriptor: [AnyHashable: Any] = [
            iTermWorkgroupRestoration.Key.workgroupID: "wg",
            iTermWorkgroupRestoration.Key.leaderID: "root",
            iTermWorkgroupRestoration.Key.anchorID: "root",
            iTermWorkgroupRestoration.Key.memberGUIDs: [member1, member2],
            iTermWorkgroupRestoration.Key.nonPeerChildren: [
                [iTermWorkgroupRestoration.Key.configID: "s0",
                 iTermWorkgroupRestoration.Key.guid: nonPeerGUID]
            ]
        ]
        WorkgroupRestorationCoordinator.shared.register(anchor: anchor,
                                                        descriptor: descriptor)
        XCTAssertTrue(iTermWorkgroupRestoration.isRestoring(guid: anchor.guid))
        XCTAssertTrue(iTermWorkgroupRestoration.isRestoring(guid: member1))
        XCTAssertTrue(iTermWorkgroupRestoration.isRestoring(guid: member2))
        XCTAssertTrue(iTermWorkgroupRestoration.isRestoring(guid: nonPeerGUID))
        XCTAssertFalse(iTermWorkgroupRestoration.isRestoring(guid: UUID().uuidString),
                       "An unrelated GUID is never reported as restoring")
    }

    // MARK: - inhibit-relaunch decision

    // The shared predicate that both restore paths (anchor and buried
    // peer) key off. If this drifts the two paths diverge: one keeps its
    // last output while the other spawns a stray shell.
    func test_modeInhibitsRelaunch_codeReviewAndDiffOnly() {
        XCTAssertTrue(iTermWorkgroupRestoration.modeInhibitsRelaunch(.codeReview))
        XCTAssertTrue(iTermWorkgroupRestoration.modeInhibitsRelaunch(.diff))
        XCTAssertFalse(iTermWorkgroupRestoration.modeInhibitsRelaunch(.regular))
    }

    private func anchorState(_ wg: iTermWorkgroup,
                             anchorID: String,
                             pending: Bool) -> [AnyHashable: Any] {
        let K = iTermWorkgroupRestoration.Key.self
        return [K.workgroupID: wg.uniqueIdentifier,
                K.anchorID: anchorID,
                K.anchorPending: pending]
    }

    // Classify against an in-memory workgroup via the injectable-model
    // seam so these tests never touch iTermWorkgroupModel.instance (whose
    // mutators persist to user defaults and post notifications).
    private func inhibits(_ wg: iTermWorkgroup,
                          anchorID: String,
                          pending: Bool) -> Bool {
        return iTermWorkgroupRestoration.shouldInhibitRelaunch(
            forAnchorState: anchorState(wg, anchorID: anchorID, pending: pending),
            workgroupForID: { $0 == wg.uniqueIdentifier ? wg : nil })
    }

    // A code-review/diff anchor that had a live program at save time (not
    // showing its overlay) must inhibit relaunch so restore leaves the
    // last output on screen instead of spawning a stray shell.
    func test_shouldInhibitRelaunch_codeReviewAnchorNotPending() {
        let root = WGFix.makeRoot()
        let review = WGFix.makePeer(parentID: root.uniqueIdentifier,
                                    command: "claude", mode: .codeReview)
        let wg = WGFix.wrap(name: "wgInhibitCR", sessions: [root, review])
        XCTAssertTrue(inhibits(wg, anchorID: review.uniqueIdentifier, pending: false))
    }

    func test_shouldInhibitRelaunch_diffAnchorNotPending() {
        let root = WGFix.makeRoot()
        let diff = WGFix.makePeer(parentID: root.uniqueIdentifier,
                                  command: "git diff", mode: .diff)
        let wg = WGFix.wrap(name: "wgInhibitDiff", sessions: [root, diff])
        XCTAssertTrue(inhibits(wg, anchorID: diff.uniqueIdentifier, pending: false))
    }

    // A pending anchor (overlay was showing at save time) must NOT inhibit:
    // that path relaunches the shell and re-presents the overlay.
    func test_shouldInhibitRelaunch_pendingAnchorDoesNotInhibit() {
        let root = WGFix.makeRoot()
        let review = WGFix.makePeer(parentID: root.uniqueIdentifier,
                                    command: "claude", mode: .codeReview)
        let wg = WGFix.wrap(name: "wgInhibitPending", sessions: [root, review])
        XCTAssertFalse(inhibits(wg, anchorID: review.uniqueIdentifier, pending: true))
    }

    // A regular-mode anchor keeps the normal relaunch behavior.
    func test_shouldInhibitRelaunch_regularAnchorDoesNotInhibit() {
        let root = WGFix.makeRoot()
        let wg = WGFix.wrap(name: "wgInhibitRegular", sessions: [root])
        XCTAssertFalse(inhibits(wg, anchorID: root.uniqueIdentifier, pending: false))
    }

    // A descriptor whose workgroup config is gone can't be classified, so
    // it must not inhibit (degrade to normal restore).
    func test_shouldInhibitRelaunch_unknownWorkgroupDoesNotInhibit() {
        let K = iTermWorkgroupRestoration.Key.self
        let state: [AnyHashable: Any] = [K.workgroupID: "does-not-exist",
                                         K.anchorID: "nobody",
                                         K.anchorPending: false]
        XCTAssertFalse(iTermWorkgroupRestoration.shouldInhibitRelaunch(
            forAnchorState: state,
            workgroupForID: { _ in nil }))
    }

    // MARK: - encode recursion guard

    // encodeState embeds each OTHER member's arrangement; those embedded
    // arrangements must NOT themselves carry a nested workgroup
    // descriptor, or restore would recurse. The guard is enforced by the
    // isEmbedding flag inside encodeState.
    func test_encodeState_embeddedMembersHaveNoNestedWorkgroupKey() {
        let wg = WGFix.wgRootWithPeers(n: 2)
        let root = wg.root!
        let peers = makePeerSessions(wg)
        let inst = iTermWorkgroupController.instance.adopt(
            workgroup: wg, leader: leader, instanceUniqueIdentifier: "wg-test",
            activeIdentifier: root.uniqueIdentifier,
            gitBase: CCGitBaseSelectorItem.defaultBase,
            peerSessionsByConfigID: peers, nonPeerSessionsByConfigID: [:])
        defer { iTermWorkgroupController.instance.exit(on: leader) }
        XCTAssertNotNil(inst)

        guard let state = iTermWorkgroupRestoration.encodeState(forSession: leader,
                                                               includeContents: false) else {
            XCTFail("Anchor should produce a workgroup descriptor")
            return
        }
        // Sanity: descriptor names this workgroup and lists the peers.
        XCTAssertEqual(state[iTermWorkgroupRestoration.Key.workgroupID] as? String,
                       wg.uniqueIdentifier)
        let members = state[iTermWorkgroupRestoration.Key.members] as? [[AnyHashable: Any]]
        XCTAssertEqual(members?.count, peers.count,
                       "Every non-anchor member should be embedded")
        // "Workgroup" is SESSION_ARRANGEMENT_WORKGROUP — must be absent
        // from each embedded member's arrangement (recursion guard).
        for m in members ?? [] {
            let arr = m[iTermWorkgroupRestoration.Key.arrangement] as? [AnyHashable: Any]
            XCTAssertNotNil(arr)
            XCTAssertNil(arr?["Workgroup"],
                         "Embedded member arrangement must not nest a workgroup descriptor")
        }
    }
}
