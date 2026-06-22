//
//  WorkgroupTestFixtures.swift
//  ModernTests
//
//  Created by George Nachman on 4/25/26.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Fake spawner

// Replaces DefaultWorkgroupSessionSpawner during tests. Returns a
// freshly-constructed PTYSession for every spawned slot and tracks
// the mapping from config UUID → live session, so tests can resolve
// any config node to its runtime session without going through the
// real iTermSessionFactory / PseudoTerminal machinery.
// Non-final so sabotage subclasses (e.g. TerminateDuringSpawnSpawner)
// can inject failures at precise points in the spawn sequence.
class FakeWorkgroupSpawner: WorkgroupSessionSpawner {
    enum SpawnKind { case peer, split, tab }

    struct SpawnRecord {
        let kind: SpawnKind
        weak var parent: PTYSession?
        let config: iTermWorkgroupSessionConfig
        weak var session: PTYSession?
    }

    private(set) var sessionsByConfigID: [String: PTYSession] = [:]
    private(set) var records: [SpawnRecord] = []

    // workgroupInstanceID forwarded to each spawn call. Tests can read
    // this to assert that the same per-entry UUID is propagated to
    // every spawn (peers, splits, tabs, nested peers).
    private(set) var workgroupInstanceIDsByConfigID: [String: String] = [:]

    // Tests that need a spy/subclass instead of the default
    // PTYSession can replace this. Defaults to a plain non-synthetic
    // PTYSession.
    var sessionFactory: () -> PTYSession = {
        return PTYSession(synthetic: false)!
    }

    // Tests sometimes want to know spawn order to assert it matches
    // some expected pre-order of the config tree.
    var spawnOrder: [String] {
        return records.map { $0.config.uniqueIdentifier }
    }

    func session(forConfigID id: String) -> PTYSession? {
        return sessionsByConfigID[id]
    }

    // Config IDs whose spawnPeer returns an UNFULFILLED promise instead
    // of an immediately-realized session. Tests fulfill them later via
    // fulfillPendingPeer to exercise the late-fulfillment paths (the
    // didTeardown guard in attachBackPointers, the invalidated guard in
    // PTYSessionPeerPort's init fan-out, activation rollback). The real
    // spawner is asynchronous in exactly this way: makeWorkgroupPeer
    // resolves the parent's PWD before fulfilling.
    var pendingPeerConfigIDs: Set<String> = []
    private var pendingSeals: [String: iTermPromiseSeal] = [:]

    func fulfillPendingPeer(configID: String, with session: PTYSession) {
        guard let seal = pendingSeals.removeValue(forKey: configID) else {
            return
        }
        sessionsByConfigID[configID] = session
        seal.fulfill(session)
    }

    // Fails a pending peer's spawn the way the real spawner does when
    // the parent dies mid-spawn or its profile/view is missing.
    func rejectPendingPeer(configID: String) {
        pendingSeals.removeValue(forKey: configID)?
            .reject(NSError(domain: "WorkgroupTestFixtures", code: 1))
    }

    func spawnPeer(parent: PTYSession,
                   config: iTermWorkgroupSessionConfig,
                   workgroupInstanceID: String) -> iTermPromise<PTYSession> {
        workgroupInstanceIDsByConfigID[config.uniqueIdentifier] = workgroupInstanceID
        if pendingPeerConfigIDs.contains(config.uniqueIdentifier) {
            records.append(SpawnRecord(kind: .peer, parent: parent, config: config, session: nil))
            return iTermPromise<PTYSession> { seal in
                pendingSeals[config.uniqueIdentifier] = seal
            }
        }
        let session = makeSession()
        sessionsByConfigID[config.uniqueIdentifier] = session
        records.append(SpawnRecord(kind: .peer, parent: parent, config: config, session: session))
        return iTermPromise<PTYSession>(value: session)
    }

    func spawnSplit(parent: PTYSession,
                    config: iTermWorkgroupSessionConfig,
                    settings: SplitSettings,
                    workgroupInstanceID: String) -> PTYSession? {
        let session = makeSession()
        sessionsByConfigID[config.uniqueIdentifier] = session
        workgroupInstanceIDsByConfigID[config.uniqueIdentifier] = workgroupInstanceID
        records.append(SpawnRecord(kind: .split, parent: parent, config: config, session: session))
        return session
    }

