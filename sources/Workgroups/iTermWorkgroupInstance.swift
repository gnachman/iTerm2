//
//  iTermWorkgroupInstance.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/23/26.
//

import Foundation

// Runtime counterpart of an iTermWorkgroup config. One instance per
// active workgroup on a main session; owned by iTermWorkgroupController
// and referenced weakly from the main session.
//
// Sessions in the workgroup come in two flavors:
//   - Peer-group members: the main (root) plus its peer children.
//     These are wired up by iTermWorkgroupPeerPort, which knows how
//     to swap the visible toolbar between peers via PTYTab.
//   - Non-peer children: split panes and new tabs spawned at entry
//     time. They have their own toolbar (built fresh from config)
//     and don't participate in the peer-swap mechanism.
@objc(iTermWorkgroupInstance)
final class iTermWorkgroupInstance: NSObject {
    @objc let workgroupUniqueIdentifier: String
    @objc weak var mainSession: PTYSession?

    // Config snapshot at entry time.
    let workgroup: iTermWorkgroup

    // The peer port wired to the main session's SessionView.
    @objc let peerPort: iTermWorkgroupPeerPort

    // Per-non-peer-session toolbar item views, keyed by session GUID.
    // Built once when the session is spawned and retained for the
    // life of the workgroup instance.
    private var nonPeerToolbarItems: [String: [SessionToolbarGenericView]] = [:]

    // GUIDs of non-peer sessions we spawned, in spawn order. Used by
    // teardown to terminate them when the workgroup exits.
    private var nonPeerSessionGUIDs: [String] = []

    // Nested peer ports for non-peer hosts that themselves host a peer
    // group (e.g. a split whose config declares peer children). Each
    // port needs to be invalidated at teardown, and toolbarItems(for:)
    // consults them when the main port doesn't own the session.
    private var nestedPeerPorts: [iTermWorkgroupPeerPort] = []

    init(workgroup: iTermWorkgroup,
         mainSession: PTYSession,
         peerPort: iTermWorkgroupPeerPort) {
        self.workgroupUniqueIdentifier = workgroup.uniqueIdentifier
        self.workgroup = workgroup
        self.mainSession = mainSession
        self.peerPort = peerPort
        super.init()
    }

    // The toolbar items to show on a specific session's SessionView.
    //
    // For peer-group sessions: each peer has its own ordered list of
    // NSView instances built fresh from its config; the same view
    // objects are retained in the port's per-peer dict across
    // activations, so anything held on a peer's view (e.g. its
    // changed-file selector's last selection) persists across peer
    // swaps. Cross-peer consistency is coordinated externally: every
    // gitStatus / changedFileSelector view reads from a single shared
    // poller, and the active-peer segment on every modeSwitcher is
    // synced on activate.
    //
    // For non-peer sessions (splits/tabs): items were built once when
    // the session was spawned and live in nonPeerToolbarItems.
    @objc
    func toolbarItems(for session: PTYSession) -> [SessionToolbarGenericView] {
        if let guid = session.guid,
           let items = nonPeerToolbarItems[guid] {
            return items
        }
        if let id = peerPort.identifier(for: session) {
            return peerPort.toolbarItems(forPeerID: id)
        }
        for port in nestedPeerPorts {
            if let id = port.identifier(for: session) {
                return port.toolbarItems(forPeerID: id)
            }
        }
        return []
    }

    // Register a peer port owned by a non-peer host (e.g. a split or
    // tab whose config itself declares peer children). The host's
    // toolbar is provided by the port, not by nonPeerToolbarItems.
    //
    // `peerChildrenPromises` are the launch promises for the nested
    // port's non-leader peers. As each resolves, we record its GUID
    // in nonPeerSessionGUIDs so teardown can clear workgroupInstance
    // and peerPort on it before terminate — otherwise the peer keeps
    // a dangling back-pointer to the torn-down instance. (The port's
    // own invalidate() terminates non-leader peers, but doesn't clear
    // those back-pointers; belt-and-suspenders here keeps cleanup
    // symmetric with registerNonPeer.)
    func registerNestedPeerPort(_ port: iTermWorkgroupPeerPort,
                                hostSession: PTYSession,
                                peerChildrenPromises: [iTermPromise<PTYSession>]) {
        nestedPeerPorts.append(port)
        if let guid = hostSession.guid {
            nonPeerSessionGUIDs.append(guid)
        }
        for promise in peerChildrenPromises {
            promise.then { [weak self] peerSession in
                guard let self, let guid = peerSession.guid else { return }
                if !self.nonPeerSessionGUIDs.contains(guid) {
                    self.nonPeerSessionGUIDs.append(guid)
                }
            }
        }
    }

