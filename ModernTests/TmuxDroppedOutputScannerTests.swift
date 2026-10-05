//
//  TmuxDroppedOutputScannerTests.swift
//  iTerm2
//
//  Created by George Nachman on 10/3/26.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxDroppedOutputScannerTests: XCTestCase {
    private func kvps(_ scanner: TmuxDroppedOutputScanner) -> [String] {
        return scanner.tokens.map { "\($0.kvpKey ?? "")=\($0.kvpValue ?? "")" }
    }

    private func data(_ string: String) -> Data {
        return string.data(using: .utf8)!
    }

    func testCapturesSetUserVar() {
        let scanner = TmuxDroppedOutputScanner()
        scanner.consume(data("hello\u{1b}]1337;SetUserVar=host_name=Ym94\u{07}world"))
        XCTAssertEqual(kvps(scanner), ["SetUserVar=host_name=Ym94"])
    }

    // The sequence may be split across %extended-output messages at any byte, including the
    // split seen in issue 13006 where ESC ] arrived in one message and the rest in the next.
    func testSequenceSplitAtEveryPosition() {
        for terminator in ["\u{07}", "\u{1b}\\"] {
            let bytes = Array(data("abc\u{1b}]1337;SetUserVar=host_name=Ym94\(terminator)def"))
            for split in 0...bytes.count {
                let scanner = TmuxDroppedOutputScanner()
                scanner.consume(Data(bytes[0..<split]))
                scanner.consume(Data(bytes[split...]))
                XCTAssertEqual(kvps(scanner), ["SetUserVar=host_name=Ym94"],
                               "split=\(split) terminator=\(terminator.debugDescription)")
            }
        }
    }

    func testCapturesShellIntegrationLocationAndVersion() {
        let scanner = TmuxDroppedOutputScanner()
        scanner.consume(data("\u{1b}]1337;RemoteHost=user@example.com\u{07}"
                             + "\u{1b}]1337;CurrentDir=/home/user\u{07}"
                             + "\u{1b}]1337;ShellIntegrationVersion=18;shell=bash\u{07}"))
        XCTAssertEqual(kvps(scanner), ["RemoteHost=user@example.com",
                                       "CurrentDir=/home/user",
                                       "ShellIntegrationVersion=18;shell=bash"])
    }

    func testIgnoresSequencesOutsideWhitelist() {
        let scanner = TmuxDroppedOutputScanner()
        scanner.consume(data("\u{1b}]1337;SetBadgeFormat=SGVsbG8=\u{07}"
                             + "\u{1b}]1337;SetProfile=Default\u{07}"
                             + "\u{1b}]1337;SetMark\u{07}"
                             + "\u{1b}]133;A\u{07}"
                             + "\u{1b}]7;file://host/tmp\u{07}"
                             + "\u{1b}]0;title\u{07}"
                             + "\u{1b}[?2004h"
                             + "plain text\r\n"))
        XCTAssertEqual(kvps(scanner), [])
    }

    // Only the last value of each key survives, so that replaying produces at most one host
    // change. Distinct user variables are distinct keys. The order is that of the last
    // occurrence of each key.
    func testCoalescesToLastValuePerKey() {
        let scanner = TmuxDroppedOutputScanner()
        scanner.consume(data("\u{1b}]1337;RemoteHost=a@one\u{07}"
                             + "\u{1b}]1337;SetUserVar=x=MQ==\u{07}"
                             + "\u{1b}]1337;SetUserVar=y=Mg==\u{07}"
                             + "\u{1b}]1337;CurrentDir=/one\u{07}"
                             + "\u{1b}]1337;RemoteHost=b@two\u{07}"
                             + "\u{1b}]1337;SetUserVar=x=Mw==\u{07}"))
        XCTAssertEqual(kvps(scanner), ["SetUserVar=y=Mg==",
                                       "CurrentDir=/one",
                                       "RemoteHost=b@two",
                                       "SetUserVar=x=Mw=="])
    }

    // A SetUserVar with no "=" unsets the variable and shares a key with one that sets it.
    func testUnsetUserVarReplacesSet() {
        let scanner = TmuxDroppedOutputScanner()
        scanner.consume(data("\u{1b}]1337;SetUserVar=x=MQ==\u{07}\u{1b}]1337;SetUserVar=x\u{07}"))
        XCTAssertEqual(kvps(scanner), ["SetUserVar=x"])
    }

    // The %extended-output stream from issue 13006 as iTerm2 received it before the pane's
    // session existed.
    func testIssue13006Stream() {
        let chunks = [
            "\u{1b}]1337;RemoteHost=debian@ns3119878.ip-51-38-181.eu\u{07}\u{1b}]1337;CurrentDir=/home/debian\u{07}",
            "\u{1b}]1337;ShellIntegrationVersion=18;shell=bash\u{07}",
            "\u{1b}]133;C;\u{07}",
            "\u{1b}]1337;RemoteHost=debian@ns3119878.ip-51-38-181.eu\u{07}\u{1b}]1337;CurrentDir=/home/debian\u{07}",
            "\u{1b}]",
            "1337;SetUserVar=host_name=bnMzMTE5ODc4\u{07}",
            "\u{1b}[?2004h\u{1b}]133;D;0\u{07}\u{1b}]133;A\u{07}\u{1b}]0;debian@ns3119878: ~\u{07}\u{1b}[01;32mdebian@ns3119878\u{1b}[00m:\u{1b}[01;34m~\u{1b}[00m$ \u{1b}]133;B\u{07}"
        ]
        let scanner = TmuxDroppedOutputScanner()
        for chunk in chunks {
            scanner.consume(data(chunk))
        }
        XCTAssertEqual(kvps(scanner), ["ShellIntegrationVersion=18;shell=bash",
                                       "RemoteHost=debian@ns3119878.ip-51-38-181.eu",
                                       "CurrentDir=/home/debian",
                                       "SetUserVar=host_name=bnMzMTE5ODc4"])
    }

    // Executing captured tokens while applying the tmux state delivers them to the session.
    func testSetTmuxStateExecutesDeferredTokens() {
        let harness = TerminalTestHarness()
        let spy = UserVarSpy()
        harness.screen.delegate = spy
        spy.screen = harness.screen

        let scanner = TmuxDroppedOutputScanner()
        scanner.consume(data("\u{1b}]1337;SetUserVar=host_name=Ym94\u{07}"))
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setTmux([kTmuxWindowOpenerStateDeferredTokens: scanner.tokens])
        })
        harness.sync()
        XCTAssertEqual(spy.userVars, ["host_name=Ym94"])
    }
}

