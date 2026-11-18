//
//  SSHConfigCharacterizationTests.swift
//  ModernTests
//
//  Pins down config behavior iTerm2 relied on with NMSSH's original parser and that agrees
//  with OpenSSH (or is a deliberate leniency). Written against the old parser before it was
//  replaced, and now run against SSHConfigResolver to show the replacement keeps it.
//

import XCTest
@_spi(Testing) import NMSSH

final class SSHConfigCharacterizationTests: XCTestCase {
    private var fixture: SSHConfigTestFixture!

    override func setUpWithError() throws {
        fixture = try SSHConfigTestFixture()
    }

    override func tearDown() {
        fixture = nil
    }

    private func lookup(_ host: String, in contents: String) throws -> NMSSHHostConfig {
        return try fixture.resolve(host, in: contents)
    }

    // MARK: - Lexing

    func testKeywordsAreCaseInsensitive() throws {
        let hostConfig = try lookup("web", in: """
            HOST web
                HoStNaMe example.com
                USER alice
                PORT 2222
                IDENTITYFILE /keys/id

            """)
        XCTAssertEqual(hostConfig.hostname, "example.com")
        XCTAssertEqual(hostConfig.user, "alice")
        XCTAssertEqual(hostConfig.port, 2222)
        XCTAssertEqual(hostConfig.identityFilePaths, ["/keys/id"])
    }

    func testTabsSeparateKeywordsAndValues() throws {
        let hostConfig = try lookup("web", in: "Host\tweb\n\tHostname\texample.com\n\tPort\t2222\n")
        XCTAssertEqual(hostConfig.hostname, "example.com")
        XCTAssertEqual(hostConfig.port, 2222)
    }

    func testCRLFLineEndings() throws {
        let hostConfig = try lookup("web", in: "Host web\r\n    Hostname example.com\r\n    Port 2222\r\n")
        XCTAssertEqual(hostConfig.hostname, "example.com")
        XCTAssertEqual(hostConfig.port, 2222)
    }

    func testNoTrailingNewline() throws {
        XCTAssertEqual(try lookup("web", in: "Host web\n    Hostname example.com").hostname, "example.com")
    }

    func testIndentedComment() throws {
        let hostConfig = try lookup("web", in: """
            Host web
                # Hostname wrong.example.com
                Hostname example.com

            """)
        XCTAssertEqual(hostConfig.hostname, "example.com")
    }

    func testTrailingCommentAfterValueIsIgnored() throws {
        let hostConfig = try lookup("web", in: """
            Host web
                Hostname example.com # the real one
                Port 2222 # not the default

            """)
        XCTAssertEqual(hostConfig.hostname, "example.com")
        XCTAssertEqual(hostConfig.port, 2222)
    }

    func testQuotedValue() throws {
        let hostConfig = try lookup("web", in: """
            Host web
                Hostname "example.com"
                IdentityFile "/path with spaces/id"

            """)
        XCTAssertEqual(hostConfig.hostname, "example.com")
        XCTAssertEqual(hostConfig.identityFilePaths, ["/path with spaces/id"])
    }

    /// An unterminated quote drops that one line; the rest of the block still applies.
    func testUnterminatedQuoteInValueDropsOnlyThatLine() throws {
        let hostConfig = try lookup("web", in: """
            Host web
                Hostname "example.com
                Port 2222

            """)
        XCTAssertNil(hostConfig.hostname)
        XCTAssertEqual(hostConfig.port, 2222)
    }

    /// Settings iTerm2 doesn't read (most of ssh_config) don't disturb the ones it does.
    func testUnreadSettingsAreIgnored() throws {
        let hostConfig = try lookup("web", in: """
            Host web
                ForwardAgent yes
                ProxyJump bastion
                Hostname example.com
                ServerAliveInterval 30
                User alice

            """)
        XCTAssertEqual(hostConfig.hostname, "example.com")
        XCTAssertEqual(hostConfig.user, "alice")
    }

    /// A line with a keyword and no value is skipped without affecting the rest.
    func testKeywordWithoutValueIsSkipped() throws {
        let hostConfig = try lookup("web", in: """
            Host web
                Hostname
                User
                Port 2222

            """)
        XCTAssertNil(hostConfig.hostname)
        XCTAssertNil(hostConfig.user)
        XCTAssertEqual(hostConfig.port, 2222)
    }

