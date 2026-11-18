//
//  SSHConfigNMSSHPortedTests.swift
//  ModernTests
//
//  NMSSH's original config tests (from submodules/NMSSH/NMSSHTests/NMSSHConfigTests.m, whose
//  target never built), first ported to Swift against the old NMSSHConfig parser and now run
//  against SSHConfigResolver, its replacement. Tests that inspected the old parser's list of
//  Host blocks are expressed as lookups. Where the replacement deliberately behaves
//  differently, the test says so.
//

import XCTest
@_spi(Testing) import NMSSH

final class SSHConfigNMSSHPortedTests: XCTestCase {
    private var fixture: SSHConfigTestFixture!

    override func setUpWithError() throws {
        fixture = try SSHConfigTestFixture()
    }

    override func tearDown() {
        fixture = nil
    }

    private func lookup(_ host: String, _ contents: String) throws -> NMSSHHostConfig {
        return try fixture.resolve(host, in: contents)
    }

    // MARK: - Parsing

    /// An empty config file is ok.
    func testEmptyConfig() throws {
        XCTAssertTrue(try lookup("anything", "").isEmpty)
    }

    /// A config file with all supported keywords is properly read.
    func testAllKeywords() throws {
        let hostConfig = try lookup("pattern", """
            Host pattern
                Hostname hostname
                User user
                Port 1234
                IdentityFile id_file

            """)
        XCTAssertEqual(hostConfig.hostname, "hostname")
        XCTAssertEqual(hostConfig.user, "user")
        XCTAssertEqual(hostConfig.port, 1234)
        XCTAssertEqual(hostConfig.identityFilePaths, ["id_file"])
    }

