import AppKit

@objc(iTermKeyMappingRepair)
class iTermKeyMappingRepair: NSObject {
    private static let mitigationDisabledKeyPrefix = "NoSyncKeyCode0MitigationDisabled_"

    @objc static func isMitigationDisabled(suffix: String) -> Bool {
        iTermUserDefaults.userDefaults().bool(forKey: mitigationDisabledKeyPrefix + suffix)
    }

    @objc static func setMitigationDisabled(_ disabled: Bool, suffix: String) {
        iTermUserDefaults.userDefaults().set(disabled, forKey: mitigationDisabledKeyPrefix + suffix)
    }

    /// Returns YES if the given serialized key binding has keycode 0 with a character
    /// that doesn't match what keycode 0 actually produces.
    @objc static func serializedKeyBindingHasCorruptedKeyCode0(_ serialized: String) -> Bool {
        let keystroke = iTermKeystroke(serialized: serialized)

        // Only 3-part format has hasVirtualKeyCode == true
        guard keystroke.hasVirtualKeyCode else {
            return false
        }

        // Only care about keycode 0
        guard keystroke.virtualKeyCode == 0 else {
            return false
        }

        // Get what keycode 0 actually produces (no modifiers)
        guard let expectedString = NSEvent.stringForKey(withKeycode: 0, modifiers: 0),
              !expectedString.isEmpty,
              let expectedScalar = expectedString.unicodeScalars.first else {
            // Couldn't determine, be conservative and assume not corrupted
            return false
        }

        // Compare case-insensitively
        let expectedChar = Character(expectedScalar).lowercased()
        let actualChar = Character(UnicodeScalar(keystroke.character) ?? UnicodeScalar(0)).lowercased()

        return expectedChar != actualChar
    }

    /// Returns an array of corrupted serialized key binding strings from a key mapping dictionary.
    @objc static func corruptedKeyBindings(in keyMappings: [String: Any]?) -> [String] {
        guard let keyMappings else {
            return []
        }
        return keyMappings.keys.filter { serializedKeyBindingHasCorruptedKeyCode0($0) }
    }

    /// Repair a key mapping dictionary by converting corrupted 3-component entries
    /// back to 2-component (legacy) format.
    @objc static func repairedKeyMappings(_ keyMappings: [String: Any]) -> [String: Any] {
        var repaired = keyMappings
        let corrupted = corruptedKeyBindings(in: keyMappings)

        for serialized in corrupted {
            guard let value = repaired[serialized] else {
                continue
            }
            repaired.removeValue(forKey: serialized)

            // Create the legacy 2-component format: "0x%x-0x%x" (character-modifierFlags)
            let keystroke = iTermKeystroke(serialized: serialized)
            let legacySerialized = String(format: "0x%x-0x%x", keystroke.character, Int32(keystroke.modifierFlags.rawValue))
            repaired[legacySerialized] = value
        }

        return repaired
    }

    /// Shows a confirmation dialog for repairing corrupted key bindings.
    /// Returns true if the user confirmed, false otherwise.
    @objc static func confirmRepair(keyMappings: [String: Any], window: NSWindow?) -> Bool {
        let corrupted = corruptedKeyBindings(in: keyMappings)
        guard !corrupted.isEmpty else {
            return false
        }

        // Format the list of affected key bindings based on character (not keycode, since it's wrong)
        let descriptions = corrupted.compactMap { serialized -> String? in
            let keystroke = iTermKeystroke(serialized: serialized)
            let keystrokeString = iTermKeystrokeFormatter.string(forKeystrokeIgnoringKeycode: keystroke)
            guard !keystrokeString.isEmpty else { return nil }

            // Get the action description
            guard let actionDict = keyMappings[serialized] as? [String: Any] else {
                return keystrokeString
            }
            let action = iTermKeyBindingAction.withDictionary(actionDict)
            let actionName = action?.displayName ?? String(localized: "KeyMappingRepair.UnknownAction", defaultValue: "Unknown action", comment: "Fallback shown for a key binding whose action cannot be identified")
            return String(localized: "KeyMappingRepair.BindingDescription", defaultValue: "\(keystrokeString): \(actionName)", comment: "A key binding description: keystroke followed by its action name")
        }

        let bindingsList = descriptions.sorted().map { "• \($0)" }.joined(separator: "\n")
        let count = corrupted.count
        // The whole intro varies by count (binding/bindings, was/were, displays/display, it/they), so
        // it is a single String Catalog plural on the count; the binding list is appended outside it
        // so the plural entry stays a simple single-argument plural (translators can add few/many).
        let intro = String(localized: "KeyMappingRepair.RepairIntro", defaultValue: "This will repair \(count) key bindings that were corrupted by a bug in an earlier version of iTerm2. The affected bindings currently display incorrectly but function properly. After repair, they will display correctly.\n\nAffected key bindings:", comment: "Repair explanation; %lld is the number of corrupted key bindings")
        let message = intro + "\n" + bindingsList

        let selection = iTermWarning.show(
            withTitle: message,
            actions: [String(localized: "KeyMappingRepair.Repair", defaultValue: "Repair", comment: "Button to repair corrupted key bindings"),
                      iTermLocalizedCancel()],
            identifier: nil,
            silenceable: .kiTermWarningTypePersistent,
            window: window
        )

        return selection == .kiTermWarningSelection0
    }
}
