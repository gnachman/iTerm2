//
//  print.swift
//  iTerm2
//
//  Created by George Nachman on 6/25/25.
//

import Foundation

fileprivate let mutex = Mutex()

// This is just like print() but it doesn't truncate its output. I can't imagine what the team that maintains print was thinking when they decided that was a good idea. I am so close to just walking into the ocean and never turning back
func fuckingPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    let text = items
        .map { String(describing: $0) }
        .joined(separator: separator)
        + terminator

    mutex.sync {
        FileHandle.standardOutput.write(text.lossyData)
    }
}

import Foundation
import Darwin

func NSFuckingLog(_ format: String, _ args: CVarArg...) {
    var tv = timeval()
    gettimeofday(&tv, nil)

    var seconds = tv.tv_sec
    let microseconds = tv.tv_usec

    var tm = tm()
    localtime_r(&seconds, &tm)

    let year = tm.tm_year + 1900
    let month = tm.tm_mon + 1
    let day = tm.tm_mday
    let hour = tm.tm_hour
    let minute = tm.tm_min
    let second = tm.tm_sec

    let tzOffset = TimeZone.current.secondsFromGMT()
    let sign = tzOffset >= 0 ? "+" : "-"
    let tzHour = abs(tzOffset) / 3600
    let tzMinute = (abs(tzOffset) % 3600) / 60
    let timezone = String(format: "%@%02d%02d", sign, tzHour, tzMinute)

    let timestamp = String(
        format: "%04d-%02d-%02d %02d:%02d:%02d.%06d%@",
        year,
        month,
        day,
        hour,
        minute,
        second,
        microseconds,
        timezone
    )

    let message = String(format: format, arguments: args)
    let process = ProcessInfo.processInfo.processName
    let pid = getpid()
    let tid = pthread_mach_thread_np(pthread_self())

    let output = "\(timestamp) \(process)[\(pid):\(tid)] \(message)\n"

    let data = output.lossyData
    mutex.sync {
        FileHandle.standardError.write(data)
    }
}
