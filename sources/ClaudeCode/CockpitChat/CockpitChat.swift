//
//  CockpitChat.swift
//  iTerm2SharedARC
//

import Foundation

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
}
