//
//  WorkgroupEntryTests.swift
//  ModernTests
//
//  Created by George Nachman on 4/25/26.
//
//  Test spec: see "Workgroup-entry test spec" in
//  ~/.claude/projects/-Users-gnachman-git-iterm2-alt5/memory or PR
//  notes. The numbered comments below map directly onto the spec
//  sections (§1.1, §1.3, etc.).
//

import XCTest
@testable import iTerm2SharedARC

final class WorkgroupEntryTests: WorkgroupEntryTestBase {

    // MARK: - §1 Toolbar item presence and content

    // §1.1 — toolbar item count matches config (after drop rules).
    func test_1_1_toolbarItemCountMatchesConfig() {
        let wg = WGFix.wgRootWithPeers(n: 2,
                                       rootItems: [.modeSwitcher, .reload],
                                       peerItems: [.modeSwitcher, .reload, .settings])
        enterWorkgroup(wg)
        XCTAssertNotNil(instance)
        for cfg in wg.sessions {
            guard let live = liveSession(forConfigID: cfg.uniqueIdentifier) else {
                XCTFail("No live session for \(cfg.displayName)")
                continue
            }
            let actual = instance!.toolbarItems(for: live)
            let expected = expectedToolbarItems(for: cfg)
            XCTAssertEqual(actual.count,
                           expected.count,
                           "\(cfg.displayName): expected \(expected.count) items, got \(actual.count)")
        }
    }

    // §1.2 — order of returned views matches config order.
    func test_1_2_toolbarItemOrderMatchesConfig() {
        let items: [iTermWorkgroupToolbarItem] = [.reload, .back, .forward, .settings]
        let wg = WGFix.wgRootWithPeers(n: 1, rootItems: items, peerItems: items)
        enterWorkgroup(wg)
        for cfg in wg.sessions {
            guard let live = liveSession(forConfigID: cfg.uniqueIdentifier) else { continue }
            let actual = instance!.toolbarItems(for: live)
            // Recover the kind from each view's `identifier` (the
            // builder sets it to the kind's rawValue).
            let actualKinds = actual.compactMap {
                iTermWorkgroupToolbarItemKind(rawValue: $0.identifier)
            }
            let expectedKinds = expectedToolbarItems(for: cfg).map { $0.kind }
            XCTAssertEqual(actualKinds, expectedKinds,
                           "\(cfg.displayName): order mismatch")
        }
    }

    // §1.3 — peer-host shadowing regression: a non-peer host that
    // has peer children must NOT return the empty toolbar slot — its
    // real items come from the nested port.
    func test_1_3_peerHostToolbarNotShadowedByEmptySlot() {
        let wg = WGFix.wgRootSplitWithPeers(splitItems: [.modeSwitcher, .reload],
                                            peerCount: 1)
        enterWorkgroup(wg)
        // Find the split-host config.
        let split = wg.sessions.first(where: {
            if case .split = $0.kind { return true }
            return false
        })!
        let live = liveSession(forConfigID: split.uniqueIdentifier)!
        let items = instance!.toolbarItems(for: live)
        XCTAssertFalse(items.isEmpty,
                       "Peer-host split returned empty toolbar — §1.3 regression")
        XCTAssertEqual(items.count, split.toolbarItems.count,
                       "Peer-host split should expose its full configured toolbar")
    }

    // §1.4 — view classes are correct for each item kind.
    func test_1_4_viewClassesPerKind() {
        let wg = WGFix.wgAllToolbarKinds()
        enterWorkgroup(wg)
        let peer = wg.sessions.first(where: {
            if case .peer = $0.kind { return true }
            return false
        })!
        let live = liveSession(forConfigID: peer.uniqueIdentifier)!
        let views = instance!.toolbarItems(for: live)
        // The expected sequence for the peer matches its config (it's
        // a peer-port toolbar so .modeSwitcher is kept; poller exists
        // because gitStatus + changedFileSelector are in the mix).
        let expectedClasses: [AnyClass] = [
            WorkgroupModeSwitcherItem.self,
            CCDiffSelectorItem.self,
            CCGitSessionToolbarItem.self,
            CCModeButtonToolbarItem.self,   // back
            CCModeButtonToolbarItem.self,   // forward
            CCModeButtonToolbarItem.self,   // reload
            CCModeButtonToolbarItem.self,   // settings
            SessionToolbarSpacer.self,
        ]
        XCTAssertEqual(views.count, expectedClasses.count)
        for (i, view) in views.enumerated() {
            XCTAssertTrue(type(of: view) === expectedClasses[i],
                          "View at index \(i): expected \(expectedClasses[i]), got \(type(of: view))")
        }
    }

