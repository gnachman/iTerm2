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
    static func show(window: NSWindow, defaultName: String, completion: (String) -> ()) {
        // Create the modal dialog
        let alert = NSAlert()
        alert.messageText = "Enter Mark Name"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        // Create the text field
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = defaultName
        alert.accessoryView = textField

        // Make the text field the first responder
        DispatchQueue.main.async {
            textField.becomeFirstResponder()
        }

        // Run the modal dialog
        let response = alert.runSheetModal(for: window)

        if response == NSApplication.ModalResponse.alertFirstButtonReturn { // OK button clicked
            let name = textField.stringValue
            guard !name.isEmpty else {
                return // Don't proceed with empty name
            }
            completion(name)
        }
    }

    @objc(showInWindow:withCompletion:)
    static func show(window: NSWindow, completion: (String) -> ()) {
        show(window: window, defaultName: currentDateTimeString(), completion: completion)
    }

    private static func currentDateTimeString() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return dateFormatter.string(from: Date())
    }
}
