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

    // Active workgroup instances keyed by instanceUniqueIdentifier.
    // The key is a stable string minted at entry time, so an entry
    // stays reachable no matter what happens to its sessions: exit
    // resolves through any member's workgroupInstance back-pointer,
    // not through the leader. (An earlier design keyed by
    // ObjectIdentifier(leader), which made the entry unreachable if
    // the leader ever deallocated while registered, and risked a
    // recycled address aliasing the stale key to a new session.
    // Session GUIDs are no better: they rotate on restart, see
    // PTYSession.replaceTerminatedShellWithNewInstance.)
    private var instances: [String: iTermWorkgroupInstance] = [:]

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
        switch enterDisposition(workgroupUniqueIdentifier: identifier, on: session) {
        case .alreadyEntered:
            return true
        case .refused(let refusal):
            switch refusal {
            case .restoring:
                RLog("iTermWorkgroupController.enter: refusing; session \(session.guid) is being restored into a workgroup")
            case .unusableWorkgroup:
                RLog("iTermWorkgroupController.enter: no usable workgroup with id \(identifier)")
            case .nonLeaderMember(let member):
                RLog("iTermWorkgroupController.enter: refusing to switch workgroups on \(session.guid), a non-leader member of \(member.instanceUniqueIdentifier)")
            }
            return false
        case .proceed(let existing, let workgroup):
            if let existing {
                // Running a different one (the disposition proved the
                // session is its leader) — exit first. The toolbar
                // refresh happens below on success.
                exit(instance: existing)
            }
            guard let instance = iTermWorkgroupInstance.enter(workgroup: workgroup,
                                                              on: session,
                                                              spawner: spawner) else {
                RLog("iTermWorkgroupController: failed to build instance for \(identifier)")
                return false
            }
            // Entry spawns splits/tabs, during which the instance's
            // sessionWillTerminate observer is already live. If a tracked
            // session died mid-spawn, the observer routed to
            // exit(instance:) and tore the instance down; registering the
            // corpse would leave a permanent ghost (teardown cleared every
            // back-pointer, so no member could ever resolve to it and no
            // path would remove the entry).
            guard !instance.didTeardown else {
                RLog("iTermWorkgroupController.enter: instance \(instance.instanceUniqueIdentifier) was torn down during entry (a member died mid-spawn); not registering")
                return false
            }
            instances[instance.instanceUniqueIdentifier] = instance
            session.delegate?.sessionDidChangeDesiredToolbarItems(session)
            checkConsistency()
            return true
        }
    }

    // What enter() would do, resolved once. Single home for the
    // predicates AND the values they resolve (the registered instance,
    // the workgroup config), so enter(), canEnter(), and menu/trigger
    // validation cannot drift from each other and enter() doesn't
    // re-derive what the check already computed.
    enum EnterDisposition {
        // The session is already running this workgroup; enter() is an
        // idempotent no-op success — nothing gets torn down or built —
        // even if the config has since been deleted from the model.
        case alreadyEntered
        case refused(EnterRefusal)
        // Go ahead: exit `existing` (nil when the session is in no
        // workgroup; non-nil means the session is its leader and is
        // switching) and build from `workgroup`.
        case proceed(existing: iTermWorkgroupInstance?, workgroup: iTermWorkgroup)
    }

    enum EnterRefusal {
        // `session` is being restored into a workgroup: the
        // restoration coordinator is about to rebuild the saved
        // instance, and an enter racing it would orphan one of the
        // two. Reconstruction itself never trips this — the
        // coordinator calls adopt, not enter.
        case restoring
        // The identifier resolves to no configured workgroup (e.g. a
        // stale trigger pointing at one the user deleted), or to one
        // with no root node, which iTermWorkgroupInstance.enter cannot
        // build. Checked BEFORE any teardown so switching to a stale
        // identifier can't destroy the running workgroup and deliver
        // nothing.
        case unusableWorkgroup
        // Switching workgroups is only supported on the leader.
        // Exiting tears down every member, and when `session` is a
        // peer or split/tab child that includes `session` itself:
        // teardown would terminate it (peer) or schedule a deferred
        // close (child) that would kill the new workgroup moments
        // after it was entered.
        case nonLeaderMember(iTermWorkgroupInstance)
    }

    func enterDisposition(workgroupUniqueIdentifier identifier: String,
                          on session: PTYSession) -> EnterDisposition {
        let existing = registeredInstance(on: session)
        if let existing {
            if existing.workgroupUniqueIdentifier == identifier {
                return .alreadyEntered
            }
            if existing.mainSession !== session {
                return .refused(.nonLeaderMember(existing))
            }
        }
        // Key the refusal on session identity, not GUID membership: a
        // live, unrelated session can share a GUID with a restoring
        // descriptor member (saved-with-contents sessions keep their
        // GUIDs), and only the actual anchor object is the one a
        // racing enter would orphan. (The terminal trigger keeps its
        // own GUID sampling — it fires on a replayed shell and needs
        // the GUID before the session object is in hand.)
        if WorkgroupRestorationCoordinator.shared.isRestoringAnchor(session) {
            return .refused(.restoring)
        }
        guard let workgroup = resolveWorkgroup(uniqueIdentifier: identifier),
              workgroup.root != nil else {
            return .refused(.unusableWorkgroup)
        }
        return .proceed(existing: existing, workgroup: workgroup)
    }

    func enterRefusal(workgroupUniqueIdentifier identifier: String,
                      on session: PTYSession) -> EnterRefusal? {
        if case .refused(let refusal) = enterDisposition(
            workgroupUniqueIdentifier: identifier, on: session) {
            return refusal
        }
        return nil
    }

    // True iff enter() would proceed (including the idempotent
    // same-workgroup no-op). UI that offers Enter Workgroup consults
    // this so it can disable instead of presenting an action that
    // silently fails.
    func canEnter(workgroupUniqueIdentifier identifier: String,
                  on session: PTYSession) -> Bool {
        return enterRefusal(workgroupUniqueIdentifier: identifier,
                            on: session) == nil
    }

    // The Workgroups-menu / Enter-Workgroup-trigger policy: enter only
    // when the session is in NO workgroup at all (the menu and triggers
    // have always required exiting first — unlike enter() itself, which
    // supports leader-side switching) AND the controller would proceed.
    // Single seam so the menu and the trigger handlers can't drift from
    // each other or from enter() as refusal predicates evolve.
    @objc
    func canEnterFromUI(workgroupUniqueIdentifier identifier: String,
                        on session: PTYSession) -> Bool {
        guard registeredInstance(on: session) == nil else { return false }
        return canEnter(workgroupUniqueIdentifier: identifier, on: session)
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
        if let existing = registeredInstance(on: leader) {
            return existing
        }
        // The caller's ID comes from a persisted descriptor, so it can
        // collide with a live instance: restoring an arrangement that
        // was saved while this workgroup was still running, restoring
        // the same arrangement twice, or two anchors in one restore
        // sharing a descriptor. Registering under the same key would
        // silently evict the live instance with no teardown, stranding
        // its buried peers. The adopted copy is a distinct workgroup
        // built on distinct sessions, so give it a fresh identity; the
        // next save re-reads the ID from the live instance, so
        // re-saving stays consistent.
        //
        // Known limitation: reattached members' shells still carry
        // ITERM_WORKGROUP_ID=<persisted id> — the env var is injected
        // only at launch and a running shell's environment can't be
        // rewritten — so after the rename an external tool reading it
        // from an adopted member resolves to the OTHER live instance
        // (the one that kept the persisted ID). Freshly spawned peers
        // in the adopted copy get the new ID. Tolerated: colliding
        // restores are rare and the alternative (evicting the live
        // instance) strands sessions.
        let resolvedID: String
        if instances[instanceUniqueIdentifier] != nil {
            resolvedID = iTermWorkgroupInstance.mintInstanceUniqueIdentifier()
            RLog("iTermWorkgroupController.adopt: persisted instance id \(instanceUniqueIdentifier) is already registered; adopting under fresh id \(resolvedID)")
        } else {
            resolvedID = instanceUniqueIdentifier
        }
        guard let instance = iTermWorkgroupInstance.adopt(
            workgroup: workgroup,
            leader: leader,
            instanceUniqueIdentifier: resolvedID,
            activeIdentifier: activeIdentifier,
            gitBase: gitBase,
            peerSessionsByConfigID: peerSessionsByConfigID,
            nonPeerSessionsByConfigID: nonPeerSessionsByConfigID,
            spawner: spawner) else {
            RLog("iTermWorkgroupController: failed to adopt \(workgroup.uniqueIdentifier)")
            return nil
        }
        // Same mid-build teardown hazard as enter(); see the
        // didTeardown guard there.
        guard !instance.didTeardown else {
            RLog("iTermWorkgroupController.adopt: instance \(instance.instanceUniqueIdentifier) was torn down during adoption; not registering")
            return nil
        }
        instances[instance.instanceUniqueIdentifier] = instance
        checkConsistency()
        return instance
    }

    @objc
    func exit(on session: PTYSession) {
        guard let instance = registeredInstance(on: session) else {
            RLog("iTermWorkgroupController.exit: session \(session.guid) is not in a registered workgroup")
            return
        }
        exit(instance: instance)
        // Refresh the toolbar on the session the user acted on (which may
        // be a peer or child, not the leader).
        session.delegate?.sessionDidChangeDesiredToolbarItems(session)
    }

    // Remove and tear down `instance` directly. The stable string key
    // means this works no matter which of the instance's sessions are
    // still alive; iTermWorkgroupInstance's sessionWillTerminate
    // observer calls this so a member's termination always reaches
    // teardown even if the leader is already gone.
    func exit(instance: iTermWorkgroupInstance) {
        if instances[instance.instanceUniqueIdentifier] === instance {
            instances.removeValue(forKey: instance.instanceUniqueIdentifier)
        }
        // Tear down even when the instance isn't (or is no longer) the
        // dict's occupant: an alive-but-unregistered instance must not
        // skip teardown or its members leak. teardown() is idempotent
        // via didTeardown, so the already-exited case stays a no-op.
        instance.teardown()
        checkConsistency()
    }

    // Asserts the registry invariants that the reentrancy bugs of the
    // past violated: no torn-down instance stays registered, keys
    // match their instances, and a live leader's back-pointer resolves
    // to its registered instance. Called after every mutation; the
    // dict is tiny. WorkgroupEntryTestBase also sweeps this in
    // tearDown so every workgroup test checks it for free.
    //
    // Debug-only, deviating from the usual asserts-in-release policy:
    // this sweeps EVERY instance after ANY mutation, so a transiently
    // inconsistent instance mid-build elsewhere (harmless and
    // self-correcting) would crash a user's release build for a state
    // it didn't cause. Development builds and the test suite keep the
    // full strictness.
    func checkConsistency() {
        #if DEBUG
        for (key, instance) in instances {
            it_assert(!instance.didTeardown,
                      "torn-down instance \(key) still registered")
            it_assert(key == instance.instanceUniqueIdentifier,
                      "dict key \(key) mismatches instance \(instance.instanceUniqueIdentifier)")
            if let main = instance.mainSession {
                it_assert(main.workgroupInstance === instance,
                          "leader back-pointer broken for \(key)")
            }
        }
        #endif
    }

    @objc
    func workgroupInstance(on session: PTYSession) -> iTermWorkgroupInstance? {
        return registeredInstance(on: session)
    }

    // The registered instance `session` belongs to, or nil. Callers
    // (the Exit Workgroup menu, triggers) often act on whatever
    // session is focused — which can be the leader, a non-leader peer,
    // or a split/tab child. Every member carries a workgroupInstance
    // back-pointer, so resolve through that, validated against the
    // dict so a stale back-pointer on a session that outlived its
    // workgroup's teardown can't resurrect a dead instance.
    private func registeredInstance(on session: PTYSession) -> iTermWorkgroupInstance? {
        guard let instance = session.workgroupInstance,
              instances[instance.instanceUniqueIdentifier] === instance else {
            return nil
        }
        return instance
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
        return instances[identifier]?.mainSession
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
