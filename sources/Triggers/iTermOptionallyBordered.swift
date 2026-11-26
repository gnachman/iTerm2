//
//  iTermOptionallyBordered.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/3/21.
//

import AppKit

// Adopted in Objective-C by TriggerController.m's iTermTwoStringView and
// tested with @protocol(iTermOptionallyBordered), so it keeps its
// Objective-C runtime name.
@objc(iTermOptionallyBordered)
protocol iTermOptionallyBordered {
    @objc(setOptionalBorderEnabled:)
    func setOptionalBorderEnabled(_ enabled: Bool)
}

extension NSTextField: iTermOptionallyBordered {
    // The argument is ignored: the border and the background are turned on
    // either way, as the Objective-C did.
    // No thread assertion: it sets two properties of the receiver, as any
    // AppKit view setter does, and adds no state of its own.
    @objc(setOptionalBorderEnabled:)
    func setOptionalBorderEnabled(_ enabled: Bool) {
        isBordered = true
        drawsBackground = true
    }
}
