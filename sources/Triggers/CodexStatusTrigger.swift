//
//  CodexStatusTrigger.swift
//  iTerm2SharedARC
//
//  Built-in title-changed trigger that drives the Codex tab-status shim.
//  Codex (OpenAI) does not emit OSC 21337; it signals working state with a
//  braille-spinner prefix on the terminal title. This trigger rides the
//  "Title Changed" event so the shim is part of the trigger system rather
//  than a hardcoded hook. It is seeded as an always-on built-in by
//  EventTriggerEvaluator and is not user-editable; the generic Title Changed
//  trigger is the configurable counterpart. Detection/policy live in
//  CodexTitleStatusDecoder + CodexTitleStatusAdaptor, applied on the session
//  side via triggerSession(_:applyCodexTitleStatusWithTitle:) so the
//  synthesized-status ownership guarantees are preserved.
//

import Foundation

@objc(iTermCodexStatusTrigger)
class CodexStatusTrigger: Trigger {
    override static var title: String {
        return "Codex Status"
    }

    override var description: String {
        return "Codex Status"
    }

    override func takesParameter() -> Bool {
        return false
    }

    override var isIdempotent: Bool {
        return true
    }

    override var allowedMatchTypes: Set<NSNumber> {
        return [NSNumber(value: iTermTriggerMatchType.eventTitleChanged.rawValue)]
    }

    override func performAction(withCapturedStrings strings: [String],
                                capturedRanges: UnsafePointer<NSRange>,
                                in session: iTermTriggerSession,
                                onString s: iTermStringLine,
                                atAbsoluteLineNumber lineNumber: Int64,
                                useInterpolation: Bool,
                                stop: UnsafeMutablePointer<ObjCBool>) -> Bool {
        let title = strings.first ?? ""
        let scopeProvider = session.triggerSessionVariableScopeProvider(self)
        let scheduler = scopeProvider.triggerCallbackScheduler()
        scheduler.scheduleTriggerCallback {
            session.triggerSession(self, applyCodexTitleStatusWithTitle: title)
        }
        return true
    }
}
