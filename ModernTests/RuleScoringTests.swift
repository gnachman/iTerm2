//
//  RuleScoringTests.swift
//  ModernTests
//
//  Ported from iTermRuleTest.m. Ranks a fixed set of automatic profile switching rules against a
//  session configuration and checks the resulting order. Parsing, stickiness and the hostname
//  monotonicity checks already live in iTermRuleExpressionTests.swift.
//

import XCTest
@testable import iTerm2SharedARC

final class RuleScoringTests: XCTestCase {
    // Rules keyed by a short name so that expected orderings read as lists of names. The
    // declaration order matters: it is used to break ties between rules with equal scores, which is
    // what the legacy test relied on through NSArray's sort.
    private let ruleStrings: [(name: String, string: String)] = [
        ("hostname", "hostname"),
        ("username", "username@"),
        ("usernameHostname", "username@hostname"),
        ("usernameHostnamePath", "username@hostname:/path"),
        ("usernamePath", "username@*:/path"),
        ("usernameWildcardStartPath", "username@*hostname:/path"),
        ("usernameWildcardEndPath", "username@hostname*:/path"),
        ("usernameWildcardStartEndPath", "username@*hostname*:/path"),
        ("usernameWildcardMiddlePath", "username@host*name:/path"),
        ("usernameWildcardAllPath", "username@*host*name*:/path"),
        ("usernameWildcardActualPath", "username@service*.*.hostname.com:/path"),
        ("hostnamePath", "hostname:/path"),
        ("path", "/path"),

        ("hostnameJob", "hostname&job"),
        ("usernameJob", "username@&job"),
        ("usernameHostnameJob", "username@hostname&job"),
        ("usernameHostnamePathJob", "username@hostname:/path&job"),
        ("usernamePathJob", "username@*:/path&job"),
        ("usernameWildcardStartPathJob", "username@*hostname:/path&job"),
        ("usernameWildcardEndPathJob", "username@hostname*:/path&job"),
        ("usernameWildcardStartEndPathJob", "username@*hostname*:/path&job"),
        ("usernameWildcardMiddlePathJob", "username@host*name:/path&job"),
        ("usernameWildcardAllPathJob", "username@*host*name*:/path&job"),
        ("usernameWildcardActualPathJob", "username@service*.*.hostname.com:/path&job"),
        ("hostnamePathJob", "hostname:/path&job"),
        ("pathJob", "/path&job"),
        ("job", "&job*"),

        ("malformed1", "/foo:bar@baz"),
        ("malformed2", "/foo:bar@baz&job"),
    ]

