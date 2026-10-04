//
//  MacRequestWatchdogTests.swift
//  iTerm2CompanionTests
//
//  MacRequestWatchdog times requests out, except while the Mac says it cannot
//  answer. MacLivenessProbe pings meanwhile, so a dead connection is still
//  noticed. These tests pin:
//
//    - An ordinary request still times out, and an answered one returns.
//    - Time while the Mac is blocked does not count.
//    - The full timeout starts over each time the Mac unblocks, including when
//      it unblocked just before the old deadline.
//    - The probe pings at its interval only while active, and reports a failed
//      ping once.
//
//  No test waits on a real clock: the sleeps are completed by hand.
//

import XCTest
import CompanionProtocol
@testable import iTerm2Companion

private struct FailsafeTimeout: Error, CustomStringConvertible {
    let what: String
    var description: String { "Timed out waiting for \(what)" }
}

/// Runs `operation`, failing instead of hanging if it never finishes. The limit
/// is generous and only matters when a test (or the code under test) is broken.
private func withFailsafe<T>(_ what: String,
                             seconds: TimeInterval = 5,
                             _ operation: @escaping () async throws -> T) async throws -> T {
    let lock = NSLock()
    var resumed = false
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
        let resumeOnce: (Result<T, Error>) -> Void = { result in
            lock.lock()
            let first = !resumed
            resumed = true
            lock.unlock()
            if first {
                continuation.resume(with: result)
            }
        }
        Task.detached {
            do {
                resumeOnce(.success(try await operation()))
            } catch {
                resumeOnce(.failure(error))
            }
        }
        Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            resumeOnce(.failure(FailsafeTimeout(what: what)))
        }
    }
}

/// Sleeps that end when the test says so.
private final class ManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [(id: Int, seconds: TimeInterval, continuation: CheckedContinuation<Void, Error>)] = []
    private var requestedDurations: [TimeInterval] = []
    private var countWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var nextID = 0

    /// Every duration asked for so far, in order.
    var requested: [TimeInterval] {
        lock.lock(); defer { lock.unlock() }
        return requestedDurations
    }

    private func makeID() -> Int {
        lock.lock(); defer { lock.unlock() }
        nextID += 1
        return nextID
    }

    func sleep(_ seconds: TimeInterval) async throws {
        let id = makeID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                pending.append((id, seconds, continuation))
                requestedDurations.append(seconds)
                let total = requestedDurations.count
                let ready = countWaiters.filter { $0.count <= total }.map { $0.continuation }
                countWaiters.removeAll { $0.count <= total }
                lock.unlock()
                ready.forEach { $0.resume() }
            }
        } onCancel: {
            lock.lock()
            let cancelled = pending.filter { $0.id == id }
            pending.removeAll { $0.id == id }
            lock.unlock()
            cancelled.forEach { $0.continuation.resume(throwing: CancellationError()) }
        }
    }

    /// Suspends until `count` sleeps have been asked for in total.
    func waitForRequests(_ count: Int) async throws {
        try await withFailsafe("sleep request #\(count)") {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.lock.lock()
                if self.requestedDurations.count >= count {
                    self.lock.unlock()
                    continuation.resume()
                } else {
                    self.countWaiters.append((count, continuation))
                    self.lock.unlock()
                }
            }
        }
    }

    /// The oldest sleep still waiting ends now.
    func completeOldest() {
        lock.lock()
        let first = pending.isEmpty ? nil : pending.removeFirst()
        lock.unlock()
        first?.continuation.resume()
    }
}

/// A request body the test finishes by hand. Like the real thing
/// (CompanionSession.request), it ends with CancellationError when its task is
/// cancelled, which is how a timed-out request is abandoned.
private final class ManualBody: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?

    func run() async throws -> String {
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.park(continuation)
            }
        } onCancel: {
            self.finish(.failure(CancellationError()))
        }
    }

    private func park(_ continuation: CheckedContinuation<String, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func finish(_ value: String) {
        finish(.success(value))
    }

    private func finish(_ outcome: Result<String, Error>) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        let continuation = self.continuation
        self.continuation = nil
        result = outcome
        lock.unlock()
        continuation?.resume(with: outcome)
    }
}

final class MacRequestWatchdogTests: XCTestCase {
    private func isTimeout(_ error: Error, label: String) -> Bool {
        guard case TransportError.connectionFailed(let message)? = error as? TransportError else {
            return false
        }
        return message.contains(label) && message.contains("timed out")
    }

