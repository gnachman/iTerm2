//
//  CompanionKeyInjection.swift
//  iTerm2SharedARC
//
//  Translates a wire-level CompanionKeyEvent (from the companion app's on-screen
//  keyboard) into the AppKit key-down event(s) that -[PTYSession
//  injectSynthesizedKeyEvent:literalText:] runs through the session's own key mapper.
//  Keeping the AppKit dependency here (rather than in the shared CompanionMessages
//  file, which also compiles into the iOS app) is what lets the wire type stay
//  platform-neutral.
//
//  Fidelity matters because the session's mapper may be the modern (Kitty) mapper
//  when a full-screen app has enabled a CSI-u key-reporting mode (disambiguate
//  escape, report all keys as escape codes, report event types, etc.). That mapper
//  is driven ENTIRELY by the event's virtual key code: FunctionalKeyDefinition,
//  the unicode-key-code, the CSI u number, and the base-layout key code all derive
//  from `keyCode`. So a synthesized event must carry the real kVK_* code, not 0, or
//  those modes encode garbage. We therefore map every special key to its physical
//  key code and reverse-map printable ASCII to its US-QWERTY key code (plus the
//  Shift it would need). Left/right Option ride the device-dependent modifier bits
//  so the profile's per-side Option behavior is honored.
//

import AppKit
import Carbon.HIToolbox

extension CompanionKeyModifiers {
    /// The AppKit modifier flags equivalent. Option is emitted as both the
    /// device-independent .option and the device-dependent side bit so it satisfies
    /// every mapper's right-vs-left test (some check NSRightAlternateKeyMask, which
    /// is 0x40 | option; others check the bare side bit).
    var eventModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if control {
            flags.insert(.control)
        }
        if shift {
            flags.insert(.shift)
        }
        if leftOption {
            flags.formUnion([.option, .leftOption])
        }
        if rightOption {
            flags.formUnion([.option, .rightOption])
        }
        return flags
    }
}

extension CompanionSpecialKey {
    /// The characters the key reports (as a physical press would), its physical US
    /// virtual key code, and whether it is a function/arrow key. The key code is
    /// what makes the modern (CSI-u) mapper recognize it as a FunctionalKeyDefinition;
    /// the .function modifier (for the function-key group) is what routes it through
    /// VT100Output in the legacy mapper.
    ///
    /// These key codes must stay consistent with iTermModernKeyMapper's
    /// `FunctionalKeyDefinition(virtualKeyCode:)` (the CSI-u authority) and the
    /// `specialKeys` table in iTermKeystroke.m. They are fixed macOS virtual key codes
    /// that do not change; kept as an explicit switch here (rather than sharing that
    /// private ObjC table) because the enum-to-keycode shape differs and the set is
    /// small and stable.
    fileprivate var keySpec: (characters: String, keyCode: Int, isFunctionKey: Bool) {
        func functionKey(_ code: Int) -> String {
            return String(UnicodeScalar(UInt16(code))!)
        }
        switch self {
        case .escape:
            return ("\u{1b}", kVK_Escape, false)
        case .tab:
            return ("\t", kVK_Tab, false)
        case .backspace:
            // The delete-left key. It carries kVK_Delete so the profile's "Delete key
            // sends ^H" key binding (applied on the real keyDown path injection now
            // routes through) matches and can substitute ^H for the usual ^?.
            return ("\u{7f}", kVK_Delete, false)
        case .forwardDelete:
            return (functionKey(NSDeleteFunctionKey), kVK_ForwardDelete, true)
        case .up:
            return (functionKey(NSUpArrowFunctionKey), kVK_UpArrow, true)
        case .down:
            return (functionKey(NSDownArrowFunctionKey), kVK_DownArrow, true)
        case .left:
            return (functionKey(NSLeftArrowFunctionKey), kVK_LeftArrow, true)
        case .right:
            return (functionKey(NSRightArrowFunctionKey), kVK_RightArrow, true)
        case .home:
            return (functionKey(NSHomeFunctionKey), kVK_Home, true)
        case .end:
            return (functionKey(NSEndFunctionKey), kVK_End, true)
        case .pageUp:
            return (functionKey(NSPageUpFunctionKey), kVK_PageUp, true)
        case .pageDown:
            return (functionKey(NSPageDownFunctionKey), kVK_PageDown, true)
        case .insert:
            return (functionKey(NSInsertFunctionKey), kVK_Help, true)   // Help == Insert on the mac
        case .f1: return (functionKey(NSF1FunctionKey), kVK_F1, true)
        case .f2: return (functionKey(NSF2FunctionKey), kVK_F2, true)
        case .f3: return (functionKey(NSF3FunctionKey), kVK_F3, true)
        case .f4: return (functionKey(NSF4FunctionKey), kVK_F4, true)
        case .f5: return (functionKey(NSF5FunctionKey), kVK_F5, true)
        case .f6: return (functionKey(NSF6FunctionKey), kVK_F6, true)
        case .f7: return (functionKey(NSF7FunctionKey), kVK_F7, true)
        case .f8: return (functionKey(NSF8FunctionKey), kVK_F8, true)
        case .f9: return (functionKey(NSF9FunctionKey), kVK_F9, true)
        case .f10: return (functionKey(NSF10FunctionKey), kVK_F10, true)
        case .f11: return (functionKey(NSF11FunctionKey), kVK_F11, true)
        case .f12: return (functionKey(NSF12FunctionKey), kVK_F12, true)
        }
    }
}

