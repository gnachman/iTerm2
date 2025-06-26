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
}

@objc(iTermBrowserModeEnclosure)
@IBDesignable
class BrowserModeEnclosure: ModalEnclosure {}

@objc(iTermHiddenModeEnclosure)
@IBDesignable
class HiddenModeEnclosure: ModalEnclosure {}

@objc(iTermSharedProfileEnclosure)
@IBDesignable
class SharedProfileEnclosure: ModalEnclosure {}

@objc(iTermWTF)
@IBDesignable
class iTermWTF: ModalEnclosure {
    @IBInspectable var blowsChunks: Bool = false
}
