//
//  iTermKeyCodeZeroCharacters.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/4/26.
//

import AppKit
import Carbon.HIToolbox

// Virtual keycode 0 is kVK_ANSI_A, but older versions of iTerm2 also wrote 0 when the keycode
// was unknown. A three-part serialized keystroke ("0xchar-0xmods-0x0") is therefore ambiguous.
// This decides whether such a binding plausibly came from pressing the A key: its character must
// be one the A key can type, either a/A or whatever keycode 0 produces in an enabled keyboard
// layout (for example, q on AZERTY or ф on Russian).
@objc(iTermKeyCodeZeroCharacters)
class iTermKeyCodeZeroCharacters: NSObject {
    private static let lock = NSLock()
    private static var cachedCharacters: Set<UInt32>?
    private static var observer: NSObjectProtocol?

    // Tests set this to avoid depending on the machine's enabled keyboard layouts.
    @objc static var testingOverride: Set<NSNumber>?

    private static let alwaysPlausible: Set<UInt32> = [0x61, 0x41]  // a, A

    @objc(characterIsPlausibleForKeyCodeZero:modifiers:)
    static func characterIsPlausibleForKeyCodeZero(_ character: UInt32,
                                                   modifiers: NSEvent.ModifierFlags) -> Bool {
        if characterIsNeverPlausibleForKeyCodeZero(character, modifiers: modifiers) {
            return false
        }
        if characterIsAlwaysPlausibleForKeyCodeZero(character, modifiers: modifiers) {
            return true
        }
        if let testingOverride {
            return testingOverride.contains(NSNumber(value: character))
        }
        return layoutCharacters().contains(character)
    }

    /// True when the A key types this character on common layouts, regardless of which layouts
    /// are enabled.
    @objc(characterIsAlwaysPlausibleForKeyCodeZero:modifiers:)
    static func characterIsAlwaysPlausibleForKeyCodeZero(_ character: UInt32,
                                                         modifiers: NSEvent.ModifierFlags) -> Bool {
        return !modifiers.contains(.numericPad) && alwaysPlausible.contains(character)
    }

    /// True when no keyboard layout could make the A key produce this character: a function key
    /// (arrows, Home, Forward Delete, F1, and so on), a control character, or a numeric keypad key.
    @objc(characterIsNeverPlausibleForKeyCodeZero:modifiers:)
    static func characterIsNeverPlausibleForKeyCodeZero(_ character: UInt32,
                                                        modifiers: NSEvent.ModifierFlags) -> Bool {
        if modifiers.contains(.numericPad) {
            return true
        }
        if (0xF700...0xF8FF).contains(character) {
            return true
        }
        return character < 0x20 || character == 0x7f
    }

    private static func layoutCharacters() -> Set<UInt32> {
        lock.lock()
        let cached = cachedCharacters
        lock.unlock()
        if let cached {
            return cached
        }
        guard Thread.isMainThread else {
            // Text Input Sources must be queried on the main thread. Until the main thread has
            // filled the cache, only a and A are trusted. Untrusted bindings still match by
            // character, so this degrades gracefully.
            DLog("Keycode 0 layout characters requested off the main thread before caching")
            return []
        }
        let computed = computeLayoutCharacters()
        DLog("Characters keycode 0 produces in enabled layouts: \(computed)")
        lock.lock()
        cachedCharacters = computed
        lock.unlock()
        startObservingIfNeeded()
        return computed
    }

    private static func startObservingIfNeeded() {
        guard observer == nil else {
            return
        }
        let name = Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String)
        observer = DistributedNotificationCenter.default().addObserver(forName: name,
                                                                        object: nil,
                                                                        queue: .main) { _ in
            DLog("Enabled keyboard input sources changed; invalidating keycode 0 characters")
            lock.lock()
            cachedCharacters = nil
            lock.unlock()
        }
    }

    private static func computeLayoutCharacters() -> Set<UInt32> {
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        var result = Set<UInt32>()
        let shift = UInt32(shiftKey >> 8) & 0xff
        for source in list {
            guard let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
                continue
            }
            let data = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue() as Data
            for modifiers in [UInt32(0), shift] {
                if let c = translateKeyCodeZero(layoutData: data, modifiers: modifiers) {
                    result.insert(c)
                }
            }
        }
        return result
    }

    private static func translateKeyCodeZero(layoutData: Data, modifiers: UInt32) -> UInt32? {
        return layoutData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> UInt32? in
            guard let base = buffer.baseAddress else {
                return nil
            }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout,
                                        UInt16(kVK_ANSI_A),
                                        UInt16(kUCKeyActionDisplay),
                                        modifiers,
                                        UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                        &deadKeyState,
                                        chars.count,
                                        &length,
                                        &chars)
            guard status == noErr, length > 0 else {
                return nil
            }
            return String(utf16CodeUnits: chars, count: length).unicodeScalars.first?.value
        }
    }
}
