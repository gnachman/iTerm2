//
//  PasswordManagerOpenGate.swift
//  iTerm2SharedARC
//
//  Decides whether one password manager window may show account data.
//

import Foundation

// The provider caches a successful authentication for the whole launch, but in
// “Require Authentication on Every Open” mode each window must authenticate again before
// it reveals anything. Each window owns one of these, so it shows no accounts while its
// own authentication prompt is up, even though the provider is still authenticated from
// an earlier open. Pure state so it can be unit tested without LocalAuthentication.
@objc(iTermPasswordManagerOpenGate)
final class PasswordManagerOpenGate: NSObject {
    private let provider: PasswordManagerDataSourceProvider
    private var authenticatedForThisOpen: Bool

    // Called when the provider's authentication is revoked (a failed or cancelled prompt
    // from any window, or a screen lock) while this window was unlocked. The window stops
    // showing the account names and user names it already loaded.
    @objc var didLock: (() -> Void)?

    @objc convenience init(provider: PasswordManagerDataSourceProvider) {
        self.init(provider: provider,
                  mayReuseAuthentication: provider.mayReuseAuthenticationOnOpen)
    }

    init(provider: PasswordManagerDataSourceProvider, mayReuseAuthentication: Bool) {
        self.provider = provider
        // An earlier unlock counts for this window only when the mode lets it be reused.
        authenticatedForThisOpen = provider.authenticated && mayReuseAuthentication
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(providerDidRevokeAuthentication(_:)),
            name: PasswordManagerDataSourceProvider.didRevokeAuthenticationNotification,
            object: provider)
    }

    // Whether this window must request authentication before it may show accounts.
    @objc var needsAuthentication: Bool {
        return !unlocked
    }

    // Records the result of this window's authentication request.
    @objc func authenticationDidComplete(_ success: Bool) {
        authenticatedForThisOpen = success
    }

    // Revocation ends this open: it stays locked even if another caller authenticates
    // later. Only a window that was unlocked is told, since a window still waiting on its
    // own prompt shows nothing and that prompt's result decides what happens to it.
    @objc private func providerDidRevokeAuthentication(_ notification: Notification) {
        let wasUnlocked = authenticatedForThisOpen
        authenticatedForThisOpen = false
        guard wasUnlocked else {
            return
        }
        DLog("Password manager authentication revoked. Lock this window.")
        didLock?()
    }

    // Whether this window may show account data now. A screen lock revokes the
    // provider's authentication, which locks every window.
    @objc var unlocked: Bool {
        return authenticatedForThisOpen && provider.authenticated
    }
}

// The standalone password manager window (used when no terminal window exists) is kept
// and reused across opens. Opening it again after it was closed must go through the open
// gate again, just like a fresh window, so every-open mode prompts every time and the
// screen-lock modes prompt after a lock. Pure so it can be unit tested.
@objc(iTermPasswordManagerStandaloneOpenAction)
enum PasswordManagerStandaloneOpenAction: Int {
    // No window yet: create one, which authenticates as it opens.
    case create
    // The window was closed: reset its gate and authenticate again before showing accounts.
    case reopen
    // The window is still open: this is the same open, so just bring it forward.
    case bringToFront
}

@objc(iTermPasswordManagerStandaloneOpen)
final class PasswordManagerStandaloneOpen: NSObject {
    @objc static func action(hasWindowController: Bool,
                             windowIsOpen: Bool) -> PasswordManagerStandaloneOpenAction {
        guard hasWindowController else {
            return .create
        }
        return windowIsOpen ? .bringToFront : .reopen
    }
}
