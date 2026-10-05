//
//  AutomaticProfileSwitcherTests.swift
//  ModernTests
//
//  Ported from iTermAutomaticProfileSwitcherTest.m. Drives iTermAutomaticProfileSwitcher through a
//  fake delegate that keeps the current profile and the list of all profiles in memory.
//

import XCTest
@testable import iTerm2SharedARC

private typealias TestProfile = [AnyHashable: Any]

// Stands in for the session. Records how often the switcher asked it to load a profile.
private final class FakeSwitcherDelegate: NSObject, iTermAutomaticProfileSwitcherDelegate {
    var profile: TestProfile = [KEY_NAME: "Initial Profile", KEY_GUID: "initial"]
    var allProfiles: [TestProfile] = []
    private(set) var callsToLoadProfile = 0

    func automaticProfileSwitcherLoad(_ savedProfile: iTermSavedProfile) {
        callsToLoadProfile += 1
        profile = savedProfile.originalProfile
    }

    func automaticProfileSwitcherCurrentProfile() -> TestProfile {
        return profile
    }

    func automaticProfileSwitcherCurrentSavedProfile() -> iTermSavedProfile {
        let savedProfile = iTermSavedProfile()
        savedProfile.originalProfile = profile
        savedProfile.profile = profile
        return savedProfile
    }

    func automaticProfileSwitcherAllProfiles() -> [TestProfile] {
        return allProfiles
    }

    func automaticProfileSwitcherSessionName() -> String {
        return ""
    }
}

// None of the profiles in these tests use expression rules, so this is never consulted.
private final class NoExpressionsProvider: NSObject, AutomaticProfileSwitchingExpressionScoreProvider {
    func score(forExpression expression: String) -> Double {
        return 0
    }
}

final class AutomaticProfileSwitcherTests: XCTestCase {
    private var delegate: FakeSwitcherDelegate!
    private var aps: iTermAutomaticProfileSwitcher!
    private let provider = NoExpressionsProvider()

    override func setUp() {
        super.setUp()
        delegate = FakeSwitcherDelegate()
        aps = iTermAutomaticProfileSwitcher(delegate: delegate)
    }

    override func tearDown() {
        aps = nil
        delegate = nil
        super.tearDown()
    }

    // MARK: - Profiles

    private func profile(name: String, guid: String, boundHosts: [String]? = nil) -> TestProfile {
        var result: TestProfile = [KEY_NAME: name, KEY_GUID: guid]
        if let boundHosts {
            result[KEY_BOUND_HOSTS] = boundHosts
        }
        return result
    }