    func spawnTab(parent: PTYSession,
                  config: iTermWorkgroupSessionConfig,
                  workgroupInstanceID: String) -> PTYSession? {
        let session = makeSession()
        sessionsByConfigID[config.uniqueIdentifier] = session
        workgroupInstanceIDsByConfigID[config.uniqueIdentifier] = workgroupInstanceID
        records.append(SpawnRecord(kind: .tab, parent: parent, config: config, session: session))
        return session
    }

    private func makeSession() -> PTYSession {
        // synthetic:false so the session behaves like a normal
        // workgroup peer/child as far as workgroupInstance/peerPort
        // wiring goes. We never start its shell; the spawner doesn't
        // call launch, and tests don't drive session.terminate().
        return sessionFactory()
    }
}

// MARK: - TerminateDuringSpawnSpawner

// Posts iTermSessionWillTerminate for a chosen session synchronously
// inside the first spawnSplit, simulating a member dying while the
// entry spawn loop is still running. iTermWorkgroupInstance's
// observer is live at that point (registered in its init, which runs
// before spawnNonPeerChildren), so this deterministically drives the
// mid-spawn teardown reentrancy paths: enter() must not register the
// torn-down instance, and children must not be pointed at the corpse.
final class TerminateDuringSpawnSpawner: FakeWorkgroupSpawner {
    var terminateTarget: (() -> PTYSession?)?

    override func spawnSplit(parent: PTYSession,
                             config: iTermWorkgroupSessionConfig,
                             settings: SplitSettings,
                             workgroupInstanceID: String) -> PTYSession? {
        if let provider = terminateTarget, let target = provider() {
            terminateTarget = nil
            NotificationCenter.default.post(
                name: NSNotification.Name.iTermSessionWillTerminate,
                object: target)
        }
        return super.spawnSplit(parent: parent,
                                config: config,
                                settings: settings,
                                workgroupInstanceID: workgroupInstanceID)
    }
}

// MARK: - TerminateDuringPeerSpawnSpawner

// Like TerminateDuringSpawnSpawner, but the sabotage fires inside
// spawnPeer instead of spawnSplit — the window where a nested peer
// group's peers are being spawned for a host that is already installed
// in the window. Drives the registerNestedPeerPort teardown backstop:
// the host must be closed as a stray and the port invalidated, not
// appended to the dead instance.
final class TerminateDuringPeerSpawnSpawner: FakeWorkgroupSpawner {
    var terminateTarget: (() -> PTYSession?)?

    override func spawnPeer(parent: PTYSession,
                            config: iTermWorkgroupSessionConfig,
                            workgroupInstanceID: String) -> iTermPromise<PTYSession> {
        if let provider = terminateTarget, let target = provider() {
            terminateTarget = nil
            NotificationCenter.default.post(
                name: NSNotification.Name.iTermSessionWillTerminate,
                object: target)
        }
        return super.spawnPeer(parent: parent,
                               config: config,
                               workgroupInstanceID: workgroupInstanceID)
    }
}

// MARK: - RollbackSpyPort

// Lets activation-rollback tests drive PTYSessionPeerPort.activate's
// commit path without a real tab: hasActivationAnchor is the seam the
// production class exposes because PTYSessionDelegate cannot be
// stubbed (about a hundred required methods). Records every
// activationDidRollBack so tests can assert the subclass hook (the
// mode-switcher resync contract) fired.
final class RollbackSpyPort: PTYSessionPeerPort {
    var rolledBackTo: [String] = []

    override func hasActivationAnchor() -> Bool {
        return true
    }

    override func activationDidRollBack(to identifier: String) {
        rolledBackTo.append(identifier)
    }
}

// Drives PTYSessionPeerPort.hasRestorableAnchor without the
// iTermBuriedSessions singleton: isBuried is the production seam, so a
// test marks whichever members it wants treated as buried.
final class BuriedSeamSpyPort: PTYSessionPeerPort {
    var buried: [PTYSession] = []

    override func isBuried(_ session: PTYSession) -> Bool {
        return buried.contains { $0 === session }
    }
}

// MARK: - FanoutSpyDelegate

// Records which toolbar views fired itemDidChange. Used by §8.4
// fanout coverage to assert every diff selector and git-status view
// in the workgroup gets driven by gitPollerDidUpdate, not just the
// ones in the main peer port.
final class FanoutSpyDelegate: NSObject, SessionToolbarItemDelegate {
    var firedFor: Set<ObjectIdentifier> = []

