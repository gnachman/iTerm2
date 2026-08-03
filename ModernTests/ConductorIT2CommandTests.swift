//
//  ConductorIT2CommandTests.swift
//  iTerm2
//
//  Pins the wire format of the it2 proxy framer commands. framer.py's mainloop
//  splits a command into newline-separated, individually base64-encoded args and
//  dispatches on the first (see handle_it2listen/handle_it2send/handle_it2close in
//  OtherResources/framer.py, covered by tests/framer_it2_test.py). The Swift side
//  must therefore emit exactly "it2listen\n<path>", "it2send\n<connid>\n<base64>",
//  and "it2close\n<connid>".
//

import XCTest
@testable import iTerm2SharedARC

final class ConductorIT2CommandTests: XCTestCase {

    func testIT2ListenStringValue() {
        let cmd = Conductor.Command.framerIT2Listen(path: "/tmp/it2.sock")
        XCTAssertEqual(cmd.stringValue, "it2listen\n/tmp/it2.sock")
        XCTAssertTrue(cmd.isFramer)
    }

    func testIT2SendStringValueBase64EncodesData() {
        // base64("hi") == "aGk=". framer b64-decodes arg[1] back to the raw bytes.
        let cmd = Conductor.Command.framerIT2Send(connid: "c5", data: Data("hi".utf8))
        XCTAssertEqual(cmd.stringValue, "it2send\nc5\naGk=")
        XCTAssertTrue(cmd.isFramer)
    }