    // MARK: - Host matching

    /// A negated pattern after a positive one excludes the host.
    func testNegationAfterPositivePattern() throws {
        let contents = "Host a* !ab\n    Hostname example.com\n"
        XCTAssertEqual(try lookup("abc", in: contents).hostname, "example.com")
        XCTAssertTrue(try lookup("ab", in: contents).isEmpty)
    }

    /// Negation also works inside a comma-separated list on one Host argument.
    func testNegationInsideCommaList() throws {
        let contents = "Host a*,!ab\n    Hostname example.com\n"
        XCTAssertEqual(try lookup("abc", in: contents).hostname, "example.com")
        XCTAssertTrue(try lookup("ab", in: contents).isEmpty)
    }

    /// A host excluded from one block still matches later blocks.
    func testNegatedBlockDoesNotHideLaterBlocks() throws {
        let hostConfig = try lookup("bastion", in: """
            Host * !bastion
                ProxyJump bastion
                User inner
            Host *
                User outer

            """)
        XCTAssertEqual(hostConfig.user, "outer")
    }

    func testDottedHostnamePatterns() throws {
        let contents = "Host *.example.com\n    User alice\n"
        XCTAssertEqual(try lookup("web.example.com", in: contents).user, "alice")
        XCTAssertTrue(try lookup("example.com", in: contents).isEmpty)
        XCTAssertTrue(try lookup("web.example.org", in: contents).isEmpty)
    }

    func testIPAddressPatterns() throws {
        let contents = "Host 10.0.0.*\n    User alice\n"
        XCTAssertEqual(try lookup("10.0.0.5", in: contents).user, "alice")
        XCTAssertTrue(try lookup("10.0.1.5", in: contents).isEmpty)
    }

    // MARK: - Precedence

    /// For HostName, User, and Port, the first matching block to set a value wins, even with
    /// non-matching blocks in between.
    func testFirstValueWinsAcrossBlocks() throws {
        let hostConfig = try lookup("web", in: """
            Host web
                Hostname web.example.com
            Host other
                Hostname other.example.com
                Port 1
                User nobody
            Host *
                Hostname fallback.example.com
                Port 2222
                User alice

            """)
        XCTAssertEqual(hostConfig.hostname, "web.example.com")
        XCTAssertEqual(hostConfig.port, 2222)
        XCTAssertEqual(hostConfig.user, "alice")
    }

    /// A `Host *` block that comes first beats a more specific block after it, as in OpenSSH.
    func testEarlierWildcardBeatsLaterSpecificBlock() throws {
        let hostConfig = try lookup("web", in: """
            Host *
                Port 1
            Host web
                Port 2
                User alice

            """)
        XCTAssertEqual(hostConfig.port, 1)
        XCTAssertEqual(hostConfig.user, "alice")
    }

    /// IdentityFile accumulates across matching blocks in file order, without duplicates.
    func testIdentityFilesAccumulateWithoutDuplicates() throws {
        let hostConfig = try lookup("web", in: """
            Host web
                IdentityFile /keys/a
                IdentityFile /keys/b
                IdentityFile /keys/a
            Host *
                IdentityFile /keys/b
                IdentityFile /keys/c

            """)
        XCTAssertEqual(hostConfig.identityFilePaths, ["/keys/a", "/keys/b", "/keys/c"])
    }

    func testIdentityFileExpandsTilde() throws {
        let hostConfig = try lookup("web", in: "Host web\n    IdentityFile ~/.ssh/id_web\n")
        XCTAssertEqual(hostConfig.identityFilePaths, [fixture.home + "/.ssh/id_web"])
    }

    // MARK: - Port

    func testPortAtTopOfRange() throws {
        XCTAssertEqual(try lookup("web", in: "Host web\n    Port 65535\n").port, 65535)
    }

    func testNegativePortIsIgnored() throws {
        XCTAssertNil(try lookup("web", in: "Host web\n    Port -1\n").port)
    }

    /// A negative port in an earlier block doesn't stop a later block from supplying one.
    func testNegativePortFallsThroughToLaterBlock() throws {
        let hostConfig = try lookup("web", in: """
            Host web
                Port -1
            Host *
                Port 2222

            """)
        XCTAssertEqual(hostConfig.port, 2222)
    }
}
