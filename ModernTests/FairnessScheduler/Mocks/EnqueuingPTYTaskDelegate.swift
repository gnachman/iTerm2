//
//  EnqueuingPTYTaskDelegate.swift
//  ModernTests
//
//  Specialized PTYTaskDelegate for testing the read pipeline that enqueues
//  read data to a TokenExecutor instead of just tracking calls.
//  This enables end-to-end pipeline testing from read → parse → queue.
//

import Foundation
@testable import iTerm2SharedARC

/// A PTYTaskDelegate that actually enqueues read data to a TokenExecutor.
/// Used for testing the full read handler pipeline.
final class EnqueuingPTYTaskDelegate: NSObject, PTYTaskDelegate {

    // MARK: - Configuration

    /// The TokenExecutor to enqueue tokens to.
    var tokenExecutor: TokenExecutor?

    /// Callback invoked when data is read (before enqueueing).
    var onThreadedRead: ((Data) -> Void)?

    /// Callback invoked after tokens are enqueued.
    var onEnqueued: (() -> Void)?

    // MARK: - Call Tracking

    private let lock = NSLock()
    private var _readCount = 0
    private var _totalBytesRead = 0
    private var _enqueueCount = 0

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _readCount
    }

    var totalBytesRead: Int {
        lock.lock()
        defer { lock.unlock() }
        return _totalBytesRead
    }

    var enqueueCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _enqueueCount
    }

    // MARK: - Initialization

    override init() {
        super.init()
    }

    /// Convenience initializer for tests that need an executor set immediately.
    convenience init(executor: TokenExecutor) {
        self.init()
        self.tokenExecutor = executor
    }

    // MARK: - PTYTaskDelegate

    func threadedReadTask(_ buffer: UnsafeMutablePointer<CChar>, length: Int32) {
        lock.lock()
        _readCount += 1
        _totalBytesRead += Int(length)
        let data = Data(bytes: buffer, count: Int(length))
        lock.unlock()

        onThreadedRead?(data)

        // Enqueue tokens to the executor (mimics PTYSession behavior)
        if let executor = tokenExecutor {
            // Add enough tokens to trigger backpressure change for verification
            executor.addMultipleTokenArrays(count: 100, tokensPerArray: 5)

            lock.lock()
            _enqueueCount += 1
            lock.unlock()

            onEnqueued?()
        }
    }

    func threadedTaskBrokenPipe() {
        // Not used in pipeline tests
    }

    func brokenPipe() {
        // Not used in pipeline tests
    }

    func tmuxClientWrite(_ data: Data) {
        // Not used in pipeline tests
    }

    func taskDiedImmediately() {
        // Not used in pipeline tests
    }

    func taskDiedWithError(_ error: String!) {
        // Not used in pipeline tests
    }

    func taskDidChangeTTY(_ task: PTYTask) {
        // Not used in pipeline tests
    }

    func taskDidRegister(_ task: PTYTask) {
        // Not used in pipeline tests
    }

    func taskDidChangePaused(_ task: PTYTask, paused: Bool) {
        // Not used in pipeline tests
    }

    func taskMuteCoprocessDidChange(_ task: PTYTask, hasMuteCoprocess: Bool) {
        // Not used in pipeline tests
    }

    func taskDidResize(to gridSize: VT100GridSize, pixelSize: NSSize) {
        // Not used in pipeline tests
    }

    func taskDidReadFromCoprocessWhileSSHIntegration(inUse data: Data) {
        // Not used in pipeline tests
    }

    // MARK: - Test Helpers

    func reset() {
        lock.lock()
        _readCount = 0
        _totalBytesRead = 0
        _enqueueCount = 0
        onThreadedRead = nil
        onEnqueued = nil
        lock.unlock()
    }
}