    func testIT2SendRoundTripsArbitraryBytes() {
        let bytes = Data((0...255).map { UInt8($0) })
        let cmd = Conductor.Command.framerIT2Send(connid: "conn9", data: bytes)
        let parts = cmd.stringValue.components(separatedBy: "\n")
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[0], "it2send")
        XCTAssertEqual(parts[1], "conn9")
        XCTAssertEqual(Data(base64Encoded: parts[2]), bytes)
    }

    func testIT2CloseStringValue() {
        let cmd = Conductor.Command.framerIT2Close(connid: "c5")
        XCTAssertEqual(cmd.stringValue, "it2close\nc5")
        XCTAssertTrue(cmd.isFramer)
    }

    // The it2 auth nonce + socket path must survive conductor state restoration, or
    // it2-over-ssh would silently stop working after a restore. (The separate SSH
    // recovery path carries them in process from the pre-recovery conductor; see
    // adoptIT2RecoveryState and testIT2StateCarriesAcrossRecovery.)
    func testIT2NonceAndSocketPersistAcrossRestorableStateCoding() throws {
        let state = Conductor.RestorableState(
            sshargs: "localhost",
            varsToSend: [:],
            clientVars: [:],
            payloads: [],
            initialDirectory: nil,
            shouldInjectShellIntegration: true,
            parsedSSHArguments: ParsedSSHArguments("localhost", booleanArgs: "",
                                                   hostnameFinder: iTermHostnameFinder()),
            depth: 0,
            parentState: nil,
            framedPID: nil,
            state: .ground,
            queue: [],
            boolArgs: "",
            dcsID: "dcs",
            clientUniqueID: "cid",
            modifiedVars: nil,
            modifiedCommandArgs: nil,
            homeDirectory: "/home/u",
            shell: "/bin/zsh",
            uname: nil,
            _terminalConfiguration: nil,
            discoveredHostname: nil,
            it2Proxy: IT2ProxyState(nonce: "the-nonce",
                                    socketPath: "/home/u/.iterm2/it2/abc.sock",
                                    authorized: nil))
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(Conductor.RestorableState.self, from: data)
        XCTAssertEqual(decoded.it2Proxy.nonce, "the-nonce")
        XCTAssertEqual(decoded.it2Proxy.socketPath, "/home/u/.iterm2/it2/abc.sock")
    }

    private func makeRestorableState(it2Nonce: String?,
                                     it2Authorized: Bool?) -> Conductor.RestorableState {
        Conductor.RestorableState(
            sshargs: "localhost",
            varsToSend: [:],
            clientVars: [:],
            payloads: [],
            initialDirectory: nil,
            shouldInjectShellIntegration: true,
            parsedSSHArguments: ParsedSSHArguments("localhost", booleanArgs: "",
                                                   hostnameFinder: iTermHostnameFinder()),
            depth: 0,
            parentState: nil,
            framedPID: nil,
            state: .ground,
            queue: [],
            boolArgs: "",
            dcsID: "dcs",
            clientUniqueID: "cid",
            modifiedVars: nil,
            modifiedCommandArgs: nil,
            homeDirectory: "/home/u",
            shell: "/bin/zsh",
            uname: nil,
            _terminalConfiguration: nil,
            discoveredHostname: nil,
            it2Proxy: IT2ProxyState(nonce: it2Nonce, socketPath: nil, authorized: it2Authorized))
    }

    // The it2 API authorization decision must survive state restoration so the user is
    // not re-prompted after a relaunch. Absent (nil) means undecided -> prompt.
    func testIT2AuthorizationPersistsAcrossRestorableStateCoding() throws {
        func roundTrip(_ authorized: Bool?) throws -> Bool? {
            let data = try JSONEncoder().encode(makeRestorableState(it2Nonce: nil,
                                                                    it2Authorized: authorized))
            return try JSONDecoder().decode(Conductor.RestorableState.self, from: data).it2Proxy.authorized
        }
        XCTAssertEqual(try roundTrip(true), true)
        XCTAssertEqual(try roundTrip(false), false)
        XCTAssertNil(try roundTrip(nil))
    }

    // A conductor saved before the it2Proxy field existed has JSON with no such key.
    // decode()'s `try?` must swallow the .keyNotFound and default to an empty IT2ProxyState,
    // rather than throwing and aborting ALL conductor state restoration for that pre-existing
    // saved session. (Round-trip encoding always emits the key, so only a hand-stripped blob
    // exercises this path.)
    func testIT2ProxyDecodesWhenKeyAbsent() throws {
        let data = try JSONEncoder().encode(makeRestorableState(it2Nonce: "the-nonce",
                                                                it2Authorized: true))
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(dict["it2Proxy"], "sanity: key present before stripping")
        dict.removeValue(forKey: "it2Proxy")
        let stripped = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try JSONDecoder().decode(Conductor.RestorableState.self, from: stripped)
        XCTAssertNil(decoded.it2Proxy.authorized)         // key-absent tolerated -> default
        XCTAssertNil(decoded.it2Proxy.nonce)
        XCTAssertEqual(decoded.dcsID, "dcs")              // rest of the state intact
    }

    // Migration: a conductor saved by the committed HEAD schema persisted the proxy as two
    // separate top-level scalar keys (it2Nonce, it2SocketPath) with no it2Proxy object.
    // Restoring such a blob must fold those into it2Proxy so the session keeps its socket
    // path and auth nonce, instead of silently reverting to an all-nil proxy (which would
    // fail every subsequent HELLO's nonce check). `authorized` was not persisted by that
    // schema, so it stays nil (undecided -> the user is re-prompted, never silently granted).
    func testIT2ProxyMigratesLegacyScalarKeys() throws {
        let data = try JSONEncoder().encode(makeRestorableState(it2Nonce: nil, it2Authorized: nil))
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // Rewrite the blob into the old on-disk shape: drop it2Proxy, add the legacy scalars.
        dict.removeValue(forKey: "it2Proxy")
        dict["it2Nonce"] = "legacy-nonce"
        dict["it2SocketPath"] = "/home/u/.iterm2/it2/legacy.sock"
        let legacy = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try JSONDecoder().decode(Conductor.RestorableState.self, from: legacy)
        XCTAssertEqual(decoded.it2Proxy.nonce, "legacy-nonce")
        XCTAssertEqual(decoded.it2Proxy.socketPath, "/home/u/.iterm2/it2/legacy.sock")
        XCTAssertNil(decoded.it2Proxy.authorized)         // not persisted by the old schema
        XCTAssertEqual(decoded.dcsID, "dcs")              // rest of the state intact
    }

    @MainActor
    private func makeConductor() -> Conductor {
        Conductor("localhost", boolArgs: "", dcsID: "dcs", clientUniqueID: "cid",
                  varsToSend: [:], clientVars: [:], initialDirectory: nil,
                  shouldInjectShellIntegration: false, parent: nil)
    }

    // The it2 proxy state must actually survive an SSH recovery. adopt copies it from the
    // retiring conductor onto the recovery shim (handleRecovery reads it off the shim),
    // and init(recovery:) then carries it into the post-recovery conductor that validates
    // HELLOs. Regression guard: the shim's own fields default to nil, so before the adopt
    // fix every post-recovery HELLO failed authorization and any grant was lost.
    @MainActor
    func testIT2StateCarriesAcrossRecovery() throws {
        let source = makeConductor()   // stands in for the pre-recovery conductor
        source.it2Nonce = "the-nonce"
        source.it2SocketPath = "/home/u/.iterm2/it2/x.sock"
        source.it2Authorized = true
        source.it2ListenSucceeded = true   // recovered framer keeps its socket bound

        let shim = makeConductor()     // fresh shim: starts with no it2 state (the bug)
        XCTAssertNil(shim.it2Nonce)
        XCTAssertFalse(shim.it2ListenSucceeded)
        shim.adoptIT2RecoveryState(from: source)
        XCTAssertEqual(shim.it2Nonce, "the-nonce")
        XCTAssertEqual(shim.it2SocketPath, "/home/u/.iterm2/it2/x.sock")
        XCTAssertEqual(shim.it2Authorized, true)
        XCTAssertTrue(shim.it2ListenSucceeded)

        // handleRecovery reads the shim's fields into ConductorRecovery; init(recovery:)
        // copies them into the post-recovery conductor.
        let recovery = ConductorRecovery(pid: 123, dcsID: "dcs", tree: [:], sshargs: "localhost",
                                         boolArgs: "", clientUniqueID: "cid", version: 2, parent: nil,
                                         it2Proxy: shim.it2Proxy)
        let recovered = Conductor(recovery: recovery)
        XCTAssertEqual(recovered.it2Nonce, "the-nonce")
        XCTAssertEqual(recovered.it2SocketPath, "/home/u/.iterm2/it2/x.sock")
        XCTAssertEqual(recovered.it2Authorized, true)
        // The menu-gating flag must survive recovery too, or the "Remote host can control
        // iTerm2" item goes permanently disabled after a transient drop even though it2 works.
        XCTAssertTrue(recovered.it2ListenSucceeded)
    }

    // listenSucceeded is deliberately NOT persisted: on state restoration the framer relaunches
    // and it2Listen re-establishes it, so a stale "true" must not be restored. Verify the
    // Codable round-trip drops it while keeping the persisted proxy fields.
    func testIT2ListenSucceededNotPersisted() throws {
        var proxy = IT2ProxyState(nonce: "n", socketPath: "/s", authorized: true)
        proxy.listenSucceeded = true
        let data = try JSONEncoder().encode(proxy)
        let decoded = try JSONDecoder().decode(IT2ProxyState.self, from: data)
        XCTAssertEqual(decoded.nonce, "n")
        XCTAssertEqual(decoded.authorized, true)
        XCTAssertFalse(decoded.listenSucceeded, "listenSucceeded must not round-trip through Codable")
    }

    private final class SpyCancellable: IT2Cancellable {
        var cancelCount = 0
        func cancel() { cancelCount += 1 }
    }

    private static func upFrame(_ type: UInt8, _ payload: Data) -> Data {
        var d = Data([type])
        let n = UInt32(payload.count)
        d.append(contentsOf: [UInt8((n >> 24) & 0xff), UInt8((n >> 16) & 0xff),
                              UInt8((n >> 8) & 0xff), UInt8(n & 0xff)])
        d.append(payload)
        return d
    }

    private static func helloFrame(nonce: String, argv: [String]) -> String {
        let json: [String: Any] = ["nonce": nonce, "argv": argv, "cwd": "/home/u",
                                   "term": "xterm", "isatty": true, "cols": 80, "rows": 24]
        let payload = try! JSONSerialization.data(withJSONObject: json)
        let frame = upFrame(UInt8(ascii: "H"), payload)
        return "c1 data \(frame.base64EncodedString())"
    }

    // A streaming command left running on a conductor that is demoted to `parent` during a
    // NESTED framer recovery would otherwise never be torn down (that conductor never unhooks
    // or deinits), leaking its it2core thread + in-process API connection. adopt must cancel
    // the retiring conductor's in-flight it2 commands as part of the hand-off.
    @MainActor
    func testAdoptCancelsRetiringConductorInFlightIT2Commands() {
        let spy = SpyCancellable()
        let source = makeConductor()
        source.it2Nonce = "n"
        let demux = ConductorIT2Demux(nonce: { "n" },
                                      send: { _, _ in },
                                      close: { _ in },
                                      run: { _, _, _, _, _ in spy })
        source.it2Demux = demux
        // Drive a validated HELLO so a command is "running" and its cancellable is retained.
        demux.handle("c1 open")
        demux.handle(Self.helloFrame(nonce: "n", argv: ["monitor", "output"]))
        XCTAssertEqual(spy.cancelCount, 0, "command is running, not yet cancelled")

        // Nested recovery adopts state onto a fresh shim without unhooking `source`.
        let shim = makeConductor()
        shim.adoptIT2RecoveryState(from: source)
        XCTAssertEqual(spy.cancelCount, 1,
                       "adopt must cancel the retiring conductor's in-flight it2 commands")
    }

    // Two conductors sharing one delegate and the same ssh identity must not cross-cancel
    // each other's in-flight auth prompt: the announcement is keyed per conductor (guid),
    // not by the shared display name. Keyed by display name, presenting the second prompt
    // would dismiss the first and resolve its command as denied without the user answering.
    @MainActor
    func testConcurrentSameIdentityConductorsDoNotCrossCancelPrompts() throws {
        let delegate = FakeIT2AuthDelegate()
        let c1 = makeConductor()   // both use sshargs "localhost" -> identical sshIdentity
        let c2 = makeConductor()
        c1.delegate = delegate
        c2.delegate = delegate

        var granted1: Bool?
        var granted2: Bool?
        c1.authorizeIT2 { granted1 = $0 }
        c2.authorizeIT2 { granted2 = $0 }

        XCTAssertNil(granted1, "c1's undecided prompt must survive c2 presenting its own")
        XCTAssertNil(granted2)

        delegate.answer(guid: c1.guid, granted: true)  // user allows c1
        XCTAssertEqual(granted1, true)
        XCTAssertNil(granted2, "answering c1 must not resolve c2")
    }

    // Exercises PTYSession's REAL announcement keying (not the test fake): the identifier
    // is derived from the conductor's guid, so two conductors sharing an ssh display name
    // but with distinct guids get distinct announcements and cannot cross-cancel.
    func testIT2AuthorizationAnnouncementIdentifierIsPerGUID() {
        let a = PTYSession.it2AuthorizationAnnouncementIdentifier(forGUID: "guid-A")
        let b = PTYSession.it2AuthorizationAnnouncementIdentifier(forGUID: "guid-B")
        XCTAssertNotEqual(a, b, "distinct guids must yield distinct identifiers")
        XCTAssertTrue(a.contains("guid-A"), "identifier is derived from the guid")
        XCTAssertEqual(a, PTYSession.it2AuthorizationAnnouncementIdentifier(forGUID: "guid-A"))
    }
}

