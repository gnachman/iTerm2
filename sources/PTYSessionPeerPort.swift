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

    init(peers: [String: iTermPromise<PTYSession>],
         activeSessionIdentifier: String) {
        self.activeSessionIdentifier = activeSessionIdentifier
        self.peers = peers
        
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
        for peer in peers.values {
            peer.then { $0.terminate() }
        }
        peers = [:]
    }
}

