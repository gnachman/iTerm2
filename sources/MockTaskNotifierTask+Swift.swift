//
//  MockTaskNotifierTask+Swift.swift
//  iTerm2SharedARC
//
//  Swift extensions for MockTaskNotifierTask to provide Swift-friendly API.
//

import Foundation

extension MockTaskNotifierTask {

    /// Creates a pipe task with read FD assigned to the task.
    /// Returns a tuple with the task and the write FD for testing.
    /// Caller is responsible for closing both FDs.
    static func createPipeTask() -> (task: MockTaskNotifierTask, writeFd: Int32)? {
        var writeFd: Int32 = 0
        guard let task = createPipeTask(withWriteFd: &writeFd) else {
            return nil
        }
        return (task, writeFd)
    }
}
