//
//  TestUtilities.swift
//  ModernTests
//
//  Shared test utilities for fairness scheduler tests.
//  Provides helper functions for creating test fixtures and synchronization.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Token Vector Creation

/// Creates a CVector containing test tokens.
/// - Parameter count: Number of tokens to create (minimum 1)
/// - Returns: A CVector containing VT100_UNKNOWNCHAR tokens
func createTestTokenVector(count: Int) -> CVector {
    var vector = CVector()
    CVectorCreate(&vector, Int32(max(count, 1)))
    for _ in 0..<max(count, 1) {
        let token = VT100Token()
        token.type = VT100_UNKNOWNCHAR
        CVectorAppendVT100Token(&vector, token)
    }
    return vector
}

/// Creates a CVector with a specified total byte length for testing.
/// - Parameters:
///   - tokenCount: Number of tokens
///   - bytesPerToken: Approximate bytes per token for length tracking
/// - Returns: A tuple of (vector, totalLength)
func createTestTokenVectorWithLength(tokenCount: Int, bytesPerToken: Int = 10) -> (vector: CVector, length: Int) {
    let vector = createTestTokenVector(count: tokenCount)
    let totalLength = tokenCount * bytesPerToken
    return (vector, totalLength)
}

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

/// Waits for mutationQueue to process all pending work.
/// Use this to synchronize tests with async scheduler operations.
func waitForMutationQueue() {
    iTermGCD.mutationQueue().sync {}
}

/// Waits for mutationQueue with a timeout.
/// - Parameter timeout: Maximum time to wait
/// - Returns: true if completed within timeout, false if timed out
func waitForMutationQueue(timeout: TimeInterval) -> Bool {
    let semaphore = DispatchSemaphore(value: 0)
    iTermGCD.mutationQueue().async {
        semaphore.signal()
    }
    return semaphore.wait(timeout: .now() + timeout) == .success
}

/// Waits for main queue to process all pending work.
func waitForMainQueue() {
    if Thread.isMainThread {
        // Already on main, run a spin through the run loop
        RunLoop.current.run(until: Date())
    } else {
        DispatchQueue.main.sync {}
    }
}

// MARK: - XCTestCase Extensions

extension XCTestCase {

    /// Creates an expectation that fulfills when the mutation queue processes a block.
    func mutationQueueExpectation(description: String = "Mutation queue processed") -> XCTestExpectation {
        let expectation = XCTestExpectation(description: description)
        iTermGCD.mutationQueue().async {
            expectation.fulfill()
        }
        return expectation
    }

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

// MARK: - FairnessScheduler Test Helpers

#if ITERM_DEBUG
extension FairnessScheduler {

    /// Test helper: Wait for all scheduled executions to complete.
    /// Polls busySessionCount until empty or timeout.
    func waitForQuiescence(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if testBusySessionCount == 0 {
                return true
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return testBusySessionCount == 0
    }
}
#endif

// MARK: - TokenExecutor Test Helpers

extension TokenExecutor {

    /// Test helper: Add multiple token groups for testing backpressure.
    /// - Parameters:
    ///   - count: Number of token arrays to add
    ///   - tokensPerArray: Tokens in each array
    func addMultipleTokenArrays(count: Int, tokensPerArray: Int = 5) {
        for _ in 0..<count {
            var vector = CVector()
            CVectorCreate(&vector, Int32(tokensPerArray))
            for _ in 0..<tokensPerArray {
                let token = VT100Token()
                token.type = VT100_UNKNOWNCHAR
                CVectorAppendVT100Token(&vector, token)
            }
            addTokens(vector, lengthTotal: tokensPerArray * 10, lengthExcludingInBandSignaling: tokensPerArray * 10)
        }
    }
}
