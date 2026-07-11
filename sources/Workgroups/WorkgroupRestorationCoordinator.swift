//
//  WorkgroupRestorationCoordinator.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/4/26.
//

import Foundation

// Collects workgroup descriptors discovered during session restoration
// (one per peer-group anchor) and rebuilds the workgroup once the anchor
// session is installed in its tab/window. Restoration has two paths
// (system window restoration and the default-arrangement startup path)
// that complete at different times, so reconstructReadyAnchors() is
// idempotent and is driven from several points (see
// iTermApplicationDelegate). Anchors whose window isn't ready yet stay
// pending and are retried when iTermDidDecodeWindowRestorableState
// fires.
@objc(WorkgroupRestorationCoordinator)
final class WorkgroupRestorationCoordinator: NSObject {
    @objc(sharedInstance) static let shared = WorkgroupRestorationCoordinator()

    private final class Pending {
        weak var anchor: PTYSession?
        let descriptor: [AnyHashable: Any]
        // GUIDs of every session involved (anchor + embedded peers +
        // non-peer children) so the Enter Workgroup trigger can be
        // suppressed for all of them until reconstruction finishes.
        let guids: Set<String>
        // Monotonic timestamp (it_timeSinceBoot) so a wall-clock step
        // mid-restore can't distort the deadline.
        let registeredAt: TimeInterval
        // True once this entry's guids have been removed from the
        // counted restoring set, so a later drain (deadline then
        // dealloc, or deadline then reconstruct) can't decrement twice.
        var restoringGuidsReleased = false

        init(anchor: PTYSession,
             descriptor: [AnyHashable: Any],
             guids: Set<String>,
             registeredAt: TimeInterval) {
            self.anchor = anchor
            self.descriptor = descriptor
            self.guids = guids
            self.registeredAt = registeredAt
        }
    }

    private var pending: [ObjectIdentifier: Pending] = [:]
    // Counted multiset, not a plain Set: two overlapping descriptors
    // (restoring the same arrangement twice while it's in flight — the
    // saved-GUID collision adopt() handles) can both claim a GUID, and
    // draining one entry must not unblock a GUID the other still
    // claims. isRestoring(guid:) is true while the count is positive.
    private var restoringGUIDCounts = [String: Int]()
    private var observing = false

    // Test hook: number of pending entries still tracked. The soft
    // deadline (below) keeps an entry past its timeout so a slow
    // restore can still reconstruct, so "pending" and "blocking Enter
    // Workgroup" are distinct states a test may want to assert apart.
    var pendingCount: Int { pending.count }

    // How long a pending anchor may wait for its tab/window before the
    // coordinator gives up and releases its restoring GUIDs. The
    // refusal in iTermWorkgroupController.enter is keyed on those
    // GUIDs, so without a deadline an anchor that never gets installed
    // (e.g. an aborted arrangement decode whose session stays retained
    // by the undo-close machinery) would block Enter Workgroup for
    // every named session until relaunch. Internal so tests can
    // shorten it.
    var pendingReconstructionTimeout: TimeInterval = 30

    private override init() {
        super.init()
    }

    // MARK: - Registration

