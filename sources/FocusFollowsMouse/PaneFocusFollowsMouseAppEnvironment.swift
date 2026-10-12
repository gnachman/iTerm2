//
//  PaneFocusFollowsMouseAppEnvironment.swift
//  iTerm2
//

import AppKit

extension SessionView: PaneFocusFollowsMousePane {
    var focusFollowsMouseMainResponder: NSView? {
        return delegate?.sessionViewFocusFollowsMouseMainResponder()
    }
}

extension NSView {
    // The first editable text field or text view in this view's subtree, in subview order.
    @objc func it_firstEditableTextDescendant() -> NSView? {
        for subview in subviews where !subview.isHidden {
            if subview.it_isEditableText {
                return subview
            }
            if let found = subview.it_firstEditableTextDescendant() {
                return found
            }
        }
        return nil
    }

    // Under focus follows mouse, an editable text field or text view in a pane takes focus when
    // the pointer is over it.
    fileprivate var it_isEditableText: Bool {
        if let textField = self as? NSTextField {
            return textField.isEditable
        }
        if let textView = self as? NSTextView {
            return textView.isEditable && !textView.isFieldEditor
        }
        return false
    }
}

// Connects PaneFocusFollowsMouse to real windows, preferences, and the private API for stealing
// key focus.
@MainActor
final class PaneFocusFollowsMouseAppEnvironment: PaneFocusFollowsMouseEnvironment {
    var isEnabled: Bool {
        return iTermPreferences.bool(forKey: kPreferenceKeyFocusFollowsMouse)
    }

    var includesSubviews: Bool {
        return iTermPreferences.bool(forKey: kPreferenceKeyFocusFollowsMouseIncludingSubviews)
    }

    var stealKeyFocusEnabled: Bool {
        return iTermAdvancedSettingsModel.stealKeyFocus()
    }

    var appIsActive: Bool {
        return NSApp.isActive
    }

    var mouseButtonIsDown: Bool {
        return NSEvent.pressedMouseButtons != 0
    }

    var currentEventIsMouseUp: Bool {
        switch NSApp.currentEvent?.type {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return true
        default:
            return false
        }
    }

    var pointerLocation: NSPoint {
        return NSEvent.mouseLocation
    }

    func pane(at screenPoint: NSPoint) -> PaneFocusFollowsMousePane? {
        guard let window = Self.window(at: screenPoint) else {
            return nil
        }
        return Self.sessionView(atWindowPoint: window.convertPoint(fromScreen: screenPoint), in: window)
    }

    // The pane a click at windowPoint would land in. A float's resize band or title bar hits the
    // float, which contains its session view rather than being inside one, so it doesn't count
    // as a pane.
    static func sessionView(atWindowPoint windowPoint: NSPoint, in window: NSWindow) -> SessionView? {
        let hit = hitView(atWindowPoint: windowPoint, in: window)
        if let splitView = hit as? NSSplitView {
            // A split view widens its dividers' hit area a few points into the panes beside them.
            // Entering a pane lands in that margin, so treat it as part of the pane.
            return sessionView(in: splitView, atWindowPoint: windowPoint)
        }
        return hit.flatMap(sessionView(containing:))
    }

    // The session view in view's subtree whose frame contains windowPoint.
    private static func sessionView(in view: NSView, atWindowPoint windowPoint: NSPoint) -> SessionView? {
        for subview in view.subviews.reversed() where !subview.isHidden {
            guard subview.convert(subview.bounds, to: nil).contains(windowPoint) else {
                continue
            }
            if let sessionView = subview as? SessionView {
                return sessionView
            }
            if let sessionView = sessionView(in: subview, atWindowPoint: windowPoint) {
                return sessionView
            }
        }
        return nil
    }

    func focusTarget(at screenPoint: NSPoint, in pane: PaneFocusFollowsMousePane) -> NSView? {
        guard let sessionView = pane as? SessionView else {
            return nil
        }
        return Self.focusTarget(hitView: Self.hitView(at: screenPoint), in: sessionView)
    }

    // Walks up from the view the pointer is over to the first view that takes focus.
    static func focusTarget(hitView: NSView?, in sessionView: SessionView) -> NSView? {
        let main = sessionView.focusFollowsMouseMainResponder
        var current = hitView
        while let view = current, view !== sessionView {
            if view === main {
                return main
            }
            if let responder = view.it_focusFollowsMouseResponder {
                return responder
            }
            if view.it_isEditableText {
                return view
            }
            current = view.superview
        }
        return nil
    }

    var firstResponder: NSResponder? {
        return NSApp.keyWindow?.firstResponder
    }

    func pane(containing view: NSView) -> PaneFocusFollowsMousePane? {
        return Self.sessionView(containing: view)
    }

    var focusedPane: PaneFocusFollowsMousePane? {
        guard let view = NSApp.keyWindow?.firstResponder as? NSView else {
            return nil
        }
        return Self.sessionView(containing: view)
    }

    func canFocus(_ pane: PaneFocusFollowsMousePane) -> Bool {
        guard let window = (pane as? SessionView)?.window else {
            return false
        }
        return window.alphaValue > 0 && NSApp.modalWindow == nil
    }