    // Register a freshly-spawned non-peer session (split or tab) with
    // its config-built toolbar items, and wire the workgroup back-
    // pointer so its desiredToolbarItems can find us.
    func registerNonPeer(session: PTYSession,
                        config: iTermWorkgroupSession) {
        guard let guid = session.guid else { return }
        let items = buildNonPeerToolbarItems(for: config)
        nonPeerToolbarItems[guid] = items
        nonPeerSessionGUIDs.append(guid)
        session.workgroupInstance = self
        // Refresh the new session's toolbar view to pick up its items.
        session.delegate?.sessionDidChangeDesiredToolbarItems(session)
    }

    private func buildNonPeerToolbarItems(for config: iTermWorkgroupSession) -> [SessionToolbarGenericView] {
        let context = WorkgroupToolbarContext(
            peerPort: nil,
            gitPoller: peerPort.gitPoller,
            scope: mainSession?.genericScope ?? iTermVariableScope(),
            peerGroupMembers: [],
            activePeerIdentifier: "",
            buttonDelegate: nil)
        var built: [SessionToolbarGenericView] = []
        for item in config.toolbarItems {
            // modeSwitcher only makes sense in a peer group; skip it
            // on non-peer sessions even if the user added it in the
            // settings UI.
            if case .modeSwitcher = item { continue }
            if let view = WorkgroupToolbarBuilder.build(
                item: item, context: context) {
                built.append(view)
            }
        }
        return built
    }

    // Tear down peers, terminate non-peer children, and release
    // references. Leaves the main session in a clean state so a later
    // enter() can install a fresh port — PTYSession.set(peerPort:)
    // asserts the previous port is gone.
    @objc
    func teardown() {
        peerPort.invalidate()
        for port in nestedPeerPorts {
            port.invalidate()
        }
        nestedPeerPorts.removeAll()
        for guid in nonPeerSessionGUIDs {
            if let s = iTermController.sharedInstance()?.session(withGUID: guid) {
                s.workgroupInstance = nil
                s.peerPort = nil
                s.terminate()
            }
        }
        nonPeerSessionGUIDs.removeAll()
        nonPeerToolbarItems.removeAll()
        mainSession?.workgroupInstance = nil
        mainSession?.peerPort = nil
    }

    // MARK: - Entry

    // Build a workgroup instance on the given main session.
    static func enter(workgroup: iTermWorkgroup,
                      on mainSession: PTYSession) -> iTermWorkgroupInstance? {
        guard let root = workgroup.root else { return nil }

        // Peer-group members = the root + its peer children.
        let peerChildren = workgroup.sessions.filter { s in
            guard s.parentID == root.uniqueIdentifier else { return false }
            if case .peer = s.kind { return true }
            return false
        }
        let peerConfigs: [iTermWorkgroupSession] = [root] + peerChildren

        // Build promises for each peer session. The leader (root) is
        // the already-existing main session; other peers are launched
        // anew via PTYSession's peer-creation helper.
        var peers: [String: iTermPromise<PTYSession>] = [:]
        peers[root.uniqueIdentifier] = iTermPromise<PTYSession>(value: mainSession)
        for peer in peerChildren {
            peers[peer.uniqueIdentifier] =
                mainSession.makeWorkgroupPeer(config: peer)
        }

        let port = iTermWorkgroupPeerPort(
            peers: peers,
            peerConfigs: peerConfigs,
            activeSessionIdentifier: root.uniqueIdentifier,
            leaderIdentifier: root.uniqueIdentifier,
            leaderScope: mainSession.genericScope)

        mainSession.peerPort = port

        let instance = iTermWorkgroupInstance(workgroup: workgroup,
                                              mainSession: mainSession,
                                              peerPort: port)

        // Propagate workgroupInstance to every peer (not just the
        // main). desiredToolbarItems on a peer needs to reach the
        // instance to return that peer's own items; without this, a
        // peer ends up with an empty toolbar the moment it's
        // activated.
        for (_, promise) in peers {
            promise.then { peerSession in
                peerSession.workgroupInstance = instance
            }
        }

        // Recursively spawn split-pane and tab children. Each non-peer
        // session that lands is used as the parent for its own children
        // — arbitrary depth works because splitVertically/addSession
        // are synchronous and leave the new session fully installed in
        // the view hierarchy before spawnNonPeerChildren(of:) returns.
        // Peer-group children of a non-peer host are handled separately
        // inside spawnSplit/spawnTab via registerNonPeerOrPeerGroupHost.
        instance.spawnNonPeerChildren(of: mainSession,
                                      parentConfigID: root.uniqueIdentifier)

        return instance
    }

    // Walk the config and spawn every split/tab descendant of the node
    // identified by `parentConfigID`, using `session` as the live parent
    // for the first level. Each spawnSplit/spawnTab call recurses back
    // into this method, so a deeply-nested tree unwinds top-down.
    func spawnNonPeerChildren(of session: PTYSession,
                              parentConfigID: String) {
        let children = workgroup.sessions.filter {
            $0.parentID == parentConfigID
        }
        for child in children {
            switch child.kind {
            case .split:
                spawnSplit(config: child, parent: session)
            case .tab:
                spawnTab(config: child, parent: session)
            case .root, .peer:
                break
            }
        }
    }
}
