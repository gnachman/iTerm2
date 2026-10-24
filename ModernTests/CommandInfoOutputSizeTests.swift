//
//  CommandInfoOutputSizeTests.swift
//  iTerm2
//
//  The Command Info popover’s Output row reports how many cells and lines a
//  command produced. The output range ends at the start of the next prompt,
//  exclusive, so neither the next prompt nor anything typed after it may be
//  counted.
//

import XCTest
@testable import iTerm2SharedARC

final class CommandInfoOutputSizeTests: XCTestCase {
    private func osc133(_ body: String) -> String {
        return "\u{1B}]133;\(body)\u{07}"
    }

    private func command(_ command: String, output: [String]) -> String {
        let body = output.map { $0 + "\r\n" }.joined()
        return osc133("A") + "qa % " + osc133("B") + command + "\r\n" +
            osc133("C") + body + osc133("D;0")
    }

    private func outputSize(_ harness: TerminalTestHarness,
                            _ command: String,
                            file: StaticString = #filePath,
                            line: UInt = #line) -> (cells: Int, lines: Int)? {
        guard let progenitor = harness.allScreenMarks().first(where: { $0.firstLineOfCommand == command }) else {
            XCTFail("No mark for \(command)", file: file, line: line)
            return nil
        }
        // The text view reads the main thread's copy of the mark.
        let mark = progenitor.doppelganger()
        let range = harness.screen.lineRangeOfOutput(forCommandMark: mark)
        return (harness.screen.numberOfCellsUsed(in: range),
                harness.screen.numberOfRawLines(in: range))
    }

    // Commands as in the QA repro. Each is followed by a prompt, and the
    // prompt after each command holds the next command line.
    private func runRepro(_ harness: TerminalTestHarness) {
        let stream = command("echo HELLO", output: ["HELLO"]) +
            command("echo HI", output: ["HI"]) +
            command("sleep 2", output: []) +
            command("echo MULTI", output: ["ONE", "TWO", "THREE"]) +
            osc133("A") + "qa % " + osc133("B") + "typed ahead"
        harness.feedEscapeSequence(Array(stream.utf8))
        harness.sync()
    }

    private func assertReproSizes(_ harness: TerminalTestHarness,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) {
        let hello = outputSize(harness, "echo HELLO", file: file, line: line)
        XCTAssertEqual(hello?.cells, 5, "echo HELLO cells", file: file, line: line)
        XCTAssertEqual(hello?.lines, 1, "echo HELLO lines", file: file, line: line)

        let sleep = outputSize(harness, "sleep 2", file: file, line: line)
        XCTAssertEqual(sleep?.cells, 0, "sleep 2 cells", file: file, line: line)
        XCTAssertEqual(sleep?.lines, 0, "sleep 2 lines", file: file, line: line)

        let multi = outputSize(harness, "echo MULTI", file: file, line: line)
        XCTAssertEqual(multi?.cells, 11, "echo MULTI cells", file: file, line: line)
        XCTAssertEqual(multi?.lines, 3, "echo MULTI lines", file: file, line: line)
    }

    func testOutputExcludesNextPromptOnScreen() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        runRepro(harness)
        assertReproSizes(harness)
    }

    // Same, but with the earlier commands scrolled into history and the last
    // one straddling history and the screen.
    func testOutputExcludesNextPromptInHistory() {
        let harness = TerminalTestHarness(width: 80, height: 3)
        runRepro(harness)
        assertReproSizes(harness)
    }
}