// Mimics PTYSession's it2 auth announcement handling: an identifier -> completion map
// where presenting a same-identifier prompt dismisses (denies) the existing one, exactly
// as queueAnnouncement -> dismissAnnouncementWithIdentifier does. The identifier is
// derived from the guid the conductor passes, so distinct guids do not collide.
private final class FakeIT2AuthDelegate: NSObject, ConductorDelegate {
    private var announcements: [String: (Bool, Bool) -> Void] = [:]
    private func identifier(_ guid: String) -> String { "IT2Authorization-\(guid)" }

    func conductorRequestIT2Authorization(guid: String, displayName: String,
                                          completion: @escaping (Bool, Bool) -> Void) {
        // queueAnnouncement dismisses any existing same-identifier prompt, firing its
        // completion as a -2 dismiss => (granted:false, remember:false).
        announcements.removeValue(forKey: identifier(guid))?(false, false)
        announcements[identifier(guid)] = completion
    }
    func conductorDismissIT2AuthorizationPrompt(guid: String) {
        announcements.removeValue(forKey: identifier(guid))?(false, false)
    }
    // Simulate the user explicitly answering (Allow/Deny) the prompt for `guid`.
    func answer(guid: String, granted: Bool) {
        announcements.removeValue(forKey: identifier(guid))?(granted, true)
    }

    func conductorWrite(string: String) {}
    func conductorAbort(reason: String) {}
    func conductorQuit() {}
    func conductorStateDidChange() {}
    func conductorStopQueueingInput() {}
    func conductorSendInitialText() {}
    let guid = "fake-delegate"
}