    func itemDidChange(sender: SessionToolbarGenericView) {
        firedFor.insert(ObjectIdentifier(sender))
    }
}

// MARK: - SpyPTYSession

// Drop-in PTYSession subclass that records terminate() calls and
// can have its `exited` flag flipped on demand. Used by teardown
// tests to assert that the workgroup teardown loop skips already-
// terminated entries (it would otherwise post a redundant
// iTermSessionWillTerminate notification mid-teardown).
class SpyPTYSession: PTYSession {
    var spy_terminateCount: Int = 0
    var spy_overrideExited: Bool = false

    override var exited: Bool {
        if spy_overrideExited { return true }
        return super.exited
    }

    override func terminate() {
        spy_terminateCount += 1
        // Don't call super: real PTYSession.terminate posts the
        // willTerminate notification and tears down screen state,
        // which would re-enter the workgroup observer and crowd the
        // signal we're trying to measure.
    }
}

// MARK: - Config builders

// Builders for the tree shapes called out in the workgroup-entry
// test spec (§Fixtures). Each builder returns a self-consistent
// iTermWorkgroup with exactly one .root node and parent-IDs wired
// up correctly. UUIDs are randomized per build so tests can run in
// parallel.
enum WGFix {
    // Default split settings: vertical, new pane on the trailing side
    // at 50/50. Tests that care about geometry override this.
    static let defaultSplit = SplitSettings(orientation: .vertical,
                                            side: .trailingOrBottom,
                                            location: 0.5)

    static func newID() -> String { UUID().uuidString }

    static func makeRoot(items: [iTermWorkgroupToolbarItem] = [],
                         displayName: String = "Main") -> iTermWorkgroupSessionConfig {
        return iTermWorkgroupSessionConfig(
            uniqueIdentifier: newID(),
            parentID: nil,
            kind: .root,
            profileGUID: nil,
            command: "",
            urlString: "",
            toolbarItems: items,
            displayName: displayName)
    }

    static func makePeer(parentID: String,
                         items: [iTermWorkgroupToolbarItem] = [],
                         displayName: String = "Peer",
                         perFileCommand: String = "",
                         command: String = "",
                         mode: iTermWorkgroupSessionMode = .regular) -> iTermWorkgroupSessionConfig {
        return iTermWorkgroupSessionConfig(
            uniqueIdentifier: newID(),
            parentID: parentID,
            kind: .peer,
            profileGUID: nil,
            command: command,
            urlString: "",
            toolbarItems: items,
            displayName: displayName,
            perFileCommand: perFileCommand,
            mode: mode)
    }

    static func makeSplit(parentID: String,
                          settings: SplitSettings = defaultSplit,
                          items: [iTermWorkgroupToolbarItem] = [],
                          displayName: String = "Split") -> iTermWorkgroupSessionConfig {
        return iTermWorkgroupSessionConfig(
            uniqueIdentifier: newID(),
            parentID: parentID,
            kind: .split(settings),
            profileGUID: nil,
            command: "",
            urlString: "",
            toolbarItems: items,
            displayName: displayName)
    }

    static func makeTab(parentID: String,
                        items: [iTermWorkgroupToolbarItem] = [],
                        displayName: String = "Tab") -> iTermWorkgroupSessionConfig {
        return iTermWorkgroupSessionConfig(
            uniqueIdentifier: newID(),
            parentID: parentID,
            kind: .tab,
            profileGUID: nil,
            command: "",
            urlString: "",
            toolbarItems: items,
            displayName: displayName)
    }

    static func wrap(name: String,
                     sessions: [iTermWorkgroupSessionConfig]) -> iTermWorkgroup {
        return iTermWorkgroup(uniqueIdentifier: newID(),
                              name: name,
                              sessions: sessions)
    }

    // wgRootOnly — nothing but a root.
    static func wgRootOnly(items: [iTermWorkgroupToolbarItem] = []) -> iTermWorkgroup {
        let root = makeRoot(items: items)
        return wrap(name: "wgRootOnly", sessions: [root])
    }

