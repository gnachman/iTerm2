//
//  AITabTitleGeneratorTests.swift
//  iTerm2 ModernTests
//
//  Unit tests for the pure decision logic behind AI tab titles. The generator
//  itself needs the on-device model, macOS 26, and the main-run cadence, so the
//  two decisions that carry the tricky behavior are factored into pure static
//  functions - regenerationDecision (should we re-title?) and applyDecision
//  (what to do with a completed generation?) - and pinned here.
//
//  Each test corresponds to a code-review finding, noted by its [F#] tag.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class AITabTitleGeneratorTests: XCTestCase {
    private func hist(_ pairs: [(Int, Int)]) -> [NSNumber: NSNumber] {
        var d = [NSNumber: NSNumber]()
        for (k, v) in pairs {
            d[NSNumber(value: k)] = NSNumber(value: v)
        }
        return d
    }

    // MARK: - regenerationDecision

    // A screen never titled before always regenerates.
    func testFirstEverRegenerates() {
        let decision = AITabTitleGenerator.regenerationDecision(
            lastOSC: nil, lastDigest: nil, lastHistogram: nil, lastIsAlternate: nil,
            digest: 1, histogram: hist([(0, 100)]), oscTitle: "", isAlternate: false)
        XCTAssertEqual(decision, .regenerate(reason: "first"))
    }

    // Unchanged shell content is skipped (the content digest is the signal).
    func testUnchangedShellContentSkips() {
        let decision = AITabTitleGenerator.regenerationDecision(
            lastOSC: "osc", lastDigest: 42, lastHistogram: hist([(0, 100)]),
            lastIsAlternate: false, digest: 42, histogram: hist([(0, 100)]),
            oscTitle: "osc", isAlternate: false)
        XCTAssertEqual(decision, .skip)
    }

    // A colorful full-screen app (rich histogram) whose background layout barely
    // moves is skipped, even though its content churned. (A monochrome histogram
    // is handled by the low-entropy path instead - see the tests.)
    func testUnchangedAlternateFrameSkips() {
        let decision = AITabTitleGenerator.regenerationDecision(
            lastOSC: "osc", lastDigest: 1, lastHistogram: hist([(0, 50), (1, 30), (2, 20)]),
            lastIsAlternate: true, digest: 2, histogram: hist([(0, 49), (1, 30), (2, 21)]),
            oscTitle: "osc", isAlternate: true)
        XCTAssertEqual(decision, .skip)   // distance 0.01 < 0.06 threshold
    }

    // Entering a low-color, no-OSC full-screen app from a shell must still
    // regenerate once, even though its background resembles the shell's (distance
    // under threshold) and the OSC title did not change. Without the transition
    // rule this first frame - and every later one - is skipped, so the app is
    // never titled.
    func testAlternateTransitionForcesRegeneration() {
        let shell = hist([(0, 100)])          // all default background
        let app = hist([(0, 96), (1, 4)])     // 0.04 distance, < 0.06 threshold
        let decision = AITabTitleGenerator.regenerationDecision(
            lastOSC: "shell", lastDigest: 111, lastHistogram: shell,
            lastIsAlternate: false,           // was a shell
            digest: 222, histogram: app, oscTitle: "shell",  // OSC unchanged
            isAlternate: true)                // now a full-screen app
        XCTAssertEqual(decision, .regenerate(reason: "transition"))
    }

    // The reverse transition (leaving a full-screen app back to the shell)
    // must also regenerate once.
    func testLeavingAlternateForcesRegeneration() {
        let decision = AITabTitleGenerator.regenerationDecision(
            lastOSC: "app", lastDigest: 5, lastHistogram: hist([(0, 100)]),
            lastIsAlternate: true, digest: 5, histogram: hist([(0, 100)]),
            oscTitle: "app", isAlternate: false)
        XCTAssertEqual(decision, .regenerate(reason: "transition"))
    }

    // A monochrome full-screen app (less/man/pager) has a histogram
    // dominated by the default-background bucket, so the background never moves as
    // the user pages to unrelated content. When the histogram is low-entropy, a
    // content-digest change must still re-title. (Was the "unchanged frame skips"
    // case that froze the title on the first page.)
    func testMonochromeAlternateRetitlesOnContentChange() {
        let decision = AITabTitleGenerator.regenerationDecision(
            lastOSC: "pager", lastDigest: 1, lastHistogram: hist([(0, 100)]),
            lastIsAlternate: true,
            digest: 2,                       // content changed (paged to new doc)
            histogram: hist([(0, 100)]),     // monochrome: background unchanged
            oscTitle: "pager", isAlternate: true)
        XCTAssertEqual(decision, .regenerate(reason: "frame"))
    }

    // A monochrome full-screen app whose content is ALSO unchanged still skips.
    func testMonochromeAlternateUnchangedSkips() {
        let decision = AITabTitleGenerator.regenerationDecision(
            lastOSC: "pager", lastDigest: 7, lastHistogram: hist([(0, 100)]),
            lastIsAlternate: true, digest: 7, histogram: hist([(0, 100)]),
            oscTitle: "pager", isAlternate: true)
        XCTAssertEqual(decision, .skip)
    }

    // A colorful TUI (rich histogram: status bars, panels) must keep the
    // background-only gate - its content churns every frame but that is not a task
    // change, so a changed digest with an unchanged histogram must still skip.
    func testColorfulAlternateStillGatesOnHistogram() {
        let decision = AITabTitleGenerator.regenerationDecision(
            lastOSC: "tui", lastDigest: 1, lastHistogram: hist([(0, 50), (1, 30), (2, 20)]),
            lastIsAlternate: true, digest: 2, histogram: hist([(0, 50), (1, 30), (2, 20)]),
            oscTitle: "tui", isAlternate: true)
        XCTAssertEqual(decision, .skip)
    }

    // The image bucket counts image CELLS, so a growing/streaming/zooming inline
    // image changes its fraction. It is excluded from the frame distance: a colorful
    // alt-screen whose NON-image color layout is unchanged must still skip even when the
    // image footprint grows enormously, rather than re-running the model on a task that
    // has not changed.
    func testGrowingImageDoesNotTripFrameChange() {
        let imageKey = Int(iTermTabTitleFrameFingerprint.imageBucketKey())
        let before = hist([(0, 50), (1, 30), (2, 20), (imageKey, 5)])
        let after = hist([(0, 50), (1, 30), (2, 20), (imageKey, 60)])   // image grew hugely
        let decision = AITabTitleGenerator.regenerationDecision(
            lastOSC: "tui", lastDigest: 1, lastHistogram: before,
            lastIsAlternate: true, digest: 2, histogram: after,
            oscTitle: "tui", isAlternate: true)
        XCTAssertEqual(decision, .skip,
                       "a growing inline image must not trip the frame-change fingerprint")
    }

    // But a real change to the NON-image color layout still re-titles.
    func testNonImageColorChangeStillRetitlesEvenWithImagePresent() {
        let imageKey = Int(iTermTabTitleFrameFingerprint.imageBucketKey())
        let before = hist([(0, 80), (1, 20), (imageKey, 10)])
        let after = hist([(0, 20), (1, 80), (imageKey, 10)])   // colors flipped
        let decision = AITabTitleGenerator.regenerationDecision(
            lastOSC: "tui", lastDigest: 1, lastHistogram: before,
            lastIsAlternate: true, digest: 2, histogram: after,
            oscTitle: "tui", isAlternate: true)
        XCTAssertEqual(decision, .regenerate(reason: "frame"),
                       "a real non-image color-layout change must still re-title")
    }

    // Low-entropy dominance is measured over NON-image buckets (mirroring
    // histogramDistance). An image-DOMINATED screen with a discriminating status bar
    // must NOT be judged low-entropy, or it routes to the digest path where a status-bar
    // clock churns a re-title every tick instead of using the stable color histogram.
    func testImageDominatedScreenWithMixedStatusBarIsNotLowEntropy() {
        let imageKey = Int(iTermTabTitleFrameFingerprint.imageBucketKey())
        // 95% image cells, 5% split across two status-bar colors: non-image side is mixed.
        let h = hist([(imageKey, 950), (0, 30), (1, 20)])
        XCTAssertFalse(AITabTitleGenerator.isLowEntropyHistogram(h),
                       "an image-dominated screen with a mixed status bar must use the histogram path")
    }

    // A monochrome status bar beside an image IS low-entropy (its color layout can't
    // distinguish frames), so the digest path is correct there.
    func testImageWithMonochromeStatusBarIsLowEntropy() {
        let imageKey = Int(iTermTabTitleFrameFingerprint.imageBucketKey())
        XCTAssertTrue(AITabTitleGenerator.isLowEntropyHistogram(hist([(imageKey, 950), (0, 50)])))
    }

    // A pure-image screen has no non-image color layout to compare, so it is low-entropy.
    func testPureImageScreenIsLowEntropy() {
        let imageKey = Int(iTermTabTitleFrameFingerprint.imageBucketKey())
        XCTAssertTrue(AITabTitleGenerator.isLowEntropyHistogram(hist([(imageKey, 1000)])))
    }

    // An image->color transition (the PRIOR frame was all-image, the current frame
    // has a small color bar) is NOT comparable via the color histogram - histogramDistance
    // would report max distance against the empty prior side and spuriously re-title. It
    // must fall back to the content digest instead: unchanged content -> skip.
    func testImageToColorTransitionUsesDigestNotMaxDistance() {
        let imageKey = Int(iTermTabTitleFrameFingerprint.imageBucketKey())
        let priorAllImage = hist([(imageKey, 1000)])                    // no non-image cells
        let currentColorful = hist([(imageKey, 950), (0, 30), (1, 20)]) // a color bar appeared
        let skip = AITabTitleGenerator.regenerationDecision(
            lastOSC: "tui", lastDigest: 5, lastHistogram: priorAllImage,
            lastIsAlternate: true, digest: 5, histogram: currentColorful,
            oscTitle: "tui", isAlternate: true)
        XCTAssertEqual(skip, .skip, "unchanged content across an image->color transition must not re-title")
        // But a real content change (digest differs) still re-titles.
        let regen = AITabTitleGenerator.regenerationDecision(
            lastOSC: "tui", lastDigest: 5, lastHistogram: priorAllImage,
            lastIsAlternate: true, digest: 6, histogram: currentColorful,
            oscTitle: "tui", isAlternate: true)
        XCTAssertEqual(regen, .regenerate(reason: "frame"))
    }

    // The transition rule must not over-fire: staying in the same regime with an
    // unchanged frame still skips.
    func testSameRegimeUnchangedStillSkips() {
        let decision = AITabTitleGenerator.regenerationDecision(
            lastOSC: "app", lastDigest: 1, lastHistogram: hist([(0, 50), (1, 50)]),
            lastIsAlternate: true, digest: 2, histogram: hist([(0, 50), (1, 50)]),
            oscTitle: "app", isAlternate: true)
        XCTAssertEqual(decision, .skip)
    }

    // MARK: - applyDecision

    // A transient failure (the model call threw) must not cache the
    // fingerprint: the screen may be static, and a retry could succeed. Caching
    // it would suppress the AI title until the screen content next changes.
    func testTransientFailureDoesNotStampFingerprint() {
        let result = AITabTitleGenerator.applyDecision(
            outcome: .transientFailure, lastAppliedTitle: "Prev Title")
        XCTAssertFalse(result.stampFingerprint)
        XCTAssertNil(result.titleToApply)
    }

    // A deterministic empty result (the model ran and returned nothing usable)
    // must cache the fingerprint so a static screen is not re-hit every interval.
    // With no prior title there is nothing to clear.
    func testDeterministicEmptyStampsFingerprint() {
        let result = AITabTitleGenerator.applyDecision(
            outcome: .produced(nil), lastAppliedTitle: nil)
        XCTAssertTrue(result.stampFingerprint)
        XCTAssertNil(result.titleToApply)
    }

    // A worth-titling screen whose generation deterministically fails
    // (sanitize rejected an over-long/garbled reply) must CLEAR a prior title, or
    // the old name ("Reviewing Auth Diff") lingers over unrelated new work and,
    // because the fingerprint is stamped, is never retried.
    func testDeterministicFailureClearsStaleTitle() {
        let result = AITabTitleGenerator.applyDecision(
            outcome: .produced(nil), lastAppliedTitle: "Reviewing Auth Diff")
        XCTAssertTrue(result.stampFingerprint)
        XCTAssertEqual(result.titleToApply, "", "a stale title must be cleared")
    }

    // A regeneration that produces the SAME title as last time must not
    // be re-applied - re-setting the tab to the name it already shows reads as the
    // tab renaming itself while the user is reading it. Still stamp the fingerprint.
    func testDuplicateTitleIsNotReapplied() {
        let result = AITabTitleGenerator.applyDecision(
            outcome: .produced("Building Project"),
            lastAppliedTitle: "Building Project")
        XCTAssertTrue(result.stampFingerprint)
        XCTAssertNil(result.titleToApply)
    }

    // A genuinely new title is applied.
    func testChangedTitleIsApplied() {
        let result = AITabTitleGenerator.applyDecision(
            outcome: .produced("Reviewing Diff"),
            lastAppliedTitle: "Building Project")
        XCTAssertTrue(result.stampFingerprint)
        XCTAssertEqual(result.titleToApply, "Reviewing Diff")
    }

    // The first title for a session (no prior applied title) is applied.
    func testFirstTitleIsApplied() {
        let result = AITabTitleGenerator.applyDecision(
            outcome: .produced("Editing Config"), lastAppliedTitle: nil)
        XCTAssertEqual(result.titleToApply, "Editing Config")
    }

    // Clearing a stale title must also drop the regeneration fingerprints,
    // or identical recurring work (rerun the same `ls`, return to the same view)
    // is skipped as "unchanged" and never re-titled.
    func testClearingResetsFingerprintsForRecurringWork() {
        let key = "AiGeneratedTabTitles"
        let previous = iTermUserDefaults.userDefaults().object(forKey: key)
        iTermUserDefaults.userDefaults().set(true, forKey: key)
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            iTermUserDefaults.userDefaults().set(previous, forKey: key)
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        let gen = AITabTitleGenerator.instance
        let guid = "h1-recurring-work-test"
        gen.forget(sessionID: guid)
        gen.seedTitledStateForTesting(sessionID: guid, digest: 999, oscTitle: "", appliedTitle: "Listing Files")
        XCTAssertTrue(gen.hasTitledFingerprint(forSessionID: guid))

        // A blank (cleared) screen is not worth titling: it clears the title and
        // must also drop the fingerprints.
        var completionValue: String? = "unset"
        var contextBuilt = false
        let ctx = AITabTitleContext(job: nil, commandLine: nil, atPrompt: true,
                                    lastCommand: nil, recentCommands: [], cwd: nil,
                                    user: nil, host: nil, text: "")
        gen.requestTitle(forSessionID: guid, screen: "",
                         backgroundHistogram: [:], isAlternate: false, oscTitle: "",
                         context: { contextBuilt = true; return ctx }) {
            completionValue = $0
        }
        XCTAssertEqual(completionValue, "", "clearing should hand back an empty title")
        XCTAssertFalse(contextBuilt,
                       "context must not be assembled for a screen that is cleared, not generated")
        XCTAssertFalse(gen.hasTitledFingerprint(forSessionID: guid),
                       "fingerprints must be dropped so recurring work re-titles")
        gen.forget(sessionID: guid)
    }

    // terminate+revive reuses the same guid. A generation in flight when the
    // session is forgotten must be invalidated so that, after a new generation
    // starts for the revived guid, the OLD generation's completion is dropped
    // rather than applying a stale title. The epoch is what disambiguates them.
    func testRevivedSessionInvalidatesInFlightGeneration() {
        let gen = AITabTitleGenerator.instance
        let guid = "h3-revive-race-test"
        gen.forget(sessionID: guid)

        // (1) A generation is in flight.
        let oldEpoch = gen.beginGenerationForTesting(sessionID: guid)
        XCTAssertTrue(gen.generationIsCurrentForTesting(sessionID: guid, epoch: oldEpoch))

        // (2) terminate -> forgetAITitleState -> forget. The in-flight generation
        // is invalidated.
        gen.forget(sessionID: guid)
        XCTAssertFalse(gen.generationIsCurrentForTesting(sessionID: guid, epoch: oldEpoch),
                       "forgetting an in-flight generation must invalidate it")

        // (3) revive (same guid) + a new idle tick starts a new generation.
        let newEpoch = gen.beginGenerationForTesting(sessionID: guid)
        XCTAssertNotEqual(oldEpoch, newEpoch, "revived generation must get a fresh epoch")

        // (4) The old generation's completion must be dropped; the new one applies.
        XCTAssertFalse(gen.generationIsCurrentForTesting(sessionID: guid, epoch: oldEpoch),
                       "the stale generation must not be current after revive")
        XCTAssertTrue(gen.generationIsCurrentForTesting(sessionID: guid, epoch: newEpoch))

        gen.forget(sessionID: guid)
    }

    // A session closed mid-generation and never revived must leave nothing
    // behind. forget bumps the epoch (leaving it non-nil) to invalidate the
    // in-flight generation; when that late generation finally completes, its
    // dropped finish must clean up the leftover epoch, or hasState stays true
    // forever and the dictionary grows unbounded.
    func testMidGenerationCloseDoesNotLeakEpoch() {
        let gen = AITabTitleGenerator.instance
        let guid = "i2-midgen-close-test"
        gen.forget(sessionID: guid)

        // Generation in flight, then the session closes (terminate -> forget).
        let epoch = gen.beginGenerationForTesting(sessionID: guid)
        gen.forget(sessionID: guid)
        XCTAssertTrue(gen.hasState(forSessionID: guid),
                      "forget of an in-flight gen retains the bumped epoch")

        // The late generation completes (stale epoch). It must drop the leftover
        // state since the session is gone (not revived, nothing in flight).
        gen.finishForTesting(sessionID: guid, epoch: epoch)
        XCTAssertFalse(gen.hasState(forSessionID: guid),
                       "a superseded late finish must leave nothing behind")

        gen.forget(sessionID: guid)
    }

    // With state consolidated into one struct, forget of a session with only
    // titled fingerprints (no generation outstanding) must remove the entry entirely -
    // the single-removeValue win that makes a missed-field leak impossible.
    func testForgetOfCompletedSessionLeavesNoState() {
        let gen = AITabTitleGenerator.instance
        let guid = "aaa6-completed-forget"
        gen.forget(sessionID: guid)
        gen.seedTitledStateForTesting(sessionID: guid, digest: 7, oscTitle: "osc", appliedTitle: "A Title")
        XCTAssertTrue(gen.hasState(forSessionID: guid))
        XCTAssertTrue(gen.hasTitledFingerprint(forSessionID: guid))
        gen.forget(sessionID: guid)
        XCTAssertFalse(gen.hasState(forSessionID: guid), "forget must leave no state behind")
        XCTAssertFalse(gen.hasTitledFingerprint(forSessionID: guid))
        XCTAssertTrue(gen.canStartGenerationForTesting(sessionID: guid),
                      "the start-gate must be open again after forget")
    }

    // A generation that stalls past the timeout must not lock the session
    // out forever: abandoning it frees the inFlight token (so shouldAttempt can
    // run again) and bumps the epoch (so the eventual late finish is dropped).
    func testStalledGenerationIsRecovered() {
        let gen = AITabTitleGenerator.instance
        let guid = "j4-stall-test"
        gen.forget(sessionID: guid)

        let epoch = gen.beginGenerationForTesting(sessionID: guid)
        XCTAssertTrue(gen.isInFlightForTesting(sessionID: guid))

        gen.abandonStalledGeneration(sessionID: guid, epoch: epoch)
        XCTAssertFalse(gen.isInFlightForTesting(sessionID: guid),
                       "abandoning a stalled generation must free the inFlight token")
        XCTAssertFalse(gen.generationIsCurrentForTesting(sessionID: guid, epoch: epoch),
                       "the stalled generation's epoch must be superseded")

        // A fresh generation can now start.
        let newEpoch = gen.beginGenerationForTesting(sessionID: guid)
        XCTAssertNotEqual(epoch, newEpoch)
        gen.forget(sessionID: guid)
    }

    // Stall -> abandon at 8s (pre-stamps the screen fingerprint) -> the model
    // call then returns a TRANSIENT failure (spurious CancellationError) in the 8-16s
    // window. The transient contract is "don't stamp, so the unchanged screen can be
    // retried", but abandon already stamped. finish must clear abandon's stamp so the
    // retry can actually happen; otherwise regenerationDecision skips the unchanged
    // screen forever and it is never titled.
    func testTransientFailureOnAbandonedPathClearsStampSoRetryCanHappen() {
        let gen = AITabTitleGenerator.instance
        let guid = "uu2-transient-abandon-test"
        gen.forget(sessionID: guid)

        let epoch = gen.beginGenerationForTesting(sessionID: guid)
        gen.abandonStalledGeneration(sessionID: guid, epoch: epoch, digest: 4242)
        XCTAssertTrue(gen.hasTitledFingerprint(forSessionID: guid),
                      "abandon must pre-stamp the screen it gave up on")

        // The slow call returns in the recovery window with a transient failure.
        gen.finishTransientForTesting(sessionID: guid, epoch: epoch, digest: 4242)

        XCTAssertFalse(gen.hasTitledFingerprint(forSessionID: guid),
                       "a transient failure must clear abandon's stamp so the screen can be retried")
        gen.forget(sessionID: guid)
    }

    // Stall -> abandon (watchdog bumps the epoch, but the model call is still
    // outstanding) -> session closes (forget) -> revive under the same guid. The
    // revived generation must NOT reuse the abandoned generation's epoch, or the
    // zombie's late finish would alias it and apply a stale title.
    func testAbandonedGenerationSurvivesForgetAndRevive() {
        let gen = AITabTitleGenerator.instance
        let guid = "m1-zombie-test"
        gen.forget(sessionID: guid)

        let zombieEpoch = gen.beginGenerationForTesting(sessionID: guid)
        gen.abandonStalledGeneration(sessionID: guid, epoch: zombieEpoch)   // bumps, task still outstanding
        gen.forget(sessionID: guid)                                         // must not reset the epoch
        let revivedEpoch = gen.beginGenerationForTesting(sessionID: guid)

        XCTAssertNotEqual(revivedEpoch, zombieEpoch,
                          "revived generation must not reuse the abandoned generation's epoch")
        XCTAssertFalse(gen.generationIsCurrentForTesting(sessionID: guid, epoch: zombieEpoch),
                       "the abandoned (zombie) generation must never become current again")
        gen.forget(sessionID: guid)
    }

    // Two generations abandoned out of order: when the second's late finish
    // runs while the first zombie is still outstanding, it must NOT reset the
    // epoch counter (which would let the first zombie alias a revived session).
    func testInterleavedStallsDoNotAliasEpoch() {
        let gen = AITabTitleGenerator.instance
        let guid = "n5-interleave"
        gen.forget(sessionID: guid)

        let a = gen.beginGenerationForTesting(sessionID: guid)   // count 1
        gen.abandonStalledGeneration(sessionID: guid, epoch: a)  // zombie A, count still 1
        let b = gen.beginGenerationForTesting(sessionID: guid)   // count 2
        gen.abandonStalledGeneration(sessionID: guid, epoch: b)  // zombie B, count still 2

        // B returns first: its finish must not reset the epoch (zombie A still out).
        gen.finishForTesting(sessionID: guid, epoch: b)
        XCTAssertTrue(gen.hasState(forSessionID: guid),
                      "epoch must not be reset while a zombie is still outstanding")

        let c = gen.beginGenerationForTesting(sessionID: guid)   // live generation
        gen.finishForTesting(sessionID: guid, epoch: a)          // zombie A returns
        XCTAssertFalse(gen.generationIsCurrentForTesting(sessionID: guid, epoch: a),
                       "the zombie must never become current")
        XCTAssertTrue(gen.generationIsCurrentForTesting(sessionID: guid, epoch: c),
                      "the live generation must remain current")
        gen.forget(sessionID: guid)
        gen.finishForTesting(sessionID: guid, epoch: c)   // drain C's finish
    }

    // Abandoning a stalled generation must stamp the fingerprint of the
    // screen it gave up on, so an unchanged screen (a first-ever title against a
    // wedged model) is not retried into the same stall every ~8s forever. A real
    // screen change still retries (its digest/OSC then differ).
    func testAbandonStampsFingerprintToBreakDeadlockLoop() {
        let gen = AITabTitleGenerator.instance
        let guid = "p1-deadlock"
        gen.forget(sessionID: guid)
        let epoch = gen.beginGenerationForTesting(sessionID: guid)
        XCTAssertFalse(gen.hasTitledFingerprint(forSessionID: guid))
        gen.abandonStalledGeneration(sessionID: guid, epoch: epoch,
                                     digest: 42, histogram: [:], oscTitle: "", isAlternate: false)
        XCTAssertTrue(gen.hasTitledFingerprint(forSessionID: guid),
                      "abandon must stamp the fingerprint so the stalled screen isn't retried")
        gen.forget(sessionID: guid)
    }

    // A generation the watchdog abandons at the timeout boundary can still be
    // merely slow: if its model call returns a good title just after, that title
    // must be applied, not dropped as superseded (which would also, because abandon
    // stamped the fingerprint, suppress the retry and leave the tab untitled).
    func testAbandonedGenerationThatSucceedsStillApplies() {
        let gen = AITabTitleGenerator.instance
        let guid = "s1-slow-success"
        gen.forget(sessionID: guid)
        let epoch = gen.beginGenerationForTesting(sessionID: guid)
        gen.abandonStalledGeneration(sessionID: guid, epoch: epoch)   // watchdog gives up at 8s
        let applied = gen.finishForTesting(sessionID: guid, epoch: epoch, title: "Slow Title")
        XCTAssertEqual(applied, "Slow Title",
                       "an abandoned-but-successful generation must still apply its title")
        gen.forget(sessionID: guid)
    }

    // A stalled generation must NOT immediately blank a good title: that
    // would flicker to the fallback and back if the model recovers within the grace
    // window. The stale title is cleared only once the model has really given up
    // (force-cleanup), so the tab falls back to the session name then.
    func testStaleTitleClearedAtForceCleanupNotAbandon() {
        let gen = AITabTitleGenerator.instance
        let guid = "t1-stale-clear"
        gen.forget(sessionID: guid)
        // Screen X gets a title.
        let e1 = gen.beginGenerationForTesting(sessionID: guid)
        _ = gen.finishForTesting(sessionID: guid, epoch: e1, title: "Reviewing Auth Diff")
        XCTAssertEqual(gen.appliedTitleForTesting(sessionID: guid), "Reviewing Auth Diff")
        // Screen Y stalls and is abandoned at 8s: the title must STAY (the model may
        // still recover, and clearing now would flicker).
        let e2 = gen.beginGenerationForTesting(sessionID: guid)
        gen.abandonStalledGeneration(sessionID: guid, epoch: e2)
        XCTAssertEqual(gen.appliedTitleForTesting(sessionID: guid), "Reviewing Auth Diff",
                       "abandon must not clear the displayed title (avoid flicker on recovery)")
        // Force-cleanup at 16s (model gave up) clears the now-stale title.
        XCTAssertTrue(gen.forceCleanupHungGeneration(sessionID: guid, epoch: e2),
                      "force-cleanup must report that it cleared a displayed title")
        XCTAssertEqual(gen.appliedTitleForTesting(sessionID: guid), "",
                       "the stale title must be cleared once the model has given up")
        gen.forget(sessionID: guid)
    }

    // force-cleanup reports false (nothing to clear) when no title was
    // showing, so the watchdog does not push a spurious clear.
    func testForceCleanupReportsNoClearWhenNoTitleShown() {
        let gen = AITabTitleGenerator.instance
        let guid = "v3-no-title"
        gen.forget(sessionID: guid)
        let epoch = gen.beginGenerationForTesting(sessionID: guid)
        gen.abandonStalledGeneration(sessionID: guid, epoch: epoch)
        XCTAssertFalse(gen.forceCleanupHungGeneration(sessionID: guid, epoch: epoch),
                       "force-cleanup must not report a clear when nothing was displayed")
        gen.forget(sessionID: guid)
    }

    // An abandoned generation that returns EMPTY within the grace window still
    // routes through applyDecision at finish, so it clears a stale title from an
    // earlier screen: the model deciding "no title" here must not leave the old name.
    func testAbandonedEmptyResultClearsStaleTitleAtFinish() {
        let gen = AITabTitleGenerator.instance
        let guid = "t1-empty-clear"
        gen.forget(sessionID: guid)
        let e1 = gen.beginGenerationForTesting(sessionID: guid)
        _ = gen.finishForTesting(sessionID: guid, epoch: e1, title: "Reviewing Auth Diff", digest: 100)
        let e2 = gen.beginGenerationForTesting(sessionID: guid)
        gen.abandonStalledGeneration(sessionID: guid, epoch: e2, digest: 100)
        let applied = gen.finishForTesting(sessionID: guid, epoch: e2, title: nil, digest: 100)
        XCTAssertEqual(applied, "",
                       "an abandoned empty result must clear the stale title at finish")
        gen.forget(sessionID: guid)
    }

    // force-cleanup clears the screen fingerprint abandon stamped, so once the
    // hung call resolves and reopens the gate an unchanged screen can be retitled
    // (rather than staying cached-as-handled and stuck on the fallback forever).
    func testForceCleanupClearsFingerprintToAllowRetry() {
        let gen = AITabTitleGenerator.instance
        let guid = "bb3-retry"
        gen.forget(sessionID: guid)
        let epoch = gen.beginGenerationForTesting(sessionID: guid)
        gen.abandonStalledGeneration(sessionID: guid, epoch: epoch, digest: 555)
        XCTAssertTrue(gen.hasTitledFingerprint(forSessionID: guid),
                      "abandon stamps the fingerprint (blocks immediate retry into the stall)")
        gen.forceCleanupHungGeneration(sessionID: guid, epoch: epoch)
        XCTAssertFalse(gen.hasTitledFingerprint(forSessionID: guid),
                       "force-cleanup clears the fingerprint so the screen can be retitled on retry")
        gen.forget(sessionID: guid)
    }

    // A generation that returns AFTER the force-cleanup grace window is
    // given up on: force-cleanup drops the abandoned mark (to keep state bounded and
    // avoid double-firing completion after it already cleared the tab), so the late
    // finish is dropped as superseded rather than applied. The 8s-16s window still
    // recovers a merely-slow generation (see testAbandonedGenerationThatSucceeds).
    func testSlowGenerationAfterForceCleanupIsDropped() {
        let gen = AITabTitleGenerator.instance
        let guid = "y7-slow"
        gen.forget(sessionID: guid)
        let epoch = gen.beginGenerationForTesting(sessionID: guid)
        gen.abandonStalledGeneration(sessionID: guid, epoch: epoch, digest: 555)   // t=8s
        gen.forceCleanupHungGeneration(sessionID: guid, epoch: epoch)              // t=16s, gives up
        let applied = gen.finishForTesting(sessionID: guid, epoch: epoch, title: "Slow Title", digest: 555)
        XCTAssertNil(applied,
                     "a return after force-cleanup must be dropped, not applied (bounded state, no double clear)")
        gen.forget(sessionID: guid)
    }

    // But once a NEWER generation has started, an abandoned generation's late
    // result is genuinely stale and must be dropped - the epoch was bumped more
    // than once, so it no longer matches epoch+1.
    func testAbandonedGenerationSupersededByNewGenIsDropped() {
        let gen = AITabTitleGenerator.instance
        let guid = "s1-superseded"
        gen.forget(sessionID: guid)
        let stale = gen.beginGenerationForTesting(sessionID: guid)
        gen.abandonStalledGeneration(sessionID: guid, epoch: stale)
        let fresh = gen.beginGenerationForTesting(sessionID: guid)   // newer generation starts
        let applied = gen.finishForTesting(sessionID: guid, epoch: stale, title: "Stale Title")
        XCTAssertNil(applied,
                     "an abandoned generation superseded by a newer one must not apply")
        XCTAssertTrue(gen.generationIsCurrentForTesting(sessionID: guid, epoch: fresh),
                      "the newer generation must remain current")
        gen.forget(sessionID: guid)
        gen.finishForTesting(sessionID: guid, epoch: fresh)
    }

    // A forgotten (closed or revived-under-same-guid) session must NOT let an
    // abandoned generation's late title apply to the new shell.
    func testAbandonedGenerationDroppedAfterForget() {
        let gen = AITabTitleGenerator.instance
        let guid = "s1-forgotten"
        gen.forget(sessionID: guid)
        let epoch = gen.beginGenerationForTesting(sessionID: guid)
        gen.abandonStalledGeneration(sessionID: guid, epoch: epoch)
        gen.forget(sessionID: guid)   // session closed / revived
        let applied = gen.finishForTesting(sessionID: guid, epoch: epoch, title: "Old Shell")
        XCTAssertNil(applied,
                     "a forgotten session must not apply an abandoned generation's title")
        gen.forget(sessionID: guid)
    }

    // Against a wedged model, a generation is abandoned at 8s (freeing
    // inFlight) but its model call is still outstanding. A new generation must NOT
    // start on top of it. Force-cleanup at 16s must NOT reopen the gate either -
    // reopening would stack a fresh hung call every grace period on a degraded
    // machine. The gate reopens only once the outstanding call actually resolves.
    func testWedgedGenerationDoesNotStackNewStarts() {
        let gen = AITabTitleGenerator.instance
        let guid = "t4-wedge"
        gen.forget(sessionID: guid)
        let epoch = gen.beginGenerationForTesting(sessionID: guid)
        gen.abandonStalledGeneration(sessionID: guid, epoch: epoch)
        XCTAssertFalse(gen.isInFlightForTesting(sessionID: guid),
                       "abandon frees inFlight")
        XCTAssertFalse(gen.canStartGenerationForTesting(sessionID: guid),
                       "a new generation must not start while an abandoned one is still outstanding")
        gen.forceCleanupHungGeneration(sessionID: guid, epoch: epoch)
        XCTAssertFalse(gen.canStartGenerationForTesting(sessionID: guid),
                       "force-cleanup must not reopen the gate while the call may still be alive")
        // The call finally resolves (returns, or its connection breaks): now a new
        // generation may start.
        gen.finishForTesting(sessionID: guid, epoch: epoch)
        XCTAssertTrue(gen.canStartGenerationForTesting(sessionID: guid),
                      "the gate reopens once the outstanding call resolves")
        gen.forget(sessionID: guid)
    }

    // A permanently-hung call (never returns, so force-cleanup keeps the gate
    // closed) must not lock the session out forever: the watchdog's phase-3 reaper
    // frees the still-outstanding epoch after a backoff, reopening the gate. A retry
    // then uses a FRESH epoch, and if the orphan ever returns its late finish is
    // dropped, not aliased.
    func testReaperReopensGateForPermanentlyHungGeneration() {
        let gen = AITabTitleGenerator.instance
        let guid = "hh1-orphan"
        gen.forget(sessionID: guid)
        let hung = gen.beginGenerationForTesting(sessionID: guid)
        gen.abandonStalledGeneration(sessionID: guid, epoch: hung)
        gen.forceCleanupHungGeneration(sessionID: guid, epoch: hung)   // gate stays closed
        XCTAssertFalse(gen.canStartGenerationForTesting(sessionID: guid))

        // Phase 3: the call still never returned, so reap the orphan.
        gen.reapOrphanedGeneration(sessionID: guid, epoch: hung)
        XCTAssertTrue(gen.canStartGenerationForTesting(sessionID: guid),
                      "reaping the orphan must reopen the gate")

        // A retry uses a fresh epoch; the orphan's late return must be dropped.
        let retry = gen.beginGenerationForTesting(sessionID: guid)
        XCTAssertNotEqual(retry, hung, "the retry must not reuse the orphaned epoch")
        let applied = gen.finishForTesting(sessionID: guid, epoch: hung, title: "Orphan Title")
        XCTAssertNil(applied, "the orphan's late finish must be dropped, not aliased onto the retry")
        XCTAssertTrue(gen.generationIsCurrentForTesting(sessionID: guid, epoch: retry))
        gen.forget(sessionID: guid)
        gen.finishForTesting(sessionID: guid, epoch: retry)
    }

    // A session closed while its generation is genuinely hung must NOT
    // have its monotonic epoch counter reset by force-cleanup: resetting it would let
    // a same-guid revive reuse the epoch and be aliased by the hung call's eventual
    // late finish (applying a dead shell's title to the revived session). The counter
    // stays bumped (a bounded entry - the accepted cost of not observing the call's
    // death); force-cleanup frees only the outstanding entry so a revive's gate is
    // not blocked.
    func testForgottenHungGenerationDoesNotAliasRevive() {
        let gen = AITabTitleGenerator.instance
        let guid = "o3-hung-gen"
        gen.forget(sessionID: guid)

        let hung = gen.beginGenerationForTesting(sessionID: guid)     // epoch 1
        gen.abandonStalledGeneration(sessionID: guid, epoch: hung)    // zombie, still outstanding
        gen.forget(sessionID: guid)                                   // session closes; epoch kept bumped
        gen.forceCleanupHungGeneration(sessionID: guid, epoch: hung)  // 16s: frees outstanding, keeps counter

        // The gate is not blocked, so a revive can start - and must NOT reuse epoch 1.
        XCTAssertTrue(gen.canStartGenerationForTesting(sessionID: guid),
                      "force-cleanup must free the outstanding entry so a revive is not gate-blocked")
        let revived = gen.beginGenerationForTesting(sessionID: guid)
        XCTAssertNotEqual(revived, hung, "a same-guid revive must not reuse the hung epoch")

        // The hung call finally returns: its late finish must be dropped, not applied
        // to the revived generation.
        let applied = gen.finishForTesting(sessionID: guid, epoch: hung, title: "Dead Shell")
        XCTAssertNil(applied, "the hung call's late finish must not alias the revived session")
        XCTAssertTrue(gen.generationIsCurrentForTesting(sessionID: guid, epoch: revived),
                      "the revived generation's bookkeeping must be intact")
        gen.forget(sessionID: guid)
        gen.finishForTesting(sessionID: guid, epoch: revived)
    }

    // A generation force-cleaned as "hung" may still be alive (FoundationModels
    // need not honor Task.cancel()). force-cleanup must NOT reset the monotonic
    // epoch counter, or a fresh generation reuses the hung epoch and the hung call's
    // eventual finish aliases it - applying a stale title and tearing down the live
    // generation's bookkeeping.
    func testForceCleanupDoesNotEnableEpochReuseRace() {
        let gen = AITabTitleGenerator.instance
        let guid = "u1-reuse"
        gen.forget(sessionID: guid)
        let hung = gen.beginGenerationForTesting(sessionID: guid)      // epoch 1
        gen.abandonStalledGeneration(sessionID: guid, epoch: hung)     // t=8s
        gen.forceCleanupHungGeneration(sessionID: guid, epoch: hung)   // t=16s

        // A fresh generation starts; it must NOT reuse the force-cleaned epoch.
        let fresh = gen.beginGenerationForTesting(sessionID: guid)
        XCTAssertNotEqual(fresh, hung, "a force-cleaned epoch must not be reused")

        // The hung call finally returns with a title: its late finish must be
        // dropped as superseded and must not disturb the fresh generation.
        let applied = gen.finishForTesting(sessionID: guid, epoch: hung, title: "Stale Title")
        XCTAssertNil(applied, "the hung generation's late finish must be dropped, not applied")
        XCTAssertTrue(gen.generationIsCurrentForTesting(sessionID: guid, epoch: fresh),
                      "the fresh generation must remain current")
        XCTAssertTrue(gen.isInFlightForTesting(sessionID: guid),
                      "the fresh generation's inFlight token must be intact")
        gen.forget(sessionID: guid)
        gen.finishForTesting(sessionID: guid, epoch: fresh)   // drain
    }

    // Abandoning is a no-op if the generation already completed (epoch moved on).
    func testAbandonIsNoOpForCompletedGeneration() {
        let gen = AITabTitleGenerator.instance
        let guid = "j4-noop-test"
        gen.forget(sessionID: guid)
        let epoch = gen.beginGenerationForTesting(sessionID: guid)
        // A newer generation started (epoch moved on): abandoning the old one
        // must not touch the new one.
        let newEpoch = gen.beginGenerationForTesting(sessionID: guid)
        gen.abandonStalledGeneration(sessionID: guid, epoch: epoch)
        XCTAssertTrue(gen.generationIsCurrentForTesting(sessionID: guid, epoch: newEpoch),
                      "abandoning a superseded generation must not disturb the current one")
        gen.forget(sessionID: guid)
    }

    // MARK: - sessionConsumesAITitle

    private let aiBit = UInt(1) << 12
    private let customBit = UInt(1) << 4   // iTermTitleComponentsCustom

    // A profile that selected the AI component consumes the title -> run it.
    func testConsumesWhenAIComponentSelected() {
        XCTAssertTrue(AITabTitleGenerator.sessionConsumesAITitle(titleComponents: aiBit, hasCustomTitleFunction: false))
    }

    // A custom title function that is the ACTIVE title mode might interpolate
    // session.aiTitle -> allow (err toward running, since we can't inspect the body).
    func testConsumesWhenActiveCustomTitleFunction() {
        XCTAssertTrue(AITabTitleGenerator.sessionConsumesAITitle(titleComponents: customBit, hasCustomTitleFunction: true))
    }

    // A profile with a stored title function that is NOT the active title mode
    // (the popup was switched to a plain component, leaving KEY_TITLE_FUNC stale) must
    // NOT consume the AI title: the function never runs, so it can never interpolate
    // session.aiTitle. Running the model would waste CPU/battery and feed the screen to
    // the model for a session the user did not opt into. The stored-but-inactive
    // function must be gated by the Custom component being active.
    func testDoesNotConsumeWhenCustomFunctionStoredButComponentInactive() {
        let jobComponent = UInt(1) << 2
        XCTAssertFalse(AITabTitleGenerator.sessionConsumesAITitle(titleComponents: jobComponent,
                                                                  hasCustomTitleFunction: true))
    }

    // A default profile (SessionName only, no AI, no custom function) does
    // NOT consume the AI title, so it must not be run through the model just
    // because the global setting is on.
    func testDoesNotConsumeForDefaultProfile() {
        let sessionNameOnly = UInt(1) << 0
        XCTAssertFalse(AITabTitleGenerator.sessionConsumesAITitle(titleComponents: sessionNameOnly, hasCustomTitleFunction: false))
    }

    // An AI profile whose AI title is currently MASKED by an active
    // TemporarySessionName (a manual rename / Set-Title trigger) must NOT consume: the
    // generated title would never be shown, so running the model wastes work and feeds
    // the screen to it for nothing.
    func testDoesNotConsumeWhenMaskedByTemporaryName() {
        XCTAssertFalse(AITabTitleGenerator.sessionConsumesAITitle(titleComponents: aiBit,
                                                                  hasCustomTitleFunction: false,
                                                                  isMaskedByTemporaryName: true))
    }

    // Not masked: the AI profile consumes as normal.
    func testConsumesWhenAIComponentSelectedAndNotMasked() {
        XCTAssertTrue(AITabTitleGenerator.sessionConsumesAITitle(titleComponents: aiBit,
                                                                 hasCustomTitleFunction: false,
                                                                 isMaskedByTemporaryName: false))
    }

    // MARK: - assembleText

    // When exactly one recent command is known and the lastCommand variable
    // is nil (a transient state right after a command finishes), the single known
    // command must still be shown, not discarded for a bare "At a shell prompt."
    func testSingleRecentCommandIsShownWhenLastCommandNil() {
        let text = AITabTitleContext.assembleText(
            job: "zsh", commandLine: "-zsh", atPrompt: true, lastCommand: nil,
            recentCommands: ["ls -la /var/log"], cwd: "/var/log", user: nil,
            host: nil, home: nil)
        XCTAssertTrue(text.contains("ls -la /var/log"), "the one known command must be shown: \(text)")
    }

    // A recent command containing an embedded newline (heredoc, quoted
    // multi-line) must be flattened to one physical line, or the assembled context
    // splits into orphaned continuation lines the trimmer can't identify as
    // history, so it sheds cwd/host instead.
    func testMultiLineCommandIsFlattenedInHistory() {
        let text = AITabTitleContext.assembleText(
            job: nil, commandLine: nil, atPrompt: true, lastCommand: nil,
            recentCommands: ["cd proj", "git commit -m 'line1\nline2'", "ls"],
            cwd: "/proj", user: nil, host: nil, home: nil)
        XCTAssertTrue(text.contains("  git commit -m 'line1 line2'"),
                      "embedded newline must be flattened: \(text)")
        XCTAssertFalse(text.contains("line1\nline2"), "no raw embedded newline should remain")
    }

    // The running command reaches assembleText from two sources with different
    // spacing: commandLine (argv, single-spaced) and recentCommands.last (typed, with
    // interior whitespace runs). Under the auto-composer path (runningCommandInHistory),
    // the dedup must canonicalize interior whitespace so it still fires; otherwise the
    // running command is emitted twice (Command line: AND under Earlier commands).
    func testRunningCommandDedupedDespiteSpacingDifference() {
        let text = AITabTitleContext.assembleText(
            job: "python", commandLine: "python train.py",       // argv, single-spaced
            atPrompt: false, lastCommand: nil,
            recentCommands: ["cd project", "python  train.py"],   // typed, interior double space
            cwd: nil, user: nil, host: nil, home: nil,
            runningCommandInHistory: true)
        let occurrences = text.components(separatedBy: "train.py").count - 1
        XCTAssertEqual(occurrences, 1, "the running command must not be emitted twice: \(text)")
    }

    // Under STANDARD shell integration (runningCommandInHistory == false), a
    // recentCommands entry equal to the running command is a genuinely-FINISHED command
    // (run `make`, it finishes, then run `make` again). It must NOT be dropped - doing so
    // would omit the whole "Earlier commands" arc.
    func testFinishedCommandEqualToRunningIsNotDroppedUnderStandardIntegration() {
        let text = AITabTitleContext.assembleText(
            job: "make", commandLine: "make",
            atPrompt: false, lastCommand: nil,
            recentCommands: ["make"],   // a genuinely-finished make, not the running one
            cwd: nil, user: nil, host: nil, home: nil,
            runningCommandInHistory: false)
        XCTAssertTrue(text.contains(AITabTitleContext.historyHeaderSuffix),
                      "the earlier finished command must still appear: \(text)")
        XCTAssertTrue(text.contains("\(AITabTitleContext.historyLinePrefix)make"),
                      "the finished make must be listed under Earlier commands: \(text)")
    }

    // MARK: - condense

    // The digest path and the prompt path share ONE line walk, differing only in
    // blank-line policy. These pin both policies and the shared interior collapse so a
    // future edit to one can't silently desync it from the other.
    func testCondenseDropAllRemovesEveryBlankLine() {
        XCTAssertEqual(AITabTitleGenerator.condense("a\n\n\nb", blankLines: .dropAll), "a\nb")
    }

    func testCondenseCollapseRunsKeepsOneInteriorBlankAndTrimsEnds() {
        XCTAssertEqual(AITabTitleGenerator.condense("a\n\n\nb", blankLines: .collapseRuns), "a\n\nb")
        XCTAssertEqual(AITabTitleGenerator.condense("\n\na\nb\n\n", blankLines: .collapseRuns), "a\nb")
    }

    func testCondenseSharesInteriorWhitespaceCollapseAcrossPolicies() {
        XCTAssertEqual(AITabTitleGenerator.condense("a  b\tc", blankLines: .dropAll), "a b c")
        XCTAssertEqual(AITabTitleGenerator.condense("a  b\tc", blankLines: .collapseRuns), "a b c")
    }

    // MARK: - clearDecision

    // A screen that stopped being worth titling, after a title was shown, clears.
    func testClearsWhenNoLongerWorthTitlingAndHadTitle() {
        XCTAssertTrue(AITabTitleGenerator.clearDecision(worthTitling: false, lastAppliedTitle: "Reviewing Auth Diff"))
    }

    // Still worth titling: keep the current title.
    func testDoesNotClearWhenStillWorthTitling() {
        XCTAssertFalse(AITabTitleGenerator.clearDecision(worthTitling: true, lastAppliedTitle: "Reviewing Auth Diff"))
    }

    // Nothing was ever applied: nothing to clear (don't churn an empty value).
    func testDoesNotClearWhenNothingApplied() {
        XCTAssertFalse(AITabTitleGenerator.clearDecision(worthTitling: false, lastAppliedTitle: nil))
        XCTAssertFalse(AITabTitleGenerator.clearDecision(worthTitling: false, lastAppliedTitle: ""))
    }

    // MARK: - sanitize

    // A reply with a leading blank line (a common on-device quirk) must still
    // yield the title, not nil (which would stamp the fingerprint and lose it).
    func testSanitizeTakesFirstNonEmptyLine() {
        XCTAssertEqual(AITabTitleGenerator.sanitize("\nDeploying Service"), "Deploying Service")
        XCTAssertEqual(AITabTitleGenerator.sanitize("\n\n  Reviewing Diff  \n"), "Reviewing Diff")
    }

    // A newline INSIDE the title field must not truncate the title: the lines
    // are joined with a space, not cut at the first newline.
    func testSanitizeJoinsInteriorNewline() {
        XCTAssertEqual(AITabTitleGenerator.sanitize("Fix\nAuth Bug"), "Fix Auth Bug")
        XCTAssertEqual(AITabTitleGenerator.sanitize("\nReviewing\nPull Request"), "Reviewing Pull Request")
    }

    // An interior tab is whitespace, not a malformed reply: scrub it to a
    // space and keep the title rather than rejecting it (which would stamp the
    // screen as untitleable).
    func testSanitizeScrubsInteriorTab() {
        XCTAssertEqual(AITabTitleGenerator.sanitize("Build\tSystem"), "Build System")
    }

    // A doubled regular space must collapse to one, not persist as a visible
    // double space that also wastes the length budget.
    func testSanitizeCollapsesDoubleSpace() {
        XCTAssertEqual(AITabTitleGenerator.sanitize("Git  Rebase"), "Git Rebase")
        XCTAssertEqual(AITabTitleGenerator.sanitize("A   B\t C"), "A B C")
    }

    // Unicode space separators (IDEOGRAPHIC U+3000, EM/EN, ZWSP) collapse to a
    // single ASCII space too, so they don't persist verbatim and word-boundary
    // truncation still works.
    func testSanitizeCollapsesUnicodeSpaces() {
        XCTAssertEqual(AITabTitleGenerator.sanitize("Build\u{3000}System"), "Build System")
        XCTAssertEqual(AITabTitleGenerator.sanitize("A\u{2003}B\u{2000}C"), "A B C")
        XCTAssertEqual(AITabTitleGenerator.sanitize("Zero\u{200B}Width"), "Zero Width")
    }

    // A genuine control character (ESC/NUL/newline in the middle) is still rejected.
    func testSanitizeRejectsRealControlChars() {
        XCTAssertNil(AITabTitleGenerator.sanitize("Build\u{1b}System"))
    }

    // A ZWJ emoji sequence or a bidi mark is a Unicode FORMAT char (Cf), not a
    // malformed control char - a valid title must survive it, not be discarded.
    func testSanitizeKeepsZWJEmojiAndBidi() {
        XCTAssertEqual(AITabTitleGenerator.sanitize("👨‍💻 Dev Setup"), "👨‍💻 Dev Setup")
        // A right-to-left mark (U+200F) is Cf; the title should survive.
        XCTAssertEqual(AITabTitleGenerator.sanitize("Editing \u{200F}config"), "Editing \u{200F}config")
    }

    // A content-free (all-punctuation) reply is not a usable title and must be
    // rejected, not renamed onto the tab.
    func testSanitizeRejectsPunctuationOnly() {
        XCTAssertNil(AITabTitleGenerator.sanitize("--"))
        XCTAssertNil(AITabTitleGenerator.sanitize("..."))
        XCTAssertNil(AITabTitleGenerator.sanitize("\""))
        XCTAssertNil(AITabTitleGenerator.sanitize("??"))
    }

    // But a title with any letter/number (incl. CJK) is kept.
    func testSanitizeKeepsTitleWithContent() {
        XCTAssertEqual(AITabTitleGenerator.sanitize("v2.0 Release"), "v2.0 Release")
        XCTAssertEqual(AITabTitleGenerator.sanitize("文件编辑"), "文件编辑")
    }

    // The content check must run AFTER truncation: a "- " bullet plus one word
    // longer than the cap truncates to just "-", which must still be rejected.
    func testSanitizeRejectsTitleThatTruncatesToPunctuation() {
        let longWord = String(repeating: "x", count: 50)   // > maximumTitleLength (40)
        XCTAssertNil(AITabTitleGenerator.sanitize("- \(longWord)"))
    }

    // But bidi OVERRIDE / ISOLATE controls (also Cf) can visually reorder the
    // title and adjacent tab-bar text (Trojan-Source), so they must be rejected.
    func testSanitizeRejectsBidiOverride() {
        XCTAssertNil(AITabTitleGenerator.sanitize("Build \u{202E}drowssap System"))  // RLO
        XCTAssertNil(AITabTitleGenerator.sanitize("A\u{2066}B\u{2069}C"))            // LRI/PDI
    }

    // Unwrap only a matched surrounding quote pair, not every leading/trailing
    // quote: a title that legitimately begins/ends with an apostrophe must survive.
    func testSanitizeKeepsLeadingApostrophe() {
        XCTAssertEqual(AITabTitleGenerator.sanitize("'90s Playlist"), "'90s Playlist")
        XCTAssertEqual(AITabTitleGenerator.sanitize("'Tis the Season"), "'Tis the Season")
    }

    // A genuinely wrapped title is still unwrapped.
    func testSanitizeUnwrapsMatchedQuotePair() {
        XCTAssertEqual(AITabTitleGenerator.sanitize("\"Deploying Service\""), "Deploying Service")
        XCTAssertEqual(AITabTitleGenerator.sanitize("\u{2018}Reviewing Diff\u{2019}"), "Reviewing Diff")
    }

    // A double-wrapped reply must be fully unwrapped, not left with an inner
    // quote pair. The loop only strips a genuine matched pair, so a legitimate
    // leading/trailing apostrophe is still preserved.
    func testSanitizeUnwrapsNestedQuotePairs() {
        XCTAssertEqual(AITabTitleGenerator.sanitize("\"\"Build System\"\""), "Build System")
        XCTAssertEqual(AITabTitleGenerator.sanitize("'90s Playlist"), "'90s Playlist")
    }

    // Only a genuine MATCHED wrapping pair is unwrapped. A mismatched pair (an
    // opening quote of one kind and a different closing quote) is NOT a wrapper, so
    // stripping it would delete legitimate content (a possessive/closing apostrophe
    // or a stray opener). Leave such asymmetric strings alone.
    func testSanitizeKeepsMismatchedQuotes() {
        // Straight double opener, straight single closer: not a pair.
        XCTAssertEqual(AITabTitleGenerator.sanitize("\"Developers'"), "\"Developers'")
        // Curly double opener with a straight single closer: not a pair.
        XCTAssertEqual(AITabTitleGenerator.sanitize("\u{201C}Reviewing Diff'"),
                       "\u{201C}Reviewing Diff'")
        // A curly CLOSER at the front paired with a curly OPENER at the back is
        // reversed, not a wrapper.
        XCTAssertEqual(AITabTitleGenerator.sanitize("\u{201D}Build\u{201C}"),
                       "\u{201D}Build\u{201C}")
    }

    // A genuine curly pair (opener ... matching closer) is still unwrapped.
    func testSanitizeUnwrapsCurlyPair() {
        XCTAssertEqual(AITabTitleGenerator.sanitize("\u{201C}Build System\u{201D}"), "Build System")
        XCTAssertEqual(AITabTitleGenerator.sanitize("\u{2018}90s\u{2019}"), "90s")
    }

    // The model sometimes emits the SAME curly glyph at both ends. That is
    // still a wrapping pair and must be unwrapped, while a leading apostrophe (only
    // at the front) is left alone.
    func testSanitizeUnwrapsSameGlyphCurlyPair() {
        XCTAssertEqual(AITabTitleGenerator.sanitize("\u{201D}Build System\u{201D}"), "Build System")
        XCTAssertEqual(AITabTitleGenerator.sanitize("\u{201C}Build System\u{201C}"), "Build System")
        // Curly apostrophe only at the front: not a pair, kept.
        XCTAssertEqual(AITabTitleGenerator.sanitize("\u{2019}90s Playlist"), "\u{2019}90s Playlist")
    }

    // A title made of TWO separate quoted spans merely begins and ends with a
    // quote glyph; it is NOT a single wrapped title. isMatchedQuotePair only compares
    // the two endpoints, so without a balance check the outer quotes would be stripped,
    // corrupting the title ("git" vs "hg" -> git" vs "hg). The interior-contains check
    // keeps these intact while still unwrapping a genuine nested double-wrap.
    func testSanitizeKeepsSeparateQuotedSpans() {
        XCTAssertEqual(AITabTitleGenerator.sanitize("\"git\" vs \"hg\""), "\"git\" vs \"hg\"")
        XCTAssertEqual(AITabTitleGenerator.sanitize("'ls' and 'cd'"), "'ls' and 'cd'")
        // Curly variant: “build” vs “ship” (curly opener at both far ends).
        XCTAssertEqual(AITabTitleGenerator.sanitize("\u{201C}build\u{201D} vs \u{201C}ship\u{201D}"),
                       "\u{201C}build\u{201D} vs \u{201C}ship\u{201D}")
    }

    // A legitimate but slightly-too-long title (four Title-Case words > 40
    // chars) must be truncated on a word boundary, not discarded: discarding
    // returns nil, which stamps the screen as handled and leaves it untitled
    // forever. The scalar-abuse cap below still rejects (Zalgo), but plausible
    // model output is kept.
    func testSanitizeTruncatesOverlongTitleAtWordBoundary() {
        let out = AITabTitleGenerator.sanitize("Continuous Integration Pipeline Configuration")
        XCTAssertEqual(out, "Continuous Integration Pipeline")
        XCTAssertLessThanOrEqual(out?.count ?? 999, 40)
    }

    // A single word longer than the cap is hard-truncated rather than dropped.
    func testSanitizeHardTruncatesOverlongSingleWord() {
        let word = String(repeating: "A", count: 60)
        let out = AITabTitleGenerator.sanitize(word)
        XCTAssertEqual(out?.count, 40)
    }

    // The agent screen markup must be stripped before titling: ⟨cursor⟩ and
    // ⟨image⟩ tokens removed, and ⟨dim⟩…⟨/dim⟩ runs removed WITH their content (a
    // faint shell autosuggestion is a command not run and must not name the tab).
    func testPlainTitleTextStripsAgentMarkup() {
        let cursor = "\u{27E8}cursor\u{27E9}"
        let dimOpen = "\u{27E8}dim\u{27E9}"
        let dimClose = "\u{27E8}/dim\u{27E9}"
        let image = "\u{27E8}image\u{27E9}"
        // A partially-typed command with a dim autosuggestion after the cursor.
        let input = "$ git \(cursor)\(dimOpen)push origin main\(dimClose)\nprevious \(image) output"
        let out = WorkgroupIntrospection.plainTitleText(input)
        XCTAssertFalse(out.contains("\u{27E8}"), "no markup brackets should survive")
        XCTAssertFalse(out.contains("push origin main"),
                       "the dim autosuggestion content must be removed, not just its markers")
        XCTAssertTrue(out.contains("git "), "the actually-typed text is kept")
        XCTAssertTrue(out.contains("previous  output"), "the image token is removed")
    }

    // Plain text with no markup is returned unchanged.
    func testPlainTitleTextLeavesPlainTextAlone() {
        let s = "Reviewing Auth Diff\nls -la /usr/bin"
        XCTAssertEqual(WorkgroupIntrospection.plainTitleText(s), s)
    }

    // A faint run NOT after the cursor is real content (diff/pager/dimmed rows):
    // keep the content, drop only the markers.
    func testPlainTitleTextKeepsNonAutosuggestionFaintContent() {
        let dimOpen = "\u{27E8}dim\u{27E9}"
        let dimClose = "\u{27E8}/dim\u{27E9}"
        let out = WorkgroupIntrospection.plainTitleText("diff \(dimOpen)context line\(dimClose) here")
        XCTAssertEqual(out, "diff context line here")
    }

    // An unbalanced dim-open AFTER the cursor (a clipped autosuggestion) drops
    // the trailing text, not just the marker.
    func testPlainTitleTextDropsUnbalancedAutosuggestionTail() {
        let cursor = "\u{27E8}cursor\u{27E9}"
        let dimOpen = "\u{27E8}dim\u{27E9}"
        let out = WorkgroupIntrospection.plainTitleText("git \(cursor)\(dimOpen)push origin main")
        XCTAssertEqual(out, "git ")
    }

    // An unbalanced dim-open after the cursor must NOT consume later lines: the
    // removal is bounded to the cursor's line, so real content below survives.
    func testPlainTitleTextUnbalancedDimDoesNotEatLaterLines() {
        let cursor = "\u{27E8}cursor\u{27E9}"
        let dimOpen = "\u{27E8}dim\u{27E9}"
        let dimClose = "\u{27E8}/dim\u{27E9}"
        // Open after cursor, but the close is on a later, unrelated line.
        let out = WorkgroupIntrospection.plainTitleText("cmd \(cursor)\(dimOpen)ghost\nreal content \(dimClose)here")
        XCTAssertTrue(out.contains("real content"), "later lines must survive: \(out)")
        XCTAssertTrue(out.contains("here"), "\(out)")
        XCTAssertFalse(out.contains("ghost"), "the on-line suggestion is still dropped: \(out)")
    }

    // The cursor resting on the first cell of a genuine dim region (nothing
    // typed before it) is NOT an autosuggestion: keep the content.
    func testPlainTitleTextKeepsDimLineWhenCursorAtLineStart() {
        let cursor = "\u{27E8}cursor\u{27E9}"
        let dimOpen = "\u{27E8}dim\u{27E9}"
        let dimClose = "\u{27E8}/dim\u{27E9}"
        let out = WorkgroupIntrospection.plainTitleText("prev line\n\(cursor)\(dimOpen)dimmed row\(dimClose)")
        XCTAssertTrue(out.contains("dimmed row"), "a real dim region must survive: \(out)")
    }

    // A base char plus hundreds of combining scalars is few graphemes but is
    // rendering-hostile ("Zalgo"); the scalar-count bound must reject it even
    // though the grapheme count passes.
    func testSanitizeRejectsZalgo() {
        let zalgo = "a" + String(repeating: "\u{0301}", count: 300)
        XCTAssertNil(AITabTitleGenerator.sanitize(zalgo))
    }

    // A normal single-line reply is unchanged; genuinely empty stays nil.
    func testSanitizeNormalAndEmpty() {
        XCTAssertEqual(AITabTitleGenerator.sanitize("Editing Config"), "Editing Config")
        XCTAssertNil(AITabTitleGenerator.sanitize("\n\n   \n"))
        XCTAssertNil(AITabTitleGenerator.sanitize(""))
    }

    // MARK: - abbreviatingHome

    // For a root shell HOME is "/". The home must not be treated as a prefix
    // of every absolute path, or each directory shown to the model is corrupted
    // with a spurious ~ (/etc/nginx -> ~/etc/nginx).
    func testRootHomeDoesNotCorruptAbsolutePaths() {
        XCTAssertEqual(AITabTitleContext.abbreviatingHome("/etc/nginx", home: "/"), "/etc/nginx")
        XCTAssertEqual(AITabTitleContext.abbreviatingHome("/var/log", home: "/"), "/var/log")
        XCTAssertEqual(AITabTitleContext.abbreviatingHome("/", home: "/"), "/")
    }

    // A normal home still abbreviates.
    func testNormalHomeStillAbbreviates() {
        XCTAssertEqual(AITabTitleContext.abbreviatingHome("/Users/gnachman/git", home: "/Users/gnachman"), "~/git")
        XCTAssertEqual(AITabTitleContext.abbreviatingHome("/Users/gnachman", home: "/Users/gnachman"), "~")
        XCTAssertEqual(AITabTitleContext.abbreviatingHome("/opt/x", home: "/Users/gnachman"), "/opt/x")
    }

    // A path that merely shares a character prefix with home (a sibling directory
    // whose name extends home's last component) must NOT be abbreviated - the boundary bug
    // in the shared prettyPWD that this consolidation fixed.
    func testHomePrefixBoundaryDoesNotOverMatch() {
        XCTAssertEqual(AITabTitleContext.abbreviatingHome("/Users/gnachmanx", home: "/Users/gnachman"),
                       "/Users/gnachmanx")
        XCTAssertEqual(AITabTitleContext.abbreviatingHome("/Users/gnachman-backup/logs", home: "/Users/gnachman"),
                       "/Users/gnachman-backup/logs")
        // A trailing slash on home is tolerated.
        XCTAssertEqual(AITabTitleContext.abbreviatingHome("/Users/gnachman/git", home: "/Users/gnachman/"), "~/git")
    }

    // A doubled slash must never reach the output, no matter where it comes from
    // (a root/degenerate home, or a redundant slash in the path). Root home may render
    // as "/" or "~" - that is don't-care - but "//" is always wrong.
    func testDoubledSlashesNeverAppear() {
        // Slash-only home and path normalize to "/", never "//".
        XCTAssertEqual(AITabTitleContext.abbreviatingHome("//", home: "//"), "/")
        XCTAssertEqual(AITabTitleContext.abbreviatingHome("//", home: "/Users/gnachman"), "/")
        // A trailing slash on the path collapses so it still matches home.
        XCTAssertEqual(AITabTitleContext.abbreviatingHome("/Users/gnachman/", home: "/Users/gnachman"), "~")
        // A redundant interior slash is collapsed rather than carried into the ~ result.
        XCTAssertEqual(AITabTitleContext.abbreviatingHome("/Users/gnachman//git", home: "/Users/gnachman"), "~/git")
        XCTAssertEqual(AITabTitleContext.abbreviatingHome("/etc//nginx", home: "/Users/gnachman"), "/etc/nginx")
    }

    // MARK: - isTransient (error classification)

    // Only genuinely transient errors (a cancelled task) should skip stamping
    // the fingerprint. A deterministic FoundationModels failure (guardrail,
    // unsupported language, context overflow) reproduces for the same screen, so
    // an unrecognized error must be treated as deterministic - otherwise the same
    // offending screen is re-run through the model every cadence tick forever.
    func testCancellationIsTransient() {
        XCTAssertTrue(AITabTitleGenerator.isTransientGenerationError(CancellationError()))
    }

    func testArbitraryErrorIsDeterministic() {
        let e = NSError(domain: "FoundationModels.GenerationError", code: 1, userInfo: nil)
        XCTAssertFalse(AITabTitleGenerator.isTransientGenerationError(e))
    }
}

