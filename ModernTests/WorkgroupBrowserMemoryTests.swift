//
//  WorkgroupBrowserMemoryTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class WorkgroupBrowserMemoryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var memory: WorkgroupBrowserMemory!

    override func setUp() {
        super.setUp()
        suiteName = "WorkgroupBrowserMemoryTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        memory = WorkgroupBrowserMemory(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private let url = ["user.browserURL": "https://example.com/issue/1"]

    func testRecordsByConversationAndMember() {
        memory.record(url, conversation: "c1", member: "m1")
        XCTAssertEqual(memory.values(conversation: "c1", member: "m1"), url)
        XCTAssertNil(memory.values(conversation: "c2", member: "m1"))
        XCTAssertNil(memory.values(conversation: "c1", member: "m2"))
    }

    func testLaterValuesReplaceEarlierOnes() {
        memory.record(url, conversation: "c1", member: "m1")
        let later = ["user.browserURL": "https://example.com/issue/2"]
        memory.record(later, conversation: "c1", member: "m1")
        XCTAssertEqual(memory.values(conversation: "c1", member: "m1"), later)
        XCTAssertEqual(memory.entries.count, 1)
    }

    func testSurvivesANewInstance() {
        memory.record(url, conversation: "c1", member: "m1")
        let reloaded = WorkgroupBrowserMemory(defaults: defaults)
        XCTAssertEqual(reloaded.values(conversation: "c1", member: "m1"), url)
    }

    func testEmptyValuesAreNotRecorded() {
        memory.record([:], conversation: "c1", member: "m1")
        XCTAssertTrue(memory.entries.isEmpty)
    }

    func testForgetsTheLeastRecentlyUsedConversations() {
        for i in 0..<WorkgroupBrowserMemory.capacity {
            memory.record(url, conversation: "c\(i)", member: "m1")
        }
        // Using c0 again makes c1 the oldest.
        memory.record(url, conversation: "c0", member: "m1")
        memory.record(url, conversation: "new", member: "m1")
        XCTAssertNotNil(memory.values(conversation: "c0", member: "m1"))
        XCTAssertNil(memory.values(conversation: "c1", member: "m1"))
        XCTAssertNotNil(memory.values(conversation: "new", member: "m1"))
    }

    func testCapacityCountsConversationsNotMembers() {
        memory.record(url, conversation: "c0", member: "m1")
        memory.record(url, conversation: "c0", member: "m2")
        for i in 1..<WorkgroupBrowserMemory.capacity {
            memory.record(url, conversation: "c\(i)", member: "m1")
        }
        XCTAssertNotNil(memory.values(conversation: "c0", member: "m1"))
        XCTAssertNotNil(memory.values(conversation: "c0", member: "m2"))
    }

    // On /clear the old conversation's end may be reported after the new one
    // started, and must not erase it.
    func testALateEndDoesNotForgetANewerConversation() {
        memory.setConversation("new", forSessionGUID: "s1")
        memory.forgetConversation("old", forSessionGUID: "s1")
        XCTAssertEqual(memory.conversation(forSessionGUID: "s1"), "new")
        memory.forgetConversation("new", forSessionGUID: "s1")
        XCTAssertNil(memory.conversation(forSessionGUID: "s1"))
    }

    // The same rule as the API's variable requests.
    func testOnlyUserVariablesCanBeSetOnMembersByName() {
        XCTAssertTrue(WorkgroupMemberBuiltInFunction.isSettableName("user.browserURL"))
        XCTAssertFalse(WorkgroupMemberBuiltInFunction.isSettableName("session.name"))
        XCTAssertFalse(WorkgroupMemberBuiltInFunction.isSettableName("tab.title"))
        XCTAssertFalse(WorkgroupMemberBuiltInFunction.isSettableName("user.a.b"))
        XCTAssertFalse(WorkgroupMemberBuiltInFunction.isSettableName("user."))
        // A URL template can't name it, so nothing could follow it.
        XCTAssertFalse(WorkgroupMemberBuiltInFunction.isSettableName("user.review-url"))
        XCTAssertTrue(WorkgroupMemberBuiltInFunction.isSettableName("user._x9"))
    }

    func testConversationsBySession() {
        memory.setConversation("c1", forSessionGUID: "s1")
        XCTAssertEqual(memory.conversation(forSessionGUID: "s1"), "c1")
        memory.setConversation("c2", forSessionGUID: "s1")
        XCTAssertEqual(memory.conversation(forSessionGUID: "s1"), "c2")
        memory.forgetSession(guid: "s1")
        XCTAssertNil(memory.conversation(forSessionGUID: "s1"))
    }

    // The report's job pid only covers the moment before the job poll
    // catches up. Once the job moves on, returning to the same shell (the
    // agent died without SessionEnd) doesn't bring it back.
    func testReportJobPIDIsForgottenOnceTheJobChanges() {
        memory.setConversation("c1", forSessionGUID: "s1", jobPID: 100)
        memory.jobChanged(forSessionGUID: "s1", to: 100)
        XCTAssertEqual(memory.report(forSessionGUID: "s1")?.jobPID, 100)
        memory.jobChanged(forSessionGUID: "s1", to: 200)
        XCTAssertNil(memory.report(forSessionGUID: "s1")?.jobPID)
        memory.jobChanged(forSessionGUID: "s1", to: 100)
        XCTAssertNil(memory.report(forSessionGUID: "s1")?.jobPID)
        XCTAssertEqual(memory.conversation(forSessionGUID: "s1"), "c1")
    }

    // MARK: - Binding

    func testRestoreSetsTheVariablesAndReportsThePage() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let binding = try XCTUnwrap(WorkgroupBrowserURLBinding(urlString: "\\(user.browserURL)", session: session))
        defer { binding.invalidate() }
        XCTAssertFalse(binding.hasPage)
        binding.restore(url)
        XCTAssertEqual(session.genericScope.stringValue(forVariableName: "user.browserURL"),
                       url["user.browserURL"])
        XCTAssertTrue(binding.hasPage)
        XCTAssertEqual(binding.values, url)
    }

    func testRestoreIgnoresValuesThatDoNotFormAnAcceptableURL() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let binding = try XCTUnwrap(WorkgroupBrowserURLBinding(urlString: "\\(user.browserURL)", session: session))
        defer { binding.invalidate() }
        binding.restore(["user.browserURL": "file:///etc/passwd"])
        XCTAssertEqual(session.genericScope.stringValue(forVariableName: "user.browserURL"), "")
        binding.restore(["user.other": "https://example.com/"])
        XCTAssertEqual(session.genericScope.stringValue(forVariableName: "user.other"), "")
        XCTAssertFalse(binding.hasPage)
    }

    func testRestoringSeveralVariablesNavigatesOnceToTheFinalPage() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let binding = try XCTUnwrap(WorkgroupBrowserURLBinding(
            urlString: "https://github.com/\\(user.owner)/\\(user.repo)", session: session))
        defer { binding.invalidate() }
        binding.open = { _, _ in true }
        var navigations = [[String: String]]()
        binding.didNavigate = { navigations.append($0) }
        session.genericScope.setValue("A", forVariableNamed: "user.owner")
        session.genericScope.setValue("X", forVariableNamed: "user.repo")
        XCTAssertEqual(navigations, [["user.owner": "A", "user.repo": "X"]])

        let restored = ["user.owner": "B", "user.repo": "Y"]
        binding.restore(restored)
        XCTAssertEqual(navigations.last, restored)
        XCTAssertEqual(navigations.count, 2)
    }

    // Variables set for a member before it started are applied together, so
    // a URL formed from some new values and some old ones is never visited.
    func testChangingTogetherNavigatesOnceToTheFinalPage() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let binding = try XCTUnwrap(WorkgroupBrowserURLBinding(
            urlString: "https://\\(user.host)/\\(user.path)", session: session))
        defer { binding.invalidate() }
        binding.open = { _, _ in true }
        session.genericScope.setValue("a.example", forVariableNamed: "user.host")
        session.genericScope.setValue("one", forVariableNamed: "user.path")
        var navigations = [[String: String]]()
        binding.didNavigate = { navigations.append($0) }
        binding.changingTogether {
            session.genericScope.setValue("b.example", forVariableNamed: "user.host")
            session.genericScope.setValue("two", forVariableNamed: "user.path")
        }
        XCTAssertEqual(navigations, [["user.host": "b.example", "user.path": "two"]])
    }

    // A page that didn't load isn't remembered, and setting the same value
    // again tries again.
    func testRefusedNavigationIsNotRecordedAndCanBeRetried() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let binding = try XCTUnwrap(WorkgroupBrowserURLBinding(urlString: "\\(user.browserURL)", session: session))
        defer { binding.invalidate() }
        var loads = 0
        var loaded = false
        binding.open = { _, _ in
            loads += 1
            return loaded
        }
        var navigations = 0
        binding.didNavigate = { _ in navigations += 1 }
        session.genericScope.setValue("https://example.com/", forVariableNamed: "user.browserURL")
        XCTAssertEqual(loads, 1)
        XCTAssertEqual(navigations, 0)

        loaded = true
        binding.restore(["user.browserURL": "https://example.com/"])
        XCTAssertEqual(loads, 2)
        XCTAssertEqual(navigations, 1)
    }

    func testInvalidatedBindingNoLongerFollowsTheVariables() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let binding = try XCTUnwrap(WorkgroupBrowserURLBinding(urlString: "\\(user.browserURL)", session: session))
        var navigations = 0
        binding.didNavigate = { _ in navigations += 1 }
        binding.invalidate()
        XCTAssertNil(binding.didNavigate)
        session.genericScope.setValue("https://example.com/", forVariableNamed: "user.browserURL")
        XCTAssertEqual(navigations, 0)
    }
}
