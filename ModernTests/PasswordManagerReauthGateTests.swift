//
//  PasswordManagerReauthGateTests.swift
//  ModernTests
//
//  The password manager caches a successful Touch ID / password authentication on
//  a process-lifetime singleton, so once you unlock it once, subsequent opens
//  (⌥⌘F, from a profile, a new window) skip the prompt until the screen locks.
//  "Require Authentication on Every Open" opts out of that reuse so every open
//  re-prompts. The decision is factored into a pure function so it can be tested
//  without LocalAuthentication: a cached authentication may be reused unless the
//  user requires authentication on every open, and the every-open preference only
//  applies when authentication is required at all.
//

import XCTest
@testable import iTerm2SharedARC

final class PasswordManagerReauthGateTests: XCTestCase {
    func testReusesCachedAuthByDefault() {
        // Auth required, every-open off: the historical behavior. Reuse the cache.
        XCTAssertTrue(PasswordManagerDataSourceProvider.mayReuseAuthentication(authRequired: true,
                                                                               requireEveryOpen: false))
    }

    func testEveryOpenForcesReauth() {
        // Auth required, every-open on: never reuse; force a fresh prompt each open.
        XCTAssertFalse(PasswordManagerDataSourceProvider.mayReuseAuthentication(authRequired: true,
                                                                                requireEveryOpen: true))
    }

    func testEveryOpenIsMootWhenAuthNotRequired() {
        // With authentication not required there is no prompt to force, so the
        // every-open preference cannot lock the user out of an unprotected manager.
        XCTAssertTrue(PasswordManagerDataSourceProvider.mayReuseAuthentication(authRequired: false,
                                                                               requireEveryOpen: true))
        XCTAssertTrue(PasswordManagerDataSourceProvider.mayReuseAuthentication(authRequired: false,
                                                                               requireEveryOpen: false))
    }

    // The settings menu shows the three stored settings as one exclusive choice.
    private func mode(_ authRequired: Bool,
                      _ afterScreenLocks: Bool,
                      _ everyOpen: Bool) -> PasswordManagerAuthenticationMode {
        return PasswordManagerDataSourceProvider.authenticationMode(authRequired: authRequired,
                                                                    afterScreenLocks: afterScreenLocks,
                                                                    everyOpen: everyOpen)
    }

    func testModeIsNeverWhenAuthNotRequired() {
        // Leftover sub-settings from before authentication was turned off don't matter.
        XCTAssertEqual(mode(false, false, false), .never)
        XCTAssertEqual(mode(false, true, false), .never)
        XCTAssertEqual(mode(false, false, true), .never)
        XCTAssertEqual(mode(false, true, true), .never)
    }

    func testModeOncePerLaunch() {
        XCTAssertEqual(mode(true, false, false), .oncePerLaunch)
    }

    func testModeOncePerLaunchAndAfterScreenLocks() {
        XCTAssertEqual(mode(true, true, false), .oncePerLaunchAndAfterScreenLocks)
    }

    func testEveryOpenTakesPrecedenceOverAfterScreenLocks() {
        XCTAssertEqual(mode(true, false, true), .everyOpen)
        XCTAssertEqual(mode(true, true, true), .everyOpen)
    }

    func testScreenLockRequiresAuthenticationOnlyForModesThatPromptAfterALock() {
        // These modes revoke the cached authentication and close an open window
        // when the screen locks.
        XCTAssertTrue(PasswordManagerDataSourceProvider.requiresAuthenticationAfterScreenLock(mode: .oncePerLaunchAndAfterScreenLocks))
        XCTAssertTrue(PasswordManagerDataSourceProvider.requiresAuthenticationAfterScreenLock(mode: .everyOpen))
        XCTAssertFalse(PasswordManagerDataSourceProvider.requiresAuthenticationAfterScreenLock(mode: .oncePerLaunch))
        XCTAssertFalse(PasswordManagerDataSourceProvider.requiresAuthenticationAfterScreenLock(mode: .never))
    }

    // F-098: a screen lock must revoke the cached authentication even when it was
    // obtained without ever opening the password manager window (for example, by
    // saving a browser basic-auth credential). The provider observes the lock itself,
    // so no window or view controller has to exist. A private notification center
    // stands in for the distributed one so the test doesn't post a real system-wide
    // screen-lock notification.
    private static let screenIsLocked = Notification.Name("com.apple.screenIsLocked")

    private func makeProvider(center: NotificationCenter,
                              mode: PasswordManagerAuthenticationMode) -> PasswordManagerDataSourceProvider {
        return PasswordManagerDataSourceProvider(browser: true,
                                                 screenLockNotificationCenter: center,
                                                 authenticationMode: { mode })
    }

    func testScreenLockRevokesAuthenticationWithoutAWindow() {
        let center = NotificationCenter()
        let provider = makeProvider(center: center, mode: .oncePerLaunchAndAfterScreenLocks)
        provider.markAuthenticatedForTesting()
        XCTAssertTrue(provider.authenticated)

        center.post(name: Self.screenIsLocked, object: nil)

        XCTAssertFalse(provider.authenticated)
    }

