//
//  WorkgroupToolbarShortcut.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/8/26.
//

import AppKit
import Carbon.HIToolbox

// Codable wrapper for an iTermKeystroke. Stored as the keystroke's
// `serialized` string so the storage format mirrors the rest of the
// app's key-binding plumbing (iTermKeyMappings, iTermShortcut). The
// runtime keystroke is reconstituted on demand, so equality and
// hashing are based on the serialized form alone — that gives us
// invariant `Hashable` conformance without depending on iTermKeystroke
// (an Objective-C NSObject whose hash is identity-based).
struct WorkgroupToolbarShortcut: Codable, Equatable, Hashable {
    let serialized: String

    init(serialized: String) {
        self.serialized = serialized
    }

    init(keystroke: iTermKeystroke) {
        self.serialized = keystroke.serialized
    }

    var keystroke: iTermKeystroke? {
        let k = iTermKeystroke(serialized: serialized)
        return k.isValid ? k : nil
    }

    // Bridge to iTermShortcut for iTermShortcutInputView, which speaks
    // the older iTermShortcut model rather than iTermKeystroke. The
    // virtual keycode bit is preserved when the underlying keystroke
    // carries one (modern format), and dropped (hasKeyCode = NO) on
    // legacy keystrokes — matching the iTermShortcut `hasKeyCode`
    // semantics exactly.
    func makeShortcut() -> iTermShortcut? {
        guard let k = keystroke else { return nil }
        let chars: String
        if let scalar = UnicodeScalar(k.modifiedCharacter) {
            chars = String(scalar)
        } else {
            chars = ""
        }
        let unmodChars: String
        if let scalar = UnicodeScalar(k.character) {
            unmodChars = String(scalar)
        } else {
            unmodChars = ""
        }
        return iTermShortcut(
            keyCode: UInt(k.virtualKeyCode),
            hasKeyCode: k.hasVirtualKeyCode,
            modifiers: k.modifierFlags,
            characters: chars,
            charactersIgnoringModifiers: unmodChars)
    }

    init?(shortcut: iTermShortcut) {
        guard shortcut.isAssigned, let k = shortcut.keystroke else { return nil }
        self.serialized = k.serialized
    }

    // Convenience constructor for the built-in defaults below. Builds a
    // keycode-anchored keystroke so the binding survives layout switches
    // (e.g. cmd-r still fires on Dvorak).
    static func make(virtualKeyCode: Int,
                     character: unichar,
                     modifierFlags: NSEvent.ModifierFlags) -> WorkgroupToolbarShortcut {
        let keystroke = iTermKeystroke(
            virtualKeyCode: Int32(virtualKeyCode),
            hasKeyCode: true,
            modifierFlags: modifierFlags,
            character: UInt32(character),
            modifiedCharacter: UTF32Char(character))
        return WorkgroupToolbarShortcut(keystroke: keystroke)
    }
}

// Three-shortcut bundle for the navigation cluster's back/forward/reload
// buttons. Each is independently optional so the user can clear one
// without disturbing the others.
struct WorkgroupNavigationShortcuts: Codable, Equatable, Hashable {
    var back: WorkgroupToolbarShortcut?
    var forward: WorkgroupToolbarShortcut?
    var reload: WorkgroupToolbarShortcut?

    // ctrl-cmd arrows for back/forward: cmd-arrows alone are claimed
    // by the global Move-Tab-Left/Right binding (and "global beats
    // toolbar" in our dispatch), so they'd never fire as toolbar
    // shortcuts. Adding ctrl dodges the conflict while keeping the
    // arrow-direction visual cue.
    static let defaults: WorkgroupNavigationShortcuts = .init(
        back: .make(virtualKeyCode: kVK_LeftArrow,
                    character: unichar(NSLeftArrowFunctionKey),
                    modifierFlags: [.command, .control]),
        forward: .make(virtualKeyCode: kVK_RightArrow,
                       character: unichar(NSRightArrowFunctionKey),
                       modifierFlags: [.command, .control]),
        reload: .make(virtualKeyCode: kVK_ANSI_R,
                      character: unichar("r".unicodeScalars.first!.value),
                      modifierFlags: .command))
}

extension WorkgroupToolbarShortcut {
    static let reloadDefault: WorkgroupToolbarShortcut = .make(
        virtualKeyCode: kVK_ANSI_R,
        character: unichar("r".unicodeScalars.first!.value),
        modifierFlags: .command)
}
