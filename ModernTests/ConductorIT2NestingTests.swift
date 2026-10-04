//
//  ConductorIT2NestingTests.swift
//  iTerm2 ModernTests
//
//  ssh integration nested inside ssh integration: a session's conductor chain has an outer
//  conductor (Mac to host A) and an inner one (A to B). Every remote it2 piece is defined against
//  the INNERMOST conductor, because that is the host the shell, the it2 socket and the grant file
//  are on. These pin that the inner conductor, not its parent, is the one used: for routing a
//  frame to its demux, for the nonce that authenticates it, for the origin a command runs with,
//  for the grant it is checked against, and for the it2 it tells the shell to run.
//

import XCTest
@testable import iTerm2SharedARC

private final class NestingDelegate: NSObject, ConductorDelegate {
    private(set) var prompts = [String]()
    func conductorRequestIT2Authorization(guid: String, displayName: String,
                                          completion: @escaping (Bool, Bool, Bool) -> Void) {
        prompts.append(guid)
    }
    func conductorDismissIT2AuthorizationPrompt(guid: String) {}
    func conductorWrite(string: String) {}
    func conductorAbort(reason: String) {}
    func conductorQuit() {}
    func conductorStateDidChange() {}
    func conductorStopQueueingInput() {}
    func conductorSendInitialText() {}
    let guid = "the-session"
}

private final class NestingGrantBacking: IT2HostGrantBacking {
    var data: Data?
    func loadGrantData() -> Data? { data }
    func saveGrantData(_ data: Data?) { self.data = data }
}