    func test_answeredRequestReturnsItsResult() async throws {
        let sleeper = ManualSleeper()
        let watchdog = MacRequestWatchdog(sleep: { try await sleeper.sleep($0) })
        let result = try await watchdog.run(timeout: 15, label: "Chat list request") { "lists" }
        XCTAssertEqual(result, "lists")
    }

    func test_unansweredRequestTimesOut() async throws {
        let sleeper = ManualSleeper()
        let watchdog = MacRequestWatchdog(sleep: { try await sleeper.sleep($0) })
        let body = ManualBody()
        let request = Task { try await watchdog.run(timeout: 15, label: "Chat list request") { try await body.run() } }
        try await sleeper.waitForRequests(1)
        XCTAssertEqual(sleeper.requested, [15])
        sleeper.completeOldest()
        do {
            _ = try await withFailsafe("the request to end") { try await request.value }
            XCTFail("expected a timeout")
        } catch {
            XCTAssertTrue(isTimeout(error, label: "Chat list request"), "unexpected error: \(error)")
        }
    }

    /// The reconnect case: the Mac is already blocked when the request is sent.
    func test_deadlineDoesNotStartWhileTheMacIsBlocked() async throws {
        let sleeper = ManualSleeper()
        let watchdog = MacRequestWatchdog(sleep: { try await sleeper.sleep($0) })
        watchdog.setBlocked(true)
        XCTAssertTrue(watchdog.isBlocked)
        let body = ManualBody()
        let request = Task { try await watchdog.run(timeout: 15, label: "Chat list request") { try await body.run() } }

        // Unblocking is what starts the clock. Had the watchdog started one
        // while blocked, there would be two requests for sleep here, not one.
        watchdog.setBlocked(false)
        try await sleeper.waitForRequests(1)
        XCTAssertEqual(sleeper.requested, [15])

        // The Mac works through its backlog and answers.
        body.finish("lists")
        let result = try await withFailsafe("the request to end") { try await request.value }
        XCTAssertEqual(result, "lists")
    }

    /// A request already in flight when the alert appears.
    func test_blockDuringARequestHoldsItAndUnblockingRestartsTheFullTimeout() async throws {
        let sleeper = ManualSleeper()
        let watchdog = MacRequestWatchdog(sleep: { try await sleeper.sleep($0) })
        let body = ManualBody()
        let request = Task { try await watchdog.run(timeout: 15, label: "Loading sessions") { try await body.run() } }
        try await sleeper.waitForRequests(1)

        // The alert appears, and the original deadline passes while it is up.
        watchdog.setBlocked(true)
        sleeper.completeOldest()

        // No timeout. When the alert is dismissed the full 15 seconds start over.
        watchdog.setBlocked(false)
        try await sleeper.waitForRequests(2)
        XCTAssertEqual(sleeper.requested, [15, 15])

        // And this time it runs out.
        sleeper.completeOldest()
        do {
            _ = try await withFailsafe("the request to end") { try await request.value }
            XCTFail("expected a timeout")
        } catch {
            XCTAssertTrue(isTimeout(error, label: "Loading sessions"), "unexpected error: \(error)")
        }
    }

    /// The Mac was blocked for most of the timeout and unblocked just before the
    /// original deadline. It still gets the full timeout to catch up.
    func test_unblockingJustBeforeTheOldDeadlineStillRestartsTheFullTimeout() async throws {
        let sleeper = ManualSleeper()
        let watchdog = MacRequestWatchdog(sleep: { try await sleeper.sleep($0) })
        let body = ManualBody()
        let request = Task { try await watchdog.run(timeout: 15, label: "Loading sessions") { try await body.run() } }
        try await sleeper.waitForRequests(1)

        watchdog.setBlocked(true)
        watchdog.setBlocked(false)
        // The original deadline arrives with the Mac no longer blocked.
        sleeper.completeOldest()

        try await sleeper.waitForRequests(2)
        XCTAssertEqual(sleeper.requested, [15, 15], "the old deadline must not count: a block interrupted it")
        body.finish("tree")
        let result = try await withFailsafe("the request to end") { try await request.value }
        XCTAssertEqual(result, "tree")
    }

