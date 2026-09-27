//
//  CSIWindowReportTests.swift
//  iTerm2 ModernTests
//
//  Regression test for issue 13035's secondary observation: `CSI 16 t` (report
//  character cell size) was never answered because the CSI parser had no case for
//  parameter 16, so the sequence was classified as unsupported. `CSI 14 t` and
//  `CSI 18 t` were answered normally. The fix adds the 16 case and a handler that
//  replies `CSI 6 ; height ; width t`. xterm defines this report in pixels, but
//  iTerm2 reports it in points to match its points-based CSI 14 t.
//

import XCTest
@testable import iTerm2SharedARC

final class CSIWindowReportTests: XCTestCase {
    private func feed(_ harness: TerminalTestHarness, _ string: String) {
        let bytes = Array(string.utf8).map { CChar(bitPattern: $0) }
        bytes.withUnsafeBufferPointer { ptr in
            let raw = UnsafeMutablePointer(mutating: ptr.baseAddress!)
            harness.screen.threadedReadTask(raw, length: Int32(bytes.count))
        }
    }

    private func waitForReport(_ harness: TerminalTestHarness,
                               timeout: TimeInterval = 5) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            harness.sync()
            if let data = harness.delegate.sentReports.first {
                return String(data: data, encoding: .utf8)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return harness.delegate.sentReports.first.flatMap { String(data: $0, encoding: .utf8) }
    }

    /// `CSI 16 t` must produce a `CSI 6 ; height ; width t` reply. Before the fix
    /// it produced no reply at all.
    func testReportCellSize() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        feed(harness, "\u{1B}[16t")
        let reply = waitForReport(harness)

        XCTAssertNotNil(reply, "CSI 16t must be answered (it was silently unsupported before the fix)")
        if let reply {
            let pattern = "^\u{1B}\\[6;[0-9]+;[0-9]+t$"
            XCTAssertNotNil(reply.range(of: pattern, options: .regularExpression),
                            "CSI 16t reply must be ESC[6;<height>;<width>t; got \(reply.debugDescription)")
        }
    }

    /// `CSI 14 t` (text area size) must still be answered with a
    /// `CSI 4 ; height ; width t` reply, to guard against the 16 case
    /// accidentally disturbing its neighbor.
    func testReportTextAreaSizeStillWorks() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        feed(harness, "\u{1B}[14t")
        let reply = waitForReport(harness)

        XCTAssertNotNil(reply, "CSI 14t must be answered")
        if let reply {
            let pattern = "^\u{1B}\\[4;[0-9]+;[0-9]+t$"
            XCTAssertNotNil(reply.range(of: pattern, options: .regularExpression),
                            "CSI 14t reply must be ESC[4;<height>;<width>t; got \(reply.debugDescription)")
        }
    }
}
