//
//  EnterWorkgroupTrigger.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/25/26.
//

import Foundation

// Trigger that enters a workgroup on the matching session. The
// parameter is the target workgroup's uniqueIdentifier (stored as a
// String, never a free-form value — the popup constrains it to one
// of the configured or built-in workgroups). Useful for declarative
// entry: "when I see `claude>` in this profile's output, enter the
// Claude Code workgroup", without writing a job-monitor.
@objc(iTermEnterWorkgroupTrigger)
class EnterWorkgroupTrigger: Trigger {
    override static var title: String {
        return String(localized: "EnterWorkgroupTrigger_EnterWorkgroup", defaultValue: "Enter Workgroup…", comment: "User-visible message: Enter Workgroup…")
    }

    override var description: String {
        return String(format: String(localized: "EnterWorkgroupTrigger_EnterWorkgroup_FORMAT", defaultValue: "Enter Workgroup “%1$@”", comment: "Formatted user-facing text in description"), displayLabel(forID: effectiveID))
    }

    override func takesParameter() -> Bool {
        return true
    }

    override func paramIsPopupButton() -> Bool {
        return true
    }

    override var isIdempotent: Bool {
        // Re-entering an already-active workgroup is a no-op in the
        // controller, so the trigger is safe to fire repeatedly.
        return true
    }

    // Live session required — a session-ended event has nothing to
    // host the workgroup on.
    override var allowedMatchTypes: Set<NSNumber> {
        var set: Set<NSNumber> = [NSNumber(value: iTermTriggerMatchType.regex.rawValue)]
        set.formUnion(EventTriggerMatchTypeHelper.allEventTypesExceptSessionEndedSet)
        return set
    }

    // MARK: - Popup

    // The set of workgroups eligible for entry: everything the user
    // has configured (which now includes the Claude Code workgroup if
    // installed via the onboarding installer).
    private var availableWorkgroups: [iTermWorkgroup] {
        return iTermWorkgroupModel.instance.workgroups
    }

    // The trigger's `param` resolves to a workgroup UUID. Empty/nil
    // (the case right after the user changes the action type, since
    // the popup-default-selection in TriggerController doesn't write
    // back to the trigger) falls back to the first workgroup in the
    // sorted popup order — matching what the popup is visibly
    // showing the user. Without this fallback the table row reads
    // "(unset)" while the popup reads e.g. "Chat.
    private var effectiveID: String? {
        if let s = self.param as? String, !s.isEmpty {
            return s
        }
        return firstSortedWorkgroupID
    }

    private var firstSortedWorkgroupID: String? {
        guard let dict = menuItemsForPoupupButton() else { return nil }
        return objectsSortedByValue(inDict: dict).first as? String
    }

    private func displayLabel(forID id: String?) -> String {
        guard let id, !id.isEmpty else { return String(localized: "EnterWorkgroupTrigger_Unset", defaultValue: "(unset)", comment: "Text shown in displayLabel: (unset)") }
        if let wg = availableWorkgroups.first(where: { $0.uniqueIdentifier == id }) {
            return wg.name.isEmpty ? String(localized: "EnterWorkgroupTrigger_Untitled", defaultValue: "Untitled", comment: "Text shown in displayLabel: Untitled") : wg.name
        }
        return String(localized: "EnterWorkgroupTrigger_Missing", defaultValue: "(missing)", comment: "Text shown in displayLabel: (missing)")
    }

    override func menuItemsForPoupupButton() -> [AnyHashable: Any]? {
        var dict: [AnyHashable: Any] = [:]
        for wg in availableWorkgroups {
            let label = wg.name.isEmpty ? String(localized: "EnterWorkgroupTrigger_Untitled", defaultValue: "Untitled", comment: "Label text in menuItemsForPoupupButton") : wg.name
            dict[wg.uniqueIdentifier] = label
        }
        return dict
    }

    override func index(for object: Any?) -> Int {
        guard let dict = menuItemsForPoupupButton() else { return -1 }
        return objectsSortedByValue(inDict: dict).firstIndex { obj in
            (obj as? String) == (object as? String)
        } ?? -1
    }

    override func object(at index: Int) -> Any? {
        guard let dict = menuItemsForPoupupButton() else { return nil }
        let sorted = objectsSortedByValue(inDict: dict)
        guard index >= 0, index < sorted.count else { return nil }
        return sorted[index]
    }

    override func paramAttributedString() -> NSAttributedString? {
        return NSAttributedString(string: displayLabel(forID: effectiveID),
                                  attributes: regularAttributes())
    }

    // MARK: - Action

    override func performAction(withCapturedStrings strings: [String],
                                capturedRanges: UnsafePointer<NSRange>,
                                in session: iTermTriggerSession,
                                onString s: iTermStringLine,
                                atAbsoluteLineNumber lineNumber: Int64,
                                useInterpolation: Bool,
                                stop: UnsafeMutablePointer<ObjCBool>) -> Bool {
        guard let id = effectiveID, !id.isEmpty else { return false }
        let scopeProvider = session.triggerSessionVariableScopeProvider(self)
        let scheduler = scopeProvider.triggerCallbackScheduler()
        scheduler.scheduleTriggerCallback {
            session.triggerSession(self,
                                   enterWorkgroupWithIdentifier: id)
        }
        return true
    }
}
