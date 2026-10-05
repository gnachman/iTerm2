//
//  AdapterShellEnvironmentTests.swift
//  ModernTests
//
//  Password manager adapters run with an explicit environment built from the user’s shell
//  PATH plus the standard CLI install directories. Homebrew’s bw is a Node script whose
//  shebang needs node on PATH (issue 13046). The shell is asked through an injected fetcher
//  so the waiting, timeout, refresh and caching rules can be tested without spawning one.
//

import XCTest
@testable import iTerm2SharedARC

final class AdapterShellEnvironmentTests: XCTestCase {
    private let fallback = AdapterShellEnvironment.fallbackDirectories.joined(separator: ":")

    // Records each fetch’s completion so a test can reply late, never, or in order.
    private final class FakeShell {
        var completions: [(String?) -> Void] = []
        var fetchCount: Int { completions.count }
        func fetch(_ completion: @escaping (String?) -> Void) {
            completions.append(completion)
        }
    }

    private func makeEnvironment(shell: FakeShell,
                                 timeout: TimeInterval = 10,
                                 dropDeadline: TimeInterval = 20,
                                 refreshInterval: TimeInterval = .infinity) -> AdapterShellEnvironment {
        return AdapterShellEnvironment(fetchPath: shell.fetch,
                                       timeout: timeout,
                                       dropDeadline: dropDeadline,
                                       refreshInterval: refreshInterval)
    }

    private func merged(_ shellPath: String) -> String {
        return AdapterShellEnvironment.mergedPath(shellPath: shellPath)
    }

