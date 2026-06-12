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

    // A hostname that isn't ours: stamped remote.
    func testReportingForeignHostnameStampsRemote() {
        XCTAssertEqual(localityAfterReporting("me@build-box.example.invalid"), .remote)
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
}
