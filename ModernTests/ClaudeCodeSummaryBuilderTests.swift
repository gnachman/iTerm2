//
//  ClaudeCodeSummaryBuilderTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

final class ClaudeCodeSummaryBuilderTests: XCTestCase {

    // MARK: - Helpers

    private func makeStatus(_ text: String, id: String = UUID().uuidString) -> iTermSessionTabStatus {
        let s = iTermSessionTabStatus(sessionID: id)
        s.statusText = text
        return s
    }

    // MARK: - isClaudeCodeStatus

    func testIsClaudeCodeStatus_waiting() {
        XCTAssertTrue(ClaudeCodeSummaryBuilder.isClaudeCodeStatus("Waiting"))
    }

    func testIsClaudeCodeStatus_working() {
        XCTAssertTrue(ClaudeCodeSummaryBuilder.isClaudeCodeStatus("Working\u{2026}"))
    }

    func testIsClaudeCodeStatus_idle() {
        XCTAssertTrue(ClaudeCodeSummaryBuilder.isClaudeCodeStatus("Idle"))
    }

    func testIsClaudeCodeStatus_nil() {
        XCTAssertFalse(ClaudeCodeSummaryBuilder.isClaudeCodeStatus(nil))
    }

    func testIsClaudeCodeStatus_emptyString() {
        XCTAssertFalse(ClaudeCodeSummaryBuilder.isClaudeCodeStatus(""))
    }

    func testIsClaudeCodeStatus_unrelatedStatus() {
        XCTAssertFalse(ClaudeCodeSummaryBuilder.isClaudeCodeStatus("Running"))
    }

    func testIsClaudeCodeStatus_partialMatch() {
        // "Waiting" must match exactly — a prefix should not pass.
        XCTAssertFalse(ClaudeCodeSummaryBuilder.isClaudeCodeStatus("Wait"))
    }

    func testIsClaudeCodeStatus_wrongEllipsis() {
        // Three ASCII dots are not the Unicode ellipsis character used in "Working…".
        XCTAssertFalse(ClaudeCodeSummaryBuilder.isClaudeCodeStatus("Working..."))
    }

    // MARK: - buildSummary — empty

    func testBuildSummary_empty() {
        XCTAssertEqual(ClaudeCodeSummaryBuilder.buildSummary(from: []), "No sessions")
    }

    // MARK: - buildSummary — single counts (singular form)

    func testBuildSummary_oneWaiting() {
        let sessions = [makeStatus("Waiting")]
        XCTAssertEqual(ClaudeCodeSummaryBuilder.buildSummary(from: sessions), "1 waiting")
    }

    func testBuildSummary_oneWorking() {
        let sessions = [makeStatus("Working\u{2026}")]
        XCTAssertEqual(ClaudeCodeSummaryBuilder.buildSummary(from: sessions), "1 working")
    }

    func testBuildSummary_oneIdle() {
        let sessions = [makeStatus("Idle")]
        XCTAssertEqual(ClaudeCodeSummaryBuilder.buildSummary(from: sessions), "1 idle")
    }

    // MARK: - buildSummary — plural counts

    func testBuildSummary_twoWaiting() {
        let sessions = [makeStatus("Waiting"), makeStatus("Waiting")]
        XCTAssertEqual(ClaudeCodeSummaryBuilder.buildSummary(from: sessions), "2 waiting")
    }

    func testBuildSummary_twoWorking() {
        let sessions = [makeStatus("Working\u{2026}"), makeStatus("Working\u{2026}")]
        XCTAssertEqual(ClaudeCodeSummaryBuilder.buildSummary(from: sessions), "2 working")
    }

    func testBuildSummary_twoIdle() {
        let sessions = [makeStatus("Idle"), makeStatus("Idle")]
        XCTAssertEqual(ClaudeCodeSummaryBuilder.buildSummary(from: sessions), "2 idle")
    }

    // MARK: - buildSummary — mixed states (ordering: waiting, working, idle)

    func testBuildSummary_waitingAndWorking() {
        let sessions = [makeStatus("Waiting"), makeStatus("Working\u{2026}")]
        XCTAssertEqual(ClaudeCodeSummaryBuilder.buildSummary(from: sessions), "1 waiting, 1 working")
    }

    func testBuildSummary_waitingAndIdle() {
        let sessions = [makeStatus("Waiting"), makeStatus("Idle")]
        XCTAssertEqual(ClaudeCodeSummaryBuilder.buildSummary(from: sessions), "1 waiting, 1 idle")
    }

    func testBuildSummary_workingAndIdle() {
        let sessions = [makeStatus("Working\u{2026}"), makeStatus("Idle")]
        XCTAssertEqual(ClaudeCodeSummaryBuilder.buildSummary(from: sessions), "1 working, 1 idle")
    }

    func testBuildSummary_allThreeStates() {
        let sessions = [
            makeStatus("Waiting"),
            makeStatus("Working\u{2026}"),
            makeStatus("Idle"),
        ]
        XCTAssertEqual(ClaudeCodeSummaryBuilder.buildSummary(from: sessions), "1 waiting, 1 working, 1 idle")
    }

    func testBuildSummary_multipleOfEachState() {
        let sessions = [
            makeStatus("Waiting"), makeStatus("Waiting"),
            makeStatus("Working\u{2026}"),
            makeStatus("Idle"), makeStatus("Idle"), makeStatus("Idle"),
        ]
        XCTAssertEqual(ClaudeCodeSummaryBuilder.buildSummary(from: sessions), "2 waiting, 1 working, 3 idle")
    }

    // MARK: - buildSummary — exemplar from the status bar (regression guard)

    func testBuildSummary_exemplarString() {
        // The exemplar shown in statusBarComponentExemplar is "2 waiting, 1 working".
        // This test guards against regressions that would silently change the format.
        let sessions = [makeStatus("Waiting"), makeStatus("Waiting"), makeStatus("Working\u{2026}")]
        XCTAssertEqual(ClaudeCodeSummaryBuilder.buildSummary(from: sessions), "2 waiting, 1 working")
    }
}