final class AITabTitleFrameFingerprintTests: XCTestCase {
    private func key(_ mode: ColorMode, _ bg: Int, _ green: Int, _ blue: Int) -> UInt32 {
        return iTermTabTitleFrameFingerprint.histogramKey(forImage: false,
                                                          backgroundColorMode: Int32(mode.rawValue),
                                                          backgroundColor: Int32(bg),
                                                          bgGreen: Int32(green),
                                                          bgBlue: Int32(blue))
    }

    private func imageKey() -> UInt32 {
        return iTermTabTitleFrameFingerprint.histogramKey(forImage: true,
                                                          backgroundColorMode: 0,
                                                          backgroundColor: 0,
                                                          bgGreen: 0,
                                                          bgBlue: 0)
    }

    // backgroundHistogramForScreen stores each bucket in a CFDictionary keyed
    // as (key + 1) in uint32_t arithmetic, so a key of UINT32_MAX would wrap to 0 -
    // a NULL CFDictionary key, exactly what the +1 scheme exists to avoid. The image
    // sentinel must therefore never be UINT32_MAX. It must still be distinct from
    // every real color key (image cells contribute one stable bucket).
    func testImageBucketKeySurvivesPlusOneAndIsDistinct() {
        XCTAssertNotEqual(imageKey(), UInt32.max, "image sentinel wraps to the NULL key after +1")
        XCTAssertNotEqual(UInt64(imageKey()) + 1, 1 << 32, "image sentinel +1 must not overflow uint32_t to 0")
        // Must not collide with a real color key in any mode.
        XCTAssertNotEqual(imageKey(), key(ColorMode24bit, 255, 255, 255))
        XCTAssertNotEqual(imageKey(), key(ColorModeNormal, 255, 0, 0))
        // Stable: the same for every image cell regardless of its x/y indices.
        XCTAssertEqual(imageKey(), imageKey())
    }

