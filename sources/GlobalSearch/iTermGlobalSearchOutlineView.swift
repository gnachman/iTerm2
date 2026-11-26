//
//  iTermGlobalSearchOutlineView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

import AppKit

// The Find Globally window's outline view. iTermGlobalSearch.xib names it as
// a customClass by its Objective-C name.
@objc(iTermGlobalSearchOutlineView)
class iTermGlobalSearchOutlineView: NSOutlineView {
    // No thread assertion: it returns a constant and reads no state.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
