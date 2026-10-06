//
//  VT100RemoteHostStampTests.swift
//  iTerm2
//
//  Drives the screen's host-reporting path (the same one OSC RemoteHost and
//  the SetHostname trigger funnel through) and asserts that locality is
//  stamped onto the VT100RemoteHost at report time.
//

import XCTest
@testable import iTerm2SharedARC

final class VT100RemoteHostStampTests: XCTestCase {
    private var session = FakeSession()

    private func makeScreen() -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal!.termType = "xterm"
            screen.destructivelySetScreenWidth(80, height: 25, mutableState: mutableState)
        })
        return screen
    }

    private func report(_ remoteHostString: String, to screen: VT100Screen) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setRemoteHostFrom(remoteHostString)
        })
    }

    private func localityAfterReporting(_ remoteHostString: String) -> VT100RemoteHostLocality {
        let screen = makeScreen()
        report(remoteHostString, to: screen)
        return screen.lastRemoteHost()?.localityState ?? .unknown
    }

    private func makeHost(_ user: String, _ host: String, _ locality: VT100RemoteHostLocality) -> VT100RemoteHost {
        return VT100RemoteHost(username: user, hostname: host, locality: locality)
    }

    // Shell integration reporting the live local hostname: stamped localhost,
    // even though a later network change could rename the machine.
    func testReportingLocalHostnameStampsLocalhost() {
        let local = "me@" + Host.fullyQualifiedDomainName()
        XCTAssertEqual(localityAfterReporting(local), .localhost)
    }

    // A hostname that isn't ours: stamped remote at report time. It stays remote
    // even if our own .local name later drifts, because the verdict is frozen
    // rather than recomputed from names.
    func testReportingForeignHostnameStampsRemote() {
        let screen = makeScreen()
        report("me@build-box.example.invalid", to: screen)
        let host = screen.lastRemoteHost()
        XCTAssertEqual(host?.localityState, .remote)
        XCTAssertEqual(host?.isRemoteHost, true)
        XCTAssertEqual(host?.isLocalhost, false)
    }

    // A user-only re-report (trailing @, empty host) backfills the hostname
    // from the previous host; its locality should carry forward rather than be
    // recomputed against the backfilled name.
    func testUserOnlyReportCarriesLocalityForward() {
        let screen = makeScreen()
        report("me@" + Host.fullyQualifiedDomainName(), to: screen)
        report("me2@", to: screen)
        XCTAssertEqual(screen.lastRemoteHost()?.localityState, .localhost,
                       "user-only report should inherit the previous host's localhost stamp")
    }

    // Unhooking a conductor SSH session restores the pre-ssh terminal config,
    // including its serialized remote host. Restoring must preserve that host's
    // locality rather than re-stamping it remote just because the restore call
    // uses ssh:YES for its (separate) host-change side-effect semantics.
    func testRestoreFromSavedStatePreservesLocalhostLocality() {
        let screen = makeScreen()
        // A pre-ssh localhost host, serialized the way VT100ScreenState saves
        // it under the "RemoteHost" key. Use a name that won't match the live
        // local hostname so a name-compare fallback couldn't accidentally pass.
        let savedHost = makeHost("me", "MacBook-Pro-was.local", .localhost)
        let terminalState: [AnyHashable: Any] = ["RemoteHost": savedHost.dictionaryValue()]
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.restore(fromSavedState: terminalState)
        })
        XCTAssertEqual(screen.lastRemoteHost()?.localityState, .localhost,
                       "restoring a pre-ssh localhost host must not re-stamp it remote")
    }
    // MARK: - Whether locality was verified (issue 13117)

    // A hostname compare is a guess, so it isn't verified, either way it goes.
    func testHostnameCompareIsNotVerified() {
        let screen = makeScreen()
        report("me@build-box.example.invalid", to: screen)
        XCTAssertEqual(screen.lastRemoteHost()?.localityVerified, false)

        let localScreen = makeScreen()
        report("me@" + Host.fullyQualifiedDomainName(), to: localScreen)
        XCTAssertEqual(localScreen.lastRemoteHost()?.localityVerified, false)
    }

    // A user-only re-report carries the previous host's verification forward along
    // with its locality.
    func testUserOnlyReportCarriesVerificationForward() {
        let screen = makeScreen()
        let token = iTermMachineIdentity.localVersion1TokenForTesting()!
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setWorkingDirectoryFromURLString("file://me@vpn-name.example/tmp?machineID=\(token)")
            mutableState.appendCarriageReturnLineFeed()
        })
        report("me2@", to: screen)
        XCTAssertEqual(screen.lastRemoteHost()?.username, "me2")
        XCTAssertEqual(screen.lastRemoteHost()?.localityVerified, true)
    }

    // Saved and restored with the host, so a restored session doesn't turn a proven
    // verdict back into a guess.
    func testVerificationSurvivesDictionaryRoundTrip() {
        let verified = VT100RemoteHost(username: "me", hostname: "box.example",
                                       locality: .remote, localityVerified: true)
        let restored = VT100RemoteHost(dictionary: verified.dictionaryValue())
        XCTAssertEqual(restored?.localityState, .remote)
        XCTAssertEqual(restored?.localityVerified, true)

        let unverified = VT100RemoteHost(username: "me", hostname: "box.example",
                                         locality: .remote, localityVerified: false)
        XCTAssertEqual(VT100RemoteHost(dictionary: unverified.dictionaryValue())?.localityVerified, false)
    }

    // Data saved before verification existed has no key for it. That verdict was a
    // hostname compare or older, so it reads back as unverified.
    func testLegacyDictionaryIsUnverified() {
        var dict = makeHost("me", "box.example", .remote).dictionaryValue() as! [String: Any]
        dict.removeValue(forKey: "Locality Verified")
        XCTAssertEqual(VT100RemoteHost(dictionary: dict)?.localityVerified, false)
    }

    // The main thread reads hosts through their doppelgangers.
    func testDoppelgangerKeepsVerification() {
        let host = VT100RemoteHost(username: "me", hostname: "box.example",
                                   locality: .remote, localityVerified: true)
        XCTAssertEqual((host.doppelganger() as! any VT100RemoteHostReading).localityVerified, true)
    }

    // +localhost is this machine by construction.
    func testLocalhostIsVerified() {
        XCTAssertTrue(VT100RemoteHost.localhost().localityVerified)
    }

    // Unhooking a conductor restores the pre-ssh host, verification included.
    func testRestoreFromSavedStatePreservesVerification() {
        let screen = makeScreen()
        let savedHost = VT100RemoteHost(username: "me", hostname: "MacBook-Pro-was.local",
                                        locality: .localhost, localityVerified: true)
        let terminalState: [AnyHashable: Any] = ["RemoteHost": savedHost.dictionaryValue()]
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.restore(fromSavedState: terminalState)
        })
        XCTAssertEqual(screen.lastRemoteHost()?.localityVerified, true)
    }
}