    // Waits for main-queue timers scheduled before this call with deadlines up to `seconds`.
    private func spinMainQueue(seconds: TimeInterval) {
        let done = expectation(description: "timers before \(seconds)s have fired")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            done.fulfill()
        }
        wait(for: [done], timeout: seconds + 5)
    }

    // MARK: - Merging

    func testNoShellPathUsesFallbackDirectories() {
        XCTAssertEqual(AdapterShellEnvironment.mergedPath(shellPath: nil), fallback)
        XCTAssertEqual(AdapterShellEnvironment.mergedPath(shellPath: ""), fallback)
    }

    func testShellPathComesFirstAndMissingFallbacksAreAppended() {
        XCTAssertEqual(merged("/Users/me/bin:/usr/bin:/bin"),
                       "/Users/me/bin:/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/usr/sbin:/sbin")
    }

    func testFallbacksAlreadyPresentAreNotDuplicated() {
        XCTAssertEqual(merged(fallback), fallback)
    }

    func testEmptyEntriesAreDropped() {
        XCTAssertEqual(merged("::/usr/bin::"),
                       "/usr/bin:/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/bin:/usr/sbin:/sbin")
    }

    func testEnvironmentHasHomeAndPath() {
        let environment = AdapterShellEnvironment.environment(path: "/usr/bin")
        XCTAssertEqual(environment["PATH"], "/usr/bin")
        XCTAssertEqual(environment["HOME"], NSHomeDirectory())
        XCTAssertEqual(environment.count, 2)
    }

    // MARK: - First fetch

    func testFirstCallWaitsForShellThenDeliversMergedPath() {
        let shell = FakeShell()
        let environment = makeEnvironment(shell: shell)
        var delivered: [String: String]?
        environment.environment { delivered = $0 }
        XCTAssertNil(delivered, "Must wait for the shell when nothing is cached")
        XCTAssertEqual(shell.fetchCount, 1)

        shell.completions[0]("/Users/me/bin:/usr/bin")
        XCTAssertEqual(delivered?["PATH"], merged("/Users/me/bin:/usr/bin"))
        XCTAssertEqual(delivered?["HOME"], NSHomeDirectory())
    }

    func testPendingCompletionsFlushOnce() {
        let shell = FakeShell()
        let environment = makeEnvironment(shell: shell)
        var firstCalls = 0
        var secondCalls = 0
        environment.environment { _ in firstCalls += 1 }
        environment.environment { _ in secondCalls += 1 }
        XCTAssertEqual(shell.fetchCount, 1, "One outstanding fetch serves every waiter")

        shell.completions[0]("/usr/bin")
        XCTAssertEqual(firstCalls, 1)
        XCTAssertEqual(secondCalls, 1)

        environment.environment { _ in }
        XCTAssertEqual(firstCalls, 1)
        XCTAssertEqual(secondCalls, 1)
    }

    func testFailedFirstFetchCachesFallback() {
        let shell = FakeShell()
        let environment = makeEnvironment(shell: shell)
        var delivered: [String: String]?
        environment.environment { delivered = $0 }
        shell.completions[0](nil)
        XCTAssertEqual(delivered?["PATH"], fallback)

        var immediate: [String: String]?
        environment.environment { immediate = $0 }
        XCTAssertEqual(immediate?["PATH"], fallback, "Nobody waits once the shell has failed")
        XCTAssertEqual(shell.fetchCount, 1, "environment() never starts a fetch on its own once cached")
    }

    // MARK: - Slow shell

    func testTimeoutGivesWaitersFallbackButKeepsFetchAlive() {
        let shell = FakeShell()
        let environment = makeEnvironment(shell: shell, timeout: 0.05)
        let timedOut = expectation(description: "fallback delivered after timeout")
        var delivered: [String: String]?
        environment.environment {
            delivered = $0
            timedOut.fulfill()
        }
        wait(for: [timedOut], timeout: 5)
        XCTAssertEqual(delivered?["PATH"], fallback)

        // Later callers don’t wait either, and nothing new is launched: the shell is still running.
        var immediate: [String: String]?
        environment.environment { immediate = $0 }
        XCTAssertEqual(immediate?["PATH"], fallback)
        XCTAssertEqual(shell.fetchCount, 1)

        // The slow shell finally answers and its PATH takes over.
        shell.completions[0]("/Users/me/.nvm/versions/node/v22/bin:/usr/bin")
        var afterReply: [String: String]?
        environment.environment { afterReply = $0 }
        XCTAssertEqual(afterReply?["PATH"], merged("/Users/me/.nvm/versions/node/v22/bin:/usr/bin"))
    }

    func testDroppedReplyCachesFallbackAndAllowsRetry() {
        let shell = FakeShell()
        let environment = makeEnvironment(shell: shell, timeout: 0.02, dropDeadline: 0.05, refreshInterval: 0)
        var delivered: [String: String]?
        environment.environment { delivered = $0 }
        spinMainQueue(seconds: 0.2)
        XCTAssertEqual(delivered?["PATH"], fallback)
        XCTAssertEqual(shell.fetchCount, 1)

        // Given up on: a prefetch may try again.
        environment.prefetch()
        XCTAssertEqual(shell.fetchCount, 2, "A new fetch starts once the earlier one was dropped")

        // A reply from the dropped fetch still beats the fallback.
        shell.completions[0]("/Users/me/bin")
        var late: [String: String]?
        environment.environment { late = $0 }
        XCTAssertEqual(late?["PATH"], merged("/Users/me/bin"))
    }

    // MARK: - Refresh

    func testEnvironmentNeverStartsARefresh() {
        let shell = FakeShell()
        let environment = makeEnvironment(shell: shell, refreshInterval: 0)
        environment.environment { _ in }
        shell.completions[0]("/usr/bin")

        var delivered: [String: String]?
        environment.environment { delivered = $0 }
        environment.environment { _ in }
        XCTAssertEqual(delivered?["PATH"], merged("/usr/bin"))
        XCTAssertEqual(shell.fetchCount, 1, "Per-command use must not launch a shell")
    }

    func testPrefetchRefreshesInBackgroundOnlyAfterInterval() {
        let shell = FakeShell()
        let environment = makeEnvironment(shell: shell, refreshInterval: .infinity)
        environment.prefetch()
        environment.prefetch()
        XCTAssertEqual(shell.fetchCount, 1, "One fetch at a time")
        shell.completions[0]("/usr/bin")

        environment.prefetch()
        XCTAssertEqual(shell.fetchCount, 1, "No refresh inside the interval")
    }

    func testPrefetchRefreshDoesNotBlockAndReplacesCache() {
        let shell = FakeShell()
        let environment = makeEnvironment(shell: shell, refreshInterval: 0)
        environment.environment { _ in }
        shell.completions[0]("/usr/bin")

        environment.prefetch()
        XCTAssertEqual(shell.fetchCount, 2, "Interval elapsed, so a refresh started")
        var delivered: [String: String]?
        environment.environment { delivered = $0 }
        XCTAssertEqual(delivered?["PATH"], merged("/usr/bin"), "Cached value while the refresh runs")
        environment.prefetch()
        XCTAssertEqual(shell.fetchCount, 2, "No second refresh while one is outstanding")

        shell.completions[1]("/Users/me/bin")
        var refreshed: [String: String]?
        environment.environment { refreshed = $0 }
        XCTAssertEqual(refreshed?["PATH"], merged("/Users/me/bin"))
    }

    func testFailedRefreshKeepsCachedPath() {
        let shell = FakeShell()
        let environment = makeEnvironment(shell: shell, refreshInterval: 0)
        environment.environment { _ in }
        shell.completions[0]("/Users/me/bin")

        environment.prefetch()
        shell.completions[1](nil)
        var delivered: [String: String]?
        environment.environment { delivered = $0 }
        XCTAssertEqual(delivered?["PATH"], merged("/Users/me/bin"))
    }
}