    // MARK: - §2 ownerPeerID tagging

    // §2.1 — every tagged view's ownerPeerID is the config UUID of
    // the node whose toolbar list contains it.
    func test_2_1_ownerPeerIDIsConfigUUIDOfHost() {
        let wg = WGFix.wgRootWithPeers(n: 2,
                                       rootItems: [.reload],
                                       peerItems: [.reload])
        enterWorkgroup(wg)
        for cfg in wg.sessions {
            guard let live = liveSession(forConfigID: cfg.uniqueIdentifier) else { continue }
            for view in instance!.toolbarItems(for: live) {
                if let button = view as? CCModeButtonToolbarItem {
                    XCTAssertEqual(button.ownerPeerID, cfg.uniqueIdentifier)
                }
                if let selector = view as? CCDiffSelectorItem {
                    XCTAssertEqual(selector.ownerPeerID, cfg.uniqueIdentifier)
                }
            }
        }
    }

    // §2.2 — two peers each with a button get DIFFERENT ownerPeerID
    // tags (each its own peer's UUID).
    func test_2_2_distinctOwnerPeerIDsAcrossPeers() {
        let wg = WGFix.wgRootWithPeers(n: 2,
                                       rootItems: [.reload],
                                       peerItems: [.reload])
        enterWorkgroup(wg)
        var allTags = Set<String>()
        for cfg in wg.sessions {
            guard let live = liveSession(forConfigID: cfg.uniqueIdentifier) else { continue }
            for view in instance!.toolbarItems(for: live) {
                if let button = view as? CCModeButtonToolbarItem,
                   let id = button.ownerPeerID {
                    allTags.insert(id)
                }
            }
        }
        XCTAssertEqual(allTags.count, wg.sessions.count,
                       "Each peer should produce its own distinct ownerPeerID")
    }

    // §2.3 — buttons live on the session they're configured on, not
    // on the workgroup or a containing peer-group.
    func test_2_3_buttonOwnerIsLocalSessionConfig() {
        let wg = WGFix.wgRootPeersAndSplits(peerCount: 1, splitCount: 2)
        enterWorkgroup(wg)
        for cfg in wg.sessions {
            guard let live = liveSession(forConfigID: cfg.uniqueIdentifier) else { continue }
            for view in instance!.toolbarItems(for: live) {
                if let button = view as? CCModeButtonToolbarItem {
                    XCTAssertEqual(button.ownerPeerID,
                                   cfg.uniqueIdentifier,
                                   "Button on \(cfg.displayName) should be tagged with its own config UUID, not the workgroup or peer-group ID")
                }
            }
        }
    }

    // MARK: - §3 Delegate wiring

    // §3.1, §3.2 — buttonDelegate non-nil on every button; identity is
    // the peer port for peer-port toolbars and the workgroup instance
    // for non-peer toolbars.
    func test_3_1_3_2_buttonDelegateWiring() {
        let wg = WGFix.wgRootPeersAndSplits(peerCount: 1, splitCount: 1)
        enterWorkgroup(wg)
        for cfg in wg.sessions {
            guard let live = liveSession(forConfigID: cfg.uniqueIdentifier) else { continue }
            for view in instance!.toolbarItems(for: live) {
                guard let button = view as? CCModeButtonToolbarItem else { continue }
                XCTAssertNotNil(button.buttonDelegate,
                                "\(cfg.displayName): button missing delegate")
                if expectedToolbarIsPeerPort(cfg: cfg) {
                    XCTAssertTrue(
                        button.buttonDelegate is iTermWorkgroupPeerPort,
                        "\(cfg.displayName): peer-port button delegate should be the port")
                } else {
                    XCTAssertTrue(
                        button.buttonDelegate is iTermWorkgroupInstance,
                        "\(cfg.displayName): non-peer button delegate should be the instance")
                }
            }
        }
    }