    @objc(registerWithAnchor:descriptor:)
    func register(anchor: PTYSession, descriptor: [AnyHashable: Any]) {
        var guids = Set<String>()
        guids.insert(anchor.guid)
        if let memberGUIDs = descriptor[iTermWorkgroupRestoration.Key.memberGUIDs] as? [String] {
            guids.formUnion(memberGUIDs)
        }
        if let nonPeers = descriptor[iTermWorkgroupRestoration.Key.nonPeerChildren] as? [[AnyHashable: Any]] {
            for child in nonPeers {
                if let g = child[iTermWorkgroupRestoration.Key.guid] as? String {
                    guids.insert(g)
                }
            }
        }
        pending[ObjectIdentifier(anchor)] = Pending(anchor: anchor,
                                                    descriptor: descriptor,
                                                    guids: guids,
                                                    registeredAt: NSDate.it_timeSinceBoot())
        for guid in guids {
            restoringGUIDCounts[guid, default: 0] += 1
        }
        startObservingIfNeeded()
        // Registration also happens on mid-session arrangement decodes
        // (open saved arrangement, undo-close, duplicate tab), which
        // none of the startup-time reconstruct callers cover. Schedule
        // a pass for the next tick, when the anchor is installed in its
        // tab. Without this the entry stays pending forever and its
        // GUIDs stay in restoringGUIDs, which permanently blocks
        // iTermWorkgroupController.enter for those sessions. Harmless
        // during startup restoration: reconstructReadyAnchors() is
        // idempotent and skips not-yet-ready anchors.
        DispatchQueue.main.async { [weak self] in
            self?.reconstructReadyAnchors()
        }
        // And one more pass just past the deadline, so a wedged entry
        // is guaranteed to drain even if no decode notification ever
        // fires again.
        DispatchQueue.main.asyncAfter(deadline: .now() + pendingReconstructionTimeout + 1) { [weak self] in
            self?.reconstructReadyAnchors()
        }
    }

    @objc(isRestoringWithGuid:)
    func isRestoring(guid: String) -> Bool {
        return (restoringGUIDCounts[guid] ?? 0) > 0
    }

    // True iff `session` is itself the anchor of a still-pending
    // restoration. The manual Enter Workgroup path keys its refusal on
    // this (object identity) rather than on isRestoring(guid:): a live,
    // unrelated session can share a GUID with a restoring descriptor
    // member (saved-with-contents sessions keep their GUIDs), and
    // refusing it would be a spurious regression of manual entry.
    func isRestoringAnchor(_ session: PTYSession) -> Bool {
        // Only while still blocking: a past-deadline entry is kept
        // (so a slow restore can still reconstruct) but has released
        // its GUIDs, so it must no longer refuse a manual enter.
        return pending.values.contains {
            $0.anchor === session && !$0.restoringGuidsReleased
        }
    }

    // Decrement the counted set for `p`'s guids, once. Idempotent so
    // the deadline (which releases but keeps the entry) and a later
    // removal can both call it without double-decrementing.
    private func releaseRestoringGUIDs(_ p: Pending) {
        guard !p.restoringGuidsReleased else { return }
        p.restoringGuidsReleased = true
        for guid in p.guids {
            guard let count = restoringGUIDCounts[guid] else { continue }
            if count <= 1 {
                restoringGUIDCounts[guid] = nil
            } else {
                restoringGUIDCounts[guid] = count - 1
            }
        }
    }

    // MARK: - Reconstruction

    // Safe to call repeatedly and from several restoration callbacks
    // (the restorable-state-controller completion, the post-restoration
    // block, the non-server branch, and the per-window decode
    // notification). Once an anchor is rebuilt it's removed from
    // `pending`, and reconstruct() additionally early-returns when the
    // anchor already has a workgroupInstance, so duplicate calls are
    // no-ops. We iterate a snapshot of the entries so removing from
    // `pending` mid-loop can't invalidate the iterator even if
    // reconstruct() were to re-enter.
    @objc
    func reconstructReadyAnchors() {
        for (key, p) in Array(pending) {
            guard let anchor = p.anchor else {
                // Anchor deallocated before we could rebuild — drop it.
                releaseRestoringGUIDs(p)
                pending.removeValue(forKey: key)
                continue
            }
            // Wait until the anchor is installed in a tab inside a real
            // window; reconstruction needs the tab for the leader and
            // for the eventual peer-swap. Readiness is checked BEFORE
            // the deadline so an anchor that became ready late (a slow
            // multi-window startup) is still rebuilt.
            guard anchor.delegate != nil,
                  anchor.delegate?.realParentWindow() != nil else {
                // Past the deadline and still not ready: release the
                // GUIDs (a soft limit — stop blocking Enter Workgroup
                // for every named session) but KEEP the entry, so if
                // the anchor's window finally installs later the
                // workgroup is still rebuilt rather than silently lost.
                // releaseRestoringGUIDs is idempotent, so re-running
                // this each pass is harmless.
                if NSDate.it_timeSinceBoot() - p.registeredAt >= pendingReconstructionTimeout,
                   !p.restoringGuidsReleased {
                    RLog("WorkgroupRestoration: anchor \(anchor.guid) not ready within \(pendingReconstructionTimeout)s; releasing \(p.guids.count) restoring GUIDs but still awaiting its window")
                    releaseRestoringGUIDs(p)
                }
                continue
            }
            reconstruct(anchor: anchor, descriptor: p.descriptor)
            releaseRestoringGUIDs(p)
            pending.removeValue(forKey: key)
        }
    }

