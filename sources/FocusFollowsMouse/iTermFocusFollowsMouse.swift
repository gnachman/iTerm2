//
//  iTermFocusFollowsMouse.swift
//  iTerm2
//
//  Created by George Nachman on 6/28/25.
//

// Windows that automatically close when they lose key status, such as an auto-hiding hotkey window,
// implement this to keep focus follows mouse from making another window key.
@objc
@MainActor
protocol iTermFocusFollowsMouseDisabling: AnyObject {
    func disableFocusFollowsMouse() -> Bool
    func implementsDisableFocusFollowsMouse() -> Bool
}

@MainActor
extension NSWindow: iTermFocusFollowsMouseDisabling {
    func disableFocusFollowsMouse() -> Bool {
        return false
    }
    func implementsDisableFocusFollowsMouse() -> Bool {
        return false
    }
}

@MainActor
extension NSWindowController: iTermFocusFollowsMouseDisabling {
    func disableFocusFollowsMouse() -> Bool {
        return false
    }
    func implementsDisableFocusFollowsMouse() -> Bool {
        return false
    }
}