    func testScreenLockRevokesAuthenticationInEveryOpenMode() {
        let center = NotificationCenter()
        let provider = makeProvider(center: center, mode: .everyOpen)
        provider.markAuthenticatedForTesting()

        center.post(name: Self.screenIsLocked, object: nil)

        XCTAssertFalse(provider.authenticated)
    }

    func testScreenLockKeepsAuthenticationInOncePerLaunchMode() {
        let center = NotificationCenter()
        let provider = makeProvider(center: center, mode: .oncePerLaunch)
        provider.markAuthenticatedForTesting()

        center.post(name: Self.screenIsLocked, object: nil)

        XCTAssertTrue(provider.authenticated)
    }
}

// Remembered basic-auth credentials are filled in silently only when the browser password
// manager can be read without an authentication prompt. A challenge is not the user opening the
// password manager, so it must never raise one; when a prompt would be needed the plain
// basic-auth sheet is shown instead, and the user can ask for the password manager from it.
final class BrowserBasicAuthSilentLookupGateTests: XCTestCase {
    private func readable(authenticated: Bool,
                          authRequired: Bool,
                          requireEveryOpen: Bool) -> Bool {
        return iTermBrowserBasicAuthStore.isReadableWithoutPrompt(authenticated: authenticated,
                                                                 authRequired: authRequired,
                                                                 requireEveryOpen: requireEveryOpen)
    }

    func testReadableWhenAuthenticationNotRequired() {
        XCTAssertTrue(readable(authenticated: false, authRequired: false, requireEveryOpen: false))
        XCTAssertTrue(readable(authenticated: false, authRequired: false, requireEveryOpen: true))
    }

    func testReadableWhenUnlockedOncePerLaunch() {
        XCTAssertTrue(readable(authenticated: true, authRequired: true, requireEveryOpen: false))
    }

    func testNotReadableWhenLocked() {
        XCTAssertFalse(readable(authenticated: false, authRequired: true, requireEveryOpen: false))
        XCTAssertFalse(readable(authenticated: false, authRequired: true, requireEveryOpen: true))
    }

    func testNotReadableInEveryOpenModeEvenAfterAnEarlierUnlock() {
        // Every open authenticates afresh, so an earlier unlock cannot be reused and reading
        // would prompt. A basic-auth challenge must show the plain sheet rather than prompt.
        XCTAssertFalse(readable(authenticated: true, authRequired: true, requireEveryOpen: true))
    }
}

// F-147: in “Require Authentication on Every Open” mode the provider stays authenticated
// after the first unlock of the launch, but each new password manager window prompts
// again. The window must not show any accounts behind that prompt. Each window owns a
// gate that says whether it may show account data; it opens only once this window’s
// own authentication has succeeded, or when an earlier unlock may be reused.
final class PasswordManagerOpenGateTests: XCTestCase {
    private func makeProvider(center: NotificationCenter = NotificationCenter(),
                              mode: PasswordManagerAuthenticationMode = .everyOpen) -> PasswordManagerDataSourceProvider {
        return PasswordManagerDataSourceProvider(browser: true,
                                                 screenLockNotificationCenter: center,
                                                 authenticationMode: { mode })
    }

    func testEveryOpenAfterEarlierUnlockHidesAccountsUntilThisOpenAuthenticates() {
        let provider = makeProvider()
        provider.markAuthenticatedForTesting()  // unlocked earlier in this launch

        let gate = PasswordManagerOpenGate(provider: provider, mayReuseAuthentication: false)

        XCTAssertTrue(gate.needsAuthentication)
        XCTAssertFalse(gate.unlocked, "accounts must not be shown behind the every-open prompt")

        gate.authenticationDidComplete(true)

        XCTAssertFalse(gate.needsAuthentication)
        XCTAssertTrue(gate.unlocked)
    }

    func testEveryOpenFailedAuthenticationStaysLocked() {
        let provider = makeProvider()
        provider.markAuthenticatedForTesting()
        let gate = PasswordManagerOpenGate(provider: provider, mayReuseAuthentication: false)

        gate.authenticationDidComplete(false)

        XCTAssertFalse(gate.unlocked)
    }

    func testReusableEarlierUnlockShowsAccountsImmediately() {
        // Once per launch (with or without after-screen-locks), or authentication off:
        // an earlier unlock is reused, so there is no prompt and nothing to hide.
        let provider = makeProvider(mode: .oncePerLaunch)
        provider.markAuthenticatedForTesting()

        let gate = PasswordManagerOpenGate(provider: provider, mayReuseAuthentication: true)

        XCTAssertFalse(gate.needsAuthentication)
        XCTAssertTrue(gate.unlocked)
    }

    func testFirstOpenOfLaunchIsLockedUntilAuthenticated() {
        let provider = makeProvider()

        let gate = PasswordManagerOpenGate(provider: provider, mayReuseAuthentication: true)

        XCTAssertTrue(gate.needsAuthentication)
        XCTAssertFalse(gate.unlocked)

        provider.markAuthenticatedForTesting()  // what a successful prompt does
        gate.authenticationDidComplete(true)

        XCTAssertTrue(gate.unlocked)
    }

