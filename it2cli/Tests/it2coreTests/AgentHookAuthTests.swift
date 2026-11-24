import XCTest
@testable import it2core

/// The decision AgentHookAuth makes for a hook that needs a cookie: send, give up, or wait for the
/// consent helper. Issue 13175: hooks must never add to a pile of pending consent requests.
final class AgentHookAuthTests: XCTestCase {
    private final class Recorder {
        var checks: [AgentHookAuth.Permission]
        var lockHeld = false
        var allAppsAllowed = false
        var helperRuns = 0
        var cookieRequests = 0
        /// What the next check returns after the helper runs, if different.
        var afterHelper: AgentHookAuth.Permission?

        init(_ checks: [AgentHookAuth.Permission]) {
            self.checks = checks
        }

        var steps: AgentHookAuth.Steps {
            return AgentHookAuth.Steps(
                allAppsAllowed: { self.allAppsAllowed },
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
        XCTAssertEqual(AgentHookAuth.credentials(r.steps), .connect(cookie: "cookie", key: "key"))
        XCTAssertEqual(r.helperRuns, 0)
        XCTAssertEqual(r.cookieRequests, 1)
    }

    // No cookie can be had, but iTerm2 accepts a cookieless connection when all apps are
    // allowed, so still connect. .unavailable covers statuses this code doesn't recognize (an odd
    // TCC state, an MDM profile), which won't pass on their own; skipping on them would silently
    // break hooks for good for someone who allows all apps.
    func testDeniedNotRunningAndUnrecognizedConnectWithoutCookie() {
        for permission in [AgentHookAuth.Permission.denied, .notRunning, .unavailable] {
            let r = Recorder([permission])
            XCTAssertEqual(AgentHookAuth.credentials(r.steps), .connectWithoutCookie, "\(permission)")
            XCTAssertEqual(r.helperRuns, 0, "\(permission)")
            XCTAssertEqual(r.cookieRequests, 0, "\(permission)")
        }
    }

    // Issue 13230: under load the check timed out, and every hook connected without a cookie
    // only to be rejected. A timed-out check means the answer isn't known, so don't connect.
    func testTimedOutSkipsConnecting() {
        let r = Recorder([.timedOut])
        XCTAssertEqual(AgentHookAuth.credentials(r.steps), .skip)
        XCTAssertEqual(r.helperRuns, 0)
        XCTAssertEqual(r.cookieRequests, 0)
    }

    // The serial case: the first hook waits for the user, then gets its cookie.
    func testNeedsConsentWithNoPromptPendingWaitsForHelperThenSends() {
        let r = Recorder([.needsConsent, .permitted])
        XCTAssertEqual(AgentHookAuth.credentials(r.steps), .connect(cookie: "cookie", key: "key"))
        XCTAssertEqual(r.helperRuns, 1)
        XCTAssertEqual(r.cookieRequests, 1)
    }

    // A prompt is already up: don't start another helper, don't send an event that would
    // queue behind it in iTerm2, and don't make a connection iTerm2 would likely reject.
    func testPromptPendingSkipsAtOnce() {
        let r = Recorder([.needsConsent])
        r.lockHeld = true
        XCTAssertEqual(AgentHookAuth.credentials(r.steps), .skip)
        XCTAssertEqual(r.helperRuns, 0)
        XCTAssertEqual(r.cookieRequests, 0)
        // Not even checked: tccd holds the check while a prompt is up.
        XCTAssertEqual(r.checks, [.needsConsent])
    }

    func testUserDeclinesOrCheckFailsAfterHelperConnectsWithoutCookie() {
        for permission in [AgentHookAuth.Permission.denied, .unavailable] {
            let r = Recorder([.needsConsent, permission])
            XCTAssertEqual(AgentHookAuth.credentials(r.steps), .connectWithoutCookie, "\(permission)")
            XCTAssertEqual(r.helperRuns, 1, "\(permission)")
            XCTAssertEqual(r.cookieRequests, 0, "\(permission)")
        }
    }

    // The helper lost a race or couldn't prompt: still undecided, so don't connect.
    func testStillUndecidedAfterHelperSkips() {
        for permission in [AgentHookAuth.Permission.needsConsent, .timedOut] {
            let r = Recorder([.needsConsent, permission])
            XCTAssertEqual(AgentHookAuth.credentials(r.steps), .skip, "\(permission)")
            XCTAssertEqual(r.helperRuns, 1, "\(permission)")
            XCTAssertEqual(r.cookieRequests, 0, "\(permission)")
        }
    }

    // When the hook's first command can't connect, the rest of the event's commands must fail
    // at once rather than each repeating the attempt and its seconds-long permission check.
    func testSharedClientFactoryRemembersAFailedConnect() {
        var attempts = 0
        let factory = SharedAPIClientFactory(base: {
            attempts += 1
            throw IT2Error.connectionError("no cookie yet")
        })
        XCTAssertThrowsError(try factory.make())
        XCTAssertThrowsError(try factory.make())
        XCTAssertEqual(attempts, 1)
        factory.disconnect()
        XCTAssertThrowsError(try factory.make())
        XCTAssertEqual(attempts, 2, "disconnect starts over")
    }

    // “Allow all apps to connect” means iTerm2 accepts a cookieless connection, so don't spend a
    // permission check or a cookie request, and don't let a check that would time out under load,
    // or a pending consent prompt, stop a connection that would succeed.
    func testAllAppsAllowedConnectsWithoutCookieAndAsksNothing() {
        let r = Recorder([])
        r.allAppsAllowed = true
        r.lockHeld = true
        XCTAssertEqual(AgentHookAuth.credentials(r.steps), .connectWithoutCookie)
        XCTAssertEqual(r.checks, [], "no permission check")
        XCTAssertEqual(r.helperRuns, 0)
        XCTAssertEqual(r.cookieRequests, 0)
    }

    // MARK: - AllAppsAllowedFile

    func testAllAppsAllowedFileIsBesideThePrivateFolder() {
        XCTAssertEqual(AllAppsAllowedFile.path(forSocketPath: "/Users/u/Library/Application Support/iTerm2-dev/private/socket"),
                       "/Users/u/Library/Application Support/iTerm2-dev/disable-automation-auth")
    }

    // Must match +[iTermAPIHelper noauthMagic]: hex of the path's UTF-8 bytes, a space, the UUID.
    func testAllAppsAllowedFileExpectedContents() {
        XCTAssertEqual(AllAppsAllowedFile.expectedContents(path: "/a b"),
                       "2f612062 61DF88DC-3423-4823-B725-22570E01C027")
    }

    private func temporaryNoAuthPath() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AllAppsAllowedFileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
        }
        return dir.appendingPathComponent("disable-automation-auth").path
    }

