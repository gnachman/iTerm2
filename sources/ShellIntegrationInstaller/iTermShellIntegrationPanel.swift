//
//  iTermShellIntegrationPanel.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/19.
//

import AppKit

// The shell integration installer's window. iTermShellIntegrationWindowController.xib
// declares a plain window and names this class as its custom class, which is what makes
// it an NSPanel; windowDidLoad relies on that. The name is pinned so nib loading finds
// it. It must not gain a stored property without a default or a designated initializer:
// Swift would then stop inheriting init(contentRect:styleMask:backing:defer:), which nib
// loading calls, and register a stub that traps in its place.
@objc(iTermShellIntegrationPanel)
class iTermShellIntegrationPanel: NSPanel {
}
