//
//  WorkgroupAutoSendClippingsTests.swift
//  ModernTests
//
//  Covers the "Auto-Send Clippings When Idle" code-review toolbar toggle:
//  clipping formatting, the toolbar-item model (Codable + registry), its
//  presence in the Claude Code preset, the one-time backfill that adds it to
//  existing installs, and the pure working -> idle send decision.
//

import XCTest
@testable import iTerm2SharedARC

final class WorkgroupAutoSendClippingsTests: XCTestCase {

    // MARK: - Clipping formatting

    func test_formattedForSending_titleAndDetail() {
        let c = PTYSessionClipping(type: "note", title: "Bug", detail: "line 5")
        XCTAssertEqual(c.formattedForSending, "**Bug**\nline 5")
    }

    func test_formattedForSending_blankTitleFallsBackToDetailOnly() {
        let c = PTYSessionClipping(type: "note", title: "   ", detail: "just detail")
        XCTAssertEqual(c.formattedForSending, "just detail")
    }

    func test_joinedForSending_singleEqualsFormatted() {
        let c = PTYSessionClipping(type: "note", title: "T", detail: "D")
        XCTAssertEqual([c].joinedForSending(), c.formattedForSending)
    }

    func test_joinedForSending_multipleContainsEach() {
        let a = PTYSessionClipping(type: "note", title: "A", detail: "aa")
        let b = PTYSessionClipping(type: "note", title: "B", detail: "bb")
        let joined = [a, b].joinedForSending()
        XCTAssertTrue(joined.contains(a.formattedForSending))
        XCTAssertTrue(joined.contains(b.formattedForSending))
    }

    // MARK: - Toolbar item model

    func test_toolbarItem_codableRoundTrip() throws {
        let original: iTermWorkgroupToolbarItem = .autoSendClippingsWhenIdle
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(iTermWorkgroupToolbarItem.self,
                                               from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.kind, .autoSendClippingsWhenIdle)
    }

    // Survives a full workgroup encode/decode (the shape persisted to user
    // defaults), not just a bare enum round-trip.
    func test_toolbarItem_survivesWorkgroupRoundTrip() throws {
        let root = iTermWorkgroupSessionConfig(
            uniqueIdentifier: "root", parentID: nil, kind: .root,
            profileGUID: nil, command: "", urlString: "",
            toolbarItems: [], displayName: "Main")
        let review = iTermWorkgroupSessionConfig(
            uniqueIdentifier: "review", parentID: "root", kind: .peer,
            profileGUID: nil, command: "claude", urlString: "",
            toolbarItems: [.modeSwitcher, .autoSendClippingsWhenIdle],
            displayName: "Code Review", mode: .codeReview)
        let wg = iTermWorkgroup(uniqueIdentifier: "wg", name: "WG",
                                sessions: [root, review])
        let data = try JSONEncoder().encode([wg])
        let decoded = try JSONDecoder().decode([iTermWorkgroup].self, from: data)
        let decodedReview = decoded.first?.session(withUniqueIdentifier: "review")
        XCTAssertEqual(decodedReview?.toolbarItems.contains(.autoSendClippingsWhenIdle),
                       true)
    }

