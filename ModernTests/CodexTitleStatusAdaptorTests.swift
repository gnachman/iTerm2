//
//  CodexTitleStatusAdaptorTests.swift
//  ModernTests
//
//  Verifies the foreground-ancestry gate matches Codex regardless of
//  install method (brew, npm/npx, etc.) and refuses to claim sessions
//  where no codex process is in the foreground.
//

import XCTest
@testable import iTerm2SharedARC

final class CodexTitleStatusAdaptorTests: XCTestCase {

    private func newStatus() -> iTermSessionTabStatus {
        return iTermSessionTabStatus(sessionID: "test")
    }

    // Spinner glyph captured from real Codex sessions; treated as opaque here.
    private let spinnerTitle = "⠙ project"
    private let idleTitle = "project"

    // MARK: - Foreground match

    func testBrewInstall_codexPath_matches() {
        let status = newStatus()
        let changed = CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: ["/opt/homebrew/bin/codex", "-zsh"],
            tabStatus: status)
        XCTAssertTrue(changed)
        XCTAssertEqual(status.statusText, "Working")
        XCTAssertTrue(status.hasIndicator)
    }

    func testNpmInstall_nodeWrapperAndRustChild_matches() {
        // Empirically observed npm process tree:
        //   1. Rust binary at .../codex-<platform>/.../bin/codex (deepest, has TTY)
        //   2. node ./node_modules/.bin/codex
        //   3. shell
        // iTermProcessInfo lists deepest first, lowercased.
        let status = newStatus()
        let changed = CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: [
                "/private/tmp/codex-npm-test/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex",
                "node",
                "-zsh",
            ],
            tabStatus: status)
        XCTAssertTrue(changed)
        XCTAssertEqual(status.statusText, "Working")
    }

    func testPlainCodexInPath_matches() {
        let status = newStatus()
        let changed = CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: ["codex", "-zsh"],
            tabStatus: status)
        XCTAssertTrue(changed)
        XCTAssertEqual(status.statusText, "Working")
    }

    func testNoCodexInAncestors_noChange() {
        let status = newStatus()
        let changed = CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: ["node", "-zsh"],
            tabStatus: status)
        XCTAssertFalse(changed)
        XCTAssertNil(status.statusText)
        XCTAssertFalse(status.hasIndicator)
    }

    func testNilAncestors_noChange() {
        let status = newStatus()
        let changed = CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: nil,
            tabStatus: status)
        XCTAssertFalse(changed)
    }

    func testCodexAsSubstring_doesNotMatch() {
        // Only the last path component counts; "codex-ish" must not match.
        let status = newStatus()
        let changed = CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: ["/usr/local/bin/codex-ish", "node", "-zsh"],
            tabStatus: status)
        XCTAssertFalse(changed)
    }

    // MARK: - Title-driven state transitions

    func testCodexForeground_idleTitle_setsIdle() {
        let status = newStatus()
        CodexTitleStatusAdaptor.apply(
            title: idleTitle,
            ancestorJobNames: ["codex", "-zsh"],
            tabStatus: status)
        XCTAssertEqual(status.statusText, "Idle")
        XCTAssertTrue(status.hasIndicator)
    }

    func testWorkingThenCodexExits_clearsState() {
        let status = newStatus()
        CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: ["codex", "-zsh"],
            tabStatus: status)
        XCTAssertEqual(status.statusText, "Working")

        // Codex left the foreground; shim should clear what it owned.
        CodexTitleStatusAdaptor.apply(
            title: idleTitle,
            ancestorJobNames: ["-zsh"],
            tabStatus: status)
        XCTAssertNil(status.statusText)
        XCTAssertFalse(status.hasIndicator)
    }

    func testWorkingThenIdle_titleDrivenTransition() {
        let status = newStatus()
        CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: ["codex", "-zsh"],
            tabStatus: status)
        XCTAssertEqual(status.statusText, "Working")

        // Codex still in foreground but title lost its spinner prefix.
        CodexTitleStatusAdaptor.apply(
            title: idleTitle,
            ancestorJobNames: ["codex", "-zsh"],
            tabStatus: status)
        XCTAssertEqual(status.statusText, "Idle")
    }

    // MARK: - Coexistence with real OSC 21337 emitters

    func testRealOSCEmitter_wins_overSynthesizedState() {
        // A real OSC 21337 emitter wrote a status before codex started.
        // The shim must not stomp on it.
        let status = newStatus()
        let update = VT100TabStatusUpdate()
        update.indicatorPresence = .set
        update.indicator = iTermSRGBColor(r: 1, g: 0, b: 0)
        update.statusPresence = .set
        update.status = "RealStatus"
        XCTAssertTrue(status.apply(update))

        let changed = CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: ["codex", "-zsh"],
            tabStatus: status)
        XCTAssertFalse(changed)
        XCTAssertEqual(status.statusText, "RealStatus")
    }
}
