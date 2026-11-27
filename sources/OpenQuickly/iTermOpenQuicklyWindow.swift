//
//  iTermOpenQuicklyWindow.swift
//  iTerm
//
//  Created by George Nachman on 7/13/14.
//
//

import AppKit

// An NSPanel that can become key.
@objc(iTermOpenQuicklyWindow)
class iTermOpenQuicklyWindow: NSPanel {
    override init(contentRect: NSRect,
                  styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType,
                  defer flag: Bool) {
        // The .nonactivatingPanel style lets the panel become key without
        // activating iTerm2, which is required for the global Open Quickly
        // hotkey (the panel must accept keystrokes while another app remains
        // in front).
        super.init(contentRect: contentRect,
                   styleMask: style.union(.nonactivatingPanel),
                   backing: backingStoreType,
                   defer: flag)
        // Belt and suspenders: also set the underlying state so AppKit can't
        // fall back to the panel default when the getter below isn't
        // consulted.
        super.hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool {
        return true
    }

    override var hidesOnDeactivate: Bool {
        // The global hotkey can show this panel while iTerm2 is in the
        // background. The NSPanel default of YES makes the window server drop
        // the panel on the second invocation (it's already in the "should
        // hide because app inactive" state from the previous orderOut), so
        // this always answers NO. The panel is still dismissed by
        // windowDidResignKey: when the user clicks away. Setting the value
        // stores it in NSPanel as usual.
        get {
            return false
        }
        set {
            super.hidesOnDeactivate = newValue
        }
    }

    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval {
        // A negative setting gives zero.
        return max(0, iTermAdvancedSettingsModel.openQuicklyAnimationDuration())
    }

    @objc func autoHidesHotKeyWindow() -> Bool {
        return false
    }

    override func disableFocusFollowsMouse() -> Bool {
        return true
    }

    override func implementsDisableFocusFollowsMouse() -> Bool {
        return true
    }
}
