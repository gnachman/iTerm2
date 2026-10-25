//
//  FrameDelayBaselineTests.swift
//  iTerm2 ModernTests
//
//  The baseline queueing delay is measured from, allowing for frame size: the link's cost per
//  byte read off the least delays of frames of different sizes.
//

import XCTest
@testable import iTerm2SharedARC

final class FrameDelayBaselineTests: XCTestCase {
    private let window: TimeInterval = 10
    private let sizes = [40, 200, 700, 1500, 3000, 4096]

    /// A deterministic jitter in [0, 1).
    private struct Noise {
        var state: UInt64 = 0x9E3779B97F4A7C15
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    /// Frames of `sizes` in turn over `seconds`, crossing a link of `rate` bytes a second and
    /// `oneWay` seconds, each queued up to `queueing` more, with every fifth one queued not at all.
    private func baseline(rate: Double, oneWay: TimeInterval, queueing: TimeInterval,
                          seconds: TimeInterval = 5, offset: TimeInterval = 4321) -> FrameDelayBaseline {
        var noise = Noise()
        var baseline = FrameDelayBaseline()
        var t = 0.0
        var i = 0
        while t < seconds {
            let bytes = sizes[i % sizes.count]
            let queued = i % 5 == 0 ? 0 : noise.next() * queueing
            baseline.add(delay: offset + oneWay + Double(bytes) / rate + queued, bytes: bytes, now: t, window: window)
            t += 0.01
            i += 1
        }
        return baseline
    }

    func testItFindsTheCostPerByteOfASlowLink() {
        let e = baseline(rate: 20 * 1024, oneWay: 0.015, queueing: 0.3).evaluate(now: 5, window: window)
        XCTAssertEqual(e.correction(forBytes: 4096) - e.correction(forBytes: 40), (4096.0 - 40) / (20 * 1024), accuracy: 0.002)
        XCTAssertEqual(try XCTUnwrap(e.base), 4321 + 0.015 + 40.0 / (20 * 1024), accuracy: 0.001)
    }

    func testAFastLinkCostsNothingPerByte() {
        let e = baseline(rate: 10 * 1024 * 1024, oneWay: 0.015, queueing: 0.05).evaluate(now: 5, window: window)
        XCTAssertEqual(e.correction(forBytes: 4096) - e.correction(forBytes: 40), 0, accuracy: 0.001)
    }

    // What went wrong with the delivery rate's correction cannot happen: every bucket the edge is
    // drawn through reads the baseline at its least, whatever the slope, so no size of frame
    // looks queued against another.
    func testEachBucketOnTheEdgeReadsTheBaseAtItsLeast() throws {
        let rates: [Double] = [5 * 1024, 20 * 1024, 1024 * 1024]
        for rate in rates {
            let e = baseline(rate: rate, oneWay: 0.03, queueing: 0.2).evaluate(now: 5, window: window)
            let base = try XCTUnwrap(e.base)
            let onEdge = e.buckets.filter(\.onEdge)
            XCTAssertGreaterThanOrEqual(onEdge.count, 2, "rate \(rate)")
            for bucket in onEdge {
                let delay = try XCTUnwrap(bucket.leastDelay) - e.correction(forBytes: try XCTUnwrap(bucket.leastBytes))
                XCTAssertEqual(delay, base, accuracy: 1e-9, "rate \(rate), bucket from \(bucket.lowerBound)")
            }
            for bucket in e.buckets where !bucket.onEdge {
                if let least = bucket.leastDelay, let bytes = bucket.leastBytes {
                    XCTAssertGreaterThanOrEqual(least - e.correction(forBytes: bytes), base - 1e-9,
                                                "nothing reads below the base")
                }
            }
        }
    }

    // Frames that hardly vary in size get no correction: it would be the same for all of them.
    func testSimilarSizesAreNotCorrected() {
        var baseline = FrameDelayBaseline()
        for i in 0..<200 {
            let bytes = [3000, 3500, 4096][i % 3]
            baseline.add(delay: 1 + Double(bytes) / 20480, bytes: bytes, now: Double(i) / 100, window: window)
        }
        let e = baseline.evaluate(now: 2, window: window)
        XCTAssertTrue(e.edge.isEmpty)
        XCTAssertEqual(e.correction(forBytes: 4096), 0)
        XCTAssertEqual(try XCTUnwrap(e.base), 1 + 3000.0 / 20480, accuracy: 1e-9)
    }

