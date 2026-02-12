//
//  MockPTYTaskDelegate.swift
//  ModernTests
//
//  Mock implementation of PTYTaskDelegate for testing dispatch source integration.
//  Provides call tracking and callbacks for verifying read handler pipeline.
//

import Foundation
@testable import iTerm2SharedARC

/// Mock delegate for testing the read handler pipeline in PTYTask.
final class MockPTYTaskDelegate: NSObject, PTYTaskDelegate {

    // MARK: - Configuration

    /// Callback invoked when threadedReadTask is called.
    /// Use this to fulfill expectations or capture data in tests.
    var onThreadedRead: ((Data) -> Void)?

    // MARK: - Call Tracking

    private let lock = NSLock()
    private var _readCallCount = 0
    private var _lastReadData: Data?
    private var _readDataChunks: [Data] = []
    private var _brokenPipeCount = 0
    private var _threadedBrokenPipeCount = 0

    var readCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _readCallCount
    }

    var lastReadData: Data? {
        lock.lock()
        defer { lock.unlock() }
        return _lastReadData
    }

    /// All data chunks received via threadedReadTask, in order.
    var readDataChunks: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return _readDataChunks
    }

    var brokenPipeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _brokenPipeCount
    }

    var threadedBrokenPipeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _threadedBrokenPipeCount
    }

    // MARK: - Convenience (backward compat with regression tests)

    var threadedBrokenPipeCalled: Bool {
        return threadedBrokenPipeCount > 0
    }

    var readData: [Data] {
        return readDataChunks
    }

    // MARK: - PTYTaskDelegate

    func threadedReadTask(_ buffer: UnsafeMutablePointer<CChar>, length: Int32) {
        lock.lock()
        _readCallCount += 1
        let data = Data(bytes: buffer, count: Int(length))
        _lastReadData = data
        _readDataChunks.append(data)
        lock.unlock()

        onThreadedRead?(data)
    }

    func threadedTaskBrokenPipe() {
        lock.lock()
        _threadedBrokenPipeCount += 1
        lock.unlock()
    }

    func brokenPipe() {
        lock.lock()
        _brokenPipeCount += 1
        lock.unlock()
    }

    func tmuxClientWrite(_ data: Data) {
        // Not used in these tests
    }

    func taskDiedImmediately() {
        // Not used in these tests
    }

    func taskDiedWithError(_ error: String!) {
        // Not used in these tests
    }

    func taskDidChangeTTY(_ task: PTYTask) {
        // Not used in these tests
    }

    func taskDidRegister(_ task: PTYTask) {
        // Not used in these tests
    }

    func taskDidChangePaused(_ task: PTYTask, paused: Bool) {
        // Not used in these tests
    }

    func taskMuteCoprocessDidChange(_ task: PTYTask, hasMuteCoprocess: Bool) {
        // Not used in these tests
    }

    func taskDidResize(to gridSize: VT100GridSize, pixelSize: NSSize) {
        // Not used in these tests
    }

    func taskDidReadFromCoprocessWhileSSHIntegration(inUse data: Data) {
        // Not used in these tests
    }

    // MARK: - Test Helpers

    func reset() {
        lock.lock()
        _readCallCount = 0
        _lastReadData = nil
        _readDataChunks = []
        _brokenPipeCount = 0
        _threadedBrokenPipeCount = 0
        onThreadedRead = nil
        lock.unlock()
    }

    /// Thread-safe accessor for read count
    func getReadCount() -> Int {
        return readCallCount
    }

    /// Thread-safe accessor for last read data
    func getLastReadData() -> Data? {
        return lastReadData
    }
}
