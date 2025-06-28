//
//  iTermFocusFollowsMouse.swift
//  iTerm2
//
//  Created by George Nachman on 6/28/25.
//

// The delegate, an NSResponder, should forward refuseFirstResponderAtCurrentMouseLocation to us.
@objc
protocol iTermFocusFollowsMouseDelegate: AnyObject, iTermFocusFollowsMouseFocusReceiver {
    var window: NSWindow? { get }
    func focusFollowsMouseDidBecomeFirstResponder()
    func focusFollowsMouseDesiredFirstResponder() -> NSResponder
    func focusFollowsMouseDidChangeMouseLocationToRefusFirstResponderAt()
}

@objc
protocol iTermFocusFollowsMouseDisabling: AnyObject {
    func disableFocusFollowsMouse() -> Bool
    func implementsDisableFocusFollowsMouse() -> Bool
}

extension NSWindow: iTermFocusFollowsMouseDisabling {
    func disableFocusFollowsMouse() -> Bool {
        return false
    }
    func implementsDisableFocusFollowsMouse() -> Bool {
        return false
    }
}

extension NSWindowController: iTermFocusFollowsMouseDisabling {
    func disableFocusFollowsMouse() -> Bool {
        return false
    }
    func implementsDisableFocusFollowsMouse() -> Bool {
        return false
    }
}

@objc
class iTermFocusFollowsMouse: NSObject {
    @objc weak var delegate: iTermFocusFollowsMouseDelegate?
    private var mouseLocationToRefuseFirstResponderAt: NSPoint? = NSEvent.mouseLocation

