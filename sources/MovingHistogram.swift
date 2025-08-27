//
//  MovingHistogram.swift
//  iTerm2
//
//  Created by George Nachman on 8/26/25.
//

@objc(iTermMovingHistogram)
class MovingHistogram: NSObject {
    let bucketSize: Int
    let numberOfBuckets: Int
    private var histograms = [iTermHistogram]()

    @objc
    init(bucketSize: Int,
         numberOfBuckets: Int) {
        self.bucketSize = bucketSize
        self.numberOfBuckets = numberOfBuckets
    }
}

@objc
extension MovingHistogram {
    @objc(addValue:)
    func add(value: Double) {
        let histogram = currentHistogram()
        histogram.addValue(value)
    }

    @objc
    var histogram: iTermHistogram {
        let combined = iTermHistogram()
        for bucket in histograms {
            combined.merge(from: bucket)
        }
        return combined;
    }
}

private extension MovingHistogram {
    private func currentHistogram() -> iTermHistogram {
        if let last = histograms.last, last.count < bucketSize {
            return last
        }
        // Must allocate a new one
        let histogram = iTermHistogram()
        histograms.append(histogram)
        while histograms.count > numberOfBuckets {
            histograms.removeFirst()
        }
        return histogram
    }
}