    // Outside 24-bit color, green/blue are not meaningful background
    // components (indexed cells leave them stale, image cells repurpose them as
    // x/y indices), so a visually identical background must hash to one bucket
    // regardless of what green/blue happen to hold - matching BackgroundColorsEqual.
    func testIndexedModeMasksGreenBlue() {
        XCTAssertEqual(key(ColorModeNormal, 5, 99, 88), key(ColorModeNormal, 5, 0, 0))
    }

    func testDefaultModeMasksGreenBlue() {
        XCTAssertEqual(key(ColorModeAlternate, 1, 7, 3), key(ColorModeAlternate, 1, 0, 0))
    }

    // 24-bit color genuinely uses green/blue, so they must still distinguish.
    func test24BitPreservesGreenBlue() {
        XCTAssertNotEqual(key(ColorMode24bit, 10, 20, 30), key(ColorMode24bit, 10, 0, 0))
    }

    // Different indexed colors, and different modes, must never collide.
    func testDistinctColorsAndModesDoNotCollide() {
        XCTAssertNotEqual(key(ColorModeNormal, 1, 0, 0), key(ColorModeNormal, 2, 0, 0))
        XCTAssertNotEqual(key(ColorModeNormal, 1, 0, 0), key(ColorModeAlternate, 1, 0, 0))
    }
}

