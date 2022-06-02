//
//  ConductorRecovery.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/27/22.
//

import Foundation

@objc(iTermConductorRecovery)
class ConductorRecovery: NSObject {
    @objc let pid: pid_t
    @objc let dcsID: String
    @objc let tree: NSDictionary
    @objc let sshargs: String
    @objc let boolArgs: String
    @objc let clientUniqueID: String
    @objc let parent: Conductor?

    @objc init(pid: pid_t,
               dcsID: String,
               tree: NSDictionary,
               sshargs: String,
               boolArgs: String,
               clientUniqueID: String,
               parent: Conductor?) {
        self.pid = pid
        self.dcsID = dcsID
        self.tree = tree
        self.sshargs = sshargs
        self.boolArgs = boolArgs
        self.clientUniqueID = clientUniqueID
        self.parent = parent
    }
}
