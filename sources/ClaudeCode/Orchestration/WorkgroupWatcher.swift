//
//  WorkgroupWatcher.swift
//  iTerm2SharedARC
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
// transitions into targetState. Carries the captured display names so
// the status_update message reads correctly even if the workgroup is
// torn down between registration and firing.
struct WorkgroupWatcher: Codable, Equatable {
    var watcherID: String
    var sessionGUID: String
    var workgroupID: String
    var workgroupName: String
    var roleID: String
    var roleName: String
    var targetState: SessionState
    var registeredAt: Date
    // Absent in watchers persisted before screen-poll watching existed;
    // decode-missing means the original tab-status behavior.
    var mode: WatchMode?

    var effectiveMode: WatchMode { mode ?? .tabStatus }
}
