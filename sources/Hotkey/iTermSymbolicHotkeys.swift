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
        let eventMods = modifiers.rawValue & relevantModifierMask
        for rawObj in dict.values {
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
                DLog("Found entry for keycode \(keyCode): \(parameters) and modifiers is \(modifiers.rawValue)")
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
