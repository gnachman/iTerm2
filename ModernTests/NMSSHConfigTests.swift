//
//  NMSSHConfigTests.swift
//  ModernTests
//
//  Ported from submodules/NMSSH/NMSSHTests/NMSSHConfigTests.m, whose test target no longer
//  builds (it needs a live-server config.yml for its other tests). These exercise the
//  NMSSH.framework that iTerm2 actually ships, from ThirdParty/.
//

import XCTest
@testable import iTerm2SharedARC

final class NMSSHConfigTests: XCTestCase {
    private func parse(_ contents: String,
                       file: StaticString = #filePath,
                       line: UInt = #line) throws -> NMSSHConfig {
        return try XCTUnwrap(NMSSHConfig(string: contents), "Config failed to parse", file: file, line: line)
    }

    private func patterns(_ hostConfig: NMSSHHostConfig) -> [String] {
        return (hostConfig.hostPatterns as? [String]) ?? []
    }

    private func identityFiles(_ hostConfig: NMSSHHostConfig?) -> [String] {
        return (hostConfig?.identityFiles as? [String]) ?? []
    }

    // MARK: - Parsing

    /// An empty config file is ok.
    func testEmptyConfig() throws {
        let config = try parse("")
        XCTAssertEqual(config.hostConfigs.count, 0)
    }

    /// A config file with all supported keywords is properly read.
    func testAllKeywords() throws {
        let config = try parse("""
            Host pattern
                Hostname hostname
                User user
                Port 1234
                IdentityFile id_file

            """)
        XCTAssertEqual(config.hostConfigs.count, 1)

        let hostConfig = config.hostConfigs[0]
        XCTAssertEqual(patterns(hostConfig), ["pattern"])
        XCTAssertEqual(hostConfig.hostname, "hostname")
        XCTAssertEqual(hostConfig.user, "user")
        XCTAssertEqual(hostConfig.port, 1234)
        XCTAssertEqual(identityFiles(hostConfig), ["id_file"])
    }

    /// Comments are ignored.
    func testCommentsIgnored() throws {
        let config = try parse("""
            # Comment
            Host pattern
            # Comment
                Hostname hostname
            # Comment
                Port 1234
            # Comment
                IdentityFile id_file
            # Comment

            """)
        XCTAssertEqual(config.hostConfigs.count, 1)

        let hostConfig = config.hostConfigs[0]
        XCTAssertEqual(patterns(hostConfig), ["pattern"])
        XCTAssertEqual(hostConfig.hostname, "hostname")
        XCTAssertEqual(hostConfig.port, 1234)
        XCTAssertEqual(identityFiles(hostConfig), ["id_file"])
    }

    /// Empty lines are ignored.
    func testEmptyLinesIgnored() throws {
        let config = try parse("""

            Host pattern

                Hostname hostname

                Port 1234

                IdentityFile id_file


            """)
        XCTAssertEqual(config.hostConfigs.count, 1)

        let hostConfig = config.hostConfigs[0]
        XCTAssertEqual(patterns(hostConfig), ["pattern"])
        XCTAssertEqual(hostConfig.hostname, "hostname")
        XCTAssertEqual(hostConfig.port, 1234)
        XCTAssertEqual(identityFiles(hostConfig), ["id_file"])
    }

    /// Unknown keywords are ignored.
    func testIgnoreUnknownKeywords() throws {
        let config = try parse("""
            Host pattern
                Hostname hostname
                Port 1234
                jfkldsajfdkl fjdkslafjdl fdjkla fjdslkf asdl
                IdentityFile id_file

            """)
        XCTAssertEqual(config.hostConfigs.count, 1)

        let hostConfig = config.hostConfigs[0]
        XCTAssertEqual(patterns(hostConfig), ["pattern"])
        XCTAssertEqual(hostConfig.hostname, "hostname")
        XCTAssertEqual(hostConfig.port, 1234)
        XCTAssertEqual(identityFiles(hostConfig), ["id_file"])
    }

    /// A malformed port line doesn't break parsing.
    func testMalformedPort() throws {
        let config = try parse("""
            Host pattern
                Hostname hostname
                Port
                IdentityFile id_file

            """)
        XCTAssertEqual(config.hostConfigs.count, 1)

        let hostConfig = config.hostConfigs[0]
        XCTAssertEqual(patterns(hostConfig), ["pattern"])
        XCTAssertEqual(hostConfig.hostname, "hostname")
        XCTAssertNil(hostConfig.port)
        XCTAssertEqual(identityFiles(hostConfig), ["id_file"])
    }

