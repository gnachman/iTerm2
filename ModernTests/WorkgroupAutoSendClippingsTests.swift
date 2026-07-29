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

    // MARK: - Auto-request review: toolbar model

    func test_requestReviewItem_codableRoundTrip() throws {
        let original: iTermWorkgroupToolbarItem = .autoRequestReviewWhenIdle
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(iTermWorkgroupToolbarItem.self,
                                               from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.kind, .autoRequestReviewWhenIdle)
    }

    func test_requestReviewItem_registryIncludesItem() {
        let metadata = iTermWorkgroupToolbarItemRegistry.metadata(
            forKind: .autoRequestReviewWhenIdle)
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.hasParameters, false)
        XCTAssertEqual(metadata?.defaultValue, .autoRequestReviewWhenIdle)
    }

    func test_requestReviewItem_presetMainSessionIncludesItByDefault() {
        let wg = WorkgroupPresets.buildCodingAgentPlusDiffPlusCodeReview()
        XCTAssertEqual(wg.root?.toolbarItems.contains(.autoRequestReviewWhenIdle),
                       true,
                       "Main (root) session should ship with the toggle by default")
    }

    func test_requestReviewItem_claudeCodeTemplateMainSessionIncludesIt() {
        let main = ClaudeCodeWorkgroupTemplate.config.session(
            withUniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.main)
        XCTAssertNotNil(main)
        XCTAssertTrue(main!.toolbarItems.contains(.autoRequestReviewWhenIdle))
    }

    // MARK: - Auto-request review: backfill transform

    private func legacyClaudeCodeWorkgroupMissingRequestReview()
        -> iTermWorkgroup {
        let main = iTermWorkgroupSessionConfig(
            uniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.main,
            parentID: nil, kind: .root, profileGUID: nil, command: "",
            urlString: "", toolbarItems: [.modeSwitcher, .gitStatus],
            displayName: "Chat")
        let review = iTermWorkgroupSessionConfig(
            uniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.review,
            parentID: ClaudeCodeWorkgroupTemplate.ID.main, kind: .peer,
            profileGUID: nil, command: "claude", urlString: "",
            toolbarItems: [.modeSwitcher], displayName: "Code Review",
            mode: .codeReview)
        return iTermWorkgroup(
            uniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.workgroup,
            name: "Claude Code", sessions: [main, review])
    }

    func test_requestReviewBackfill_addsToLegacyMainSession() {
        let migrated = iTermWorkgroupModel
            .addingAutoRequestReviewToClaudeCodeMainSession(
                [legacyClaudeCodeWorkgroupMissingRequestReview()])
        XCTAssertNotNil(migrated)
        let main = migrated?.first?.session(
            withUniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.main)
        XCTAssertEqual(main?.toolbarItems.last, .autoRequestReviewWhenIdle)
        XCTAssertEqual(main?.toolbarItems.first, .modeSwitcher)
    }

    func test_requestReviewBackfill_idempotentWhenAlreadyPresent() {
        var wg = legacyClaudeCodeWorkgroupMissingRequestReview()
        var main = wg.sessions[0]
        main.toolbarItems = main.toolbarItems + [.autoRequestReviewWhenIdle]
        wg = iTermWorkgroup(uniqueIdentifier: wg.uniqueIdentifier,
                            name: wg.name, sessions: [main, wg.sessions[1]])
        XCTAssertNil(
            iTermWorkgroupModel.addingAutoRequestReviewToClaudeCodeMainSession([wg]))
    }

    func test_requestReviewBackfill_ignoresNonClaudeCodeWorkgroup() {
        var wg = legacyClaudeCodeWorkgroupMissingRequestReview()
        wg = iTermWorkgroup(uniqueIdentifier: "other-workgroup",
                            name: wg.name, sessions: wg.sessions)
        XCTAssertNil(
            iTermWorkgroupModel.addingAutoRequestReviewToClaudeCodeMainSession([wg]))
    }

    // MARK: - Auto-request review: decision

    func test_requestReviewDecision_firesForMainOnWorkingToIdle() {
        XCTAssertTrue(iTermWorkgroupPeerPort.shouldAutoRequestReview(
            previousState: .working, newState: .idle,
            isMainSession: true, toggleOn: true, reviewCount: 1))
    }

    func test_requestReviewDecision_noFireWhenNotMainSession() {
        XCTAssertFalse(iTermWorkgroupPeerPort.shouldAutoRequestReview(
            previousState: .working, newState: .idle,
            isMainSession: false, toggleOn: true, reviewCount: 1))
    }

    func test_requestReviewDecision_noFireWhenToggleOff() {
        XCTAssertFalse(iTermWorkgroupPeerPort.shouldAutoRequestReview(
            previousState: .working, newState: .idle,
            isMainSession: true, toggleOn: false, reviewCount: 1))
    }

    func test_requestReviewDecision_noFireWhenNotExactlyOneReview() {
        for count in [0, 2, 3] {
            XCTAssertFalse(iTermWorkgroupPeerPort.shouldAutoRequestReview(
                previousState: .working, newState: .idle,
                isMainSession: true, toggleOn: true, reviewCount: count),
                "reviewCount=\(count) must not fire")
        }
    }

    func test_requestReviewDecision_noFireWhenNotEdgeFromWorking() {
        for previous: SessionState? in [.idle, .waiting, .unknown, nil] {
            XCTAssertFalse(iTermWorkgroupPeerPort.shouldAutoRequestReview(
                previousState: previous, newState: .idle,
                isMainSession: true, toggleOn: true, reviewCount: 1),
                "previous=\(String(describing: previous)) must not fire")
        }
    }

    func test_requestReviewDecision_noFireWhenNewStateNotIdle() {
        XCTAssertFalse(iTermWorkgroupPeerPort.shouldAutoRequestReview(
            previousState: .working, newState: .working,
            isMainSession: true, toggleOn: true, reviewCount: 1))
    }

    // MARK: - Arrangement save/restore of the toggle flags

    // The arrangement keys are private statics in PTYSession.m; the tests
    // reference them by their literal string values (kept in sync there).
    private let autoSendKey = "Auto Send Clippings When Idle"
    private let autoRequestKey = "Auto Request Review When Idle"

    private func encodedArrangement(_ session: PTYSession) -> [AnyHashable: Any] {
        let encoder = iTermMutableDictionaryEncoderAdapter.encoder()
        session.encodeArrangement(withContents: false, encoder: encoder)
        return encoder.mutableDictionary as? [AnyHashable: Any] ?? [:]
    }

    func test_arrangement_encodesFlagsWhenOn() {
        let session = PTYSession(synthetic: false)!
        session.autoSendClippingsWhenIdle = true
        session.autoRequestReviewWhenIdle = true
        let dict = encodedArrangement(session)
        XCTAssertEqual(dict[autoSendKey] as? Bool, true)
        XCTAssertEqual(dict[autoRequestKey] as? Bool, true)
    }

    // Off is the default, so the keys are omitted to keep arrangements lean.
    func test_arrangement_omitsFlagsWhenOff() {
        let session = PTYSession(synthetic: false)!
        let dict = encodedArrangement(session)
        XCTAssertNil(dict[autoSendKey])
        XCTAssertNil(dict[autoRequestKey])
    }

    // MARK: - Strict reported-idle (loop / restart race)

    private func tabStatus(sessionID: String, statusText: String?) -> iTermSessionTabStatus {
        let status = iTermSessionTabStatus(sessionID: sessionID)
        if let statusText {
            let update = VT100TabStatusUpdate()
            update.statusPresence = .set
            update.status = statusText
            _ = status.apply(update)
        }
        return status
    }

    // A restart clears the tab status. The general state falls back to .idle,
    // which is what made a restart look like a "review finished" edge; the
    // strict reported state returns .unknown so no working -> idle edge fires.
    @MainActor
    func test_reportedState_clearedStatusIsUnknownNotIdle() {
        let status = tabStatus(sessionID: "s", statusText: nil)
        XCTAssertEqual(WorkgroupIntrospection.state(forTabStatus: status), .idle)
        XCTAssertEqual(WorkgroupIntrospection.reportedState(forTabStatus: status), .unknown)
    }

    @MainActor
    func test_reportedState_readsExplicitStatusText() {
        let cases: [(String, SessionState)] = [
            ("idle", .idle), ("working", .working), ("waiting", .waiting)]
        for (text, expected) in cases {
            let status = tabStatus(sessionID: "s", statusText: text)
            XCTAssertEqual(WorkgroupIntrospection.reportedState(forTabStatus: status),
                           expected, "text=\(text)")
        }
    }

    // The restart-induced sequence working -> (cleared) is .working -> .unknown
    // under the strict state, which is NOT the working -> idle edge, so neither
    // auto behavior fires on a restart.
    func test_decision_restartClearIsNotAWorkingToIdleEdge() {
        XCTAssertNil(iTermWorkgroupPeerPort.clippingsToAutoSend(
            previousState: .working, newState: .unknown,
            mode: .codeReview, toggleOn: true, mainSessionState: .idle, clippings: oneClipping))
        XCTAssertFalse(iTermWorkgroupPeerPort.shouldAutoRequestReview(
            previousState: .working, newState: .unknown,
            isMainSession: true, toggleOn: true, reviewCount: 1))
    }
}
