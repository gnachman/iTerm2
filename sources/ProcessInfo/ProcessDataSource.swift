//
//  ProcessDataSource.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/19/22.
//

import Foundation

@objc(iTermProcessDataSource)
protocol ProcessDataSource: AnyObject {
    @objc(nameOfProcessWithPid:isForeground:)
    func nameOfProcess(withPid thePid: pid_t,
                       isForeground: UnsafeMutablePointer<ObjCBool>) -> String?

    @objc(commandLineArgumentsForProcess:execName:)
    func commandLineArguments(forProcess pid: pid_t,
                              execName: AutoreleasingUnsafeMutablePointer<NSString>?) -> [String]?

    @objc(startTimeForProcess:)
    func startTime(forProcess pid: pid_t) -> Date?
}