    // Number of times -stealKeyFocus has been called since the last time it
    // was released with releaseKeyFocus.
    private var keyFocusStolenCount = 0

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidResignActive(_:)),
                                               name: NSApplication.didResignActiveNotification,
                                               object: nil)
    }

    var focusFollowsMouse: Bool {
        return iTermPreferences.bool(forKey: kPreferenceKeyFocusFollowsMouse)
    }

    private var stealFocus: Bool {
        return iTermAdvancedSettingsModel.stealKeyFocus()
    }

    private func isInKeyWindow(window: NSWindow?) -> Bool {
        // This exists to work around an apparent OS bug described in issue 2690. Under some circumstances
        // (which I cannot reproduce) the key window will be an NSToolbarFullScreenWindow and the iTermTerminalWindow
        // will be one of the main windows. NSToolbarFullScreenWindow doesn't appear to handle keystrokes,
        // so they fall through to the main window. We'd like the cursor to blink and have other key-
        // window behaviors in this case.
        guard let window else { return false }
        if window.isKeyWindow {
            DLog("\(String(describing: delegate)) is key window")
            return true
        }
        guard let theKeyWindow = NSApp.keyWindow else {
            DLog("There is no key window")
            return false
        }
        let className = String(cString: object_getClassName(theKeyWindow))
        if className == "NSToolbarFullScreenWindow" {
            DLog("key window is a NSToolbarFullScreenWindow, using my main window status of \(window.isMainWindow) as key status")
            return window.isMainWindow
        }
        return false
    }

    private var controller: iTermFocusFollowsMouseDisabling? {
        if let keyWindow = NSApp.keyWindow, keyWindow.implementsDisableFocusFollowsMouse() {
            return NSApp.keyWindow
        } else if let controller = NSApp.keyWindow?.windowController,
                  controller.implementsDisableFocusFollowsMouse() {
            return NSApp.keyWindow?.windowController
        } else {
            return nil
        }
    }

    @objc(mouseWillEnter:)
    func mouseWillEnter(with event: NSEvent) -> Bool {
        if iTermAdvancedSettingsModel.stealKeyFocus() &&
            iTermPreferences.bool(forKey: kPreferenceKeyFocusFollowsMouse) {
            DLog("Trying to steal key focus");
            if stealKeyFocus() {
                if keyFocusStolenCount == 0 {
                    delegate?.window?.makeFirstResponder(delegate?.focusFollowsMouseDesiredFirstResponder())
                    iTermSecureKeyboardEntryController.sharedInstance().didStealFocus()
                }
                keyFocusStolenCount += 1
                return true
            }
        }
        return false
    }

    @objc(mouseEntered:)
    func mouseEntered(with event: NSEvent) {
        guard let delegate,
           let window = delegate.window,
           focusFollowsMouse &&
            window.alphaValue > 0 &&
                NSApp.modalWindow == nil else {
            return
        }
        DLog("Taking FFM path in PTYTextView.mouseEntered")
        let currentController = controller
        guard mouseLocationToRefuseFirstResponderAt != NSEvent.mouseLocation else {
            DLog("\(delegate) Refusing first responder on enter")
            return
        }
        DLog("\(delegate) Mouse location is \(NSEvent.mouseLocation), refusal point is \(mouseLocationToRefuseFirstResponderAt.debugDescriptionOrNil)")
        if stealFocus {
            DLog("steal")
            // Some windows automatically close when they lose key status and are
            // incompatible with FFM. Check if the key window or its controller implements
            // disableFocusFollowsMouse and if it returns YES do nothing.
            if currentController?.disableFocusFollowsMouse() != true {
                DLog("makeKeyWindow")
                window.makeKey()
            }
        } else {
            if NSApp.isActive && currentController?.disableFocusFollowsMouse() != true {
                DLog("makeKeyWIndow without stealing")
                window.makeKey()
            } else {
                DLog("Not making key window. NSApp.isActive=\(NSApp.isActive) currentController.disableFocusFollowsMouse=\((currentController?.disableFocusFollowsMouse()).d)")
            }
        }

        if isInKeyWindow(window: window) {
            DLog("In key window so call textViewDidBecomeFirstResponder")
            let desired = delegate.focusFollowsMouseDesiredFirstResponder()
            if window.firstResponder != desired {
                window.makeFirstResponder(desired)
            } else {
                delegate.focusFollowsMouseDidBecomeFirstResponder()
            }
        } else {
            DLog("Not in key window")
        }
    }

    // Uses an undocumented/deprecated API to receive key presses even when inactive.
    func stealKeyFocus() -> Bool {
        // Make sure everything needed for focus stealing exists in this version of Mac OS.
        guard let getCurrentProcess = GetCPSGetCurrentProcessFunction(),
              let stealKeyFocusFn = GetCPSStealKeyFocusFunction() else {
            return false
        }

        var psn = CPSProcessSerNum()
        if getCurrentProcess(&psn) == noErr {
            let err = stealKeyFocusFn(&psn);
            DLog("CPSStealKeyFocus returned \(err)")
            // CPSStealKeyFocus appears to succeed even when it returns an error. See issue 4113.
            return true
        }

        return false
    }

    // Undoes -stealKeyFocus.
    func releaseKeyFocus() {
        guard let getCurrentProcess = GetCPSGetCurrentProcessFunction(),
              let releaseKeyFocusFn = GetCPSReleaseKeyFocusFunction() else {
            return
        }
        var psn = CPSProcessSerNum()
        if getCurrentProcess(&psn) == noErr {
            DLog("CPSReleaseKeyFocus");
            _ = releaseKeyFocusFn(&psn)
        }
    }


    // Returns true if stoen focus was released.
    @objc(mouseExited:)
    func mouseExited(with event: NSEvent) -> Bool {
        var result = false
        if keyFocusStolenCount > 0 {
            DLog("Releasing key focus %d times \(keyFocusStolenCount)")
            for _ in 0..<keyFocusStolenCount {
                releaseKeyFocus()
            }
            iTermSecureKeyboardEntryController.sharedInstance().didReleaseFocus()
            keyFocusStolenCount = 0
            result = true
        }
        if NSApp.isActive {
            resetMouseLocationToRefuseFirstResponderAt()
        } else {
            DLog("Ignore mouse exited because app is not active");
        }
        return result
    }

    @objc(mouseMoved:)
    func mouseMoved(with event: NSEvent) {
        self.resetMouseLocationToRefuseFirstResponderAt()
    }

    @objc
    var haveTrackedMovement: Bool {
        return mouseLocationToRefuseFirstResponderAt != nil
    }

    @objc private func applicationDidResignActive(_ notification: Notification) {
        refuseFirstResponderAtCurrentMouseLocation()
    }

    // TODO: Call this on applicatoinDidResignActive (also reset numTouches to 0)
    @objc
    func refuseFirstResponderAtCurrentMouseLocation() {
        DLog("set refuse location");
        mouseLocationToRefuseFirstResponderAt = NSEvent.mouseLocation
        delegate?.focusFollowsMouseDidChangeMouseLocationToRefusFirstResponderAt()
    }

    // Undoes -refuseFirstResponderAtCurrentMouseLocation.
    @objc
    func resetMouseLocationToRefuseFirstResponderAt() {
        DLog("reset refuse location from\n\(Thread.callStackSymbols.joined(separator: "\n"))")
        mouseLocationToRefuseFirstResponderAt = nil
        delegate?.focusFollowsMouseDidChangeMouseLocationToRefusFirstResponderAt()
    }

    @objc
    var haveStolenFocus: Bool {
        return keyFocusStolenCount > 0
    }
}
