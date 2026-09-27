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
}
