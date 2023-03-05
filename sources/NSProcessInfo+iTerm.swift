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
        let now = mach_absolute_time()

        var result = 0.0
        cpuUsageElapsedTime.mutate { info in
            if info.time > 0 {
                let elapsedTime = NSDate.it_timeInterval(forAbsoluteTime: now - info.time)
                result = (timeUsed - info.usage) / elapsedTime
            }
            return CPUUsageInfo(usage: timeUsed, time: now)
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