    private var profileHostA: TestProfile { profile(name: "host=a", guid: "1", boundHosts: ["a"]) }
    private var profileHostB: TestProfile { profile(name: "host=b", guid: "2", boundHosts: ["b"]) }
    private var profilePathDir1: TestProfile { profile(name: "path=dir1", guid: "3", boundHosts: ["/dir1"]) }
    private var profilePathDir1AndSubs: TestProfile { profile(name: "path=dir1AndSubs", guid: "3", boundHosts: ["/dir1/*"]) }
    private var profilePathDir2: TestProfile { profile(name: "path=dir2", guid: "4", boundHosts: ["/dir2"]) }
    private var profileUserX: TestProfile { profile(name: "user=x", guid: "5", boundHosts: ["x@"]) }
    private var profileUserY: TestProfile { profile(name: "user=y", guid: "6", boundHosts: ["y@"]) }
    private var profileUserGeorgeHostItermPathHome: TestProfile {
        profile(name: "user=george host=iterm2.com path=home", guid: "7", boundHosts: ["george@iterm2.com:/home"])
    }
    private var profileUserGeorgePathHome: TestProfile {
        profile(name: "user=george path=home", guid: "8", boundHosts: ["george@:/home"])
    }
    private var profileUserGeorgeHostIterm: TestProfile {
        profile(name: "user=george host=iterm2.com", guid: "9", boundHosts: ["george@iterm2.com"])
    }
    private var profileHostItermPathHome: TestProfile {
        profile(name: "host=iterm2.com path=home", guid: "10", boundHosts: ["iterm2.com:/home"])
    }
    private var profileHostIterm: TestProfile { profile(name: "host=iterm2.com", guid: "11", boundHosts: ["iterm2.com"]) }
    private var profileUserGeorge: TestProfile { profile(name: "user=george", guid: "12", boundHosts: ["george@"]) }
    private var profilePathHome: TestProfile { profile(name: "path=home", guid: "13", boundHosts: ["/home"]) }
    private var profileHostAllDotCom: TestProfile { profile(name: "host=*.com", guid: "14", boundHosts: ["*.com"]) }
    private var profileAllPaths: TestProfile { profile(name: "path=/*", guid: "15", boundHosts: ["/*"]) }
    private var profileJobX: TestProfile { profile(name: "job=x", guid: "16", boundHosts: ["&x"]) }
    private var profileJobY: TestProfile { profile(name: "job=y", guid: "17", boundHosts: ["&y"]) }
    private var profileHostAll: TestProfile { profile(name: "host=*", guid: "18", boundHosts: ["*"]) }
    private var profileWithoutBoundHosts: TestProfile { profile(name: "Boring", guid: "19") }

    // MARK: - Helpers

    private func update(_ switcher: iTermAutomaticProfileSwitcher,
                        hostname: String,
                        username: String,
                        path: String,
                        job: String) {
        switcher.setHostname(hostname,
                             username: username,
                             path: path,
                             job: job,
                             commandLine: nil,
                             expressionValueProvider: provider)
    }

    private func update(hostname: String, username: String, path: String, job: String) {
        update(aps, hostname: hostname, username: username, path: path, job: job)
    }

    private func assertCurrentProfile(is expected: TestProfile,
                                      file: StaticString = #filePath,
                                      line: UInt = #line) {
        let current = delegate.profile
        XCTAssertTrue((current as NSDictionary).isEqual(toProfile: expected),
                      "Expected profile \(expected[KEY_NAME] ?? "?") but current profile is \(current[KEY_NAME] ?? "?")",
                      file: file,
                      line: line)
    }

    // MARK: - Various kinds of rules cause a profile switch

    func testSwitchesOnHostName() {
        delegate.profile = profileHostA
        delegate.allProfiles = [profileHostA, profileHostB]
        update(hostname: "b", username: "whatever", path: "whatever", job: "whatever")
        assertCurrentProfile(is: profileHostB)
    }

    func testSwitchesOnUserName() {
        delegate.profile = profileUserX
        delegate.allProfiles = [profileUserX, profileUserY]
        update(hostname: "whatever", username: "y", path: "whatever", job: "whatever")
        assertCurrentProfile(is: profileUserY)
    }

    func testSwitchesOnPath() {
        delegate.profile = profilePathDir1
        delegate.allProfiles = [profilePathDir1, profilePathDir2]
        update(hostname: "whatever", username: "whatever", path: "/dir2", job: "whatever")
        assertCurrentProfile(is: profilePathDir2)
    }

    func testSwitchesOnWildcard() {
        delegate.profile = profileHostA
        delegate.allProfiles = [profileHostA, profileHostAllDotCom]
        update(hostname: "iterm2.com", username: "george", path: "/home", job: "whatever")
        assertCurrentProfile(is: profileHostAllDotCom)
    }

    func testSwitchesOnJob() {
        delegate.profile = profileJobX
        delegate.allProfiles = [profileJobX, profileJobY]
        update(hostname: "whatever", username: "whatever", path: "whatever", job: "y")
        assertCurrentProfile(is: profileJobY)
    }

