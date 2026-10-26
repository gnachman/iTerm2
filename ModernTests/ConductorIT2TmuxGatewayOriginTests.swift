//
//  ConductorIT2TmuxGatewayOriginTests.swift
//  iTerm2 ModernTests
//
//  A remote it2 with no explicit target acts on the session its call arrived on. When that
//  session is a tmux integration gateway and the caller is in a tmux pane, the gateway is never
//  the right answer: the pane is shown in a session of its own, or, when this connection can't
//  place it at all, the call reached iTerm2 over another connection's socket (a tmux server
//  hands every pane the IT2_SOCK of whichever connection started it). Acting on the gateway then
//  renamed another connection's gateway session and reported success. So the conductor withholds
//  the gateway as the origin, and it2core reports the pane as unplaced instead of guessing.
//

import XCTest
@testable import iTerm2SharedARC

private final class GatewayDelegate: NSObject, ConductorDelegate {
    var isGateway = false
    func conductorRequestIT2Authorization(guid: String, displayName: String, callerTmuxPane: String?,
                                          completion: @escaping (Bool, Bool, Bool) -> Void) {}
    func conductorDismissIT2AuthorizationPrompt(guid: String) {}
    func conductorWrite(string: String) {}
    func conductorAbort(reason: String) {}
    func conductorQuit() {}
    func conductorStateDidChange() {}
    func conductorStopQueueingInput() {}
    func conductorSendInitialText() {}
    var conductorIsTmuxGateway: Bool { isGateway }
    let guid = "gateway-session"
}

private final class PlainDelegate: NSObject, ConductorDelegate {
    func conductorRequestIT2Authorization(guid: String, displayName: String, callerTmuxPane: String?,
                                          completion: @escaping (Bool, Bool, Bool) -> Void) {}
    func conductorDismissIT2AuthorizationPrompt(guid: String) {}
    func conductorWrite(string: String) {}
    func conductorAbort(reason: String) {}
    func conductorQuit() {}
    func conductorStateDidChange() {}
    func conductorStopQueueingInput() {}
    func conductorSendInitialText() {}
    let guid = "plain-session"
}

@MainActor
final class ConductorIT2TmuxGatewayOriginTests: XCTestCase {
    private var delegate: GatewayDelegate!
    private var conductor: Conductor!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            delegate = GatewayDelegate()
            conductor = Conductor("host", boolArgs: "", dcsID: "dcs", clientUniqueID: "cid",
                                  varsToSend: [:], clientVars: [:], initialDirectory: nil,
                                  shouldInjectShellIntegration: false, parent: nil)
            conductor.delegate = delegate
            conductor.it2Nonce = "nonce"
            conductor.it2Authorized = true
            Conductor.it2APIEnabledForTesting = true
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            Conductor.it2APIEnabledForTesting = nil
            Conductor.it2RunForTesting = nil
            conductor = nil
            delegate = nil
        }
        super.tearDown()
    }

    private func originSessionID(environment: [String: String]) -> String?? {
        var origins = [String?]()
        Conductor.it2RunForTesting = { _, _, originSessionID in
            origins.append(originSessionID)
            return 0
        }
        let json: [String: Any] = ["nonce": "nonce", "argv": ["session", "set-name", "x"], "cwd": "/",
                                   "term": "xterm", "isatty": false, "cols": 80, "rows": 24,
                                   "env": environment]
        let payload = try! JSONSerialization.data(withJSONObject: json)
        var frame = Data([UInt8(ascii: "H")])
        withUnsafeBytes(of: UInt32(payload.count).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(payload)
        conductor.handleIT2("c1 open", depth: conductor.depth)
        conductor.handleIT2("c1 data \(frame.base64EncodedString())", depth: conductor.depth)
        let done = expectation(description: "main")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(origins.count, 1)
        return origins.first
    }

    private let tmuxPane = ["TMUX": "/tmp/tmux-501/qa34,123,1", "TMUX_PANE": "%7"]

    func testGatewayIsNotTheOriginOfACallFromATmuxPane() {
        delegate.isGateway = true
        XCTAssertEqual(originSessionID(environment: tmuxPane), .some(nil))
    }

    func testGatewayIsStillTheOriginOutsideTmux() {
        delegate.isGateway = true
        XCTAssertEqual(originSessionID(environment: [:]), "gateway-session")
    }

    func testEmptyTMUXIsNotATmuxPane() {
        delegate.isGateway = true
        XCTAssertEqual(originSessionID(environment: ["TMUX": ""]), "gateway-session")
    }

    // A delegate that doesn't say whether it is a gateway is taken not to be one.
    func testDelegateWithoutTheAnswerIsNotAGateway() {
        let plain = PlainDelegate()
        conductor.delegate = plain
        XCTAssertEqual(originSessionID(environment: tmuxPane), "plain-session")
        withExtendedLifetime(plain) {}
    }

    // Plain tmux (not integration) in an ssh session: its panes are not iTerm2 sessions, and the
    // ssh session showing tmux is the right default.
    func testOrdinarySessionIsTheOriginOfACallFromATmuxPane() {
        XCTAssertEqual(originSessionID(environment: tmuxPane), "gateway-session")
    }
}
