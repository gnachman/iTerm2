//
//  CPUUsageGovernor.swift
//  iTerm2GitAgent
//
//  Created by George Nachman on 7/31/21.
//

import Foundation
import MachO

@objc(iTermCPUUsageGovernor)
public class CPUUsageGovernor: NSObject {
    private let samplingInterval: TimeInterval
    private let maximumUtilization: Double
    private let pid: pid_t
    private let queue: DispatchQueue
    private let task: mach_port_t

    init?(samplingInterval: TimeInterval,
          maximumUtilization: Double,
          pid: pid_t) {
        self.samplingInterval = samplingInterval
        self.maximumUtilization = maximumUtilization
        self.pid = pid
        if task_for_pid(mach_task_self(), pid, &task) != KERN_SUCCESS {
            NSLog("Failed to get task for \(pid): \(strerror(errno))")
            return nil
        }
        queue = DispatchQueue(label: "com.iterm2.cpu-usage-goveroer")
        queue.async {
            self.mainLoop()
        }
    }

    private func mainLoop() {
        while shouldContinue {
            NSLog("governor: sleep for \(samplingInterval) seconds")
            Thread.sleep(forTimeInterval: samplingInterval)

            let utilization = self.utilization
            NSLog("governor: utilization is \(utilization)%")

            let sleepTime = samplingInterval * (utilization / maximumUtilization - 1)
            if sleepTime > 0 {
                NSLog("governor: sleep for \(sleepTime) seconds")
                suspend()
                Thread.sleep(sleepTime)
                resume()
            }
        }
    }

    private var shouldContinue: Bool {
        return kill(pid, 0) == 0
    }

    private var utilization: Double {

    }
}
