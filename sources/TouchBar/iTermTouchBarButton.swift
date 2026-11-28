//
//  iTermTouchBarButton.swift
//  iTerm2
//
//  Created by George Nachman on 11/23/16.
//

import AppKit

// A touch bar button that remembers what pressing it does. keyBindingAction
// is a dictionary whose contents depend on the button: a custom touch bar
// item keeps its key binding action's dictionary, the man page button keeps
// the man command under "command", and a color preset button keeps the
// preset's name under "presetName". It is nil for buttons that need no
// dictionary, such as the function keys, and for the man page button while
// there is no word to look up.
@objc(iTermTouchBarButton)
class iTermTouchBarButton: NSButton {
    @objc var keyBindingAction: [AnyHashable: Any]?
}
