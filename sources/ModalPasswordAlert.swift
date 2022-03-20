//
//  ModalPasswordAlert.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/19/22.
//

import AppKit

class ModalPasswordAlert {
    private let prompt: String

    init(_ prompt: String) {
        self.prompt = prompt
    }

    func run(window: NSWindow?) -> String? {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let newPassword = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        newPassword.isEditable = true
        newPassword.isSelectable = true
        alert.accessoryView = newPassword
        alert.layout()
        alert.window.makeFirstResponder(newPassword)

        let result = { () -> NSApplication.ModalResponse in
            if let window = window, window.isVisible {
                return alert.runSheetModal(for: window)
            } else {
                return alert.runModal()
            }
        }()
        if result == .alertFirstButtonReturn {
            return newPassword.stringValue
        }
        return nil
    }
}