    func test_registry_includesItem() {
        let metadata = iTermWorkgroupToolbarItemRegistry.metadata(
            forKind: .autoSendClippingsWhenIdle)
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.hasParameters, false)
        XCTAssertEqual(metadata?.defaultValue, .autoSendClippingsWhenIdle)
        XCTAssertTrue(iTermWorkgroupToolbarItemRegistry.all.contains {
            $0.kind == .autoSendClippingsWhenIdle
        })
    }

    // injectAutoItems strips stranded companions (.navigation without a
    // changedFileSelector, etc.); the toggle is self-contained and must
    // never be dropped.
    func test_injectAutoItems_keepsToggle() {
        let injected = WorkgroupToolbarBuilder.injectAutoItems(
            into: [.modeSwitcher, .reload(nil), .autoSendClippingsWhenIdle])
        XCTAssertTrue(injected.contains(.autoSendClippingsWhenIdle))
    }

    // MARK: - Preset

    func test_preset_reviewPeerIncludesToggleByDefault() {
        let wg = WorkgroupPresets.buildCodingAgentPlusDiffPlusCodeReview()
        let review = wg.sessions.first { $0.mode == .codeReview }
        XCTAssertNotNil(review)
        XCTAssertTrue(review!.toolbarItems.contains(.autoSendClippingsWhenIdle),
                      "Code Review peer should ship with the toggle by default")
    }

    func test_claudeCodeTemplate_reviewPeerIncludesToggle() {
        let review = ClaudeCodeWorkgroupTemplate.config.session(
            withUniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.review)
        XCTAssertNotNil(review)
        XCTAssertTrue(review!.toolbarItems.contains(.autoSendClippingsWhenIdle))
    }

    // MARK: - Backfill transform

    // Builds a Claude Code workgroup whose review peer lacks the toggle, as an
    // install predating the feature would have persisted it.
    private func legacyClaudeCodeWorkgroup(
        reviewItems: [iTermWorkgroupToolbarItem] = [.modeSwitcher, .reload(nil)]
    ) -> iTermWorkgroup {
        let root = iTermWorkgroupSessionConfig(
            uniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.main,
            parentID: nil, kind: .root, profileGUID: nil, command: "",
            urlString: "", toolbarItems: [.modeSwitcher], displayName: "Chat")
        let review = iTermWorkgroupSessionConfig(
            uniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.review,
            parentID: ClaudeCodeWorkgroupTemplate.ID.main, kind: .peer,
            profileGUID: nil, command: "claude", urlString: "",
            toolbarItems: reviewItems, displayName: "Code Review",
            mode: .codeReview)
        return iTermWorkgroup(
            uniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.workgroup,
            name: "Claude Code", sessions: [root, review])
    }

    func test_backfill_addsToggleToLegacyReviewPeer() {
        let migrated = iTermWorkgroupModel
            .addingAutoSendClippingsToClaudeCodeReviewPeer([legacyClaudeCodeWorkgroup()])
        XCTAssertNotNil(migrated, "Backfill should report a change")
        let review = migrated?.first?.session(
            withUniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.review)
        XCTAssertEqual(review?.toolbarItems.contains(.autoSendClippingsWhenIdle),
                       true)
        // Existing items are preserved and the new one is appended last.
        XCTAssertEqual(review?.toolbarItems.last, .autoSendClippingsWhenIdle)
        XCTAssertEqual(review?.toolbarItems.first, .modeSwitcher)
    }

    func test_backfill_idempotentWhenAlreadyPresent() {
        let wg = legacyClaudeCodeWorkgroup(
            reviewItems: [.modeSwitcher, .autoSendClippingsWhenIdle])
        XCTAssertNil(
            iTermWorkgroupModel.addingAutoSendClippingsToClaudeCodeReviewPeer([wg]),
            "No change expected when the toggle is already present")
    }

    func test_backfill_ignoresNonClaudeCodeWorkgroup() {
        // Same review peer ID but a different workgroup ID: out of scope.
        var wg = legacyClaudeCodeWorkgroup()
        wg = iTermWorkgroup(uniqueIdentifier: "some-other-workgroup",
                            name: wg.name, sessions: wg.sessions)
        XCTAssertNil(
            iTermWorkgroupModel.addingAutoSendClippingsToClaudeCodeReviewPeer([wg]),
            "Only the Claude Code workgroup's review peer is in scope")
    }

    func test_backfill_ignoresNonReviewPeer() {
        // Claude Code workgroup, but no session with the review peer ID.
        let root = iTermWorkgroupSessionConfig(
            uniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.main,
            parentID: nil, kind: .root, profileGUID: nil, command: "",
            urlString: "", toolbarItems: [.modeSwitcher], displayName: "Chat")
        let wg = iTermWorkgroup(
            uniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.workgroup,
            name: "Claude Code", sessions: [root])
        XCTAssertNil(
            iTermWorkgroupModel.addingAutoSendClippingsToClaudeCodeReviewPeer([wg]))
    }

    // MARK: - Auto-send decision

    private let oneClipping = [PTYSessionClipping(type: "n", title: "T", detail: "D")]

    func test_decision_firesOnWorkingToIdle() {
        let text = iTermWorkgroupPeerPort.clippingsToAutoSend(
            previousState: .working, newState: .idle,
            mode: .codeReview, toggleOn: true, mainSessionState: .idle,
            clippings: oneClipping)
        XCTAssertEqual(text, oneClipping.joinedForSending())
    }

    func test_decision_noFireWhenNotEdgeFromWorking() {
        // idle -> idle, unknown -> idle, and nil -> idle are all non-edges.
        for previous: SessionState? in [.idle, .waiting, .unknown, nil] {
            XCTAssertNil(iTermWorkgroupPeerPort.clippingsToAutoSend(
                previousState: previous, newState: .idle,
                mode: .codeReview, toggleOn: true, mainSessionState: .idle,
                clippings: oneClipping),
                "previous=\(String(describing: previous)) must not fire")
        }
    }

    func test_decision_noFireWhenNewStateNotIdle() {
        XCTAssertNil(iTermWorkgroupPeerPort.clippingsToAutoSend(
            previousState: .working, newState: .working,
            mode: .codeReview, toggleOn: true, mainSessionState: .idle,
            clippings: oneClipping))
    }

    func test_decision_noFireWhenToggleOff() {
        XCTAssertNil(iTermWorkgroupPeerPort.clippingsToAutoSend(
            previousState: .working, newState: .idle,
            mode: .codeReview, toggleOn: false, mainSessionState: .idle,
            clippings: oneClipping))
    }

    func test_decision_noFireWhenNotCodeReview() {
        for mode: iTermWorkgroupSessionMode in [.regular, .diff] {
            XCTAssertNil(iTermWorkgroupPeerPort.clippingsToAutoSend(
                previousState: .working, newState: .idle,
                mode: mode, toggleOn: true, mainSessionState: .idle,
                clippings: oneClipping),
                "mode=\(mode) must not fire")
        }
    }

    func test_decision_noFireWhenNoClippings() {
        XCTAssertNil(iTermWorkgroupPeerPort.clippingsToAutoSend(
            previousState: .working, newState: .idle,
            mode: .codeReview, toggleOn: true, mainSessionState: .idle,
            clippings: []))
    }

    /// The main session being mid-turn (.working) defers the auto-send so an
    /// autonomous paste + submit never clobbers the agent's in-progress input.
    /// idle / waiting / unknown all proceed.
    func test_decision_noFireWhenMainSessionWorking() {
        XCTAssertNil(iTermWorkgroupPeerPort.clippingsToAutoSend(
            previousState: .working, newState: .idle,
            mode: .codeReview, toggleOn: true, mainSessionState: .working,
            clippings: oneClipping),
            "must not inject while the main session's agent is working")
        for mainState: SessionState in [.idle, .waiting, .unknown] {
            XCTAssertNotNil(iTermWorkgroupPeerPort.clippingsToAutoSend(
                previousState: .working, newState: .idle,
                mode: .codeReview, toggleOn: true, mainSessionState: mainState,
                clippings: oneClipping),
                "mainState=\(mainState) is safe to send into")
        }
    }
}