    // wgRootWithPeers(n) — root + n peer children.
    static func wgRootWithPeers(n: Int,
                                rootItems: [iTermWorkgroupToolbarItem] = [],
                                peerItems: [iTermWorkgroupToolbarItem] = []) -> iTermWorkgroup {
        let root = makeRoot(items: rootItems)
        var sessions = [root]
        for i in 0..<n {
            sessions.append(makePeer(parentID: root.uniqueIdentifier,
                                     items: peerItems,
                                     displayName: "Peer\(i)"))
        }
        return wrap(name: "wgRootWithPeers", sessions: sessions)
    }

    // wgRootWithSplits(n) — root + n split children (no peers).
    static func wgRootWithSplits(n: Int,
                                 rootItems: [iTermWorkgroupToolbarItem] = [],
                                 splitItems: [iTermWorkgroupToolbarItem] = []) -> iTermWorkgroup {
        let root = makeRoot(items: rootItems)
        var sessions = [root]
        for i in 0..<n {
            sessions.append(makeSplit(parentID: root.uniqueIdentifier,
                                      items: splitItems,
                                      displayName: "Split\(i)"))
        }
        return wrap(name: "wgRootWithSplits", sessions: sessions)
    }

    // wgRootWithTab — root + 1 tab child.
    static func wgRootWithTab(rootItems: [iTermWorkgroupToolbarItem] = [],
                              tabItems: [iTermWorkgroupToolbarItem] = []) -> iTermWorkgroup {
        let root = makeRoot(items: rootItems)
        let tab = makeTab(parentID: root.uniqueIdentifier, items: tabItems)
        return wrap(name: "wgRootWithTab", sessions: [root, tab])
    }

    // wgRootSplitWithPeers — root + 1 split that itself hosts peers.
    // This is the §1.3 regression shape.
    static func wgRootSplitWithPeers(splitItems: [iTermWorkgroupToolbarItem] = [.modeSwitcher, .reload(nil)],
                                     peerCount: Int = 1) -> iTermWorkgroup {
        let root = makeRoot()
        let split = makeSplit(parentID: root.uniqueIdentifier,
                              items: splitItems,
                              displayName: "SplitHost")
        var sessions = [root, split]
        for i in 0..<peerCount {
            sessions.append(makePeer(parentID: split.uniqueIdentifier,
                                     items: splitItems,
                                     displayName: "SplitPeer\(i)"))
        }
        return wrap(name: "wgRootSplitWithPeers", sessions: sessions)
    }

    // wgRootPeersAndSplits — root has peer children AND split children.
    static func wgRootPeersAndSplits(peerCount: Int = 2,
                                     splitCount: Int = 2) -> iTermWorkgroup {
        let root = makeRoot(items: [.modeSwitcher, .gitStatus])
        var sessions = [root]
        for i in 0..<peerCount {
            sessions.append(makePeer(parentID: root.uniqueIdentifier,
                                     items: [.modeSwitcher, .reload(nil)],
                                     displayName: "P\(i)"))
        }
        for i in 0..<splitCount {
            sessions.append(makeSplit(parentID: root.uniqueIdentifier,
                                      items: [.reload(nil), .changedFileSelector],
                                      displayName: "S\(i)"))
        }
        return wrap(name: "wgRootPeersAndSplits", sessions: sessions)
    }

    // wgDeepNesting — split-of-split-of-split-of-split + a tab child of
    // a deep split, exercising recursive descent.
    static func wgDeepNesting() -> iTermWorkgroup {
        let root = makeRoot()
        let split1 = makeSplit(parentID: root.uniqueIdentifier, displayName: "L1")
        let split2 = makeSplit(parentID: split1.uniqueIdentifier, displayName: "L2")
        let split3 = makeSplit(parentID: split2.uniqueIdentifier, displayName: "L3")
        let split4 = makeSplit(parentID: split3.uniqueIdentifier, displayName: "L4")
        let tabUnderL3 = makeTab(parentID: split3.uniqueIdentifier, displayName: "TabUnderL3")
        return wrap(name: "wgDeepNesting",
                    sessions: [root, split1, split2, split3, split4, tabUnderL3])
    }

