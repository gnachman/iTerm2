//
//  FlowControlHistory.swift
//  iTerm2SharedARC
//
//  The flow control monitor's record of one conductor's controller: snapshots from the last
//  minute, and the values and rates its charts plot. A stretch without a controller (flow
//  control off, or starting again) is a gap, so a chart does not draw a line across it.
//

import Foundation

struct FlowControlHistory {
    typealias Snapshot = FramerFlowController.Snapshot

    struct Sample {
        var time: TimeInterval
        /// Nil while the conductor had no controller.
        var snapshot: Snapshot?
    }

    struct Point: Equatable {
        var time: TimeInterval
        var value: Double?
    }

    /// The least and most of a series over a span, for drawing a band.
    struct Band: Equatable {
        var time: TimeInterval
        var least: Double?
        var most: Double?
    }

    let duration: TimeInterval
    private(set) var samples = [Sample]()

    init(duration: TimeInterval = 60) {
        self.duration = duration
    }

    mutating func record(_ snapshot: Snapshot, at time: TimeInterval) {
        append(Sample(time: time, snapshot: snapshot))
    }

    mutating func recordGap(at time: TimeInterval) {
        append(Sample(time: time, snapshot: nil))
    }

    private mutating func append(_ sample: Sample) {
        samples.append(sample)
        let horizon = sample.time - duration
        if let keep = samples.firstIndex(where: { $0.time >= horizon }), keep > 0 {
            samples.removeFirst(keep)
        }
    }

    /// `value` of each sample.
    func values(_ value: (Snapshot) -> Double?) -> [Point] {
        samples.map { Point(time: $0.time, value: $0.snapshot.flatMap(value)) }
    }

    /// How fast `total`, a count of bytes since flow control started, grew up to each sample, in
    /// bytes per second (see `rate(ofTotals:over:)`). Where a sample has no controller, there is
    /// no rate.
    func rate(over span: TimeInterval = 0, of total: (Snapshot) -> Int) -> [Point] {
        Self.rate(ofTotals: values { Double(total($0)) }, over: span)
    }

    /// How fast a running total grew up to each point, in units per second: since the latest
    /// point at least `span` earlier, or the one just before. A longer span smooths output that
    /// arrives in bursts. Where the total is missing or fell (a new count starting over) anywhere
    /// in between, there is no rate.
    static func rate(ofTotals totals: [Point], over span: TimeInterval) -> [Point] {
        var points = [Point]()
        for (index, later) in totals.enumerated() where index > 0 {
            var start = index - 1
            while start > 0 && later.time - totals[start].time < span {
                start -= 1
            }
            let stretch = totals[start...index]
            let values = stretch.compactMap(\.value)
            guard values.count == stretch.count,
                  zip(values, values.dropFirst()).allSatisfy({ $0 <= $1 }),
                  let first = values.first, let last = values.last,
                  later.time > totals[start].time else {
                points.append(Point(time: later.time, value: nil))
                continue
            }
            points.append(Point(time: later.time, value: (last - first) / (later.time - totals[start].time)))
        }
        return points
    }

    /// For each point, the values of `points` in the `span` up to and including it.
    private static func trailing(_ points: [Point], over span: TimeInterval) -> [(time: TimeInterval, values: [Double])] {
        var start = 0
        return points.indices.map { index in
            let time = points[index].time
            while points[start].time <= time - span {
                start += 1
            }
            return (time, points[start...index].compactMap(\.value))
        }
    }

    /// The least and most of `points` over the `span` up to each one. For the window, which shows
    /// a reading that jumps from sample to sample as the range it covered.
    static func extremes(of points: [Point], over span: TimeInterval) -> [Band] {
        trailing(points, over: span).map { Band(time: $0.time, least: $0.values.min(), most: $0.values.max()) }
    }

    /// The mean of `points` over the `span` up to each one, for the window. The controller's own
    /// inputs are not smoothed: delay noise only ever adds, so a mean would read high, and it
    /// would see the effect of what it does later.
    static func mean(of points: [Point], over span: TimeInterval) -> [Point] {
        trailing(points, over: span).map { time, values in
            Point(time: time, value: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count))
        }
    }
}
