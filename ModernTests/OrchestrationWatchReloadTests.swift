//
//  OrchestrationWatchReloadTests.swift
//  iTerm2 ModernTests
//
//  Covers the gap that made an orchestration watch die silently when its
//  watched session reloaded in place (e.g. a Claude Code "Code Review" peer
//  restarting). A shell reload rotates the session's guid via
//  replaceTerminatedShellWithNewInstance but keeps its stableID. Watchers used
//  to be keyed on the rotating guid, so after a reload the stored key went
//  stale, the session no longer resolved, and the watch neither fired nor was
//  dropped. The fix keys watchers on the reload-durable stableID
//  (OrchestratorDispatcher.watcherKey) and matches through
//  WorkgroupWatcher.targets(stableID:guid:), which compares against both ids.
//
//  These drive a real PTYSession and rotate its guid the same way a reload
//  does (setGuid: via KVC, as PTYSessionStableIDTests does), so they exercise
//  the actual identity behavior rather than a mock.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class OrchestrationWatchReloadTests: XCTestCase {
    private func watcher(key: String, targetState: SessionState = .idle) -> WorkgroupWatcher {
        WorkgroupWatcher(watcherID: UUID().uuidString,
                         sessionGUID: key,
                         workgroupID: "wg-test",
                         workgroupName: "WG",
                         roleID: "builtin.claudeCode.review",
                         roleName: "Code Review",
                         targetState: targetState,
                         registeredAt: Date())
    }

    // Simulate an in-place shell reload: the guid rotates, the stableID does not.
    private func reload(_ session: PTYSession) {
        session.setValue(UUID().uuidString, forKey: "guid")
    }

    // The store-side key must be the reload-durable stableID, not the guid, and
    // it must not change across a reload. If this reverts to session.guid, the
    // watch-dies-on-reload bug is back.
    func test_watcherKey_isStableID_andSurvivesReload() {
        let s = PTYSession(synthetic: false)!
        let key = OrchestratorDispatcher.watcherKey(for: s)
        XCTAssertEqual(key, s.stableID)
        XCTAssertNotEqual(key, s.guid)

        let oldGuid = s.guid
        reload(s)
        XCTAssertNotEqual(s.guid, oldGuid, "the reload should have rotated the guid")
        XCTAssertEqual(OrchestratorDispatcher.watcherKey(for: s), key,
                       "the watcher key must be stable across a reload")
    }

    // The gap: a watcher keyed on the stableID keeps matching its session after
    // a reload rotates the guid, so its screen poller / tab-status match follows
    // the reloaded session instead of being stranded.
    func test_stableIDKeyedWatcher_followsSessionAcrossReload() {
        let s = PTYSession(synthetic: false)!
        let w = watcher(key: OrchestratorDispatcher.watcherKey(for: s))  // keyed on stableID
        XCTAssertTrue(w.targets(stableID: s.stableID, guid: s.guid),
                      "should match its session before the reload")
        reload(s)
        XCTAssertTrue(w.targets(stableID: s.stableID, guid: s.guid),
                      "a stableID-keyed watcher must still match after the reload")
    }

    // The bug this fix closes: a watcher keyed on the raw guid is orphaned once
    // the guid rotates, which is why the watch died silently for hours.
    func test_legacyGuidKeyedWatcher_isOrphanedByReload() {
        let s = PTYSession(synthetic: false)!
        let w = watcher(key: s.guid)  // legacy keying on the rotating guid
        XCTAssertTrue(w.targets(stableID: s.stableID, guid: s.guid),
                      "should match its session before the reload")
        reload(s)
        XCTAssertFalse(w.targets(stableID: s.stableID, guid: s.guid),
                       "a guid-keyed watcher no longer matches once the guid rotates")
    }

    // targets() matches on either id and falls back to the guid when the
    // session can't be resolved (stableID passed as nil). String comparison
    // only, so the tokens here need not be well-formed ids.
    func test_targets_matchesEitherIdAndFallsBackToGuid() {
        let onStable = watcher(key: "ptys_STABLEKEY01")
        XCTAssertTrue(onStable.targets(stableID: "ptys_STABLEKEY01", guid: "G1"))
        XCTAssertFalse(onStable.targets(stableID: "ptys_OTHERKEY002", guid: "G1"))
        XCTAssertFalse(onStable.targets(stableID: nil, guid: "G1"),
                       "an unresolved session (nil stableID) must not match on the guid it isn't keyed to")

        let onGuid = watcher(key: "G1")
        XCTAssertTrue(onGuid.targets(stableID: "ptys_STABLEKEY01", guid: "G1"),
                      "a legacy guid-keyed watcher matches by guid")
        XCTAssertFalse(onGuid.targets(stableID: "ptys_STABLEKEY01", guid: "G2"))
        XCTAssertTrue(onGuid.targets(stableID: nil, guid: "G1"),
                      "falls back to the guid when the session can't be resolved")
    }
}
