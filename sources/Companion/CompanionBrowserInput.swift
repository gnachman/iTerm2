//
//  CompanionBrowserInput.swift
//  iTerm2
//
//  Delivers phone input to the web view of a browser session: taps become mouse
//  clicks, scroll gestures become pixel scroll-wheel events, and keys become key
//  events (or inserted text). The events are synthesized NSEvents handed straight
//  to the web view, so WebKit treats them as real user input (trusted DOM events,
//  default actions like following a link or submitting a form on Return) and they
//  work whether or not the web view's window is key, or the web view is in a
//  window at all (a browser in a background tab).
//
//  A click makes the web view its window's first responder, just as a real click
//  would, so a tap from the phone focuses that browser pane on the Mac.
//

import AppKit
import Carbon.HIToolbox

enum CompanionBrowserInput {
    /// One unit of keyboard input for a web view.
    enum Stroke: Equatable {
        /// A key press (key down then key up).
        case key(characters: String,
                 charactersIgnoringModifiers: String,
                 keyCode: UInt16,
                 modifiers: NSEvent.ModifierFlags)
        /// Text with no corresponding key on a US keyboard, inserted the way an
        /// input method would.
        case text(String)
    }

    // MARK: - Key mapping

    /// The strokes that reproduce `event` in a web view.
    static func strokes(for event: CompanionKeyEvent) -> [Stroke] {
        let modifiers = modifierFlags(event.modifiers)
        switch event.key {
        case .special(let special):
            let (character, keyCode, extraFlags) = specialKey(special)
            return [.key(characters: character,
                         charactersIgnoringModifiers: character,
                         keyCode: keyCode,
                         modifiers: modifiers.union(extraFlags))]
        case .text(let text):
            var result = [Stroke]()
            var pendingText = ""
            func flushText() {
                if !pendingText.isEmpty {
                    result.append(.text(pendingText))
                    pendingText = ""
                }
            }
            for character in text {
                guard let stroke = textKey(character, modifiers: modifiers) else {
                    pendingText.append(character)
                    continue
                }
                flushText()
                result.append(stroke)
            }
            flushText()
            return result
        }
    }