// recentShellCommands must keep the last N commands without walking the
// entire prompt-mark history forward every ~5s. The bounded reverse walk
// (enumeratePromptsBackward + stop) must return exactly what the old forward
// walk's suffix did.
final class VT100ScreenPromptBackwardTests: XCTestCase {
    private func screenWithPromptMarks(_ count: Int) -> (VT100Screen, [String]) {
        let session = FakeSession()
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        var guids: [String] = []
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            screen.destructivelySetScreenWidth(20, height: 10, mutableState: mutableState)
            for i in 0..<count {
                let mark = mutableState.addMark(onLine: Int32(i), of: VT100ScreenMark.self) as! VT100ScreenMark
                mutableState.mutableIntervalTree().mutate(mark) { obj in
                    (obj as! VT100ScreenMark).isPrompt = true
                }
                guids.append(mark.guid)
            }
        })
        return (screen, guids)
    }

    private func forwardGuids(_ screen: VT100Screen) -> [String] {
        var out: [String] = []
        screen.enumeratePrompts(from: nil, to: nil) { out.append($0.guid) }
        return out
    }

    // The backward walk visits the same prompts as the forward walk, reversed.
    func testBackwardIsForwardReversed() {
        let (screen, _) = screenWithPromptMarks(5)
        let forward = forwardGuids(screen)
        var backward: [String] = []
        screen.enumeratePromptsBackward { mark, _ in backward.append(mark.guid) }
        XCTAssertEqual(forward.count, 5)
        XCTAssertEqual(backward, forward.reversed())
    }

    // Stopping after K yields exactly the newest K, in newest-first order - the
    // bound that keeps the walk from touching the whole history.
    func testStopBoundsToNewestK() {
        let (screen, _) = screenWithPromptMarks(6)
        let forward = forwardGuids(screen)
        var bounded: [String] = []
        screen.enumeratePromptsBackward { mark, stop in
            bounded.append(mark.guid)
            if bounded.count >= 2 { stop.pointee = true }
        }
        XCTAssertEqual(bounded.count, 2)
        XCTAssertEqual(bounded, Array(forward.reversed().prefix(2)))
    }

    // Reversing the newest-first bounded result reproduces the old
    // forward-walk-then-suffix(N), i.e. the last N in chronological order.
    func testBoundedReversedEqualsForwardSuffix() {
        let (screen, _) = screenWithPromptMarks(6)
        let forward = forwardGuids(screen)
        var newestFirst: [String] = []
        screen.enumeratePromptsBackward { mark, stop in
            newestFirst.append(mark.guid)
            if newestFirst.count >= 3 { stop.pointee = true }
        }
        XCTAssertEqual(newestFirst.reversed(), Array(forward.suffix(3)))
    }
}

