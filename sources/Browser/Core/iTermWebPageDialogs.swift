//
//  iTermWebPageDialogs.swift
//  iTerm2SharedARC
//
//  The JavaScript alert and confirm dialogs shown for web pages in the built-in browser and in web
//  Quick Look.
//

import AppKit

enum iTermWebPageDialogs {
    static func showAlert(message: String) {
        let warning = iTermWarning()
        warning.heading = String(localized: "BrowserManager.WebPageAlert", defaultValue: "Web Page Alert", comment: "Title for a JavaScript alert dialog")
        warning.title = message
        warning.actionLabels = [iTermLocalizedOK()]
        warning.warningType = .kiTermWarningTypePersistent
        warning.runModal()
    }

    // Returns whether the user chose OK.
    static func confirm(message: String) -> Bool {
        let warning = iTermWarning()
        warning.heading = String(localized: "BrowserManager.WebPageConfirmation", defaultValue: "Web Page Confirmation", comment: "Title for a JavaScript confirmation dialog")
        warning.title = message
        warning.actionLabels = [iTermLocalizedOK(), iTermLocalizedCancel()]
        warning.cancelLabel = iTermLocalizedCancel()
        warning.warningType = .kiTermWarningTypePersistent
        return warning.runModal() == .kiTermWarningSelection0
    }
}
