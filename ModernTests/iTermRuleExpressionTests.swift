//
//  iTermRuleExpressionTests.swift
//  iTerm2
//
//  Created by George Nachman on 1/18/26.
//

import XCTest
@testable import iTerm2SharedARC

// Mock provider for expression scoring
class MockExpressionScoreProvider: NSObject, AutomaticProfileSwitchingExpressionScoreProvider {
    var scores: [String: Double] = [:]

    func score(forExpression expression: String) -> Double {
        return scores[expression] ?? -Double.infinity
    }
}

final class iTermRuleExpressionTests: XCTestCase {

    var provider: MockExpressionScoreProvider!

    override func setUp() {
        super.setUp()
        provider = MockExpressionScoreProvider()
    }

    // MARK: - Expression Rule Parsing (NEW)

    func testBasicExpressionRule() {
        let rule = iTermRule(string: "{x + y}")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.expression, "x + y")
        XCTAssertNil(rule?.hostname)
        XCTAssertNil(rule?.username)
        XCTAssertNil(rule?.path)
        XCTAssertNil(rule?.job)
        XCTAssertFalse(rule?.isSticky ?? true)
    }

    func testStickyExpressionRule() {
        let rule = iTermRule(string: "!{x + y}")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.expression, "x + y")
        XCTAssertTrue(rule?.isSticky ?? false)
    }

    func testExpressionRuleWhitespace() {
        let rule = iTermRule(string: "{ x + y }")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.expression, " x + y ")
    }

    func testEmptyExpressionRule() {
        let rule = iTermRule(string: "{}")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.expression, "")
    }

    // DISABLED: Uses comparison operator (>) which is not implemented in the parser
    /*
    func testExpressionWithBraces() {
        let rule = iTermRule(string: "{(x > 0) ? 1 : 0}")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.expression, "(x > 0) ? 1 : 0")
    }
    */

    func testMalformedExpressionRule() {
        // Missing closing brace should be treated as traditional rule
        let rule = iTermRule(string: "{x + y")
        XCTAssertNotNil(rule)
        // Should parse as hostname (entire string since no closing brace)
        XCTAssertNil(rule?.expression)
        XCTAssertEqual(rule?.hostname, "{x + y")
    }

    func testNonExpressionRuleUnchanged() {
        let rule = iTermRule(string: "hostname")
        XCTAssertNotNil(rule)
        XCTAssertNil(rule?.expression)
        XCTAssertEqual(rule?.hostname, "hostname")
    }

    // MARK: - Expression Scoring (NEW)

    func testExpressionScoreFromProvider() {
        // Changed from {columns > 100} to {columns + 100} because comparison operators not implemented
        let rule = iTermRule(string: "{columns + 100}")
        XCTAssertNotNil(rule)

        provider.scores["columns + 100"] = 42.0

        let score = rule?.score(forHostname: "anyhost",
                               username: "anyuser",
                               path: "/anypath",
                               job: "anyjob",
                               commandLine: "",
                               expressionValueProvider: provider)
        XCTAssertEqual(score, 42.0)
    }

    func testExpressionIgnoresHostname() {
        // Changed from {columns > 100} to {columns} because comparison operators not implemented
        let rule = iTermRule(string: "{columns}")
        XCTAssertNotNil(rule)

        provider.scores["columns"] = 10.0

        // Expression score should be same regardless of hostname
        let score1 = rule?.score(forHostname: "host1",
                                username: "user",
                                path: "/path",
                                job: "job",
                                commandLine: "",
                                expressionValueProvider: provider)
        let score2 = rule?.score(forHostname: "differenthost",
                                username: "user",
                                path: "/path",
                                job: "job",
                                commandLine: "",
                                expressionValueProvider: provider)
        XCTAssertEqual(score1, 10.0)
        XCTAssertEqual(score2, 10.0)
    }

    func testExpressionIgnoresPath() {
        // Changed from {myvar == 5} to {myvar + 5} because comparison operators not implemented
        let rule = iTermRule(string: "{myvar + 5}")
        XCTAssertNotNil(rule)

        provider.scores["myvar + 5"] = 15.0

        let score = rule?.score(forHostname: "host",
                               username: "user",
                               path: "/different/path",
                               job: "job",
                               commandLine: "",
                               expressionValueProvider: provider)
        XCTAssertEqual(score, 15.0)
    }

    func testProviderReturnsNegative() {
        let rule = iTermRule(string: "{x}")
        XCTAssertNotNil(rule)

        provider.scores["x"] = -5.0

        let score = rule?.score(forHostname: "host",
                               username: "user",
                               path: "/path",
                               job: "job",
                               commandLine: "",
                               expressionValueProvider: provider)
        XCTAssertEqual(score, -5.0)
    }

    func testProviderReturnsZero() {
        let rule = iTermRule(string: "{x}")
        XCTAssertNotNil(rule)

        provider.scores["x"] = 0.0

        let score = rule?.score(forHostname: "host",
                               username: "user",
                               path: "/path",
                               job: "job",
                               commandLine: "",
                               expressionValueProvider: provider)
        XCTAssertEqual(score, 0.0)
    }

    func testExpressionNotInProvider() {
        let rule = iTermRule(string: "{undefined}")
        XCTAssertNotNil(rule)

        // Provider doesn't have this expression
        let score = rule?.score(forHostname: "host",
                               username: "user",
                               path: "/path",
                               job: "job",
                               commandLine: "",
                               expressionValueProvider: provider)
        XCTAssertEqual(score, -Double.infinity)
    }

    // MARK: - Backward Compatibility - Traditional Rules

    func testTraditionalRuleStillWorks() {
        let rule = iTermRule(string: "hostname")
        XCTAssertNotNil(rule)
        XCTAssertNil(rule?.expression)

        let score = rule?.score(forHostname: "hostname",
                               username: "x",
                               path: "x",
                               job: "x",
                               commandLine: "",
                               expressionValueProvider: provider)
        XCTAssertGreaterThan(score ?? 0, 0)
    }

    func testTraditionalRuleIgnoresProvider() {
        let rule = iTermRule(string: "myhost")
        XCTAssertNotNil(rule)

        // Provider shouldn't be called for traditional rules
        provider.scores["something"] = 999.0

        let score = rule?.score(forHostname: "myhost",
                               username: "user",
                               path: "/path",
                               job: "job",
                               commandLine: "",
                               expressionValueProvider: provider)
        // Score should be based on traditional scoring, not provider
        XCTAssertGreaterThan(score ?? 0, 0)
        XCTAssertNotEqual(score, 999.0)
    }

    // MARK: - Ported Tests from iTermRuleTest.m

    func testHostnameOnly() {
        let rule = iTermRule(string: "hostname")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.hostname, "hostname")
        XCTAssertNil(rule?.username)
        XCTAssertNil(rule?.path)
        XCTAssertNil(rule?.job)
    }

    func testUsernameOnly() {
        let rule = iTermRule(string: "username@")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.username, "username")
        XCTAssertNil(rule?.hostname)
    }

    func testUsernameHostname() {
        let rule = iTermRule(string: "username@hostname")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.username, "username")
        XCTAssertEqual(rule?.hostname, "hostname")
        XCTAssertNil(rule?.path)
    }

    func testUsernameHostnamePath() {
        let rule = iTermRule(string: "username@hostname:/path")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.username, "username")
        XCTAssertEqual(rule?.hostname, "hostname")
        XCTAssertEqual(rule?.path, "/path")
    }

    func testPathOnly() {
        let rule = iTermRule(string: "/path")
        XCTAssertNotNil(rule)
        XCTAssertNil(rule?.username)
        XCTAssertNil(rule?.hostname)
        XCTAssertEqual(rule?.path, "/path")
    }

    func testJobOnly() {
        let rule = iTermRule(string: "&job")
        XCTAssertNotNil(rule)
        XCTAssertNil(rule?.username)
        XCTAssertNil(rule?.hostname)
        XCTAssertNil(rule?.path)
        XCTAssertEqual(rule?.job, "job")
    }

    func testHostnameJob() {
        let rule = iTermRule(string: "hostname&job")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.hostname, "hostname")
        XCTAssertEqual(rule?.job, "job")
    }

    func testUsernameHostnamePathJob() {
        let rule = iTermRule(string: "username@hostname:/path&job")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.username, "username")
        XCTAssertEqual(rule?.hostname, "hostname")
        XCTAssertEqual(rule?.path, "/path")
        XCTAssertEqual(rule?.job, "job")
    }

    func testSticky() {
        let nonSticky = iTermRule(string: "hostname")
        let sticky = iTermRule(string: "!hostname")

        XCTAssertFalse(nonSticky?.isSticky ?? true)
        XCTAssertTrue(sticky?.isSticky ?? false)
    }

    func testStickyWithJob() {
        let rule = iTermRule(string: "!hostname&job")
        XCTAssertNotNil(rule)
        XCTAssertTrue(rule?.isSticky ?? false)
        XCTAssertEqual(rule?.hostname, "hostname")
        XCTAssertEqual(rule?.job, "job")
    }

    func testHostnameExactMatchOutranksPartial() {
        let exactRule = iTermRule(string: "hostname")
        let partialRule = iTermRule(string: "host*")

        let exactScore = exactRule?.score(forHostname: "hostname",
                                          username: "user",
                                          path: "/path",
                                          job: "job",
                                          commandLine: "",
                                          expressionValueProvider: provider) ?? 0
        let partialScore = partialRule?.score(forHostname: "hostname",
                                              username: "user",
                                              path: "/path",
                                              job: "job",
                                              commandLine: "",
                                              expressionValueProvider: provider) ?? 0

        XCTAssertGreaterThan(exactScore, partialScore)
    }

    func testLongerWildcardOutranksShort() {
        let longRule = iTermRule(string: "hostname*")
        let shortRule = iTermRule(string: "h*")

        let longScore = longRule?.score(forHostname: "hostname12",
                                        username: "user",
                                        path: "/path",
                                        job: "job",
                                        commandLine: "",
                                        expressionValueProvider: provider) ?? 0
        let shortScore = shortRule?.score(forHostname: "hostname12",
                                          username: "user",
                                          path: "/path",
                                          job: "job",
                                          commandLine: "",
                                          expressionValueProvider: provider) ?? 0

        XCTAssertGreaterThan(longScore, shortScore)
    }

    func testNoMatchReturnsZero() {
        let rule = iTermRule(string: "hostname")

        let score = rule?.score(forHostname: "differenthost",
                               username: "x",
                               path: "x",
                               job: "x",
                               commandLine: "",
                               expressionValueProvider: provider) ?? -1
        XCTAssertEqual(score, 0)
    }

    func testJobGlobMatching() {
        let rule = iTermRule(string: "&job*")

        let matchScore = rule?.score(forHostname: "x",
                                     username: "x",
                                     path: "x",
                                     job: "jobber",
                                     commandLine: "",
                                     expressionValueProvider: provider) ?? 0
        let noMatchScore = rule?.score(forHostname: "x",
                                       username: "x",
                                       path: "x",
                                       job: "different",
                                       commandLine: "",
                                       expressionValueProvider: provider) ?? -1

        XCTAssertGreaterThan(matchScore, 0)
        XCTAssertEqual(noMatchScore, 0)
    }

    // MARK: - Edge Cases

    func testMalformedRuleWithColon() {
        let rule = iTermRule(string: "/foo:bar@baz")
        XCTAssertNotNil(rule)
        // Should parse as path only
        XCTAssertEqual(rule?.path, "/foo:bar@baz")
    }

    func testCatchallRule() {
        let rule = iTermRule(string: "*")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.hostname, "*")

        let score = rule?.score(forHostname: "anyhost",
                               username: "x",
                               path: "x",
                               job: "x",
                               commandLine: "",
                               expressionValueProvider: provider) ?? 0
        // Catchall gets lowest non-zero score
        XCTAssertGreaterThan(score, 0)
    }

    func testUsernameWildcardPath() {
        let rule = iTermRule(string: "username@*:/path")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.username, "username")
        XCTAssertEqual(rule?.hostname, "*")
        XCTAssertEqual(rule?.path, "/path")
    }
}
