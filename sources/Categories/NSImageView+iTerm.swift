//
//  NSImageView+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/3/18.
//

import AppKit

extension NSImageView {
    // nil clears the tint, as contentTintColor allows.
    // No thread assertion: it sets one property of the receiver, as any
    // AppKit view setter does, and adds no state of its own.
    @objc(it_setTintColor:)
    func it_setTintColor(_ color: NSColor?) {
        contentTintColor = color
    }
}
