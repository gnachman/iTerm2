//
//  ClaudeCodeWorkgroupTemplate.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/26.
//

import Foundation

// Factory for the Claude Code workgroup the onboarding installer installs
// into the user's iTermWorkgroupModel. After install it's just regular
// user data — editable in Settings, removable on uninstall — but the
// identifier strings stay stable so an Enter Workgroup trigger pointing
// at this ID keeps resolving across upgrades.
enum ClaudeCodeWorkgroupTemplate {
    // The strings start with "builtin." for backward compatibility:
    // pre-cleanup, this workgroup was a hardcoded built-in keyed off
    // these literals. Users who already had triggers or saved state
    // pointing at "builtin.claudeCode" must keep working.
    enum ID {
        static let workgroup = "builtin.claudeCode"
        static let main = "builtin.claudeCode.main"
        static let diff = "builtin.claudeCode.diff"
        static let review = "builtin.claudeCode.review"
    }

    // Defers the actual structure to the shared preset builder so the
    // installed workgroup and the user-pickable "Coding Agent + Diff +
    // Code Review" preset can't drift apart. Only IDs and the display
    // name diverge; everything else (commands, toolbar items, modes)
    // lives in WorkgroupPresets.
    static let config: iTermWorkgroup =
        WorkgroupPresets.buildCodingAgentPlusDiffPlusCodeReview(
            workgroupID: ID.workgroup,
            rootID: ID.main,
            diffID: ID.diff,
            reviewID: ID.review,
            name: "Claude Code")
}
