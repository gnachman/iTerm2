//
//  ClaudeWatcherTerminationTests.swift
//  iTerm2 ModernTests
//
//  Reproduces the 3.7.1 crash cluster where ClaudeWatcher.thresholdReached()
//  offered the Claude Code upsell during app termination. When the app quits,
//  GlobalJobMonitor posts a storm of "claude" job-change notifications as each
//  session tears down; the watcher saw >= threshold sessions and offered the
//  upsell to sessions that were mid-teardown, which trapped (SIGTRAP). It was
//  the single largest crash cluster.
//
//  These tests drive the notification -> threshold -> offer path with injected
//  seams so no live controller, sessions, or UI are needed.
//

import XCTest
@testable import iTerm2SharedARC

final class ClaudeWatcherTerminationTests: XCTestCase {
    private func makeWatcher(exited: @escaping (String) -> Bool? = { _ in false },
                             offered: @escaping (String) -> Void) -> ClaudeWatcher {
        // seedFromJobMonitor: false so we don't spin up the real GlobalJobMonitor
        // (which would start observing live sessions). bypassEnabledCheck: true so
        // the watcher installs its observers regardless of user defaults.
        return ClaudeWatcher(threshold: 3,
                             seedFromJobMonitor: false,
                             bypassEnabledCheck: true,
                             sessionExitedProvider: exited,
                             offerOverride: offered)!
    }

    private func postClaudeChange(_ guids: Set<String>) {
        NotificationCenter.default.post(
            name: GlobalJobMonitor.didChangeNotification,
            object: nil,
            userInfo: [
                GlobalJobMonitor.jobNameKey: "claude",
                GlobalJobMonitor.sessionGUIDsKey: guids
            ])
    }

    // MARK: - Pure eligibility predicate

    func testShouldOffer_truthTable() {
        // Terminating suppresses the offer regardless of session state.
        XCTAssertFalse(ClaudeWatcher.shouldOffer(isTerminating: true, sessionExited: false))
        XCTAssertFalse(ClaudeWatcher.shouldOffer(isTerminating: true, sessionExited: true))
        XCTAssertFalse(ClaudeWatcher.shouldOffer(isTerminating: true, sessionExited: nil))

        // Not terminating: a missing or exited session is skipped; only a live
        // (not-exited) session is eligible.
        XCTAssertFalse(ClaudeWatcher.shouldOffer(isTerminating: false, sessionExited: nil))
        XCTAssertFalse(ClaudeWatcher.shouldOffer(isTerminating: false, sessionExited: true))
        XCTAssertTrue(ClaudeWatcher.shouldOffer(isTerminating: false, sessionExited: false))
    }

    // MARK: - End-to-end notification path

    func testThresholdOffersWhenNotTerminating() {
        var offered = Set<String>()
        let watcher = makeWatcher(offered: { offered.insert($0) })
        withExtendedLifetime(watcher) {
            postClaudeChange(["a", "b", "c"])
        }
        XCTAssertEqual(offered, ["a", "b", "c"])
    }

    // This is the crash repro: the same threshold-crossing notification that
    // fired during quit must NOT produce an offer once termination has begun.
    func testNoOfferAfterApplicationWillTerminate() {
        var offered = Set<String>()
        let watcher = makeWatcher(offered: { offered.insert($0) })
        withExtendedLifetime(watcher) {
            // Simulate the applicationShouldTerminate broadcast that precedes
            // the window-close cascade.
            NotificationCenter.default.post(
                name: Notification.Name(iTermApplicationWillTerminate),
                object: nil)
            // The teardown storm delivers a >= threshold "claude" change.
            postClaudeChange(["a", "b", "c"])
        }
        XCTAssertTrue(offered.isEmpty,
                      "ClaudeWatcher must not offer the upsell during termination")
    }

    func testExitedSessionsAreSkipped() {
        var offered = Set<String>()
        let watcher = makeWatcher(exited: { guid in guid == "b" ? true : false },
                                  offered: { offered.insert($0) })
        withExtendedLifetime(watcher) {
            postClaudeChange(["a", "b", "c"])
        }
        XCTAssertEqual(offered, ["a", "c"])
    }

    func testMissingSessionsAreSkipped() {
        var offered = Set<String>()
        // nil = no live session for that GUID.
        let watcher = makeWatcher(exited: { guid in guid == "b" ? nil : false },
                                  offered: { offered.insert($0) })
        withExtendedLifetime(watcher) {
            postClaudeChange(["a", "b", "c"])
        }
        XCTAssertEqual(offered, ["a", "c"])
    }

    func testBelowThresholdDoesNotOffer() {
        var offered = Set<String>()
        let watcher = makeWatcher(offered: { offered.insert($0) })
        withExtendedLifetime(watcher) {
            postClaudeChange(["a", "b"])
        }
        XCTAssertTrue(offered.isEmpty)
    }
}
