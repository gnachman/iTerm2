//
//  iTermFocusablePanel.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/3/20.
//

import AppKit

// A panel that accepts key, main, and first responder. Several xibs name it
// as a window's customClass. It must not gain a designated initializer or a
// stored property without a default: Swift would then stop inheriting
// init(contentRect:styleMask:backing:defer:), which nib loading calls, and
// register a stub that traps in its place.
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
