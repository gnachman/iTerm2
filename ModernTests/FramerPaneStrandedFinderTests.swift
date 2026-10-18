//
//  FramerPaneStrandedFinderTests.swift
//  iTerm2 ModernTests
//
//  A pane left running on a host with no session for it, because iTerm2 restarted without
//  restoring the session, is found once restoration has settled and the connection has
//  resynchronized, and offered to the user.
//

import XCTest
@testable import iTerm2SharedARC

private final class FinderConductorDelegate: NSObject, ConductorDelegate {
    private(set) var writes = [String]()
    func conductorRequestIT2Authorization(guid: String, displayName: String, callerTmuxPane: String?,
                                          completion: @escaping (Bool, Bool, Bool) -> Void) {}
    func conductorDismissIT2AuthorizationPrompt(guid: String) {}
    func conductorWrite(string: String) { writes.append(string) }
    func conductorAbort(reason: String) {}
    func conductorQuit() {}
    func conductorStateDidChange() {}
    func conductorStopQueueingInput() {}
    func conductorSendInitialText() {}
    let guid = "the-leader"

    /// The first argument of each command written.
    var commandNames: [String] {
        writes.joined().components(separatedBy: "\n\n").filter { !$0.isEmpty }.compactMap { command in
            command.components(separatedBy: "\n").first.flatMap { Data(base64Encoded: $0) }
                .flatMap { String(data: $0, encoding: .utf8) }
        }
    }
    func reset() { writes = [] }
}

@MainActor
private final class FakePresenter: StrandedFramerPanePresenter {
    private(set) var presented = [(conductor: Conductor, pids: [Int32])]()
    func present(strandedPanes pids: [Int32], on conductor: Conductor) {
        presented.append((conductor, pids))
    }
}

private final class NullPaneClient: NSObject, ConductorPaneClient {
    func conductorPaneDidOutput(_ data: Data) {}
    func conductorPaneDidExit(code: Int32) {}
    func conductorPaneDidLoseConnection() {}
}

@MainActor
final class FramerPaneStrandedFinderTests: XCTestCase {
    private var delegate: FinderConductorDelegate!
    private var conductor: Conductor!
    private var presenter: FakePresenter!
    private var claimed = Set<Int32>()
    private var reattachRequests = 0

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            delegate = FinderConductorDelegate()
            conductor = Conductor("host", boolArgs: "", dcsID: "dcs", clientUniqueID: "cid",
                                  varsToSend: [:], clientVars: [:], initialDirectory: nil,
                                  shouldInjectShellIntegration: false, parent: nil)
            conductor.framedPID = 100
            conductor.delegate = delegate
            presenter = FakePresenter()
            claimed = []
            reattachRequests = 0
        }
    }

    private func makeFinder() -> FramerPaneStrandedFinder {
        return FramerPaneStrandedFinder(presenter: presenter,
                                        observesConductors: false,
                                        isOwned: { _ in true },
                                        claimedPIDs: { [unowned self] _ in self.claimed },
                                        reattachAll: { [unowned self] in self.reattachRequests += 1 })
    }

    private func reply(_ lines: [String], on conductor: Conductor? = nil) {
        let c = conductor ?? self.conductor!
        c.handleCommandBegin(identifier: "x", depth: c.depth)
        for line in lines {
            c.handle(line: line, depth: c.depth)
        }
        c.handleCommandEnd(identifier: "x", type: "f", status: 0, depth: c.depth)
    }

    // Sessions restored in windows decoded later may still claim their panes.
    func testNothingIsCheckedUntilRestorationSettles() {
        let finder = makeFinder()
        finder.conductorDidResynchronize(conductor)
        XCTAssertFalse(delegate.commandNames.contains("panes"))
        finder.restorationDidSettle()
        XCTAssertEqual(delegate.commandNames, ["panes"])
        reply(["7"])
        XCTAssertEqual(presenter.presented.map(\.pids), [[7]])
    }

    // A pane with a session, or with a restored session waiting to reattach, is not stranded.
    // Waiting sessions get a chance to reattach first: their requests go ahead of the query.
    func testOnlyPanesNoSessionClaimsAreOffered() {
        let finder = makeFinder()
        finder.restorationDidSettle()
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "true",
                            client: NullPaneClient()) { _ in }
        reply(["2"])
        claimed = [3]
        delegate.reset()

        finder.conductorDidResynchronize(conductor)
        XCTAssertEqual(reattachRequests, 1)
        XCTAssertEqual(delegate.commandNames, ["panes"])
        reply(["2 3 4 5"])
        XCTAssertEqual(presenter.presented.count, 1)
        XCTAssertTrue(presenter.presented.first?.conductor === conductor)
        XCTAssertEqual(presenter.presented.first?.pids, [4, 5])
    }

    func testNothingIsOfferedWhenEveryPaneIsClaimed() {
        let finder = makeFinder()
        finder.restorationDidSettle()
        claimed = [3]
        finder.conductorDidResynchronize(conductor)
        reply(["3"])
        XCTAssertTrue(presenter.presented.isEmpty)
    }

    // Its commands could be lost until it has resynchronized; the check comes with that.
    func testAConductorStillResynchronizingIsNotChecked() throws {
        let json = try XCTUnwrap(conductor.jsonValue)
        let restored = try XCTUnwrap(Conductor.create(json, delegate: delegate))
        let finder = makeFinder()
        finder.restorationDidSettle()
        delegate.reset()
        finder.conductorDidResynchronize(restored)
        XCTAssertFalse(delegate.commandNames.contains("panes"))
    }

    // A connection with no session to show the offer in is left alone.
    func testAConductorNoSessionOwnsIsNotChecked() {
        let finder = FramerPaneStrandedFinder(presenter: presenter,
                                              observesConductors: false,
                                              isOwned: { _ in false },
                                              claimedPIDs: { _ in [] },
                                              reattachAll: {})
        finder.restorationDidSettle()
        finder.conductorDidResynchronize(conductor)
        XCTAssertTrue(delegate.commandNames.isEmpty)
    }
}
