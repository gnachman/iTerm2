//
//  NSProcessInfo+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/24/21.
//

import Darwin
import Foundation

extension ProcessInfo {
    static let hasARMProcessor: Bool = {
        (ProcessInfo.it_machine ?? "").contains("arm")
    }()

    static var it_machine: String? {
        var sysinfo = utsname()
        guard uname(&sysinfo) == EXIT_SUCCESS else {
            return nil
        }
        let data = Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN))
        guard let machine = String(bytes: data, encoding: .ascii) else {
            return nil
        }
        return machine.trimmingCharacters(in: .controlCharacters)
    }

    @objc static var it_hasARMProcessor: Bool {
        return hasARMProcessor
    }

    private struct CPUUsageInfo {
        var usage = 0.0
        var time = UInt64(0)  // mach_absolute_time
        var lastResult: Double?
    }

    private static var cpuUsageElapsedTime = MutableAtomicObject(CPUUsageInfo())

    private static var cumulativeOwnTotalCPUUsage: Double? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else {
            DLog("getrusage failed with errno \(errno)")
            return nil
        }
        return usage.totalCPUUsage
    }

    // The first call always returns 0. The second and on give the average usage since the preceding call.
    @objc
    static func ownCPUUsage() -> Double {
        guard let timeUsed = cumulativeOwnTotalCPUUsage else {
            return 0
        }

        var result = 0.0
        cpuUsageElapsedTime.mutate { info in
            // Measure the time inside the mutex because concurrent calls could lead to time
            // appearing to move backwards otherwise.
            let now = mach_absolute_time()
            if info.time > 0 {
                // Avoid recomputing too often because if we haven't sampled enough we'll get crazy
                // results.
                let nowSeconds = NSDate.it_timeInterval(forAbsoluteTime: now)
                let lastSeconds = NSDate.it_timeInterval(forAbsoluteTime: info.time)
                let rateLimit = 0.01
                if nowSeconds > lastSeconds + rateLimit {
                    let elapsedTime = nowSeconds - lastSeconds
                    result = (timeUsed - info.usage) / elapsedTime
                } else {
                    // Asking too often
                    if let lastResult = info.lastResult {
                        result = lastResult
                    }
                    return info
                }
            }
            return CPUUsageInfo(usage: timeUsed, time: now, lastResult: result)
        }
        return result
    }

}

extension timeval {
    var timeInterval: TimeInterval {
        return Double(tv_sec) + Double(tv_usec) / 1000000.0
    }
}

extension rusage {
    var totalCPUUsage: TimeInterval {
        ru_utime.timeInterval + ru_stime.timeInterval
    }
}
