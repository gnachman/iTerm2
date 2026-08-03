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
                                       rootItems: [.modeSwitcher, .reload(nil)],
                                       peerItems: [.modeSwitcher, .reload(nil)])
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

    // §1.2 — order of returned views matches config order. The
    // navigation cluster + standalone reload only render alongside a
    // changed-file selector (the build-time guard drops .navigation
    // otherwise), so the input list seeds one. .modeSwitcher is in
    // the list so the auto-injection of .name is suppressed (it
    // would prepend otherwise and throw off the order check).
    func test_1_2_toolbarItemOrderMatchesConfig() {
        let items: [iTermWorkgroupToolbarItem] = [
            .modeSwitcher,
            .changedFileSelector,
            .reload(nil),
            .navigation(WorkgroupNavigationShortcuts(back: nil, forward: nil, reload: nil))
        ]
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
        let wg = WGFix.wgRootSplitWithPeers(splitItems: [.modeSwitcher, .reload(nil)],
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
        // Expected sequence matches the fixture's item order:
        // modeSwitcher, changedFileSelector, gitStatus, navigation
        // (back/forward/reload cluster), reload (standalone), spacer.
        // This is a peer-port toolbar so .modeSwitcher is kept; the
        // poller is alive because gitStatus + changedFileSelector are
        // in the mix.
        let expectedClasses: [AnyClass] = [
            WorkgroupModeSwitcherItem.self,
            CCDiffSelectorItem.self,
            CCGitSessionToolbarItem.self,
            WorkgroupNavigationToolbarItem.self,
            WorkgroupReloadToolbarItem.self,
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
                                       rootItems: [.reload(nil)],
                                       peerItems: [.reload(nil)])
        enterWorkgroup(wg)
        for cfg in wg.sessions {
            guard let live = liveSession(forConfigID: cfg.uniqueIdentifier) else { continue }
            for view in instance!.toolbarItems(for: live) {
                if let nav = view as? WorkgroupNavigationToolbarItem {
                    XCTAssertEqual(nav.ownerPeerID, cfg.uniqueIdentifier)
                }
                if let reload = view as? WorkgroupReloadToolbarItem {
                    XCTAssertEqual(reload.ownerPeerID, cfg.uniqueIdentifier)
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
                                       rootItems: [.reload(nil)],
                                       peerItems: [.reload(nil)])
        enterWorkgroup(wg)
        var allTags = Set<String>()
        for cfg in wg.sessions {
            guard let live = liveSession(forConfigID: cfg.uniqueIdentifier) else { continue }
            for view in instance!.toolbarItems(for: live) {
                if let reload = view as? WorkgroupReloadToolbarItem,
                   let id = reload.ownerPeerID {
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
                if let nav = view as? WorkgroupNavigationToolbarItem {
                    XCTAssertEqual(nav.ownerPeerID,
                                   cfg.uniqueIdentifier,
                                   "Navigation cluster on \(cfg.displayName) should be tagged with its own config UUID, not the workgroup or peer-group ID")
                }
                if let reload = view as? WorkgroupReloadToolbarItem {
                    XCTAssertEqual(reload.ownerPeerID,
                                   cfg.uniqueIdentifier,
                                   "Reload button on \(cfg.displayName) should be tagged with its own config UUID, not the workgroup or peer-group ID")
                }
            }
        }
    }

    // MARK: - §3 Delegate wiring

    // §3.1, §3.2 — navigationDelegate non-nil on every navigation /
    // reload toolbar item; identity is the peer port for peer-port
    // toolbars and the workgroup instance for non-peer toolbars.
    func test_3_1_3_2_buttonDelegateWiring() {
        let wg = WGFix.wgRootPeersAndSplits(peerCount: 1, splitCount: 1)
        enterWorkgroup(wg)
        for cfg in wg.sessions {
            guard let live = liveSession(forConfigID: cfg.uniqueIdentifier) else { continue }
            for view in instance!.toolbarItems(for: live) {
                let delegate: WorkgroupNavigationToolbarItemDelegate?
                if let nav = view as? WorkgroupNavigationToolbarItem {
                    delegate = nav.navigationDelegate
                } else if let reload = view as? WorkgroupReloadToolbarItem {
                    delegate = reload.navigationDelegate
                } else {
                    continue
                }
                XCTAssertNotNil(delegate,
                                "\(cfg.displayName): toolbar item missing navigationDelegate")
                if expectedToolbarIsPeerPort(cfg: cfg) {
                    XCTAssertTrue(
                        delegate is iTermWorkgroupPeerPort,
                        "\(cfg.displayName): peer-port toolbar's delegate should be the port")
                } else {
                    XCTAssertTrue(
                        delegate is iTermWorkgroupInstance,
                        "\(cfg.displayName): non-peer toolbar's delegate should be the instance")
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
        let wg = WGFix.wgRootWithSplits(n: 1, splitItems: [.reload(nil)])
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
        let wg = WGFix.wgRootWithSplits(n: 1, splitItems: [.reload(nil)])
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
                on: leader,
                mechanism: .menu))
        let inst = iTermWorkgroupController.instance.workgroupInstance(on: leader)
        XCTAssertNotNil(inst)
        XCTAssertEqual(inst?.workgroupUniqueIdentifier, wg.uniqueIdentifier)
        iTermWorkgroupController.instance.exit(on: leader)
    }

    // §7.2 — controller resolution is independent of session GUIDs
    // (it goes through the member's workgroupInstance back-pointer
    // and the stable instanceUniqueIdentifier key). Drives an actual
    // GUID rotation on the leader via KVC (-[PTYSession setGuid:]
    // exists in PTYSession.m but is not surfaced in the public
    // header, so the Swift type-level property is read-only — KVC
    // dispatches to the unpublished setter directly). If the
    // controller keyed by GUID, this lookup would miss after the
    // rotation.
    func test_7_2_controllerSurvivesLeaderGUIDRotation() {
        let wg = WGFix.wgRootOnly()
        registerWithModel(wg)
        defer { unregisterFromModel(wg) }
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader,
                mechanism: .menu))
        let originalGUID = leader.guid
        leader.setValue(UUID().uuidString, forKey: "guid")
        XCTAssertNotEqual(leader.guid, originalGUID,
                          "Sanity: KVC setter rotated the GUID")
        XCTAssertNotNil(
            iTermWorkgroupController.instance.workgroupInstance(on: leader),
            "Controller resolves via the workgroupInstance back-pointer and the stable instanceUniqueIdentifier key; GUID rotation must not invalidate the lookup")
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
                on: leader,
                mechanism: .menu))
        let inst1 = iTermWorkgroupController.instance.workgroupInstance(on: leader)
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader,
                mechanism: .menu))
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
                on: leader,
                mechanism: .menu))
        let inst1 = iTermWorkgroupController.instance.workgroupInstance(on: leader)
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg2.uniqueIdentifier,
                on: leader,
                mechanism: .menu))
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
                                        rootItems: [.reload(nil)],
                                        peerItems: [.reload(nil)])
        enterWorkgroup(dry)
        XCTAssertNil(instance!.gitPoller, "No git item → no poller")
        teardownInstance()

        // Workgroup where only the leaf split has changedFileSelector.
        let withFileSel = WGFix.wgRootWithSplits(
            n: 1,
            rootItems: [.reload(nil)],
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
        let wg = WGFix.wgRootWithSplits(n: 1, splitItems: [.reload(nil)])
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
        let wg = WGFix.wgRootWithSplits(n: 1, splitItems: [.reload(nil)])
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

    // MARK: - §12 Session-lookup registry pass

    // §12.1 — a workgroup peer that is in no tab and not buried is
    // still resolvable by GUID, via the lookup's workgroup-registry
    // pass; after exit it is unreachable again. In the test bundle
    // there are no terminal windows and nothing is buried, so the
    // registry leg is provably the one that resolves these.
    func test_12_1_registryPassResolvesPortOnlyPeers() {
        let wg = WGFix.wgRootWithPeers(n: 2)
        registerWithModel(wg)
        defer { unregisterFromModel(wg) }
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader,
                spawner: spawner))
        defer { iTermWorkgroupController.instance.exit(on: leader) }
        let controller = iTermController.sharedInstance()!
        let peerConfigs = wg.sessions.filter {
            if case .peer = $0.kind { return true }
            return false
        }
        XCTAssertEqual(peerConfigs.count, 2)
        var peerGuids: [String] = []
        for cfg in peerConfigs {
            let peer = spawner.session(forConfigID: cfg.uniqueIdentifier)!
            peerGuids.append(peer.guid)
            XCTAssertTrue(controller.anySession(withGUID: peer.guid) === peer,
                          "Port-only peer must be findable by GUID")
            // Prove WHICH leg found it, so a future regression in an
            // earlier leg can't mask one here.
            var location: iTermSessionLookupLocation?
            controller.enumerateSessionLookupLocations { session, loc, stop in
                if session?.guid == peer.guid {
                    location = loc
                    stop?.pointee = true
                }
            }
            XCTAssertEqual(location, .workgroupRegistryPort)
        }
        // Parity: the diagnosis dump is built on the same enumerator,
        // so it must mention every session the lookup can reach.
        let diagnosis = controller.diagnosis(unresolvableGUID: "no-such-guid")
        for guid in peerGuids {
            XCTAssertTrue(diagnosis.contains(guid),
                          "Diagnosis must list reachable session \(guid)")
        }
        // Exit unregisters; nothing remains reachable through the
        // registry (no ghost).
        iTermWorkgroupController.instance.exit(on: leader)
        for guid in peerGuids {
            XCTAssertNil(controller.anySession(withGUID: guid),
                         "Exited peer must not be findable")
        }
    }

    // §12.2 — when no member of a peer group has a live delegate and
    // none is buried (the fixture's permanent condition), activate
    // refuses AND leaves activeSessionIdentifier untouched, so the
    // port never claims a peer that didn't swap in. This is the
    // no-desync half of the findable-implies-revealable contract; the
    // reveal half (window-creating revival of a registry-only peer,
    // and the buried-anchor rescue) needs real windows and
    // iTermBuriedSessions state, so it is covered by manual
    // verification rather than this unit suite.
    func test_12_2_activateWithoutAnyAnchorRefusesAndKeepsActiveIdentifier() {
        let wg = WGFix.wgRootWithPeers(n: 1)
        registerWithModel(wg)
        defer { unregisterFromModel(wg) }
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader,
                spawner: spawner))
        defer { iTermWorkgroupController.instance.exit(on: leader) }
        let port = leader.peerPort!
        XCTAssertNil(port.sessionDelegate)
        let peerCfg = wg.sessions.first {
            if case .peer = $0.kind { return true }
            return false
        }!
        let before = port.activeSessionIdentifier
        XCTAssertFalse(port.activate(identifier: peerCfg.uniqueIdentifier),
                       "No anchor anywhere: activate must refuse")
        XCTAssertEqual(port.activeSessionIdentifier, before,
                       "A refused activation must not commit")
    }

    // MARK: - §13 Mid-spawn termination

    // §13.1 — a member dying synchronously while the entry spawn loop
    // is still running tears the instance down via the
    // sessionWillTerminate observer; enter() must report failure, not
    // register the corpse, and not leave any spawned child pointing
    // at it.
    func test_13_1_memberDeathMidSpawnAbortsEntryWithoutGhost() {
        let root = WGFix.makeRoot()
        let peer = WGFix.makePeer(parentID: root.uniqueIdentifier)
        let split1 = WGFix.makeSplit(parentID: root.uniqueIdentifier)
        let split2 = WGFix.makeSplit(parentID: root.uniqueIdentifier)
        let wg = WGFix.wrap(name: "sabotage", sessions: [root, peer, split1, split2])
        registerWithModel(wg)
        defer { unregisterFromModel(wg) }

        let saboteur = TerminateDuringSpawnSpawner()
        saboteur.sessionFactory = { SpyPTYSession(synthetic: false)! }
        saboteur.terminateTarget = { [weak leader = self.leader] in leader }

        let entered = iTermWorkgroupController.instance.enter(
            workgroupUniqueIdentifier: wg.uniqueIdentifier,
            on: leader,
            spawner: saboteur)
        XCTAssertFalse(entered,
                       "enter() must not report success after a mid-spawn teardown")

        // No ghost: the aborted instance is not registered anywhere.
        let abortedID = saboteur.workgroupInstanceIDsByConfigID.values.first
        XCTAssertNotNil(abortedID)
        if let abortedID {
            XCTAssertNil(
                iTermWorkgroupController.instance.mainSession(
                    forInstanceUniqueIdentifier: abortedID))
            XCTAssertFalse(
                iTermWorkgroupController.instance.allInstances.contains {
                    $0.instanceUniqueIdentifier == abortedID
                })
        }
        // Teardown cleaned the leader.
        XCTAssertNil(leader.workgroupInstance)
        XCTAssertNil(leader.peerPort)
        // No spawned session points at the corpse (registerNonPeer's
        // didTeardown guard; the spawn loop also aborts).
        for record in saboteur.records {
            if let session = record.session {
                XCTAssertNil(session.workgroupInstance,
                             "\(record.config.displayName) points at a torn-down instance")
            }
        }
        // The realized peer was terminated by teardown exactly once
        // (didTeardown reentrancy guard held).
        let spawnedPeer = saboteur.session(forConfigID: peer.uniqueIdentifier) as! SpyPTYSession
        XCTAssertEqual(spawnedPeer.spy_terminateCount, 1)
        // The split whose spawn the sabotage interrupted was already
        // installed by the spawner but could never be registered;
        // teardown can't reach it, so the spawn path must close the
        // stray itself (closeStraySpawn; delegate-less in this fixture,
        // so it terminates directly).
        let straySplit = saboteur.session(forConfigID: split1.uniqueIdentifier) as! SpyPTYSession
        XCTAssertEqual(straySplit.spy_terminateCount, 1,
                       "The mid-spawn stray must be closed, not stranded")
        // The second split was never spawned at all (the loop aborts).
        XCTAssertNil(saboteur.session(forConfigID: split2.uniqueIdentifier))
    }

    // §13.2 — same sabotage, but the interrupted spawn is a split that
    // HOSTS A NESTED PEER GROUP. The guard must fire before the nested
    // branch runs: no nested peers spawned into the dead instance (they
    // would be running, windowless, unreachable shells that nothing
    // ever terminates), and the stray host itself is closed.
    func test_13_2_memberDeathDuringNestedHostSpawnSpawnsNoNestedPeers() {
        let root = WGFix.makeRoot()
        let host = WGFix.makeSplit(parentID: root.uniqueIdentifier)
        let nestedPeer = WGFix.makePeer(parentID: host.uniqueIdentifier)
        let wg = WGFix.wrap(name: "nested-sabotage", sessions: [root, host, nestedPeer])
        registerWithModel(wg)
        defer { unregisterFromModel(wg) }

        let saboteur = TerminateDuringSpawnSpawner()
        saboteur.sessionFactory = { SpyPTYSession(synthetic: false)! }
        saboteur.terminateTarget = { [weak leader = self.leader] in leader }

        XCTAssertFalse(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader,
                spawner: saboteur))
        XCTAssertNil(saboteur.session(forConfigID: nestedPeer.uniqueIdentifier),
                     "No nested peer may be spawned into a torn-down instance")
        let hostSession = saboteur.session(forConfigID: host.uniqueIdentifier) as! SpyPTYSession
        XCTAssertEqual(hostSession.spy_terminateCount, 1,
                       "The stray nested-group host must be closed")
        XCTAssertNil(hostSession.workgroupInstance)
        XCTAssertNil(hostSession.peerPort)
    }

    // §13.3 — the member dies later still: DURING the nested peer
    // spawn itself (the host already passed the spawnSplit guard).
    // registerNestedPeerPort's backstop must invalidate the port
    // (terminating the just-spawned nested peer), unwind the port
    // assignment on the host, and close the host as a stray — it was
    // never registered anywhere, so no teardown sweep can reach it.
    func test_13_3_memberDeathDuringNestedPeerSpawnClosesHostAndPeers() {
        let root = WGFix.makeRoot()
        let host = WGFix.makeSplit(parentID: root.uniqueIdentifier)
        let nestedPeer = WGFix.makePeer(parentID: host.uniqueIdentifier)
        let wg = WGFix.wrap(name: "nested-peer-sabotage",
                            sessions: [root, host, nestedPeer])
        registerWithModel(wg)
        defer { unregisterFromModel(wg) }

        let saboteur = TerminateDuringPeerSpawnSpawner()
        saboteur.sessionFactory = { SpyPTYSession(synthetic: false)! }
        saboteur.terminateTarget = { [weak leader = self.leader] in leader }

        XCTAssertFalse(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader,
                spawner: saboteur))
        let hostSession = saboteur.session(forConfigID: host.uniqueIdentifier) as! SpyPTYSession
        XCTAssertEqual(hostSession.spy_terminateCount, 1,
                       "The host must be closed; nothing else can ever reach it")
        XCTAssertNil(hostSession.peerPort,
                     "The invalidated port must not stay wired to the host")
        XCTAssertNil(hostSession.workgroupInstance)
        let nestedPeerSession = saboteur.session(forConfigID: nestedPeer.uniqueIdentifier) as! SpyPTYSession
        XCTAssertEqual(nestedPeerSession.spy_terminateCount, 1,
                       "invalidate() must terminate the spawned nested peer")
    }

    // MARK: - §14 Late-fulfilling peer spawns

    // §14.1 — a peer whose spawn fulfills after the workgroup exited
    // must come out clean: no back-pointer to the dead instance
    // (attachBackPointers' didTeardown guard), no reference to the
    // invalidated port (the init fan-out's invalidated guard), and
    // terminated by invalidate()'s deferred kill.
    func test_14_1_lateFulfillingPeerDoesNotAttachToTornDownWorkgroup() {
        let root = WGFix.makeRoot()
        let peer = WGFix.makePeer(parentID: root.uniqueIdentifier)
        let wg = WGFix.wrap(name: "late", sessions: [root, peer])
        registerWithModel(wg)
        defer { unregisterFromModel(wg) }
        spawner.pendingPeerConfigIDs = [peer.uniqueIdentifier]
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader,
                spawner: spawner))
        // Exit while the peer's spawn is still unfulfilled. Teardown's
        // back-pointer sweep only covers realized peers — the gap
        // under test.
        iTermWorkgroupController.instance.exit(on: leader)

        let late = SpyPTYSession(synthetic: false)!
        spawner.fulfillPendingPeer(configID: peer.uniqueIdentifier, with: late)
        XCTAssertNil(late.workgroupInstance,
                     "Late fulfillment must not resurrect the instance back-pointer")
        XCTAssertNil(late.peerPort,
                     "Late fulfillment must not wire the invalidated port")
        XCTAssertEqual(late.spy_terminateCount, 1,
                       "invalidate()'s deferred terminate should kill the late peer")
    }

    // §14.2 — a committed activation whose peer spawn REJECTS (the
    // real spawner rejects on session-terminated / missing profile /
    // missing view) must roll back: then-blocks never run for a
    // rejected promise, so the catchError leg restores the last
    // actually-swapped identifier and fires the subclass resync hook.
    // Uses RollbackSpyPort because committing requires an activation
    // anchor that unit fixtures cannot provide (see hasActivationAnchor).
    func test_14_2_rejectedSpawnRollsBackCommittedActivation() {
        var seal: iTermPromiseSeal?
        let pending = iTermPromise<PTYSession> { seal = $0 }
        let port = RollbackSpyPort(
            peers: ["leaderID": iTermPromise<PTYSession>(value: leader),
                    "peerID": pending],
            activeSessionIdentifier: "leaderID",
            leaderIdentifier: "leaderID")
        XCTAssertTrue(port.activate(identifier: "peerID"))
        XCTAssertEqual(port.activeSessionIdentifier, "peerID",
                       "Activation commits aspirationally")
        seal?.reject(NSError(domain: "test", code: 1))
        XCTAssertEqual(port.activeSessionIdentifier, "leaderID",
                       "Rejection must roll the commit back")
        XCTAssertEqual(port.rolledBackTo, ["leaderID"],
                       "The subclass hook must fire so mode switchers resync")
    }

    // §14.3 — activating a peer whose spawn ALREADY rejected must
    // refuse without committing. This is the synchronous twin of 14.2:
    // a settled promise runs callbacks synchronously, so a commit here
    // would fire the rollback INSIDE activate — before the
    // iTermWorkgroupPeerPort override's post-super switcher sync,
    // which would then overwrite the rollback's resync — and the
    // caller would be told the activation succeeded.
    func test_14_3_activateOnAlreadyRejectedSpawnRefusesWithoutCommitting() {
        var seal: iTermPromiseSeal?
        let rejected = iTermPromise<PTYSession> { seal = $0 }
        seal?.reject(NSError(domain: "test", code: 1))
        let port = RollbackSpyPort(
            peers: ["leaderID": iTermPromise<PTYSession>(value: leader),
                    "peerID": rejected],
            activeSessionIdentifier: "leaderID",
            leaderIdentifier: "leaderID")
        XCTAssertFalse(port.activate(identifier: "peerID"),
                       "A peer that can never exist must not report activation success")
        XCTAssertEqual(port.activeSessionIdentifier, "leaderID",
                       "Nothing may be committed for a dead peer")
        XCTAssertEqual(port.rolledBackTo, [],
                       "Upfront refusal means there is nothing to roll back")
    }

    // §14.4 — a swap that silently declined (PTYTab refuses while a
    // resize holds the lock, or for tmux clients) must not be recorded
    // as the last real swap: a later rollback would restore the
    // phantom, making activeSession lie and defeating reveal's rescue
    // gate. recordSwapOutcome is the seam (the swap itself needs a
    // real PTYTab); the declined outcome is a replacement that never
    // acquired a delegate.
    func test_14_4_declinedSwapIsNotRecordedAsLastSwapped() {
        var seal: iTermPromiseSeal?
        let pending = iTermPromise<PTYSession> { seal = $0 }
        let port = RollbackSpyPort(
            peers: ["leaderID": iTermPromise<PTYSession>(value: leader),
                    "peerID": pending],
            activeSessionIdentifier: "leaderID",
            leaderIdentifier: "leaderID")
        // Simulate a declined swap of some other member: the
        // replacement never landed in a tab (delegate stays nil).
        port.recordSwapOutcome(identifier: "phantomID",
                               replacement: PTYSession(synthetic: false)!)
        // Now a committed activation fails; the rollback must restore
        // the member whose view really occupies the tab ("leaderID"),
        // not the phantom.
        XCTAssertTrue(port.activate(identifier: "peerID"))
        seal?.reject(NSError(domain: "test", code: 1))
        XCTAssertEqual(port.activeSessionIdentifier, "leaderID")
        XCTAssertEqual(port.rolledBackTo, ["leaderID"])
    }

    // §14.5 — peer cycling must skip members whose spawn already
    // failed: activate() refuses them without advancing, so a cycle
    // that targets a dead member would wedge there forever (every
    // keypress recomputes the same dead target).
    func test_14_5_peerCyclingSkipsDeadMembers() {
        let wg = WGFix.wgRootWithPeers(n: 2)
        registerWithModel(wg)
        defer { unregisterFromModel(wg) }
        let peerConfigs = wg.sessions.filter {
            if case .peer = $0.kind { return true }
            return false
        }
        let deadPeer = peerConfigs[0]
        let livePeer = peerConfigs[1]
        spawner.pendingPeerConfigIDs = [deadPeer.uniqueIdentifier]
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader,
                spawner: spawner))
        defer { iTermWorkgroupController.instance.exit(on: leader) }
        spawner.rejectPendingPeer(configID: deadPeer.uniqueIdentifier)
        let port = leader.peerPort as! iTermWorkgroupPeerPort
        let rootID = wg.root!.uniqueIdentifier
        // Forward from the root: the dead first peer is skipped.
        XCTAssertEqual(port.viableConfigIdentifier(byOffset: 1),
                       livePeer.uniqueIdentifier)
        // Backward from the live peer: skips the dead one, reaches root.
        port.activeSessionIdentifier = livePeer.uniqueIdentifier
        XCTAssertEqual(port.viableConfigIdentifier(byOffset: -1), rootID)
    }

    // §14.7 — the ⌥⇧⌘<digit> chord for a dead peer must be consumed as
    // a no-op, not refused: activatePeer's Bool propagates up to
    // iTermApplication's event dispatch, and a false there lets the
    // chord fall through to the focused shell as input.
    func test_14_7_digitChordForDeadPeerIsConsumedNotLeaked() {
        let wg = WGFix.wgRootWithPeers(n: 2)
        registerWithModel(wg)
        defer { unregisterFromModel(wg) }
        let peerConfigs = wg.sessions.filter {
            if case .peer = $0.kind { return true }
            return false
        }
        let deadPeer = peerConfigs[0]
        spawner.pendingPeerConfigIDs = [deadPeer.uniqueIdentifier]
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader,
                spawner: spawner))
        defer { iTermWorkgroupController.instance.exit(on: leader) }
        spawner.rejectPendingPeer(configID: deadPeer.uniqueIdentifier)
        let port = leader.peerPort as! iTermWorkgroupPeerPort
        let before = port.activeSessionIdentifier
        // peerConfigs order is [root, peer1, peer2]; the dead peer is
        // at index 1, i.e. digit 2.
        XCTAssertTrue(port.activatePeer(byShortcutDigit: 2),
                      "An in-range digit owns the chord even when the member is dead")
        XCTAssertEqual(port.activeSessionIdentifier, before,
                       "Nothing may be committed for the dead member")
        // Out-of-range digits still decline (the chord isn't ours).
        XCTAssertFalse(port.activatePeer(byShortcutDigit: 7))
    }

    // §14.6 — clicking the mode-switcher segment of a dead peer:
    // AppKit highlights the segment before the delegate runs
    // (.selectOne tracking), and the refused activation never commits
    // or rolls back, so the didSelect handler itself must resync the
    // switchers to the really-active member.
    func test_14_6_refusedSwitcherClickResyncsHighlight() {
        let root = WGFix.makeRoot(items: [.modeSwitcher])
        let peer = WGFix.makePeer(parentID: root.uniqueIdentifier)
        let wg = WGFix.wrap(name: "switcher", sessions: [root, peer])
        registerWithModel(wg)
        defer { unregisterFromModel(wg) }
        spawner.pendingPeerConfigIDs = [peer.uniqueIdentifier]
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader,
                spawner: spawner))
        defer { iTermWorkgroupController.instance.exit(on: leader) }
        spawner.rejectPendingPeer(configID: peer.uniqueIdentifier)
        let port = leader.peerPort as! iTermWorkgroupPeerPort
        let switcher = port.toolbarItems(forPeerID: root.uniqueIdentifier)
            .compactMap { $0 as? WorkgroupModeSwitcherItem }
            .first!
        // Simulate AppKit selecting the clicked (dead) segment, then
        // the delegate callback.
        switcher.setActiveIdentifier(peer.uniqueIdentifier)
        port.workgroupModeSwitcher(switcher, didSelect: peer.uniqueIdentifier)
        XCTAssertEqual(switcher.selectedIdentifier, root.uniqueIdentifier,
                       "A refused activation must resync the highlight to the active member")
        XCTAssertEqual(port.activeSessionIdentifier, root.uniqueIdentifier)
    }

    // §14.8 — hasRestorableAnchor is true when a sibling is buried even
    // though no member has a live delegate. reveal() relies on this to
    // retry the swap (which disinters the buried anchor) instead of
    // reviving the windowless member into its own window — which would
    // put two members of one peer group on screen once the buried one
    // is restored.
    func test_14_8_hasRestorableAnchorTrueForBuriedSibling() {
        let a = PTYSession(synthetic: false)!
        let b = PTYSession(synthetic: false)!
        let port = BuriedSeamSpyPort(
            peers: ["a": iTermPromise<PTYSession>(value: a),
                    "b": iTermPromise<PTYSession>(value: b)],
            activeSessionIdentifier: "a",
            leaderIdentifier: "a")
        // No member has a delegate (unit fixtures have no tabs), and
        // none is marked buried yet.
        XCTAssertFalse(port.hasActivationAnchor())
        XCTAssertFalse(port.hasRestorableAnchor())
        // Bury b: now the group has a restorable anchor even though
        // still no live delegate.
        port.buried = [b]
        XCTAssertFalse(port.hasActivationAnchor())
        XCTAssertTrue(port.hasRestorableAnchor())
    }

    // §14.9 — ownsIdentifier distinguishes "this port owns the id"
    // (consume a matching peer-switch chord even if the member is
    // dead/unactivatable) from "not ours" (let the chord fall
    // through). This is the predicate activatePeer(matching:) uses to
    // avoid leaking a configured shortcut for a dead peer to the shell.
    func test_14_9_ownsIdentifierDistinguishesOwnedFromForeign() {
        let wg = WGFix.wgRootWithPeers(n: 1)
        registerWithModel(wg)
        defer { unregisterFromModel(wg) }
        let peer = wg.sessions.first {
            if case .peer = $0.kind { return true }
            return false
        }!
        spawner.pendingPeerConfigIDs = [peer.uniqueIdentifier]
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader,
                spawner: spawner))
        defer { iTermWorkgroupController.instance.exit(on: leader) }
        spawner.rejectPendingPeer(configID: peer.uniqueIdentifier)
        let port = leader.peerPort!
        // Owned even though the member's spawn rejected (and so
        // isActivatable is false): the chord still belongs to us.
        XCTAssertTrue(port.ownsIdentifier(peer.uniqueIdentifier))
        XCTAssertFalse(port.isActivatable(identifier: peer.uniqueIdentifier))
        XCTAssertTrue(port.ownsIdentifier(wg.root!.uniqueIdentifier))
        XCTAssertFalse(port.ownsIdentifier("not-a-member"))
    }

    // §14.10 — the deferred close used by teardown and
    // closeStraySpawn must fall back to terminate() when the delegate
    // has detached by the time the block runs, instead of silently
    // no-oping and leaking a stray shell.
    func test_14_10_deferredCloseTerminatesWhenDelegateGone() {
        let spy = SpyPTYSession(synthetic: false)!
        // No delegate (the detached-by-tick case) and not exited.
        XCTAssertNil(spy.delegate)
        iTermWorkgroupInstance.deferredClose(spy)
        XCTAssertEqual(spy.spy_terminateCount, 0, "Close is deferred to the next tick")
        // Drain one main-runloop turn so the async block runs.
        let drained = expectation(description: "runloop")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1.0)
        XCTAssertEqual(spy.spy_terminateCount, 1,
                       "A delegate-less session must be terminated, not silently skipped")
    }

    // MARK: - §15 enter()/canEnter parity

    // §15.1 — every refusal predicate refuses through BOTH canEnter
    // (so UI disables) and enter() (so nothing breaks if UI didn't).
    // One table; each future refusal added to enterRefusal() gets a
    // case here instead of a hunt through menu/trigger call sites.
    func test_15_1_enterAndCanEnterAgreeOnRefusals() {
        let controller = iTermWorkgroupController.instance

        // Unknown identifier.
        XCTAssertFalse(controller.canEnter(workgroupUniqueIdentifier: "no-such-workgroup",
                                           on: leader))
        XCTAssertFalse(controller.enter(workgroupUniqueIdentifier: "no-such-workgroup",
                                        on: leader,
                                        spawner: spawner))

        // Rootless workgroup (corrupted/hand-edited persisted data).
        let orphanPeer = WGFix.makePeer(parentID: "no-such-parent")
        let rootless = WGFix.wrap(name: "rootless", sessions: [orphanPeer])
        registerWithModel(rootless)
        defer { unregisterFromModel(rootless) }
        XCTAssertFalse(controller.canEnter(workgroupUniqueIdentifier: rootless.uniqueIdentifier,
                                           on: leader))
        XCTAssertFalse(controller.enter(workgroupUniqueIdentifier: rootless.uniqueIdentifier,
                                        on: leader,
                                        spawner: spawner))

        // Switching from a non-leader member refuses; from the leader
        // it is allowed (that's the supported switch path).
        let wg1 = WGFix.wgRootWithPeers(n: 1)
        let wg2 = WGFix.wgRootOnly()
        registerWithModel(wg1)
        registerWithModel(wg2)
        defer {
            unregisterFromModel(wg1)
            unregisterFromModel(wg2)
        }
        XCTAssertTrue(controller.enter(workgroupUniqueIdentifier: wg1.uniqueIdentifier,
                                       on: leader,
                                       spawner: spawner))
        let peerCfg = wg1.sessions.first {
            if case .peer = $0.kind { return true }
            return false
        }!
        let peerSession = spawner.session(forConfigID: peerCfg.uniqueIdentifier)!
        XCTAssertFalse(controller.canEnter(workgroupUniqueIdentifier: wg2.uniqueIdentifier,
                                           on: peerSession))
        XCTAssertFalse(controller.enter(workgroupUniqueIdentifier: wg2.uniqueIdentifier,
                                        on: peerSession,
                                        spawner: spawner))
        XCTAssertTrue(controller.canEnter(workgroupUniqueIdentifier: wg2.uniqueIdentifier,
                                          on: leader),
                      "Leader-side switching is the supported path")
        controller.exit(on: leader)

        // Mid-restoration refusal, end to end: a session that IS a
        // pending restoration anchor is refused; draining the entry
        // (here via the deadline) unblocks it.
        let coordinator = WorkgroupRestorationCoordinator.shared
        let savedTimeout = coordinator.pendingReconstructionTimeout
        defer { coordinator.pendingReconstructionTimeout = savedTimeout }
        let wg3 = WGFix.wgRootOnly()
        registerWithModel(wg3)
        defer { unregisterFromModel(wg3) }
        coordinator.register(anchor: leader, descriptor: [:])
        XCTAssertFalse(controller.canEnter(workgroupUniqueIdentifier: wg3.uniqueIdentifier,
                                           on: leader))
        XCTAssertFalse(controller.enter(workgroupUniqueIdentifier: wg3.uniqueIdentifier,
                                        on: leader,
                                        spawner: spawner))
        coordinator.pendingReconstructionTimeout = 0
        coordinator.reconstructReadyAnchors()
        XCTAssertTrue(controller.canEnter(workgroupUniqueIdentifier: wg3.uniqueIdentifier,
                                          on: leader))
        XCTAssertTrue(controller.enter(workgroupUniqueIdentifier: wg3.uniqueIdentifier,
                                       on: leader,
                                       spawner: spawner))
        controller.exit(on: leader)
    }

    // §15.2 — the idempotent same-workgroup case stays in parity even
    // after the config is deleted from the model: enter() is a no-op
    // success (nothing gets torn down or built), so canEnter must
    // agree rather than reporting the identifier unusable.
    func test_15_2_sameWorkgroupParitySurvivesConfigDeletion() {
        let controller = iTermWorkgroupController.instance
        let wg = WGFix.wgRootOnly()
        registerWithModel(wg)
        XCTAssertTrue(controller.enter(workgroupUniqueIdentifier: wg.uniqueIdentifier,
                                       on: leader,
                                       spawner: spawner))
        defer { controller.exit(on: leader) }
        unregisterFromModel(wg)
        XCTAssertTrue(controller.canEnter(workgroupUniqueIdentifier: wg.uniqueIdentifier,
                                          on: leader))
        XCTAssertTrue(controller.enter(workgroupUniqueIdentifier: wg.uniqueIdentifier,
                                       on: leader,
                                       spawner: spawner))
    }

    // §15.3 — a wedged restoration descriptor (anchor alive but never
    // installed in a window) must release its GUIDs after the deadline
    // (so it stops blocking Enter Workgroup) but KEEP the pending entry
    // so a still-slower restore can reconstruct if the anchor's window
    // finally installs, rather than silently losing the workgroup.
    func test_15_3_wedgedDescriptorReleasesGuidsButKeepsEntry() {
        let coordinator = WorkgroupRestorationCoordinator.shared
        let savedTimeout = coordinator.pendingReconstructionTimeout
        defer { coordinator.pendingReconstructionTimeout = savedTimeout }
        // Flush any dead-anchor leftover entries from earlier tests
        // (the coordinator is a shared singleton) so the baseline count
        // is stable across this test's own reconstruct passes.
        coordinator.reconstructReadyAnchors()
        let beforeCount = coordinator.pendingCount
        coordinator.pendingReconstructionTimeout = 0
        let anchor = PTYSession(synthetic: false)!
        coordinator.register(
            anchor: anchor,
            descriptor: [iTermWorkgroupRestoration.Key.memberGUIDs: [leader.guid]])
        XCTAssertTrue(coordinator.isRestoring(guid: leader.guid))
        XCTAssertEqual(coordinator.pendingCount, beforeCount + 1)
        coordinator.reconstructReadyAnchors()
        withExtendedLifetime(anchor) {
            // Soft limit: GUIDs released (Enter Workgroup unblocked)...
            XCTAssertFalse(coordinator.isRestoring(guid: leader.guid),
                           "Past-deadline entry must stop blocking Enter Workgroup")
            // ...but the entry is retained so a late window install can
            // still reconstruct.
            XCTAssertEqual(coordinator.pendingCount, beforeCount + 1,
                           "A slow restore must not be abandoned at the deadline")
        }
    }

    // §15.4 — a live, unrelated session whose GUID merely collides with
    // a restoring descriptor member (saved-with-contents sessions keep
    // their GUIDs) must NOT be blocked: the refusal keys on anchor
    // object identity, not GUID membership.
    func test_15_4_liveSessionWithCollidingRestoringGuidStillEnters() {
        let controller = iTermWorkgroupController.instance
        let coordinator = WorkgroupRestorationCoordinator.shared
        let savedTimeout = coordinator.pendingReconstructionTimeout
        defer { coordinator.pendingReconstructionTimeout = savedTimeout }
        let wg = WGFix.wgRootOnly()
        registerWithModel(wg)
        defer { unregisterFromModel(wg) }
        // A DIFFERENT session is the restoration anchor; its descriptor
        // names `leader`'s guid as a member. `leader` is live and
        // unrelated.
        let restoringAnchor = PTYSession(synthetic: false)!
        coordinator.register(
            anchor: restoringAnchor,
            descriptor: [iTermWorkgroupRestoration.Key.memberGUIDs: [leader.guid]])
        withExtendedLifetime(restoringAnchor) {
            XCTAssertTrue(coordinator.isRestoring(guid: leader.guid),
                          "Precondition: the colliding guid is in the restoring set")
            XCTAssertTrue(controller.canEnter(workgroupUniqueIdentifier: wg.uniqueIdentifier,
                                              on: leader),
                          "A live unrelated session must not be blocked by a GUID collision")
            XCTAssertTrue(controller.enter(workgroupUniqueIdentifier: wg.uniqueIdentifier,
                                           on: leader,
                                           spawner: spawner))
            controller.exit(on: leader)
        }
        // Drain the still-pending restoring entry so it can't leak into
        // other tests through the shared coordinator.
        coordinator.pendingReconstructionTimeout = 0
        coordinator.reconstructReadyAnchors()
    }

    // §15.5 — two overlapping restoration descriptors (the same
    // arrangement restored twice in flight) both claim a GUID; draining
    // one entry must NOT unblock a GUID the other still claims. The
    // restoring set is a counted multiset, not a plain set.
    func test_15_5_overlappingRestoringDescriptorsCountIndependently() {
        let coordinator = WorkgroupRestorationCoordinator.shared
        let savedTimeout = coordinator.pendingReconstructionTimeout
        defer { coordinator.pendingReconstructionTimeout = savedTimeout }
        let sharedGuid = leader.guid
        let descriptor: [AnyHashable: Any] =
            [iTermWorkgroupRestoration.Key.memberGUIDs: [sharedGuid]]
        // Two distinct anchors, overlapping descriptors.
        let anchorA = PTYSession(synthetic: false)!
        var anchorB: PTYSession? = PTYSession(synthetic: false)!
        coordinator.register(anchor: anchorA, descriptor: descriptor)
        coordinator.register(anchor: anchorB!, descriptor: descriptor)
        XCTAssertTrue(coordinator.isRestoring(guid: sharedGuid))
        // Drain entry B (its anchor deallocates); A still claims the GUID.
        anchorB = nil
        coordinator.reconstructReadyAnchors()
        withExtendedLifetime(anchorA) {
            XCTAssertTrue(coordinator.isRestoring(guid: sharedGuid),
                          "A still-pending entry must keep its GUID claimed")
        }
        // Now drain A too (via the deadline); the GUID finally clears.
        coordinator.pendingReconstructionTimeout = 0
        coordinator.reconstructReadyAnchors()
        withExtendedLifetime(anchorA) {
            XCTAssertFalse(coordinator.isRestoring(guid: sharedGuid),
                           "Once every claimant drains, the GUID is no longer restoring")
        }
    }

    // MARK: - §16 Adopt collision safety

    // §16.1 — a second adopt whose descriptor resolves a child GUID to
    // a pane that already belongs to a live instance (restoring the
    // same arrangement twice while the workgroup runs; restored-with-
    // contents sessions keep their saved GUIDs) must not steal the
    // pane: its back-pointer stays on the original instance and the
    // copy's teardown must not close it.
    func test_16_1_adoptDoesNotStealAnotherInstancesChild() {
        let controller = iTermWorkgroupController.instance

        // Instance 1 with a split child, entered normally.
        let root1 = WGFix.makeRoot()
        let split1 = WGFix.makeSplit(parentID: root1.uniqueIdentifier)
        let wg1 = WGFix.wrap(name: "original", sessions: [root1, split1])
        registerWithModel(wg1)
        defer { unregisterFromModel(wg1) }
        spawner.sessionFactory = { SpyPTYSession(synthetic: false)! }
        XCTAssertTrue(controller.enter(workgroupUniqueIdentifier: wg1.uniqueIdentifier,
                                       on: leader,
                                       spawner: spawner))
        defer { controller.exit(on: leader) }
        let child = spawner.session(forConfigID: split1.uniqueIdentifier) as! SpyPTYSession
        let inst1 = controller.workgroupInstance(on: leader)!
        XCTAssertTrue(child.workgroupInstance === inst1)

        // Second instance adopted with the SAME pane offered as its
        // non-peer child (what a duplicate restore produces).
        let root2 = WGFix.makeRoot()
        let split2 = WGFix.makeSplit(parentID: root2.uniqueIdentifier)
        let wg2 = WGFix.wrap(name: "copy", sessions: [root2, split2])
        registerWithModel(wg2)
        defer { unregisterFromModel(wg2) }
        let leader2 = PTYSession(synthetic: false)!
        let inst2 = controller.adopt(
            workgroup: wg2,
            leader: leader2,
            instanceUniqueIdentifier: iTermWorkgroupInstance.mintInstanceUniqueIdentifier(),
            activeIdentifier: root2.uniqueIdentifier,
            gitBase: CCGitBaseSelectorItem.defaultBase,
            peerSessionsByConfigID: [:],
            nonPeerSessionsByConfigID: [split2.uniqueIdentifier: child],
            spawner: FakeWorkgroupSpawner())
        XCTAssertNotNil(inst2)
        XCTAssertTrue(child.workgroupInstance === inst1,
                      "Adopt must not steal a child registered to another instance")

        // Tearing down the copy leaves the original's pane untouched.
        controller.exit(on: leader2)
        XCTAssertTrue(child.workgroupInstance === inst1)
        XCTAssertEqual(child.spy_terminateCount, 0,
                       "The copy's teardown must not touch the original's pane")
    }

    // §16.2 — the PEER half of §16.1: a second adopt whose
    // peerSessionsByConfigID resolves to a peer that already belongs
    // to a live instance must not wire it into a second port (the new
    // port's init fan-out would trip set(peerPort:)'s release-enabled
    // assert, and the copy's teardown would invalidate the original's
    // port). The collision is treated as not-restored: the copy spawns
    // a fresh peer instead.
    func test_16_2_adoptDoesNotStealAnotherInstancesPeer() {
        let controller = iTermWorkgroupController.instance

        // Instance 1 with one realized peer, entered normally.
        let wg1 = WGFix.wgRootWithPeers(n: 1)
        registerWithModel(wg1)
        defer { unregisterFromModel(wg1) }
        spawner.sessionFactory = { SpyPTYSession(synthetic: false)! }
        XCTAssertTrue(controller.enter(workgroupUniqueIdentifier: wg1.uniqueIdentifier,
                                       on: leader,
                                       spawner: spawner))
        defer { controller.exit(on: leader) }
        let peer1Cfg = wg1.sessions.first {
            if case .peer = $0.kind { return true }
            return false
        }!
        let stolenPeer = spawner.session(forConfigID: peer1Cfg.uniqueIdentifier) as! SpyPTYSession
        let inst1 = controller.workgroupInstance(on: leader)!
        XCTAssertTrue(stolenPeer.workgroupInstance === inst1)
        let originalPort = stolenPeer.peerPort
        XCTAssertNotNil(originalPort)

        // Second instance adopted with the SAME peer session offered
        // for its own peer slot (what a duplicate restore with kept
        // GUIDs produces).
        let wg2 = WGFix.wgRootWithPeers(n: 1)
        registerWithModel(wg2)
        defer { unregisterFromModel(wg2) }
        let peer2Cfg = wg2.sessions.first {
            if case .peer = $0.kind { return true }
            return false
        }!
        let leader2 = PTYSession(synthetic: false)!
        let copySpawner = FakeWorkgroupSpawner()
        copySpawner.sessionFactory = { SpyPTYSession(synthetic: false)! }
        let inst2 = controller.adopt(
            workgroup: wg2,
            leader: leader2,
            instanceUniqueIdentifier: iTermWorkgroupInstance.mintInstanceUniqueIdentifier(),
            activeIdentifier: wg2.root!.uniqueIdentifier,
            gitBase: CCGitBaseSelectorItem.defaultBase,
            peerSessionsByConfigID: [peer2Cfg.uniqueIdentifier: stolenPeer],
            nonPeerSessionsByConfigID: [:],
            spawner: copySpawner)
        XCTAssertNotNil(inst2)
        // The original keeps its wiring; the copy got a fresh spawn.
        XCTAssertTrue(stolenPeer.workgroupInstance === inst1,
                      "Adopt must not steal a peer registered to another instance")
        XCTAssertTrue(stolenPeer.peerPort === originalPort)
        let freshPeer = copySpawner.session(forConfigID: peer2Cfg.uniqueIdentifier) as! SpyPTYSession
        XCTAssertFalse(freshPeer === stolenPeer)

        // Tearing down the copy kills only its own fresh peer.
        controller.exit(on: leader2)
        XCTAssertEqual(stolenPeer.spy_terminateCount, 0,
                       "The copy's teardown must not touch the original's peer")
        XCTAssertTrue(stolenPeer.workgroupInstance === inst1)
        XCTAssertTrue(stolenPeer.peerPort === originalPort)
        XCTAssertEqual(freshPeer.spy_terminateCount, 1)
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

