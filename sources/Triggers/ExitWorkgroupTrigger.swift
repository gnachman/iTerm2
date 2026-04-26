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
        scheduler.scheduleTriggerCallback {
            session.triggerSessionExitWorkgroup(self)
        }
        return true
    }
}
