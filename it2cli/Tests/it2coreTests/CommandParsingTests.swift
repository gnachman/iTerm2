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

    /// The shortcut shares SetStatusOptions with the subcommand rather than
    /// restating them, so an option added to one cannot be missing from the
    /// other. That is not hypothetical: cc-status calls the shortcut, and an
    /// earlier restated copy failed every call. These parse the same
    /// arguments through both to keep that promise.
    func testSetStatusAcceptsANegativeBackgroundTasksDelta() throws {
        // A bare "-1" looks like a flag unless the option parses
        // unconditionally, and decrementing is the whole point of the option.
        let viaShortcut = try SetStatusShortcut.parse(
            ["-s", "session-id", "--background-tasks-delta", "-1"])
        XCTAssertEqual(viaShortcut.options.backgroundTasksDelta, -1)

        let viaSubcommand = try Session.SetStatus.parse(
            ["-s", "session-id", "--background-tasks-delta", "-1"])
        XCTAssertEqual(viaSubcommand.options.backgroundTasksDelta, -1)
    }

    func testSetStatusParsesTurnOpen() throws {
        let open = try Session.SetStatus.parse(["-s", "session-id", "--turn-open", "true"])
        XCTAssertEqual(open.options.turnOpen, true)
        let closed = try SetStatusShortcut.parse(["-s", "session-id", "--turn-open", "false"])
        XCTAssertEqual(closed.options.turnOpen, false)
        XCTAssertNil(try Session.SetStatus.parse(["-s", "session-id"]).options.turnOpen)
    }

    func testSetStatusParsesJSON() throws {
        XCTAssertTrue(try Session.SetStatus.parse(["-s", "session-id", "--json"]).options.json)
        XCTAssertTrue(try SetStatusShortcut.parse(["-s", "session-id", "--json"]).options.json)
        XCTAssertFalse(try Session.SetStatus.parse(["-s", "session-id"]).options.json)
    }

    func testSetStatusParsesPreconditions() throws {
        let guarded = try Session.SetStatus.parse(
            ["-s", "session-id", "--if-turn-open", "false", "--if-background-tasks", "0"])
        XCTAssertEqual(guarded.options.ifTurnOpen, false)
        XCTAssertEqual(guarded.options.ifBackgroundTasks, 0)
        let viaShortcut = try SetStatusShortcut.parse(
            ["-s", "session-id", "--if-turn-open", "false", "--if-background-tasks", "0"])
        XCTAssertEqual(viaShortcut.options.ifTurnOpen, false)
        XCTAssertEqual(viaShortcut.options.ifBackgroundTasks, 0)
        let plain = try Session.SetStatus.parse(["-s", "session-id"])
        XCTAssertNil(plain.options.ifTurnOpen)
        XCTAssertNil(plain.options.ifBackgroundTasks)
    }

    /// set_session_status has answered with nothing, and now with the full
    /// status, depending on the iTerm2 it reaches. The update has
    /// landed by the time the answer is looked at, so an answer in an older
    /// form must not be reported as a failure: the status is read back
    /// instead, and only when that is impossible does the caller hear that
    /// the update went through but its result is unknown.
    func testSetStatusJSONResultIsPassedThroughWhenItIsAnObject() throws {
        var readBacks = 0
        let json = try Session.SetStatus.statusJSON(
            fromResult: #"{"status":"idle","detail":null,"background_tasks":0,"turn_open":false}"#) {
                readBacks += 1
                return "{}"
            }
        XCTAssertEqual(json, #"{"status":"idle","detail":null,"background_tasks":0,"turn_open":false}"#)
        XCTAssertEqual(readBacks, 0)
    }

    func testSetStatusJSONReadsBackWhenTheResultIsNotTheStatus() throws {
        for result in ["1", ""] {
            let json = try Session.SetStatus.statusJSON(fromResult: result) {
                return #"{"status":null,"detail":null,"background_tasks":1,"turn_open":null}"#
            }
            XCTAssertEqual(json, #"{"status":null,"detail":null,"background_tasks":1,"turn_open":null}"#,
                           "result \(result)")
        }
    }

    func testSetStatusJSONFailsHonestlyWhenNothingCanBeReadBack() {
        XCTAssertThrowsError(try Session.SetStatus.statusJSON(fromResult: "1") { "" }) { error in
            let text = "\(error)"
            XCTAssertTrue(text.contains("updated"), text)
        }
        XCTAssertThrowsError(try Session.SetStatus.statusJSON(fromResult: "") {
            throw IT2Error.apiError("Get status failed: unknown function")
        })
    }

    func testGetStatusParses() throws {
        let command = try IT2.parseAsRoot(["session", "get-status", "-s", "session-id"])
        XCTAssertTrue(command is Session.GetStatus, "expected Session.GetStatus, got \(type(of: command))")
    }

    func testUnknownSubcommandThrows() {
        XCTAssertThrowsError(try IT2.parseAsRoot(["definitely-not-a-real-command"]))
    }
}
