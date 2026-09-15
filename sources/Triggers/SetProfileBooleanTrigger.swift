//
//  SetProfileBooleanTrigger.swift
//  iTerm2SharedARC
//
//  A trigger action that sets a session-local profile boolean to a fixed On/Off value when the
//  trigger fires. Paired with the Job Started / Job Ended match types it gives declarative
//  "while this job runs" behavior, e.g. Job Started: claude -> Prevent sleep On, Job Ended:
//  claude -> Prevent sleep Off. The assertion itself is held by iTermSleepPreventionCoordinator,
//  which derives it from the live set of sessions with KEY_PREVENT_SLEEP enabled.
//

import AppKit
import Foundation

@objc(iTermSetProfileBooleanTrigger)
class SetProfileBooleanTrigger: Trigger {
    // param encodes <profile key>\u{1}<0|1> using the same codec as SetUserVariableTrigger.
    private func keyAndValue(_ param: String?) -> (key: String, value: Bool)? {
        guard let param, !param.isEmpty else { return nil }
        let (key, raw) = TwoParameterTriggerCodec.convert(string: param)
        guard !key.isEmpty else { return nil }
        return (key, raw == "1")
    }

    // Cache the key->label map once per trigger instance. `description` (via paramAttributedString)
    // runs per trigger row on every trigger-table reload, and ProfileBoolSettingCatalog.entries()
    // does a full allSettings() scan; caching avoids rescanning on each row render.
    private let labelsLock = NSLock()
    private var cachedLabelsByKey: [String: String]?

    // Resolve a friendly label for a profile key. IMPORTANT: `description` is also called off the
    // main thread -- Trigger.tryString runs on the trigger mutation queue and DLogs `self` with
    // %@, which invokes -description there. ProfileBoolSettingCatalog.entries() reads
    // main-thread-only AppKit (NSButton titles) via PreferencePanel.allSettings(), so it must only
    // be built on the main thread. Off-main we use any cache already built on main, else the raw
    // key (which is itself reasonably readable, e.g. "Prevent Sleep").
    private func label(forKey key: String) -> String {
        labelsLock.lock()
        let cached = cachedLabelsByKey
        labelsLock.unlock()
        if let cached {
            return cached[key] ?? key
        }
        guard Thread.isMainThread else {
            return key
        }
        var map: [String: String] = [:]
        for entry in ProfileBoolSettingCatalog.entries() {
            map[entry.key] = entry.label
        }
        // Do NOT cache an empty map. entries() is empty until the shared Preferences window has
        // loaded; caching {} here would be non-nil and permanently short-circuit the rebuild,
        // leaving the row showing raw keys forever. Only memoize once a real result is available.
        if !map.isEmpty {
            labelsLock.lock()
            cachedLabelsByKey = map
            labelsLock.unlock()
        }
        return map[key] ?? key
    }

    // MARK: - Trigger overrides

    override static var title: String {
        return String(localized: "Trigger.SetProfileBoolean.Title", defaultValue: "Set Profile Setting…", comment: "Trigger action name: set a session-local profile boolean setting")
    }

    override var description: String {
        if let (key, value) = keyAndValue(param as? String) {
            return "Set “\(label(forKey: key))” to \(value ? "On" : "Off")"
        }
        return "Set Profile Setting"
    }

    override func takesParameter() -> Bool {
        return true
    }

    // Rendered by TriggerController as an iTermProfileBoolSettingPickerView (a searchable,
    // path-grouped setting picker plus an On/Off control).
    override func paramIsSettingPicker() -> Bool {
        return true
    }

    override var isIdempotent: Bool {
        // Setting a profile bool to the value it already has is a no-op, so re-firing is safe.
        return true
    }

    // A live session is required to hold the override; a session-ended event has nothing to set.
    override var allowedMatchTypes: Set<NSNumber> {
        var set: Set<NSNumber> = [NSNumber(value: iTermTriggerMatchType.regex.rawValue)]
        set.formUnion(EventTriggerMatchTypeHelper.allEventTypesExceptSessionEndedSet)
        return set
    }

    // MARK: - Display

    override func paramAttributedString() -> NSAttributedString? {
        return NSAttributedString(string: description, attributes: regularAttributes())
    }

    // MARK: - Action

    override func performAction(withCapturedStrings strings: [String],
                                capturedRanges: UnsafePointer<NSRange>,
                                in session: iTermTriggerSession,
                                onString s: iTermStringLine,
                                atAbsoluteLineNumber lineNumber: Int64,
                                useInterpolation: Bool,
                                stop: UnsafeMutablePointer<ObjCBool>) -> Bool {
        guard let (key, value) = keyAndValue(param as? String) else { return false }
        let scopeProvider = session.triggerSessionVariableScopeProvider(self)
        let scheduler = scopeProvider.triggerCallbackScheduler()
        scheduler.scheduleTriggerCallback {
            session.triggerSession(self, setSessionSpecificProfileBool: value, forKey: key)
        }
        return true
    }
}