    private var rules: [(name: String, rule: iTermRule)] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        rules = try ruleStrings.map { entry in
            let rule = try XCTUnwrap(iTermRule(string: entry.string), "Failed to parse rule \(entry.string)")
            return (entry.name, rule)
        }
    }

    private func score(_ rule: iTermRule,
                       hostname: String,
                       username: String,
                       path: String,
                       job: String) -> Double {
        return rule.score(forHostname: hostname,
                          username: username,
                          path: path,
                          job: job,
                          commandLine: nil,
                          expressionValueProvider: nil)
    }

    // Returns the names of the rules with a positive score, highest score first. Like the legacy
    // test's comparator, scores are truncated to integers before comparison and ties keep the
    // declaration order. Note that the fractional part of a score (which rewards longer wildcard
    // patterns) is therefore ignored here; the monotonicity tests below cover it.
    private func matchingRuleNames(hostname: String,
                                   username: String,
                                   path: String,
                                   job: String) -> [String] {
        let scored: [(name: String, score: Int, index: Int)] = rules.enumerated().compactMap { index, entry in
            let value = score(entry.rule, hostname: hostname, username: username, path: path, job: job)
            guard value > 0 else {
                return nil
            }
            return (entry.name, Int(value), index)
        }
        return scored.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.index < rhs.index
        }.map { $0.name }
    }

    // MARK: - Rules without a job component

    func testHostnameOnlyMatchesHostnameRule() {
        let names = matchingRuleNames(hostname: "hostname", username: "x", path: "x", job: "x")
        XCTAssertEqual(names, ["hostname"])
    }

    func testUsernameOnlyMatchesUsernameRule() {
        let names = matchingRuleNames(hostname: "x", username: "username", path: "x", job: "x")
        XCTAssertEqual(names, ["username"])
    }

    func testUsernameHostnameRanking() {
        let names = matchingRuleNames(hostname: "hostname", username: "username", path: "x", job: "x")
        XCTAssertEqual(names, ["usernameHostname", "hostname", "username"])
    }

    func testUsernameHostnamePathRanking() {
        let names = matchingRuleNames(hostname: "hostname", username: "username", path: "/path", job: "x")
        XCTAssertEqual(names, ["usernameHostnamePath",
                               "usernameHostname",
                               "usernameWildcardStartPath",
                               "usernameWildcardEndPath",
                               "usernameWildcardStartEndPath",
                               "usernameWildcardMiddlePath",
                               "usernameWildcardAllPath",
                               "hostnamePath",
                               "hostname",
                               "usernamePath",
                               "username",
                               "path"])
    }

    func testUsernameWildcardPathRanking() {
        let names = matchingRuleNames(hostname: "x", username: "username", path: "/path", job: "x")
        XCTAssertEqual(names, ["usernamePath", "username", "path"])
    }

    func testUsernameWildcardStartPathRanking() {
        let names = matchingRuleNames(hostname: "service01.hostname", username: "username", path: "/path", job: "x")
        XCTAssertEqual(names, ["usernameWildcardStartPath",
                               "usernameWildcardStartEndPath",
                               "usernameWildcardAllPath",
                               "usernamePath",
                               "username",
                               "path"])
    }

    func testUsernameWildcardEndPathRanking() {
        let names = matchingRuleNames(hostname: "hostname.com", username: "username", path: "/path", job: "x")
        XCTAssertEqual(names, ["usernameWildcardEndPath",
                               "usernameWildcardStartEndPath",
                               "usernameWildcardAllPath",
                               "usernamePath",
                               "username",
                               "path"])
    }

    func testUsernameWildcardStartEndPathRanking() {
        let names = matchingRuleNames(hostname: "service01.hostname.com", username: "username", path: "/path", job: "x")
        XCTAssertEqual(names, ["usernameWildcardStartEndPath",
                               "usernameWildcardAllPath",
                               "usernamePath",
                               "username",
                               "path"])
    }

    func testUsernameWildcardActualPathRanking() {
        let names = matchingRuleNames(hostname: "service01.prod.hostname.com", username: "username", path: "/path", job: "x")
        XCTAssertEqual(names, ["usernameWildcardActualPath",
                               "usernameWildcardStartEndPath",
                               "usernameWildcardAllPath",
                               "usernamePath",
                               "username",
                               "path"])
    }

    func testHostnamePathRanking() {
        let names = matchingRuleNames(hostname: "hostname", username: "x", path: "/path", job: "x")
        XCTAssertEqual(names, ["hostnamePath", "hostname", "path"])
    }

    func testPathOnlyMatchesPathRule() {
        let names = matchingRuleNames(hostname: "x", username: "x", path: "/path", job: "x")
        XCTAssertEqual(names, ["path"])
    }

    // MARK: - Rules with a job component

    func testHostnameJobRanking() {
        let names = matchingRuleNames(hostname: "hostname", username: "x", path: "x", job: "job")
        XCTAssertEqual(names, ["hostnameJob", "hostname", "job"])
    }

    func testUsernameJobRanking() {
        let names = matchingRuleNames(hostname: "x", username: "username", path: "x", job: "job")
        XCTAssertEqual(names, ["usernameJob", "job", "username"])
    }

    func testUsernameHostnameJobRanking() {
        let names = matchingRuleNames(hostname: "hostname", username: "username", path: "x", job: "job")
        XCTAssertEqual(names, ["usernameHostnameJob",
                               "hostnameJob",
                               "usernameHostname",
                               "hostname",
                               "usernameJob",
                               "job",
                               "username"])
    }

    func testUsernameHostnamePathJobRanking() {
        let names = matchingRuleNames(hostname: "hostname", username: "username", path: "/path", job: "job")
        XCTAssertEqual(names, ["usernameHostnamePathJob",
                               "usernameHostnameJob",
                               "usernameWildcardStartPathJob",
                               "usernameWildcardEndPathJob",
                               "usernameWildcardStartEndPathJob",
                               "usernameWildcardMiddlePathJob",
                               "usernameWildcardAllPathJob",
                               "hostnamePathJob",
                               "hostnameJob",
                               "usernameHostnamePath",
                               "usernameHostname",
                               "usernameWildcardStartPath",
                               "usernameWildcardEndPath",
                               "usernameWildcardStartEndPath",
                               "usernameWildcardMiddlePath",
                               "usernameWildcardAllPath",
                               "hostnamePath",
                               "hostname",
                               "usernamePathJob",
                               "usernameJob",
                               "pathJob",
                               "job",
                               "usernamePath",
                               "username",
                               "path"])
    }

    func testUsernameWildcardPathJobRanking() {
        let names = matchingRuleNames(hostname: "x", username: "username", path: "/path", job: "job")
        XCTAssertEqual(names, ["usernamePathJob",
                               "usernameJob",
                               "pathJob",
                               "job",
                               "usernamePath",
                               "username",
                               "path"])
    }

    func testUsernameWildcardStartPathJobRanking() {
        let names = matchingRuleNames(hostname: "service01.hostname", username: "username", path: "/path", job: "job")
        XCTAssertEqual(names, ["usernameWildcardStartPathJob",
                               "usernameWildcardStartEndPathJob",
                               "usernameWildcardAllPathJob",
                               "usernameWildcardStartPath",
                               "usernameWildcardStartEndPath",
                               "usernameWildcardAllPath",
                               "usernamePathJob",
                               "usernameJob",
                               "pathJob",
                               "job",
                               "usernamePath",
                               "username",
                               "path"])
    }

    func testUsernameWildcardEndPathJobRanking() {
        let names = matchingRuleNames(hostname: "hostname.com", username: "username", path: "/path", job: "job")
        XCTAssertEqual(names, ["usernameWildcardEndPathJob",
                               "usernameWildcardStartEndPathJob",
                               "usernameWildcardAllPathJob",
                               "usernameWildcardEndPath",
                               "usernameWildcardStartEndPath",
                               "usernameWildcardAllPath",
                               "usernamePathJob",
                               "usernameJob",
                               "pathJob",
                               "job",
                               "usernamePath",
                               "username",
                               "path"])
    }

    func testUsernameWildcardStartEndPathJobRanking() {
        let names = matchingRuleNames(hostname: "service01.hostname.com", username: "username", path: "/path", job: "job")
        XCTAssertEqual(names, ["usernameWildcardStartEndPathJob",
                               "usernameWildcardAllPathJob",
                               "usernameWildcardStartEndPath",
                               "usernameWildcardAllPath",
                               "usernamePathJob",
                               "usernameJob",
                               "pathJob",
                               "job",
                               "usernamePath",
                               "username",
                               "path"])
    }

    func testUsernameWildcardActualPathJobRanking() {
        let names = matchingRuleNames(hostname: "service01.prod.hostname.com", username: "username", path: "/path", job: "job")
        XCTAssertEqual(names, ["usernameWildcardActualPathJob",
                               "usernameWildcardStartEndPathJob",
                               "usernameWildcardAllPathJob",
                               "usernameWildcardActualPath",
                               "usernameWildcardStartEndPath",
                               "usernameWildcardAllPath",
                               "usernamePathJob",
                               "usernameJob",
                               "pathJob",
                               "job",
                               "usernamePath",
                               "username",
                               "path"])
    }

    func testHostnamePathJobRanking() {
        let names = matchingRuleNames(hostname: "hostname", username: "x", path: "/path", job: "job")
        XCTAssertEqual(names, ["hostnamePathJob",
                               "hostnameJob",
                               "hostnamePath",
                               "hostname",
                               "pathJob",
                               "job",
                               "path"])
    }

    func testPathJobRanking() {
        let names = matchingRuleNames(hostname: "x", username: "x", path: "/path", job: "job")
        XCTAssertEqual(names, ["pathJob", "job", "path"])
    }

    // MARK: - Misc

    func testNothingMatchesUnrelatedConfiguration() {
        let names = matchingRuleNames(hostname: "x", username: "x", path: "x", job: "x")
        XCTAssertEqual(names, [])
    }

    func testJobGlobMatchesLongerJobName() {
        let names = matchingRuleNames(hostname: "x", username: "x", path: "x", job: "jobber")
        XCTAssertEqual(names, ["job"])
    }

    // MARK: - Wildcard length monotonicity

    func testScoreMonotonicInWildcardRulePathLength() throws {
        let exactPathRule = try XCTUnwrap(iTermRule(string: "/path123"))
        let longPathRule = try XCTUnwrap(iTermRule(string: "/path*"))
        let shortPathRule = try XCTUnwrap(iTermRule(string: "/p*"))

        let exactScore = score(exactPathRule, hostname: "hostname", username: "george", path: "/path123", job: "job")
        let longScore = score(longPathRule, hostname: "hostname", username: "george", path: "/path123", job: "job")
        let shortScore = score(shortPathRule, hostname: "hostname", username: "george", path: "/path123", job: "job")

        XCTAssertGreaterThan(longScore, shortScore)
        XCTAssertGreaterThan(exactScore, longScore)
    }

    func testScoreMonotonicInWildcardRulePathLength_VeryLongRule() throws {
        let longString = String(repeating: "x", count: 1024)
        let longRule = try XCTUnwrap(iTermRule(string: "/x\(longString)*"))
        let shortRule = try XCTUnwrap(iTermRule(string: "/\(longString)*"))
        let path = "/xx\(longString)"

        let longScore = score(longRule, hostname: "hostname", username: "george", path: path, job: "job")
        let shortScore = score(shortRule, hostname: "hostname", username: "george", path: path, job: "job")

        XCTAssertGreaterThan(longScore, shortScore)
    }
}
