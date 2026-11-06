//
//  PTYSessionSelectedCommandSearchTests.swift
//  ModernTests
//
//  With a command selected, Find is restricted to that command. Selecting a
//  different command while a search is active prunes the results outside the
//  new command but nothing searched inside it, so Find Next had nothing to go
//  to until the query was retyped. Selecting a command used to reset the
//  tail-find position to zero so the next tail find re-searched everything
//  under the new range; the SearchEngine rewrite dropped the only reader of
//  that position.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionSelectedCommandSearchTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // A programmatic resize clears search results, and enabling Metal
        // after the window appears relays out the session. Keep the window
        // still for the duration of the test.
        setPreferences([kPreferenceKeyUseMetal: false])
        fixture = TerminalWindowTestFixture(engageLayoutEngine: false)
        settle()
    }

    override func tearDown() {
        fixture?.close()
        fixture = nil
        super.tearDown()
    }

    // MARK: - Fixture plumbing

    private var session: PTYSession {
        guard let session = fixture.terminal.currentSession() else {
            it_fatalError("No current session")
        }
        return session
    }

    private var helper: iTermFindOnPageHelper {
        guard let textview = session.textview else {
            it_fatalError("Session has no text view")
        }
        return textview.findOnPageHelper
    }

    /// Sets preferences for the rest of the test, restoring them afterward.
    private func setPreferences(_ values: [String: Any]) {
        let ud = iTermUserDefaults.userDefaults()
        for (key, value) in values {
            let saved = ud.object(forKey: key)
            addTeardownBlock {
                if let saved {
                    ud.set(saved, forKey: key)
                } else {
                    ud.removeObject(forKey: key)
                }
            }
            ud.set(value, forKey: key)
        }
    }

    private func spin(until condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: 15)
        while !condition() && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return condition()
    }

    /// Runs the work already queued on the main queue and run loop, then the
    /// work that queued, so layout deferred with dispatch_async or
    /// performSelector:afterDelay:0 has happened.
    private func drainMainQueue() {
        for _ in 0..<2 {
            var dispatched = false
            var performed = false
            DispatchQueue.main.async {
                dispatched = true
            }
            RunLoop.main.perform {
                performed = true
            }
            XCTAssertTrue(spin(until: { dispatched && performed }), "The main queue did not drain")
        }
    }

    /// Lets the window finish laying out. The window gets its final size a
    /// little after it appears, and each resize of the session clears its
    /// search results, so wait until the grid and the scroll view have stayed
    /// put for a run of consecutive run loop passes.
    private func settle() {
        drainMainQueue()
        fixture.window.layoutIfNeeded()
        var lastSize = session.screen.size
        var lastFrame = session.view?.scrollview.frame ?? .zero
        var stablePasses = 0
        let stable = spin {
            let size = session.screen.size
            let frame = session.view?.scrollview.frame ?? .zero
            if size.width == lastSize.width && size.height == lastSize.height && NSEqualRects(frame, lastFrame) {
                stablePasses += 1
            } else {
                stablePasses = 0
                lastSize = size
                lastFrame = frame
            }
            return stablePasses >= 30
        }
        XCTAssertTrue(stable, "The window did not stop resizing")
    }

    // MARK: - Terminal content

    /// Runs a shell-integration command: prompt, typed command, output, exit code.
    private func runCommand(_ command: String, output: [String]) {
        let screen = session.screen
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalPromptDidStart(false, kind: .initial, freshLine: true, aid: nil)
            mutableState.appendString(atCursor: "$ ")
            mutableState.terminalCommandDidStart()
            mutableState.appendString(atCursor: command)
            mutableState.appendCarriageReturnLineFeed()
            mutableState.terminalCommandDidEnd()
            for line in output {
                mutableState.appendString(atCursor: line)
                mutableState.appendCarriageReturnLineFeed()
            }
            mutableState.terminalReturnCode(ofLastCommandWas: NSNumber(value: 0), aid: nil)
        })
        screen.waitForQueuedTokensForTesting()
    }

    private func promptMarks() -> [VT100ScreenMark] {
        var result = [VT100ScreenMark]()
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            result = mutableState.intervalTree.allObjects().compactMap { $0 as? VT100ScreenMark }.filter { $0.isPrompt }
        })
        return result.sorted { $0.promptRange.start.y < $1.promptRange.start.y }
    }

    /// What clicking a command does.
    private func select(_ mark: VT100ScreenMark) {
        session.perform(NSSelectorFromString("selectCommandWithMark:"), with: mark)
    }

    private func lineRange(of mark: VT100ScreenMark) -> ClosedRange<Int64> {
        let range = session.screen.rangeOfCommandAndOutput(forMark: mark, includeSucessorDivider: true)
        return range.start.y...range.end.y
    }

    // MARK: - Searching

    /// Lets the find driver's timer drain the search engine.
    private func waitForSearchToFinish() {
        XCTAssertTrue(spin(until: { !helper.findInProgress }), "Search did not finish")
    }

    private func resultLines() -> [Int64] {
        return helper.searchResults.array.map { $0.safeAbsStartY }.sorted()
    }

    private struct Commands {
        let first: VT100ScreenMark
        let third: VT100ScreenMark
        let firstLines: ClosedRange<Int64>
        let thirdLines: ClosedRange<Int64>
    }

    /// Three commands, of which the first and third contain “hello”.
    private func runThreeCommands() throws -> Commands {
        runCommand("echo hello", output: ["hello"])
        runCommand("echo bye", output: ["bye"])
        runCommand("cat greeting", output: ["hello again"])
        // Redrawing removes the search results on lines that were written
        // since the last redraw, trusting the tail find to put them back. Get
        // that out of the way before searching so the results stay put.
        _ = session.textview?.refresh()
        let marks = promptMarks()
        XCTAssertEqual(marks.count, 3, "Setup: expected three prompt marks")
        let commands = Commands(first: marks[0],
                                third: marks[2],
                                firstLines: lineRange(of: marks[0]),
                                thirdLines: lineRange(of: marks[2]))
        XCTAssertTrue(commands.firstLines.upperBound < commands.thirdLines.lowerBound,
                      "Setup: commands must not overlap")
        return commands
    }

    /// Selects the first command and searches for “hello”, verifying that the
    /// results are restricted to it.
    private func searchFirstCommand(_ commands: Commands) throws {
        select(commands.first)
        XCTAssertGreaterThan(helper.absLineRange.length, 0,
                             "Setup: selecting a command restricts the search range")
        session.showFindPanel()
        let driver = try XCTUnwrap(session.view?.findDriver)
        driver.refreshSearchResults(forQuery: "hello", mode: .caseInsensitiveSubstring)
        waitForSearchToFinish()

        let before = resultLines()
        XCTAssertFalse(before.isEmpty, "Setup: the first command contains hello")
        XCTAssertTrue(before.allSatisfy { commands.firstLines.contains($0) },
                      "Results are restricted to the selected command: \(before) vs \(commands.firstLines)")
    }

    func testSelectingAnotherCommandSearchesIt() throws {
        let commands = try runThreeCommands()
        try searchFirstCommand(commands)

        select(commands.third)
        waitForSearchToFinish()

        let after = resultLines()
        XCTAssertFalse(after.isEmpty, "Selecting another command must search inside it")
        XCTAssertTrue(after.allSatisfy { commands.thirdLines.contains($0) },
                      "Results must come from the newly selected command: \(after) vs \(commands.thirdLines)")
    }

    /// Typing deselects the command. The search must then cover everything
    /// again, but since this happens on every keystroke it must not select a
    /// result, which would scroll the view to it.
    func testDeselectingByTypingSearchesEverythingWithoutSelectingAResult() throws {
        let commands = try runThreeCommands()
        try searchFirstCommand(commands)

        session.perform(NSSelectorFromString("removeSelectedCommandRange"))
        XCTAssertEqual(helper.absLineRange.length, 0, "Deselecting lifts the restriction")
        waitForSearchToFinish()

        let after = resultLines()
        XCTAssertTrue(after.contains { commands.firstLines.contains($0) },
                      "Results must include the first command: \(after)")
        XCTAssertTrue(after.contains { commands.thirdLines.contains($0) },
                      "Results must include the third command: \(after)")
        XCTAssertNil(helper.selectedResult, "Deselecting must not select, and so scroll to, a result")
    }

    /// Turning off click-to-select deselects the command through a different
    /// path, which must also search everything again.
    func testTurningOffClickToSelectSearchesEverything() throws {
        let commands = try runThreeCommands()
        try searchFirstCommand(commands)

        setPreferences([kPreferenceKeyClickToSelectCommand: false])
        session.textViewReloadSelectedCommand()
        XCTAssertEqual(helper.absLineRange.length, 0, "The restriction is lifted with the selection")
        waitForSearchToFinish()

        let after = resultLines()
        XCTAssertTrue(after.contains { commands.thirdLines.contains($0) },
                      "Results must include the command that was not selected: \(after)")
    }
}
