//
//  FrameDelayBaseline.swift
//  iTerm2SharedARC
//
//  What a flow controller measures queueing delay from: the least one-way delay a frame has
//  had recently, allowing for its size.
//
//  A frame is seen once its last byte is in, so its reading includes the time to push its bytes
//  across the link: 0.2 s for 4 KB at 20 KB/s, nothing to speak of on a fast link. Small frames,
//  such as echo, would otherwise set a baseline that large ones never reach, and every large
//  frame would look queued. That time cannot come from the delivery rate: with a small window the
//  rate is what the window allows, not what the link carries, and taking out too much makes large
//  frames read below the empty path, so that everything else looks queued and the window shrinks
//  for good.
//
//  Instead the link's cost per byte is read off the frames themselves. Frames fall into buckets
//  by size, doubling from 128 bytes, and each keeps its least delay over the window L with the
//  size of the frame that had it. On an empty path a frame's delay is a constant plus its size
//  times the cost per byte, so the least delays lie on or above that line, and the lower edge of
//  the buckets' points traces it. A frame's correction is that edge at its size, measured from
//  the smallest size on it, so every bucket on the edge reads the same at its least: the
//  baseline. Readings are kept raw and corrected only when compared, so the baseline and the
//  recent readings are always corrected alike.
//
//  Reading the baseline changes nothing: each bucket keeps two halves of the window, aligned to
//  fixed slots of time.
//

import Foundation

struct FrameDelayBaseline {
    struct Parameters {
        /// Each bucket holds frames from this size up to twice it; the first holds smaller ones too
        /// and the last larger ones.
        var bucketSizes = [0, 128, 256, 512, 1024, 2048, 4096]
        /// A bucket's least delay counts toward the edge once it has this many readings in the
        /// window. A bucket with few may not have caught an empty path, but that leaves its least
        /// too high, never too low, and the lower edge passes under such points. Requiring more
        /// would drop the rare sizes, such as echo during a flood, whenever half the window ages
        /// out, and with them the correction.
        var minimumReadings = 1
        /// The steepest cost per byte believed, in seconds: a link of 1 KB/s.
        var maximumCostPerByte = 1.0 / 1024
    }

    /// What one bucket knows, as of some time.
    struct Bucket: Equatable {
        /// The smallest frame it holds.
        var lowerBound: Int
        /// The largest frame it holds; nil for the last.
        var upperBound: Int?
        var readings: Int
        /// The least raw one-way delay, and the size of the frame that had it.
        var leastDelay: TimeInterval?
        var leastBytes: Int?
        /// Whether its least delay is a point on the lower edge.
        var onEdge = false
    }

    /// The baseline as of some time.
    struct Evaluation {
        var buckets: [Bucket]
        /// Points (bytes, delay) along the lower edge, by size. Empty when frames do not vary
        /// enough in size for their cost to matter, and nothing is corrected.
        var edge: [(bytes: Double, delay: TimeInterval)]
        /// The least corrected delay: what an empty path reads.
        var base: TimeInterval?
        private let maximumCostPerByte: Double

        init(buckets: [Bucket], edge: [(bytes: Double, delay: TimeInterval)], base: TimeInterval?,
             maximumCostPerByte: Double) {
            self.buckets = buckets
            self.edge = edge
            self.base = base
            self.maximumCostPerByte = maximumCostPerByte
        }

        /// How much of a frame's delay its size accounts for, beyond the smallest frame on the
        /// edge. Never steeper than the maximum cost, nor falling with size.
        func correction(forBytes bytes: Int) -> TimeInterval {
            guard edge.count >= 2 else {
                return 0
            }
            let x = Double(bytes)
            func slope(_ i: Int) -> Double {
                let dx = edge[i + 1].bytes - edge[i].bytes
                return dx > 0 ? min(max(0, (edge[i + 1].delay - edge[i].delay) / dx), maximumCostPerByte) : 0
            }
            if x <= edge[0].bytes {
                return (x - edge[0].bytes) * slope(0)
            }
            var cost = 0.0
            for i in 0..<(edge.count - 1) {
                let end = edge[i + 1].bytes
                if x <= end || i == edge.count - 2 {
                    return cost + (x - edge[i].bytes) * slope(i)
                }
                cost += (end - edge[i].bytes) * slope(i)
            }
            return cost
        }

        /// The link's cost per KB, for display: between frames of 1 and 4 KB, the sizes a flood is
        /// sent in. Below the smallest size seen the edge is flat, so the cost from no bytes at
        /// all would read low.
        var costPerKilobyte: TimeInterval {
            (correction(forBytes: 4096) - correction(forBytes: 1024)) / 3
        }
    }

    private struct Half {
        var slot: Int
        var start: TimeInterval
        var readings = 0
        var least: (delay: TimeInterval, bytes: Int)?
    }

    let parameters: Parameters
    /// Per bucket, the halves of the window, newest last.
    private var halves: [[Half]]