@MainActor
final class ConductorIT2NestingTests: XCTestCase {
    private var delegate: NestingDelegate!
    private var outer: Conductor!
    private var inner: Conductor!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            delegate = NestingDelegate()
            outer = Conductor("outer-host", boolArgs: "", dcsID: "dcs-outer", clientUniqueID: "outer-cid",
                              varsToSend: [:], clientVars: [:], initialDirectory: nil,
                              shouldInjectShellIntegration: false, parent: nil)
            // Framing, so the inner conductor's frames carry a depth of their own.
            outer.framedPID = 100
            inner = Conductor("inner-host", boolArgs: "", dcsID: "dcs-inner", clientUniqueID: "inner-cid",
                              varsToSend: [:], clientVars: [:], initialDirectory: nil,
                              shouldInjectShellIntegration: false, parent: outer)
            // As PTYSession does: both report to the one session showing the shell.
            outer.delegate = delegate
            inner.delegate = delegate
            outer.it2Nonce = "outer-nonce"
            inner.it2Nonce = "inner-nonce"
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            Conductor.it2APIEnabledForTesting = nil
            Conductor.it2RunForTesting = nil
            Conductor.hostGrantStoreForTesting = nil
            Conductor.hostGrantVerifierForTesting = nil
            outer = nil
            inner = nil
            delegate = nil
        }
        super.tearDown()
    }

    private func hello(connid: String, nonce: String, argv: [String] = ["session", "list"]) -> String {
        let json: [String: Any] = ["nonce": nonce, "argv": argv, "cwd": "/",
                                   "term": "xterm", "isatty": false, "cols": 80, "rows": 24]
        let payload = try! JSONSerialization.data(withJSONObject: json)
        var frame = Data([UInt8(ascii: "H")])
        withUnsafeBytes(of: UInt32(payload.count).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(payload)
        return "\(connid) data \(frame.base64EncodedString())"
    }

    private func pumpMain() {
        let done = expectation(description: "main")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    // MARK: - Routing

    func testInnerConductorIsOneLevelDeeper() {
        XCTAssertEqual(inner.depth, outer.depth + 1)
    }

    // A frame from the inner host's framer is handled by the inner conductor's demux.
    func testInnerFrameIsHandledByTheInnerConductor() {
        inner.handleIT2("c1 open", depth: inner.depth)
        XCTAssertTrue(inner.it2DemuxForHandling().hasOpenConnection("c1"))
        XCTAssertFalse(outer.it2DemuxForHandling().hasOpenConnection("c1"))
    }

    // Frames from the outer host's framer arrive at the session's (inner) conductor too, and
    // must be passed up rather than handled with the wrong nonce and origin.
    func testOuterFrameIsPassedToTheParent() {
        inner.handleIT2("c2 open", depth: outer.depth)
        XCTAssertTrue(outer.it2DemuxForHandling().hasOpenConnection("c2"))
        XCTAssertFalse(inner.it2DemuxForHandling().hasOpenConnection("c2"))
    }

    // MARK: - What a command runs with

    // The inner host's it2 authenticates with the nonce the inner connection minted, and runs
    // with the inner connection as its origin, which is what pane addressing matches against.
    func testInnerCommandRunsWithTheInnerOrigin() {
        Conductor.it2APIEnabledForTesting = true
        var origins = [(String, String?)]()
        Conductor.it2RunForTesting = { _, originIdentifier, originSessionID in
            origins.append((originIdentifier, originSessionID))
            return 0
        }
        inner.it2Authorized = true
        inner.handleIT2("c1 open", depth: inner.depth)
        inner.handleIT2(hello(connid: "c1", nonce: "inner-nonce"), depth: inner.depth)
        pumpMain()
        XCTAssertEqual(origins.map(\.0), ["inner-cid"])
        XCTAssertEqual(origins.first?.1, "the-session", "the default target is the session showing the shell")
    }

    // The outer connection's nonce is not valid on the inner one: a process on host A cannot
    // drive iTerm2 as host B.
    func testOuterNonceDoesNotAuthenticateTheInnerConnection() {
        Conductor.it2APIEnabledForTesting = true
        var ran = false
        Conductor.it2RunForTesting = { _, _, _ in
            ran = true
            return 0
        }
        inner.it2Authorized = true
        inner.handleIT2("c1 open", depth: inner.depth)
        inner.handleIT2(hello(connid: "c1", nonce: "outer-nonce"), depth: inner.depth)
        pumpMain()
        XCTAssertFalse(ran)
    }

    // Each hop decides for itself. Allowing host A does not let host B in.
    func testOuterAuthorizationDoesNotCarryToTheInnerConnection() {
        Conductor.it2APIEnabledForTesting = true
        var ran = false
        Conductor.it2RunForTesting = { _, _, _ in
            ran = true
            return 0
        }
        outer.it2Authorized = true
        inner.handleIT2("c1 open", depth: inner.depth)
        inner.handleIT2(hello(connid: "c1", nonce: "inner-nonce"), depth: inner.depth)
        pumpMain()
        XCTAssertFalse(ran, "still waiting on the inner connection's own prompt")
        XCTAssertEqual(delegate.prompts, [inner.guid])
    }

    // MARK: - The grant

    // The grant consulted is the inner host's: the file is read from the inner host, and the
    // record is the one minted for it.
    func testGrantIsCheckedForTheInnerHost() {
        let store = IT2HostGrantStore(backing: NestingGrantBacking())
        store.add(IT2HostGrant(host: inner.sshIdentity.stringIdentifier, id: "inner",
                               secretSHA256: "hash", granted: Date()))
        store.add(IT2HostGrant(host: outer.sshIdentity.stringIdentifier, id: "outer",
                               secretSHA256: "hash", granted: Date()))
        Conductor.hostGrantStoreForTesting = store
        var checked = [(String, String)]()
        let done = expectation(description: "verified")
        Conductor.hostGrantVerifierForTesting = { grant, home in
            checked.append((grant.id, home))
            done.fulfill()
            return true
        }
        outer.homeDirectory = "/home/outer"
        inner.homeDirectory = "/home/inner"
        var granted: Bool?
        inner.authorizeIT2 { granted = $0 }
        wait(for: [done], timeout: 2)
        pumpMain()
        XCTAssertEqual(checked.map(\.0), ["inner"])
        XCTAssertEqual(checked.map(\.1), ["/home/inner"])
        XCTAssertEqual(granted, true)
        XCTAssertNil(outer.it2Authorized, "the outer connection is untouched")
    }

    // MARK: - The it2 on the inner host

    // The inner host's shell is told about the inner connection's socket and its own upload,
    // under its own home directory.
    func testInnerProxyNamesTheInnerHostsFiles() throws {
        var env = [String: String]()
        inner.activateIT2Proxy(home: "/home/inner", env: &env)
        XCTAssertTrue(try XCTUnwrap(env["IT2_PY"]).hasPrefix("/home/inner/"))
        XCTAssertEqual(env["IT2_NONCE"], inner.it2Nonce)
        XCTAssertNotEqual(env["IT2_NONCE"], outer.it2Nonce)
        XCTAssertEqual(inner.it2ClientRecord?["py"], env["IT2_PY"])
        XCTAssertNil(outer.it2ClientRecord?["py"], "the outer connection was not touched")
    }
}
