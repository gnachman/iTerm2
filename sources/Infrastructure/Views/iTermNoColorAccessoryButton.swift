//
//  iTermNoColorAccessoryButton.swift
//  iTerm2
//
//  Created by George Nachman on 6/5/15.
//
//

import AppKit

// First responders may implement methods in this protocol.
@objc(iTermNoColorAccessoryButtonResponder)
protocol iTermNoColorAccessoryButtonResponder: NSObjectProtocol {
    @objc optional func noColorChosen(_ sender: Any?)
}

// A button for use as an accessory in the color picker panel that selects
// "no color". It declares no designated initializer, so it inherits
// NSButton's.
@objc(iTermNoColorAccessoryButton)
class iTermNoColorAccessoryButton: NSButton {
    convenience init() {
        let image = NSImage.it_imageNamed("NoColor", for: Self.self)
        let topBottomMargin = 8.0
        let size = image?.size ?? .zero
        self.init(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height + topBottomMargin * 2))
        setButtonType(.momentaryPushIn)
        self.image = image
        target = nil
        action = #selector(iTermNoColorAccessoryButtonResponder.noColorChosen(_:))
        isBordered = false
        (cell as? NSButtonCell)?.highlightsBy = .contentsCellMask
        title = ""
    }
}
