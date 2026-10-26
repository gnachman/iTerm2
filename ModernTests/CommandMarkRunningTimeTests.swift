//
//  CommandMarkRunningTimeTests.swift
//  iTerm2
//
//  A command mark's start and end dates must be the same on the mutation
//  thread's mark and its main-thread doppelganger. The Command Info popover
//  reads the doppelganger, so a start date stamped when a mutation is replayed
//  onto it (rather than when the command started) made quick commands show a
//  negative running time like “0:-1.999”.
//

import XCTest
@testable import iTerm2SharedARC

final class CommandMarkRunningTimeTests: XCTestCase {
    private func osc133(_ body: String) -> String {
        return "\u{1B}]133;\(body)\u{07}"
    }

    // A quick command: the prompt, command, output, exit code and next prompt
    // all arrive before the main thread syncs, as they do for `echo hi`.
    func testQuickCommandDoppelgangerDatesMatchProgenitor() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        let stream = osc133("A") + "$ " + osc133("B") + "echo hi\r\n" +
            osc133("C") + "hi\r\n" + osc133("D;0") + osc133("A") + "$ " + osc133("B")
        harness.send(Array(stream.utf8))
        harness.sync()

        guard let progenitor = harness.allScreenMarks().first(where: { $0.firstLineOfCommand == "echo hi" }) else {
            XCTFail("No command mark")
            return
        }
        guard let startDate = progenitor.startDate, let endDate = progenitor.endDate else {
            XCTFail("Command mark lacks start or end date")
            return
        }
        XCTAssertLessThanOrEqual(startDate, endDate)

        let doppelganger = progenitor.doppelganger()
        XCTAssertEqual(doppelganger.startDate, startDate)
        XCTAssertEqual(doppelganger.endDate, endDate)
        if let dStart = doppelganger.startDate, let dEnd = doppelganger.endDate {
            XCTAssertGreaterThanOrEqual(dEnd.timeIntervalSince(dStart), 0)
        }
    }

    // The auto-composer sets the command before sending it, through a
    // different code path.
    func testComposerCommandDoppelgangerStartDateMatchesProgenitor() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.send(Array((osc133("A") + "$ " + osc133("B")).utf8))
        harness.sync()
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.composerWillSendCommand("echo hi",
                                                 startingAt: VT100GridAbsCoordMake(2, 0))
        })
        guard let progenitor = harness.allScreenMarks().first(where: { $0.firstLineOfCommand == "echo hi" }),
              let startDate = progenitor.startDate else {
            XCTFail("No command mark with a start date")
            return
        }
        let doppelganger = progenitor.doppelganger()
        XCTAssertEqual(doppelganger.startDate, startDate)
    }

    func testFormattedHMS() {
        XCTAssertEqual(TimeInterval(0).formattedHMS, "0:00.000")
        XCTAssertEqual(TimeInterval(2.04).formattedHMS, "0:02.040")
        XCTAssertEqual(TimeInterval(61.5).formattedHMS, "1:01.500")
        // A slightly negative interval (clock adjustment) must not render as “0:-1.999”.
        XCTAssertEqual(TimeInterval(-0.001).formattedHMS, "0:00.000")
    }
}