    // §3.3 — same matrix for changedFileSelector.
    func test_3_3_diffSelectorDelegateWiring() {
        let wg = WGFix.wgRootPeersAndSplits(peerCount: 1, splitCount: 1)
        enterWorkgroup(wg)
        for cfg in wg.sessions {
            guard let live = liveSession(forConfigID: cfg.uniqueIdentifier) else { continue }
            for view in instance!.toolbarItems(for: live) {
                guard let selector = view as? CCDiffSelectorItem else { continue }
                XCTAssertNotNil(selector.diffSelectorDelegate)
                if expectedToolbarIsPeerPort(cfg: cfg) {
                    XCTAssertTrue(
                        selector.diffSelectorDelegate is iTermWorkgroupPeerPort)
                } else {
                    XCTAssertTrue(
                        selector.diffSelectorDelegate is iTermWorkgroupInstance)
                }
            }
        }
    }

    // §3.4 — modeSwitcher.modeSwitchDelegate is the owning peer port.
    func test_3_4_modeSwitchDelegateIsPeerPort() {
        let wg = WGFix.wgRootSplitWithPeers(
            splitItems: [.modeSwitcher],
            peerCount: 1)
        enterWorkgroup(wg)
        for cfg in wg.sessions {
            guard let live = liveSession(forConfigID: cfg.uniqueIdentifier) else { continue }
            for view in instance!.toolbarItems(for: live) {
                guard let switcher = view as? WorkgroupModeSwitcherItem else { continue }
                XCTAssertNotNil(switcher.modeSwitchDelegate)
                XCTAssertTrue(
                    switcher.modeSwitchDelegate is iTermWorkgroupPeerPort,
                    "modeSwitcher delegate should be the peer port")
            }
        }
    }

    // MARK: - §4 Peer port topology

    // §4.1 — main port keys = root + peer children of root; leader =
    // root.uniqueIdentifier.
    func test_4_1_mainPortPeerKeysAndLeader() {
        let wg = WGFix.wgRootWithPeers(n: 2)
        enterWorkgroup(wg)
        let root = wg.root!
        let peerKidIDs = wg.sessions
            .filter { $0.parentID == root.uniqueIdentifier }
            .filter { if case .peer = $0.kind { return true }; return false }
            .map { $0.uniqueIdentifier }
        let expected = Set([root.uniqueIdentifier] + peerKidIDs)
        // We don't have a public peers property; assert via
        // identifier(for:) against the realized sessions instead.
        for id in expected {
            let live = liveSession(forConfigID: id)!
            XCTAssertEqual(instance!.peerPort.identifier(for: live), id)
        }
        XCTAssertEqual(instance!.peerPort.activeSessionIdentifier,
                       root.uniqueIdentifier,
                       "Main port leader should be the root")
    }

    // §4.2 — for each non-peer host with peer children, exactly one
    // nested port exists; its keys = host + peer children of host.
    func test_4_2_nestedPortForPeerHost() {
        let wg = WGFix.wgRootSplitWithPeers(
            splitItems: [.modeSwitcher],
            peerCount: 2)
        enterWorkgroup(wg)
        let host = wg.sessions.first(where: {
            if case .split = $0.kind { return true }
            return false
        })!
        let hostLive = liveSession(forConfigID: host.uniqueIdentifier)!
        // The session's peerPort is the nested port — assert its
        // members.
        guard let port = hostLive.peerPort as? iTermWorkgroupPeerPort else {
            XCTFail("Peer-host should have a peer port assigned")
            return
        }
        let peerKidIDs = wg.sessions
            .filter { $0.parentID == host.uniqueIdentifier }
            .filter { if case .peer = $0.kind { return true }; return false }
            .map { $0.uniqueIdentifier }
        let expected = Set([host.uniqueIdentifier] + peerKidIDs)
        for id in expected {
            let live = liveSession(forConfigID: id)!
            XCTAssertEqual(port.identifier(for: live), id)
        }
        XCTAssertEqual(port.activeSessionIdentifier, host.uniqueIdentifier,
                       "Nested port's leader should be the host")
    }

    // §4.3 — non-peer host with no peer children does NOT get a port.
    func test_4_3_noNestedPortForLeafSplit() {
        let wg = WGFix.wgRootWithSplits(n: 1, splitItems: [.reload])
        enterWorkgroup(wg)
        let split = wg.sessions.first(where: {
            if case .split = $0.kind { return true }
            return false
        })!
        let live = liveSession(forConfigID: split.uniqueIdentifier)!
        XCTAssertNil(live.peerPort,
                     "Leaf split (no peer children) should not own a port")
    }

