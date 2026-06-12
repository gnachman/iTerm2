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

    private struct Pending {
        weak var anchor: PTYSession?
        let descriptor: [AnyHashable: Any]
        // GUIDs of every session involved (anchor + embedded peers +
        // non-peer children) so the Enter Workgroup trigger can be
        // suppressed for all of them until reconstruction finishes.
        let guids: Set<String>
    }

    private var pending: [ObjectIdentifier: Pending] = [:]
    private var restoringGUIDs = Set<String>()
    private var observing = false

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
                                                    guids: guids)
        restoringGUIDs.formUnion(guids)
        startObservingIfNeeded()
    }

    @objc(isRestoringWithGuid:)
    func isRestoring(guid: String) -> Bool {
        return restoringGUIDs.contains(guid)
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
                pending.removeValue(forKey: key)
                restoringGUIDs.subtract(p.guids)
                continue
            }
            // Wait until the anchor is installed in a tab inside a real
            // window; reconstruction needs the tab for the leader and
            // for the eventual peer-swap.
            guard anchor.delegate != nil,
                  anchor.delegate?.realParentWindow() != nil else {
                continue
            }
            reconstruct(anchor: anchor, descriptor: p.descriptor)
            pending.removeValue(forKey: key)
            restoringGUIDs.subtract(p.guids)
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
            ?? ("wg-" + UUID().uuidString)
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
            DLog("WorkgroupRestoration: config \(workgroupID) is gone; peers not restored, anchor left standalone")
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
                guard let session = PTYSession(
                    fromArrangement: arrangement,
                    named: nil,
                    in: view,
                    with: nil,
                    for: .paneObject,
                    partialAttachments: nil,
                    options: nil) else {
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
            DLog("WorkgroupRestoration: leader \(leaderID) missing from restored members; degrading to anchor only")
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
        // re-find them by GUID so adopt can re-wire their toolbars.
        var nonPeerSessions: [String: PTYSession] = [:]
        if let nonPeers = descriptor[K.nonPeerChildren] as? [[AnyHashable: Any]] {
            for child in nonPeers {
                guard let configID = child[K.configID] as? String,
                      let guid = child[K.guid] as? String,
                      let s = iTermController.sharedInstance()?.session(withGUID: guid) else {
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
        // like the buried members. If it was a deferred peer still on its
        // pre-launch overlay at save time, normal restoration relaunched
        // its shell and dropped the overlay; re-present it here. The
        // reload variants restart the (now-running) shell on Start, which
        // is the right primitive for an already-live session.
        if (descriptor[K.anchorPending] as? Bool) ?? false,
           let cfg = workgroup.sessions.first(where: {
               $0.uniqueIdentifier == anchorID
           }) {
            anchor.workgroupSessionMode = cfg.mode
            switch cfg.mode {
            case .codeReview:
                anchor.codeReviewRawCommand = cfg.command
                anchor.reloadCodeReviewPromptOverlay()
            case .diff:
                anchor.reloadDiffWithDeferralIfNeeded()
            case .regular:
                break
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