    func testMatchAllRuleOutranksProfileWithoutRules() {
        delegate.profile = profileWithoutBoundHosts
        delegate.allProfiles = [profileWithoutBoundHosts, profileHostAll]
        update(hostname: "whatever", username: "whatever", path: "whatever", job: "whatever")
        assertCurrentProfile(is: profileHostAll)
    }

    // MARK: - Priority is correct (Host > Job > User > Path)

    func testUsernameHostnamePathOutranksUsernameHostname() {
        delegate.profile = profileHostA
        delegate.allProfiles = [profileUserGeorgeHostItermPathHome, profileUserGeorgeHostIterm]
        update(hostname: "iterm2.com", username: "george", path: "/home", job: "whatever")
        assertCurrentProfile(is: profileUserGeorgeHostItermPathHome)
    }

    func testUsernameHostnameOutranksUsernamePath() {
        delegate.profile = profileHostA
        delegate.allProfiles = [profileUserGeorgeHostIterm, profileUserGeorgePathHome]
        update(hostname: "iterm2.com", username: "george", path: "/home", job: "whatever")
        assertCurrentProfile(is: profileUserGeorgeHostIterm)
    }

    func testJobOutranksUsernamePath() {
        delegate.profile = profileHostA
        delegate.allProfiles = [profileJobX, profileUserGeorgePathHome]
        update(hostname: "whatever", username: "george", path: "/home", job: "x")
        assertCurrentProfile(is: profileJobX)
    }

    func testHostnamePathOutranksUsernamePath() {
        delegate.profile = profileHostA
        delegate.allProfiles = [profileHostItermPathHome, profileUserGeorgePathHome]
        update(hostname: "iterm2.com", username: "george", path: "/home", job: "whatever")
        assertCurrentProfile(is: profileHostItermPathHome)
    }

    func testHostnamePathOutranksHostname() {
        delegate.profile = profileHostA
        delegate.allProfiles = [profileHostItermPathHome, profileHostIterm]
        update(hostname: "iterm2.com", username: "george", path: "/home", job: "whatever")
        assertCurrentProfile(is: profileHostItermPathHome)
    }

    func testHostnameOutranksUsername() {
        delegate.profile = profileHostA
        delegate.allProfiles = [profileHostIterm, profileUserGeorge]
        update(hostname: "iterm2.com", username: "george", path: "/home", job: "whatever")
        assertCurrentProfile(is: profileHostIterm)
    }

    func testUsernameOutranksPath() {
        delegate.profile = profileHostA
        delegate.allProfiles = [profileUserGeorge, profilePathHome]
        update(hostname: "iterm2.com", username: "george", path: "/home", job: "whatever")
        assertCurrentProfile(is: profileUserGeorge)
    }

    func testExactHostnameOutranksWildcard() {
        delegate.profile = profileHostA
        delegate.allProfiles = [profileHostIterm, profileHostAllDotCom]
        update(hostname: "iterm2.com", username: "george", path: "/home", job: "whatever")
        assertCurrentProfile(is: profileHostIterm)
    }

    // MARK: - Profile stack

    // Regression test for issue 4581. Don't switch away from the current profile to something on
    // the stack if it still matches.
    func testPreferSpecificRuleEvenIfStackHasMatch() {
        delegate.profile = profileAllPaths
        delegate.allProfiles = [profileAllPaths, profilePathDir1AndSubs]

        update(hostname: "iterm2.com", username: "george", path: "/", job: "job")
        assertCurrentProfile(is: profileAllPaths)

        update(hostname: "iterm2.com", username: "george", path: "/dir1/foo", job: "job")
        assertCurrentProfile(is: profilePathDir1AndSubs)

        update(hostname: "iterm2.com", username: "george", path: "/dir1/foo/temp", job: "job")
        assertCurrentProfile(is: profilePathDir1AndSubs)
    }

