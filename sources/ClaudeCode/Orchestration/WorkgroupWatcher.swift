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

    var effectiveMode: WatchMode { mode ?? .tabStatus }

    // Human-readable goal for log lines and status_update details:
    // "state 'idle'" or "condition 'emacs has exited'".
    var goalDescription: String {
        if let condition {
            return "condition '\(condition)'"
        }
        return "state '\(targetState?.rawValue ?? "unknown")'"
    }
}

enum SessionState: String, Codable {
    case idle
    case working
    case waiting
    case unknown   // emitted by dispatcher; not accepted as input
}
