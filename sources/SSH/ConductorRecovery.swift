//
//  ConductorRecovery.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/27/22.
//

import Foundation

@objc(iTermConductorRecovery)
public class ConductorRecovery: NSObject {
    @objc let pid: pid_t
    @objc let dcsID: String
    @objc let tree: NSDictionary
    @objc let sshargs: String
    @objc let boolArgs: String
    @objc let clientUniqueID: String
    @objc let parent: Conductor?
    @objc let version: Int
    // it2-over-ssh proxy state carried across recovery from the pre-recovery conductor so
    // the proxy keeps working (and the user is not re-prompted) after reattaching. NOT
    // re-read from the framer: the nonce/socket could be, but the authorization grant is a
    // local trust decision and must never be re-derivable from remote-controlled state, so
    // the whole value travels via this in-process handoff. See Conductor.init(recovery:).
    let it2Proxy: IT2ProxyState

    init(pid: pid_t,
         dcsID: String,
         tree: NSDictionary,
         sshargs: String,
         boolArgs: String,
         clientUniqueID: String,
         version: Int,
         parent: Conductor?,
         it2Proxy: IT2ProxyState) {
        self.pid = pid
        self.dcsID = dcsID
        self.tree = tree
        self.sshargs = sshargs
        self.boolArgs = boolArgs
        self.clientUniqueID = clientUniqueID
        self.version = version
        self.parent = parent
        self.it2Proxy = it2Proxy
    }
}
