//
//  ClockWatcher.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/20/23.
//

import Foundation

/// Measures time excluding time while the machine was sleeping or the entire process was hung. Notably, it continues to count while
/// the main queue is busy.
@objc(iTermClockWatcher)
class ClockWatcher: NSObject {
    private static let queue = DispatchQueue(label: "com.iterm2.clock-watcher")
    private var ticks = MutableAtomicObject(0)
    private var _maxTime = MutableAtomicObject(TimeInterval(0))
    @objc var maxTime: TimeInterval {
        get { _maxTime.value }
        set { _maxTime.set(newValue) }
    }

    @objc
    init(maxTime: TimeInterval) {
        _maxTime.set(maxTime)

        super.init()

        schedule()
    }

    @objc
    var reachedMaxTime: Bool {
        return elapsedTime >= maxTime
    }

    @objc
    var elapsedTime: TimeInterval {
        TimeInterval(ticks.value)
    }

    private func schedule() {
        Self.queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.tick()
        }
    }

    @objc
    private func tick() {
        ticks.mutate { count in
            count + 1
        }
        schedule()
    }
}
