//
//  NSAlert+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/6/18.
//

import AppKit

extension NSAlert {
    // Activates the app, shows the alert as a sheet on `window`, and blocks in
    // a modal session until the sheet ends. Returns the button's response, or
    // abort if `window` closes first.
    @objc(runSheetModalForWindow:)
    func runSheetModal(for window: NSWindow) -> NSApplication.ModalResponse {
        DLog("Run sheet modal for window \(window)")

        NSApp.activate(ignoringOtherApps: true)

        // If the parent window is closed before the sheet is dismissed, the
        // completion handler never fires and runModal(for:) would block
        // forever (an unrecoverable app hang). The shared guard observes the
        // parent closing and aborts the modal (draining any nested modals
        // stacked over the dead parent).
        beginSheetModal(for: window) { returnCode in
            // Only stop this alert's own session. If the sheet is being torn
            // down because its parent closed,
            // iTermRunModalForWindowAbortingIfParentCloses has already
            // aborted it, so stopping here could hit whatever modal is
            // current now.
            if NSApp.modalWindow === self.window {
                NSApp.stopModal(withCode: returnCode)
            }
        }
        return iTermRunModalForWindowAbortingIfParentCloses(self.window, window)
    }
}