@available(macOS 26, *)
final class AppleIntelligenceTokenBudgetTests: XCTestCase {
    // A genuine ceiling: each ASCII char is at most one token, so the
    // estimate counts ASCII at 1/char (over-counting natural text is safe; the
    // alternative - under-counting dense content - overflows the window).
    func testASCIIEstimateIsOnePerChar() {
        XCTAssertEqual(AppleIntelligenceRunner.estimatedTokenUpperBound(String(repeating: "a", count: 300)), 300)
    }

    // The budget-viability check must use the SAME schema basis the real
    // budget uses (exact schema tokens), not a fixed 96. A large schema drives the
    // real budget to its floor even where the old fixed-96 estimate would pass,
    // masking a window that leaves no room for the screen.
    func testBudgetViabilityUsesRealSchemaTokens() {
        let real = AppleIntelligenceRunner.promptBudget(
            maxContextTokens: 1330, outputReserve: 256, instructionTokens: 200, schemaTokens: 700)
        XCTAssertEqual(real, 256, "a large schema drives the real budget to its floor")
        XCTAssertFalse(AppleIntelligenceRunner.budgetLeavesRoomForScreen(real),
                       "a floored budget must be flagged as leaving no room for the screen")
        // Documents the divergence the fix closes: the old fixed-96 estimate passes
        // for exactly these parameters, hiding the floored real budget.
        XCTAssertTrue((1330 - 256 - 200 - 96) > 768,
                      "old fixed-96 assert would have passed here, masking the problem")
        // The shipping-shaped call stays viable.
        let shipping = AppleIntelligenceRunner.promptBudget(
            maxContextTokens: 4096, outputReserve: 256, instructionTokens: 200, schemaTokens: 96)
        XCTAssertTrue(AppleIntelligenceRunner.budgetLeavesRoomForScreen(shipping))
    }

