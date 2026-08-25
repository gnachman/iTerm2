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

    // Optional initial value for the password field (e.g. a remembered password that
    // just failed, so the user can correct it). Nil leaves the field empty.
    var initialPassword: String?

    // When true, a "Remember this password" checkbox is shown. Its state after the user
    // dismisses the alert is available in `rememberChecked`. Off by default so existing
    // callers are unaffected.
    var showRememberCheckbox = false
    // Initial state of the Remember checkbox.
    var rememberByDefault = false
    // The Remember checkbox state when OK was clicked (false on cancel).
    private(set) var rememberChecked = false

    // When true, a "Password Manager" button is added. Used by runAsyncOutcome, which
    // reports it via .passwordManager. Off by default so existing callers are unaffected.
    var showPasswordManagerButton = false

    // How the user dismissed the alert when using runAsyncOutcome.
    enum Outcome: Equatable {
        case ok(password: String)
        case cancel
        // Carries whatever the user had typed into the password field, so the caller can
        // pre-fill it if the user backs out of the password manager.
        case passwordManager(typedPassword: String)
    }

    // Keep this object alive until the completion block runs.
    private var keepalive: ModalPasswordAlert?

    init(_ prompt: String) {
        self.prompt = prompt
    }

    private struct Views {
        var alert: NSAlert
        var newPassword: NSSecureTextField
        var usernameField: NSTextField?
        var rememberCheckbox: NSButton?
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
            rememberChecked = (views.rememberCheckbox?.state == .on)
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

    // Like runAsync, but reports a three-way outcome so the caller can distinguish the
    // "Password Manager" button (shown when showPasswordManagerButton is true) from OK
    // and Cancel.
    func runAsyncOutcome(window: NSWindow?, completion: @escaping (Outcome) -> ()) {
        precondition(keepalive == nil)
        keepalive = self
        let views = makeAlert()
        scheduleTimer(views: views)
        if let window {
            views.alert.beginSheetModal(for: window) { [weak self] response in
                self?.handleAsyncOutcome(response, views: views, completion: completion)
            }
        } else {
            handleAsyncOutcome(views.alert.runModal(), views: views, completion: completion)
        }
    }

    private func handleAsyncOutcome(_ response: NSApplication.ModalResponse,
                                    views: Views,
                                    completion: @escaping (Outcome) -> ()) {
        switch response {
        case .alertFirstButtonReturn:
            username = views.usernameField?.stringValue
            rememberChecked = (views.rememberCheckbox?.state == .on)
            completion(.ok(password: views.newPassword.stringValue))
        case .alertThirdButtonReturn:
            // Preserve anything the user already typed so it can pre-fill the dialog if they
            // back out of the password manager.
            username = views.usernameField?.stringValue
            completion(.passwordManager(typedPassword: views.newPassword.stringValue))
        default:
            completion(.cancel)
        }
        keepalive = nil
    }

    private func handleAsyncCompletion(_ response: NSApplication.ModalResponse,
                                       views: Views,
                                       completion: @escaping (String?) -> ()) {
        if response == .alertFirstButtonReturn {
            username = views.usernameField?.stringValue
            rememberChecked = (views.rememberCheckbox?.state == .on)
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
        if showPasswordManagerButton {
            alert.addButton(withTitle: "Password Manager")
        }

        let newPassword = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        newPassword.isEditable = true
        newPassword.isSelectable = true
        newPassword.placeholderString = "Password"
        if let initialPassword {
            newPassword.stringValue = initialPassword
        }

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

        let rememberCheckbox: NSButton?
        if showRememberCheckbox {
            let checkbox = NSButton(checkboxWithTitle: "Remember this password", target: nil, action: nil)
            checkbox.state = rememberByDefault ? .on : .off
            rememberCheckbox = checkbox
            wrapper.addArrangedSubview(checkbox)
        } else {
            rememberCheckbox = nil
        }

        alert.accessoryView = wrapper
        return Views(alert: alert,
                     newPassword: newPassword,
                     usernameField: usernameField,
                     rememberCheckbox: rememberCheckbox)
    }
}
