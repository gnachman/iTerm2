//
//  FramerPaneJobManagerTests.swift
//  iTerm2 ModernTests
//
//  A framer pane session's task: the conductor's output for the pane goes into a pipe the
//  session reads like a pty, input and size changes go back to the conductor, and the pipe
//  closes after the last output when the pane exits or the connection ends.
//

import XCTest
@testable import iTerm2SharedARC

private final class Delegate: NSObject, ConductorDelegate {
    var writes = [String]()
    func conductorRequestIT2Authorization(guid: String, displayName: String, callerTmuxPane: String?,
                                          completion: @escaping (Bool, Bool, Bool) -> Void) {}
    func conductorDismissIT2AuthorizationPrompt(guid: String) {}
    func conductorWrite(string: String) { writes.append(string) }
    func conductorAbort(reason: String) {}
    func conductorQuit() {}
    func conductorStateDidChange() {}
    func conductorStopQueueingInput() {}
    func conductorSendInitialText() {}
    let guid = "g"

    /// The first argument of each command written.
    var commandNames: [String] {
        writes.joined().components(separatedBy: "\n\n").compactMap { command in
            command.components(separatedBy: "\n").first.flatMap { Data(base64Encoded: $0) }
                .flatMap { String(data: $0, encoding: .utf8) }
        }
    }
}

@MainActor
final class FramerPaneJobManagerTests: XCTestCase {
    private func makeConductor(_ delegate: Delegate) -> Conductor {
        let conductor = Conductor("host", boolArgs: "", dcsID: "dcs", clientUniqueID: "cid",
                                  varsToSend: [:], clientVars: [:], initialDirectory: nil,
                                  shouldInjectShellIntegration: false, parent: nil)
        conductor.framedPID = 100
        conductor.delegate = delegate
        return conductor
    }

