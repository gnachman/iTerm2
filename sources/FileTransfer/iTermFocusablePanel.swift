//
//  iTermFocusablePanel.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/3/20.
//

import AppKit

// A panel that accepts key, main, and first responder. Several xibs name it
// as a window's customClass by its Objective-C name, so it declares no
// initializer and no stored property (traps.md, "A window subclass loaded
// from a nib traps if it declares an initializer").
// No thread assertion: each override returns a constant and reads no state.
@objc(iTermFocusablePanel)
class iTermFocusablePanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }

    override var acceptsFirstResponder: Bool {
        return true
    }
}
