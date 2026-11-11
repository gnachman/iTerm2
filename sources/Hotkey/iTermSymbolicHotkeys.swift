//
//  iTermSymbolicHotkeys.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/23/25.
//

import Foundation

@objc
class iTermSymbolicHotkeys: NSObject {

    // Bits we care about when comparing an event's modifiers to those stored
    // for a symbolic hotkey. Excludes CapsLock, NumericPad (set automatically
    // by hardware, not part of a user-defined shortcut), and device-specific
    // (left/right) bits.
    private static let relevantModifierMask: UInt =
        NSEvent.ModifierFlags.shift.rawValue
        | NSEvent.ModifierFlags.control.rawValue
        | NSEvent.ModifierFlags.option.rawValue
        | NSEvent.ModifierFlags.command.rawValue
        | NSEvent.ModifierFlags.function.rawValue

    // IDs of the Shift variants of Mission Control (34), Application Windows
    // (35), Show Desktop (37), Dashboard (63), and Move left/right a space
    // (80/82). Each pairs with a base shortcut (32, 33, 36, 62, 79, 81) plus
    // Shift. They once ran the base action in slow motion but no longer do
    // anything, yet macOS leaves them enabled. Deferring to them made
    // Ctrl-Shift-Arrow a dead key. Issue 13202.
    private static let ignoredIDs: Set<String> = ["34", "35", "37", "63", "80", "82"]

    @objc(haveBoundKeyForKeycode:modifiers:)
    static func haveBoundKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard let userDefaults = UserDefaults(suiteName: "com.apple.symbolichotkeys") else {
            DLog("No user default for com.apple.symbolichotkeys")
            return false
        }
        guard let dict = userDefaults.object(forKey: "AppleSymbolicHotKeys") as? [AnyHashable: Any] else {
            DLog("AppleSymbolicHotKeys not in defaults")
            return false
        }
        return haveBoundKey(keyCode: keyCode, modifiers: modifiers, hotkeys: dict)
    }

    static func haveBoundKey(keyCode: UInt16,
                             modifiers: NSEvent.ModifierFlags,
                             hotkeys dict: [AnyHashable: Any]) -> Bool {
        let eventMods = modifiers.rawValue & relevantModifierMask
        for (key, rawObj) in dict {
            if ignoredIDs.contains("\(key)") {
                continue
            }
            guard let obj = rawObj as? [AnyHashable: Any] else {
                continue
            }
            guard let n = obj["enabled"] as? NSNumber, n.boolValue else {
                continue
            }
            guard let value = obj["value"] as? [AnyHashable: Any] else {
                continue
            }
            guard let parameters = value["parameters"] as? [Int],
                  parameters.count >= 3 else {
                continue
            }
            if parameters[1] == keyCode {
                DLog("Found entry \(key) for keycode \(keyCode): \(parameters) and modifiers is \(modifiers.rawValue)")
                // Exact match on the relevant modifier bits. Subset matching
                // would cause a hotkey for, e.g., Ctrl+Right to also fire on
                // Ctrl+Shift+Right. Issue 12859.
                let storedMods = UInt(clamping: parameters[2]) & relevantModifierMask
                if storedMods == eventMods {
                    return true
                }
            }
        }
        DLog("Return false")
        return false
    }
}