    /// Comments are ignored.
    func testCommentsIgnored() throws {
        let hostConfig = try lookup("pattern", """
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
        XCTAssertEqual(hostConfig.hostname, "hostname")
        XCTAssertEqual(hostConfig.port, 1234)
        XCTAssertEqual(hostConfig.identityFilePaths, ["id_file"])
    }

    /// Empty lines are ignored.
    func testEmptyLinesIgnored() throws {
        let hostConfig = try lookup("pattern", """

            Host pattern

                Hostname hostname

                Port 1234

                IdentityFile id_file


            """)
        XCTAssertEqual(hostConfig.hostname, "hostname")
        XCTAssertEqual(hostConfig.port, 1234)
        XCTAssertEqual(hostConfig.identityFilePaths, ["id_file"])
    }

    /// Unknown keywords are ignored.
    func testIgnoreUnknownKeywords() throws {
        let hostConfig = try lookup("pattern", """
            Host pattern
                Hostname hostname
                Port 1234
                jfkldsajfdkl fjdkslafjdl fdjkla fjdslkf asdl
                IdentityFile id_file

            """)
        XCTAssertEqual(hostConfig.hostname, "hostname")
        XCTAssertEqual(hostConfig.port, 1234)
        XCTAssertEqual(hostConfig.identityFilePaths, ["id_file"])
    }

    /// A malformed port line doesn't break parsing.
    func testMalformedPort() throws {
        let hostConfig = try lookup("pattern", """
            Host pattern
                Hostname hostname
                Port
                IdentityFile id_file

            """)
        XCTAssertEqual(hostConfig.hostname, "hostname")
        XCTAssertNil(hostConfig.port)
        XCTAssertEqual(hostConfig.identityFilePaths, ["id_file"])
    }

    /// Multiple patterns are parsed properly.
    func testMultiplePatterns() throws {
        let contents = "Host pattern1 pattern2\n    Hostname h\n"
        XCTAssertEqual(try lookup("pattern1", contents).hostname, "h")
        XCTAssertEqual(try lookup("pattern2", contents).hostname, "h")
    }

    /// Quoted patterns are parsed properly.
    func testQuotedPatterns() throws {
        let contents = "Host pattern1 \"a quoted pattern\" pattern2 \"foo bar\" \"baz\"\n    Hostname h\n"
        for host in ["pattern1", "a quoted pattern", "pattern2", "foo bar", "baz"] {
            XCTAssertEqual(try lookup(host, contents).hostname, "h", host)
        }
        XCTAssertNil(try lookup("a", contents).hostname)
    }

    /// The old parser kept the patterns before an unterminated quote. OpenSSH rejects the
    /// line; the replacement treats its block as not matching.
    func testUnterminatedQuotation() throws {
        let contents = "Host pattern1 \"unterminated quotation\n    Hostname h\n"
        XCTAssertNil(try lookup("pattern1", contents).hostname)
        XCTAssertNil(try lookup("other", contents).hostname)
    }

    /// Multiple identity file commands are respected.
    func testMultipleIdentityFile() throws {
        let hostConfig = try lookup("pattern", """
            Host pattern
                Hostname hostname
                Port 1234
                IdentityFile id_file1
                IdentityFile id_file2

            """)
        XCTAssertEqual(hostConfig.identityFilePaths, ["id_file1", "id_file2"])
    }

    /// Leading, trailing, and midline spaces are ignored.
    func testExtraSpaces() throws {
        let contents = "  Host         pattern    \"quoted pattern\"  \"   \"  \n"
            + "    Hostname    hostname      \n"
        for host in ["pattern", "quoted pattern", "   "] {
            XCTAssertEqual(try lookup(host, contents).hostname, "hostname", "“\(host)”")
        }
    }

    /// Multiple Host blocks.
    func testMultipleHosts() throws {
        let contents = """
            Host pattern1
                Hostname hostname1
                Port 1
                IdentityFile id_file1
            Host pattern2
                Hostname hostname2
                Port 2
                IdentityFile id_file2

            """
        var hostConfig = try lookup("pattern1", contents)
        XCTAssertEqual(hostConfig.hostname, "hostname1")
        XCTAssertEqual(hostConfig.port, 1)
        XCTAssertEqual(hostConfig.identityFilePaths, ["id_file1"])

        hostConfig = try lookup("pattern2", contents)
        XCTAssertEqual(hostConfig.hostname, "hostname2")
        XCTAssertEqual(hostConfig.port, 2)
        XCTAssertEqual(hostConfig.identityFilePaths, ["id_file2"])
    }

    // MARK: - Matching

    /// Asserts that each host in `matching` resolves to `hostname` and each in `notMatching`
    /// gets no settings.
    private func assertConfig(_ contents: String,
                              resolves matching: [String],
                              to hostname: String,
                              andNot notMatching: [String] = [],
                              file: StaticString = #filePath,
                              line: UInt = #line) throws {
        for host in matching {
            XCTAssertEqual(try lookup(host, contents).hostname, hostname,
                           "Match failed for “\(host)”", file: file, line: line)
        }
        for host in notMatching {
            XCTAssertTrue(try lookup(host, contents).isEmpty,
                          "Match should have failed for “\(host)”", file: file, line: line)
        }
    }

    /// A simple pattern matches.
    func testSimplestPossiblePattern() throws {
        try assertConfig("Host pattern1\n    Hostname hostname1\n", resolves: ["pattern1"], to: "hostname1")
    }

    /// A simple pattern fails when it ought to.
    func testSimplestPossiblePatternNoMatch() throws {
        try assertConfig("Host pattern1\n    Hostname hostname1\n", resolves: [], to: "hostname1", andNot: ["pattern2"])
    }

    /// A comma-separated pattern list of simple patterns works.
    func testSimplePatternList() throws {
        try assertConfig("Host pattern1,pattern2\n    Hostname hostname1\n",
                         resolves: ["pattern1", "pattern2"], to: "hostname1", andNot: ["pattern3"])
    }

    /// A question mark wildcard works.
    func testSingleCharWildcard() throws {
        try assertConfig("Host pattern?\n    Hostname hostname1\n",
                         resolves: ["pattern1", "pattern2"], to: "hostname1", andNot: ["Xattern3"])
    }

    /// A lone star matches everything, including the empty string.
    func testLoneStarMatchesAll() throws {
        try assertConfig("Host *\n    Hostname hostname1\n", resolves: ["pattern1", "pattern2", ""], to: "hostname1")
    }

    /// A star suffix matches all suffixes.
    func testStarSuffix() throws {
        try assertConfig("Host a*\n    Hostname hostname1\n", resolves: ["abcdef", "a"], to: "hostname1", andNot: [""])
    }

    /// A star in the middle of a pattern works.
    func testMidlineStar() throws {
        try assertConfig("Host abc*xyz\n    Hostname hostname1\n",
                         resolves: ["abcxyz", "abc123xyz"],
                         to: "hostname1",
                         andNot: ["abc", "xyz", "abxyz", "abcyz", "abcabc"])
    }

    /// A star prefix works.
    func testLeadingStar() throws {
        try assertConfig("Host *xyz\n    Hostname hostname1\n", resolves: ["xyz", "123xyz"], to: "hostname1", andNot: ["abc", ""])
    }

    /// Multiple disjoint stars work.
    func testMultipleDisjointStars() throws {
        try assertConfig("Host a*b*c\n    Hostname hostname1\n", resolves: ["a12b34c", "abc"], to: "hostname1", andNot: ["abc1", ""])
    }

    /// Two stars in a row work.
    func testConsecutiveStars() throws {
        try assertConfig("Host a**z\n    Hostname hostname1\n", resolves: ["abcz", "abz", "az"], to: "hostname1", andNot: ["a", ""])
    }

    /// A star followed by a question mark works.
    func testStarQuestionMark() throws {
        try assertConfig("Host a*?z\n    Hostname hostname1\n", resolves: ["abcz", "abz"], to: "hostname1", andNot: ["az", "a", ""])
    }

    /// A Host line with several comma-separated pattern lists.
    func testMultiplePatternLists() throws {
        try assertConfig("Host pattern1,pattern2 pattern3,pattern4\n    Hostname hostname1\n",
                         resolves: ["pattern1", "pattern2", "pattern3", "pattern4"],
                         to: "hostname1")
    }

    /// A negated pattern alone matches nothing.
    func testNegationAlone() throws {
        try assertConfig("Host !pattern1\n    Hostname hostname1\n", resolves: [], to: "hostname1", andNot: ["pattern1", "pattern2"])
    }

    /// A negated pattern combined with a matchable pattern.
    func testNegationPlusMatchablePattern() throws {
        try assertConfig("Host !*x* a*\n    Hostname hostname1\n", resolves: ["abc"], to: "hostname1", andNot: ["axy", "b"])
    }

    /// Two blocks where the first negates and the second matches.
    func testTwoRulesWhereFirstNegatesAndSecondMatches() throws {
        let contents = """
            Host !*x* a*
                Hostname hostname1
            Host *z
                Hostname hostname2

            """
        try assertConfig(contents, resolves: ["abc"], to: "hostname1", andNot: ["axy", "b"])
        try assertConfig(contents, resolves: ["axz", "xz", "z"], to: "hostname2")
    }

    /// Two blocks that both match are merged, and the first value for each setting wins.
    func testMergeTwoMatchingRules() throws {
        let hostConfig = try lookup("hostname", """
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
        XCTAssertEqual(hostConfig.hostname, "hostname1")
        XCTAssertEqual(hostConfig.port, 1)
        XCTAssertEqual(hostConfig.user, "user")
        XCTAssertEqual(hostConfig.identityFilePaths, ["id_file1", "id_file2"])
    }
}