    func testAllAppsAllowedFileValidOnlyWhenRootOwnedWithExactContents() throws {
        let path = try temporaryNoAuthPath()
        let root: (String) -> uid_t? = { _ in 0 }

        XCTAssertFalse(AllAppsAllowedFile.isValid(path: path, ownerID: root), "missing")

        try AllAppsAllowedFile.expectedContents(path: path).write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertTrue(AllAppsAllowedFile.isValid(path: path, ownerID: root))
        XCTAssertFalse(AllAppsAllowedFile.isValid(path: path), "owned by the user, not root")
        XCTAssertFalse(AllAppsAllowedFile.isValid(path: path, ownerID: { _ in nil }), "owner unreadable")

        try (AllAppsAllowedFile.expectedContents(path: path) + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertFalse(AllAppsAllowedFile.isValid(path: path, ownerID: root), "contents not exact")

        try AllAppsAllowedFile.expectedContents(path: "/elsewhere").write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertFalse(AllAppsAllowedFile.isValid(path: path, ownerID: root), "made for another path")
    }

    func testAllAppsAllowedFileOwnerIsTheRealOwner() throws {
        let path = try temporaryNoAuthPath()
        try "x".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(AllAppsAllowedFile.ownerID(of: path), getuid())
        XCTAssertNil(AllAppsAllowedFile.ownerID(of: path + "-missing"))
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
