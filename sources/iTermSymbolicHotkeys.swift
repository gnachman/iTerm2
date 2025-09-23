//
//  iTermSymbolicHotkeys.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/23/25.
//

import Foundation

@objc
class iTermSymbolicHotkeys: NSObject {

    @objc(haveBoundKeyForKeycode:modifiers:)
    static func haveBoundKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard let userDefaults = UserDefaults(suiteName: "com.apple.symbolichotkeys") else {
            return false
        }
        guard let dict = userDefaults.object(forKey: "AppleSymbolicHotKeys") as? [AnyHashable: Any] else {
            return false
        }
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
            if parameters[1] == keyCode && UInt(clamping: parameters[2]) & modifiers.rawValue == UInt(clamping: parameters[2]) {
                return true
            }
        }
        return false
    }
}