    private func reconstruct(anchor: PTYSession,
                             descriptor: [AnyHashable: Any]) {
        let K = iTermWorkgroupRestoration.Key.self
        guard let workgroupID = descriptor[K.workgroupID] as? String,
              let leaderID = descriptor[K.leaderID] as? String,
              let anchorID = descriptor[K.anchorID] as? String else {
            return
        }
        let instanceID = (descriptor[K.instanceID] as? String)
            ?? iTermWorkgroupInstance.mintInstanceUniqueIdentifier()
        let gitBase = (descriptor[K.gitBase] as? String)
            ?? CCGitBaseSelectorItem.defaultBase

        // Cheap, member-independent guards FIRST, so the throwaway-
        // session cases below never deserialize peers we'd immediately
        // drop.
        //
        // Idempotency: a successful adopt sets workgroupInstance on every
        // member, including the anchor. If it's already set, another pass
        // rebuilt this workgroup — nothing to do.
        if anchor.workgroupInstance != nil {
            return
        }
        // Config may have been deleted or edited since quit. Without it
        // we can't build toolbars or the mode switcher, so we can't wire
        // a workgroup at all. The would-be peers are simply not restored
        // (their content is lost); the anchor remains a normal session.
        // We bail BEFORE deserializing the members so we don't create and
        // immediately abandon their sessions.
        guard let workgroup = iTermWorkgroupModel.instance.workgroup(uniqueIdentifier: workgroupID) else {
            RLog("WorkgroupRestoration: config \(workgroupID) is gone; peers not restored, anchor left standalone")
            return
        }

        // Recreate the embedded (buried) peer members from their saved
        // arrangements. The anchor is already a live restored session.
        var sessionsByConfigID: [String: PTYSession] = [anchorID: anchor]
        if let members = descriptor[K.members] as? [[AnyHashable: Any]] {
            for m in members {
                guard let configID = m[K.configID] as? String,
                      let arrangement = m[K.arrangement] as? [AnyHashable: Any] else {
                    continue
                }
                // A not-yet-started deferred peer (Code Review prompt /
                // Diff "waiting") has no live process and no meaningful
                // content. Skip deserialization: leaving it out of
                // peerSessions makes adopt spawn it fresh, which
                // re-presents its overlay. Deserializing instead would
                // spawn a stray shell with no overlay (the bug this
                // guards against).
                if (m[K.pending] as? Bool) ?? false {
                    continue
                }
                let frame = NSRectFromString((m[K.frame] as? String) ?? "")
                let view = SessionView(frame: frame)
                // A non-pending code-review/diff peer had a live program at
                // save time. If its program is gone we must not launch a
                // replacement (that would be a stray shell); leave its
                // restored last output on screen instead. Regular peers keep
                // the normal relaunch behavior.
                var options: [AnyHashable: Any]? = nil
                if let cfg = workgroup.session(withUniqueIdentifier: configID),
                   iTermWorkgroupRestoration.modeInhibitsRelaunch(cfg.mode) {
                    options = [PTYSessionArrangementOptionsInhibitRelaunch: true]
                }
                guard let session = PTYSession(
                    fromArrangement: arrangement,
                    named: nil,
                    in: view,
                    with: nil,
                    for: .paneObject,
                    partialAttachments: nil,
                    options: options) else {
                    continue
                }
                // Put it in buried state (textview disconnected, no
                // delegate). Safe on a tab-less session; mirrors
                // makeWorkgroupPeer. We deliberately don't add it to
                // iTermBuriedSessions — the peer-swap works without it,
                // matching live workgroup peers.
                session.bury()
                sessionsByConfigID[configID] = session
            }
        }

        guard let leaderSession = sessionsByConfigID[leaderID] else {
            // Corrupt descriptor: the leader isn't among the restored
            // members. We did build the other members above; terminate
            // them rather than leaking abandoned sessions, and degrade
            // gracefully to just the still-on-screen anchor.
            RLog("WorkgroupRestoration: leader \(leaderID) missing from restored members; degrading to anchor only")
            for (id, s) in sessionsByConfigID where id != anchorID {
                s.terminate()
            }
            return
        }

        // Peers passed to adopt = every member except the leader.
        var peerSessions: [String: PTYSession] = [:]
        for (id, s) in sessionsByConfigID where id != leaderID {
            peerSessions[id] = s
        }

        // Non-peer split/tab children restored normally into their tabs;
        // re-find them by GUID so adopt can re-wire their toolbars. The
        // workgroupInstance check skips candidates already owned by a
        // live workgroup: restored-with-contents sessions keep their
        // saved GUIDs, so restoring an arrangement while its workgroup
        // is still running can resolve a child GUID to the ORIGINAL
        // instance's pane (session lookup returns the first match);
        // adopting it would steal the back-pointer and let this copy's
        // teardown close the running workgroup's pane. (adopt() guards
        // this too; checking here avoids even offering the session.)
        var nonPeerSessions: [String: PTYSession] = [:]
        if let nonPeers = descriptor[K.nonPeerChildren] as? [[AnyHashable: Any]] {
            for child in nonPeers {
                guard let configID = child[K.configID] as? String,
                      let guid = child[K.guid] as? String,
                      let s = iTermController.sharedInstance()?.session(withGUID: guid),
                      s.workgroupInstance == nil else {
                    continue
                }
                nonPeerSessions[configID] = s
            }
        }

        iTermWorkgroupController.instance.adopt(
            workgroup: workgroup,
            leader: leaderSession,
            instanceUniqueIdentifier: instanceID,
            activeIdentifier: anchorID,
            gitBase: gitBase,
            peerSessionsByConfigID: peerSessions,
            nonPeerSessionsByConfigID: nonPeerSessions)

        // The anchor is the one peer that window restoration already
        // brought back as a live session, so it can't be "spawned fresh"
        // like the buried members.
        if let cfg = workgroup.session(withUniqueIdentifier: anchorID) {
            // Always restore the anchor's mode tag (and the code-review
            // raw command) so the reload / restart / toolbar affordance
            // matches a live workgroup. adopt() does this for restored
            // PEER members but not for the leader, and the anchor may be
            // the leader. Neither is persisted on the session arrangement.
            anchor.workgroupSessionMode = cfg.mode
            if cfg.mode == .codeReview {
                anchor.codeReviewRawCommand = cfg.command
            }
            // Only re-present the pre-launch overlay if it was showing at
            // save time. If it was, normal restoration relaunched the
            // anchor's shell and dropped the overlay; the reload variants
            // restart that now-running shell on Start. If it was NOT
            // showing, the anchor had a live program: we leave the restored
            // last output on screen, and if the program is gone
            // sessionFromArrangement already put the session in a
            // restartable exited state so the toolbar reload still works.
            if (descriptor[K.anchorPending] as? Bool) ?? false {
                switch cfg.mode {
                case .codeReview:
                    anchor.reloadCodeReviewPromptOverlay()
                case .diff:
                    anchor.reloadDiffWithDeferralIfNeeded()
                case .regular:
                    break
                }
            }
        }

        // Refresh the toolbar on the active (in-pane) session — the
        // leader may be buried and have no delegate.
        anchor.delegate?.sessionDidChangeDesiredToolbarItems(anchor)
    }

    // MARK: - Re-arm

    private func startObservingIfNeeded() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowRestorableStateDidDecode(_:)),
            name: .iTermDidDecodeWindowRestorableState,
            object: nil)
    }

    @objc
    private func windowRestorableStateDidDecode(_ notification: Notification) {
        reconstructReadyAnchors()
    }
}
