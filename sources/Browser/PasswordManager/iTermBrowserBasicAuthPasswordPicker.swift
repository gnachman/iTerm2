//
//  iTermBrowserBasicAuthPasswordPicker.swift
//  iTerm2
//
//  Presents the browser password manager so the user can pick an entry to answer an HTTP
//  basic-auth challenge, then delivers the chosen username/password back via completion.
//  This reuses the same password-manager UI (and whatever backend the user has chosen)
//  as the rest of the browser, rather than a bespoke picker.
//

import AppKit

@MainActor
@objc class iTermBrowserBasicAuthPasswordPicker: NSObject, @preconcurrency iTermPasswordManagerDelegate {
    private var windowController: iTermBrowserPasswordManagerWindowController?
    private var pendingUserName: String?
    private var completion: ((iTermBrowserBasicAuthStore.Credential?) -> Void)?
    // Keep self alive until the window closes; the window controller holds `delegate`
    // unretained.
    private var keepalive: iTermBrowserBasicAuthPasswordPicker?

    // Present the password manager, pre-selecting `accountName` if it exists. The
    // completion is called exactly once: with the chosen credential, or nil if the user
    // closed the picker without choosing one.
    func present(in parentWindow: NSWindow?,
                 accountName: String,
                 completion: @escaping (iTermBrowserBasicAuthStore.Credential?) -> Void) {
        self.completion = completion
        keepalive = self

        let windowController = iTermBrowserPasswordManagerWindowController()
        windowController.delegate = self
        // Non-nil didSendUserName plus sendUserByDefault makes the default button send
        // BOTH the user name and the password, so we receive each via the delegate.
        windowController.sendUserByDefault = true
        windowController.didSendUserName = { }
        self.windowController = windowController

        guard let window = windowController.window else {
            finish(nil)
            return
        }
        if let parentWindow, parentWindow.isVisible {
            parentWindow.beginSheet(window) { _ in }
        } else {
            window.makeKeyAndOrderFront(nil)
        }
        windowController.selectAccountName(accountName)
    }

    // MARK: - iTermPasswordManagerDelegate

    func iTermPasswordManagerCanEnterPassword() -> Bool { true }

    func iTermPasswordManagerCanEnterUserName() -> Bool { true }

    func iTermPasswordManagerCanBroadcast() -> Bool { false }

    func iTermPasswordManagerEnterUserName(_ username: String, broadcast: Bool) {
        // Sent just before the password in send-both mode.
        pendingUserName = username
    }

    func iTermPasswordManagerEnterPassword(_ password: String, broadcast: Bool) {
        finish(iTermBrowserBasicAuthStore.Credential(user: pendingUserName ?? "", password: password))
    }

    func iTermPasswordManagerDidClose() {
        // Fires on any close, including cancel. No-op if a credential was already
        // delivered (finish clears the completion).
        finish(nil)
    }

    private func finish(_ credential: iTermBrowserBasicAuthStore.Credential?) {
        guard let completion else {
            return
        }
        self.completion = nil
        // iTermPasswordManagerDidClose is delivered synchronously from deep inside the
        // window controller's own close path (sendDidClose during orderOutOrEndSheet). The
        // controller holds our delegate unretained, and we (plus the browser manager) hold
        // the only strong references to it. Releasing the controller here would deallocate
        // it while its own method is still unwinding on the stack - a use-after-free. So
        // drop the controller's delegate immediately (nothing more should call back), but
        // defer releasing the controller and self to the next runloop turn, after the close
        // has finished unwinding. The completion (which clears the manager's strong ref to
        // us) is likewise deferred so `self` outlives this callback.
        windowController?.delegate = nil
        Task { @MainActor [self] in
            windowController = nil
            completion(credential)
            keepalive = nil
        }
    }
}
