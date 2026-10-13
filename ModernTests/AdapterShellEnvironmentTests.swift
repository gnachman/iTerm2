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

    // MARK: - CLAUDE_CONFIG_DIR (QA finding F-244)

    func testParseSplitsPathAndClaudeConfigDir() {
        let both = AdapterShellEnvironment.parse(shellOutput: "/usr/bin:/bin\n/Users/me/cfg")
        XCTAssertEqual(both.path, "/usr/bin:/bin")
        XCTAssertEqual(both.claudeConfigDir, "/Users/me/cfg")

        // The gateway trims trailing newlines, so an unset variable leaves only PATH.
        let pathOnly = AdapterShellEnvironment.parse(shellOutput: "/usr/bin:/bin")
        XCTAssertEqual(pathOnly.path, "/usr/bin:/bin")
        XCTAssertNil(pathOnly.claudeConfigDir)

        XCTAssertNil(AdapterShellEnvironment.parse(shellOutput: "").path)
    }

    // The real fetch command, run by a shell the way the gateway runs it, must print what
    // parse(shellOutput:) expects, both with the variable set and unset, and exit 0 either way
    // (the gateway reports a nonzero exit as nil, which would lose PATH too).
    func testFetchCommandOutputParses() throws {
        func run(_ environment: [String: String]) throws -> (status: Int32, output: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-f", "-c", AdapterShellEnvironment.fetchCommand]
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            return (process.terminationStatus,
                    text.trimmingCharacters(in: .newlines))
        }
        let set = try run(["PATH": "/a/bin:/usr/bin:/bin", "CLAUDE_CONFIG_DIR": "/Users/me/my cfg"])
        XCTAssertEqual(set.status, 0)
        let parsedSet = AdapterShellEnvironment.parse(shellOutput: set.output)
        XCTAssertEqual(parsedSet.path, "/a/bin:/usr/bin:/bin")
        XCTAssertEqual(parsedSet.claudeConfigDir, "/Users/me/my cfg")

        let unset = try run(["PATH": "/a/bin:/usr/bin:/bin"])
        XCTAssertEqual(unset.status, 0)
        let parsedUnset = AdapterShellEnvironment.parse(shellOutput: unset.output)
        XCTAssertEqual(parsedUnset.path, "/a/bin:/usr/bin:/bin")
        XCTAssertNil(parsedUnset.claudeConfigDir)
    }

    func testShellValuesCarryClaudeConfigDirButAdapterEnvironmentDoesNot() {
        let shell = FakeShell()
        let environment = makeEnvironment(shell: shell)
        var values: AdapterShellEnvironment.ShellValues?
        var adapterEnvironment: [String: String]?
        environment.shellValues { values = $0 }
        environment.environment { adapterEnvironment = $0 }
        XCTAssertEqual(shell.fetchCount, 1)
        shell.completions[0]("/usr/bin\n/Users/me/cfg")

        XCTAssertEqual(values, AdapterShellEnvironment.ShellValues(path: merged("/usr/bin"),
                                                                   claudeConfigDir: "/Users/me/cfg",
                                                                   reportedByShell: true))
        XCTAssertEqual(adapterEnvironment?["PATH"], merged("/usr/bin"))
        XCTAssertNil(adapterEnvironment?["CLAUDE_CONFIG_DIR"])
        XCTAssertEqual(adapterEnvironment?.count, 2)

        // Cached: no new shell run.
        var cached: AdapterShellEnvironment.ShellValues?
        environment.shellValues { cached = $0 }
        XCTAssertEqual(cached, values)
        XCTAssertEqual(shell.fetchCount, 1)
    }

    func testFailedFetchShellValuesAreNotReportedByShell() {
        let shell = FakeShell()
        let environment = makeEnvironment(shell: shell)
        var values: AdapterShellEnvironment.ShellValues?
        environment.shellValues { values = $0 }
        shell.completions[0](nil)
        XCTAssertEqual(values, AdapterShellEnvironment.ShellValues(path: fallback,
                                                                   claudeConfigDir: nil,
                                                                   reportedByShell: false))
    }

    func testRefreshReplacesClaudeConfigDirAndFailedRefreshKeepsIt() {
        let shell = FakeShell()
        let environment = makeEnvironment(shell: shell, refreshInterval: 0)
        environment.shellValues { _ in }
        shell.completions[0]("/usr/bin\n/old")

        environment.prefetch()
        shell.completions[1]("/usr/bin")
        var afterUnset: AdapterShellEnvironment.ShellValues?
        environment.shellValues { afterUnset = $0 }
        XCTAssertNil(afterUnset?.claudeConfigDir, "The shell no longer sets it")
        XCTAssertEqual(afterUnset?.reportedByShell, true)

        environment.prefetch()
        shell.completions[2]("/usr/bin\n/new")
        environment.prefetch()
        shell.completions[3](nil)
        var afterFailure: AdapterShellEnvironment.ShellValues?
        environment.shellValues { afterFailure = $0 }
        XCTAssertEqual(afterFailure?.claudeConfigDir, "/new")
        XCTAssertEqual(afterFailure?.reportedByShell, true)
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
