//
//  iTermTransparentLayerView.swift
//  iTerm
//
//  Created by George Nachman on 3/13/13.
//

import AppKit

// A view that draws nothing and is never opaque. When it is made with
// init(frame:), it is backed by a plain CALayer with a clear background
// instead of the layer class AppKit would make.
@objc(iTermTransparentLayerView)
class iTermTransparentLayerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    // A view decoded from an archive gets only NSView's own setup, without
    // the layer that init(frame:) installs.
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var isOpaque: Bool {
        return false
    }
}