    func focus(_ pane: PaneFocusFollowsMousePane, responder: NSResponder, evenIfInactive: Bool) {
        guard let sessionView = pane as? SessionView, let window = sessionView.window else {
            return
        }
        // Some windows automatically close when they lose key status and are incompatible with
        // focus follows mouse. Moving within them is fine, but don't make another window key.
        let mayMakeKey = Self.keyWindowDisablingFocusFollowsMouse?.disableFocusFollowsMouse() != true
        if (evenIfInactive || NSApp.isActive) && mayMakeKey {
            DLog("Make \(window) key")
            window.makeKey()
        } else {
            DLog("Not making \(window) key. NSApp.isActive=\(NSApp.isActive) mayMakeKey=\(mayMakeKey)")
        }
        // With stolen key focus the window doesn't become key because the app is inactive, but
        // typing still goes to its first responder.
        guard evenIfInactive || Self.isInKeyWindow(window) else {
            DLog("\(window) is not key")
            return
        }
        if window.firstResponder === responder {
            sessionView.delegate?.sessionViewFocusFollowsMouseActivateSession()
            return
        }
        if responder !== sessionView.focusFollowsMouseMainResponder {
            // An overlay only becomes first responder; it doesn't make its session active the
            // way the terminal does. Activate first, because activating focuses the terminal.
            sessionView.delegate?.sessionViewFocusFollowsMouseActivateSession()
        }
        window.makeFirstResponder(responder)
    }

    // Uses an undocumented API to receive key presses while another app is active.
    func stealKeyFocus() {
        guard let getCurrentProcess = GetCPSGetCurrentProcessFunction(),
              let stealKeyFocusFunction = GetCPSStealKeyFocusFunction() else {
            return
        }
        var psn = CPSProcessSerNum()
        if getCurrentProcess(&psn) == noErr {
            // CPSStealKeyFocus appears to succeed even when it returns an error. See issue 4113.
            let err = stealKeyFocusFunction(&psn)
            DLog("CPSStealKeyFocus returned \(err)")
            iTermSecureKeyboardEntryController.sharedInstance().didStealFocus()
        }
    }

    // Undoes stealKeyFocus().
    func releaseKeyFocus() {
        guard let getCurrentProcess = GetCPSGetCurrentProcessFunction(),
              let releaseKeyFocusFunction = GetCPSReleaseKeyFocusFunction() else {
            return
        }
        var psn = CPSProcessSerNum()
        if getCurrentProcess(&psn) == noErr {
            DLog("CPSReleaseKeyFocus")
            _ = releaseKeyFocusFunction(&psn)
            iTermSecureKeyboardEntryController.sharedInstance().didReleaseFocus()
        }
    }

    func stolenKeyFocusDidChange(for pane: PaneFocusFollowsMousePane) {
        (pane as? SessionView)?.delegate?.sessionViewFocusFollowsMouseStolenKeyFocusDidChange()
    }

    func scheduleRebaseline(_ block: @escaping () -> Void) {
        DispatchQueue.main.async {
            block()
        }
    }

    // MARK: - Private

    // The frontmost window at screenPoint, or nil if it, across all apps, isn't one of ours.
    private static func window(at screenPoint: NSPoint) -> NSWindow? {
        let windowNumber = NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0)
        return NSApp.window(withWindowNumber: windowNumber)
    }

    // The view a click at screenPoint would hit, or nil if the frontmost window there isn't ours.
    private static func hitView(at screenPoint: NSPoint) -> NSView? {
        guard let window = window(at: screenPoint) else {
            return nil
        }
        return hitView(atWindowPoint: window.convertPoint(fromScreen: screenPoint), in: window)
    }

    private static func hitView(atWindowPoint windowPoint: NSPoint, in window: NSWindow) -> NSView? {
        guard let contentView = window.contentView else {
            return nil
        }
        // -hitTest: takes a point in the receiver's superview's coordinate system.
        let hitTestPoint = contentView.superview?.convert(windowPoint, from: nil) ?? windowPoint
        return contentView.hitTest(hitTestPoint)
    }

    private static func sessionView(containing view: NSView) -> SessionView? {
        var current: NSView? = view
        while let candidate = current {
            if let sessionView = candidate as? SessionView {
                return sessionView
            }
            current = candidate.superview
        }
        return nil
    }

    private static var keyWindowDisablingFocusFollowsMouse: iTermFocusFollowsMouseDisabling? {
        guard let keyWindow = NSApp.keyWindow else {
            return nil
        }
        if keyWindow.implementsDisableFocusFollowsMouse() {
            return keyWindow
        }
        if let controller = keyWindow.windowController, controller.implementsDisableFocusFollowsMouse() {
            return controller
        }
        return nil
    }

    private static func isInKeyWindow(_ window: NSWindow) -> Bool {
        // This exists to work around an apparent OS bug described in issue 2690. Under some
        // circumstances (which I cannot reproduce) the key window will be an
        // NSToolbarFullScreenWindow and the iTermTerminalWindow will be one of the main windows.
        // NSToolbarFullScreenWindow doesn't appear to handle keystrokes, so they fall through to
        // the main window. We'd like the cursor to blink and have other key-window behaviors in
        // this case.
        if window.isKeyWindow {
            return true
        }
        guard let keyWindow = NSApp.keyWindow else {
            return false
        }
        if String(cString: object_getClassName(keyWindow)) == "NSToolbarFullScreenWindow" {
            DLog("Key window is a NSToolbarFullScreenWindow, using main window status of \(window.isMainWindow) as key status")
            return window.isMainWindow
        }
        return false
    }
}
