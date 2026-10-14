//
//  iTermBufferedCommandRunnerTests.swift
//  iTerm2 ModernTests
//
//  Covers iTermBufferedCommandRunner's handling of commands that flood
//  output and of commands whose descendants hold the output pipe open
//  after a timeout.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermBufferedCommandRunnerTests: XCTestCase {
    private let cap = 1024 * 1024

    private static func physicalFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : 0
    }

    // Runs blockingRun(withTimeout:) off the main thread and waits for it
    // event-driven, with a deadline far longer than the expected run time but
    // far shorter than the time the bug would take, so a regression fails
    // instead of hanging the suite.
    private func runAndWait(_ runner: iTermBufferedCommandRunner,
                            runnerTimeout: TimeInterval,
                            testDeadline: TimeInterval) {
        let done = expectation(description: "runner finished")
        DispatchQueue.global().async {
            _ = runner.blockingRun(withTimeout: runnerTimeout)
            done.fulfill()
        }
        if XCTWaiter().wait(for: [done], timeout: testDeadline) != .completed {
            XCTFail("Runner did not finish within \(testDeadline) seconds")
            // Don't leave the command running into later tests.
            runner.terminate()
        }
    }

    // F-116: each chunk read from the pipe used to be autoreleased into a
    // pool that wasn't drained until reading finished, so a command that
    // floods stdout grew memory by gigabytes even though the captured
    // output was capped. The runner here does not stop at the cap, so it
    // keeps reading until the timeout; the peak footprint must stay small.
    func test_floodingCommand_doesNotAccumulateReadChunks() {
        let runner = iTermBufferedCommandRunner(command: "/usr/bin/yes",
                                                withArguments: [],
                                                path: "/")
        runner.maximumOutputSize = NSNumber(value: cap)
        runner.discardStandardError = true
        let baseline = Self.physicalFootprint()
        var peak = baseline
        var chunks = 0
        // Called serially (the reader waits for each call to finish).
        runner.outputHandler = { _, handled in
            chunks += 1
            if chunks % 64 == 0 {
                peak = max(peak, Self.physicalFootprint())
            }
            handled()
        }
        runAndWait(runner, runnerTimeout: 3, testDeadline: 60)

        XCTAssertGreaterThan(chunks, 64, "yes should have produced plenty of output")
        XCTAssertEqual(runner.output?.count, cap)
        XCTAssertTrue(runner.truncated)
        // Without the fix this grows by well over a gigabyte in 3 seconds.
        let growth = peak > baseline ? peak - baseline : 0
        XCTAssertLessThan(growth, 300 * 1024 * 1024,
                          "Footprint grew by \(growth) bytes while reading \(chunks) chunks")
    }

    // F-116: with terminateWhenOutputExceedsMaximum, hitting the cap ends the
    // run instead of reading (and discarding) output until the timeout.
    func test_terminateWhenOutputExceedsMaximum_endsRunAtCap() {
        let runner = iTermBufferedCommandRunner(command: "/usr/bin/yes",
                                                withArguments: [],
                                                path: "/")
        runner.maximumOutputSize = NSNumber(value: cap)
        runner.discardStandardError = true
        runner.terminateWhenOutputExceedsMaximum = true
        // The runner's own timeout is a backstop so a regression doesn't
        // leave `yes` running; the test deadline is well before it.
        runAndWait(runner, runnerTimeout: 35, testDeadline: 30)

        XCTAssertEqual(runner.output?.count, cap)
        XCTAssertTrue(runner.truncated)
    }

    // F-117: a timed-out wrapper whose child holds stdout open used to leave
    // the runner waiting until the child exited on its own. With
    // terminatesProcessGroup the timeout kills the child too.
    func test_timeout_killsProcessGroupHoldingThePipe() {
        // `sleep` is not the last command, so sh forks it instead of
        // exec'ing it, and it inherits sh's stdout.
        let runner = iTermBufferedCommandRunner(command: "/bin/sh",
                                                withArguments: ["-c", "/bin/sleep 600; true"],
                                                path: "/")
        runner.discardStandardError = true
        runner.terminatesProcessGroup = true
        runAndWait(runner, runnerTimeout: 1, testDeadline: 30)
    }
}