    // The screen reserve, the context floor, and the viability threshold are one
    // invariant. budgetLeavesRoomForScreen must pass exactly when contextBudget =
    // budget - screenReserveTokens rises strictly above the minContextTokens floor, i.e.
    // budget > minContextTokens + screenReserveTokens. Deriving the threshold from the
    // named constants keeps the three sites from drifting.
    func testBudgetViabilityThresholdDerivesFromReserveAndFloor() {
        let threshold = AppleIntelligenceRunner.minContextTokens + AppleIntelligenceRunner.screenReserveTokens
        XCTAssertFalse(AppleIntelligenceRunner.budgetLeavesRoomForScreen(threshold),
                       "a budget exactly at floor+reserve leaves no real room for the screen")
        XCTAssertTrue(AppleIntelligenceRunner.budgetLeavesRoomForScreen(threshold + 1))
        // At the smallest viable budget the context share is strictly above the floor.
        let contextShare = (threshold + 1) - AppleIntelligenceRunner.screenReserveTokens
        XCTAssertGreaterThan(contextShare, AppleIntelligenceRunner.minContextTokens)
    }

    // A single visible line longer than the budget must still contribute a
    // non-empty prefix, so the screen is never dropped entirely (which would title
    // the tab from context alone, or from nothing).
    func testTruncatedLineToFitKeepsPrefix() async throws {
        let line = String(repeating: "x", count: 1000)
        let out = try await AppleIntelligenceRunner.truncatedLineToFit(line, fits: { $0.count <= 100 })
        XCTAssertFalse(out.isEmpty, "an overlong line must still yield a non-empty prefix")
        XCTAssertLessThanOrEqual(out.count, 100)
        XCTAssertTrue(line.hasPrefix(out), "keeps a prefix of the original line")
    }

    // A line that already fits is returned unchanged.
    func testTruncatedLineToFitReturnsFittingLineUnchanged() async throws {
        let line = "short line"
        let out = try await AppleIntelligenceRunner.truncatedLineToFit(line, fits: { $0.count <= 100 })
        XCTAssertEqual(out, line)
    }

    // If nothing fits at all, it converges to empty rather than looping.
    func testTruncatedLineToFitEmptyWhenNothingFits() async throws {
        let out = try await AppleIntelligenceRunner.truncatedLineToFit("abc", fits: { _ in false })
        XCTAssertTrue(out.isEmpty)
    }

    // Dense alphanumeric is now bounded at 1 token/char, a true ceiling.
    func testDenseAlphanumericIsUpperBounded() {
        let dense = String(repeating: "aB3xZ9", count: 50)  // 300 alnum chars
        XCTAssertGreaterThanOrEqual(AppleIntelligenceRunner.estimatedTokenUpperBound(dense), 300)
    }

    // CJK/emoji are ~1+ token per grapheme, so the estimate must NOT
    // under-count them the way count/3 does, or a full non-Latin screen gets
    // budgeted as fitting when it actually overflows the context window.
    func testCJKEstimateCountsEachScalar() {
        let cjk = String(repeating: "文", count: 100)
        XCTAssertGreaterThanOrEqual(AppleIntelligenceRunner.estimatedTokenUpperBound(cjk), 100)
    }

    func testEmojiEstimateNotUndercounted() {
        let emoji = String(repeating: "🔥", count: 50)
        XCTAssertGreaterThanOrEqual(AppleIntelligenceRunner.estimatedTokenUpperBound(emoji), 50)
    }

    // High-entropy alphanumeric (base64, hex, UUIDs, commit hashes, minified
    // JS) tokenizes far denser than the 3-chars/token natural-language average, so
    // the estimate must count alphanumeric conservatively or the pre-26.4 fit
    // check passes an oversized prompt that then overflows the window.
    func testDenseAlphanumericNotUndercounted() {
        let dense = String(repeating: "aB3xZ9", count: 50)  // 300 alnum chars
        XCTAssertGreaterThanOrEqual(AppleIntelligenceRunner.estimatedTokenUpperBound(dense), 150)
    }

    // Punctuation/symbol-dense ASCII tokenizes near 1 token/char, not 1/3,
    // so the estimate must not undercount it (or the fit check passes an oversized
    // prompt). A run of 90 symbols must estimate well above 90/3 = 30.
    func testPunctuationDenseNotUndercounted() {
        let symbols = String(repeating: "{", count: 90)
        XCTAssertGreaterThanOrEqual(AppleIntelligenceRunner.estimatedTokenUpperBound(symbols), 90)
    }

    // A true ceiling: CJK is often 2+ BPE tokens per scalar, so the estimate for
    // 100 CJK scalars should be at least ~2x the naive scalar count.
    func testCJKEstimateIsAnUpperBoundNotJustScalarCount() {
        let cjk = String(repeating: "文", count: 100)
        XCTAssertGreaterThanOrEqual(AppleIntelligenceRunner.estimatedTokenUpperBound(cjk), 200)
    }

    private func estimateMeasure(_ s: String) -> Int {
        return AppleIntelligenceRunner.estimatedTokenUpperBound(s)
    }

    // A context already within budget is returned unchanged.
    func testContextWithinBudgetUnchanged() async throws {
        let ctx = "At a shell prompt.\nDirectory: ~/x\nHost: a@b"
        let out = try await AppleIntelligenceRunner.truncatedContext(ctx, tokenBudget: 1000, measure: estimateMeasure)
        XCTAssertEqual(out, ctx)
    }

    // An oversized context (long recent-command history) must be trimmed so
    // it fits - otherwise the prompt overflows even with the whole screen dropped.
    func testOversizedContextTrimmedToFit() async throws {
        let huge = "Recent commands run in this shell, oldest first:\n"
            + (0..<200).map { "  command-number-\($0)-with-some-length" }.joined(separator: "\n")
        let out = try await AppleIntelligenceRunner.truncatedContext(huge, tokenBudget: 20, measure: estimateMeasure)
        XCTAssertLessThanOrEqual(AppleIntelligenceRunner.estimatedTokenUpperBound(out), 20)
    }

    // The recent-command history sits BEFORE Directory:/Host: in the
    // assembled context, so trimming must drop history first and preserve the
    // compact, high-signal cwd/host lines - not shed them from the end.
    func testTruncateDropsHistoryBeforeCwdAndHost() async throws {
        let context = "At a shell prompt.\n"
            + "Recent commands run in this shell, oldest first:\n"
            + (0..<8).map { "  a-fairly-long-command-number-\($0)" }.joined(separator: "\n") + "\n"
            + "Directory: ~/some/project\n"
            + "Host: gnachman@host"
        let keep = "At a shell prompt.\nDirectory: ~/some/project\nHost: gnachman@host"
        let budget = AppleIntelligenceRunner.estimatedTokenUpperBound(keep) + 30
        let out = try await AppleIntelligenceRunner.truncatedContext(context, tokenBudget: budget, measure: estimateMeasure)
        XCTAssertLessThanOrEqual(AppleIntelligenceRunner.estimatedTokenUpperBound(out), budget)
        XCTAssertTrue(out.contains("Directory: ~/some/project"), "cwd must survive: \(out)")
        XCTAssertTrue(out.contains("Host: gnachman@host"), "host must survive: \(out)")
    }

    // A single overlong line (a huge one-liner command) is hard-truncated.
    func testSingleOverlongLineHardTruncated() async throws {
        let line = String(repeating: "x", count: 10000)
        let out = try await AppleIntelligenceRunner.truncatedContext(line, tokenBudget: 10, measure: estimateMeasure)
        XCTAssertLessThanOrEqual(AppleIntelligenceRunner.estimatedTokenUpperBound(out), 10)
    }

    // When the offender is one oversized MIDDLE line (a giant Command line:)
    // and there is no history to shed, the trimmer must char-truncate that largest
    // line - NOT drop the trailing compact Directory:/Host: lines, which a plain
    // removeLast() would shed first (inverting the priority).
    func testTruncateTargetsOversizedMiddleLineNotCwdHost() async throws {
        let context = "Foreground program: node\n"
            + "Command line: node " + String(repeating: "x", count: 4000) + "\n"
            + "Directory: ~/some/project\n"
            + "Host: gnachman@host"
        // Budget: room for the short lines plus a truncated command, but nowhere near
        // the full 4000-char command line.
        let budget = 60
        let out = try await AppleIntelligenceRunner.truncatedContext(context, tokenBudget: budget, measure: estimateMeasure)
        XCTAssertLessThanOrEqual(AppleIntelligenceRunner.estimatedTokenUpperBound(out), budget)
        XCTAssertTrue(out.contains("Directory: ~/some/project"), "cwd must survive: \(out)")
        XCTAssertTrue(out.contains("Host: gnachman@host"), "host must survive: \(out)")
    }
}

final class CleanedOSCTitleTests: XCTestCase {
    // cleanedOSCTitle is used as a "task changed" signal. A program that
    // animates a TRAILING counter (Building 41% -> 42%, npm install (12s) ->
    // (13s)) must not read as a task change on every tick, the same way a leading
    // spinner already doesn't.
    func testTrailingPercentCounterIsStable() {
        XCTAssertEqual(PTYSession.cleanedOSCTitle("Building 41%"),
                       PTYSession.cleanedOSCTitle("Building 42%"))
    }

    func testTrailingElapsedTimeIsStable() {
        XCTAssertEqual(PTYSession.cleanedOSCTitle("npm install (12s)"),
                       PTYSession.cleanedOSCTitle("npm install (135s)"))
    }