    // A bucket that has not seen an empty path has a least delay that is too high. The lower edge
    // passes under it, so it changes nothing, however few or many readings it has.
    func testABucketThatHasNotSeenAnEmptyPathIsLeftOffTheEdge() {
        var baseline = FrameDelayBaseline()
        for i in 0..<50 {
            baseline.add(delay: 1 + 100.0 / 20480, bytes: 100, now: Double(i) / 100, window: window)
            baseline.add(delay: 1 + 4096.0 / 20480, bytes: 4096, now: Double(i) / 100, window: window)
        }
        for i in 0..<3 {
            baseline.add(delay: 5, bytes: 1500, now: Double(i) / 100, window: window)
        }
        let e = baseline.evaluate(now: 1, window: window)
        XCTAssertEqual(e.buckets.filter(\.onEdge).map(\.lowerBound), [0, 4096])
        XCTAssertEqual(e.costPerKilobyte, 1024.0 / 20480, accuracy: 1e-9)
    }

    // A rare size, such as echo during a flood, counts from its first reading: with only large
    // frames to go by, the correction would vanish and the echo would make them look queued.
    func testARareSizeCountsFromItsFirstReading() {
        var baseline = FrameDelayBaseline()
        for i in 0..<200 {
            baseline.add(delay: 1 + 1024.0 / 20480 + 0.01 * Double(i % 7), bytes: 1024, now: Double(i) / 100, window: window)
        }
        baseline.add(delay: 1 + 45.0 / 20480, bytes: 45, now: 1, window: window)
        baseline.add(delay: 1 + 300.0 / 20480, bytes: 300, now: 1.5, window: window)
        let e = baseline.evaluate(now: 2, window: window)
        XCTAssertEqual(e.costPerKilobyte, 1024.0 / 20480, accuracy: 1e-6)
    }

    // A cost that falls with size is noise; one steeper than 1 KB/s is not believed.
    func testTheCostNeverFallsNorExceedsTheSteepest() {
        var falling = FrameDelayBaseline()
        var steep = FrameDelayBaseline()
        for i in 0..<50 {
            let t = Double(i) / 100
            falling.add(delay: 1.1, bytes: 100, now: t, window: window)
            falling.add(delay: 1.0, bytes: 4096, now: t, window: window)
            steep.add(delay: 1, bytes: 100, now: t, window: window)
            steep.add(delay: 100, bytes: 4096, now: t, window: window)
        }
        XCTAssertEqual(falling.evaluate(now: 1, window: window).costPerKilobyte, 0)
        XCTAssertEqual(steep.evaluate(now: 1, window: window).costPerKilobyte, 1, accuracy: 1e-9)
    }

    // A least delay lasts between half a window and a window, so a slow stretch is forgotten.
    func testOldReadingsAgeOut() {
        var baseline = FrameDelayBaseline()
        for i in 0..<100 {
            baseline.add(delay: 1, bytes: 100, now: Double(i) / 100, window: window)
        }
        XCTAssertNotNil(baseline.evaluate(now: 9, window: window).base)
        XCTAssertNil(baseline.evaluate(now: 21, window: window).base)
        XCTAssertEqual(baseline.evaluate(now: 21, window: window).buckets[0].readings, 0)
    }

    // Reading it changes nothing.
    func testEvaluatingDoesNotChangeIt() {
        let a = baseline(rate: 20 * 1024, oneWay: 0.015, queueing: 0.3)
        var b = a
        for t in stride(from: 0.0, to: 30, by: 0.37) {
            _ = b.evaluate(now: t, window: window)
        }
        b.add(delay: 4321.5, bytes: 300, now: 12, window: window)
        var c = a
        c.add(delay: 4321.5, bytes: 300, now: 12, window: window)
        XCTAssertEqual(b.evaluate(now: 13, window: window).buckets, c.evaluate(now: 13, window: window).buckets)
    }

    // Two frames on either side of a bucket boundary can differ by a byte. A few ms of jitter
    // between them would make the steepest slope believed, and frames beyond the last point,
    // corrected along it, would read seconds below the baseline. Points on the edge are at least
    // twice the size of the one before.
    func testNeighboringSizesDoNotMakeASteepSegment() {
        let cost = 1.0 / 20480
        var baseline = FrameDelayBaseline()
        for i in 0..<60 {
            let t = Double(i) / 100
            baseline.add(delay: 1 + 100 * cost, bytes: 100, now: t, window: window)
            baseline.add(delay: 1 + 2047 * cost, bytes: 2047, now: t, window: window)
            baseline.add(delay: 1 + 2048 * cost + 0.01, bytes: 2048, now: t, window: window)
        }
        let e = baseline.evaluate(now: 1, window: window)
        let edge = e.edge.map(\.bytes)
        for (a, b) in zip(edge, edge.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b, 2 * a, "edge \(edge)")
        }
        XCTAssertEqual(e.correction(forBytes: 4096) - e.correction(forBytes: 2048), 2048 * cost, accuracy: 0.2 * 2048 * cost)
        XCTAssertEqual(e.costPerKilobyte, 1024 * cost, accuracy: 0.2 * 1024 * cost)
    }
}
