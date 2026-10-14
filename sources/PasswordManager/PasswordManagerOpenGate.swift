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

    @objc convenience init(provider: PasswordManagerDataSourceProvider) {
        self.init(provider: provider,
                  mayReuseAuthentication: provider.mayReuseAuthenticationOnOpen)
    }

    init(provider: PasswordManagerDataSourceProvider, mayReuseAuthentication: Bool) {
        self.provider = provider
        // An earlier unlock counts for this window only when the mode lets it be reused.
        authenticatedForThisOpen = provider.authenticated && mayReuseAuthentication
        super.init()
    }

    // Whether this window must request authentication before it may show accounts.
    @objc var needsAuthentication: Bool {
        return !unlocked
    }

    // Records the result of this window's authentication request.
    @objc func authenticationDidComplete(_ success: Bool) {
        authenticatedForThisOpen = success
    }

    // Whether this window may show account data now. A screen lock revokes the
    // provider's authentication, which locks every window.
    @objc var unlocked: Bool {
        return authenticatedForThisOpen && provider.authenticated
    }
}