    private static func modifierFlags(_ modifiers: CompanionKeyModifiers) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if modifiers.control {
            flags.insert(.control)
        }
        if modifiers.shift {
            flags.insert(.shift)
        }
        if modifiers.leftOption || modifiers.rightOption {
            flags.insert(.option)
        }
        return flags
    }

    private static func functionKey(_ code: Int) -> String {
        return String(UnicodeScalar(UInt32(code))!)
    }

    private static func specialKey(_ key: CompanionSpecialKey) -> (String, UInt16, NSEvent.ModifierFlags) {
        let arrow: NSEvent.ModifierFlags = [.numericPad, .function]
        switch key {
        case .escape: return ("\u{1b}", UInt16(kVK_Escape), [])
        case .tab: return ("\t", UInt16(kVK_Tab), [])
        case .backspace: return ("\u{7f}", UInt16(kVK_Delete), [])
        case .forwardDelete: return (functionKey(NSDeleteFunctionKey), UInt16(kVK_ForwardDelete), .function)
        case .up: return (functionKey(NSUpArrowFunctionKey), UInt16(kVK_UpArrow), arrow)
        case .down: return (functionKey(NSDownArrowFunctionKey), UInt16(kVK_DownArrow), arrow)
        case .left: return (functionKey(NSLeftArrowFunctionKey), UInt16(kVK_LeftArrow), arrow)
        case .right: return (functionKey(NSRightArrowFunctionKey), UInt16(kVK_RightArrow), arrow)
        case .home: return (functionKey(NSHomeFunctionKey), UInt16(kVK_Home), .function)
        case .end: return (functionKey(NSEndFunctionKey), UInt16(kVK_End), .function)
        case .pageUp: return (functionKey(NSPageUpFunctionKey), UInt16(kVK_PageUp), .function)
        case .pageDown: return (functionKey(NSPageDownFunctionKey), UInt16(kVK_PageDown), .function)
        case .insert: return (functionKey(NSHelpFunctionKey), UInt16(kVK_Help), .function)
        case .f1: return (functionKey(NSF1FunctionKey), UInt16(kVK_F1), .function)
        case .f2: return (functionKey(NSF2FunctionKey), UInt16(kVK_F2), .function)
        case .f3: return (functionKey(NSF3FunctionKey), UInt16(kVK_F3), .function)
        case .f4: return (functionKey(NSF4FunctionKey), UInt16(kVK_F4), .function)
        case .f5: return (functionKey(NSF5FunctionKey), UInt16(kVK_F5), .function)
        case .f6: return (functionKey(NSF6FunctionKey), UInt16(kVK_F6), .function)
        case .f7: return (functionKey(NSF7FunctionKey), UInt16(kVK_F7), .function)
        case .f8: return (functionKey(NSF8FunctionKey), UInt16(kVK_F8), .function)
        case .f9: return (functionKey(NSF9FunctionKey), UInt16(kVK_F9), .function)
        case .f10: return (functionKey(NSF10FunctionKey), UInt16(kVK_F10), .function)
        case .f11: return (functionKey(NSF11FunctionKey), UInt16(kVK_F11), .function)
        case .f12: return (functionKey(NSF12FunctionKey), UInt16(kVK_F12), .function)
        }
    }

    /// US-layout key codes for the characters a key press can produce, and
    /// whether Shift is needed. The key code only affects the DOM `code`
    /// property; the text typed comes from the characters.
    private static let usKeys: [Character: (Int, Bool)] = {
        var map = [Character: (Int, Bool)]()
        let letters: [Int] = [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E,
                              kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J,
                              kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O,
                              kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T,
                              kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y,
                              kVK_ANSI_Z]
        for (i, code) in letters.enumerated() {
            let lower = Character(UnicodeScalar(UInt8(ascii: "a") + UInt8(i)))
            map[lower] = (code, false)
            map[Character(lower.uppercased())] = (code, true)
        }
        let unshifted: [(Character, Int)] = [
            ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3),
            ("4", kVK_ANSI_4), ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7),
            ("8", kVK_ANSI_8), ("9", kVK_ANSI_9), (" ", kVK_Space), ("-", kVK_ANSI_Minus),
            ("=", kVK_ANSI_Equal), ("[", kVK_ANSI_LeftBracket), ("]", kVK_ANSI_RightBracket),
            ("\\", kVK_ANSI_Backslash), (";", kVK_ANSI_Semicolon), ("'", kVK_ANSI_Quote),
            (",", kVK_ANSI_Comma), (".", kVK_ANSI_Period), ("/", kVK_ANSI_Slash),
            ("`", kVK_ANSI_Grave),
        ]
        for (character, code) in unshifted {
            map[character] = (code, false)
        }
        let shifted: [(Character, Int)] = [
            (")", kVK_ANSI_0), ("!", kVK_ANSI_1), ("@", kVK_ANSI_2), ("#", kVK_ANSI_3),
            ("$", kVK_ANSI_4), ("%", kVK_ANSI_5), ("^", kVK_ANSI_6), ("&", kVK_ANSI_7),
            ("*", kVK_ANSI_8), ("(", kVK_ANSI_9), ("_", kVK_ANSI_Minus), ("+", kVK_ANSI_Equal),
            ("{", kVK_ANSI_LeftBracket), ("}", kVK_ANSI_RightBracket), ("|", kVK_ANSI_Backslash),
            (":", kVK_ANSI_Semicolon), ("\"", kVK_ANSI_Quote), ("<", kVK_ANSI_Comma),
            (">", kVK_ANSI_Period), ("?", kVK_ANSI_Slash), ("~", kVK_ANSI_Grave),
        ]
        for (character, code) in shifted {
            map[character] = (code, true)
        }
        return map
    }()

    /// A key press for a typed character, or nil if no US key produces it (the
    /// character is then inserted as text).
    private static func textKey(_ character: Character, modifiers: NSEvent.ModifierFlags) -> Stroke? {
        switch character {
        case "\n", "\r":
            return .key(characters: "\r", charactersIgnoringModifiers: "\r",
                        keyCode: UInt16(kVK_Return), modifiers: modifiers)
        case "\t":
            return .key(characters: "\t", charactersIgnoringModifiers: "\t",
                        keyCode: UInt16(kVK_Tab), modifiers: modifiers)
        default:
            break
        }
        guard let (keyCode, needsShift) = usKeys[character] else {
            return nil
        }
        var flags = modifiers
        if needsShift {
            flags.insert(.shift)
        }
        var characters = String(character)
        if flags.contains(.control),
           let ascii = character.lowercased().first?.asciiValue,
           ascii >= UInt8(ascii: "a"), ascii <= UInt8(ascii: "z") {
            // Control-letter produces the corresponding control character, as a
            // hardware key press would.
            characters = String(UnicodeScalar(ascii - UInt8(ascii: "a") + 1))
        }
        return .key(characters: characters,
                    charactersIgnoringModifiers: String(character),
                    keyCode: UInt16(keyCode),
                    modifiers: flags)
    }

    // MARK: - Delivery

    /// Type `event` into the page.
    @MainActor
    static func send(_ event: CompanionKeyEvent, to webView: NSView) {
        for stroke in strokes(for: event) {
            switch stroke {
            case let .key(characters, charactersIgnoringModifiers, keyCode, modifiers):
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let keyEvent = NSEvent.keyEvent(with: type,
                                                          location: .zero,
                                                          modifierFlags: modifiers,
                                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                                          windowNumber: webView.window?.windowNumber ?? 0,
                                                          context: nil,
                                                          characters: characters,
                                                          charactersIgnoringModifiers: charactersIgnoringModifiers,
                                                          isARepeat: false,
                                                          keyCode: keyCode) else {
                        DLog("Could not create key event for \(stroke)")
                        continue
                    }
                    if type == .keyDown {
                        webView.keyDown(with: keyEvent)
                    } else {
                        webView.keyUp(with: keyEvent)
                    }
                }
            case .text(let text):
                webView.insertText(text)
            }
        }
    }

    /// Click the page at `point`, in web view points with the origin at the top left.
    @MainActor
    static func click(_ webView: NSView, at point: CGPoint) {
        let location = windowLocation(webView, point: point)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let mouseEvent = NSEvent.mouseEvent(with: type,
                                                      location: location,
                                                      modifierFlags: [],
                                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: webView.window?.windowNumber ?? 0,
                                                      context: nil,
                                                      eventNumber: 0,
                                                      clickCount: 1,
                                                      pressure: type == .leftMouseDown ? 1 : 0) else {
                DLog("Could not create mouse event")
                return
            }
            if type == .leftMouseDown {
                webView.mouseDown(with: mouseEvent)
            } else {
                webView.mouseUp(with: mouseEvent)
            }
        }
    }

    /// Scroll whatever is under `point` (web view points, origin at the top left)
    /// so its content moves by (`deltaX`, `deltaY`) points; positive moves it
    /// right / down.
    @MainActor
    static func scroll(_ webView: NSView, at point: CGPoint, deltaX: Double, deltaY: Double) {
        let wheelY = Int32(clamping: Int(deltaY.rounded()))
        let wheelX = Int32(clamping: Int(deltaX.rounded()))
        guard wheelX != 0 || wheelY != 0,
              let cgEvent = CGEvent(scrollWheelEvent2Source: nil,
                                    units: .pixel,
                                    wheelCount: 2,
                                    wheel1: wheelY,
                                    wheel2: wheelX,
                                    wheel3: 0) else {
            return
        }
        // A scroll event carries a global location (origin at the top left of the
        // main screen); WebKit converts it back to find what to scroll.
        let inWindow = windowLocation(webView, point: point)
        var global = webView.window?.convertPoint(toScreen: inWindow) ?? inWindow
        global.y = (NSScreen.screens.first?.frame.height ?? 0) - global.y
        cgEvent.location = global
        guard let wheelEvent = NSEvent(cgEvent: cgEvent) else {
            return
        }
        webView.scrollWheel(with: wheelEvent)
    }

    /// `point` (view points, origin at the top left) in window coordinates.
    @MainActor
    private static func windowLocation(_ view: NSView, point: CGPoint) -> NSPoint {
        let local = NSPoint(x: point.x, y: view.isFlipped ? point.y : view.bounds.height - point.y)
        return view.convert(local, to: nil)
    }
}
