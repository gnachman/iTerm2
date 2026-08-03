//
//  iTermWorkgroupRestoration.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/4/26.
//

import Foundation

// Facade that owns the on-disk schema for restoring a workgroup peer
// group across an app relaunch. PTYSession stores exactly one opaque
// arrangement key (SESSION_ARRANGEMENT_WORKGROUP) whose value this type
// produces (encodeState) and whose decoding it routes
// (registerForRestoration). Keeping the schema here means future
// additions to persisted workgroup state never touch PTYSession's
// encode/decode paths.
//
// The descriptor is anchored on whichever peer-group member is visible
// in its split pane at save time (the "anchor"), since that's the
// session window restoration reliably brings back. The OTHER members
// (which are buried, and otherwise not persisted at all) are embedded
// as full session arrangements. Non-peer split/tab children are
// recorded by GUID; they restore on their own and are re-found and
// re-wired at reconstruction time.
@objc(iTermWorkgroupRestoration)
final class iTermWorkgroupRestoration: NSObject {
    enum Key {
        static let workgroupID = "workgroupID"
        static let instanceID = "instanceID"
        static let gitBase = "gitBase"
        static let leaderID = "leaderID"
        static let anchorID = "anchorID"
        static let members = "members"
        static let memberGUIDs = "memberGUIDs"
        static let nonPeerChildren = "nonPeerChildren"
        // True when the anchor itself is a deferred peer still showing
        // its pre-launch overlay (Code Review prompt / Diff "waiting for
        // changes") at save time.
        static let anchorPending = "anchorPending"
        // member / nonPeerChild sub-keys
        static let configID = "configID"
        static let displayName = "displayName"
        static let frame = "frame"
        static let arrangement = "arrangement"
        static let guid = "guid"
        // True for a member that is a deferred peer still showing its
        // pre-launch overlay (never started). Such a peer has no live
        // process or meaningful content, so restore re-creates it fresh
        // (which re-presents the overlay) rather than adopting its
        // arrangement, which would otherwise spawn a stray shell with no
        // overlay.
        static let pending = "pending"
    }

    // A deferred peer that hasn't been started yet is sitting on its
    // pre-launch overlay: the Code Review prompt panel, or the Diff
    // "waiting for changes" panel (or has a queued diff launch). Such a
    // session must be re-created fresh on restore, not adopted.
    static func isShowingPreLaunchOverlay(_ session: PTYSession) -> Bool {
        if session.view?.codeReviewPromptOverlay != nil { return true }
        if session.view?.diffWaitingPromptOverlay != nil { return true }
        if session.hasPendingDiffLaunch { return true }
        return false
    }

    // Re-entrancy guard. Embedding a member's arrangement runs
    // PTYSession.encodeArrangement, which calls back into encodeState;
    // returning nil while embedding stops a member from recursively
    // embedding its siblings. Main-queue only, so a plain Bool is safe.
    private static var isEmbedding = false

