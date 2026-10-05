//
//  BookmarkDialogViewController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/21/23.
//

import Cocoa

@objc(iTermBookmarkDialogViewController)
class BookmarkDialogViewController: NSObject {
    @objc(showInWindow:withDefaultName:completion:)
    static func show(window: NSWindow, defaultName: String, completion: @escaping (String) -> ()) {
        // Create the text field
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = defaultName

        // Create the modal dialog
        let warning = iTermWarning()
        warning.heading = String(localized: "BookmarkDialog.EnterName", defaultValue: "Enter Mark Name", comment: "Prompt asking the user to enter a name for a mark")
        warning.title = ""
        warning.actionLabels = [iTermLocalizedOK(), iTermLocalizedCancel()]
        warning.cancelLabel = iTermLocalizedCancel()
        warning.warningType = .kiTermWarningTypePersistent
        warning.accessory = textField
        warning.remoteInputs = [.textInput(withIdentifier: "name",  // Localization unneeded
                                           label: nil,
                                           textField: textField)]
        warning.initialFirstResponder = textField
        warning.window = window

        // Run the modal dialog
        warning.runModalAsync { selection, _ in
            if selection == .kiTermWarningSelection0 { // OK button clicked
                let name = textField.stringValue
                guard !name.isEmpty else {
                    return // Don't proceed with empty name
                }
                completion(name)
            }
        }
    }

    @objc(showInWindow:withCompletion:)
    static func show(window: NSWindow, completion: @escaping (String) -> ()) {
        show(window: window, defaultName: currentDateTimeString(), completion: completion)
    }

    private static func currentDateTimeString() -> String {
        let dateFormatter = DateFormatter()
        // Localization unneeded
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return dateFormatter.string(from: Date())
    }
}