    // A genuine task change (different words) must still register as different.
    func testDifferentTaskStillDiffers() {
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("Building project"),
                          PTYSession.cleanedOSCTitle("Running tests"))
    }

    // The existing leading-spinner behavior is preserved.
    func testLeadingSpinnerStillStripped() {
        XCTAssertEqual(PTYSession.cleanedOSCTitle("⠋ Compiling"),
                       PTYSession.cleanedOSCTitle("⠙ Compiling"))
    }

    // A spinner token (braille or bracketed) animated anywhere - trailing or
    // middle - is dropped so it doesn't churn the OSC change signal every frame.
    func testSpinnerTokenStrippedAnywhere() {
        XCTAssertEqual(PTYSession.cleanedOSCTitle("Building ⠋"),
                       PTYSession.cleanedOSCTitle("Building ⠹"))
        XCTAssertEqual(PTYSession.cleanedOSCTitle("Compiling [⠋]"),
                       PTYSession.cleanedOSCTitle("Compiling [⠸]"))
        XCTAssertEqual(PTYSession.cleanedOSCTitle("Building ⠋ main"),
                       PTYSession.cleanedOSCTitle("Building ⠹ main"))
    }

    // But a token with a number (e.g. a percentage) is kept so the volatile-numeric
    // normalizer still handles it, and a distinct number is still a real change.
    func testSpinnerDropDoesNotEatNumericTokens() {
        XCTAssertEqual(PTYSession.cleanedOSCTitle("Building 41%"),
                       PTYSession.cleanedOSCTitle("Building 42%"))
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("Port 8080"),
                          PTYSession.cleanedOSCTitle("Port 9090"))
    }

    // Digits that distinguish real work (numbered files, issue/PR ids, page
    // numbers) must NOT be collapsed - only volatile counters were the target.
    // Otherwise switching files in an editor (the OSC-title signal exists exactly
    // for this) is swallowed and the tab keeps the first file's title.
    func testNumberedFilenamesStillDiffer() {
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("file1.md"),
                          PTYSession.cleanedOSCTitle("file2.md"))
    }

    func testIssueIdsStillDiffer() {
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("Issue 1234"),
                          PTYSession.cleanedOSCTitle("Issue 5678"))
    }

    func testPageNumbersStillDiffer() {
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("Page 1"),
                          PTYSession.cleanedOSCTitle("Page 2"))
    }

    // A fractional elapsed timer must be neutralized like an integer one.
    func testFractionalElapsedIsStable() {
        XCTAssertEqual(PTYSession.cleanedOSCTitle("Elapsed 1.5s"),
                       PTYSession.cleanedOSCTitle("Elapsed 1.6s"))
    }

    // A combined ISO datetime token (with T) is a clock and must be neutralized.
    func testISODateTimeIsStable() {
        XCTAssertEqual(PTYSession.cleanedOSCTitle("2026-08-30T12:34:56"),
                       PTYSession.cleanedOSCTitle("2026-08-30T12:34:57"))
    }

    // An ISO-8601 timestamp with a trailing zone (Z or +HH:MM) is a live clock
    // and must be neutralized.
    func testISODateTimeWithZoneIsStable() {
        XCTAssertEqual(PTYSession.cleanedOSCTitle("2026-08-30T12:34:56Z"),
                       PTYSession.cleanedOSCTitle("2026-08-30T12:34:57Z"))
        XCTAssertEqual(PTYSession.cleanedOSCTitle("12:34:56+05:00"),
                       PTYSession.cleanedOSCTitle("12:34:57+05:00"))
    }

    // A bare HH:MM-HH:MM time RANGE must NOT be misread as clock+timezone-offset
    // and collapsed: the trailing HH:MM looks like an offset, so the old code stripped
    // it and treated the range as a plain clock, making two different ranges clean to
    // the same token and hiding a real OSC change across a task switch.
    func testTimeRangeIsNotCollapsedAsClockOffset() {
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("Standup 09:00-10:30"),
                          PTYSession.cleanedOSCTitle("Standup 11:00-12:00"))
    }

    // But a genuine timezone offset (ISO datetime, or a seconds-precision time)
    // is still neutralized as a live clock - including an ISO datetime whose time has
    // no seconds, where the T context alone marks the +HH:MM as an offset.
    func testTimezoneOffsetStillCollapses() {
        XCTAssertEqual(PTYSession.cleanedOSCTitle("Build 12:34:56+05:00"),
                       PTYSession.cleanedOSCTitle("Build 12:34:57+05:00"))
        XCTAssertEqual(PTYSession.cleanedOSCTitle("2026-08-30T12:34+05:00"),
                       PTYSession.cleanedOSCTitle("2026-08-30T12:35+05:00"))
    }

    // A 12-hour am/pm clock is a live clock and must be neutralized.
    func testTwelveHourClockIsStable() {
        XCTAssertEqual(PTYSession.cleanedOSCTitle("Build 3:45pm"),
                       PTYSession.cleanedOSCTitle("Build 3:46pm"))
    }

    // Aspect ratios, scores, and host:port are colon-separated digit tokens
    // but NOT clocks (minute/second groups are not the classic 2-digit shape), so
    // switching them is a real OSC task change that must remain distinguishable.
    func testRatiosScoresAndPortsAreNotClocks() {
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("Render 16:9"),
                          PTYSession.cleanedOSCTitle("Render 4:3"))
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("Score 2:1"),
                          PTYSession.cleanedOSCTitle("Score 3:0"))
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("Tunnel 8080:80"),
                          PTYSession.cleanedOSCTitle("Tunnel 9090:80"))
    }

    // But genuine clocks (H:MM and H:MM:SS) are still neutralized.
    func testClassicClockShapesStillNeutralized() {
        XCTAssertEqual(PTYSession.cleanedOSCTitle("at 9:05"),
                       PTYSession.cleanedOSCTitle("at 9:06"))
        XCTAssertEqual(PTYSession.cleanedOSCTitle("at 09:05:33"),
                       PTYSession.cleanedOSCTitle("at 09:05:34"))
    }

    // A 2+2 host:port pair whose values exceed clock ranges (80:80 -> 90:90)
    // must NOT be collapsed as a clock, so the OSC change is still detected.
    func testHostPortPairIsNotClock() {
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("Proxy 80:80"),
                          PTYSession.cleanedOSCTitle("Proxy 90:90"))
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("db 5432:5432"),
                          PTYSession.cleanedOSCTitle("db 6432:6432"))
    }

    // A wall clock / timer in the title must be neutralized so it does not
    // re-fire generation every second.
    func testClockCountersAreStable() {
        XCTAssertEqual(PTYSession.cleanedOSCTitle("Build 12:34:56"),
                       PTYSession.cleanedOSCTitle("Build 12:34:57"))
    }

    func testDateCountersAreStable() {
        XCTAssertEqual(PTYSession.cleanedOSCTitle("Log 2026-08-30"),
                       PTYSession.cleanedOSCTitle("Log 2026-08-31"))
    }

    // The s/m/h unit rule must not fire on filenames that merely contain a
    // digit+letter (1m.log is a file, not "1 minute").
    func testUnitLikeFilenamesStillDiffer() {
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("1m.log"),
                          PTYSession.cleanedOSCTitle("2m.log"))
    }

    // Bracketed elapsed timers are still neutralized.
    func testBracketedElapsedIsStable() {
        XCTAssertEqual(PTYSession.cleanedOSCTitle("npm install (12s)"),
                       PTYSession.cleanedOSCTitle("npm install (135s)"))
    }

    // The ISO-date rule must require the 4-2-2 shape, not merely "two
    // hyphens" - version strings, IP fragments, and step/shard counters must not
    // be treated as volatile dates (or advancing them masks a real title change).
    func testVersionLikeTokensStillDiffer() {
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("1-2-3"),
                          PTYSession.cleanedOSCTitle("1-2-4"))
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("10-0-0"),
                          PTYSession.cleanedOSCTitle("10-0-1"))
    }

    // A genuine ISO date is still neutralized.
    func testRealISODateStillNeutralized() {
        XCTAssertEqual(PTYSession.cleanedOSCTitle("2026-08-30"),
                       PTYSession.cleanedOSCTitle("2026-12-31"))
    }

    // Metric-suffixed counters (Claude Code's "1.2k tokens") must be
    // neutralized so they don't re-fire generation every tick.
    func testMetricSuffixCountersAreStable() {
        XCTAssertEqual(PTYSession.cleanedOSCTitle("Using 1.2k tokens"),
                       PTYSession.cleanedOSCTitle("Using 1.3k tokens"))
        XCTAssertEqual(PTYSession.cleanedOSCTitle("3.4M"),
                       PTYSession.cleanedOSCTitle("3.5M"))
    }

    // All-digit uppercase <n>K / <n>M tokens are resolution/size identifiers
    // (4K, 8K, 1M rows), not animated counters, so switching them is a real task
    // change and must remain distinguishable. (Counters use a lowercase 'k' or a
    // decimal - see testMetricSuffixCountersAreStable - and stay volatile.)
    func testResolutionAndSizeIdentifiersStillDiffer() {
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("encode 4K"),
                          PTYSession.cleanedOSCTitle("encode 8K"))
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("1M rows"),
                          PTYSession.cleanedOSCTitle("5M rows"))
    }

    // N/M progress counters (downloads) must be neutralized.
    func testProgressCountersAreStable() {
        XCTAssertEqual(PTYSession.cleanedOSCTitle("Downloading 42/100"),
                       PTYSession.cleanedOSCTitle("Downloading 43/100"))
    }

    // But the whitelist still preserves real identifiers (the reason we didn't
    // switch to a blanket digit-collapse).
    func testMetricLikeFilenamesStillDiffer() {
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("data1k.csv"),
                          PTYSession.cleanedOSCTitle("data2k.csv"))
    }

    // Single-letter size suffixes (B/G) far more often denote a size that
    // identifies the work than an animated counter, so a model-size or capacity
    // change must remain a distinguishable title (k/M stay volatile for counters).
    func testSizeSuffixesStillDiffer() {
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("Loading 7B model"),
                          PTYSession.cleanedOSCTitle("Loading 13B model"))
        XCTAssertNotEqual(PTYSession.cleanedOSCTitle("Cache 40G"),
                          PTYSession.cleanedOSCTitle("Cache 50G"))
    }
}

// The generation watchdog times out on IDLE (no forward progress), not total
// wall-clock, so a slow-but-progressing on-device generation isn't force-cleaned and its
// title discarded. These pin the shared progress clock and sleepUntilIdle's return-value
// logic. (The reset-on-progress loop is timing-dependent, so it is verified by the box
// tests plus code inspection rather than a sleep-based, flaky assertion.)
final class GenerationProgressTests: XCTestCase {
    func testTouchUpdatesLastActivityTime() {
        let p = GenerationProgress(now: 100.0)
        XCTAssertEqual(p.lastActivityTime, 100.0)
        p.touch(250.0)
        XCTAssertEqual(p.lastActivityTime, 250.0)
    }

    // Progress last touched "long ago" (the 2001 reference date) is already past the
    // idle threshold, so sleepUntilIdle completes immediately and reports NOT cancelled.
    func testSleepUntilIdleCompletesWhenAlreadyIdle() async {
        let p = GenerationProgress(now: 0.0)
        let cancelled = await AITabTitleGenerator.sleepUntilIdle(p, timeoutNanos: 100_000_000)
        XCTAssertFalse(cancelled, "an already-idle generation reaches the threshold, not cancelled")
    }

    // A fresh (not-idle) progress would sleep, but cancelling the task must make it
    // return `cancelled` promptly (the normal-completion path cancels the watchdog).
    func testSleepUntilIdleReportsCancellation() async {
        let p = GenerationProgress(now: Date.timeIntervalSinceReferenceDate)
        let task = Task { await AITabTitleGenerator.sleepUntilIdle(p, timeoutNanos: 10_000_000_000) }
        task.cancel()
        let cancelled = await task.value
        XCTAssertTrue(cancelled, "a cancelled sleepUntilIdle must report cancelled")
    }
}

final class EnableSessionNameComponentTests: XCTestCase {
    private let aiBit = UInt(1) << 12

    // A program-set OSC 0/1/2 title must NOT enable the sticky
    // TemporarySessionName on a profile that selects the AI component - decided purely
    // from profile config, regardless of device availability or the global setting.
    // Otherwise the sticky bit out-ranks the AI title in titleForSessionName for the life
    // of the session and never self-heals when AI later populates (the re-enable bug).
    func testProgramOSCDoesNotEnableTemporaryNameForAIProfile() {
        XCTAssertFalse(PTYSession.programOSCTitleShouldEnableTemporaryName(forComponents: aiBit))
    }

    // Even with AI unavailable / the setting off, an AI profile still does not
    // enable it: the AI-empty degrade in titleForSessionName shows the program's OSC name
    // non-stickily, so nothing is lost and no persistent mask is created.
    func testProgramOSCDoesNotEnableTemporaryNameForAIProfileEvenWhenAITitleEmpty() {
        // (No availability/setting argument any more - the decision is profile-only.)
        XCTAssertFalse(PTYSession.programOSCTitleShouldEnableTemporaryName(forComponents: aiBit))
    }

    // A non-AI profile always enables TemporarySessionName from a program OSC
    // title (unchanged). Deliberate triggers/renames don't come through this gate
    // at all, so they still beat AI per.
    func testProgramOSCEnablesTemporaryNameForNonAIProfile() {
        XCTAssertTrue(PTYSession.programOSCTitleShouldEnableTemporaryName(forComponents: 0))
        let sessionNameBit = UInt(1) << 0
        XCTAssertTrue(PTYSession.programOSCTitleShouldEnableTemporaryName(forComponents: sessionNameBit))
    }
}

@MainActor
final class AITabTitleTerminateTests: XCTestCase {
    // -terminate calls forgetAITitleState, then schedules an async display
    // tick that runs after the session is marked exited. That tick calls
    // maybeUpdateAITitle, which (unguarded) re-populates the generator's
    // per-session dictionaries via shouldAttempt - undoing the forget and leaking
    // one entry per closed session for the life of the process. maybeUpdateAITitle
    // must be a no-op once the session has exited.
    func testExitedSessionDoesNotRepopulateGeneratorState() {
        let key = "AiGeneratedTabTitles"
        let previous = iTermUserDefaults.userDefaults().object(forKey: key)
        iTermUserDefaults.userDefaults().set(true, forKey: key)
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            iTermUserDefaults.userDefaults().set(previous, forKey: key)
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }

        let gen = AITabTitleGenerator.instance
        let session = PTYSession(synthetic: false)!
        // Give it a profile that consumes the AI title so the/ gate lets
        // it through (a synthetic session otherwise has no profile).
        session.profile = [KEY_TITLE_COMPONENTS: NSNumber(value: UInt(1) << 12)]
        let guid = session.guid
        gen.forget(sessionID: guid)
        // A freshly created session is not idle (its last-output time is "now");
        // push it into the past so maybeUpdateAITitle's isIdle gate passes.
        session.setValue(0.0, forKey: "lastOutputIgnoringOutputAfterResizing")

        // A live, idle, feature-on session gets evaluated: state appears. This is
        // the vector that must not fire after the session closes.
        session.maybeUpdateAITitle()
        XCTAssertTrue(gen.hasState(forSessionID: guid),
                      "a live idle session should have been evaluated")

        // Close: forgetAITitleState clears the state.
        session.forgetAITitleState()
        XCTAssertFalse(gen.hasState(forSessionID: guid))

        // The post-terminate async display tick fires with exited == YES. It must
        // leave the generator empty for this guid.
        session.setValue(true, forKey: "exited")
        session.maybeUpdateAITitle()
        XCTAssertFalse(gen.hasState(forSessionID: guid),
                       "a post-exit display tick must not repopulate generator state")

        gen.forget(sessionID: guid)
    }

    // forgetAITitleState (called on restart / guid change) must clear the
    // aiTitle variable, or a stale title from the dead shell lingers on the
    // revived session's tab (forget() wipes lastAppliedTitle, disabling the normal
    // clear-on-idle path).
    func testForgetClearsAITitleVariable() {
        let session = PTYSession(synthetic: false)!
        session.genericScope.setValue("Building Project",
                                      forVariableNamed: iTermVariableKeySessionAITitle)
        XCTAssertEqual(session.genericScope.value(forVariableName: iTermVariableKeySessionAITitle) as? String,
                       "Building Project")
        session.forgetAITitleState()
        let after = session.genericScope.value(forVariableName: iTermVariableKeySessionAITitle) as? String
        XCTAssertTrue(after == nil || after == "", "aiTitle must be cleared: \(after ?? "nil")")
    }

    // A session with no profile is not confirmed to display the AI title, so
    // maybeUpdateAITitle must not run it through the model (a missing profile must
    // not fall through the consume-gate).
    func testNilProfileSessionDoesNotGenerate() {
        let key = "AiGeneratedTabTitles"
        let previous = iTermUserDefaults.userDefaults().object(forKey: key)
        iTermUserDefaults.userDefaults().set(true, forKey: key)
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            iTermUserDefaults.userDefaults().set(previous, forKey: key)
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        let gen = AITabTitleGenerator.instance
        // A fresh synthetic session has no profile.
        let session = PTYSession(synthetic: false)!
        XCTAssertNil(session.profile)
        let guid = session.guid
        gen.forget(sessionID: guid)
        session.setValue(0.0, forKey: "lastOutputIgnoringOutputAfterResizing")

        session.maybeUpdateAITitle()
        // The reorder means the cheap throttle (shouldAttempt) may stamp
        // lastAttempt before the profile gate, but the profile-less session must
        // still not reach generation - nothing goes in flight.
        XCTAssertFalse(gen.isInFlightForTesting(sessionID: guid),
                       "a profile-less session must not be run through the model")
        gen.forget(sessionID: guid)
    }
}

// The corpus is appended concurrently by the shipping app and the Python
// capture script; correctness rests on each line being a SINGLE atomic O_APPEND
// write. atomicAppend encodes the retry policy that keeps that invariant.
final class AITabTitleCorpusAppendTests: XCTestCase {
    // A genuine partial write must NOT be retried: re-appending the leftover bytes at
    // the new end-of-file can splice a concurrent writer's full line into the middle
    // of this record. It must stop after ONE call and report .partial (the record is
    // dropped; load() skips the malformed tail).
    func testPartialWriteIsNotReAppended() {
        var calls = 0
        let outcome = AITabTitleCorpus.atomicAppend(totalBytes: 100) {
            calls += 1
            return (40, false)   // wrote 40 of 100, not interrupted
        }
        XCTAssertEqual(outcome, .partial(40))
        XCTAssertEqual(calls, 1, "a partial write must not trigger a spliceable re-append")
    }

    // A write interrupted before doing anything (EINTR) wrote nothing, so retrying
    // cannot splice - it must retry until the record lands.
    func testInterruptedWriteRetriesUntilComplete() {
        var calls = 0
        let outcome = AITabTitleCorpus.atomicAppend(totalBytes: 10) {
            calls += 1
            if calls < 3 { return (-1, true) }   // EINTR twice, then success
            return (10, false)
        }
        XCTAssertEqual(outcome, .complete)
        XCTAssertEqual(calls, 3)
    }

    func testCompleteWriteInOneCall() {
        var calls = 0
        let outcome = AITabTitleCorpus.atomicAppend(totalBytes: 10) {
            calls += 1
            return (10, false)
        }
        XCTAssertEqual(outcome, .complete)
        XCTAssertEqual(calls, 1)
    }

    // A hard error (not EINTR) is reported and not retried.
    func testHardErrorReportedAndNotRetried() {
        var calls = 0
        let outcome = AITabTitleCorpus.atomicAppend(totalBytes: 10) {
            calls += 1
            return (-1, false)
        }
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(calls, 1)
    }

