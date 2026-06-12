//
//  ExitWorkgroupTrigger.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/25/26.
//

import Foundation

// Trigger that exits the active workgroup on the matching session.
// Useful as the counterpart to EnterWorkgroupTrigger — e.g. fire
// "Job Ended: claude" → Exit Workgroup so the workgroup tears down
// when claude finishes.
@objc(iTermExitWorkgroupTrigger)
class ExitWorkgroupTrigger: Trigger {
    // Key under which the leader-only flag is stored in the trigger's
    // eventParams. Shared with the editor UI and the Claude Code installer.
    @objc static let leaderOnlyParamKey = "leaderOnly"

    override static var title: String {
        return "Exit Workgroup"
    }

    override var description: String {
        return "Exit Workgroup"
    }

    override func takesParameter() -> Bool {
        return false
    }

    override var isIdempotent: Bool {
        return true
    }

    override var hasLeaderOnlyOption: Bool {
        return true
    }

    // When true, exiting only happens if this trigger fired on the workgroup
    // leader (main session). The claude-code installer sets this so a peer
    // (Code Review, Diff) whose own claude ends or reloads doesn't tear down
    // the whole workgroup. Stored in eventParams so it round-trips with the
    // rest of the trigger's serialized configuration. Defaults to false, which
    // preserves the legacy behavior of exiting from whichever session matched.
    @objc var leaderOnly: Bool {
        return (eventParams?[Self.leaderOnlyParamKey] as? NSNumber)?.boolValue ?? false
    }

    // Live session required to exit a workgroup on it.
    override var allowedMatchTypes: Set<NSNumber> {
        var set: Set<NSNumber> = [NSNumber(value: iTermTriggerMatchType.regex.rawValue)]
        set.formUnion(EventTriggerMatchTypeHelper.allEventTypesExceptSessionEndedSet)
        return set
    }

    override func performAction(withCapturedStrings strings: [String],
                                capturedRanges: UnsafePointer<NSRange>,
                                in session: iTermTriggerSession,
                                onString s: iTermStringLine,
                                atAbsoluteLineNumber lineNumber: Int64,
                                useInterpolation: Bool,
                                stop: UnsafeMutablePointer<ObjCBool>) -> Bool {
        let scopeProvider = session.triggerSessionVariableScopeProvider(self)
        let scheduler = scopeProvider.triggerCallbackScheduler()
        let leaderOnly = self.leaderOnly
        scheduler.scheduleTriggerCallback {
            session.triggerSessionExitWorkgroup(self, leaderOnly: leaderOnly)
        }
        return true
    }
}
