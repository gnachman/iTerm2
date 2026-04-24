//
//  SSHCommandRunning.swift
//  iTerm2
//
//  Created by George Nachman on 7/1/25.
//

@MainActor
protocol SSHCommandRunning: AnyObject {
    func runRemoteCommand(_ commandLine: String,
                          completion: @escaping  (Data, Int32) -> ())
    func registerProcess(_ pid: pid_t)
    func deregisterProcess(_ pid: pid_t)
    func poll(_ completion: @escaping (Data) -> ())
}

