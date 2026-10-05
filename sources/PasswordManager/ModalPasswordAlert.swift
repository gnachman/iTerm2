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

    // Optional explanation shown under the prompt, such as why the last attempt failed.
    var detail: String?

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
        var warning: iTermWarning
        var newPassword: NSSecureTextField
        var usernameField: NSTextField?
        var rememberCheckbox: NSButton?
    }

    // The order of the warning's actions.
    private static let okSelection = iTermWarningSelection.kiTermWarningSelection0
    private static let passwordManagerSelection = iTermWarningSelection.kiTermWarningSelection2

    func run(window: NSWindow?) -> String? {
        let views = makeAlert()
        if let window, window.isVisible {
            views.warning.window = window
        }
        if views.warning.runModal() == Self.okSelection {
            username = views.usernameField?.stringValue
            rememberChecked = (views.rememberCheckbox?.state == .on)
            return views.newPassword.stringValue
        }
        return nil
    }

    func runAsync(window: NSWindow?, completion: @escaping (String?) -> ()) {
        precondition(keepalive == nil)
        keepalive = self
        let views = makeAlert()
        views.warning.window = window
        views.warning.runModalAsync { [weak self] selection, _ in
            self?.handleAsyncCompletion(selection, views: views, completion: completion)
        }
    }

    // Like runAsync, but reports a three-way outcome so the caller can distinguish the
    // "Password Manager" button (shown when showPasswordManagerButton is true) from OK
    // and Cancel.
    func runAsyncOutcome(window: NSWindow?, completion: @escaping (Outcome) -> ()) {
        precondition(keepalive == nil)
        keepalive = self
        let views = makeAlert()
        views.warning.window = window
        views.warning.runModalAsync { [weak self] selection, _ in
            self?.handleAsyncOutcome(selection, views: views, completion: completion)
        }
    }

    private func handleAsyncOutcome(_ selection: iTermWarningSelection,
                                    views: Views,
                                    completion: @escaping (Outcome) -> ()) {
        switch selection {
        case Self.okSelection:
            username = views.usernameField?.stringValue
            rememberChecked = (views.rememberCheckbox?.state == .on)
            completion(.ok(password: views.newPassword.stringValue))
        case Self.passwordManagerSelection:
            // Preserve anything the user already typed so it can pre-fill the dialog if they
            // back out of the password manager.
            username = views.usernameField?.stringValue
            completion(.passwordManager(typedPassword: views.newPassword.stringValue))
        default:
            completion(.cancel)
        }
        keepalive = nil
    }

    private func handleAsyncCompletion(_ selection: iTermWarningSelection,
                                       views: Views,
                                       completion: @escaping (String?) -> ()) {
        if selection == Self.okSelection {
            username = views.usernameField?.stringValue
            rememberChecked = (views.rememberCheckbox?.state == .on)
            completion(views.newPassword.stringValue)
        } else {
            completion(nil)
        }
        keepalive = nil
    }

    private func makeAlert() -> Views {
        // An iTermWarning so the companion app can show the prompt and answer it.
        let warning = iTermWarning()
        warning.heading = prompt
        warning.title = detail ?? ""
        var actions = [iTermLocalizedOK(), iTermLocalizedCancel()]
        if showPasswordManagerButton {
            actions.append(String(localized: "ModalPasswordAlert.PasswordManagerButton", defaultValue: "Password Manager", comment: "Button to open the password manager"))
        }
        warning.actionLabels = actions
        if showPasswordManagerButton {
            // It opens the password manager window on this Mac, which the companion app
            // cannot see or operate.
            warning.warningActions?.last?.notOfferedRemotely = true
        }
        warning.cancelLabel = iTermLocalizedCancel()
        warning.warningType = .kiTermWarningTypePersistent

        let newPassword = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        newPassword.isEditable = true
        newPassword.isSelectable = true
        newPassword.placeholderString = String(localized: "ModalPasswordAlert.PasswordPlaceholder", defaultValue: "Password", comment: "Placeholder for the password field")
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
            field.placeholderString = String(localized: "ModalPasswordAlert.UserNamePlaceholder", defaultValue: "User name", comment: "Placeholder for the user name field")

            wrapper.addArrangedSubview(field)
            field.nextKeyView = newPassword
            newPassword.nextKeyView = field
        } else {
            usernameField = nil
        }

        wrapper.addArrangedSubview(newPassword)

        let rememberCheckbox: NSButton?
        if showRememberCheckbox {
            let checkbox = NSButton(checkboxWithTitle: String(localized: "ModalPasswordAlert.RememberPassword", defaultValue: "Remember this password", comment: "Checkbox to remember the entered password"), target: nil, action: nil)
            checkbox.state = rememberByDefault ? .on : .off
            rememberCheckbox = checkbox
            wrapper.addArrangedSubview(checkbox)
        } else {
            rememberCheckbox = nil
        }

        // iTermWarning sizes its accessory from the view's frame, and a stack view laid out by
        // constraints has none until it is in a window. Give it a container with a real frame.
        wrapper.layoutSubtreeIfNeeded()
        let container = NSView(frame: NSRect(origin: .zero, size: wrapper.fittingSize))
        container.addSubview(wrapper)
        NSLayoutConstraint.activate([
            wrapper.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wrapper.topAnchor.constraint(equalTo: container.topAnchor),
            wrapper.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        warning.accessory = container
        var remoteInputs = [iTermWarningRemoteInput]()
        if let usernameField {
            remoteInputs.append(.textInput(withIdentifier: "username",  // Localization unneeded
                                           label: usernameField.placeholderString,
                                           textField: usernameField))
        }
        remoteInputs.append(.secretInput(withIdentifier: "password",  // Localization unneeded
                                         label: nil,
                                         textField: newPassword))
        warning.remoteInputs = remoteInputs
        warning.remoteCheckbox = rememberCheckbox
        if let usernameField, (username ?? "").isEmpty {
            warning.initialFirstResponder = usernameField
        } else {
            warning.initialFirstResponder = newPassword
        }
        return Views(warning: warning,
                     newPassword: newPassword,
                     usernameField: usernameField,
                     rememberCheckbox: rememberCheckbox)
    }
}
