//
//  TmuxClientReportTests.swift
//  ModernTests
//
//  tmux answers most reports itself, so a tmux integration pane doesn't send them. A few iTerm2
//  reports pass that check because tmux doesn't know them, but the report was then dropped anyway
//  because the send path refused every report for a tmux client. QA finding F-058.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxClientReportTests: XCTestCase {
    private func osc1337(_ payload: String) -> [UInt8] {
        return Array("\u{1b}]1337;\(payload)\u{07}".utf8)
    }

    private func tmuxHarness() -> TerminalTestHarness {
        let harness = TerminalTestHarness()
        harness.delegate.configuration.isTmuxClient = true
        harness.delegate.configuration.isDirty = true
        harness.sync()
        return harness
    }

    /// Waits for the first report and returns every report sent by then.
    private func waitForReports(_ harness: TerminalTestHarness, timeout: TimeInterval = 30) -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            harness.sync()
            if !harness.delegate.sentReports.isEmpty {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return harness.delegate.sentReports.compactMap { String(data: $0, encoding: .utf8) }
    }

    func testReportCellSizeIsAnsweredInTmux() {
        let harness = tmuxHarness()
        // tmux answers a cursor position report itself, so this one must not go out. It's sent
        // first so it would be seen before the cell size report if it did.
        harness.send(Array("\u{1b}[6n".utf8) + osc1337("ReportCellSize"))
        let reports = waitForReports(harness)
        XCTAssertEqual(reports.count, 1, "\(reports)")
        XCTAssertTrue(reports.first?.hasPrefix("\u{1b}]1337;ReportCellSize=") ?? false, "\(reports)")
    }

    func testReportWindowFrameIsAnsweredInTmux() {
        let harness = tmuxHarness()
        harness.send(osc1337("ReportWindowFrame"))
        let reports = waitForReports(harness)
        XCTAssertEqual(reports.count, 1, "\(reports)")
        XCTAssertTrue(reports.first?.hasPrefix("\u{1b}]1337;WindowFrame=") ?? false, "\(reports)")
    }
}
