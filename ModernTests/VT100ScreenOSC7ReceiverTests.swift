//
//  VT100ScreenOSC7ReceiverTests.swift
//  iTerm2
//
//  Receiver-side behavior of -setWorkingDirectoryFromURLString: (the OSC 7
//  handler). iTermMachineIdentityTests covers the token parser in isolation;
//  these drive a real VT100Screen so the locality verdict, the acceptOSC7 gate,
//  and the pathless-report poll guard are exercised end to end. Uses FakeSession
//  from VT100ScreenTests.swift.
//

import XCTest
@testable import iTerm2SharedARC

final class VT100ScreenOSC7ReceiverTests: XCTestCase {
    // This machine's version-1 token ("1:<hmac>"), computed the same way the code
    // under test does, so a matching token yields a deterministic localhost verdict
    // without duplicating the key/HMAC here.
    private var localMachineIDToken: String {
        return iTermMachineIdentity.localVersion1TokenForTesting()!
    }

    private func makeScreen() -> (VT100Screen, FakeSession) {
        let session = FakeSession()
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            screen.destructivelySetScreenWidth(80, height: 25, mutableState: mutableState)
        })
        return (screen, session)
    }

    // Sends one OSC 7 URL and returns the resulting last remote host, read on the
    // mutation thread right after the (synchronous) interval-tree update.
    private func sendOSC7(_ url: String, to screen: VT100Screen) -> (any VT100RemoteHostReading)? {
        var host: (any VT100RemoteHostReading)?
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setWorkingDirectoryFromURLString(url)
            host = mutableState.lastRemoteHost
        })
        // currentDirectoryReallyDidChangeTo: runs the path/prompt completion via an
        // async hop on the mutation queue when the directory actually changes, so a
        // second joined block (FIFO on the serial queue) drains it and its side
        // effects before assertions.
        drain(screen)
        return host
    }

    private func drain(_ screen: VT100Screen) {
        screen.performBlock(joinedThreads: { _, _, _ in })
    }

    override func setUp() {
        super.setUp()
        Host.it_resetRememberedLocalHostnamesForTesting()
        VT100ScreenMutableState.resetOSC7DisabledWarningForTesting()
    }

    override func tearDown() {
        Host.it_resetRememberedLocalHostnamesForTesting()
        VT100ScreenMutableState.resetOSC7DisabledWarningForTesting()
        super.tearDown()
    }

    // MARK: - machineID locality verdict

    // (a) A matching machineID makes a host that is NOT one of our live names
    // localhost, and the name is remembered for name-only consumers afterward.
    func testMatchingMachineIDIsLocalhostAndRemembersName() {
        let name = "vpn-name-that-is-not-a-live-local-name.example"
        XCTAssertFalse(Host.it_hostnameIsThisMachine(name))

        let (screen, _) = makeScreen()
        let host = sendOSC7("file://gnachman@\(name)/Users/gnachman?machineID=\(localMachineIDToken)", to: screen)
        XCTAssertEqual(host?.localityState, .localhost)
        XCTAssertTrue(host?.isLocalhost ?? false)
        // Finding: it_rememberVerifiedLocalHostname bypasses the live-name check,
        // so a drifted VPN/Tailscale/mDNS name is now recognized by name-only
        // consumers even though it matches none of the live local names.
        XCTAssertTrue(Host.it_hostnameIsThisMachine(name))
    }

    // (b) A mismatched machineID forces Remote even when the reported hostname is
    // one of our live local names: the verdict beats the name compare.
    func testMismatchedMachineIDBeatsLocalHostname() throws {
        guard let localName = Host.it_localHostNames().first else {
            throw XCTSkip("No local host names available")
        }
        let (screen, _) = makeScreen()
        let host = sendOSC7("file://gnachman@\(localName)/Users/gnachman?machineID=1:00000000-0000-0000-0000-000000000000",
                            to: screen)
        XCTAssertEqual(host?.localityState, .remote)
    }

    // (c) An empty machineID value (a non-Darwin peer's positive "not this
    // machine" assertion) forces Remote even for a local-looking name.
    func testEmptyMachineIDValueIsRemote() throws {
        guard let localName = Host.it_localHostNames().first else {
            throw XCTSkip("No local host names available")
        }
        let (screen, _) = makeScreen()
        let host = sendOSC7("file://gnachman@\(localName)/Users/gnachman?machineID=1:", to: screen)
        XCTAssertEqual(host?.localityState, .remote)
    }

    // (d) With no machineID at all, locality falls back to the hostname compare,
    // so one of our live names is still localhost.
    func testNoMachineIDFallsBackToHostname() throws {
        guard let localName = Host.it_localHostNames().first else {
            throw XCTSkip("No local host names available")
        }
        let (screen, _) = makeScreen()
        let host = sendOSC7("file://gnachman@\(localName)/Users/gnachman", to: screen)
        XCTAssertEqual(host?.localityState, .localhost)
    }

    // MARK: - username carry-forward is scoped to the same host

    // A third-party OSC 7 that omits the user (VTE-style file://host/path) for a
    // DIFFERENT host must not inherit the previous host's username.
    func testUserIsNotCarriedAcrossHostChange() {
        let (screen, _) = makeScreen()
        screen.performBlock(joinedThreads: { _, ms, _ in
            ms.setRemoteHostFrom("gnachman@mymac.local")
            ms.appendCarriageReturnLineFeed()
        })
        let host = sendOSC7("file://remotebox.example/home/bob", to: screen)
        XCTAssertEqual(host?.hostname, "remotebox.example")
        XCTAssertTrue((host?.username ?? "").isEmpty)
    }

    // ...but the same host with the user dropped (fish's built-in cwd report) still
    // heals from the previous report. This is the case the carry-forward exists for.
    func testUserIsCarriedForwardOnSameHost() {
        let (screen, _) = makeScreen()
        screen.performBlock(joinedThreads: { _, ms, _ in
            ms.setRemoteHostFrom("gnachman@myhost.example")
            ms.appendCarriageReturnLineFeed()
        })
        let host = sendOSC7("file://myhost.example/tmp/zz", to: screen)
        XCTAssertEqual(host?.username, "gnachman")
    }

    // MARK: - pathless report must not poll

    // A pathless OSC 7 (file://user@host) records the host but must NOT fall into
    // currentDirectoryDidChangeTo:'s empty-dir branch, which polls the local child
    // process for its cwd (wrong for a remote host over plain ssh).
    func testPathlessOSC7DoesNotPollWorkingDirectory() {
        let (screen, session) = makeScreen()
        session.getWorkingDirectoryCallCount = 0
        let host = sendOSC7("file://gnachman@host.example", to: screen)
        XCTAssertEqual(host?.hostname, "host.example")
        XCTAssertEqual(session.getWorkingDirectoryCallCount, 0)
    }

    // A report WITH a path uses the reported value directly and likewise never
    // polls, confirming the guard didn't change the normal path.
    func testOSC7WithPathDoesNotPollWorkingDirectory() {
        let (screen, session) = makeScreen()
        session.getWorkingDirectoryCallCount = 0
        _ = sendOSC7("file://gnachman@host.example/Users/gnachman", to: screen)
        XCTAssertEqual(session.getWorkingDirectoryCallCount, 0)
    }

    // A percent-encoded path (RFC 3986, byte-wise over UTF-8) decodes to the right
    // directory, including a space and a multi-byte character. Host-less so the
    // directory records synchronously (a host would defer it behind setHost's
    // paused side effect, which this harness doesn't fire).
    func testPercentEncodedPathDecodes() {
        let (screen, _) = makeScreen()
        _ = sendOSC7("file:///tmp/sp%20ace/%C3%BCn%C3%AF", to: screen)
        XCTAssertEqual(screen.workingDirectory(onLine: screen.numberOfLines()),
                       "/tmp/sp ace/ünï")
    }

    // A directory whose name is not valid UTF-8 (Linux filenames are arbitrary
    // bytes) must still track: NSURLComponents.path returns "" for the undecodable
    // escape, but the 8-bit fallback records the directory rather than silently
    // keeping the previous one.
    func testUndecodablePercentEscapeStillRecordsDirectory() {
        let (screen, _) = makeScreen()
        _ = sendOSC7("file:///tmp/ok", to: screen)
        _ = sendOSC7("file:///tmp/%FFbad", to: screen)
        XCTAssertNotEqual(screen.workingDirectory(onLine: screen.numberOfLines()), "/tmp/ok")
    }

    // An empty machineID query value (?machineID=, no version) is not a verdict:
    // it yields .unknown and falls back to the hostname compare, so a live local
    // name is still localhost rather than being forced remote.
    func testEmptyMachineIDQueryFallsBackToHostname() throws {
        guard let localName = Host.it_localHostNames().first else {
            throw XCTSkip("No local host names available")
        }
        let (screen, _) = makeScreen()
        let host = sendOSC7("file://gnachman@\(localName)/Users/gnachman?machineID=", to: screen)
        XCTAssertEqual(host?.localityState, .localhost)
    }

    // An empty-authority OSC 7 (file:///path, or USER/hostname both unset) that
    // carries a machineID verdict must classify locality by the verdict while
    // carrying the previously reported hostname forward, NOT overwrite it with the
    // empty string. NSURLComponents.host is @"" (not nil) for an empty authority,
    // so this used to clobber the hostname.
    func testEmptyAuthorityWithMachineIDPreservesHostname() {
        let (screen, _) = makeScreen()
        screen.performBlock(joinedThreads: { _, ms, _ in
            ms.setRemoteHostFrom("gnachman@myhost.example")
            // Advance the cursor so the OSC 7's host mark lands on a later line and
            // -lastRemoteHost returns it rather than the mark just established here.
            ms.appendCarriageReturnLineFeed()
        })
        let host = sendOSC7("file:///tmp/zz?machineID=\(localMachineIDToken)", to: screen)
        XCTAssertEqual(host?.hostname, "myhost.example")
        XCTAssertEqual(host?.localityState, .localhost)
        // The carried-forward name must NOT be added to the remembered-local set:
        // the token vouches for this report's machine, not that name.
        XCTAssertFalse(Host.it_hostnameIsThisMachine("myhost.example"))
    }

    // An empty-authority OSC 7 with a matching machineID proves THIS report came
    // from this machine; it says nothing about the hostname carried forward from a
    // previous report. That name must not be added to the process-wide
    // remembered-local-names set, or a genuinely remote host stays misclassified as
    // local for the rest of the app run.
    func testCarriedForwardHostnameIsNotRememberedAsLocal() {
        let (screen, _) = makeScreen()
        let remote = "remotebox-not-this-machine.example"
        XCTAssertFalse(Host.it_hostnameIsThisMachine(remote))
        screen.performBlock(joinedThreads: { _, ms, _ in
            ms.setRemoteHostFrom("bob@\(remote)")
            ms.appendCarriageReturnLineFeed()
        })
        let host = sendOSC7("file:///tmp/zz?machineID=\(localMachineIDToken)", to: screen)
        XCTAssertEqual(host?.hostname, remote)          // still carried forward
        XCTAssertEqual(host?.localityState, .localhost) // verdict still applies
        XCTAssertFalse(Host.it_hostnameIsThisMachine(remote))  // but the NAME was not vouched for
    }

    // MARK: - prompt establishment gated on machineID (not shellIntegrationInstalled)

    // Establishing the prompt runs in currentDirectoryReallyDidChangeTo:'s
    // completion, which is async (a paused side effect this harness doesn't fire)
    // the first time a directory is reported, but SYNCHRONOUS when the directory is
    // unchanged. So the first send records the directory and the second send (same
    // URL) runs the establish-or-skip decision inline, where screenPromptDidStart
    // is observable. URLs are host-less on purpose: a host would defer the whole
    // completion behind setHost's paused side effect.
    private func promptEstablishCountForRepeated(_ url: String) -> Int {
        let (screen, session) = makeScreen()
        _ = sendOSC7(url, to: screen)   // records the directory
        session.promptDidStartCallCount = 0
        _ = sendOSC7(url, to: screen)   // same directory -> synchronous completion
        return session.promptDidStartCallCount
    }

    // A shell-integration OSC 7 (a machineID token present) must NOT establish the
    // prompt, because OSC 133;A will. Crucially this holds even though no 133;A has
    // been seen yet (shellIntegrationInstalled is still NO): the previous
    // shellIntegrationInstalled gate missed exactly this first-OSC-7-of-session
    // case. Uses a future-version token (2:...) so the machineID is present but
    // yields no locality verdict, keeping the report on the synchronous, host-less
    // path instead of routing through setHost.
    func testShellIntegrationOSC7DoesNotEstablishPrompt() {
        let count = promptEstablishCountForRepeated("file:///Users/gnachman?machineID=2:future")
        XCTAssertEqual(count, 0)
    }

    // A third-party OSC 7 (no machineID, e.g. a VTE-style chpwd hook) is the only
    // prompt signal, so it still establishes the prompt.
    func testThirdPartyOSC7EstablishesPrompt() {
        let count = promptEstablishCountForRepeated("file:///Users/gnachman")
        XCTAssertEqual(count, 1)
    }

    // A first-party OSC 7 whose identity couldn't be computed (scripts emit "0:"
    // when sysctl fails) must still be recognized as shell integration, so 133;A
    // keeps sole ownership of the prompt. The token is present (so not third-party)
    // but yields no locality verdict.
    func testShellIntegrationOSC7WithoutIdentityDoesNotEstablishPrompt() {
        let count = promptEstablishCountForRepeated("file:///Users/gnachman?machineID=0:")
        XCTAssertEqual(count, 0)
    }

    // MARK: - malformed input

    // A URL NSURL rejects (an unencoded space in the authority) is ignored: no
    // crash, the working directory is untouched, and no local-cwd poll fires.
    func testUnparseableURLLeavesStateUnchanged() {
        let (screen, session) = makeScreen()
        _ = sendOSC7("file:///Users/gnachman", to: screen)   // host-less: records synchronously
        let before = screen.workingDirectory(onLine: screen.numberOfLines())
        XCTAssertEqual(before, "/Users/gnachman")
        session.getWorkingDirectoryCallCount = 0
        _ = sendOSC7("file://Mac Book.local/Users/other", to: screen)
        XCTAssertEqual(screen.workingDirectory(onLine: screen.numberOfLines()), before)
        XCTAssertEqual(session.getWorkingDirectoryCallCount, 0)
    }

    // A previously recorded host must survive an unparseable follow-up report (a
    // space in the authority makes NSURL nil): the drop leaves the old host, it is
    // not blanked.
    func testUnparseableURLPreservesPreviousHost() {
        let (screen, _) = makeScreen()
        _ = sendOSC7("file://gnachman@good.example/tmp/a", to: screen)
        let host = sendOSC7("file://gnachman@bad host/tmp/b", to: screen)
        XCTAssertEqual(host?.hostname, "good.example")
    }

    // MARK: - acceptOSC7 gate

    // Snapshot and restore AcceptOSC7 via a teardown block (runs even if the test
    // body fails) so a flipped assertion can't leave the developer's real defaults
    // suite with OSC 7 disabled.
    private func withAcceptOSC7(_ value: Bool) {
        let original = iTermAdvancedSettingsModel.acceptOSC7()
        addTeardownBlock { iTermAdvancedSettingsModel.setAcceptOSC7(original) }
        iTermAdvancedSettingsModel.setAcceptOSC7(value)
    }

    // With acceptOSC7 off, a first-party (machineID-bearing) OSC 7 updates nothing
    // and instead surfaces the "shell integration is broken" warning once.
    func testAcceptOSC7DisabledSuppressesReportAndWarns() {
        withAcceptOSC7(false)
        let (screen, session) = makeScreen()
        let host = sendOSC7("file://gnachman@host.example/Users/gnachman?machineID=\(localMachineIDToken)",
                            to: screen)
        XCTAssertNil(host)
        // The warning side effect flushes at the end of performBlock.
        XCTAssertTrue(session.didWarnOSC7Disabled)
    }

    // With acceptOSC7 on (the default), the same report is honored.
    func testAcceptOSC7EnabledHonorsReport() {
        withAcceptOSC7(true)
        let (screen, session) = makeScreen()
        let host = sendOSC7("file://gnachman@host.example/Users/gnachman?machineID=\(localMachineIDToken)",
                            to: screen)
        XCTAssertEqual(host?.hostname, "host.example")
        XCTAssertFalse(session.didWarnOSC7Disabled)
    }

    // The warning is process-wide: restoring many sessions that each report OSC 7
    // while acceptOSC7 is off must present at most one alert, not one per session.
    func testOSC7DisabledWarningIsShownOnlyOncePerApp() {
        withAcceptOSC7(false)
        let (screenA, sessionA) = makeScreen()
        let (screenB, sessionB) = makeScreen()
        let url = "file://gnachman@host.example/Users/gnachman?machineID=\(localMachineIDToken)"
        _ = sendOSC7(url, to: screenA)
        _ = sendOSC7(url, to: screenB)
        XCTAssertTrue(sessionA.didWarnOSC7Disabled)
        XCTAssertFalse(sessionB.didWarnOSC7Disabled)   // second session must not re-warn
    }
}