    // Workgroup with one of every user-addable toolbar-item kind —
    // used to exercise §1.4 (correct view classes for each kind).
    // .name isn't included; it's auto-injected only when no
    // .modeSwitcher is present, which we have here.
    static func wgAllToolbarKinds() -> iTermWorkgroup {
        let items: [iTermWorkgroupToolbarItem] = [
            .modeSwitcher,
            .changedFileSelector,
            .gitStatus,
            .navigation(WorkgroupNavigationShortcuts(back: nil, forward: nil, reload: nil)),
            .reload(nil),
            .spacer(minWidth: 4, maxWidth: 8)
        ]
        let root = makeRoot(items: items)
        let peer = makePeer(parentID: root.uniqueIdentifier, items: items, displayName: "P")
        return wrap(name: "wgAllToolbarKinds", sessions: [root, peer])
    }
}

// MARK: - Test base class

// Shared scaffolding for workgroup-entry tests. Subclasses call
// `enter(workgroup)` and then assert on the resulting object graph
// via the helper accessors below.
class WorkgroupEntryTestBase: XCTestCase {
    var leader: PTYSession!
    var spawner: FakeWorkgroupSpawner!
    var instance: iTermWorkgroupInstance?
    var workgroup: iTermWorkgroup!

    override func setUp() {
        super.setUp()
        leader = PTYSession(synthetic: false)!
        spawner = FakeWorkgroupSpawner()
    }

    override func tearDown() {
        // Every workgroup test sweeps the controller's registry
        // invariants for free: no torn-down instance registered, keys
        // matching, leader back-pointers resolving. A violation here
        // points at whatever the test just did, instead of surfacing
        // as a ghost in some later test (or in the field).
        iTermWorkgroupController.instance.checkConsistency()
        // Drop strong refs in a defined order so deinit never has to
        // look at a partially-released graph.
        instance = nil
        workgroup = nil
        spawner = nil
        leader = nil
        super.tearDown()
    }

    @discardableResult
    func enterWorkgroup(_ wg: iTermWorkgroup) -> iTermWorkgroupInstance? {
        workgroup = wg
        instance = iTermWorkgroupInstance.enter(workgroup: wg,
                                                on: leader,
                                                spawner: spawner)
        return instance
    }

    // Resolves a config UUID to its live PTYSession. The leader
    // (root config) is the test's leader session; everything else
    // came from the fake spawner.
    func liveSession(forConfigID id: String) -> PTYSession? {
        if let root = workgroup.root, id == root.uniqueIdentifier {
            return leader
        }
        return spawner.session(forConfigID: id)
    }

    func config(forConfigID id: String) -> iTermWorkgroupSessionConfig? {
        return workgroup.sessions.first(where: { $0.uniqueIdentifier == id })
    }

    // True if config N has any peer-kind children — useful for picking
    // which expectation to assert.
    func configHasPeerChildren(_ id: String) -> Bool {
        return workgroup.sessions.contains { s in
            guard s.parentID == id else { return false }
            if case .peer = s.kind { return true }
            return false
        }
    }

    // True if config N is itself a peer node.
    func configIsPeer(_ id: String) -> Bool {
        guard let cfg = config(forConfigID: id) else { return false }
        if case .peer = cfg.kind { return true }
        return false
    }

    // Computes the toolbar items that should appear on the live
    // session for config N, after the production-side filtering rules
    // (drop .modeSwitcher on non-peer-port toolbars; drop git-poller
    // items if no poller exists in the workgroup).
    func expectedToolbarItems(for cfg: iTermWorkgroupSessionConfig) -> [iTermWorkgroupToolbarItem] {
        let isPeerPortToolbar: Bool
        if case .peer = cfg.kind {
            // Peer in a peer port (main or nested) — full items.
            isPeerPortToolbar = true
        } else if cfg.parentID == nil {
            // Root is always part of the main peer port.
            isPeerPortToolbar = true
        } else if configHasPeerChildren(cfg.uniqueIdentifier) {
            // Non-peer host that itself runs a peer group — its
            // toolbar comes from the nested port (peer-port-style).
            isPeerPortToolbar = true
        } else {
            // Leaf non-peer (split/tab without peer kids).
            isPeerPortToolbar = false
        }
        let workgroupHasPoller = workgroup.sessions.contains { s in
            s.toolbarItems.contains(where: { $0.needsGitPoller })
        }
        return cfg.toolbarItems.filter { item in
            if !isPeerPortToolbar, case .modeSwitcher = item { return false }
            if item.needsGitPoller, !workgroupHasPoller { return false }
            return true
        }
    }
}