    func test_cancellingTheRequestEndsItWhileHeld() async throws {
        let sleeper = ManualSleeper()
        let watchdog = MacRequestWatchdog(sleep: { try await sleeper.sleep($0) })
        watchdog.setBlocked(true)
        let body = ManualBody()
        let request = Task { try await watchdog.run(timeout: 15, label: "Loading sessions") { try await body.run() } }
        request.cancel()
        body.finish("late")
        // Either outcome is fine as long as it ends: the body's result, or a
        // cancellation. What must not happen is a hang.
        _ = try? await withFailsafe("the cancelled request to end") { try await request.value }
    }
}

final class MacLivenessProbeTests: XCTestCase {
    /// Pings the test answers by hand.
    private final class ManualPinger: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var answers: [Bool] = []
        private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

        var pingCount: Int {
            lock.lock(); defer { lock.unlock() }
            return count
        }

        /// What the next pings return, in order. Defaults to true.
        func answer(_ values: [Bool]) {
            lock.lock(); answers = values; lock.unlock()
        }

        func ping() async -> Bool {
            return recordPing()
        }

        private func recordPing() -> Bool {
            lock.lock()
            count += 1
            let total = count
            let result = answers.isEmpty ? true : answers.removeFirst()
            let ready = waiters.filter { $0.count <= total }.map { $0.continuation }
            waiters.removeAll { $0.count <= total }
            lock.unlock()
            ready.forEach { $0.resume() }
            return result
        }

        func waitForPings(_ target: Int) async throws {
            try await withFailsafe("ping #\(target)") {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.lock.lock()
                    if self.count >= target {
                        self.lock.unlock()
                        continuation.resume()
                    } else {
                        self.waiters.append((target, continuation))
                        self.lock.unlock()
                    }
                }
            }
        }
    }

    func test_pingsAfterEachIntervalWhileActive() async throws {
        let sleeper = ManualSleeper()
        let pinger = ManualPinger()
        let probe = MacLivenessProbe(interval: 10, sleep: { try await sleeper.sleep($0) },
                                     ping: { await pinger.ping() },
                                     onDead: {})
        XCTAssertEqual(sleeper.requested, [], "an inactive probe does nothing")

        probe.setActive(true)
        probe.setActive(true)  // idempotent: still one loop
        try await sleeper.waitForRequests(1)
        XCTAssertEqual(pinger.pingCount, 0, "the first ping comes after the first interval")
        sleeper.completeOldest()
        try await pinger.waitForPings(1)
        try await sleeper.waitForRequests(2)
        sleeper.completeOldest()
        try await pinger.waitForPings(2)
        try await sleeper.waitForRequests(3)
        XCTAssertEqual(sleeper.requested, [10, 10, 10])
        probe.setActive(false)
    }

    func test_failedPingReportsDeadOnceAndStops() async throws {
        let sleeper = ManualSleeper()
        let pinger = ManualPinger()
        pinger.answer([true, false])
        let (dead, deadContinuation) = AsyncStream<Void>.makeStream()
        let probe = MacLivenessProbe(interval: 10,
                                     sleep: { try await sleeper.sleep($0) },
                                     ping: { await pinger.ping() },
                                     onDead: { deadContinuation.yield() })
        probe.setActive(true)
        try await sleeper.waitForRequests(1)
        sleeper.completeOldest()
        try await sleeper.waitForRequests(2)
        sleeper.completeOldest()
        try await withFailsafe("the probe to report a dead connection") {
            for await _ in dead { break }
        }
        XCTAssertEqual(pinger.pingCount, 2)
        XCTAssertEqual(sleeper.requested, [10, 10], "it stopped: no further interval was started")

        // It can be started again for the next connection.
        probe.setActive(true)
        try await sleeper.waitForRequests(3)
        probe.setActive(false)
    }

    func test_deactivatingStopsThePings() async throws {
        let sleeper = ManualSleeper()
        let pinger = ManualPinger()
        let probe = MacLivenessProbe(interval: 10, sleep: { try await sleeper.sleep($0) },
                                     ping: { await pinger.ping() },
                                     onDead: {})
        probe.setActive(true)
        try await sleeper.waitForRequests(1)
        probe.setActive(false)
        // Starting again begins a fresh interval; the cancelled one never pinged.
        probe.setActive(true)
        try await sleeper.waitForRequests(2)
        XCTAssertEqual(pinger.pingCount, 0)
        probe.setActive(false)
    }
}
