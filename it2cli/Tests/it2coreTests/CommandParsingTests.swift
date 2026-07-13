import XCTest
import ArgumentParser
@testable import it2core

// Unit tests for the command tree. These exercise argument parsing only; they
// never construct an APIClient or talk to a running iTerm2, so they are safe to
// run offline in CI.
final class CommandParsingTests: XCTestCase {
    func testRootCommandName() {
        XCTAssertEqual(IT2.configuration.commandName, "it2")
    }

    func testParsesSessionList() throws {
        let command = try IT2.parseAsRoot(["session", "list"])
        XCTAssertTrue(command is Session.List, "expected Session.List, got \(type(of: command))")
    }

    func testParsesSessionSend() throws {
        let command = try IT2.parseAsRoot(["session", "send", "hello"])
        XCTAssertTrue(command is Session.Send, "expected Session.Send, got \(type(of: command))")
    }

    func testTopLevelShortcutParses() throws {
        // `it2 ls` is a top-level alias for `it2 session list`.
        let command = try IT2.parseAsRoot(["ls"])
        XCTAssertTrue(command is LsShortcut, "expected LsShortcut, got \(type(of: command))")
    }

    func testParsesAuthCookie() throws {
        let command = try IT2.parseAsRoot(["auth", "cookie"])
        XCTAssertTrue(command is Auth.Cookie, "expected Auth.Cookie, got \(type(of: command))")
    }

    func testParsesAuthCookieSingleUse() throws {
        let command = try IT2.parseAsRoot(["auth", "cookie", "--single-use"])
        XCTAssertTrue(command is Auth.Cookie, "expected Auth.Cookie, got \(type(of: command))")
    }

    func testUnknownSubcommandThrows() {
        XCTAssertThrowsError(try IT2.parseAsRoot(["definitely-not-a-real-command"]))
    }
}