    /// Multiple patterns are parsed properly.
    func testMultiplePatterns() throws {
        let config = try parse("Host pattern1 pattern2\n")
        XCTAssertEqual(config.hostConfigs.count, 1)
        XCTAssertEqual(patterns(config.hostConfigs[0]), ["pattern1", "pattern2"])
    }

    /// Quoted patterns are parsed properly.
    func testQuotedPatterns() throws {
        let config = try parse("Host pattern1 \"a quoted pattern\" pattern2 \"foo bar\" \"baz\"\n")
        XCTAssertEqual(config.hostConfigs.count, 1)
        XCTAssertEqual(patterns(config.hostConfigs[0]),
                       ["pattern1", "a quoted pattern", "pattern2", "foo bar", "baz"])
    }

    /// An unterminated quoted pattern is ignored.
    func testUnterminatedQuotation() throws {
        let config = try parse("Host pattern1 \"unterminated quotation\n")
        XCTAssertEqual(config.hostConfigs.count, 1)
        XCTAssertEqual(patterns(config.hostConfigs[0]), ["pattern1"])
    }

    /// Multiple IdentityFile lines are respected.
    func testMultipleIdentityFile() throws {
        let config = try parse("""
            Host pattern
                Hostname hostname
                Port 1234
                IdentityFile id_file1
                IdentityFile id_file2

            """)
        XCTAssertEqual(config.hostConfigs.count, 1)
        XCTAssertEqual(identityFiles(config.hostConfigs[0]), ["id_file1", "id_file2"])
    }

    /// Leading, trailing, and midline spaces are ignored.
    func testExtraSpaces() throws {
        let config = try parse("  Host         pattern    \"quoted pattern\"  \"   \"  \n"
                               + "    Hostname    hostname      \n")
        XCTAssertEqual(config.hostConfigs.count, 1)

        let hostConfig = config.hostConfigs[0]
        XCTAssertEqual(patterns(hostConfig), ["pattern", "quoted pattern", "   "])
        XCTAssertEqual(hostConfig.hostname, "hostname")
    }

    /// Multiple Host blocks.
    func testMultipleHosts() throws {
        let config = try parse("""
            Host pattern1
                Hostname hostname1
                Port 1
                IdentityFile id_file1
            Host pattern2
                Hostname hostname2
                Port 2
                IdentityFile id_file2

            """)
        XCTAssertEqual(config.hostConfigs.count, 2)

        var hostConfig = config.hostConfigs[0]
        XCTAssertEqual(patterns(hostConfig), ["pattern1"])
        XCTAssertEqual(hostConfig.hostname, "hostname1")
        XCTAssertEqual(hostConfig.port, 1)
        XCTAssertEqual(identityFiles(hostConfig), ["id_file1"])

        hostConfig = config.hostConfigs[1]
        XCTAssertEqual(patterns(hostConfig), ["pattern2"])
        XCTAssertEqual(hostConfig.hostname, "hostname2")
        XCTAssertEqual(hostConfig.port, 2)
        XCTAssertEqual(identityFiles(hostConfig), ["id_file2"])
    }

    // MARK: - Matching

    /// Asserts that each host in `matching` resolves to `hostname` and each in `notMatching`
    /// matches nothing.
    private func assertConfig(_ config: NMSSHConfig,
                              resolves matching: [String],
                              to hostname: String,
                              andNot notMatching: [String] = [],
                              file: StaticString = #filePath,
                              line: UInt = #line) {
        for host in matching {
            XCTAssertEqual(config.hostConfig(forHost: host)?.hostname, hostname,
                           "Match failed for “\(host)”", file: file, line: line)
        }
        for host in notMatching {
            XCTAssertNil(config.hostConfig(forHost: host),
                         "Match should have failed for “\(host)”", file: file, line: line)
        }
    }

    /// A simple pattern matches.
    func testSimplestPossiblePattern() throws {
        let config = try parse("Host pattern1\n    Hostname hostname1\n")
        assertConfig(config, resolves: ["pattern1"], to: "hostname1")
    }

    /// A simple pattern fails when it ought to.
    func testSimplestPossiblePatternNoMatch() throws {
        let config = try parse("Host pattern1\n    Hostname hostname1\n")
        assertConfig(config, resolves: [], to: "hostname1", andNot: ["pattern2"])
    }

