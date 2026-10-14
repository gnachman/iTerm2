//
//  WorkgroupUsageTests.swift
//  iTerm2 ModernTests
//
//  Covers the "AI Usage" workgroup toolbar item: the JSON contract its
//  command must satisfy (WorkgroupUsageReport decoding + fraction
//  clamping) and the bundled claude_usage.sh parser against a real
//  `claude -p /usage` sample, driven through the fixture env var so no
//  live subscription is needed.
//

import XCTest
@testable import iTerm2SharedARC

final class WorkgroupUsageTests: XCTestCase {
    // MARK: - JSON contract

    func test_decodeReport_parsesBarsAndError() throws {
        let json = """
        {"bars":[{"label":"Session","fraction":0.02,"detail":"resets soon"},
                 {"label":"Week","fraction":0.67,"detail":null}],
         "error":null}
        """
        let report = try JSONDecoder().decode(
            WorkgroupUsageReport.self,
            from: Data(json.utf8))
        XCTAssertNil(report.error)
        XCTAssertEqual(report.bars.count, 2)
        XCTAssertEqual(report.bars[0].label, "Session")
        XCTAssertEqual(report.bars[0].fraction, 0.02, accuracy: 1e-9)
        XCTAssertEqual(report.bars[0].detail, "resets soon")
        XCTAssertEqual(report.bars[1].label, "Week")
        XCTAssertNil(report.bars[1].detail)
        // `short` is optional in the contract: absent decodes to nil.
        XCTAssertNil(report.bars[0].short)
        // Optional error metadata: absent decodes to nil (nil reportable
        // is treated as not-reportable by the view).
        XCTAssertNil(report.diagnostic)
        XCTAssertNil(report.reportable)
    }

    func test_decodeReport_errorWithEmptyBars() throws {
        let json = #"{"bars":[],"error":"claude CLI not found"}"#
        let report = try JSONDecoder().decode(
            WorkgroupUsageReport.self,
            from: Data(json.utf8))
        XCTAssertEqual(report.error, "claude CLI not found")
        XCTAssertTrue(report.bars.isEmpty)
    }

    func test_bar_clampsFraction() throws {
        let json = #"{"bars":[{"label":"Over","fraction":1.5,"detail":null},{"label":"Under","fraction":-0.2,"detail":null}],"error":null}"#
        let report = try JSONDecoder().decode(
            WorkgroupUsageReport.self,
            from: Data(json.utf8))
        XCTAssertEqual(report.bars[0].clampedFraction, 1.0, accuracy: 1e-9)
        XCTAssertEqual(report.bars[1].clampedFraction, 0.0, accuracy: 1e-9)
    }

    // MARK: - Bundled parser script

    // Resolve the shipped parser from the source tree so the test
    // exercises the exact script that gets bundled.
    private func scriptURL() -> URL {
        // #filePath is ModernTests/WorkgroupUsageTests.swift; the repo
        // root is its parent's parent.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRoot
            .appendingPathComponent("sources")
            .appendingPathComponent("Workgroups")
            .appendingPathComponent("UsageProviders")
            .appendingPathComponent("claude_usage.sh")
    }

