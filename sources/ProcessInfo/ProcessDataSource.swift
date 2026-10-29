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

    // The arguments exactly as the process received them, each one whole and unescaped.
    // commandLineArguments can't promise that: it may shell-escape them for display, and a source
    // that rebuilds argv by splitting a joined command line, like ps output, can't recover the
    // boundaries at all. Such a source leaves this unimplemented.
    @objc(rawCommandLineArgumentsForProcess:)
    optional func rawCommandLineArguments(forProcess pid: pid_t) -> [String]?

    // The process's process group, or 0 when unknown.
    @objc(processGroupIDForProcess:)
    optional func processGroupID(forProcess pid: pid_t) -> pid_t

    @objc(startTimeForProcess:)
    func startTime(forProcess pid: pid_t) -> Date?

    // If the given file descriptor of the process is open on a terminal device
    // (a /dev/tty* character device), returns that device's rdev. Returns 0 if the
    // fd is not a tty (e.g. a pipe, regular file, or a non-terminal character
    // device like /dev/null) or cannot be read. Remote data sources that can't
    // introspect file descriptors return 0.
    @objc(ttyRdevForFileDescriptor:ofProcess:)
    func ttyRdev(forFileDescriptor fd: Int32, ofProcess pid: pid_t) -> dev_t
}