// Decides which panes' dropped output is scanned: only panes about to get a new session, never
// panes in hidden windows.
final class TmuxDroppedOutputTrackerTests: XCTestCase {
    private let userVar = "\u{1b}]1337;SetUserVar=x=MQ==\u{07}".data(using: .utf8)!

    private func kvps(_ tokens: [VT100Token]) -> [String] {
        return tokens.map { "\($0.kvpKey ?? "")=\($0.kvpValue ?? "")" }
    }

    func testIgnoresPaneThatIsNotBeingOpened() {
        let tracker = TmuxDroppedOutputTracker()
        tracker.didLearnPanes([1, 2], window: 1)
        tracker.didDropOutput(userVar, pane: 2)
        XCTAssertEqual(kvps(tracker.takeTokens(pane: 2)), [])
    }

    func testCapturesPaneBeingOpened() {
        let tracker = TmuxDroppedOutputTracker()
        tracker.didLearnPanes([1, 2], window: 1)
        tracker.willOpenPane(2)
        tracker.didDropOutput(userVar, pane: 2)
        XCTAssertEqual(kvps(tracker.takeTokens(pane: 2)), ["SetUserVar=x=MQ=="])
    }

    // After %window-add the new window's panes aren't known until its layout is fetched. Its
    // panes are newer than every known pane; older ones belong to hidden windows.
    func testWindowAwaitingLayoutCapturesOnlyUnknownPanes() {
        let tracker = TmuxDroppedOutputTracker()
        tracker.didLearnPanes([0, 3], window: 0)
        tracker.windowWillAwaitLayout(5)
        tracker.didDropOutput(userVar, pane: 3)
        tracker.didDropOutput(userVar, pane: 4)
        XCTAssertEqual(kvps(tracker.takeTokens(pane: 3)), [])
        XCTAssertEqual(kvps(tracker.takeTokens(pane: 4)), ["SetUserVar=x=MQ=="])
    }

    // The window's layout may arrive in a %layout-change before the opener starts. That must not
    // make its panes look like old ones.
    func testLayoutOfWindowAwaitingLayoutKeepsItsPanes() {
        let tracker = TmuxDroppedOutputTracker()
        tracker.didLearnPanes([0], window: 0)
        tracker.windowWillAwaitLayout(1)
        tracker.didDropOutput(userVar, pane: 1)
        tracker.didLearnPanes([1], window: 1)
        tracker.willOpenPane(1)
        tracker.didLearnPanes([1], window: 1)
        tracker.windowDidStopAwaitingLayout(1)
        XCTAssertEqual(kvps(tracker.takeTokens(pane: 1)), ["SetUserVar=x=MQ=="])
    }

    func testWindowThatIsNotOpenedDiscardsItsScanners() {
        let tracker = TmuxDroppedOutputTracker()
        tracker.windowWillAwaitLayout(1)
        tracker.didDropOutput(userVar, pane: 1)
        tracker.didLearnPanes([1], window: 1)
        tracker.windowDidStopAwaitingLayout(1)
        XCTAssertEqual(kvps(tracker.takeTokens(pane: 1)), [])
        tracker.didDropOutput(userVar, pane: 1)
        XCTAssertEqual(kvps(tracker.takeTokens(pane: 1)), [])
    }

    func testFinishingOpenStopsCapturing() {
        let tracker = TmuxDroppedOutputTracker()
        tracker.didLearnPanes([1], window: 1)
        tracker.willOpenPane(1)
        tracker.didFinishOpeningPanes([1])
        tracker.didDropOutput(userVar, pane: 1)
        XCTAssertEqual(kvps(tracker.takeTokens(pane: 1)), [])
    }

    func testResetForgetsEverything() {
        let tracker = TmuxDroppedOutputTracker()
        tracker.willOpenPane(1)
        tracker.didDropOutput(userVar, pane: 1)
        tracker.reset()
        XCTAssertEqual(kvps(tracker.takeTokens(pane: 1)), [])
        tracker.didDropOutput(userVar, pane: 1)
        XCTAssertEqual(kvps(tracker.takeTokens(pane: 1)), [])
    }
}

private class UserVarSpy: FakeSession {
    var userVars = [String]()

    override func screenSetUserVar(_ kvp: String) {
        userVars.append(kvp)
    }
}
