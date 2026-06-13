//
//  iTermWorkgroupController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/26.
//

import Foundation

// Public API for entering and exiting workgroups on sessions. Owns no
// trigger logic — callers (trigger sources like ClaudeCodeModeController,
// menu actions, API calls) invoke these methods directly.
@objc(iTermWorkgroupController)
final class iTermWorkgroupController: NSObject {
    @objc static let instance = iTermWorkgroupController()

    // Sessions currently running a workgroup, keyed by the Swift
    // object identity of the leader PTYSession. Object identity is
    // stable for the lifetime of the session object, even across
    // restarts that rotate `session.guid` (see
    // PTYSession.replaceTerminatedShellWithNewInstance). Keying by
    // GUID would break the moment the leader was restarted: lookups
    // by the new GUID would miss, and a re-enter under the new GUID
    // would orphan the original instance.
    private var instances: [ObjectIdentifier: iTermWorkgroupInstance] = [:]

    private override init() {
        super.init()
    }

    // Enter the workgroup identified by `workgroupUniqueIdentifier` on
    // `session`. Idempotent: entering the same workgroup twice is a
    // no-op; entering a different one while one is already running
    // exits the old one first.
    @objc
    @discardableResult
    func enter(workgroupUniqueIdentifier identifier: String,
               on session: PTYSession) -> Bool {
        return enter(workgroupUniqueIdentifier: identifier,
                     on: session,
                     spawner: DefaultWorkgroupSessionSpawner())
    }

    // Same as the @objc enter but lets the caller (only tests, today)
    // inject a spawner so the controller's dict stays the source of
    // truth without dragging in the real factory/PseudoTerminal.
    @discardableResult
    func enter(workgroupUniqueIdentifier identifier: String,
               on session: PTYSession,
               spawner: WorkgroupSessionSpawner) -> Bool {
        let key = ObjectIdentifier(session)

        // Already running the same one? Nothing to do.
        if let existing = instances[key],
           existing.workgroupUniqueIdentifier == identifier {
            return true
        }
        // Running a different one — exit first.
        if instances[key] != nil {
            exit(on: session)
        }

        guard let workgroup = resolveWorkgroup(uniqueIdentifier: identifier) else {
            DLog("iTermWorkgroupController: no workgroup with id \(identifier)")
            return false
        }
        guard let instance = iTermWorkgroupInstance.enter(workgroup: workgroup,
                                                          on: session,
                                                          spawner: spawner) else {
            DLog("iTermWorkgroupController: failed to build instance for \(identifier)")
            return false
        }
        instances[key] = instance
        session.delegate?.sessionDidChangeDesiredToolbarItems(session)
        return true
    }

    // Reconstruct a workgroup from already-restored sessions (app
    // relaunch). Idempotent: if `leader` already hosts an instance,
    // returns it untouched. Registration in `instances` is the last
    // step and is synchronous, so the instance (and the peer port it
    // transitively retains) stays alive — both back-pointers on the
    // sessions are weak. The caller (WorkgroupRestorationCoordinator)
    // resolves the config and the member sessions, and is responsible
    // for refreshing the toolbar on the active (in-pane) session.
    @discardableResult
    func adopt(workgroup: iTermWorkgroup,
               leader: PTYSession,
               instanceUniqueIdentifier: String,
               activeIdentifier: String,
               gitBase: String,
               peerSessionsByConfigID: [String: PTYSession],
               nonPeerSessionsByConfigID: [String: PTYSession],
               spawner: WorkgroupSessionSpawner = DefaultWorkgroupSessionSpawner()) -> iTermWorkgroupInstance? {
        let key = ObjectIdentifier(leader)
        if let existing = instances[key] {
            return existing
        }
        guard let instance = iTermWorkgroupInstance.adopt(
            workgroup: workgroup,
            leader: leader,
            instanceUniqueIdentifier: instanceUniqueIdentifier,
            activeIdentifier: activeIdentifier,
            gitBase: gitBase,
            peerSessionsByConfigID: peerSessionsByConfigID,
            nonPeerSessionsByConfigID: nonPeerSessionsByConfigID,
            spawner: spawner) else {
            DLog("iTermWorkgroupController: failed to adopt \(workgroup.uniqueIdentifier)")
            return nil
        }
        instances[key] = instance
        return instance
    }

    @objc
    func exit(on session: PTYSession) {
        let leader = leaderSession(for: session)
        guard let instance = instances.removeValue(forKey: ObjectIdentifier(leader)) else {
            return
        }
        instance.teardown()
        // Refresh the toolbar on the session the user acted on (which may
        // be a peer or child, not the leader) as well as the leader.
        session.delegate?.sessionDidChangeDesiredToolbarItems(session)
    }

    @objc
    func workgroupInstance(on session: PTYSession) -> iTermWorkgroupInstance? {
        return instances[ObjectIdentifier(leaderSession(for: session))]
    }

    // The instance is keyed by its leader, but callers (the Exit
    // Workgroup menu, triggers) often act on whatever session is
    // focused — which can be a non-leader peer (after the user switched
    // peers, or after restoring a workgroup that was saved on a peer) or
    // a split/tab child. Every workgroup member carries a back-pointer
    // to its instance, whose mainSession is the leader, so resolve
    // through that. Falls back to the session itself when it isn't a
    // member, leaving non-member lookups (the common case) unchanged.
    private func leaderSession(for session: PTYSession) -> PTYSession {
        return session.workgroupInstance?.mainSession ?? session
    }

    // All active workgroup instances, sorted by instance-unique
    // identifier so iteration order is stable across calls. The
    // underlying dictionary's value-iteration order is unspecified and
    // shifts after any mutation, which would surface as the cockpit's
    // workgroup-mode tree spuriously reordering itself on every
    // refresh. Sorting here means every caller gets a deterministic
    // order without having to remember to sort at the call site.
    @objc
    var allInstances: [iTermWorkgroupInstance] {
        return instances.values.sorted {
            $0.instanceUniqueIdentifier < $1.instanceUniqueIdentifier
        }
    }

    // Look up the main (leader) session for the active workgroup
    // instance whose per-entry id matches `identifier`. Returns nil
    // if no active workgroup has that id (e.g. the workgroup was
    // exited, or `identifier` was never a workgroup instance id).
    @objc
    func mainSession(forInstanceUniqueIdentifier identifier: String) -> PTYSession? {
        for instance in instances.values {
            if instance.instanceUniqueIdentifier == identifier {
                return instance.mainSession
            }
        }
        return nil
    }

    // MARK: - Private

    // Looks up the workgroup config by identifier in the user's
    // configured workgroups. Returns nil if the identifier doesn't
    // match a configured workgroup — e.g. a stale trigger pointing
    // at one the user has since deleted.
    private func resolveWorkgroup(uniqueIdentifier: String) -> iTermWorkgroup? {
        return iTermWorkgroupModel.instance.workgroup(uniqueIdentifier: uniqueIdentifier)
    }
}
