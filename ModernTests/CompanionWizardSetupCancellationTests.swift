//
//  CompanionWizardSetupCancellationTests.swift
//  iTerm2 ModernTests
//
//  QA finding F-036: closing the companion setup wizard while it downloaded did
//  not cancel setup. The plugin was still installed, an unexplained admin
//  password prompt appeared, and cancelling it brought the closed wizard back
//  with “Setup Could Not Be Completed”. Closing must abort with no consent
//  prompt, nothing written, and nothing shown. All side effects are fakes: no
//  network and no admin prompt.
//

import XCTest
@testable import iTerm2SharedARC

/// A step that blocks until the test releases it, and tells the test it began.
@MainActor
private final class Gate {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    /// Called by the fake step.
    func pass() async {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters = []
        if released {
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Called by the test: returns once the fake step is blocked in pass().
    func waitUntilStarted() async {
        if started {
            return
        }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        released = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

@MainActor
private final class FakeSteps {
    var log: [String] = []
    var writes: [CompanionWizardAIKeyPlan.Write] = []
    let aiGate = Gate()
    let companionGate = Gate()
    var blockAI = false
    var blockCompanion = false
    /// Errors thrown by the install steps, e.g. URLSession's cancellation error.
    var companionError: Error?
    var consentError: Error?
    /// Run during grantConsent, e.g. the window closing while the prompt is up.
    var duringConsent: () -> Void = {}

    var steps: CompanionWizardSetupSteps {
        return CompanionWizardSetupSteps(
            installAIPlugin: { [self] in
                log.append("installAI")
                if blockAI { await aiGate.pass() }
            },
            installCompanionPlugin: { [self] in
                log.append("installCompanion")
                if blockCompanion { await companionGate.pass() }
                if let companionError { throw companionError }
            },
            grantConsent: { [self] ai, companion in
                log.append("grantConsent(ai: \(ai), companion: \(companion))")
                duringConsent()
                if let consentError { throw consentError }
            },
            revokeAIConsent: { [self] in log.append("revokeAI") },
            revokeCompanionConsent: { [self] in log.append("revokeCompanion") },
            writeAIKey: { [self] write in
                log.append("writeKey")
                writes.append(write)
            })
    }
}

private struct FakeError: Error {}

@MainActor
final class CompanionWizardSetupCancellationTests: XCTestCase {
    private typealias Runner = CompanionWizardSetupRunner

    private let commit = CompanionWizardAIKeyPlan.Write(vendor: .openAI, key: "new", vendorPreference: 1)
    private let rollback = CompanionWizardAIKeyPlan.Write(vendor: .openAI, key: "old", vendorPreference: 2)

    private func plan(full: Bool, storesKey: Bool = false) -> Runner.Plan {
        return Runner.Plan(full: full,
                           keyCommit: storesKey ? commit : nil,
                           keyRollback: storesKey ? rollback : nil,
                           priorEnableAI: false,
                           priorEnableCompanion: false)
    }

    private func isCancelled(_ outcome: Runner.Outcome) -> Bool {
        if case .cancelled = outcome { return true }
        return false
    }

    // MARK: - Runner

    func testCompletesWhenNotCancelled() async {
        let fake = FakeSteps()
        let outcome = await Runner.run(plan: plan(full: true, storesKey: true),
                                       steps: fake.steps,
                                       isCancelled: { false },
                                       progress: { _ in },
                                       verify: { .ready })
        guard case .completed = outcome else {
            return XCTFail("Expected completed, got \(outcome)")
        }
        XCTAssertEqual(fake.log, ["installAI", "installCompanion",
                                  "grantConsent(ai: true, companion: true)", "writeKey"])
        XCTAssertEqual(fake.writes, [commit])
    }

    func testClosedDuringCompanionDownloadStopsBeforeConsent() async {
        let fake = FakeSteps()
        fake.blockCompanion = true
        var cancelled = false
        let task = Task { @MainActor in
            await Runner.run(plan: plan(full: false),
                             steps: fake.steps,
                             isCancelled: { cancelled },
                             progress: { _ in },
                             verify: { .ready })
        }
        await fake.companionGate.waitUntilStarted()
        cancelled = true
        fake.companionGate.release()
        let outcome = await task.value
        XCTAssertTrue(isCancelled(outcome), "\(outcome)")
        XCTAssertEqual(fake.log, ["installCompanion"])
    }

    func testClosedDuringAIDownloadSkipsCompanionInstallAndConsent() async {
        let fake = FakeSteps()
        fake.blockAI = true
        var cancelled = false
        let task = Task { @MainActor in
            await Runner.run(plan: plan(full: true, storesKey: true),
                             steps: fake.steps,
                             isCancelled: { cancelled },
                             progress: { _ in },
                             verify: { .ready })
        }
        await fake.aiGate.waitUntilStarted()
        cancelled = true
        fake.aiGate.release()
        let outcome = await task.value
        XCTAssertTrue(isCancelled(outcome), "\(outcome)")
        XCTAssertEqual(fake.log, ["installAI"])
        XCTAssertEqual(fake.writes, [])
    }

    func testDownloadErrorFromCancellationIsNotReportedAsFailure() async {
        // URLSession throws when its Task is cancelled. That must not surface
        // as “Setup Could Not Be Completed”.
        let fake = FakeSteps()
        fake.blockCompanion = true
        fake.companionError = URLError(.cancelled)
        var cancelled = false
        let task = Task { @MainActor in
            await Runner.run(plan: plan(full: false),
                             steps: fake.steps,
                             isCancelled: { cancelled },
                             progress: { _ in },
                             verify: { .ready })
        }
        await fake.companionGate.waitUntilStarted()
        cancelled = true
        fake.companionGate.release()
        let outcome = await task.value
        XCTAssertTrue(isCancelled(outcome), "\(outcome)")
        XCTAssertEqual(fake.log, ["installCompanion"])
    }

    func testClosedWhileConsentPromptIsUpRollsBackSilently() async {
        let fake = FakeSteps()
        var cancelled = false
        fake.duringConsent = { cancelled = true }
        let outcome = await Runner.run(plan: plan(full: true, storesKey: true),
                                       steps: fake.steps,
                                       isCancelled: { cancelled },
                                       progress: { _ in },
                                       verify: { .ready })
        XCTAssertTrue(isCancelled(outcome), "\(outcome)")
        XCTAssertEqual(fake.log, ["installAI", "installCompanion",
                                  "grantConsent(ai: true, companion: true)",
                                  "revokeAI", "revokeCompanion"])
        XCTAssertEqual(fake.writes, [])
    }

    func testClosedWhileConsentPromptIsUpAndThenDeniedIsNotAFailure() async {
        // Choosing Don’t Allow on a prompt for a wizard that is already closed
        // must not bring it back with a failure sheet.
        let fake = FakeSteps()
        var cancelled = false
        fake.duringConsent = { cancelled = true }
        fake.consentError = FakeError()
        let outcome = await Runner.run(plan: plan(full: false),
                                       steps: fake.steps,
                                       isCancelled: { cancelled },
                                       progress: { _ in },
                                       verify: { .ready })
        XCTAssertTrue(isCancelled(outcome), "\(outcome)")
        XCTAssertEqual(fake.log, ["installCompanion", "grantConsent(ai: false, companion: true)"])
    }

    func testFailureWithoutCancellationRollsBackAndReports() async {
        let fake = FakeSteps()
        let outcome = await Runner.run(plan: plan(full: true, storesKey: true),
                                       steps: fake.steps,
                                       isCancelled: { false },
                                       progress: { _ in },
                                       verify: { .pluginsNotLoaded })
        guard case .failed = outcome else {
            return XCTFail("Expected failed, got \(outcome)")
        }
        XCTAssertEqual(fake.log, ["installAI", "installCompanion",
                                  "grantConsent(ai: true, companion: true)", "writeKey",
                                  "revokeAI", "revokeCompanion", "writeKey"])
        XCTAssertEqual(fake.writes, [commit, rollback])
    }

    // MARK: - Window controller

    /// The QA repro: Terminal Viewing & Control Only > Install, then close the
    /// window while “Downloading the companion plugin…” shows.
    func testClosingWizardWindowDuringDownloadCancelsSetup() async throws {
        let fake = FakeSteps()
        fake.blockCompanion = true
        let wizard = CompanionWizardWindowController()
        wizard.setupSteps = fake.steps
        wizard.show(startingAt: .companionOnly)
        let window = try XCTUnwrap(wizard.window)
        defer { window.orderOut(nil) }
        wizard.perform(NSSelectorFromString("installPressed:"), with: nil)
        let installTask = try XCTUnwrap(wizard.installTask)

        await fake.companionGate.waitUntilStarted()
        window.performClose(nil)
        XCTAssertFalse(window.isVisible)
        fake.companionGate.release()
        await installTask.value

        XCTAssertEqual(fake.log, ["installCompanion"])
        XCTAssertFalse(window.isVisible, "A closed wizard must not come back")
        XCTAssertNil(window.attachedSheet)
    }

    /// Cmd-W is the Close menu item, whose action is closeCurrentSession:, not
    /// performClose:. Unless the wizard handles it, the action goes to the main
    /// terminal window (closing a session there) or the item is disabled, and
    /// the wizard keeps installing.
    func testCloseMenuItemClosesWizardAndCancelsSetup() async throws {
        let fake = FakeSteps()
        fake.blockCompanion = true
        let wizard = CompanionWizardWindowController()
        wizard.setupSteps = fake.steps
        wizard.show(startingAt: .companionOnly)
        let window = try XCTUnwrap(wizard.window)
        defer { window.orderOut(nil) }
        wizard.perform(NSSelectorFromString("installPressed:"), with: nil)
        let installTask = try XCTUnwrap(wizard.installTask)

        await fake.companionGate.waitUntilStarted()
        let close = NSSelectorFromString("closeCurrentSession:")
        let item = NSMenuItem(title: "Close", action: close, keyEquivalent: "w")
        XCTAssertTrue((wizard as NSObject as? NSMenuItemValidation)?.validateMenuItem(item) ?? false,
                      "The Close menu item must be enabled for the wizard")
        // The window's responder chain is what the Close menu item reaches
        // when the wizard is key.
        XCTAssertTrue(window.tryToPerform(close, with: item))
        XCTAssertFalse(window.isVisible)
        fake.companionGate.release()
        await installTask.value

        XCTAssertEqual(fake.log, ["installCompanion"])
        XCTAssertFalse(window.isVisible)
    }
}
