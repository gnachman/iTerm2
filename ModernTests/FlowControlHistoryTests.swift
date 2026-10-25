//
//  FlowControlHistoryTests.swift
//  iTerm2 ModernTests
//
//  The flow control monitor's record of a conductor's controller: the last minute of snapshots,
//  and rates worked out from consecutive ones.
//

import XCTest
@testable import iTerm2SharedARC

final class FlowControlHistoryTests: XCTestCase {
    typealias Controller = FramerFlowController

    private func makeController() -> Controller {
        Controller(now: 0, recovering: false) { _ in }
    }

    /// The leader's frame of `bytes`, arrived and consumed at `now`.
    private func pass(_ c: Controller, bytes: Int, at now: TimeInterval) {
        c.frameDidArrive(now: now, sendMilliseconds: Int64(now * 1000), bytes: bytes,
                         limited: false, exempt: false)
        c.flowDidConsume(.leader, bytes: bytes, now: now)
    }

    func testItKeepsTheLastMinute() {
        let c = makeController()
        var history = FlowControlHistory()
        for second in 0...120 {
            history.record(c.snapshot(now: Double(second)), at: Double(second))
        }
        XCTAssertEqual(history.samples.first?.time, 60)
        XCTAssertEqual(history.samples.last?.time, 120)
        XCTAssertEqual(history.samples.count, 61)
    }

    func testAValueIsTakenFromEachSample() {
        let c = makeController()
        var history = FlowControlHistory()
        history.record(c.snapshot(now: 0), at: 0)
        pass(c, bytes: 1000, at: 0.1)
        history.record(c.snapshot(now: 0.2), at: 0.2)
        let consumed = history.values { Double($0.consumed) }
        XCTAssertEqual(consumed.map(\.time), [0, 0.2])
        XCTAssertEqual(consumed.map(\.value), [0, 1000])
    }

    func testARateIsTheChangeBetweenSamples() {
        let c = makeController()
        var history = FlowControlHistory()
        history.record(c.snapshot(now: 0), at: 0)
        pass(c, bytes: 1000, at: 0.25)
        history.record(c.snapshot(now: 0.5), at: 0.5)
        pass(c, bytes: 3000, at: 0.75)
        history.record(c.snapshot(now: 1), at: 1)
        let rates = history.rate { $0.consumed }
        XCTAssertEqual(rates.map(\.time), [0.5, 1])
        XCTAssertEqual(rates.map(\.value), [2000, 6000])
    }

    // Flow control starting again brings a new controller whose totals start over. The fall
    // is not a negative rate; the chart shows a gap there instead.
    func testARestartedControllerLeavesAGap() {
        let first = makeController()
        pass(first, bytes: 5000, at: 0.1)
        var history = FlowControlHistory()
        history.record(first.snapshot(now: 0.2), at: 0.2)
        let second = makeController()
        history.record(second.snapshot(now: 0.4), at: 0.4)
        pass(second, bytes: 400, at: 0.5)
        history.record(second.snapshot(now: 0.6), at: 0.6)
        let rates = history.rate { $0.consumed }
        XCTAssertEqual(rates.map(\.time), [0.4, 0.6])
        XCTAssertNil(rates[0].value)
        XCTAssertEqual(try XCTUnwrap(rates[1].value), 2000, accuracy: 1e-6)
    }

    // A conductor whose flow control is off has no snapshot. Its stretch shows as a gap, not a
    // line drawn across it.
    func testAStretchWithoutFlowControlIsAGap() {
        let c = makeController()
        var history = FlowControlHistory()
        history.record(c.snapshot(now: 0), at: 0)
        history.recordGap(at: 1)
        history.record(c.snapshot(now: 2), at: 2)
        XCTAssertEqual(history.values { $0.window }.map { $0.value == nil }, [false, true, false])
        XCTAssertEqual(history.rate { $0.consumed }.map { $0.value == nil }, [true, true])
    }

