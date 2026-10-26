//
//  ConductorRestorationTests.swift
//  iTerm2
//
//  F-706: with window restoration on, quitting iTerm2 with SSH Integration sessions open and
//  relaunching it restored each conductor from its saved state, and the restored conductor
//  reset its framer at once, before the session knew whether it had reattached to the
//  process that still ran ssh. Quitting ends that process, so the session started a new
//  local shell instead, and the reset (“reset2” and a UUID, in base64, each on its own line)
//  was typed into it. A restored conductor must write nothing until the session has
//  reattached to the surviving process.
//

import XCTest
@testable import iTerm2SharedARC

private final class RecordingConductorDelegate: NSObject, ConductorDelegate {
    var written = ""

    func conductorWrite(string: String) {
        written += string
    }
    func conductorAbort(reason: String) {}
    func conductorQuit() {}
    func conductorStateDidChange() {}
    func conductorStopQueueingInput() {}
    func conductorSendInitialText() {}
    func conductorRequestIT2Authorization(guid: String,
                                          displayName: String,
                                          callerTmuxPane: String?,
                                          completion: @escaping (Bool, Bool, Bool) -> Void) {
        completion(false, false, false)
    }
    func conductorDismissIT2AuthorizationPrompt(guid: String) {}
    let guid = "recording-delegate"
}

@MainActor
final class ConductorRestorationTests: XCTestCase {
    private var conductors = [Conductor]()
    private let reset2 = "reset2".data(using: .utf8)!.base64EncodedString()

    override func tearDown() {
        for conductor in conductors {
            var current: Conductor? = conductor
            while let c = current {
                ConductorRegistry.instance.remove(conductorGUID: c.guid, sshIdentity: c.sshIdentity)
                current = c.parent
            }
        }
        conductors = []
        super.tearDown()
    }

    // The saved state of a framing connection nested in another, as when iTerm2 quit.
    private func savedState() throws -> String {
        let delegate = RecordingConductorDelegate()
        let outer = Conductor("outer.example.com", boolArgs: "", dcsID: "dcs1", clientUniqueID: "c1",
                              varsToSend: [:], clientVars: [:], initialDirectory: nil,
                              shouldInjectShellIntegration: false, parent: nil)
        outer.delegate = delegate
        outer.framedPID = 100
        outer.framerVersion = .v2
        let inner = Conductor("inner.example.com", boolArgs: "", dcsID: "dcs2", clientUniqueID: "c2",
                              varsToSend: [:], clientVars: [:], initialDirectory: nil,
                              shouldInjectShellIntegration: false, parent: outer)
        inner.delegate = delegate
        inner.framedPID = 200
        inner.framerVersion = .v2
        conductors.append(inner)
        return try XCTUnwrap(inner.jsonValue)
    }

    // The session may start a new shell rather than reattach, so restoring writes nothing.
    func testRestoringWritesNothing() throws {
        let json = try savedState()
        let delegate = RecordingConductorDelegate()
        let restored = try XCTUnwrap(Conductor.create(json, delegate: delegate))
        conductors.append(restored)
        XCTAssertEqual(delegate.written, "")
        XCTAssertTrue(restored.awaitingResynchronization)
    }

    // Once reattached to the process that still runs ssh, each framer in the chain is reset,
    // outermost first.
    func testResettingAfterReattachingResetsTheFramers() throws {
        let json = try savedState()
        let delegate = RecordingConductorDelegate()
        let restored = try XCTUnwrap(Conductor.create(json, delegate: delegate))
        conductors.append(restored)
        restored.resetAfterReattaching()
        XCTAssertTrue(delegate.written.contains(reset2), delegate.written)
    }
}