    // Produce the workgroup descriptor for `session`, or nil when the
    // session isn't a peer-group member (the common case). Called from
    // PTYSession.encodeArrangementWithContents:.
    @objc(encodeStateForSession:includeContents:)
    static func encodeState(forSession session: PTYSession,
                            includeContents: Bool) -> [AnyHashable: Any]? {
        if isEmbedding { return nil }
        guard let port = session.peerPort as? iTermWorkgroupPeerPort,
              let instance = session.workgroupInstance,
              let anchorID = port.identifier(for: session) else {
            return nil
        }

        isEmbedding = true
        defer { isEmbedding = false }

        var members: [[AnyHashable: Any]] = []
        var memberGUIDs: [String] = []
        for member in port.realizedMembers where member.id != anchorID {
            let dict = NSMutableDictionary()
            let encoder = iTermMutableDictionaryEncoderAdapter(mutableDictionary: dict)
            member.session.encodeArrangement(withContents: includeContents,
                                             encoder: encoder)
            let frame = member.session.view?.frame ?? .zero
            let displayName = instance.workgroup.sessions
                .first { $0.uniqueIdentifier == member.id }?
                .displayName ?? ""
            members.append([
                Key.configID: member.id,
                Key.displayName: displayName,
                Key.frame: NSStringFromRect(frame),
                Key.arrangement: dict,
                Key.pending: Self.isShowingPreLaunchOverlay(member.session)
            ])
            memberGUIDs.append(member.session.guid)
        }

        var result: [AnyHashable: Any] = [
            Key.workgroupID: instance.workgroupUniqueIdentifier,
            Key.instanceID: instance.instanceUniqueIdentifier,
            Key.gitBase: instance.currentGitBase,
            Key.leaderID: port.leaderIdentifier,
            Key.anchorID: anchorID,
            Key.members: members,
            Key.memberGUIDs: memberGUIDs,
            Key.anchorPending: Self.isShowingPreLaunchOverlay(session)
        ]

        // Only the instance's primary (top-level) peer group records the
        // instance-wide non-peer split/tab children, so a nested peer
        // group saved in the same window doesn't double-record them.
        if port === instance.peerPort {
            let nonPeers = instance.leafNonPeerChildren.map { child in
                return [Key.configID: child.configID,
                        Key.guid: child.session.guid]
            }
            if !nonPeers.isEmpty {
                result[Key.nonPeerChildren] = nonPeers
            }
        }

        return result
    }

    // Whether restoration should refrain from launching a replacement
    // program for the anchor session described by `state` when there is
    // no running program to attach to. True only for a code-review or
    // diff workgroup session that had a live program at save time (i.e.
    // was NOT sitting on its pre-launch overlay): relaunching such a
    // session would spawn a stray shell, so instead we leave the restored
    // last output on screen. When the anchor WAS showing its overlay
    // (anchorPending), the coordinator re-presents it and relies on the
    // relaunched shell, so we must not suppress the launch then.
    @objc(shouldInhibitRelaunchForAnchorState:)
    static func shouldInhibitRelaunch(forAnchorState state: [AnyHashable: Any]) -> Bool {
        return shouldInhibitRelaunch(forAnchorState: state) {
            iTermWorkgroupModel.instance.workgroup(uniqueIdentifier: $0)
        }
    }

    // Injectable-model variant so tests can classify an anchor without
    // touching the shared iTermWorkgroupModel singleton (whose mutators
    // persist to user defaults and post change notifications).
    static func shouldInhibitRelaunch(forAnchorState state: [AnyHashable: Any],
                                      workgroupForID: (String) -> iTermWorkgroup?) -> Bool {
        let K = Key.self
        guard let workgroupID = state[K.workgroupID] as? String,
              let anchorID = state[K.anchorID] as? String,
              let workgroup = workgroupForID(workgroupID),
              let cfg = workgroup.session(withUniqueIdentifier: anchorID) else {
            return false
        }
        if (state[K.anchorPending] as? Bool) ?? false {
            return false
        }
        return modeInhibitsRelaunch(cfg.mode)
    }

    // Single source of truth for which workgroup modes suppress the
    // stray-shell relaunch when a restored session has no program to
    // attach to. The anchor path (shouldInhibitRelaunch(forAnchorState:))
    // and the buried-peer path (WorkgroupRestorationCoordinator) are two
    // halves of the same feature and must agree, so both call this.
    static func modeInhibitsRelaunch(_ mode: iTermWorkgroupSessionMode) -> Bool {
        switch mode {
        case .codeReview, .diff:
            return true
        case .regular:
            return false
        }
    }

    // Route a decoded descriptor to the coordinator. Called from
    // PTYSession.sessionFromArrangement.
    @objc(registerForRestorationWithSession:state:)
    static func registerForRestoration(session: PTYSession,
                                       state: [AnyHashable: Any]) {
        WorkgroupRestorationCoordinator.shared.register(anchor: session,
                                                        descriptor: state)
    }

    // True while `guid` belongs to a workgroup that is mid-restore, so
    // the Enter Workgroup trigger can no-op instead of spawning a
    // duplicate workgroup on a replayed/reattached shell.
    @objc(isRestoringWithGuid:)
    static func isRestoring(guid: String) -> Bool {
        return WorkgroupRestorationCoordinator.shared.isRestoring(guid: guid)
    }
}
