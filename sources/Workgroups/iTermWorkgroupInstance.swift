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

    // The toolbar items shown on the session's SessionView. Every
    // peer sees the same array (items flip enabled on activate).
    @objc var toolbarItems: [SessionToolbarGenericView] {
        return peerPort.toolbarItems
    }

    // Tear down peers and release references.
    @objc
    func teardown() {
        peerPort.invalidate()
        mainSession?.workgroupInstance = nil
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
        mainSession.workgroupInstance = instance
        return instance
    }
}