    private func runScript(fixture: String) throws -> Data {
        let script = scriptURL()
        try XCTSkipUnless(FileManager.default.fileExists(atPath: script.path),
                          "claude_usage.sh not found at \(script.path)")
        let fixtureURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude_usage_fixture_\(UUID().uuidString).txt")
        try fixture.write(to: fixtureURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let process = Process()
        process.launchPath = "/bin/sh"
        process.arguments = [script.path]
        var env = ProcessInfo.processInfo.environment
        env["ITERM2_AI_USAGE_FIXTURE"] = fixtureURL.path
        process.environment = env
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    func test_script_parsesRealSample() throws {
        // The real `claude -p /usage` output, verbatim (middle dot is
        // U+00B7). Header/footer lines must be ignored.
        let fixture = """
        You are currently using your subscription to power your Claude Code usage

        Current session: 2% used · resets Sep 15 at 5pm (America/Los_Angeles)
        Current week (all models): 67% used · resets Sep 19 at 1pm (America/Los_Angeles)
        Current week (Fable): 12% used · resets Sep 19 at 12:59pm (America/Los_Angeles)

        What's contributing to your limits usage?
        """
        let data = try runScript(fixture: fixture)
        let report = try JSONDecoder().decode(WorkgroupUsageReport.self, from: data)
        XCTAssertNil(report.error)
        XCTAssertEqual(report.bars.count, 3)

        XCTAssertEqual(report.bars[0].label, "Session")
        XCTAssertEqual(report.bars[0].short, "S")
        XCTAssertEqual(report.bars[1].short, "W")
        XCTAssertEqual(report.bars[2].short, "WF")
        XCTAssertEqual(report.bars[0].fraction, 0.02, accuracy: 1e-6)

        XCTAssertEqual(report.bars[1].label, "Week")
        XCTAssertEqual(report.bars[1].fraction, 0.67, accuracy: 1e-6)

        XCTAssertEqual(report.bars[2].label, "Week (Fable)")
        XCTAssertEqual(report.bars[2].fraction, 0.12, accuracy: 1e-6)

        // The reset detail is carried through for the tooltip.
        XCTAssertEqual(report.bars[0].detail,
                       "resets Sep 15 at 5pm (America/Los_Angeles)")
    }

    func test_script_reportsErrorOnUsageShapedButUnparseable() throws {
        // Output that *looks* like a usage report but no bar parses (a
        // changed or localized format) is the one reportable case, and it
        // carries the raw text as a diagnostic.
        let data = try runScript(fixture: "Current session: deux pour cent\n")
        let report = try JSONDecoder().decode(WorkgroupUsageReport.self, from: data)
        XCTAssertTrue(report.bars.isEmpty)
        XCTAssertNotNil(report.error)
        XCTAssertEqual(report.reportable, true)
        XCTAssertNotNil(report.diagnostic)
        XCTAssertTrue(report.diagnostic?.contains("Current session") ?? false)
    }

    func test_script_unparseableDiagnosticStaysValidJSON() throws {
        // Quotes, backslashes, tabs, and newlines in the raw output must
        // not break the emitted JSON string. (Usage-shaped so it takes the
        // reportable path that carries a diagnostic.)
        let data = try runScript(
            fixture: "Current session: \"weird\" \\ back\ttab\nsecond line\n")
        let report = try JSONDecoder().decode(WorkgroupUsageReport.self, from: data)
        XCTAssertEqual(report.reportable, true)
        XCTAssertTrue(report.diagnostic?.contains("\"weird\"") ?? false)
    }

    // Expected environment states must NOT be reportable (otherwise users
    // file issues about their own setup) and carry no diagnostic.
    func test_script_subscriptionNoticeIsNotReportable() throws {
        let data = try runScript(
            fixture: "/usage is only available for subscription plans.\n")
        let report = try JSONDecoder().decode(WorkgroupUsageReport.self, from: data)
        XCTAssertTrue(report.bars.isEmpty)
        XCTAssertNotEqual(report.reportable, true)
        XCTAssertNil(report.diagnostic)
    }

    func test_script_apiBillingIsNotReportable() throws {
        // API-only users (no subscription) get an auth error once we unset
        // ANTHROPIC_API_KEY. Expected, not a bug.
        let data = try runScript(fixture: "Invalid API key · Please run /login\n")
        let report = try JSONDecoder().decode(WorkgroupUsageReport.self, from: data)
        XCTAssertNotEqual(report.reportable, true)
        XCTAssertNil(report.diagnostic)
    }

    func test_script_unrecognizedOutputIsReportable() throws {
        // Output we can't attribute to any known cause is just as likely
        // an iTerm2 bug as a user-setup issue, so we don't guess: it's
        // reportable and carries the raw output, without blaming the user.
        let data = try runScript(fixture: "some unrelated gibberish\n")
        let report = try JSONDecoder().decode(WorkgroupUsageReport.self, from: data)
        XCTAssertTrue(report.bars.isEmpty)
        XCTAssertEqual(report.reportable, true)
        XCTAssertNotNil(report.diagnostic)
    }

    func test_script_nonLatinModelEmitsEmptyShort() throws {
        // A model name with no ASCII letters can't yield a byte-wise
        // initial, so the script emits an empty short and defers to the
        // toolbar's Unicode-aware fallback. It must NOT collapse the bar
        // away or crash.
        let data = try runScript(
            fixture: "Current week (\u{03a9}\u{03bc}): 10% used \u{00b7} resets soon\n")
        let report = try JSONDecoder().decode(WorkgroupUsageReport.self, from: data)
        XCTAssertEqual(report.bars.count, 1)
        XCTAssertEqual(report.bars[0].label, "Week (\u{03a9}\u{03bc})")
        XCTAssertEqual(report.bars[0].short, "")
    }

    // MARK: - Toolbar item decode robustness

    func test_decodeUsageItem_unknownProviderDegradesInsteadOfThrowing() throws {
        // Regression guard: a `.usage` item whose `provider` holds a
        // rawValue this build doesn't recognize (e.g. prefs synced from a
        // newer iTerm2) must decode to the default provider, NOT throw.
        // A throw here would propagate up and make the whole workgroup
        // model fail to decode, silently discarding every saved workgroup.
        let json = #"{"kind":"usage","provider":"someFutureVendor","command":"","intervalSeconds":60}"#
        let item = try JSONDecoder().decode(
            iTermWorkgroupToolbarItem.self, from: Data(json.utf8))
        guard case let .usage(provider, command, interval) = item else {
            return XCTFail("expected a .usage item, got \(item)")
        }
        XCTAssertEqual(provider, .anthropicClaudeCode)
        XCTAssertEqual(command, "")
        XCTAssertEqual(interval, 60)
    }

    func test_decodeUsageItem_missingProviderDefaults() throws {
        // An absent provider key still defaults cleanly (unchanged behavior).
        let json = #"{"kind":"usage"}"#
        let item = try JSONDecoder().decode(
            iTermWorkgroupToolbarItem.self, from: Data(json.utf8))
        guard case let .usage(provider, _, _) = item else {
            return XCTFail("expected a .usage item, got \(item)")
        }
        XCTAssertEqual(provider, .anthropicClaudeCode)
    }

    // MARK: - Command environment (QA finding F-011)

    // Launched from the Dock, iTerm2's PATH is /usr/bin:/bin:/usr/sbin:/sbin, so the
    // usage command must get the user's shell PATH or `claude` is not found.
    func test_tick_runsCommandWithProvidedShellPath() {
        let ran = expectation(description: "command ran")
        var capturedEnvironment: [String: String]?
        var capturedArguments: [String]?
        let item = WorkgroupUsageToolbarItem(
            identifier: "usage",
            priority: 0,
            provider: .anthropicClaudeCode,
            command: "echo hi",
            intervalSeconds: 60,
            environmentProvider: { completion in
                completion(["PATH": "/shell/bin:/usr/bin", "HOME": "/home/test"])
            },
            commandRunner: { _, arguments, environment, _ in
                capturedArguments = arguments
                capturedEnvironment = environment
                ran.fulfill()
                return nil
            })
        item.tick()
        wait(for: [ran], timeout: 10)
        XCTAssertEqual(capturedArguments, ["-c", "echo hi"])
        XCTAssertEqual(capturedEnvironment?["PATH"], "/shell/bin:/usr/bin")
        XCTAssertEqual(capturedEnvironment?["HOME"], "/home/test")
    }

    func test_tick_waitsForEnvironmentBeforeRunning() {
        var pending: (([String: String]) -> Void)?
        let ran = expectation(description: "command ran")
        let item = WorkgroupUsageToolbarItem(
            identifier: "usage",
            priority: 0,
            provider: .anthropicClaudeCode,
            command: "echo hi",
            intervalSeconds: 60,
            environmentProvider: { completion in pending = completion },
            commandRunner: { _, _, environment, _ in
                XCTAssertEqual(environment["PATH"], "/late/bin")
                ran.fulfill()
                return nil
            })
        item.tick()
        XCTAssertNotNil(pending)
        pending?(["PATH": "/late/bin"])
        wait(for: [ran], timeout: 10)
    }

    func test_usageEnvironment_replacesOnlyPath() {
        let merged = WorkgroupUsageToolbarItem.usageEnvironment(
            base: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/Users/me", "LANG": "en_US.UTF-8"],
            shellValues: shellValues(path: "/Users/me/.local/bin:/opt/homebrew/bin:/usr/bin"),
            recordedClaudeConfigDir: nil)
        // ~/.local/bin is already present, so the shell PATH is used verbatim.
        XCTAssertEqual(merged["PATH"], "/Users/me/.local/bin:/opt/homebrew/bin:/usr/bin")
        XCTAssertEqual(merged["HOME"], "/Users/me")
        XCTAssertEqual(merged["LANG"], "en_US.UTF-8")
    }

    // The native Claude Code installer puts claude in ~/.local/bin, which the shell PATH
    // fallback (used when the shell can't report PATH) lacks.
    func test_usageEnvironment_appendsLocalBinWhenMissing() {
        let merged = WorkgroupUsageToolbarItem.usageEnvironment(
            base: ["HOME": "/Users/me"],
            shellValues: shellValues(path: "/opt/homebrew/bin:/usr/bin"),
            recordedClaudeConfigDir: nil)
        XCTAssertEqual(merged["PATH"], "/opt/homebrew/bin:/usr/bin:/Users/me/.local/bin")
    }

    func test_usageEnvironment_doesNotDuplicateLocalBin() {
        let merged = WorkgroupUsageToolbarItem.usageEnvironment(
            base: ["HOME": "/Users/me"],
            shellValues: shellValues(path: "/Users/me/.local/bin:/usr/bin"),
            recordedClaudeConfigDir: nil)
        XCTAssertEqual(merged["PATH"], "/Users/me/.local/bin:/usr/bin")
    }

    // MARK: - CLAUDE_CONFIG_DIR (QA finding F-244)

    private func shellValues(path: String = "/usr/bin",
                             claudeConfigDir: String? = nil,
                             reportedByShell: Bool = true) -> AdapterShellEnvironment.ShellValues {
        return AdapterShellEnvironment.ShellValues(path: path,
                                                   claudeConfigDir: claudeConfigDir,
                                                   reportedByShell: reportedByShell)
    }

    // A CLAUDE_CONFIG_DIR exported by the user's shell startup files is what `claude` in a
    // terminal uses, so it reaches the usage command.
    func test_usageEnvironment_passesShellClaudeConfigDir() {
        let merged = WorkgroupUsageToolbarItem.usageEnvironment(
            base: ["HOME": "/Users/me"],
            shellValues: shellValues(claudeConfigDir: "/Users/me/work-claude"),
            recordedClaudeConfigDir: "/Users/me/recorded")
        XCTAssertEqual(merged["CLAUDE_CONFIG_DIR"], "/Users/me/work-claude")
    }

    // The startup files run after the inherited environment, so in a terminal the shell's
    // value wins over one iTerm2 itself was launched with.
    func test_usageEnvironment_shellClaudeConfigDirBeatsInheritedOne() {
        let merged = WorkgroupUsageToolbarItem.usageEnvironment(
            base: ["HOME": "/Users/me", "CLAUDE_CONFIG_DIR": "/inherited"],
            shellValues: shellValues(claudeConfigDir: "/Users/me/work-claude"),
            recordedClaudeConfigDir: nil)
        XCTAssertEqual(merged["CLAUDE_CONFIG_DIR"], "/Users/me/work-claude")
    }

    // The shell ran and doesn't set it: an inherited value is what a terminal session would
    // see, and the recorded value is stale, so neither is replaced by it.
    func test_usageEnvironment_shellWithoutClaudeConfigDirKeepsInheritedAndIgnoresRecorded() {
        let inherited = WorkgroupUsageToolbarItem.usageEnvironment(
            base: ["HOME": "/Users/me", "CLAUDE_CONFIG_DIR": "/inherited"],
            shellValues: shellValues(),
            recordedClaudeConfigDir: "/Users/me/recorded")
        XCTAssertEqual(inherited["CLAUDE_CONFIG_DIR"], "/inherited")

        let none = WorkgroupUsageToolbarItem.usageEnvironment(
            base: ["HOME": "/Users/me"],
            shellValues: shellValues(),
            recordedClaudeConfigDir: "/Users/me/recorded")
        XCTAssertNil(none["CLAUDE_CONFIG_DIR"])
    }

    // The shell couldn't be read: fall back to the directory recorded when the Claude Code
    // integration was installed, which came from the same shell lookup.
    func test_usageEnvironment_unreadableShellUsesRecordedClaudeConfigDir() {
        let merged = WorkgroupUsageToolbarItem.usageEnvironment(
            base: ["HOME": "/Users/me"],
            shellValues: shellValues(reportedByShell: false),
            recordedClaudeConfigDir: "/Users/me/recorded")
        XCTAssertEqual(merged["CLAUDE_CONFIG_DIR"], "/Users/me/recorded")
    }

    func test_usageEnvironment_unreadableShellKeepsInheritedOverRecorded() {
        let merged = WorkgroupUsageToolbarItem.usageEnvironment(
            base: ["HOME": "/Users/me", "CLAUDE_CONFIG_DIR": "/inherited"],
            shellValues: shellValues(reportedByShell: false),
            recordedClaudeConfigDir: "/Users/me/recorded")
        XCTAssertEqual(merged["CLAUDE_CONFIG_DIR"], "/inherited")
    }

    func test_usageEnvironment_emptyRecordedClaudeConfigDirIsIgnored() {
        let merged = WorkgroupUsageToolbarItem.usageEnvironment(
            base: ["HOME": "/Users/me"],
            shellValues: shellValues(reportedByShell: false),
            recordedClaudeConfigDir: "")
        XCTAssertNil(merged["CLAUDE_CONFIG_DIR"])
    }

    // End to end from the shell lookup's output through to the environment given to the
    // runner: what AdapterShellEnvironment parses must arrive as CLAUDE_CONFIG_DIR.
    func test_shellEnvironment_deliversClaudeConfigDirFromShellOutput() {
        let shell = AdapterShellEnvironment(fetchPath: { completion in
                                                completion("/Users/me/bin:/usr/bin\n/Users/me/work-claude")
                                            },
                                            timeout: 10,
                                            dropDeadline: 20,
                                            refreshInterval: .infinity)
        var delivered: [String: String]?
        WorkgroupUsageToolbarItem.shellEnvironment(from: shell,
                                                   base: ["HOME": "/Users/me"],
                                                   recordedClaudeConfigDir: nil) { delivered = $0 }
        XCTAssertEqual(delivered?["CLAUDE_CONFIG_DIR"], "/Users/me/work-claude")
        XCTAssertTrue(delivered?["PATH"]?.hasPrefix("/Users/me/bin:/usr/bin") ?? false)
    }

    func test_tick_whileWaitingForEnvironmentIsSkipped() {
        var providerCalls = 0
        var pending: (([String: String]) -> Void)?
        let ran = expectation(description: "command ran")
        ran.expectedFulfillmentCount = 1
        ran.assertForOverFulfill = true
        let item = WorkgroupUsageToolbarItem(
            identifier: "usage",
            priority: 0,
            provider: .anthropicClaudeCode,
            command: "echo hi",
            intervalSeconds: 60,
            environmentProvider: { completion in
                providerCalls += 1
                pending = completion
            },
            commandRunner: { _, _, _, _ in
                ran.fulfill()
                return nil
            })
        item.tick()
        item.tick()
        XCTAssertEqual(providerCalls, 1)
        pending?(["PATH": "/late/bin"])
        wait(for: [ran], timeout: 10)
    }

    // End to end through the real runner and the shipped script: a `claude` that exists
    // only in a directory on the supplied PATH must be found.
    func test_runCommand_findsClaudeOnSuppliedPath() throws {
        let script = scriptURL()
        try XCTSkipUnless(FileManager.default.fileExists(atPath: script.path),
                          "claude_usage.sh not found at \(script.path)")
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude_usage_path_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let claude = dir.appendingPathComponent("claude")
        try """
        #!/bin/sh
        echo 'Current session: 42% used · resets soon'
        """.write(to: claude, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)

        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "ITERM2_AI_USAGE_FIXTURE")
        environment["PATH"] = dir.path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        let data = WorkgroupUsageToolbarItem.runCommand(launchPath: "/bin/sh",
                                                        arguments: [script.path],
                                                        environment: environment,
                                                        timeout: 20)
        let report = try JSONDecoder().decode(WorkgroupUsageReport.self, from: try XCTUnwrap(data))
        XCTAssertNil(report.error)
        XCTAssertEqual(report.bars.count, 1)
        XCTAssertEqual(try XCTUnwrap(report.bars.first).fraction, 0.42, accuracy: 1e-6)
    }

    // MARK: - Runaway commands (QA findings F-116, F-117)

    private func runCommandOffMain(arguments: [String],
                                   timeout: TimeInterval,
                                   deadline: TimeInterval) -> Data? {
        let done = expectation(description: "runCommand returned")
        var result: Data?
        DispatchQueue.global().async {
            result = WorkgroupUsageToolbarItem.runCommand(launchPath: "/bin/sh",
                                                          arguments: arguments,
                                                          environment: ProcessInfo.processInfo.environment,
                                                          timeout: timeout)
            done.fulfill()
        }
        wait(for: [done], timeout: deadline)
        return result
    }

    // A command that floods stdout stops at the 1 MiB cap instead of
    // running until the timeout.
    func test_runCommand_floodingCommandStopsAtCap() {
        let data = runCommandOffMain(arguments: ["-c", "/usr/bin/yes"],
                                     timeout: 35,
                                     deadline: 30)
        XCTAssertEqual(data?.count, 1024 * 1024)
    }

    // The timeout kills the whole command, including a child that keeps
    // stdout open after its parent dies.
    func test_runCommand_timeoutKillsChildHoldingStdout() {
        _ = runCommandOffMain(arguments: ["-c", "/bin/sleep 600; true"],
                              timeout: 1,
                              deadline: 30)
    }
}
