//
//  TerminalModeEnclosure.swift
//  iTerm2
//
//  Created by George Nachman on 6/21/25.
//

@objc(iTermModalEnclosure)
@IBDesignable
class ModalEnclosure: NSView {
    var shiftsViewsBeneath: Bool = true
    var neighborToGrowRight: NSView?

    @objc
    var visibleForProfileTypes: ProfileType {
        return [.all]
    }
}

@objc(iTermTerminalModeEnclosure)
@IBDesignable
class TerminalModeEnclosure: ModalEnclosure {
    @IBInspectable
    override var shiftsViewsBeneath: Bool {
        get {
            super.shiftsViewsBeneath
        }
        set {
            super.shiftsViewsBeneath = newValue
        }
    }

    @IBOutlet override var neighborToGrowRight: NSView? {
        get {
            super.neighborToGrowRight
        }
        set {
            super.neighborToGrowRight = newValue
        }
    }

    @objc
    override var visibleForProfileTypes: ProfileType {
        return [.terminal]
    }
}

@objc(iTermBrowserModeEnclosure)
@IBDesignable
class BrowserModeEnclosure: ModalEnclosure {
    @objc
    override var visibleForProfileTypes: ProfileType {
        return [.browser]
    }
}

@objc(iTermHiddenModeEnclosure)
@IBDesignable
class HiddenModeEnclosure: ModalEnclosure {
    @objc
    override var visibleForProfileTypes: ProfileType {
        if iTermAdvancedSettingsModel.browserProfiles() {
            return [.all]
        } else {
            return []
        }
    }
}

@objc(iTermSharedProfileEnclosure)
@IBDesignable
class SharedProfileEnclosure: ModalEnclosure {
    @objc
    override var visibleForProfileTypes: ProfileType {
        return [.all]
    }
}

extension NSView {
    @objc
    var enclosingModalEnclosure: ModalEnclosure? {
        var current = self
        while true {
            if let enclosure = current as? ModalEnclosure {
                return enclosure
            }
            if let parent = current.superview {
                current = parent
            } else {
                return nil
            }
        }
    }
}
