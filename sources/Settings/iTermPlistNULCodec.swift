//
//  iTermPlistNULCodec.swift
//  iTerm2SharedARC
//
//  XML property lists cannot represent U+0000, not even as the character
//  reference &#0;, so writing user defaults that contain a NUL as XML fails.
//  That happens in practice: the characters NSEvent reports for Ctrl+Space
//  are a single NUL, and that is stored as a profile's hotkey characters.
//
//  Before writing XML, encode replaces each dictionary value that is a string
//  containing NUL with the same string minus its NULs, and records the
//  original's NUL-separated parts in a sidecar entry of that dictionary:
//
//      <key>HotKey Characters</key>
//      <string></string>
//      <key>iTermStringsWithNULs</key>
//      <dict>
//          <key>HotKey Characters</key>
//          <array><string></string><string></string></array>
//      </dict>
//
//  decode restores the original and removes the sidecar. Versions of iTerm2
//  that predate this see an ordinary string and ignore the extra key. If one
//  of them changes the value, the sidecar no longer matches it and decode
//  keeps the changed value.
//
//  A string with NULs that is directly inside an array has no key to attach
//  a sidecar to, so its NULs are dropped.
//

import Foundation

@objc(iTermPlistNULCodec)
final class PlistNULCodec: NSObject {
    static let sidecarKey = "iTermStringsWithNULs"
    private static let nul: Unicode.Scalar = "\u{0}"

    @objc(encodedDictionary:)
    static func encoded(_ dictionary: NSDictionary) -> NSDictionary {
        return encode(dictionary) as? NSDictionary ?? dictionary
    }

    @objc(decodedDictionary:)
    static func decoded(_ dictionary: NSDictionary) -> NSDictionary {
        return decode(dictionary) as? NSDictionary ?? dictionary
    }

    // Returns object itself when nothing beneath it needs to change.
    static func encode(_ object: Any) -> Any {
        return encodeIfNeeded(object) ?? object
    }

    // Returns object itself when nothing beneath it needs to change.
    static func decode(_ object: Any) -> Any {
        return decodeIfNeeded(object) ?? object
    }

    // MARK: - Private

    private static func containsNUL(_ string: String) -> Bool {
        return string.unicodeScalars.contains(nul)
    }

    private static func parts(_ string: String) -> [String] {
        return string.unicodeScalars.split(separator: nul, omittingEmptySubsequences: false).map {
            String(String.UnicodeScalarView($0))
        }
    }

    // The following return nil when nothing beneath object needs to change.

    private static func encodeIfNeeded(_ object: Any) -> Any? {
        switch object {
        case let dictionary as NSDictionary:
            return encodeDictionary(dictionary)
        case let array as NSArray:
            return mapElements(array) { element in
                if let string = element as? String {
                    guard containsNUL(string) else {
                        return nil
                    }
                    DLog("Dropping NULs from a string in an array")
                    return parts(string).joined()
                }
                return encodeIfNeeded(element)
            }
        default:
            return nil
        }
    }

    private static func encodeDictionary(_ dictionary: NSDictionary) -> NSDictionary? {
        var result: NSMutableDictionary?
        func mutable() -> NSMutableDictionary {
            if let result {
                return result
            }
            let copy = dictionary.mutableCopy() as! NSMutableDictionary
            result = copy
            return copy
        }

        // A stale sidecar (e.g., kept by an older version) is replaced, never carried forward.
        if dictionary[sidecarKey] != nil {
            mutable().removeObject(forKey: sidecarKey)
        }
        let sidecar = NSMutableDictionary()
        for (key, value) in dictionary {
            if let stringKey = key as? String, stringKey == sidecarKey {
                continue
            }
            if let string = value as? String {
                guard containsNUL(string), key is String else {
                    continue
                }
                let stringParts = parts(string)
                sidecar[key] = stringParts
                mutable()[key] = stringParts.joined()
            } else if let newValue = encodeIfNeeded(value) {
                mutable()[key] = newValue
            }
        }
        if sidecar.count > 0 {
            mutable()[sidecarKey] = sidecar
        }
        return result
    }

    private static func decodeIfNeeded(_ object: Any) -> Any? {
        switch object {
        case let dictionary as NSDictionary:
            return decodeDictionary(dictionary)
        case let array as NSArray:
            return mapElements(array, decodeIfNeeded)
        default:
            return nil
        }
    }

    private static func decodeDictionary(_ dictionary: NSDictionary) -> NSDictionary? {
        var result: NSMutableDictionary?
        func mutable() -> NSMutableDictionary {
            if let result {
                return result
            }
            let copy = dictionary.mutableCopy() as! NSMutableDictionary
            result = copy
            return copy
        }

        for (key, value) in dictionary {
            if let stringKey = key as? String, stringKey == sidecarKey {
                continue
            }
            if let newValue = decodeIfNeeded(value) {
                mutable()[key] = newValue
            }
        }
        guard let sidecarObject = dictionary[sidecarKey] else {
            return result
        }
        mutable().removeObject(forKey: sidecarKey)
        guard let sidecar = sidecarObject as? NSDictionary else {
            return result
        }
        for (key, value) in sidecar {
            guard let stringParts = value as? [String],
                  stringParts.count >= 2,
                  let current = dictionary[key] as? String,
                  (current as NSString).isEqual(to: stringParts.joined()) else {
                // Malformed, or the value changed after the sidecar was written.
                continue
            }
            mutable()[key] = stringParts.joined(separator: String(nul))
        }
        return result
    }

    private static func mapElements(_ array: NSArray, _ transform: (Any) -> Any?) -> NSArray? {
        var result: NSMutableArray?
        for (i, element) in array.enumerated() {
            guard let newElement = transform(element) else {
                continue
            }
            if result == nil {
                result = (array.mutableCopy() as! NSMutableArray)
            }
            result?[i] = newElement
        }
        return result
    }
}