    init(parameters: Parameters = Parameters()) {
        self.parameters = parameters
        halves = Array(repeating: [], count: parameters.bucketSizes.count)
    }

    mutating func reset() {
        halves = Array(repeating: [], count: parameters.bucketSizes.count)
    }

    private func bucketIndex(forBytes bytes: Int) -> Int {
        parameters.bucketSizes.lastIndex { $0 <= bytes } ?? 0
    }

    /// A frame of `bytes` arrived with this raw one-way delay.
    mutating func add(delay: TimeInterval, bytes: Int, now: TimeInterval, window: TimeInterval) {
        let index = bucketIndex(forBytes: bytes)
        let half = max(window / 2, 0.001)
        let slot = Int((now / half).rounded(.down))
        var list = halves[index].filter { now - $0.start < window + half }
        if list.last?.slot != slot {
            list.append(Half(slot: slot, start: Double(slot) * half))
        }
        list = Array(list.suffix(2))
        list[list.count - 1].readings += 1
        if let least = list[list.count - 1].least, least.delay <= delay {
            // Keep the earlier one.
        } else {
            list[list.count - 1].least = (delay, bytes)
        }
        halves[index] = list
    }

    /// The baseline over the last `window` as of `now`. `corrects` false takes no account of size,
    /// for readings that hold no transmission time.
    func evaluate(now: TimeInterval, window: TimeInterval, corrects: Bool = true) -> Evaluation {
        var buckets = [Bucket]()
        for (index, lowerBound) in parameters.bucketSizes.enumerated() {
            let upperBound = index + 1 < parameters.bucketSizes.count ? parameters.bucketSizes[index + 1] - 1 : nil
            let live = halves[index].filter { now - $0.start < window }
            var bucket = Bucket(lowerBound: lowerBound, upperBound: upperBound,
                                readings: live.reduce(0) { $0 + $1.readings })
            for half in live {
                if let least = half.least, bucket.leastDelay.map({ least.delay < $0 }) ?? true {
                    bucket.leastDelay = least.delay
                    bucket.leastBytes = least.bytes
                }
            }
            buckets.append(bucket)
        }
        var edge = [(bytes: Double, delay: TimeInterval)]()
        var edgeBuckets = [Int]()
        if corrects {
            let candidates = buckets.indices.filter {
                buckets[$0].readings >= parameters.minimumReadings && buckets[$0].leastDelay != nil
            }
            // The lower convex hull of the candidates' points, left to right.
            for index in candidates {
                let point = (bytes: Double(buckets[index].leastBytes!), delay: buckets[index].leastDelay!)
                while edge.count >= 2 {
                    let a = edge[edge.count - 2]
                    let b = edge[edge.count - 1]
                    let cross = (b.bytes - a.bytes) * (point.delay - a.delay) - (b.delay - a.delay) * (point.bytes - a.bytes)
                    if cross > 0 {
                        break
                    }
                    edge.removeLast()
                    edgeBuckets.removeLast()
                }
                edge.append(point)
                edgeBuckets.append(index)
            }
            // Neighboring points must be at least a doubling apart. Frames on either side of a
            // bucket boundary can differ by a byte, and a few ms of jitter between them would
            // make a slope as steep as is believed, which frames past the last point would be
            // corrected along. Of two points too close, the lower stays.
            var spaced = [(point: (bytes: Double, delay: TimeInterval), bucket: Int)]()
            for (point, bucket) in zip(edge, edgeBuckets) {
                while let last = spaced.last, point.bytes < 2 * last.point.bytes {
                    if point.delay < last.point.delay {
                        spaced.removeLast()
                    } else {
                        break
                    }
                }
                if let last = spaced.last, point.bytes < 2 * last.point.bytes {
                    continue
                }
                spaced.append((point, bucket))
            }
            edge = spaced.map(\.point)
            edgeBuckets = spaced.map(\.bucket)
            // Sizes that vary this little make the same correction for every frame, which changes
            // no comparison, and a slope between them would be mostly noise.
            if let first = edge.first, let last = edge.last, last.bytes - first.bytes < last.bytes / 2 {
                edge = []
                edgeBuckets = []
            }
        }
        for index in edgeBuckets {
            buckets[index].onEdge = true
        }
        var evaluation = Evaluation(buckets: buckets, edge: edge, base: nil,
                                    maximumCostPerByte: parameters.maximumCostPerByte)
        // With an edge, the base comes from the buckets it was drawn from, which all read the same
        // at their least; without one, from every frame.
        let counted = edge.isEmpty ? Array(buckets.indices) : edgeBuckets
        evaluation.base = counted.compactMap { index -> TimeInterval? in
            guard let delay = buckets[index].leastDelay, let bytes = buckets[index].leastBytes else {
                return nil
            }
            return delay - evaluation.correction(forBytes: bytes)
        }.min()
        return evaluation
    }
}
