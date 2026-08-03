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
    // The identifier whose view most recently actually occupied the
    // tab, as opposed to the aspirational value above. This is what a
    // failed activation rolls back to: rolling back to a captured
    // aspirational value could install an identifier that never
    // swapped in, making activeSession lie and defeating reveal's
    // activeSession != self rescue gate forever (a fulfilled promise
    // never re-runs its activation closure).
    private var lastSwappedActiveIdentifier: String
    // Set by invalidate(). Promise callbacks created at init and
    // activate() consult it so a peer spawn that fulfills after the
    // workgroup tore down doesn't wire itself to (or swap through) a
    // dead port.
    private(set) var invalidated = false
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
    // deferred-launch fan-out, iTermController's session-lookup
    // enumeration) don't have to know the internal storage.
    @objc var realizedPeerSessions: [PTYSession] {
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
        // The initially-active member is the one window creation (or
        // restoration) put in the tab.
        self.lastSwappedActiveIdentifier = activeSessionIdentifier
        self.peers = peers
        self.leader = leaderIdentifier

        super.init()
        
        for peer in peers.values {
            peer.then { [weak self] peerSession in
                // The invalidated check keeps a spawn that fulfills
                // after teardown from pointing the new session at a
                // dead port (teardown's sweep only covers peers
                // realized by then; invalidate()'s own then-block
                // terminates the late peer right after this).
                guard let self, !self.invalidated else { return }
                peerSession.set(peerPort: self)
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

    // Debug-log description of every realized member, formatted as
    // "<peerID>=<sessionGUID>". Shared by the diagnostic logging in
    // invalidate(), iTermWorkgroupInstance.teardown(), and
    // iTermController.diagnosis(unresolvableGUID:) so the member
    // format only needs to change in one place.
    var membersDebugDescription: String {
        return realizedMembers.map { "\($0.id)=\($0.session.guid)" }.joined(separator: ", ")
    }

    // Identity plus membership, so logs (and lldb po) can correlate
    // port references across log lines and with ObjC-side %p output.
    override var debugDescription: String {
        return "<\(type(of: self)): \(it_addressString) leader=\(leader) members=[\(membersDebugDescription)]>"
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
        // A spawn that already REJECTED can never be activated, so
        // refuse before committing. Committing would be worse than
        // pointless: a settled promise runs its callbacks
        // synchronously, so the catchError rollback would fire INSIDE
        // this call — before the iTermWorkgroupPeerPort override's
        // post-super switcher sync, which would then overwrite the
        // rollback's resync and re-highlight the dead peer — and the
        // caller would be told the activation succeeded. (A spawn that
        // rejects AFTER commit is the asynchronous case the catchError
        // below handles, in the correct order.)
        guard promise.maybeError == nil else {
            RLog("PTYSessionPeerPort.activate: refusing \(identifier); its spawn already failed (\(promise.maybeError!.localizedDescription))")
            return false
        }
        // Rescue first so every caller benefits (reveal, peer-switch
        // shortcuts, next/previous cycling): if the user buried the
        // group's only in-tab member, no member has a delegate and the
        // guard below would refuse. Restoring that member (a no-op when
        // a delegate is live) gives the swap an anchor.
        disinterAnchorIfNeeded()
        // Resolve the anchor BEFORE committing activeSessionIdentifier.
        // When every member is buried/windowless there is nothing to
        // swap on; committing anyway would desync the port — it would
        // believe this peer is active while the buried sibling's view
        // is what iTermBuriedSessions would restore, and the next
        // activation attempt would no-op on the already-active check.
        guard hasActivationAnchor() else {
            RLog("PTYSessionPeerPort.activate: no member of \(debugDescription) has a live delegate; refusing to activate \(identifier)")
            return false
        }
        activeSessionIdentifier = identifier
        promise.then { [weak self] replacement in
            guard let self, !invalidated else {
                return
            }
            if activeSessionIdentifier != identifier {
                return
            }
            // The delegate was alive at commit time, but an unrealized
            // peer's spawn fulfills asynchronously (PWD resolution) and
            // the user can bury the group's only in-tab member in the
            // interim. Re-run the rescue (a no-op when a delegate is
            // live), and if the group still has no anchor, roll the
            // commit back — otherwise the port would claim this peer is
            // active though it never swapped in, and reveal's
            // activeSession != self check would skip the rescue forever
            // after.
            disinterAnchorIfNeeded()
            guard let delegate = sessionDelegate else {
                RLog("PTYSessionPeerPort.activate: delegate vanished before \(identifier) fulfilled and no anchor could be restored")
                rollBackActivation()
                return
            }
            delegate.sessionActivate(replacement, amongPeers: self, moveToolbar: true)
            recordSwapOutcome(identifier: identifier, replacement: replacement)
            // The peer's view is now swapped into the tab (visible only if
            // that tab is the foreground one; the hook self-checks).
            didSwapInPeer(replacement)
        }.catchError { [weak self] error in
            // A deferred peer's spawn can REJECT (makeWorkgroupPeer:
            // session terminated mid-spawn, missing profile or view).
            // then-blocks never run for a rejected promise, so without
            // this the commit above would stick forever on a peer that
            // will never exist: activeSession nil, the mode-switcher
            // highlight stuck on a dead segment, re-activation a no-op.
            guard let self, !invalidated else {
                return
            }
            if activeSessionIdentifier != identifier {
                return
            }
            RLog("PTYSessionPeerPort.activate: spawn of \(identifier) failed (\(error.localizedDescription))")
            rollBackActivation()
        }
        return true
    }

    // Whether some member can anchor a swap. Seam for unit tests: a
    // real PTYSessionDelegate cannot be stubbed (the protocol has on
    // the order of a hundred required methods), so the rollback tests
    // override this to let activate() commit without a live tab.
    // @objc because PTYSession.reveal consults it to decide between
    // retrying a swap (some sibling is anchored) and reviving into a
    // window (the whole group is windowless).
    @objc func hasActivationAnchor() -> Bool {
        return sessionDelegate != nil
    }

    // Like hasActivationAnchor, but also true when a member is buried
    // (and therefore restorable into the group's pane via
    // disinterAnchorIfNeeded). reveal uses this to decide between
    // retrying the swap — which disinters that buried sibling first —
    // and reviving the windowless member into its own window. Reviving
    // when a buried sibling exists would put two members of one peer
    // group on screen once the buried one is later restored.
    @objc func hasRestorableAnchor() -> Bool {
        if sessionDelegate != nil {
            return true
        }
        return realizedPeerSessions.contains { isBuried($0) }
    }

    // True iff this port owns `identifier` (whether or not the member
    // is realized or activatable). A peer-switch shortcut that matches
    // an owned-but-dead member must be consumed, not leaked to the
    // shell, so callers distinguish "not ours" (keep looking / fall
    // through) from "ours but can't activate" (consume).
    func ownsIdentifier(_ identifier: String) -> Bool {
        return peers[identifier] != nil
    }

    // Seam for tests (the production check hits the iTermBuriedSessions
    // singleton, which unit tests can't populate): is `session`
    // currently buried?
    func isBuried(_ session: PTYSession) -> Bool {
        return (iTermBuriedSessions.sharedInstance().buriedSessions() ?? [])
            .contains { $0 === session }
    }

    // True when `identifier` names a member whose spawn hasn't already
    // failed. Peer cycling skips members for which this is false: a
    // rejected promise stays rejected forever (peers are never
    // respawned) and activate() refuses dead members without advancing
    // activeSessionIdentifier, so without the skip the user would
    // wedge on the dead member, never able to cycle past it.
    func isActivatable(identifier: String) -> Bool {
        guard let promise = peers[identifier] else { return false }
        return promise.maybeError == nil
    }

    // The swap inside sessionActivate can silently decline (PTYTab
    // refuses while a session-initiated resize holds the lock, and for
    // tmux clients), so verify the replacement actually landed in a
    // tab before recording it as the last real swap. Recording a
    // declined swap would make a later rollback restore a phantom:
    // activeSession would lie and reveal's rescue gate would skip the
    // member. Internal so tests can drive it directly — the swap
    // itself needs a real PTYTab.
    func recordSwapOutcome(identifier: String, replacement: PTYSession) {
        guard replacement.delegate != nil else {
            RLog("PTYSessionPeerPort: swap to \(identifier) did not take effect; not recording it as swapped")
            return
        }
        lastSwappedActiveIdentifier = identifier
    }

    // Invoked immediately after a peer's view is swapped into the tab
    // (visible iff that tab is the foreground one). Base does nothing;
    // iTermWorkgroupPeerPort overrides it to give a .diff peer's deferred
    // launch a chance to fire, which it does only once the peer is
    // actually shown.
    func didSwapInPeer(_ session: PTYSession) {}

    // Restores the last identifier whose view actually occupied the
    // tab after a committed activation that can never complete (spawn
    // rejected, or delegate gone at fulfillment with no restorable
    // anchor). Rolling back to a captured prior value would be wrong:
    // it could itself be aspirational (a superseded activation that
    // never swapped in).
    private func rollBackActivation() {
        RLog("PTYSessionPeerPort: rolling back activation to \(lastSwappedActiveIdentifier)")
        activeSessionIdentifier = lastSwappedActiveIdentifier
        activationDidRollBack(to: lastSwappedActiveIdentifier)
    }

    // Called after a committed activation is rolled back because the
    // swap could never run (see activate). Subclasses that mirrored
    // the commit into UI state (e.g. iTermWorkgroupPeerPort's mode
    // switchers, which highlight at commit time) override this to
    // re-sync to the restored identifier.
    func activationDidRollBack(to identifier: String) {
    }

    // The activate() swap needs some member with a live delegate to
    // anchor on. If none has one, the group's only in-tab member was
    // buried by the user — that member, unlike born-buried peers, IS
    // registered in iTermBuriedSessions — so restore it to give the
    // group back an in-tab anchor. Called from activate(identifier:)
    // at both commit and fulfillment time; no-op while a delegate is
    // live.
    private func disinterAnchorIfNeeded() {
        guard sessionDelegate == nil else {
            return
        }
        guard let anchor = realizedPeerSessions.first(where: { isBuried($0) }) else {
            RLog("PTYSessionPeerPort.disinterAnchorIfNeeded: no member of \(debugDescription) has a delegate and none is in iTermBuriedSessions; cannot restore an anchor")
            return
        }
        RLog("PTYSessionPeerPort.disinterAnchorIfNeeded: restoring buried member \(anchor.guid) so the peer group has an in-tab anchor")
        iTermBuriedSessions.sharedInstance().restore(anchor)
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
        RLog("PTYSessionPeerPort.invalidate: port=\(debugDescription) peerIDs=\(peers.keys.sorted())")
        invalidated = true
        for identifier in peers.keys where identifier != leader {
            peers[identifier]?.then {
                RLog("PTYSessionPeerPort.invalidate: terminating peer \(identifier) guid=\($0.guid) exited=\($0.exited)")
                $0.terminate()
            }
        }
        peers = [:]
    }
}

