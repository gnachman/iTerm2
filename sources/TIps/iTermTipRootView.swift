//
//  iTermTipRootView.swift
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

import AppKit

// Root view for the tip window, named as a customClass by
// iTermTipWindowController.xib. Draws transparent. Is not layer backed because
// a window's content view can't be both transparent and layer-backed.
@objc(iTermTipRootView)
class iTermTipRootView: NSView {
    override func awakeFromNib() {
        super.awakeFromNib()
        setAccessibilityElement(true)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Erase the view to transparent. The fill color is clear, so it has
        // to replace the pixels (.copy). A plain fill() blends the color
        // over what is already there, and blending clear over anything
        // changes nothing.
        NSColor.clear.set()
        bounds.fill(using: .copy)
    }

    override var isFlipped: Bool {
        return true
    }
}
