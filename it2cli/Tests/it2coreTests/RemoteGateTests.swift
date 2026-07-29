import XCTest
import ArgumentParser
@testable import it2core

/// The embedded / over-SSH path must never run commands that mint or export durable local
/// credentials. `it2 auth cookie` drives osascript locally to produce a reusable
/// ITERM2_COOKIE/ITERM2_KEY; streaming that to a remote would escape the per-session grant.
final class RemoteGateTests: XCTestCase {
    // Direct invocation is blocked by name before parsing, so osascript is never spawned.
    func testAuthCookieBlockedOverSSHByName() {
        let cap = OutputCapture()
        let ctx = cap.context(channel: FakeChannel(), isRemote: true)
        let code = runToExitCode(["auth", "cookie"], ctx)
        XCTAssertEqual(code, IT2Error.invalidArgument("").exitCode)  // 4
        XCTAssertTrue(cap.err.joined().contains("not available over SSH integration"),
                      "expected an explanatory error, got \(cap.err)")
        XCTAssertTrue(cap.out.isEmpty, "no credential must be written to stdout: \(cap.out)")
    }

    // The --single-use variant (which skips the secondary approval) is blocked too.
    func testAuthCookieSingleUseBlockedOverSSH() {
        let cap = OutputCapture()
        let ctx = cap.context(channel: FakeChannel(), isRemote: true)
        let code = runToExitCode(["auth", "cookie", "--single-use"], ctx)
        XCTAssertEqual(code, IT2Error.invalidArgument("").exitCode)
        XCTAssertTrue(cap.out.isEmpty, "no credential over SSH: \(cap.out)")
    }

    // The runParsedCommand gate (the universal choke point) blocks a marked command even when
    // it is reached by delegation -- e.g. an alias resolving to `auth cookie` -- which the
    // by-name pre-parse gate would not see.
    func testRemoteForbiddenCommandBlockedViaRunParsedCommand() throws {
        let command = try IT2.parseAsRoot(["auth", "cookie"])
        XCTAssertTrue(command is RemoteForbiddenCommand, "auth cookie should be RemoteForbidden")
        let cap = OutputCapture()
        let ctx = cap.context(channel: FakeChannel(), isRemote: true)
        XCTAssertThrowsError(try runParsedCommand(command, ctx)) { error in
            guard case IT2Error.invalidArgument = error else {
                return XCTFail("expected invalidArgument, got \(error)")
            }
        }
    }

    // A stand-in forbidden command that runs without side effects (unlike auth cookie, which
    // spawns osascript), so both branches of the runParsedCommand gate can be exercised
    // end-to-end. run() emits a marker so the local (allowed) branch is observable.
    private struct FakeForbiddenCommand: ParsableCommand, IT2Runnable, RemoteForbiddenCommand {
        static let configuration = CommandConfiguration(commandName: "fakeforbidden")
        func run(_ context: IT2Context) throws { context.out("ran-locally") }
    }

    // Both branches of the gate, driven through the real runParsedCommand path:
    // remote -> rejected before run(); local -> allowed, run() executes. Guards against a
    // regression that inverts the isRemote condition (which a flag-only assertion would miss).
    func testRunParsedCommandGateBothBranches() throws {
        // Remote: rejected, run() never executes (no marker).
        let remoteCap = OutputCapture()
        let remoteCtx = remoteCap.context(channel: FakeChannel(), isRemote: true)
        XCTAssertThrowsError(try runParsedCommand(FakeForbiddenCommand(), remoteCtx))
        XCTAssertFalse(remoteCap.out.contains("ran-locally"), "remote must not run a forbidden command")

        // Local: allowed, run() executes.
        let localCap = OutputCapture()
        let localCtx = localCap.context(channel: FakeChannel(), isRemote: false)
        XCTAssertNoThrow(try runParsedCommand(FakeForbiddenCommand(), localCtx))
        XCTAssertTrue(localCap.out.contains("ran-locally"), "local must run the command; gate must not fire")
    }

    func testStandaloneContextIsNotRemote() {
        XCTAssertFalse(IT2Context.standalone.isRemote)
    }

    // The top-level subcommand is matched by position: a value that merely equals a command
    // name (e.g. `it2 session send auth`) must not be mistaken for the `auth` subtree.
    func testTopLevelSubcommandDetection() {
        XCTAssertEqual(it2TopLevelSubcommand(in: ["auth", "cookie"]), "auth")
        XCTAssertEqual(it2TopLevelSubcommand(in: ["session", "send", "auth"]), "session")
        XCTAssertNil(it2TopLevelSubcommand(in: ["--version"]))
    }

    // The runParsedCommand gate (the path an alias to `auth cookie` takes) must name the ROOT
    // command "auth", not the leaf "cookie" which is not a top-level command.
    func testForbiddenMessageNamesRootCommandNotLeaf() throws {
        XCTAssertEqual(it2RootSubcommandName(for: try IT2.parseAsRoot(["auth", "cookie"])), "auth")
        let command = try IT2.parseAsRoot(["auth", "cookie"])
        let ctx = OutputCapture().context(channel: FakeChannel(), isRemote: true)
        XCTAssertThrowsError(try runParsedCommand(command, ctx)) { error in
            guard case IT2Error.invalidArgument(let msg) = error else {
                return XCTFail("expected invalidArgument, got \(error)")
            }
            XCTAssertTrue(msg.contains("`it2 auth`"), "message must name the root command: \(msg)")
            XCTAssertFalse(msg.contains("cookie"), "message must not name the leaf: \(msg)")
        }
    }

    // Help/usage requests mint nothing, so the remote gate must let them through to print usage
    // rather than returning a security error implying the docs are forbidden.
    func testHelpRequestsAreNotBlocked() {
        XCTAssertTrue(it2IsHelpRequest(["auth", "--help"]))
        XCTAssertTrue(it2IsHelpRequest(["auth", "-h"]))
        XCTAssertTrue(it2IsHelpRequest(["help", "auth"]))
        XCTAssertFalse(it2IsHelpRequest(["auth", "cookie"]))

        for args in [["auth", "--help"], ["help", "auth"]] {
            let cap = OutputCapture()
            let ctx = cap.context(channel: FakeChannel(), isRemote: true)
            let code = runToExitCode(args, ctx)
            XCTAssertNotEqual(code, IT2Error.invalidArgument("").exitCode,
                              "\(args) should print usage, not be blocked")
            XCTAssertFalse((cap.out + cap.err).joined().contains("not available over SSH integration"),
                           "\(args) must not be reported as forbidden")
        }
    }
}
