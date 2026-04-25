//
//  iTermWorkgroupInstance.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/26.
//

import Foundation

// Runtime counterpart of an iTermWorkgroup config. One instance per
// active workgroup on a main session; owned by iTermWorkgroupController
// and referenced weakly from the main session.
//
// Landing A scope: peer group only. Split-pane and tab children aren't
// built yet — that's landing B.
@objc(iTermWorkgroupInstance)
final class iTermWorkgroupInstance: NSObject {
    @objc let workgroupUniqueIdentifier: String
    @objc weak var mainSession: PTYSession?

    // Config snapshot at entry time.
    let workgroup: iTermWorkgroup

    // The peer port wired to the main session's SessionView.
    @objc let peerPort: iTermWorkgroupPeerPort

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
    // Each peer has its own ordered list of NSView instances built
    // fresh from its config; the same view objects are retained in
    // the port's per-peer dict across activations, so anything held
    // on a peer's view (e.g. its changed-file selector's last
    // selection) persists across peer swaps. Cross-peer consistency
    // is coordinated externally: every gitStatus / changedFileSelector
    // view reads from a single shared poller, and the active-peer
    // segment on every modeSwitcher is synced on activate.
    @objc
    func toolbarItems(for session: PTYSession) -> [SessionToolbarGenericView] {
        guard let id = peerPort.identifier(for: session) else { return [] }
        return peerPort.toolbarItems(forPeerID: id)
    }

    // Tear down peers and release references. Leaves the main
    // session in a clean state so a later enter() can install a
    // fresh port — PTYSession.set(peerPort:) asserts the previous
    // port is gone.
    @objc
    func teardown() {
        peerPort.invalidate()
        mainSession?.workgroupInstance = nil
        mainSession?.peerPort = nil
    }

    // MARK: - Entry

    // Build a workgroup instance on the given main session.
    //
    // Landing A only handles the peer group (root + peer children).
    // Splits/tabs are returned but not yet instantiated; that's
    // landing B.
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
        return instance
    }
}
