import XCTest
@testable import it2core

/// The decision AgentHookAuth makes for a hook that needs a cookie: send, give up, or wait for the
/// consent helper. Issue 13175: hooks must never add to a pile of pending consent requests.
final class AgentHookAuthTests: XCTestCase {
    private final class Recorder {
        var checks: [AgentHookAuth.Permission]
        var lockHeld = false
        var helperRuns = 0
        var cookieRequests = 0
        /// What the next check returns after the helper runs, if different.
        var afterHelper: AgentHookAuth.Permission?

        init(_ checks: [AgentHookAuth.Permission]) {
            self.checks = checks
        }

        var steps: AgentHookAuth.Steps {
            return AgentHookAuth.Steps(
                check: { self.checks.removeFirst() },
                consentRequestInProgress: { self.lockHeld },
                runConsentHelper: { self.helperRuns += 1 },
                requestCookie: {
                    self.cookieRequests += 1
                    return ("cookie", "key")
                })
        }
    }

    func testPermittedSendsWithoutHelper() {
        let r = Recorder([.permitted])
        let result = AgentHookAuth.credentials(r.steps)
        XCTAssertEqual(result.cookie, "cookie")
        XCTAssertEqual(result.key, "key")
        XCTAssertEqual(r.helperRuns, 0)
        XCTAssertEqual(r.cookieRequests, 1)
    }

    func testDeniedNotRunningAndUnavailableGiveUpQuietly() {
        for permission in [AgentHookAuth.Permission.denied, .notRunning, .unavailable] {
            let r = Recorder([permission])
            let result = AgentHookAuth.credentials(r.steps)
            XCTAssertNil(result.cookie, "\(permission)")
            XCTAssertEqual(r.helperRuns, 0, "\(permission)")
            XCTAssertEqual(r.cookieRequests, 0, "\(permission)")
        }
    }

    // The serial case: the first hook waits for the user, then gets its cookie.
    func testNeedsConsentWithNoPromptPendingWaitsForHelperThenSends() {
        let r = Recorder([.needsConsent, .permitted])
        let result = AgentHookAuth.credentials(r.steps)
        XCTAssertEqual(result.cookie, "cookie")
        XCTAssertEqual(r.helperRuns, 1)
        XCTAssertEqual(r.cookieRequests, 1)
    }

    // A prompt is already up: don't start another helper and don't send an event that would
    // queue behind it in iTerm2.
    func testNeedsConsentWhilePromptPendingGivesUpAtOnce() {
        let r = Recorder([.needsConsent])
        r.lockHeld = true
        let result = AgentHookAuth.credentials(r.steps)
        XCTAssertNil(result.cookie)
        XCTAssertEqual(r.helperRuns, 0)
        XCTAssertEqual(r.cookieRequests, 0)
        // Not even checked: tccd holds the check while a prompt is up.
        XCTAssertEqual(r.checks, [.needsConsent])
    }

    func testUserDeclinesAfterHelperGivesUp() {
        let r = Recorder([.needsConsent, .denied])
        let result = AgentHookAuth.credentials(r.steps)
        XCTAssertNil(result.cookie)
        XCTAssertEqual(r.helperRuns, 1)
        XCTAssertEqual(r.cookieRequests, 0)
    }

    // The helper lost a race or couldn't prompt: still undecided, so don't send.
    func testStillNeedsConsentAfterHelperGivesUp() {
        let r = Recorder([.needsConsent, .needsConsent])
        let result = AgentHookAuth.credentials(r.steps)
        XCTAssertNil(result.cookie)
        XCTAssertEqual(r.helperRuns, 1)
        XCTAssertEqual(r.cookieRequests, 0)
    }

    func testOnlyHandleAgentHookUsesTheNewPolicy() {
        XCTAssertEqual(CookieAuth.policy, .appleScript)
        CookieAuth.$policy.withValue(.agentHook) {
            XCTAssertEqual(CookieAuth.policy, .agentHook)
        }
        XCTAssertEqual(CookieAuth.policy, .appleScript)
    }

    func testHelperArgumentsAddressTheSameInstance() {
        XCTAssertEqual(AgentHookAuth.Target.bundleID("com.example").arguments, ["--bundle-id", "com.example"])
        XCTAssertEqual(AgentHookAuth.Target.pid(123).arguments, ["--pid", "123"])
    }

    func testRequestConsentIsHiddenAndParses() throws {
        let command = try IT2.parseAsRoot(["request-consent", "--pid", "42"])
        XCTAssertEqual((command as? RequestConsent)?.pid, 42)
        XCTAssertFalse(RequestConsent.configuration.shouldDisplay)
    }

    // MARK: - ConsentLock

    private func temporaryLockPath() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConsentLockTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
        }
        return dir.appendingPathComponent("it2-consent.lock").path
    }

    func testLockIsFreeUntilAHelperTakesIt() throws {
        let path = try temporaryLockPath()
        XCTAssertFalse(ConsentLock.isHeld(path: path))
        let fd = try XCTUnwrap(ConsentLock.acquire(path: path))
        XCTAssertTrue(ConsentLock.isHeld(path: path))
        close(fd)
        XCTAssertFalse(ConsentLock.isHeld(path: path))
    }

    // Hooks probe constantly. A probe in progress must not look like a helper to another probe,
    // or hooks would give up while consent is already granted.
    func testProbesDoNotCollideWithEachOther() throws {
        let path = try temporaryLockPath()
        let otherProbe = open(path, O_RDWR | O_CREAT, 0o600)
        XCTAssertGreaterThanOrEqual(otherProbe, 0)
        defer {
            close(otherProbe)
        }
        XCTAssertEqual(flock(otherProbe, LOCK_SH | LOCK_NB), 0)
        XCTAssertFalse(ConsentLock.isHeld(path: path))
    }

    func testSymlinkAtLockPathIsNotFollowed() throws {
        let path = try temporaryLockPath()
        let elsewhere = path + "-elsewhere"
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: elsewhere)
        XCTAssertTrue(ConsentLock.isHeld(path: path))
        XCTAssertNil(ConsentLock.acquire(path: path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: elsewhere))
    }

    // proc_pidpath reports /private/var/..., where a translocated app runs from. The app path
    // must be canonicalized the same way or the running iTerm2 is never found.
    func testCanonicalPathKeepsPrivate() {
        XCTAssertEqual(AgentHookAuth.Target.canonicalPath("/tmp"), "/private/tmp")
        XCTAssertEqual(AgentHookAuth.Target.canonicalPath("/private/tmp"), "/private/tmp")
        XCTAssertNil(AgentHookAuth.Target.canonicalPath("/nonexistent-\(UUID().uuidString)"))
    }
}
