//
//  FramerRecoveryRefusals.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/24/26.
//

import Foundation

// Remembers which SSH Integration connections were abandoned so their framer output can't
// start framer recovery (F-354, F-459). Recovering would type base64 "recover" into the
// shell that owns the tty and leave a recovery conductor holding the keyboard.
//
// Abandoning a connection abandons every connection nested in it, so a refusal at a
// parent depth covers that depth and every deeper one. That keeps output parsed before
// the abandonment (with the depths of the old, deeper framing) from recovering too.
//
// Only a hook by a connection that wasn't abandoned lifts a refusal. Its it2ssh unique
// ID tells them apart, so a stale hook in the abandoned connection's own buffered output
// can't lift it.
//
// Not thread-safe. VT100Terminal keeps one on the mutation queue for the tokens it
// executes, and PTYSession keeps one on the main queue for recoveries that were already
// requested when it decided to abandon the connection.
@objc(iTermFramerRecoveryRefusals)
final class FramerRecoveryRefusals: NSObject {
    // The lowest refused parent depth, or nil if nothing is refused.
    private var lowestRefusedParentDepth: Int32?
    private var abandonedClientUniqueIDs = Set<String>()

    // parentDepth is the depth of the abandoned connection's parent, or -1 for the
    // outermost connection.
    @objc(refuseForChildrenOfConductorAtDepth:abandonedClientUniqueIDs:)
    func refuse(parentDepth: Int32, abandonedClientUniqueIDs ids: [String]) {
        guard parentDepth >= -1 else {
            return
        }
        lowestRefusedParentDepth = min(lowestRefusedParentDepth ?? parentDepth, parentDepth)
        abandonedClientUniqueIDs.formUnion(ids.filter { !$0.isEmpty })
    }

    @objc var hasRefusal: Bool {
        return lowestRefusedParentDepth != nil
    }

    // Whether framer output for a child of the conductor at parentDepth must not start
    // recovery.
    @objc(isRefusedForChildrenOfConductorAtDepth:)
    func isRefused(parentDepth: Int32) -> Bool {
        guard let lowestRefusedParentDepth else {
            return false
        }
        return parentDepth >= lowestRefusedParentDepth
    }

    // A conductor hooked as a child of the conductor at parentDepth. Returns whether the
    // hook may start a conductor.
    //
    // A hook deeper than the abandoned connection was parsed inside its framing, so it
    // came from its stale output and is refused. So is a hook carrying an abandoned
    // connection's unique ID: starting a conductor for either would write to the shell
    // that owns the tty. Any other hook is a new connection whose framer output is its
    // own, so recovery is allowed again at its depth and below.
    @objc(shouldAcceptHookAsChildOfConductorAtDepth:clientUniqueID:)
    func shouldAcceptHook(parentDepth: Int32, clientUniqueID: String?) -> Bool {
        guard let lowest = lowestRefusedParentDepth else {
            return true
        }
        if parentDepth > lowest {
            DLog("Refuse hook at parent depth \(parentDepth) inside an abandoned connection at \(lowest)")
            return false
        }
        if let clientUniqueID, abandonedClientUniqueIDs.contains(clientUniqueID) {
            DLog("Refuse hook by abandoned connection \(clientUniqueID)")
            return false
        }
        lowestRefusedParentDepth = nil
        return true
    }

    // The it2ssh unique ID in an SSH_INIT token's parameters, which are the token, the
    // unique ID, and so on, separated by spaces, ending with the DCS ID.
    @objc(clientUniqueIDFromHookParameters:)
    static func clientUniqueID(fromHookParameters params: String?) -> String? {
        guard let parts = params?.components(separatedBy: " "), parts.count >= 2 else {
            return nil
        }
        return parts[1]
    }

    @objc(dcsIDFromHookParameters:)
    static func dcsID(fromHookParameters params: String?) -> String? {
        guard let parts = params?.components(separatedBy: " "), parts.count >= 2 else {
            return nil
        }
        return parts.last
    }
}