    // Over a span, the rate is from the latest sample at least that much earlier.
    func testARateOverASpanSmoothsBursts() throws {
        let c = makeController()
        var history = FlowControlHistory()
        for tenth in 0...20 {
            let t = Double(tenth) / 10
            if tenth % 5 == 0 && tenth > 0 {
                // A burst every half second.
                pass(c, bytes: 1000, at: t - 0.05)
            }
            history.record(c.snapshot(now: t), at: t)
        }
        let rates = history.rate(over: 1) { $0.consumed }
        let atTwo = try XCTUnwrap(rates.last)
        XCTAssertEqual(atTwo.time, 2)
        // From 1.0 to 2.0: the bursts at 1.45 and 1.95.
        XCTAssertEqual(try XCTUnwrap(atTwo.value), 2000, accuracy: 1e-6)
        let jagged = history.rate { $0.consumed }.compactMap(\.value)
        XCTAssertEqual(try XCTUnwrap(jagged.max()), 10_000, accuracy: 1e-6,
                       "a tenth of a second alone sees a burst as 10 KB/s")
    }

    // A restart anywhere in the span leaves no rate there.
    func testARestartInsideTheSpanLeavesAGap() {
        let first = makeController()
        pass(first, bytes: 5000, at: 0.05)
        var history = FlowControlHistory()
        history.record(first.snapshot(now: 0.1), at: 0.1)
        history.record(first.snapshot(now: 0.2), at: 0.2)
        let second = makeController()
        history.record(second.snapshot(now: 0.3), at: 0.3)
        pass(second, bytes: 100, at: 0.35)
        history.record(second.snapshot(now: 0.4), at: 0.4)
        let rates = history.rate(over: 1) { $0.consumed }
        XCTAssertEqual(rates.map(\.time), [0.2, 0.3, 0.4])
        XCTAssertEqual(rates.map { $0.value == nil }, [false, true, true])
    }

    // For the window: the least and most of a series over a trailing span, and its mean.
    func testExtremesAndMeanOverASpan() throws {
        // Each point's value is its time, except a missing one at 0.3.
        let points = (0...10).map { tenth -> FlowControlHistory.Point in
            let t = Double(tenth) / 10
            return FlowControlHistory.Point(time: t, value: tenth == 3 ? nil : t)
        }
        let band = FlowControlHistory.extremes(of: points, over: 0.5)
        let last = try XCTUnwrap(band.last)
        XCTAssertEqual(last.time, 1)
        XCTAssertEqual(try XCTUnwrap(last.least), 0.6, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(last.most), 1, accuracy: 1e-9)
        let mean = FlowControlHistory.mean(of: points, over: 0.5)
        XCTAssertEqual(try XCTUnwrap(mean.last?.value), 0.8, accuracy: 1e-9)
        // Around the missing point, only the others count.
        let atPoint4 = try XCTUnwrap(mean.first { abs($0.time - 0.4) < 1e-9 }?.value)
        XCTAssertEqual(atPoint4, (0 + 0.1 + 0.2 + 0.4) / 4, accuracy: 1e-9)
        // Where nothing in the span has a value, neither has the result.
        let gap = [FlowControlHistory.Point(time: 0, value: nil), FlowControlHistory.Point(time: 1, value: nil)]
        XCTAssertNil(FlowControlHistory.mean(of: gap, over: 0.5).last?.value)
        XCTAssertNil(FlowControlHistory.extremes(of: gap, over: 0.5).last?.least)
    }

    // A session's bytes received, sampled as a running total, give its receive rate whether or
    // not flow control is on.
    func testARateFromRunningTotals() throws {
        let totals = [0.0, 1000, 3000, nil, 3500, 500].enumerated().map {
            FlowControlHistory.Point(time: Double($0.offset) / 2, value: $0.element)
        }
        let rates = FlowControlHistory.rate(ofTotals: totals, over: 0)
        XCTAssertEqual(rates.map(\.time), [0.5, 1, 1.5, 2, 2.5])
        XCTAssertEqual(rates.map(\.value), [2000, 4000, nil, nil, nil], "a gap, then a total that fell")
        let smoothed = FlowControlHistory.rate(ofTotals: Array(totals.prefix(3)), over: 1)
        XCTAssertEqual(try XCTUnwrap(smoothed.last?.value), 3000, accuracy: 1e-9)
    }
}