    /// Reads the pipe until end of file. The writes happen on another queue, so this waits for
    /// data rather than reading once. The pipe does not block.
    private func readToEnd(_ fd: Int32) -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date(timeIntervalSinceNow: 30)
        while Date() < deadline {
            // Lets main-thread work, such as a kill, happen meanwhile.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            let n = read(fd, &buffer, buffer.count)
            if n > 0 {
                result.append(contentsOf: buffer[0..<n])
            } else if n == 0 {
                return result
            }
        }
        XCTFail("no end of file")
        return result
    }

    func testOutputArrivesAndExitEndsItAfterward() throws {
        let delegate = Delegate()
        let manager = try XCTUnwrap(FramerPaneJobManager(conductor: makeConductor(delegate)))
        manager.conductorPaneDidOutput(Data("hello ".utf8))
        manager.conductorPaneDidOutput(Data("world".utf8))
        manager.conductorPaneDidExit(code: 3)
        XCTAssertEqual(readToEnd(manager.fd), Data("hello world".utf8))
        XCTAssertEqual(manager.exitCode, 3)
    }

    func testLosingTheConnectionEndsIt() throws {
        let delegate = Delegate()
        let manager = try XCTUnwrap(FramerPaneJobManager(conductor: makeConductor(delegate)))
        manager.conductorPaneDidOutput(Data("partial".utf8))
        manager.conductorPaneDidLoseConnection()
        XCTAssertEqual(readToEnd(manager.fd), Data("partial".utf8))
        XCTAssertNil(manager.exitCode)
    }

    func testNoLocalProcess() throws {
        let manager = try XCTUnwrap(FramerPaneJobManager(conductor: makeConductor(Delegate())))
        XCTAssertEqual(manager.externallyVisiblePid, 0, "never mistaken for a pid on this Mac")
        XCTAssertTrue(manager.isReadOnly)
        XCTAssertTrue(manager.ioAllowed)
        XCTAssertTrue(manager.closeFileDescriptor())
        XCTAssertFalse(manager.closeFileDescriptor(), "only once")
        XCTAssertFalse(manager.ioAllowed)
    }

    func testInputSizeAndKillGoToThePane() throws {
        let delegate = Delegate()
        let conductor = makeConductor(delegate)
        let manager = try XCTUnwrap(FramerPaneJobManager(conductor: conductor))
        manager.paneDidStart(pid: 4242)
        manager.forward(Data("ls\r".utf8))
        let sent = expectation(for: NSPredicate { _, _ in delegate.commandNames.contains("send") },
                               evaluatedWith: nil)
        wait(for: [sent], timeout: 30)
        XCTAssertEqual(manager.remotePID, 4242)
        // Commands after the first wait for its reply; answer it so the next can go.
        conductor.handleCommandBegin(identifier: "x", depth: 0)
        conductor.handleCommandEnd(identifier: "x", type: "f", status: 0, depth: 0)
        manager.setGridSize(VT100GridSize(width: 100, height: 30))
        let resized = expectation(for: NSPredicate { _, _ in delegate.commandNames.contains("panesize") },
                                  evaluatedWith: nil)
        wait(for: [resized], timeout: 30)
        conductor.handleCommandBegin(identifier: "y", depth: 0)
        conductor.handleCommandEnd(identifier: "y", type: "f", status: 0, depth: 0)
        manager.kill(with: .force)
        let killed = expectation(for: NSPredicate { _, _ in delegate.commandNames.contains("kill") },
                                 evaluatedWith: nil)
        wait(for: [killed], timeout: 30)
    }

    func testKillingBeforeThePaneStartedEndsTheSession() throws {
        let manager = try XCTUnwrap(FramerPaneJobManager(conductor: makeConductor(Delegate())))
        manager.kill(with: .force)
        XCTAssertEqual(readToEnd(manager.fd), Data())
    }

    // A restored pane session waits for its leader's conductor to resynchronize, then
    // reattaches: it gets what the pane wrote meanwhile and sends its size so the program
    // redraws.
    func testARestoredPaneReattachesOnceItsConductorResynchronizes() throws {
        let delegate = Delegate()
        let live = makeConductor(delegate)
        // Answers below are not what a reset waits for, so use the reset that waits for none.
        live.framerVersion = .v1
        let json = try XCTUnwrap(live.jsonValue)
        let restored = try XCTUnwrap(Conductor.create(json, delegate: delegate))
        let manager = try XCTUnwrap(FramerPaneJobManager(
            conductorProvider: { restored },
            gridSizeProvider: { VT100GridSize(width: 90, height: 30) }))
        var reattachedPID: Int32?
        manager.didReattach = { reattachedPID = $0 }
        restored.handlePaneOutput(Data("missed".utf8), pid: 4242, depth: 0)
        manager.restore(pid: 4242)
        delegate.writes = []
        XCTAssertFalse(delegate.commandNames.contains("panes"), "not before resynchronizing")

        restored.didResynchronize()
        // Resynchronizing queues its own commands ahead of the panes query. Answer them in
        // turn; "4242" is the answer that matters.
        for _ in 0..<20 where reattachedPID == nil {
            restored.handleCommandBegin(identifier: "x", depth: 0)
            restored.handle(line: "4242", depth: 0)
            restored.handleCommandEnd(identifier: "x", type: "f", status: 0, depth: 0)
        }
        XCTAssertTrue(delegate.commandNames.contains("panes"))
        XCTAssertEqual(reattachedPID, 4242)
        restored.handlePaneOutput(Data(" then more".utf8), pid: 4242, depth: 0)
        manager.conductorPaneDidExit(code: 0)
        XCTAssertEqual(readToEnd(manager.fd), Data("missed then more".utf8))
        XCTAssertTrue(delegate.commandNames.contains("panesize"), "sent its size")
    }

    // What tells a stranded pane from one whose session is still on its way back: a session
    // that does not know its conductor yet claims its pid on every conductor.
    func testSessionsClaimTheirPanes() throws {
        let delegate = Delegate()
        let here = makeConductor(delegate)
        let elsewhere = makeConductor(delegate)
        let onHere = try XCTUnwrap(FramerPaneJobManager(conductorProvider: { here },
                                                        gridSizeProvider: { nil }))
        onHere.restore(pid: 11)
        let unplaced = try XCTUnwrap(FramerPaneJobManager(conductorProvider: { nil },
                                                          gridSizeProvider: { nil }))
        unplaced.restore(pid: 12)
        let onElsewhere = try XCTUnwrap(FramerPaneJobManager(conductorProvider: { elsewhere },
                                                             gridSizeProvider: { nil }))
        onElsewhere.restore(pid: 13)

        let claimed = FramerPaneJobManager.claimedPIDs(on: here)
        XCTAssertTrue(claimed.isSuperset(of: [11, 12]))
        XCTAssertFalse(claimed.contains(13))
        onHere.conductorPaneDidExit(code: 0)
        XCTAssertFalse(FramerPaneJobManager.claimedPIDs(on: here).contains(11), "ended")
        withExtendedLifetime([onHere, unplaced, onElsewhere]) {}
    }
}
