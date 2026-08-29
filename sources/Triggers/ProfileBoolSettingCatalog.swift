//
//  ProfileBoolSettingCatalog.swift
//  iTerm2SharedARC
//
//  Single source of truth for the profile boolean settings that the "Set Profile Setting" trigger
//  action can target. Used by both SetProfileBooleanTrigger (for its row description) and
//  ProfileBoolSettingPickerView (for the searchable picker), so the two cannot drift.
//

import AppKit

enum ProfileBoolSettingCatalog {
    struct Entry {
        let key: String
        let label: String
        let pathComponents: [String]
    }

    /// The eligible profile boolean settings, sorted by label. Reuses the same source and safety
    /// gate as the "Toggle Setting" key action: registered profile checkbox controls that are not
    /// hiddenFromActions.
    ///
    /// Two deliberate exclusions:
    ///   - Title reporting (KEY_ALLOW_TITLE_REPORTING): a trigger fires on (possibly hostile)
    ///     terminal output, unlike a key binding, and title reporting echoes attacker-influenced
    ///     data back into the input stream, so its worst case is more than cosmetic.
    ///   - Inverted checkboxes (.invertedCheckbox): PLAIN checkboxes only. The trigger writes the
    ///     On/Off value verbatim to the raw profile key (triggerSideEffectSetSessionSpecificProfileBool
    ///     stores @(value)), so an inverted-checkbox item labeled e.g. "Allow window resizing" set
    ///     to On would store KEY_DISABLE_WINDOW_RESIZING=YES -- the opposite of the label. Until the
    ///     value is inverted per-setting, inverted checkboxes must not be offered.
    static func entries() -> [Entry] {
        let panel = PreferencePanel.sharedInstance()
        // allSettings() folds over the panel's tab views, which are nil until the window nib loads.
        // +sharedInstance does not force-load, so unless the user has opened the main Preferences
        // window this launch, allSettings() would be empty -- and this catalog is reached from
        // entry points that load a different panel (Add Trigger, Edit Session). Touch .window to
        // force the nib to load. Main-thread only (callers guarantee this: label(forKey:) falls
        // back off-main, and the picker builds groups on the main thread).
        _ = panel.window
        var result: [Entry] = []
        var seen = Set<String>()
        for setting in panel.allSettings() {
            guard setting.isProfile,
                  setting.info.type == .checkbox,
                  let key = setting.info.key,
                  key != KEY_ALLOW_TITLE_REPORTING,
                  let button = setting.info.control as? NSButton,
                  !button.hiddenFromActions,
                  !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            let label = button.accessibilityLabel() ?? button.title
            result.append(Entry(key: key, label: label, pathComponents: setting.pathComponents))
        }
        return result.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }
}
