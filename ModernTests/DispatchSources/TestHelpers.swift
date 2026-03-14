//
//  TestHelpers.swift
//  ModernTests
//
//  Shared test utilities for dispatch source tests.
//  Provides pipe creation, queue synchronization, and condition waiting.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Pipe Utilities

/// Creates a non-blocking pipe for testing I/O operations.
/// - Returns: Tuple with read and write file descriptors, or nil on failure
func createTestPipe() -> (readFd: Int32, writeFd: Int32)? {
    var fds: [Int32] = [0, 0]
    guard pipe(&fds) == 0 else { return nil }

    // Set non-blocking on both ends
    let readFlags = fcntl(fds[0], F_GETFL)
    let writeFlags = fcntl(fds[1], F_GETFL)
    _ = fcntl(fds[0], F_SETFL, readFlags | O_NONBLOCK)
    _ = fcntl(fds[1], F_SETFL, writeFlags | O_NONBLOCK)

    return (fds[0], fds[1])
}

/// Closes both ends of a test pipe.
func closeTestPipe(_ fds: (readFd: Int32, writeFd: Int32)) {
    close(fds.readFd)
    close(fds.writeFd)
}

/// Writes data to a file descriptor.
/// - Parameters:
///   - fd: File descriptor to write to
///   - data: String data to write
/// - Returns: Number of bytes written, or -1 on error
@discardableResult
func writeToFd(_ fd: Int32, data: String) -> Int {
    return data.withCString { ptr in
        Darwin.write(fd, ptr, strlen(ptr))
    }
}

// MARK: - Queue Synchronization

/// Waits for main queue to process all pending work.
func waitForMainQueue() {
    if Thread.isMainThread {
        // Already on main, run a spin through the run loop
        RunLoop.current.run(until: Date())
    } else {
        DispatchQueue.main.sync {}
    }
}

// MARK: - Mock Backpressure Source

/// Minimal mock for PTYTask.tokenExecutor that exposes a settable backpressureLevel.
/// Used to test that wantsRead only checks backpressure in per-PTY mode.
final class MockBackpressureSource: NSObject {
    @objc var backpressureLevel: BackpressureLevel = .none
}

// MARK: - XCTestCase Extensions

extension XCTestCase {

    /// Waits for a condition to become true, polling at intervals.
    /// - Parameters:
    ///   - condition: Closure that returns true when condition is met
    ///   - timeout: Maximum time to wait
    ///   - pollInterval: Time between checks
    /// - Returns: true if condition became true within timeout
    func waitForCondition(_ condition: @escaping () -> Bool,
                          timeout: TimeInterval,
                          pollInterval: TimeInterval = 0.01) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return condition()
    }
}