    // A perpetual EINTR stream must be bounded, not busy-loop forever. On a
    // regular file this never happens, but the cap is a safety backstop.
    func testInterruptedWriteIsBoundedAndFailsAfterCap() {
        var calls = 0
        let outcome = AITabTitleCorpus.atomicAppend(totalBytes: 10) {
            calls += 1
            return (-1, true)   // perpetually interrupted
        }
        XCTAssertEqual(outcome, .failed, "an unbounded EINTR stream must terminate as .failed")
        XCTAssertEqual(calls, AITabTitleCorpus.maxInterruptedRetries + 1,
                       "EINTR retries must be bounded by the cap")
    }
}

// PTYSession-level AI-title lifecycle: the title must not be persisted
// into arrangements (it is re-derived on restore), and disabling the feature must
// clear an applied title promptly rather than waiting for a display tick.
@MainActor
final class PTYSessionAITitleLifecycleTests: XCTestCase {
    // A generated AI tab title is screen-derived and re-generated on restore (the
    // restore path skips it), so persisting it is dead data and would leak a model
    // summary of the screen into the on-disk plist. It must be stripped from the
    // encoded arrangement variables, mirroring the restore-side skip.
    func testArrangementVariablesOmitAITitle() {
        let s = PTYSession(synthetic: false)!
        s.genericScope.setValue("Editing AppleIntelligenceRunner.swift",
                                forVariableNamed: iTermVariableKeySessionAITitle)
        s.genericScope.setValue("Profile Name",
                                forVariableNamed: iTermVariableKeySessionAutoNameFormat)
        let vars = s.encodableArrangementVariables()
        XCTAssertNil(vars[iTermVariableKeySessionAITitle],
                     "the AI title must not be persisted into an arrangement")
        XCTAssertEqual(vars[iTermVariableKeySessionAutoNameFormat] as? String, "Profile Name",
                       "other variables must still be persisted (the filter is surgical)")
    }

    private static let aiSettingKey = "AiGeneratedTabTitles"

    private func withAITabTitles(_ enabled: Bool, _ body: () -> Void) {
        let previous = iTermUserDefaults.userDefaults().object(forKey: Self.aiSettingKey)
        iTermUserDefaults.userDefaults().set(enabled, forKey: Self.aiSettingKey)
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            iTermUserDefaults.userDefaults().set(previous, forKey: Self.aiSettingKey)
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        body()
    }

    // With the feature OFF, firing the settings-change observer must clear an
    // already-applied AI title immediately.
    func testDisablingFeatureClearsAppliedAITitle() {
        withAITabTitles(false) {
            let s = PTYSession(synthetic: false)!
            s.genericScope.setValue("Stale AI Title", forVariableNamed: iTermVariableKeySessionAITitle)
            s.clearAppliedAITitleIfFeatureDisabled()
            let after = s.genericScope.value(forVariableName: iTermVariableKeySessionAITitle) as? String
            XCTAssertEqual(after, "", "disabling the feature must clear an applied AI title")
        }
    }

    // The mirror image: with the feature ON, the observer must NOT touch an applied
    // title (turning it on regenerates on the next tick; this path is a no-op).
    func testEnablingFeatureLeavesAppliedAITitleAlone() {
        withAITabTitles(true) {
            let s = PTYSession(synthetic: false)!
            s.genericScope.setValue("Live AI Title", forVariableNamed: iTermVariableKeySessionAITitle)
            s.clearAppliedAITitleIfFeatureDisabled()
            let after = s.genericScope.value(forVariableName: iTermVariableKeySessionAITitle) as? String
            XCTAssertEqual(after, "Live AI Title", "with the feature on, the observer must not clear the title")
        }
    }
}

// The context builder (AITabTitleContext.assembleText) and the trimmer
// (AppleIntelligenceRunner.truncatedContext) agree on line structure only through
// shared constants. These tests pin that agreement so a header/indent rename can't
// silently make the trimmer shed the high-signal cwd/host lines instead of history.
final class AITabTitleContextTrimmerCouplingTests: XCTestCase {
    private func assembled() -> String {
        return AITabTitleContext.assembleText(
            job: nil, commandLine: nil, atPrompt: true, lastCommand: nil,
            recentCommands: ["git status", "git add -p", "git commit"],
            cwd: "/Users/x/proj", user: "x", host: "h", home: "/Users/x")
    }

    func testAssembledContextCarriesTheMarkersTheTrimmerMatches() {
        let lines = assembled().components(separatedBy: "\n")
        XCTAssertTrue(lines.contains { $0.hasSuffix(AITabTitleContext.historyHeaderSuffix) },
                      "the history header must end with the suffix the trimmer matches")
        XCTAssertTrue(lines.contains { $0.hasPrefix(AITabTitleContext.historyLinePrefix) },
                      "each history command must carry the indent the trimmer matches")
        XCTAssertTrue(lines.contains { $0.hasPrefix(AITabTitleContext.directoryLinePrefix) },
                      "the cwd line must carry the prefix the trimmer protects")
        XCTAssertTrue(lines.contains { $0.hasPrefix(AITabTitleContext.hostLinePrefix) },
                      "the host line must carry the prefix the trimmer protects")
    }

    // End-to-end: an over-budget context sheds history first and KEEPS cwd/host.
    func testTruncatedContextShedsHistoryButProtectsCwdAndHost() async throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("truncatedContext is gated to macOS 26")
        }
        let text = AITabTitleContext.assembleText(
            job: nil, commandLine: nil, atPrompt: true, lastCommand: nil,
            recentCommands: (0..<20).map { "command-number-\($0)-with-padding-text" },
            cwd: "/Users/x/proj", user: "x", host: "h", home: "/Users/x")
        // Budget measured in characters (fake tokenizer). Small enough to force
        // shedding history, but larger than the compact cwd/host lines.
        let out = try await AppleIntelligenceRunner.truncatedContext(text, tokenBudget: 60) { $0.count }
        XCTAssertTrue(out.hasPrefix("") && out.contains(AITabTitleContext.directoryLinePrefix),
                      "the cwd line must survive trimming")
        XCTAssertTrue(out.contains(AITabTitleContext.hostLinePrefix),
                      "the host line must survive trimming")
        XCTAssertFalse(out.contains("command-number-0-"),
                       "old history commands must be shed first")
    }
}

// The AI-branch degrade in titleForSessionName must not surface a tab-domain
// value (the OSC 1 icon name) in the WINDOW title, and must still use the icon name
// for the TAB title.
final class AITitleWindowDegradeTests: XCTestCase {
    private func title(isWindow: Bool, iconName: String?, windowName: String?, aiTitle: String?) -> String {
        return iTermSessionTitleBuiltInFunction.title(
            forSessionName: "the-session-name",
            profileName: "Prof",
            job: "", commandLine: "", pwd: "", tty: "", user: "", host: "",
            aiTitle: aiTitle, homeDirectory: nil, tmuxPane: nil,
            iconName: iconName, windowName: windowName,
            tmuxWindowName: nil, tmuxWindowTitle: nil,
            rows: 0, columns: 0,
            components: .AI, isWindowTitle: isWindow)
    }

    // WINDOW title, no OSC 2 window name, no AI title yet, but an OSC 1 icon name is
    // set: the degrade must use the session name, NOT leak the icon (tab) name.
    func testAIWindowTitleDegradeDoesNotLeakIconName() {
        let result = title(isWindow: true, iconName: "tab-icon-name", windowName: nil, aiTitle: nil)
        XCTAssertEqual(result, "the-session-name",
                       "AI window-title degrade must use the session name, not the OSC 1 icon name")
        XCTAssertNotEqual(result, "tab-icon-name")
    }

    // TAB title in the same state still degrades to the icon name (the tab-domain name).
    func testAITabTitleDegradeStillUsesIconName() {
        let result = title(isWindow: false, iconName: "tab-icon-name", windowName: nil, aiTitle: nil)
        XCTAssertEqual(result, "tab-icon-name",
                       "AI tab-title degrade should still use the OSC 1 icon name")
    }

    private func emptyResultTitle(isWindow: Bool) -> String {
        return iTermSessionTitleBuiltInFunction.title(
            forSessionName: "", profileName: "",
            job: "", commandLine: "", pwd: "", tty: "", user: "", host: "",
            aiTitle: "", homeDirectory: nil, tmuxPane: nil,
            iconName: nil, windowName: nil,
            tmuxWindowName: nil, tmuxWindowTitle: nil,
            rows: 0, columns: 0,
            components: .AI, isWindowTitle: isWindow)
    }

    // An AI WINDOW title with an empty result keeps the historical single space,
    // NOT "Shell" - the icon/window/Shell fallback is tab-only.
    func testAIWindowTitleEmptyResultIsSingleSpaceNotShell() {
        XCTAssertEqual(emptyResultTitle(isWindow: true), " ",
                       "AI window title empty result must be a single space, not Shell")
    }

    // The AI TAB fallback is unchanged: an empty result still degrades to Shell.
    func testAITabTitleEmptyResultStillUsesShellFallback() {
        XCTAssertEqual(emptyResultTitle(isWindow: false), "Shell")
    }

    // Drift guard for the masking precedence the Swift generation gate
    // (sessionConsumesAITitle's isMaskedByTemporaryName) mirrors: the renderer masks the
    // AI title when TemporarySessionName is set AND the effective session name is
    // non-empty, and shows the AI title otherwise. If the renderer's precedence changes,
    // these fail - a signal to re-check the gate, which has no compile-time link to it.
    private func tabTitle(components: iTermTitleComponents, sessionName: String, aiTitle: String?) -> String {
        return iTermSessionTitleBuiltInFunction.title(
            forSessionName: sessionName, profileName: "Prof",
            job: "", commandLine: "", pwd: "", tty: "", user: "", host: "",
            aiTitle: aiTitle, homeDirectory: nil, tmuxPane: nil,
            iconName: nil, windowName: nil,
            tmuxWindowName: nil, tmuxWindowTitle: nil,
            rows: 0, columns: 0,
            components: components, isWindowTitle: false)
    }

    func testRendererMasksAITitleWhenTemporaryNameActiveWithNonEmptyName() {
        let masked = iTermTitleComponents(rawValue: iTermTitleComponents.AI.rawValue
                                          | iTermTitleComponents.temporarySessionName.rawValue)
        // TemporarySessionName set + non-empty effective name -> the manual name wins,
        // the AI title is masked (matches the gate returning "not consumed").
        XCTAssertEqual(tabTitle(components: masked, sessionName: "Manual Name", aiTitle: "Model Guess"),
                       "Manual Name")
    }

    func testRendererShowsAITitleWhenTemporaryNameActiveButEffectiveNameEmpty() {
        let masked = iTermTitleComponents(rawValue: iTermTitleComponents.AI.rawValue
                                          | iTermTitleComponents.temporarySessionName.rawValue)
        // TemporarySessionName set but EMPTY effective name -> not masked -> AI title shows
        // (matches the gate returning "consumed").
        XCTAssertEqual(tabTitle(components: masked, sessionName: "", aiTitle: "Model Guess"),
                       "Model Guess")
    }

    // An OSC 2 window name wins verbatim for the WINDOW title of an AI profile,
    // exactly like a non-AI profile: no model guess, and NO Job/Size suffix even when
    // those components are also selected. Enabling the AI tab-title component must not
    // change what the window titlebar shows.
    func testAIWindowTitleShowsOSC2VerbatimWithNoSuffix() {
        let result = iTermSessionTitleBuiltInFunction.title(
            forSessionName: "the-session-name",
            profileName: "Prof",
            job: "psql", commandLine: "", pwd: "", tty: "", user: "", host: "",
            aiTitle: "Model Guess", homeDirectory: nil, tmuxPane: nil,
            iconName: nil, windowName: "prod-db",
            tmuxWindowName: nil, tmuxWindowTitle: nil,
            rows: 0, columns: 0,
            components: iTermTitleComponents(rawValue: iTermTitleComponents.AI.rawValue | iTermTitleComponents.job.rawValue),
            isWindowTitle: true)
        XCTAssertEqual(result, "prod-db",
                       "OSC 2 window name must win verbatim for an AI window title, no Job suffix")
    }

    private func aiAndJob() -> iTermTitleComponents {
        return iTermTitleComponents(rawValue: iTermTitleComponents.AI.rawValue | iTermTitleComponents.job.rawValue)
    }

    // A tmux WINDOW title with a set-titles-string uses it (+ Job suffix), NOT the
    // AI title - the collapse of the old branches 1/2/4a into effectiveSessionName must
    // preserve the tmux window-title chain (tmuxWindowTitle first).
    func testAITmuxWindowTitleUsesSetTitlesString() {
        let result = iTermSessionTitleBuiltInFunction.title(
            forSessionName: "sess", profileName: "Prof",
            job: "git push", commandLine: "", pwd: "", tty: "", user: "", host: "",
            aiTitle: "Model Guess", homeDirectory: nil,
            tmuxPane: "pane-title",
            iconName: nil, windowName: nil,
            tmuxWindowName: "winname", tmuxWindowTitle: "MyWindow",
            rows: 0, columns: 0,
            components: aiAndJob(), isWindowTitle: true)
        XCTAssertEqual(result, "MyWindow (git push)",
                       "tmux window title uses the set-titles-string, not the AI title")
    }

    // A tmux WINDOW title with an OSC 2 window name but no set-titles-string falls to the
    // window name (the old branch 2), still not the AI title.
    func testAITmuxWindowTitleFallsToWindowName() {
        let result = iTermSessionTitleBuiltInFunction.title(
            forSessionName: "sess", profileName: "Prof",
            job: "git push", commandLine: "", pwd: "", tty: "", user: "", host: "",
            aiTitle: "Model Guess", homeDirectory: nil,
            tmuxPane: "pane-title",
            iconName: nil, windowName: "OSCWin",
            tmuxWindowName: "winname", tmuxWindowTitle: nil,
            rows: 0, columns: 0,
            components: aiAndJob(), isWindowTitle: true)
        XCTAssertEqual(result, "OSCWin (git push)",
                       "tmux window title falls to the OSC 2 window name, not the AI title")
    }

    // The TAB title of the same AI profile still uses the AI title (+ Job suffix): the
    // window-title verbatim rule must not leak into the tab title.
    func testAITabTitleStillUsesAITitleWithSuffix() {
        let result = iTermSessionTitleBuiltInFunction.title(
            forSessionName: "the-session-name",
            profileName: "Prof",
            job: "psql", commandLine: "", pwd: "", tty: "", user: "", host: "",
            aiTitle: "Model Guess", homeDirectory: nil, tmuxPane: nil,
            iconName: nil, windowName: "prod-db",
            tmuxWindowName: nil, tmuxWindowTitle: nil,
            rows: 0, columns: 0,
            components: iTermTitleComponents(rawValue: iTermTitleComponents.AI.rawValue | iTermTitleComponents.job.rawValue),
            isWindowTitle: false)
        XCTAssertEqual(result, "Model Guess (psql)",
                       "the AI tab title still applies, with the Job suffix")
    }
}
