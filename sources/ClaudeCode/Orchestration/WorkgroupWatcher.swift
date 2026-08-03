//
//  WorkgroupWatcher.swift
//  iTerm2SharedARC
//

//  NOTE: This file is also compiled into the iTerm2 Companion iOS app. Keep it
//  platform-neutral (Foundation only).
//

import Foundation

// How a watcher detects that its session reached targetState.
enum WatchMode: String, Codable {
    // The session reports machine-readable status (OSC 21337 / the
    // cc-status hook). Fires off iTermSessionTabStatus transitions —
    // free, exact, the default.
    case tabStatus
    // The session reports no status, so doneness can only be judged by
    // reading the rendered screen. A headless AI poller (ScreenWatchPoller)
    // watches the screen and fires when it decides the target is reached
    // or when it gives up after a time cap.
    case screenPoll
}

// A registered async watcher. Fires once when sessionGUID's role
// satisfies the watcher's goal: either a transition into targetState,
// or (for condition watchers) a plain-English condition judged true by
// reading the screen. Carries the captured display names so
// the status_update message reads correctly even if the workgroup is
// torn down between registration and firing.
//
// Exactly one of targetState / condition is set. targetState was
// non-optional before condition watchers existed, so every persisted
// pre-condition watcher decodes with targetState present and
// condition absent.
struct WorkgroupWatcher: Codable, Equatable {
    var watcherID: String
    // The session this watcher targets, identified by a reload-durable
    // reference: the session's stableID for watchers registered under
    // reference keying, or a raw guid for watchers persisted before it.
    // Match through `targets(stableID:guid:)`, never a bare `==`: a
    // stableID-keyed watcher must follow an in-place shell reload (which
    // rotates the guid but keeps the stableID), while a legacy guid-keyed
    // watcher still matches its original session. The field name is historical.
    var sessionGUID: String
    var workgroupID: String
    var workgroupName: String
    var roleID: String
    var roleName: String
    var targetState: SessionState?
    var registeredAt: Date
    // Absent in watchers persisted before screen-poll watching existed;
    // decode-missing means the original tab-status behavior.
    var mode: WatchMode?
    // Plain-English condition judged by screen observation (always
    // mode == .screenPoll). nil for state watchers.
    var condition: String?
    // The user asked to be told when this fires: iTerm2 sends a push
    // notification to the paired phone itself rather than hoping the
    // model decides to. Absent in watchers persisted before push
    // support existed.
    var notifyUser: Bool? = nil

    // Set true when this (session-bound, screen-reading) watch was armed while
    // View Contents was "Ask" and the user gave the one-time consent prompt.
    // It records that repeated background screen reads are allowed to continue
    // under Ask. nil means the watch never needed it -- it was armed under
    // "Always" (or reads no screen), so it holds no standing Ask consent and
    // must stop if View Contents is later downgraded to Ask. Absent in watchers
    // persisted before the consent prompt existed (treated as no consent).
    var screenReadConsented: Bool? = nil

    var effectiveMode: WatchMode { mode ?? .tabStatus }

    // Which read categories this watch's mechanism uses, derived from its frozen
    // shape via the single policy below so registration and runtime enforcement
    // can't drift.
    var readRequirement: (needsScreen: Bool, needsState: Bool) {
        return Self.readRequirement(hasCondition: condition != nil,
                                    hasTargetState: targetState != nil,
                                    isScreenPoll: effectiveMode == .screenPoll)
    }

    // THE read-category policy, on booleans, so every site derives from one
    // source: the registration gate (OrchestratorDispatcher.watchReadRequirement),
    // the runtime instance property above, and the offer/guidance
    // (watchFormSatisfiable). A screen-poll mechanism reads the screen (View
    // Contents); condition watches always do. A target_state watch reports the
    // session's state (Check Terminal State); a condition watch reports only a
    // screen condition.
    static func readRequirement(hasCondition: Bool,
                                hasTargetState: Bool,
                                isScreenPoll: Bool) -> (needsScreen: Bool, needsState: Bool) {
        return (needsScreen: hasCondition || isScreenPoll,
                needsState: hasTargetState)
    }

    // THE mode decision: a watch is judged by reading the screen (screen-poll)
    // when a plain-English condition was supplied, or when the session reports no
    // machine-readable status (so there is no tab-status transition to fire on).
    // Shared by doRegisterWatch (which mode to create) and watchReadRequirement
    // (which reads that mode implies) so the two can't disagree.
    static func isScreenPollMode(hasCondition: Bool, sessionReportsStatus: Bool) -> Bool {
        return hasCondition || !sessionReportsStatus
    }

    // Human-readable goal for log lines and status_update details:
    // "state 'idle'" or "condition 'emacs has exited'".
    var goalDescription: String {
        if let condition {
            return "condition '\(condition)'"
        }
        return "state '\(targetState?.rawValue ?? "unknown")'"
    }

    // Whether this watcher targets the session identified by `stableID` (its
    // reload-durable id, nil when the session can't be resolved) and `guid`
    // (its current, rotating id). A watcher keyed on the stableID follows a
    // shell reload; a legacy watcher keyed on a guid matches only its original
    // (unrotated) session. Comparing against both covers both keyings and is
    // the single chokepoint through which every watcher/session match runs.
    func targets(stableID: String?, guid: String) -> Bool {
        if let stableID, sessionGUID == stableID {
            return true
        }
        return sessionGUID == guid
    }
}

enum SessionState: String, Codable {
    case idle
    case working
    case waiting
    case unknown   // emitted by dispatcher; not accepted as input
}
