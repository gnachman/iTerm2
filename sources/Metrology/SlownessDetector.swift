//
//  SlownessDetector.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/21/24.
//

import Foundation

@objc(iTermSlownessDetector)
class SlownessDetector: NSObject {
    private var state = [String: TimeInterval]()
    private var resetTime: TimeInterval
    private var stack = [TimeInterval]()
    @objc var enabled = false

    override init() {
        resetTime = Date.timeSinceBoot
    }

    @objc(measureEvent:block:)
    func measure(event: String, closure: () -> ()) {
        if (!enabled) {
            closure()
            return
        }
        stack.append(0)
        let durationWithoutDoubleCounting = NSDate.duration(of: closure)
        let duration = durationWithoutDoubleCounting - stack.last!
        stack.removeLast()
        for i in 0..<stack.count {
            stack[i] += duration
        }
        increase(event: event, duration: duration)
    }

    private func increase(event: String, duration: TimeInterval) {
        state[event] = (state[event] ?? 0.0) + duration
    }

    @objc var timeDistribution: [String: TimeInterval] {
        state
    }

    @objc func reset() {
        state = [:]
        resetTime = Date.timeSinceBoot
    }

    @objc var timeSinceReset: TimeInterval {
        Date.timeSinceBoot - resetTime
    }
}

fileprivate var timebase: Double = {
    var temp = mach_timebase_info_data_t()
    mach_timebase_info(&temp)
    let nanos_per_sec = 1_000_000_000.0
    return Double(temp.numer) / (Double(temp.denom) * nanos_per_sec)
}()

extension Date {
    static var timeSinceBoot: TimeInterval {
        TimeInterval(mach_absolute_time()) * timebase
    }
}
