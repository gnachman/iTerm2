//
//  FrozenMainQueue.swift
//  iTerm2 ModernTests
//
//  Test harness that reproduces what a modal alert does to the main thread when
//  it is started from a main-queue callout (a DispatchQueue.main.async block or
//  a @MainActor task): the thread spins a nested run loop in the modal panel
//  mode, and CFRunLoop refuses to drain the main dispatch queue from a nested
//  loop inside a main-queue callout. So main-queue blocks and @MainActor jobs
//  are frozen, while run loop blocks/timers in the common modes and background
//  queues keep running.
//
//  Every use self-checks that the freeze really happened: a @MainActor task and
//  a main-queue block are queued just before the spin and must not have run by
//  the time the body finishes, after the nested loop has made several passes.
//
//  Nothing here depends on timing for success. The deadline is only a guard so
//  a broken test fails instead of hanging.
//

import AppKit
import XCTest
import os

enum FrozenMainQueue {
    struct Timeout: Error, CustomStringConvertible {
        let what: String
        var description: String { "Timed out waiting for \(what)" }
    }

    /// Handed to the body so it can wait for the nested run loop to turn.
    final class Freeze: Sendable {
        fileprivate struct State: Sendable {
            var done = false
            var passes = 0
            var mainActorCanaryRan = false
            var mainQueueCanaryRan = false
            var passWaiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []
        }
        fileprivate let state = OSAllocatedUnfairLock(initialState: State())

        /// Suspends until the nested modal run loop has completed `count` more
        /// passes. Use it to give frozen work a real chance to (wrongly) run
        /// before asserting that it did not.
        func waitForRunLoopPasses(_ count: Int) async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow = state.withLock { state -> Bool in
                    if state.done {
                        return true
                    }
                    state.passWaiters.append((state.passes + count, continuation))
                    return false
                }
                if resumeNow {
                    continuation.resume()
                }
            }
        }

        fileprivate func notePass() {
            let ready = state.withLock { state -> [CheckedContinuation<Void, Never>] in
                state.passes += 1
                let passes = state.passes
                let ready = state.passWaiters.filter { $0.threshold <= passes }.map { $0.continuation }
                state.passWaiters.removeAll { $0.threshold <= passes }
                return ready
            }
            for continuation in ready {
                continuation.resume()
            }
        }

        fileprivate func finish() {
            let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
                state.done = true
                let all = state.passWaiters.map { $0.continuation }
                state.passWaiters.removeAll()
                return all
            }
            for continuation in waiters {
                continuation.resume()
            }
        }
    }

    /// Runs `body` (off the main thread) while the main thread is stuck in a
    /// nested modal-panel run loop inside a main-queue callout. `setup` runs on
    /// the main thread inside that callout, just before the loop starts, the
    /// way code that is about to show an alert would.
    static func run<T>(file: StaticString = #filePath,
                       line: UInt = #line,
                       setup: @escaping @MainActor () -> Void = {},
                       _ body: (Freeze) async throws -> T) async throws -> T {
        let freeze = Freeze()
        let (entered, enteredContinuation) = AsyncStream<Void>.makeStream()
        let (exited, exitedContinuation) = AsyncStream<Void>.makeStream()
        let modalMode = CFRunLoopMode(RunLoop.Mode.modalPanel.rawValue as CFString)

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                setup()
            }
            // Queued behind this callout. They can only run once it returns.
            Task { @MainActor in
                freeze.state.withLock { $0.mainActorCanaryRan = true }
            }
            DispatchQueue.main.async {
                freeze.state.withLock { $0.mainQueueCanaryRan = true }
            }
            enteredContinuation.yield()
            let deadline = Date().addingTimeInterval(60)
            while !freeze.state.withLock({ $0.done }) && Date() < deadline {
                CFRunLoopRunInMode(modalMode, 0.01, true)
                freeze.notePass()
            }
            exitedContinuation.yield()
        }

        for await _ in entered { break }
        let result: Result<T, Error>
        do {
            result = .success(try await body(freeze))
        } catch {
            result = .failure(error)
        }
        // Let the nested loop turn a few more times so that, if the main queue
        // were NOT frozen, the canaries would have had every chance to run.
        await freeze.waitForRunLoopPasses(3)
        let (mainActorCanaryRan, mainQueueCanaryRan) = freeze.state.withLock {
            ($0.mainActorCanaryRan, $0.mainQueueCanaryRan)
        }
        freeze.finish()
        for await _ in exited { break }
        // Back to normal: wait until the main actor is serviced again so
        // nothing queued during the freeze leaks into the next test.
        await MainActor.run {}

        XCTAssertFalse(mainActorCanaryRan,
                       "A @MainActor task ran during the freeze, so the harness did not reproduce the bug",
                       file: file, line: line)
        XCTAssertFalse(mainQueueCanaryRan,
                       "A main-queue block ran during the freeze, so the harness did not reproduce the bug",
                       file: file, line: line)
        return try result.get()
    }

    /// Runs `operation`, failing with Timeout instead of hanging if it never
    /// finishes. The limit is generous and only matters when a test is broken.
    static func withFailsafe<T>(_ what: String,
                                seconds: TimeInterval = 10,
                                _ operation: @escaping () async throws -> T) async throws -> T {
        let resumed = OSAllocatedUnfairLock(initialState: false)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let resumeOnce: (Result<T, Error>) -> Void = { result in
                let first = resumed.withLock { resumed -> Bool in
                    let first = !resumed
                    resumed = true
                    return first
                }
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
                resumeOnce(.failure(Timeout(what: what)))
            }
        }
    }
}