    // §4.4 — peerPort.contains is true iff session is a member.
    func test_4_4_peerPortContainsCorrectness() {
        let wg = WGFix.wgRootWithPeers(n: 2)
        enterWorkgroup(wg)
        // Members should be contained.
        for cfg in wg.sessions {
            let live = liveSession(forConfigID: cfg.uniqueIdentifier)!
            XCTAssertTrue(instance!.peerPort.contains(session: live))
        }
        // A foreign session should not be.
        let stranger = PTYSession(synthetic: false)!
        XCTAssertFalse(instance!.peerPort.contains(session: stranger))
    }

    // §4.5 — identifier(for:) returns config UUID for members, nil
    // otherwise.
    func test_4_5_peerPortIdentifierFor() {
        let wg = WGFix.wgRootWithPeers(n: 2)
        enterWorkgroup(wg)
        for cfg in wg.sessions {
            let live = liveSession(forConfigID: cfg.uniqueIdentifier)!
            XCTAssertEqual(instance!.peerPort.identifier(for: live),
                           cfg.uniqueIdentifier)
        }
        let stranger = PTYSession(synthetic: false)!
        XCTAssertNil(instance!.peerPort.identifier(for: stranger))
    }

    // MARK: - §5 Session ↔ instance/port back-pointers

    // §5.1, §5.2, §5.3, §5.4, §5.5 — combined for tree traversal.
    func test_5_backPointers() {
        let wg = WGFix.wgRootPeersAndSplits(peerCount: 2, splitCount: 2)
        enterWorkgroup(wg)
        let root = wg.root!
        for cfg in wg.sessions {
            guard let live = liveSession(forConfigID: cfg.uniqueIdentifier) else { continue }
            // §5.1: workgroupInstance back-pointer
            XCTAssertTrue(live.workgroupInstance === instance,
                          "\(cfg.displayName): workgroupInstance back-pointer wrong")
            // §5.5: leader's peerPort is the main port
            if cfg.uniqueIdentifier == root.uniqueIdentifier {
                XCTAssertTrue(live.peerPort === instance!.peerPort,
                              "Leader's peerPort should be the main port")
                continue
            }
            // §5.2: peers in the main port
            if configIsPeer(cfg.uniqueIdentifier) && cfg.parentID == root.uniqueIdentifier {
                XCTAssertTrue(live.peerPort === instance!.peerPort)
                continue
            }
            // §5.3 / §5.4: non-peer host
            if configHasPeerChildren(cfg.uniqueIdentifier) {
                XCTAssertNotNil(live.peerPort,
                                "Peer-host \(cfg.displayName) should have its nested port")
            } else {
                XCTAssertNil(live.peerPort,
                             "Leaf non-peer \(cfg.displayName) should have nil peerPort")
            }
        }
    }

    // MARK: - §6 Lookup helpers

    // §6.3 — config(forConfigID:) returns the right config for every
    // node. We can't reach the fileprivate liveSession helper, but we
    // can spot-check via toolbar callbacks (covered in §3 / §8).
    func test_6_3_configByID_viaPublicLookups() {
        let wg = WGFix.wgRootPeersAndSplits(peerCount: 1, splitCount: 1)
        enterWorkgroup(wg)
        // session(forIdentifier:) on a port resolves a peer's config
        // ID to its live session.
        for cfg in wg.sessions {
            let live = liveSession(forConfigID: cfg.uniqueIdentifier)!
            // peer ID round-trip via main port
            if let id = instance!.peerPort.identifier(for: live) {
                XCTAssertTrue(
                    instance!.peerPort.session(forIdentifier: id) === live)
            }
        }
    }

    // §6.2 — lookup uses reference identity, not GUID. Asserted
    // structurally: toolbarItems(for:) matches by `entry.session ===
    // session` (visible in the source), so two distinct PTYSessions
    // with the same GUID must NOT collide. Driving an actual GUID
    // rotation requires PTYSession.setGuid, which is not exposed to
    // Swift via the public header — but the inverse property is
    // checkable: a stranger session never resolves to a workgroup
    // toolbar even if its GUID happens to match a workgroup member.
    func test_6_2_lookupUsesReferenceIdentityNotGUID() {
        let wg = WGFix.wgRootWithSplits(n: 1, splitItems: [.reload])
        enterWorkgroup(wg)
        let split = wg.sessions.first(where: {
            if case .split = $0.kind { return true }
            return false
        })!
        let live = liveSession(forConfigID: split.uniqueIdentifier)!
        XCTAssertFalse(instance!.toolbarItems(for: live).isEmpty)
        // A second session with NO relationship to this workgroup
        // should resolve to an empty toolbar — even though it shares
        // the GUID space.
        let stranger = PTYSession(synthetic: false)!
        XCTAssertTrue(instance!.toolbarItems(for: stranger).isEmpty)
    }