/// Reverse map from a printable character to the physical key code (and whether
/// Shift is needed) that produces it on the mac's CURRENTLY ACTIVE keyboard layout.
///
/// Why the active layout and not a fixed US table: the modern (CSI-u) mapper derives
/// the unicode-key-code and base-layout key code from the event's key code by running
/// it back through the mac's keyboard layout. The phone gives us a character (typed
/// under the iOS layout, which is just the user's intent); to make that round-trip
/// correctly we must choose the key code that the MAC's active layout maps to that
/// character. That reverse mapping (and its input-source-keyed cache) already lives
/// in `NSEvent.keyDown(forCharacter:)`, which we reuse below rather than duplicate.
extension CompanionKeyEvent {
    /// The AppKit key-down event(s) to inject through a session's key mapper. A
    /// `.text` run becomes one event per character (so the mapper - including the
    /// per-key CSI-u modern mapper - sees each keypress), a `.special` key becomes a
    /// single event. Empty text yields no events.
    func makeKeyDownEvents() -> [NSEvent] {
        switch key {
        case .special(let special):
            let spec = special.keySpec
            var flags = modifiers.eventModifierFlags
            if spec.isFunctionKey {
                flags.insert(.function)
            }
            return [Self.makeEvent(characters: spec.characters,
                                   charactersIgnoringModifiers: spec.characters,
                                   flags: flags,
                                   keyCode: spec.keyCode)].compactMap { $0 }
        case .text(let text):
            let deadKeyFlags = modifiers.eventModifierFlags   // loop-invariant; hoist
            var events: [NSEvent] = []
            for character in text {
                // Any newline becomes ONE Return keypress (CR 0x0d): the software
                // keyboard's Return arrives as "\n" (LF), but a terminal Return is CR
                // and raw-mode apps (vim, readline) ignore a literal LF. A pasted CRLF
                // is a single grapheme cluster ("\r\n") in Swift's Character iteration,
                // so matching it here collapses it to one Return rather than two.
                if character == "\n" || character == "\r" || character == "\r\n" {
                    if let event = Self.makeEvent(characters: "\r",
                                                  charactersIgnoringModifiers: "\r",
                                                  flags: deadKeyFlags,
                                                  keyCode: kVK_Return) {
                        events.append(event)
                    }
                    continue
                }
                // Reuse the shared, layout-aware character -> key-down builder: it picks
                // the physical key code (and Shift/Option) the mac's active layout needs
                // to produce this character, so the CSI-u modern mapper re-derives the
                // right key on any layout. Layer our dead-key modifiers on top.
                guard let base = NSEvent.keyDown(forCharacter: character) else {
                    continue
                }
                if deadKeyFlags.isEmpty {
                    events.append(base)
                    continue
                }
                let string = String(character)
                if let event = Self.makeEvent(characters: base.characters ?? string,
                                              charactersIgnoringModifiers: base.charactersIgnoringModifiers ?? string,
                                              flags: base.modifierFlags.union(deadKeyFlags),
                                              keyCode: Int(base.keyCode)) {
                    events.append(event)
                }
            }
            return events
        }
    }

