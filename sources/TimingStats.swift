//
//  TimingStats.swift
//  iTerm2
//
//  Created by George Nachman on 5/12/25.
//

import Foundation

@objcMembers
class TimingStats: NSObject {
    private var workingTime: TimeInterval = 0
    private var idleTime: TimeInterval = 0
    private var lastTimestamp: CFAbsoluteTime
    private let name: String
    private var busy: Bool?
    private var timer: Timer?

    init(name: String) {
        self.name = name
        lastTimestamp = CFAbsoluteTimeGetCurrent()
        super.init()
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard let self else {
                    timer.invalidate()
                    return
                }
                NSLog("\(name) is \(round(utilization * 100))%% utilized")
            }
        }
    }

    func recordStart() {
        let now = CFAbsoluteTimeGetCurrent()
        if busy == false {
            let idleDelta = now - lastTimestamp
            idleTime += idleDelta
        }
        lastTimestamp = now
        busy = true
    }

    func recordEnd() {
        let now = CFAbsoluteTimeGetCurrent()
        if busy == true {
            let workDelta = now - lastTimestamp
            workingTime += workDelta
        }
        lastTimestamp = now
        busy = false
    }

    private var timeSinceLastUpdate: TimeInterval {
        return CFAbsoluteTimeGetCurrent() - lastTimestamp
    }

    var totalWorkingTime: TimeInterval {
        return workingTime + (busy == true ? timeSinceLastUpdate : 0)
    }

    var totalIdleTime: TimeInterval {
        return idleTime + (busy == false ? timeSinceLastUpdate : 0)
    }

    var utilization: Double {
        let w = totalWorkingTime
        return w / (w + totalIdleTime)
    }
}
