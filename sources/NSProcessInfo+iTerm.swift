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

    static func ownCPUUsage() -> Double {
        var usage = rusage()
        if getrusage(RUSAGE_SELF, &usage) == 0 {
            let userTime = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1000000.0
            let sysTime = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1000000.0
            let timeUsed = userTime + sysTime

            var result = 0.0
            cpuUsageElapsedTime.mutate { info in
                defer {
                    info.usage = totalTime
                    info.time = mach_absolute_time()
                }
                if info.time == 0 {
                    return
                }
                let elapsedTime = NSDate.it_timeInterval(forAbsoluteTime: mach_absolute_time()) - NSDate.it_timeInterval(forAbsoluteTime: info.time)
                result = elapsedTime / (timeUsed - info.usage)
            }
            return result
        } else {
            DLog("Error getting resource usage: \(errno)")
            return 0.0
        }

        /*
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        // Get a list of all threads in the current process
        do {
            let kr = task_threads(mach_task_self_, &threadList, &threadCount)
            guard kr == KERN_SUCCESS else {
                DLog("Error getting thread list: \(kr)")
                return 0
            }
        }

        struct ThreadInfo {
            var idle: Bool
            var usage: Double
        }
        var infos = [ThreadInfo]()
        // Call thread_info() on each thread
        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)

            let kr = withUnsafeMutablePointer(to: &threadInfo) { ptr in
                let threadInfo = ptr.withMemoryRebound(to: integer_t.self, capacity: 1) { $0 }
                return thread_info(threadList![i],
                                   thread_flavor_t(THREAD_BASIC_INFO),
                                   threadInfo,
                                   &threadInfoCount)
            }
            guard kr == KERN_SUCCESS else {
                NSLog("Error getting thread info: \(kr)")
                continue
            }
            infos.append(ThreadInfo(idle: (threadInfo.flags & TH_FLAGS_IDLE) != 0,
                                    usage: Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE)))
        }

        // Clean up the thread list
        let kr = vm_deallocate(mach_task_self_,
                               vm_address_t(bitPattern: threadList),
                               vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_act_t>.size))
        if kr != KERN_SUCCESS {
            DLog("Error deallocating thread list: \(kr)")
        }

        return infos.reduce(0) { partialResult, info in
            if info.idle {
                return 0
            }
            return partialResult + info.usage
        }
*/

        /*
        var totalUsageOfCPU: Double = 0.0
        var threads = [thread_act_t]()
        return withUnsafeMutablePointer(to: &threads) { threadsList in
            var threadsCount = mach_msg_type_number_t(0)
            var temp = threadsList
            let threadsResult = withUnsafeMutablePointer(to: &temp) {
                return $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
                    task_threads(mach_task_self_, $0, &threadsCount)
                }
            }

            if threadsResult == KERN_SUCCESS {
                for index in 0..<threadsCount {
                    var threadInfo = thread_basic_info()
                    var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                    let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                            thread_info(threadsList[Int(index)], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                        }
                    }

                    guard infoResult == KERN_SUCCESS else {
                        break
                    }

                    let threadBasicInfo = threadInfo as thread_basic_info
                    if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
                        totalUsageOfCPU = (totalUsageOfCPU + (Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0))
                    }
                }
            }

            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadsList)), vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
            return totalUsageOfCPU
        }
         */

    }

}
