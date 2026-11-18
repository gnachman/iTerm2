//
//  NMSSHConfigOpenSSHDifferenceTests.swift
//  ModernTests
//
//  Records where NMSSHConfig and iTerm2's use of it disagree with OpenSSH today. These are not
//  behaviors to preserve: each test asserts the current result so that changing it is a
//  visible, deliberate decision. When a change makes iTerm2 agree with OpenSSH, update the
//  assertion (and move the test to NMSSHConfigCharacterizationTests if it then belongs there).
//
//  Each test names what OpenSSH does instead, per readconf.c.
//

import XCTest
@testable import iTerm2SharedARC

final class NMSSHConfigOpenSSHDifferenceTests: XCTestCase {
    private func lookup(_ host: String,
                        in contents: String,
                        file: StaticString = #filePath,
                        line: UInt = #line) throws -> NMSSHHostConfig? {
        let config = try XCTUnwrap(NMSSHConfig(string: contents), "Config failed to parse",
                                   file: file, line: line)
        return config.hostConfig(forHost: host)
    }

    // MARK: - Blocks

    /// NMSSH ignores Match lines but not the settings under them, so they attach to the Host
    /// block above. OpenSSH applies them only when the Match criteria hold (here, never for
    /// host “web”).
    func testSettingsUnderMatchLeakIntoPreviousHostBlock() throws {
        let hostConfig = try lookup("web", in: """
            Host web
                Hostname web.example.com
            Match host other.example.com
                Port 9999
                User intruder

            """)
        XCTAssertEqual(hostConfig?.port, 9999)
        XCTAssertEqual(hostConfig?.user, "intruder")
    }

    /// NMSSH ignores Include lines entirely. OpenSSH reads the named files in place.
    func testIncludeIsIgnored() throws {
        let hostConfig = try lookup("web", in: """
            Include /nonexistent/included.conf
            Host web
                Port 2222

            """)
        XCTAssertEqual(hostConfig?.port, 2222)
    }

    /// NMSSH drops settings that come before the first Host line. OpenSSH applies them to
    /// every host.
    func testSettingsBeforeFirstHostAreIgnored() throws {
        let contents = """
            User global
            Port 2222
            Host web
                Hostname web.example.com

            """
        let hostConfig = try lookup("web", in: contents)
        XCTAssertEqual(hostConfig?.hostname, "web.example.com")
        XCTAssertNil(hostConfig?.user)
        XCTAssertNil(hostConfig?.port)
        XCTAssertNil(try lookup("other", in: contents))
    }

    /// Within one block, NMSSH lets the last value win. OpenSSH keeps the first, as it does
    /// across blocks.
    func testLastValueWinsWithinBlock() throws {
        let hostConfig = try lookup("web", in: """
            Host web
                Hostname first.example.com
                Hostname second.example.com
                Port 1
                Port 2

            """)
        XCTAssertEqual(hostConfig?.hostname, "second.example.com")
        XCTAssertEqual(hostConfig?.port, 2)
    }

    // MARK: - Lexing

    /// NMSSH treats “Keyword=value” as an unknown keyword. OpenSSH accepts “=” as the separator.
    func testEqualsSeparatorWithoutSpacesIsIgnored() throws {
        let hostConfig = try lookup("web", in: "Host web\n    Hostname=example.com\n    Port=2222\n")
        XCTAssertNotNil(hostConfig)
        XCTAssertNil(hostConfig?.hostname)
        XCTAssertNil(hostConfig?.port)
    }

    /// With spaces around “=”, NMSSH takes “=” as the value. For Port, that parses as 0.
    /// OpenSSH reads the value after the “=”.
    func testEqualsSeparatorWithSpacesTakesEqualsAsValue() throws {
        let hostConfig = try lookup("web", in: "Host web\n    Hostname = example.com\n    Port = 2222\n")
        XCTAssertEqual(hostConfig?.hostname, "=")
        XCTAssertEqual(hostConfig?.port, 0)
    }

    /// NMSSH treats words after “#” on a Host line as more patterns. OpenSSH stops at the “#”.
    func testCommentOnHostLineAddsPatterns() throws {
        let contents = "Host web # production\n    User alice\n"
        XCTAssertEqual(try lookup("web", in: contents)?.user, "alice")
        XCTAssertEqual(try lookup("production", in: contents)?.user, "alice")
    }

    // MARK: - Matching

    /// NMSSH lowercases patterns but not the host. OpenSSH's Host matching is case-sensitive
    /// against the host as typed.
    func testPatternsAreLowercasedButHostIsNot() throws {
        XCTAssertEqual(try lookup("web", in: "Host WEB\n    User alice\n")?.user, "alice")
        XCTAssertNil(try lookup("WEB", in: "Host web\n    User alice\n"))
    }

    /// NMSSH splits each Host argument on commas. OpenSSH treats a Host argument as a single
    /// pattern (commas are only lists in Match criteria). We intend to keep this leniency.
    func testCommaListInHostArgument() throws {
        XCTAssertEqual(try lookup("b", in: "Host a,b\n    User alice\n")?.user, "alice")
    }

    // MARK: - Values

    /// NMSSH returns HostName verbatim. OpenSSH expands %h to the host as typed, and %% to %.
    func testHostNameTokensAreNotExpanded() throws {
        XCTAssertEqual(try lookup("web", in: "Host web\n    Hostname %h.example.com\n")?.hostname,
                       "%h.example.com")
    }

    /// NMSSH masks out-of-range ports to 16 bits. OpenSSH rejects the config.
    func testPortAboveRangeWraps() throws {
        XCTAssertEqual(try lookup("web", in: "Host web\n    Port 65537\n")?.port, 1)
    }

    /// NMSSH parses a non-numeric port as 0. OpenSSH rejects the config.
    func testNonNumericPortIsZero() throws {
        XCTAssertEqual(try lookup("web", in: "Host web\n    Port ssh\n")?.port, 0)
    }

    /// NMSSH reads leading digits. OpenSSH rejects the config.
    func testPortWithTrailingGarbageUsesLeadingDigits() throws {
        XCTAssertEqual(try lookup("web", in: "Host web\n    Port 22x\n")?.port, 22)
    }

    /// NMSSH accepts port 0. OpenSSH rejects it.
    func testPortZeroIsAccepted() throws {
        XCTAssertEqual(try lookup("web", in: "Host web\n    Port 0\n")?.port, 0)
    }

    /// NMSSH uses the first word and ignores the rest. OpenSSH rejects the line.
    func testExtraWordsAfterValueAreIgnored() throws {
        XCTAssertEqual(try lookup("web", in: "Host web\n    Hostname a.example.com b.example.com\n")?.hostname,
                       "a.example.com")
    }
}