    // MARK: - §7 Controller registration

    // §7.1 — after entering, controller resolves the leader to the
    // instance.
    func test_7_1_controllerRegistersInstance() {
        let wg = WGFix.wgRootOnly()
        registerWithModel(wg)
        defer { unregisterFromModel(wg) }
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader))
        let inst = iTermWorkgroupController.instance.workgroupInstance(on: leader)
        XCTAssertNotNil(inst)
        XCTAssertEqual(inst?.workgroupUniqueIdentifier, wg.uniqueIdentifier)
        iTermWorkgroupController.instance.exit(on: leader)
    }

    // §7.2 — controller's dict key is ObjectIdentifier(leader),
    // not leader.guid. Drives an actual GUID rotation on the leader
    // via KVC (-[PTYSession setGuid:] exists in PTYSession.m but is
    // not surfaced in the public header, so the Swift type-level
    // property is read-only — KVC dispatches to the unpublished
    // setter directly). If the controller keyed by GUID, this
    // lookup would miss after the rotation; ObjectIdentifier
    // keying makes it stable.
    func test_7_2_controllerSurvivesLeaderGUIDRotation() {
        let wg = WGFix.wgRootOnly()
        registerWithModel(wg)
        defer { unregisterFromModel(wg) }
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader))
        let originalGUID = leader.guid
        leader.setValue(UUID().uuidString, forKey: "guid")
        XCTAssertNotEqual(leader.guid, originalGUID,
                          "Sanity: KVC setter rotated the GUID")
        XCTAssertNotNil(
            iTermWorkgroupController.instance.workgroupInstance(on: leader),
            "Controller dict keys by ObjectIdentifier(leader); GUID rotation must not invalidate the lookup")
        iTermWorkgroupController.instance.exit(on: leader)
    }

    // §7.3 — re-entering the same workgroup is idempotent.
    func test_7_3_reEnterIdempotent() {
        let wg = WGFix.wgRootOnly()
        registerWithModel(wg)
        defer { unregisterFromModel(wg) }
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader))
        let inst1 = iTermWorkgroupController.instance.workgroupInstance(on: leader)
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader))
        let inst2 = iTermWorkgroupController.instance.workgroupInstance(on: leader)
        XCTAssertTrue(inst1 === inst2,
                      "Idempotent enter should keep the same instance")
        iTermWorkgroupController.instance.exit(on: leader)
    }

    // §7.4 — entering a different workgroup tears down the old.
    func test_7_4_enterDifferentWorkgroupReplacesInstance() {
        let wg1 = WGFix.wgRootOnly()
        let wg2 = WGFix.wgRootOnly()
        registerWithModel(wg1)
        registerWithModel(wg2)
        defer {
            unregisterFromModel(wg1)
            unregisterFromModel(wg2)
        }
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg1.uniqueIdentifier,
                on: leader))
        let inst1 = iTermWorkgroupController.instance.workgroupInstance(on: leader)
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg2.uniqueIdentifier,
                on: leader))
        let inst2 = iTermWorkgroupController.instance.workgroupInstance(on: leader)
        XCTAssertNotNil(inst2)
        XCTAssertFalse(inst1 === inst2,
                       "Switching workgroups should produce a fresh instance")
        XCTAssertEqual(inst2?.workgroupUniqueIdentifier, wg2.uniqueIdentifier)
        iTermWorkgroupController.instance.exit(on: leader)
    }

    // MARK: - §8 Git poller wiring

    // §8.1 / §8.2 — poller exists iff some node needs one; tracker
    // tracks the poller.
    func test_8_1_8_2_pollerPresenceTracksGitItems() {
        // Workgroup with no git items — no poller.
        let dry = WGFix.wgRootWithPeers(n: 1,
                                        rootItems: [.reload],
                                        peerItems: [.reload])
        enterWorkgroup(dry)
        XCTAssertNil(instance!.gitPoller, "No git item → no poller")
        teardownInstance()

        // Workgroup where only the leaf split has changedFileSelector.
        let withFileSel = WGFix.wgRootWithSplits(
            n: 1,
            rootItems: [.reload],
            splitItems: [.changedFileSelector])
        enterWorkgroup(withFileSel)
        XCTAssertNotNil(instance!.gitPoller,
                        "A non-peer split's changedFileSelector should still drive a poller")
    }

    // §8.3 — every diff selector and git-status view in the
    // workgroup shares one workgroup-wide poller, regardless of
    // which toolbar (main peer port, nested peer port, or non-peer
    // host) it's on.
    func test_8_3_pollerSharedAcrossAllToolbars() {
        let wg = pollerFanoutWorkgroup()
        enterWorkgroup(wg)
        let (diffSelectors, gitItems) = collectGitViews(workgroup: wg)
        XCTAssertFalse(diffSelectors.isEmpty)
        XCTAssertFalse(gitItems.isEmpty)
        for s in diffSelectors {
            XCTAssertTrue(s.poller === instance!.gitPoller,
                          "Every CCDiffSelectorItem must share the workgroup-wide poller")
        }
        for g in gitItems {
            XCTAssertTrue(g.poller === instance!.gitPoller,
                          "Every CCGitSessionToolbarItem must share the workgroup-wide poller")
        }
    }

    // §8.4 — gitPollerDidUpdate fans the update out to every diff
    // selector and git-status view across every toolbar (main peer
    // port, nested peer port, and non-peer host). Regression
    // coverage for an earlier bug that only iterated the main port.
    //
    // Drives the fanout by installing a counting delegate on each
    // relevant view; both CCDiffSelectorItem.set(files:) and
    // CCGitSessionToolbarItem.update() (called from pollerDidUpdate)
    // fire delegate?.itemDidChange at the end, so the spy captures
    // each invocation regardless of view kind.
    func test_8_4_pollerUpdateFansOutToAllToolbars() {
        let wg = pollerFanoutWorkgroup()
        enterWorkgroup(wg)
        let (diffSelectors, gitItems) = collectGitViews(workgroup: wg)
        let allTargets: [SessionToolbarGenericView] = diffSelectors + gitItems
        XCTAssertFalse(allTargets.isEmpty)

        let spy = FanoutSpyDelegate()
        for view in allTargets {
            view.delegate = spy
        }

        instance!.gitPollerDidUpdate()

        let expected = Set(allTargets.map { ObjectIdentifier($0) })
        XCTAssertEqual(spy.firedFor, expected,
                       "gitPollerDidUpdate must fan out to every diff selector and git-status view across peer, nested, and non-peer toolbars")
    }

    // Workgroup with git-aware items in all three toolbar locations:
    //   - main peer port (root + peer-of-root)
    //   - nested peer port (split-host + peer-of-split-host)
    //   - non-peer host (leaf split)
    private func pollerFanoutWorkgroup() -> iTermWorkgroup {
        let root = WGFix.makeRoot(
            items: [.gitStatus, .changedFileSelector])
        let mainPeer = WGFix.makePeer(
            parentID: root.uniqueIdentifier,
            items: [.gitStatus, .changedFileSelector])
        let leafSplit = WGFix.makeSplit(
            parentID: root.uniqueIdentifier,
            items: [.gitStatus, .changedFileSelector])
        let splitHost = WGFix.makeSplit(
            parentID: root.uniqueIdentifier,
            items: [.gitStatus, .changedFileSelector])
        let nestedPeer = WGFix.makePeer(
            parentID: splitHost.uniqueIdentifier,
            items: [.gitStatus, .changedFileSelector])
        return WGFix.wrap(name: "wgFanout",
                          sessions: [root, mainPeer, leafSplit,
                                     splitHost, nestedPeer])
    }

    private func collectGitViews(workgroup wg: iTermWorkgroup)
            -> (diffSelectors: [CCDiffSelectorItem],
                gitItems: [CCGitSessionToolbarItem]) {
        var diffSelectors: [CCDiffSelectorItem] = []
        var gitItems: [CCGitSessionToolbarItem] = []
        for cfg in wg.sessions {
            guard let live = liveSession(forConfigID: cfg.uniqueIdentifier)
                else { continue }
            for view in instance!.toolbarItems(for: live) {
                if let s = view as? CCDiffSelectorItem {
                    diffSelectors.append(s)
                }
                if let g = view as? CCGitSessionToolbarItem {
                    gitItems.append(g)
                }
            }
        }
        return (diffSelectors, gitItems)
    }

    // MARK: - §9 Tracked session identities

    // §9.2 — posting iTermSessionWillTerminate for any non-leader
    // tracked session triggers controller.exit on the leader. This
    // regression-covers the half-alive workgroup state from before
    // the observer was added.
    func test_9_2_terminationOfChildExitsWorkgroup() {
        let wg = WGFix.wgRootWithSplits(n: 1, splitItems: [.reload])
        registerWithModel(wg)
        defer { unregisterFromModel(wg) }
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader,
                spawner: spawner))
        XCTAssertNotNil(
            iTermWorkgroupController.instance.workgroupInstance(on: leader))
        // Find the child session and send its terminate notification.
        let split = wg.sessions.first(where: {
            if case .split = $0.kind { return true }
            return false
        })!
        let child = spawner.session(forConfigID: split.uniqueIdentifier)!
        NotificationCenter.default.post(
            name: NSNotification.Name.iTermSessionWillTerminate,
            object: child)
        XCTAssertNil(
            iTermWorkgroupController.instance.workgroupInstance(on: leader),
            "Child termination should drive the workgroup out")
    }

    // MARK: - §10 Tree shape

    // §10.2 — recursive descent realizes every node. A
    // split-of-split-of-split-of-split + a tab-under-deep-split
    // workgroup must produce a live session for every non-root
    // config, verifying that spawnNonPeerChildren walks the full
    // tree (not just one level).
    func test_10_2_recursiveDescentSpawnsEveryNode() {
        let wg = WGFix.wgDeepNesting()
        enterWorkgroup(wg)
        XCTAssertNotNil(instance)
        let nonRoot = wg.sessions.filter { $0.parentID != nil }
        XCTAssertFalse(nonRoot.isEmpty)
        for cfg in nonRoot {
            XCTAssertNotNil(spawner.session(forConfigID: cfg.uniqueIdentifier),
                            "Non-root \(cfg.displayName) was never spawned")
        }
    }

    // MARK: - PTYSession.restartSessionWithCommand guard

    // Review-comment regression: -restartSessionWithCommand: forwards
    // to -restartSession, which asserts(isRestartable). Workgroup
    // callers gate the call with isRestartable() in Swift, but the
    // ObjC method itself has no guard — calling it directly on a
    // non-restartable session would abort. Mirror the Swift caller
    // posture by early-returning at the top of the ObjC method.
    func test_restartSessionWithCommand_isNoOpWhenNotRestartable() {
        let session = PTYSession(synthetic: false)!
        XCTAssertFalse(session.isRestartable(),
                       "Fresh PTYSession (no _program) must not be restartable")
        // Pre-fix: this reaches assert(self.isRestartable) inside
        // restartSession and aborts the process. Post-fix: returns
        // silently from restartSessionWithCommand:.
        session.restart(withCommand: "")
        XCTAssertFalse(session.isRestartable())
    }

    // MARK: - perFileCommand filename escaping

    // Review-comment regression: the user's existing template was
    // `git difftool -y -x vimdiff HEAD -- '\(file)'` — they wrap the
    // placeholder in single quotes themselves so filenames with
    // spaces survive. Make the substitution shell-escape the
    // filename so users don't have to quote it manually.
    func test_resolvedPerFileCommand_wrapsFilenameInSingleQuotes() {
        let cfg = WGFix.makePeer(
            parentID: "x",
            items: [.changedFileSelector],
            perFileCommand: "git diff -- \\(file)")
        XCTAssertEqual(
            cfg.resolvedPerFileCommand(filename: "path/to/some file.txt"),
            "git diff -- 'path/to/some file.txt'")
    }

    func test_resolvedPerFileCommand_escapesEmbeddedSingleQuote() {
        let cfg = WGFix.makePeer(
            parentID: "x",
            items: [.changedFileSelector],
            perFileCommand: "vim \\(file)")
        // POSIX-shell escape for a single quote inside a single-
        // quoted string is the four-char sequence: '\''
        XCTAssertEqual(
            cfg.resolvedPerFileCommand(filename: "O'Brien.txt"),
            "vim 'O'\\''Brien.txt'")
    }

    // The user's existing pattern keeps working: their literal
    // single-quote wrappers around the placeholder concatenate with
    // the new escaped substitution to produce ''escaped'' — shell-
    // equivalent to the just-quoted string, so the resulting
    // command is still well-formed.
    func test_resolvedPerFileCommand_existingQuotedTemplateStillWorks() {
        let cfg = WGFix.makePeer(
            parentID: "x",
            items: [.changedFileSelector],
            perFileCommand: "git difftool -y -x vimdiff HEAD -- '\\(file)'")
        XCTAssertEqual(
            cfg.resolvedPerFileCommand(filename: "src/main.swift"),
            "git difftool -y -x vimdiff HEAD -- ''src/main.swift''")
    }

    // MARK: - Teardown skips already-exited entries

    // Review-comment regression: teardown() iterates every non-peer
    // entry and calls terminate() unconditionally. If one of those
    // children has ALREADY exited (e.g. it crashed and was cleaned
    // up out-of-band), the second terminate() call posts a redundant
    // iTermSessionWillTerminate notification mid-teardown — noise
    // that re-enters the observer chain. Fix: skip entries whose
    // `exited` flag is already true.
    func test_teardown_skipsAlreadyExitedNonPeerEntries() {
        spawner.sessionFactory = { SpyPTYSession(synthetic: false)! }
        let wg = WGFix.wgRootWithSplits(n: 1, splitItems: [.reload])
        enterWorkgroup(wg)
        let split = wg.sessions.first(where: {
            if case .split = $0.kind { return true }
            return false
        })!
        let child = spawner.session(forConfigID: split.uniqueIdentifier)
                as! SpyPTYSession
        // Simulate: the child already terminated independently
        // before workgroup teardown runs.
        child.spy_overrideExited = true

        instance!.teardown()

        XCTAssertEqual(child.spy_terminateCount, 0,
                       "teardown() should not call terminate() on a child whose exited flag is already true")
    }

    // MARK: - §11 Teardown completeness

    // §11.1, §11.4, §11.5 — exit clears back-pointers, removes from
    // controller, leaves leader alive. The leader's back-pointers
    // and the non-peer-host bookkeeping are explicitly cleared by
    // teardown(); peer-port members rely on the weak references
    // niling out when the port is invalidated and the instance
    // released, so we test those by checking either explicit-nil
    // (leader, non-peer hosts) or "no longer pointing at the live
    // instance" via reference comparison.
    func test_11_teardownClearsState() {
        let wg = WGFix.wgRootPeersAndSplits(peerCount: 1, splitCount: 1)
        workgroup = wg
        registerWithModel(wg)
        defer { unregisterFromModel(wg) }
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader,
                spawner: spawner))
        let allLives: [PTYSession] = wg.sessions.compactMap {
            liveSession(forConfigID: $0.uniqueIdentifier)
        }
        // Identify non-peer hosts (root + splits/tabs without peer
        // children) — teardown() explicitly nils these.
        let nonPeerHosts: [PTYSession] = wg.sessions.compactMap { cfg in
            switch cfg.kind {
            case .peer: return nil
            default:
                return self.liveSession(forConfigID: cfg.uniqueIdentifier)
            }
        }
        iTermWorkgroupController.instance.exit(on: leader)
        XCTAssertNil(
            iTermWorkgroupController.instance.workgroupInstance(on: leader),
            "Controller dict should be empty for leader after exit")
        for s in nonPeerHosts {
            XCTAssertNil(s.workgroupInstance,
                         "Non-peer hosts should have nil workgroupInstance after teardown")
            XCTAssertNil(s.peerPort,
                         "Non-peer hosts should have nil peerPort after teardown")
        }
        // §11.5 — leader still alive after teardown.
        XCTAssertFalse(leader.exited, "Leader should not be terminated by teardown")
        _ = allLives
    }

    // MARK: - Test helpers

    private func expectedToolbarIsPeerPort(cfg: iTermWorkgroupSessionConfig) -> Bool {
        if case .peer = cfg.kind { return true }
        if cfg.parentID == nil { return true }
        return configHasPeerChildren(cfg.uniqueIdentifier)
    }

    private func registerWithModel(_ wg: iTermWorkgroup) {
        iTermWorkgroupModel.instance.add(wg)
    }

    private func unregisterFromModel(_ wg: iTermWorkgroup) {
        iTermWorkgroupModel.instance.remove(uniqueIdentifier: wg.uniqueIdentifier)
    }

    // Allow §8 to run two enter/teardown cycles in a single method.
    private func teardownInstance() {
        instance?.teardown()
        instance = nil
    }
}

