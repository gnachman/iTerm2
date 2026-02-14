//
//  MockTaskNotifierTask.swift
//  ModernTests
//
//  Test-only mock implementation of iTermTask protocol for testing TaskNotifier behavior.
//  Configurable to test both dispatch source and legacy select() paths.
//

import Foundation
@testable import iTerm2SharedARC

@objc class MockTaskNotifierTask: NSObject, iTermTask {

    // MARK: - iTermTask Required Properties

    @objc var fd: Int32 = -1
    @objc var pid: pid_t = 0
    @objc var pidToWaitOn: pid_t = 0
    @objc var hasCoprocess: Bool = false
    @objc var coprocess: Coprocess?
    @objc var wantsRead: Bool = true
    @objc var wantsWrite: Bool = false
    @objc var writeBufferHasRoom: Bool = true
    @objc var hasBrokenPipe: Bool = false
    @objc var sshIntegrationActive: Bool = false

    // MARK: - Configuration for Testing

    /// Set to true to make useDispatchSource return YES.
    /// Default is NO (use select() path).
    var dispatchSourceEnabled: Bool = false

    /// If true, this mock does NOT respond to useDispatchSource selector,
    /// simulating a legacy task that relies on select().
    var simulateLegacyTask: Bool = false

    // MARK: - Call Tracking

    private(set) var processReadCallCount: Int = 0
    private(set) var processWriteCallCount: Int = 0
    private(set) var brokenPipeCallCount: Int = 0
    private(set) var didRegisterCallCount: Int = 0
    private(set) var writeTaskCoprocessCallCount: Int = 0
    private(set) var lastCoprocessData: Data?

    // MARK: - iTermTask Required Methods

    @objc func processRead() {
        processReadCallCount += 1
    }

    @objc func processWrite() {
        processWriteCallCount += 1
    }

    @objc func brokenPipe() {
        brokenPipeCallCount += 1
    }

    @objc func write(_ data: Data!, coprocess isCoprocess: Bool) {
        if isCoprocess {
            writeTaskCoprocessCallCount += 1
            lastCoprocessData = data
        }
    }

    @objc func didRegister() {
        didRegisterCallCount += 1
    }

    // MARK: - iTermTask Optional Methods

    @objc func useDispatchSource() -> Bool {
        return dispatchSourceEnabled
    }

    // MARK: - Override respondsToSelector for Legacy Simulation

    override func responds(to aSelector: Selector!) -> Bool {
        if simulateLegacyTask && aSelector == #selector(useDispatchSource) {
            return false
        }
        return super.responds(to: aSelector)
    }

    // MARK: - Test Helpers

    func reset() {
        processReadCallCount = 0
        processWriteCallCount = 0
        brokenPipeCallCount = 0
        didRegisterCallCount = 0
        writeTaskCoprocessCallCount = 0
        lastCoprocessData = nil
        dispatchSourceEnabled = false
        simulateLegacyTask = false
        wantsRead = true
        wantsWrite = false
        hasCoprocess = false
        hasBrokenPipe = false
    }

    func wait(forProcessReadCalls count: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while processReadCallCount < count && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        return processReadCallCount >= count
    }

    func wait(forCoprocessWriteCalls count: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while writeTaskCoprocessCallCount < count && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        return writeTaskCoprocessCallCount >= count
    }

    func closeFd() {
        if fd >= 0 {
            close(fd)
            fd = -1
        }
    }

    // MARK: - Factory Methods

    /// Creates a pipe task with read FD assigned to the task.
    /// Returns a tuple with the task and the write FD for testing.
    /// Caller is responsible for closing both FDs.
    static func createPipeTask() -> (task: MockTaskNotifierTask, writeFd: Int32)? {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return nil }

        // Set non-blocking on read end
        let flags = fcntl(fds[0], F_GETFL)
        fcntl(fds[0], F_SETFL, flags | O_NONBLOCK)

        let task = MockTaskNotifierTask()
        task.fd = fds[0]  // Read end

        return (task, fds[1])  // Write end
    }
}