    // Restore to a profile in the middle of the stack.
    func testWalkUpStack() {
        delegate.profile = profileHostIterm
        delegate.allProfiles = [profileHostIterm, profileUserGeorgeHostIterm, profileUserGeorgeHostItermPathHome]
        update(hostname: "iterm2.com", username: "george", path: "bogus path", job: "job")
        // Stack is now: iterm2.com, george@iterm2.com
        update(hostname: "iterm2.com", username: "george", path: "/home", job: "job")
        // Stack is now: iterm2.com, george@iterm2.com, george@iterm2.com:/home
        update(hostname: "iterm2.com", username: "george", path: "bogus path", job: "job")
        // If we didn't walk the stack all the way back up we should be on george@iterm2.com.
        assertCurrentProfile(is: profileUserGeorgeHostIterm)
    }

    // No change in configuration means no delegate call to load a profile.
    func testDontChangeProfileIfSame() {
        delegate.profile = profileHostIterm
        delegate.allProfiles = [profileHostIterm, profilePathDir1]
        update(hostname: "iterm2.com", username: "george", path: "/", job: "job")
        XCTAssertEqual(delegate.callsToLoadProfile, 0)
    }

    // Restores the first profile in the stack when nothing matches.
    func testRestoreOriginalProfileWhenNothingMatches() {
        delegate.profile = profileHostIterm
        delegate.allProfiles = [profileHostIterm, profileUserGeorgeHostIterm, profileUserGeorgeHostItermPathHome]
        update(hostname: "iterm2.com", username: "george", path: "bogus path", job: "job")
        // Stack is now: iterm2.com, george@iterm2.com
        update(hostname: "iterm2.com", username: "george", path: "/home", job: "job")
        // Stack is now: iterm2.com, george@iterm2.com, george@iterm2.com:/home
        update(hostname: "qwerty", username: "uiop", path: "asdf", job: "job")
        // Revert to the initial profile.
        assertCurrentProfile(is: profileHostIterm)
    }

    func testSavedStateRoundTrips() {
        let state = aps.savedState()
        let restored = iTermAutomaticProfileSwitcher(delegate: delegate, savedState: state)
        XCTAssertEqual(state as NSDictionary, restored.savedState() as NSDictionary)
        XCTAssertEqual(aps.profileStackString, restored.profileStackString)
    }

    // A switcher created from saved state keeps a working stack.
    func testSwitcherRestoredFromSavedStateWalksStack() {
        let restored = iTermAutomaticProfileSwitcher(delegate: delegate, savedState: aps.savedState())

        delegate.profile = profileHostIterm
        delegate.allProfiles = [profileHostIterm, profileUserGeorgeHostIterm, profileUserGeorgeHostItermPathHome]
        update(restored, hostname: "iterm2.com", username: "george", path: "bogus path", job: "job")
        // Stack is now: iterm2.com, george@iterm2.com
        assertCurrentProfile(is: profileUserGeorgeHostIterm)

        update(restored, hostname: "iterm2.com", username: "george", path: "/home", job: "job")
        // Stack is now: iterm2.com, george@iterm2.com, george@iterm2.com:/home
        assertCurrentProfile(is: profileUserGeorgeHostItermPathHome)

        // Pop one level.
        update(restored, hostname: "iterm2.com", username: "george", path: "asdf", job: "job")
        // Stack is now: iterm2.com, george@iterm2.com
        assertCurrentProfile(is: profileUserGeorgeHostIterm)

        // Back to the initial profile.
        update(restored, hostname: "qwerty", username: "uiop", path: "asdf", job: "job")
        // Stack is now: iterm2.com
        assertCurrentProfile(is: profileHostIterm)
    }

    func testUserNameWithAtSign() {
        let hostnameWildcardProfile = profile(name: "Default", guid: "200", boundHosts: ["hostname*"])
        delegate.allProfiles = [profileUserGeorge, hostnameWildcardProfile]
        update(hostname: "hostname.com", username: "user@example.com", path: "/", job: "whatever")
        assertCurrentProfile(is: hostnameWildcardProfile)
    }
}
