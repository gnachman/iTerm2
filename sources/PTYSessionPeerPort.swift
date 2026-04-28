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

    @objc var leaderSession: PTYSession? {
        return peers[leader]?.maybeValue
    }

    @objc var activeSession: PTYSession? {
        return peers[activeSessionIdentifier]?.maybeValue
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

    // Reverse-lookup: returns the peer-group identifier that `session`
    // is registered under, or nil if it isn't in this port.
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

