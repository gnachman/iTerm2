//
//  ModalPasswordAlert.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/19/22.
//

import AppKit

class ModalPasswordAlert {
    private let prompt: String
    var username: String?

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
        newPassword.placeholderString = "Password"

        let wrapper = NSStackView()
        wrapper.orientation = .vertical
        wrapper.distribution = .fillEqually
        wrapper.alignment = .leading
        wrapper.spacing = 5
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addConstraint(NSLayoutConstraint(item: wrapper,
                                                 attribute: .width,
                                                 relatedBy: .equal,
                                                 toItem: nil,
                                                 attribute: .notAnAttribute,
                                                 multiplier: 1,
                                                 constant: 200))
        let usernameField: NSTextField?
        if let username = username {
            let field = NSTextField(frame: newPassword.frame)
            usernameField = field
            field.isEditable = true
            field.isSelectable = true
            field.stringValue = username
            field.placeholderString = "User name"

            wrapper.addArrangedSubview(field)
            field.nextResponder = newPassword
        } else {
            usernameField = nil
        }

        wrapper.addArrangedSubview(newPassword)

        alert.accessoryView = wrapper
        let timer = Timer(timeInterval: 0, repeats: false) { _ in
            NSLog("Perform layout")
            alert.layout()
            newPassword.window?.makeFirstResponder(newPassword)
        }
        RunLoop.main.add(timer, forMode: .common)

        let result = { () -> NSApplication.ModalResponse in
            if let window = window, window.isVisible {
                return alert.runSheetModal(for: window)
            } else {
                return alert.runModal()
            }
        }()
        if result == .alertFirstButtonReturn {
            username = usernameField?.stringValue
            return newPassword.stringValue
        }
        return nil
    }
}