    /// A comma-separated pattern list of simple patterns works.
    func testSimplePatternList() throws {
        let config = try parse("Host pattern1,pattern2\n    Hostname hostname1\n")
        assertConfig(config, resolves: ["pattern1", "pattern2"], to: "hostname1", andNot: ["pattern3"])
    }

    /// A question mark wildcard works.
    func testSingleCharWildcard() throws {
        let config = try parse("Host pattern?\n    Hostname hostname1\n")
        assertConfig(config, resolves: ["pattern1", "pattern2"], to: "hostname1", andNot: ["Xattern3"])
    }

    /// A lone star matches everything, including the empty string.
    func testLoneStarMatchesAll() throws {
        let config = try parse("Host *\n    Hostname hostname1\n")
        assertConfig(config, resolves: ["pattern1", "pattern2", ""], to: "hostname1")
    }

    /// A star suffix matches all suffixes.
    func testStarSuffix() throws {
        let config = try parse("Host a*\n    Hostname hostname1\n")
        assertConfig(config, resolves: ["abcdef", "a"], to: "hostname1", andNot: [""])
    }

    /// A star in the middle of a pattern works.
    func testMidlineStar() throws {
        let config = try parse("Host abc*xyz\n    Hostname hostname1\n")
        assertConfig(config,
                     resolves: ["abcxyz", "abc123xyz"],
                     to: "hostname1",
                     andNot: ["abc", "xyz", "abxyz", "abcyz", "abcabc"])
    }

    /// A star prefix works.
    func testLeadingStar() throws {
        let config = try parse("Host *xyz\n    Hostname hostname1\n")
        assertConfig(config, resolves: ["xyz", "123xyz"], to: "hostname1", andNot: ["abc", ""])
    }

    /// Multiple disjoint stars work.
    func testMultipleDisjointStars() throws {
        let config = try parse("Host a*b*c\n    Hostname hostname1\n")
        assertConfig(config, resolves: ["a12b34c", "abc"], to: "hostname1", andNot: ["abc1", ""])
    }

    /// Two stars in a row work.
    func testConsecutiveStars() throws {
        let config = try parse("Host a**z\n    Hostname hostname1\n")
        assertConfig(config, resolves: ["abcz", "abz", "az"], to: "hostname1", andNot: ["a", ""])
    }

    /// A star followed by a question mark works.
    func testStarQuestionMark() throws {
        let config = try parse("Host a*?z\n    Hostname hostname1\n")
        assertConfig(config, resolves: ["abcz", "abz"], to: "hostname1", andNot: ["az", "a", ""])
    }

    /// A Host line with several comma-separated pattern lists.
    func testMultiplePatternLists() throws {
        let config = try parse("Host pattern1,pattern2 pattern3,pattern4\n    Hostname hostname1\n")
        assertConfig(config,
                     resolves: ["pattern1", "pattern2", "pattern3", "pattern4"],
                     to: "hostname1")
    }

    /// A negated pattern alone matches nothing.
    func testNegationAlone() throws {
        let config = try parse("Host !pattern1\n    Hostname hostname1\n")
        assertConfig(config, resolves: [], to: "hostname1", andNot: ["pattern1", "pattern2"])
    }

    /// A negated pattern combined with a matchable pattern.
    func testNegationPlusMatchablePattern() throws {
        let config = try parse("Host !*x* a*\n    Hostname hostname1\n")
        assertConfig(config, resolves: ["abc"], to: "hostname1", andNot: ["axy", "b"])
    }

    /// Two blocks where the first negates and the second matches.
    func testTwoRulesWhereFirstNegatesAndSecondMatches() throws {
        let config = try parse("""
            Host !*x* a*
                Hostname hostname1
            Host *z
                Hostname hostname2

            """)
        assertConfig(config, resolves: ["abc"], to: "hostname1", andNot: ["axy", "b"])
        assertConfig(config, resolves: ["axz", "xz", "z"], to: "hostname2")
    }

    /// Two blocks that both match are merged, and the first value for each setting wins.
    func testMergeTwoMatchingRules() throws {
        let config = try parse("""
            Host *
                Hostname hostname1
                Port 1
                IdentityFile id_file1
            Host *
                Hostname hostname2
                Port 2
                User user
                IdentityFile id_file2

            """)
        let hostConfig = config.hostConfig(forHost: "hostname")
        XCTAssertEqual(hostConfig?.hostname, "hostname1")
        XCTAssertEqual(hostConfig?.port, 1)
        XCTAssertEqual(hostConfig?.user, "user")
        XCTAssertEqual(identityFiles(hostConfig), ["id_file1", "id_file2"])
    }
}
