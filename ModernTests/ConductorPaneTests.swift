//
//  ConductorPaneTests.swift
//  iTerm2 ModernTests
//
//  A pane is a program a workgroup peer runs through its leader's framer (framer.py `pane`)
//  instead of over a new ssh connection. The conductor starts it, resizes it, feeds it input,
//  and hands its output and exit to the client that started it. Output and exits are routed
//  by depth, like every other framer report, so a pane started by an outer conductor is found
//  from the innermost one PTYSession talks to.
//

import XCTest
@testable import iTerm2SharedARC

private final class PaneConductorDelegate: NSObject, ConductorDelegate {
    private(set) var writes = [String]()
    private(set) var quits = 0
    func conductorRequestIT2Authorization(guid: String, displayName: String, callerTmuxPane: String?,
                                          completion: @escaping (Bool, Bool, Bool) -> Void) {}
    func conductorDismissIT2AuthorizationPrompt(guid: String) {}
    func conductorWrite(string: String) { writes.append(string) }
    func conductorAbort(reason: String) {}
    func conductorQuit() { quits += 1 }
    func conductorStateDidChange() {}
    func conductorStopQueueingInput() {}
    func conductorSendInitialText() {}
    let guid = "the-leader"

    // Every argument written so far, decoded. Each is one base64 line; a long one is split
    // across lines that end in a backslash.
    var decodedLines: [String] {
        var result = [String]()
        var pending = ""
        for line in writes.joined().components(separatedBy: "\n") {
            if line.hasSuffix("\\") {
                pending += line.dropLast()
                continue
            }
            let full = pending + line
            pending = ""
            if full.isEmpty {
                continue
            }
            result.append(String(data: Data(base64Encoded: full) ?? Data(), encoding: .utf8) ?? "?")
        }
        return result
    }

    func reset() { writes = [] }
}

private final class FakePaneClient: NSObject, ConductorPaneClient {
    private(set) var output = Data()
    private(set) var exitCodes = [Int32]()
    func conductorPaneDidOutput(_ data: Data) { output.append(data) }
    func conductorPaneDidExit(code: Int32) { exitCodes.append(code) }
}

@MainActor
final class ConductorPaneTests: XCTestCase {
    private var delegate: PaneConductorDelegate!
    private var conductor: Conductor!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            delegate = PaneConductorDelegate()
            conductor = Conductor("host", boolArgs: "", dcsID: "dcs", clientUniqueID: "cid",
                                  varsToSend: [:], clientVars: [:], initialDirectory: nil,
                                  shouldInjectShellIntegration: false, parent: nil)
            conductor.framedPID = 100
            conductor.delegate = delegate
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            conductor = nil
            delegate = nil
        }
        super.tearDown()
    }

    // The framer's answer to the command in flight.
    private func reply(_ lines: [String], status: UInt8 = 0, conductor: Conductor? = nil) {
        let c = conductor ?? self.conductor!
        c.handleCommandBegin(identifier: "x", depth: c.depth)
        for line in lines {
            c.handle(line: line, depth: c.depth)
        }
        c.handleCommandEnd(identifier: "x", type: "f", status: status, depth: c.depth)
    }

    func testStartingAPaneSendsThePaneCommand() {
        let client = FakePaneClient()
        conductor.startPane(rows: 31, cols: 97, directory: "~/src", command: "exec claude\n--resume",
                            client: client) { _ in }
        XCTAssertEqual(delegate.decodedLines, ["pane", "31", "97", "~/src", "exec claude\n--resume"])
    }

    func testThePanesPidIsReportedAndItsOutputAndExitReachTheClient() {
        let client = FakePaneClient()
        var reported: Int32?
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "true", client: client) { pid in
            reported = pid
        }
        reply(["4242"])
        XCTAssertEqual(reported, 4242)

        conductor.handlePaneOutput(Data("hello".utf8), pid: 4242, depth: 0)
        conductor.handlePaneOutput(Data(" world".utf8), pid: 4242, depth: 0)
        XCTAssertEqual(client.output, Data("hello world".utf8))

        conductor.handleTerminate(4242, code: 3, depth: 0)
        XCTAssertEqual(client.exitCodes, [3])
        XCTAssertEqual(delegate.quits, 0, "a pane exiting is not the login shell exiting")

        conductor.handlePaneOutput(Data("late".utf8), pid: 4242, depth: 0)
        XCTAssertEqual(client.output, Data("hello world".utf8), "forgotten after it exits")
    }

    func testAFailedStartReportsNoPid() {
        let client = FakePaneClient()
        var called = false
        var reported: Int32? = 1
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "true", client: client) { pid in
            called = true
            reported = pid
        }
        reply(["Command failed: no such directory"], status: 1)
        XCTAssertTrue(called)
        XCTAssertNil(reported)
    }

    func testOutputForAnUnknownPidIsDropped() {
        let client = FakePaneClient()
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "true", client: client) { _ in }
        reply(["4242"])
        conductor.handlePaneOutput(Data("x".utf8), pid: 999, depth: 0)
        XCTAssertEqual(client.output, Data())
    }

    func testInputResizeAndKillGoToThePanesPid() {
        let client = FakePaneClient()
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "true", client: client) { _ in }
        reply(["4242"])

        delegate.reset()
        conductor.resizePane(4242, rows: 40, cols: 120)
        XCTAssertEqual(delegate.decodedLines, ["panesize", "4242", "40", "120"])
        reply([])

        delegate.reset()
        conductor.sendToPane(4242, data: Data("ls\r".utf8))
        XCTAssertEqual(delegate.decodedLines, ["send", "4242", Data("ls\r".utf8).base64EncodedString()])
        reply([])

        delegate.reset()
        conductor.killPane(4242)
        XCTAssertEqual(delegate.decodedLines, ["kill", "4242"])
    }

    func testAPaneOfAnOuterConductorIsFoundFromTheInnerOne() {
        // PTYSession talks to its innermost conductor; output from the outer framer's pane
        // arrives there with the outer depth and has to be passed up.
        let inner = Conductor("inner", boolArgs: "", dcsID: "dcs-inner", clientUniqueID: "cid-inner",
                              varsToSend: [:], clientVars: [:], initialDirectory: nil,
                              shouldInjectShellIntegration: false, parent: conductor)
        inner.framedPID = 200
        inner.delegate = delegate
        let client = FakePaneClient()
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "true", client: client) { _ in }
        reply(["4242"])

        inner.handlePaneOutput(Data("up".utf8), pid: 4242, depth: conductor.depth)
        XCTAssertEqual(client.output, Data("up".utf8))
        inner.handleTerminate(4242, code: 0, depth: conductor.depth)
        XCTAssertEqual(client.exitCodes, [0])
    }

    func testAPaneWhoseClientIsGoneIsKilled() {
        var client: FakePaneClient? = FakePaneClient()
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "true", client: client!) { _ in }
        reply(["4242"])
        client = nil

        delegate.reset()
        conductor.handlePaneOutput(Data("x".utf8), pid: 4242, depth: 0)
        XCTAssertEqual(delegate.decodedLines, ["kill", "4242"])
    }
}