    /// If a synthesized `.text` key event cannot be produced by a single keystroke on
    /// the mac's active layout, return the literal characters to write instead of
    /// injecting the event; otherwise nil.
    ///
    /// Why: `NSEvent.keyDown(forCharacter:)` falls back to key code 0 for a character
    /// with no single-keystroke mapping (an accented letter, an emoji, a dead-key
    /// result). The legacy mapper still emits the literal characters, but the modern
    /// (CSI-u) mapper derives the reported key by running the key code back through the
    /// layout, so key code 0 would be mis-reported as the physical 'a' key. Key code 0
    /// is ALSO the legitimate 'a' key, so we can't test the key code directly - we test
    /// whether the key code actually round-trips to this character on the active layout.
    /// When it doesn't, writing the character literally is the best available option:
    /// under the legacy mapper it emits the same bytes the mapper would have, and it
    /// never mis-encodes to 'a'.
    ///
    /// Known limitations of the literal path (both niche - a non-layout character AND a
    /// full-reporting Kitty app):
    ///  - Under "report all keys as escape codes", the app expects a CSI-u key report
    ///    for every key (plus a release in event-types mode); a literal write sends raw
    ///    UTF-8 instead, which the app receives as text, not a keypress. We accept this
    ///    over emitting a wrong-key CSI-u report.
    ///  - The synthesized event's key code is the meaningless fallback 0 (= the 'a'
    ///    key), so a keystroke monitor/filter keyed on keyCode 0 could match these
    ///    characters, and keystroke API notifications report them as keyCode 0.
    static func literalFallback(for event: NSEvent) -> String? {
        guard let characters = event.characters, !characters.isEmpty else {
            return nil
        }
        guard let scalar = characters.unicodeScalars.first else {
            return nil
        }
        // Function/arrow keys (the .function flag, or private-use characters) carry a
        // real key code the mapper handles - never literal.
        if event.modifierFlags.contains(.function) || (0xF700...0xF8FF).contains(scalar.value) {
            return nil
        }
        // The NAMED control-byte keys (Esc/Tab/Return/Backspace) also carry a real key
        // code and must be synthesized. A RAW control/DEL byte arriving as .text, though,
        // has the fallback key code 0 and would be mis-derived under CSI-u as the 'a'
        // key, so let it fall through to the round-trip check (which routes it literal).
        if (scalar.value < 0x20 || scalar.value == 0x7f) && event.keyCode != 0 {
            return nil
        }
        // Round-trip on Shift ONLY - deliberately not Option. A character the layout
        // produces WITH Option (⌥a = "å" on US; "@"/"["/"{" on German QWERTZ) is treated
        // as a fallback here on purpose: synthesizing it would carry a bare .option that
        // the standard mapper classifies as LEFT Option, so under an OPT_ESC/OPT_META
        // profile (common Meta setups) it would wrongly prepend ESC / set the high bit
        // (typing "å" -> 0x1b 0xc3 0xa5 instead of 0xc3 0xa5). Writing it literally emits
        // the composed glyph correctly under every profile, and matches OPT_NORMAL, which
        // would have emitted the same bytes.
        //
        // An armed Option dead-key is unaffected: it carries a device-dependent side bit
        // (.leftOption/.rightOption), not bare .option, and the character it modifies is a
        // plain key that DOES round-trip on Shift alone - so it still reaches the mapper
        // for the profile's Esc+/Meta encoding. (The one exception - an armed Option dead-
        // key on a character that itself needs layout-Option, e.g. ⌥8 = "•" - takes the
        // literal path: the glyph is correct but that rare combination loses Meta routing.)
        var carbonModifiers: UInt32 = 0
        if event.modifierFlags.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }
        if NSEvent.stringForKey(withKeycode: event.keyCode, modifiers: carbonModifiers) == characters {
            return nil   // round-trips on the bare/shifted key: safe to synthesize
        }
        return characters   // needs Option, or a fallback key code: write literally
    }

    private static func makeEvent(characters: String,
                                  charactersIgnoringModifiers: String,
                                  flags: NSEvent.ModifierFlags,
                                  keyCode: Int) -> NSEvent? {
        guard !characters.isEmpty else {
            return nil
        }
        return NSEvent.keyEvent(with: .keyDown,
                                location: .zero,
                                modifierFlags: flags,
                                // A real, monotonically-advancing timestamp (matching
                                // NSEvent.keyDown(forCharacter:)) so timing-based
                                // detectors (meta-frustration, key-up delta) don't see
                                // every phone key as simultaneous.
                                timestamp: ProcessInfo.processInfo.systemUptime,
                                windowNumber: 0,
                                context: nil,
                                characters: characters,
                                charactersIgnoringModifiers: charactersIgnoringModifiers,
                                isARepeat: false,
                                keyCode: UInt16(keyCode))
    }
}
