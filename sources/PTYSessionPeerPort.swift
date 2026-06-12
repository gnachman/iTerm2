//
//  PTYSessionPeerPort.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/19/26.
//

import Foundation

// Represents the slot occupied by peer sessions.
@objc
class PTYSessionPeerPort: NSObject {
    private var peers = [String: iTermPromise<PTYSession>]()
    // This can be the identifier of a promised but not realized session. Consider it aspirational.
    var activeSessionIdentifier: String
    private let leader: String

    // Clippings shared by all sessions in this peer group. Stored on the
    // leader session's swiftState — peers read/write through this pass-through.
    // The leader outlives the other peers (see invalidate()), so anchoring the
    // data there gives clippings a natural lifetime tied to the main session.
    @objc var clippings: [PTYSessionClipping] {
        get { leaderSession?.localClippings ?? [] }
        set { leaderSession?.localClippings = newValue }
    }

    // Per-peer-group "user wants the clippings panel visible" flag.
    @objc var clippingsVisibilityFlag: Bool {
        get { leaderSession?.localClippingsVisibilityFlag ?? true }
        set { leaderSession?.localClippingsVisibilityFlag = newValue }
    }

    // Per-peer-group archive of past clipping snapshots, anchored on the
    // leader for the same lifetime reasons as `clippings`.
    @objc var clippingsArchive: [[PTYSessionClipping]] {
        get { leaderSession?.localClippingsArchive ?? [] }
        set { leaderSession?.localClippingsArchive = newValue }
    }

    // Per-peer-group view index into the archive timeline; -1 = live.
    @objc var clippingsViewIndex: Int {
        get { leaderSession?.localClippingsViewIndex ?? -1 }
        set { leaderSession?.localClippingsViewIndex = newValue }
    }

    @objc var leaderSession: PTYSession? {
        return peers[leader]?.maybeValue
    }

    @objc var activeSession: PTYSession? {
        return peers[activeSessionIdentifier]?.maybeValue
    }

    // Every peer session whose promise has fulfilled. Exposed so callers
    // that need to walk the peer group (e.g. iTermWorkgroupInstance’s
    // deferred-launch fan-out) don't have to know the internal storage.
    var realizedPeerSessions: [PTYSession] {
        return peers.values.compactMap { $0.maybeValue }
    }

    // Every realized peer paired with the identifier it is registered
    // under. Used by the restoration encoder, which needs both the
    // config UUID and the live session for each member it embeds.
    var realizedMembers: [(id: String, session: PTYSession)] {
        return peers.compactMap { (id, promise) in
            guard let session = promise.maybeValue else { return nil }
            return (id, session)
        }
    }

    // The identifier of the leader (root) peer. Exposed read-only so the
    // restoration encoder can record which member is the leader, since
    // the leader is not always the visible/active member at save time.
    @objc var leaderIdentifier: String {
        return leader
    }

    init(peers: [String: iTermPromise<PTYSession>],
         activeSessionIdentifier: String,
         leaderIdentifier: String) {
        self.activeSessionIdentifier = activeSessionIdentifier
        self.peers = peers
        self.leader = leaderIdentifier

        super.init()
        
        for peer in peers.values {
            peer.then { [weak self] peerSession in
                if let self {
                    peerSession.set(peerPort: self)
                }
            }
        }
    }
    
    func contains(session: PTYSession) -> Bool {
        return Array(peers.values).anySatisfies { $0.maybeValue === session }
    }

    // True when any peer in this port has the given session GUID,
    // whether that peer is currently in a tab or buried. Used to
    // decide whether a buried-or-orphaned peer's status belongs in
    // this peer group's window.
    @objc(containsPeerWithGUID:)
    func containsPeer(guid: String) -> Bool {
        return peers.values.contains { $0.maybeValue?.guid == guid }
    }

    // The realized peer session matching `guid`, or nil. Used by
    // callers (e.g. the toolbelt's row-resolution) that have a
    // session GUID but can't find it in the usual places (tab list
    // or iTermBuriedSessions) because the peer was never registered
    // there — see addBuriedSession's "Failed to create restorable
    // session" early-return for the workgroup-peer-born-buried case.
    @objc(peerSessionWithGUID:)
    func peerSession(withGUID guid: String) -> PTYSession? {
        return peers.values.compactMap { $0.maybeValue }
            .first { $0.guid == guid }
    }

    // Reverse-lookup: returns the peer-group identifier that `session`
    // is registered under, or nil if it isn't in this port.
    @objc(identifierForSession:)
    func identifier(for session: PTYSession) -> String? {
        for (id, promise) in peers {
            if promise.maybeValue === session {
                return id
            }
        }
        return nil
    }

    // The realized PTYSession for a given peer identifier, if the
    // promise has already fulfilled.
    func session(forIdentifier identifier: String) -> PTYSession? {
        return peers[identifier]?.maybeValue
    }

    @objc(activateIdentifier:)
    @discardableResult
    func activate(identifier: String) -> Bool {
        guard let promise = peers[identifier] else {
            return false
        }
        activeSessionIdentifier = identifier
        promise.then { [weak self] replacement in
            guard let self else {
                return
            }
            if activeSessionIdentifier != identifier {
                return
            }
            sessionDelegate?.sessionActivate(replacement, amongPeers: self, moveToolbar: true)
        }
        return true
    }
    
    var sessionDelegate: PTYSessionDelegate? {
        for peer in peers.values {
            if let delegate = peer.maybeValue?.delegate {
                return delegate
            }
        }
        return nil
    }

    // Terminate inactive session and release references.
    func invalidate() {
        for identifier in peers.keys where identifier != leader {
            peers[identifier]?.then {
                $0.terminate()
            }
        }
        peers = [:]
    }
}