    func testScreenLockLocksAnAuthenticatedWindow() {
        // A screen lock revokes the provider's authentication; the window must not keep
        // showing accounts on the strength of its own earlier success.
        let center = NotificationCenter()
        let provider = makeProvider(center: center)
        provider.markAuthenticatedForTesting()
        let gate = PasswordManagerOpenGate(provider: provider, mayReuseAuthentication: false)
        gate.authenticationDidComplete(true)
        XCTAssertTrue(gate.unlocked)

        center.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)

        XCTAssertFalse(gate.unlocked)
    }

    // A failed or cancelled prompt from any window (or a screen lock) revokes the
    // provider's authentication, which locks every open window. A window that already
    // loaded rows must clear them right away rather than keep showing account names and
    // user names until it next reloads, so the gate tells it when it locks.
    func testRevokingAuthenticationTellsAnUnlockedWindowToClearItsRows() {
        let provider = makeProvider()
        provider.markAuthenticatedForTesting()
        let gate = PasswordManagerOpenGate(provider: provider, mayReuseAuthentication: false)
        gate.authenticationDidComplete(true)
        var lockCount = 0
        gate.didLock = { lockCount += 1 }

        provider.revokeAuthentication()

        XCTAssertFalse(gate.unlocked)
        XCTAssertEqual(lockCount, 1)
    }

    func testScreenLockTellsAnUnlockedWindowToClearItsRows() {
        let center = NotificationCenter()
        let provider = makeProvider(center: center, mode: .oncePerLaunchAndAfterScreenLocks)
        provider.markAuthenticatedForTesting()
        let gate = PasswordManagerOpenGate(provider: provider, mayReuseAuthentication: true)
        XCTAssertTrue(gate.unlocked)
        var lockCount = 0
        gate.didLock = { lockCount += 1 }

        center.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)

        XCTAssertEqual(lockCount, 1)
    }

    func testOtherProvidersRevocationDoesNotLockThisWindow() {
        // The terminal and browser password managers authenticate separately.
        let provider = makeProvider()
        provider.markAuthenticatedForTesting()
        let other = makeProvider()
        other.markAuthenticatedForTesting()
        let gate = PasswordManagerOpenGate(provider: provider, mayReuseAuthentication: true)
        var lockCount = 0
        gate.didLock = { lockCount += 1 }

        other.revokeAuthentication()

        XCTAssertTrue(gate.unlocked)
        XCTAssertEqual(lockCount, 0)
    }

    func testWindowAwaitingItsOwnPromptIsNotToldToLock() {
        // It shows nothing yet, and its own prompt's result decides what happens to it.
        let provider = makeProvider()
        provider.markAuthenticatedForTesting()
        let gate = PasswordManagerOpenGate(provider: provider, mayReuseAuthentication: false)
        var lockCount = 0
        gate.didLock = { lockCount += 1 }

        provider.revokeAuthentication()

        XCTAssertEqual(lockCount, 0)

        // Its own prompt then succeeds, which authenticates the provider again.
        provider.markAuthenticatedForTesting()
        gate.authenticationDidComplete(true)

        XCTAssertTrue(gate.unlocked)
    }

    func testRevokedWindowStaysLockedWhenAnotherCallerAuthenticates() {
        // Once revoked, this open is over. Another window's successful prompt must not
        // unlock it without its own authentication.
        let provider = makeProvider()
        provider.markAuthenticatedForTesting()
        let gate = PasswordManagerOpenGate(provider: provider, mayReuseAuthentication: false)
        gate.authenticationDidComplete(true)

        provider.revokeAuthentication()
        provider.markAuthenticatedForTesting()

        XCTAssertFalse(gate.unlocked)
    }

    func testRevokingWhileAlreadyUnauthenticatedDoesNotNotify() {
        let provider = makeProvider()
        let gate = PasswordManagerOpenGate(provider: provider, mayReuseAuthentication: true)
        var lockCount = 0
        gate.didLock = { lockCount += 1 }

        provider.revokeAuthentication()

        XCTAssertEqual(lockCount, 0)
    }
}

// The standalone password manager window (used when no terminal window exists) is kept
// and reused across opens. Each open after it was closed must go through the open gate
// again, exactly like a fresh window, so every-open mode prompts every time and the
// screen-lock modes prompt after a lock instead of showing the old window.
final class PasswordManagerStandaloneOpenTests: XCTestCase {
    func testFirstOpenCreatesAWindow() {
        XCTAssertEqual(PasswordManagerStandaloneOpen.action(hasWindowController: false,
                                                            windowIsOpen: false),
                       .create)
    }

    func testReopeningAClosedWindowAuthenticatesAgain() {
        XCTAssertEqual(PasswordManagerStandaloneOpen.action(hasWindowController: true,
                                                            windowIsOpen: false),
                       .reopen)
    }

    func testOpeningAWindowThatIsStillOpenJustBringsItForward() {
        // Still the same open: its own prompt (if any) is already up or has succeeded.
        XCTAssertEqual(PasswordManagerStandaloneOpen.action(hasWindowController: true,
                                                            windowIsOpen: true),
                       .bringToFront)
    }
}
