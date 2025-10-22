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

    // Keep this object alive until the completion block runs.
    private var keepalive: ModalPasswordAlert?

    init(_ prompt: String) {
        self.prompt = prompt
    }

    private struct Views {
        var alert: NSAlert
        var newPassword: NSSecureTextField
        var usernameField: NSTextField?
    }

    func run(window: NSWindow?) -> String? {
        let views = makeAlert()
        let alert = views.alert
        let newPassword = views.newPassword
        scheduleTimer(views: views)

        let result = { () -> NSApplication.ModalResponse in
            if let window = window, window.isVisible {
                return alert.runSheetModal(for: window)
            } else {
                return alert.runModal()
            }
        }()
        if result == .alertFirstButtonReturn {
            username = views.usernameField?.stringValue
            return newPassword.stringValue
        }
        return nil
    }

    func runAsync(window: NSWindow?, completion: @escaping (String?) -> ()) {
        precondition(keepalive == nil)
        keepalive = self
        let views = makeAlert()
        scheduleTimer(views: views)
        if let window {
            views.alert.beginSheetModal(for: window) { [weak self] response in
                self?.handleAsyncCompletion(response,
                                            views: views,
                                            completion: completion)
            }
        } else {
            handleAsyncCompletion(views.alert.runModal(),
                                  views: views,
                                  completion: completion)
        }
    }

    private func handleAsyncCompletion(_ response: NSApplication.ModalResponse,
                                       views: Views,
                                       completion: @escaping (String?) -> ()) {
        if response == .alertFirstButtonReturn {
            username = views.usernameField?.stringValue
            completion(views.newPassword.stringValue)
        } else {
            completion(nil)
        }
        keepalive = nil
    }

    private func scheduleTimer(views: Views) {
        let timer = Timer(timeInterval: 0, repeats: false) { [weak self] _ in
            guard let self = self else {
                return
            }
            views.alert.layout()
            if let username = self.username, !username.isEmpty {
                views.newPassword.window?.makeFirstResponder(views.newPassword)
            } else if let usernameField = views.usernameField {
                usernameField.window?.makeFirstResponder(usernameField)
            } else {
                views.newPassword.window?.makeFirstResponder(views.newPassword)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func makeAlert() -> Views {
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
            field.nextKeyView = newPassword
            newPassword.nextKeyView = field
        } else {
            usernameField = nil
        }

        wrapper.addArrangedSubview(newPassword)


        alert.accessoryView = wrapper
        return Views(alert: alert,
                     newPassword: newPassword,
                     usernameField: usernameField)
    }
}
