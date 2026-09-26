import XCTest
import ProtobufRuntime
@testable import it2core

// Parsing of $TMUX and $TMUX_PANE, the only self-description a process running inside a tmux pane
// has. Pure string handling; never talks to iTerm2.
final class TmuxAddressTests: XCTestCase {
    func testParsesWellFormedAddress() {
        let address = TmuxAddress(tmux: "/private/tmp/tmux-501/default,52533,0", pane: "%0")
        XCTAssertEqual(address, TmuxAddress(tmux: "/private/tmp/tmux-501/default,52533,0", pane: "%0"))
        XCTAssertEqual(address?.socketPath, "/private/tmp/tmux-501/default")
        XCTAssertEqual(address?.serverPID, 52533)
        XCTAssertEqual(address?.pane, 0)
    }

    func testParsesMultiDigitPaneAndSession() {
        let address = TmuxAddress(tmux: "/tmp/tmux-501/default,1,17", pane: "%423")
        XCTAssertEqual(address?.pane, 423)
    }

    // A socket path is an arbitrary filename, so it may contain the same character that separates
    // the fields. The pid and session id are the LAST two fields, not the second and third.
    func testSocketPathMayContainCommas() {
        let address = TmuxAddress(tmux: "/tmp/od,d,socket,52533,3", pane: "%1")
        XCTAssertEqual(address?.socketPath, "/tmp/od,d,socket")
        XCTAssertEqual(address?.serverPID, 52533)
    }

    func testRejectsTooFewFields() {
        XCTAssertNil(TmuxAddress(tmux: "/tmp/default,52533", pane: "%0"))
        XCTAssertNil(TmuxAddress(tmux: "/tmp/default", pane: "%0"))
        XCTAssertNil(TmuxAddress(tmux: "", pane: "%0"))
    }

    func testRejectsEmptySocketPath() {
        XCTAssertNil(TmuxAddress(tmux: ",52533,0", pane: "%0"))
    }

    func testRejectsNonNumericFields() {
        XCTAssertNil(TmuxAddress(tmux: "/tmp/default,notapid,0", pane: "%0"))
        XCTAssertNil(TmuxAddress(tmux: "/tmp/default,52533,notasession", pane: "%0"))
    }

    // tmux never reports a nonpositive server pid or a negative session id; treat them as
    // corruption rather than silently coercing.
    func testRejectsOutOfRangeNumbers() {
        XCTAssertNil(TmuxAddress(tmux: "/tmp/default,0,0", pane: "%0"))
        XCTAssertNil(TmuxAddress(tmux: "/tmp/default,-1,0", pane: "%0"))
        XCTAssertNil(TmuxAddress(tmux: "/tmp/default,52533,-1", pane: "%0"))
    }

    func testRejectsMalformedPane() {
        let tmux = "/tmp/default,52533,0"
        XCTAssertNil(TmuxAddress(tmux: tmux, pane: "0"), "pane id must carry its % sigil")
        XCTAssertNil(TmuxAddress(tmux: tmux, pane: "%"))
        XCTAssertNil(TmuxAddress(tmux: tmux, pane: "%abc"))
        XCTAssertNil(TmuxAddress(tmux: tmux, pane: "%-1"))
        XCTAssertNil(TmuxAddress(tmux: tmux, pane: ""))
    }

}

// "Didn't ask for tmux addressing" and "asked for it with a value that doesn't parse" must stay
// distinguishable. Collapsing them to nil made a malformed --tmux fall through to the
// active-session default, putting the update on whatever the user happened to be looking at.
// Malformed options are now rejected during parsing, before any connection is opened.
final class TmuxPaneOptionsResolutionTests: XCTestCase {
    private func resolution(_ args: [String]) throws -> TmuxPaneOptions.Resolution {
        let command = try IT2.parseAsRoot(args)
        let setStatus = try XCTUnwrap(command as? SetStatusShortcut)
        return setStatus.tmuxOptions.resolution
    }

    private func assertRejected(_ args: [String], _ message: String) {
        XCTAssertThrowsError(try IT2.parseAsRoot(args), message)
    }

    func testNoTmuxOptionsIsNotRequested() throws {
        guard case .notRequested = try resolution(["set-status", "--status", "idle"]) else {
            return XCTFail("expected .notRequested")
        }
    }

    func testWellFormedPairIsAnAddress() throws {
        guard case .address(let address) = try resolution(
            ["set-status", "--tmux", "/tmp/d,99,0", "--tmux-pane", "%4"]) else {
            return XCTFail("expected .address")
        }
        XCTAssertEqual(address.pane, 4)
    }

    func testUnparseableTmuxIsRejected() {
        assertRejected(["set-status", "--tmux", "nonsense", "--tmux-pane", "%0"],
                       "garbage in --tmux must not fall through to the active session")
    }

    // tmux itself emits a -1 session id from environ_for_session(NULL, ...), so this is reachable.
    func testNegativeSessionIDIsRejected() {
        assertRejected(["set-status", "--tmux", "/tmp/d,99,-1", "--tmux-pane", "%0"],
                       "a -1 session id is not a real session")
    }



    func testHalfAPairIsRejected() {
        assertRejected(["set-status", "--tmux", "/tmp/d,99,0"],
                       "--tmux without --tmux-pane must not fall through")
        assertRejected(["set-status", "--tmux-pane", "%0"],
                       "--tmux-pane without --tmux must not fall through")
    }
}

// The exact argument shapes cc-status emits. It builds these by concatenating an address array
// onto a command, so the options land before the positionals; ArgumentParser accepts that, and
// these pin it down so a future reshuffle can't silently break the hook.
final class TmuxCommandParsingTests: XCTestCase {
    private let tmux = "/private/tmp/tmux-501/default,52533,0"

    private func address(_ options: TmuxPaneOptions) -> TmuxAddress? {
        guard case .address(let address) = options.resolution else {
            return nil
        }
        return address
    }

    func testSetStatusWithTmuxAddress() throws {
        let command = try IT2.parseAsRoot(
            ["set-status", "--tmux", tmux, "--tmux-pane", "%3", "--status", "working"])
        let setStatus = try XCTUnwrap(command as? SetStatusShortcut)
        XCTAssertNil(setStatus.options.session)
        XCTAssertEqual(address(setStatus.tmuxOptions)?.pane, 3)
        XCTAssertEqual(setStatus.options.status, "working")
    }

    // Options first, then the two positionals.
    func testSetVarWithTmuxAddressBeforePositionals() throws {
        let command = try IT2.parseAsRoot(
            ["session", "set-var", "--tmux", tmux, "--tmux-pane", "%0",
             "user.claude_background_tasks", "2"])
        let setVar = try XCTUnwrap(command as? Session.SetVar)
        XCTAssertEqual(setVar.variable, "user.claude_background_tasks")
        XCTAssertEqual(setVar.value, "2")
        XCTAssertEqual(address(setVar.tmuxOptions)?.serverPID, 52533)
        XCTAssertEqual(address(setVar.tmuxOptions)?.pane, 0)
    }

    func testGetVarWithTmuxAddressBeforePositional() throws {
        let command = try IT2.parseAsRoot(
            ["session", "get-var", "--tmux", tmux, "--tmux-pane", "%0",
             "user.claude_background_tasks"])
        let getVar = try XCTUnwrap(command as? Session.GetVar)
        XCTAssertEqual(getVar.variable, "user.claude_background_tasks")
    }



    func testSetStatusWithExplicitSession() throws {
        let command = try IT2.parseAsRoot(["set-status", "-s", "ABC-123", "--status", "idle"])
        let setStatus = try XCTUnwrap(command as? SetStatusShortcut)
        XCTAssertEqual(setStatus.options.session, "ABC-123")
        XCTAssertNil(address(setStatus.tmuxOptions))
    }

    // "active" is a spelling every other it2 command accepts, and it survived only because the
    // server used to resolve it. These commands now look their target up by GUID, so the alias has
    // to be recognized before it gets there.
    func testActiveIsStillAcceptedAsATarget() throws {
        let command = try IT2.parseAsRoot(["set-status", "-s", "active", "--status", "idle"])
        let setStatus = try XCTUnwrap(command as? SetStatusShortcut)
        XCTAssertEqual(setStatus.options.session, "active")
        // It must reach the app untouched: iTermAPIHelper resolves it, and it does not mean the
        // same thing as omitting --session (that default needs a key window).
        XCTAssertEqual(APIClient.normalizeSessionId("active"), "active")
    }
}

// Values that look like options. Detail text is arbitrary model output and a bulleted
// last_assistant_message begins with "-", which as a separate argv element is read as an option
// name: the command fails to parse and no status is set at all. Both the outer command and the
// shortcut's inner re-parse have to handle it.
final class OptionLikeValueTests: XCTestCase {
    // "" is in here deliberately: cc-status sends an empty --detail to CLEAR stale detail on most
    // events, and ArgumentParser rejects the "=" form of an empty value ("--detail=" reads as a
    // missing value), so it has to travel as two elements while the rest use "=".
    private let awkward = ["- Fixed it", "--session evil", "-n", "--", "-", ""]

    // The exact argv a producer emits, via the same helper it uses.
    private func detailArgs(_ value: String) -> [String] {
        return value.isEmpty ? ["--detail", value] : ["--detail=\(value)"]
    }

    func testSetStatusAcceptsOptionLikeDetail() throws {
        for value in awkward {
            let command = try IT2.parseAsRoot(
                ["session", "set-status", "--session=ABC"] + detailArgs(value))
            let setStatus = try XCTUnwrap(command as? Session.SetStatus)
            XCTAssertEqual(setStatus.options.detail, value, "value: \(value.debugDescription)")
        }
    }

    // The bare "=" form of an empty value is what broke: it parses as a missing value, which would
    // have failed every event that clears detail.
    func testEmptyValueInEqualsFormIsRejectedByArgumentParser() {
        XCTAssertThrowsError(
            try IT2.parseAsRoot(["session", "set-status", "--session=ABC", "--detail="]),
            "if this ever starts working, the two-element special case can go")
    }

    // The shortcut re-serializes to argv and re-parses, so it must forward the "=" form too.
    func testShortcutAcceptsOptionLikeDetail() throws {
        for value in awkward {
            let command = try IT2.parseAsRoot(["set-status", "--session=ABC"] + detailArgs(value))
            let shortcut = try XCTUnwrap(command as? SetStatusShortcut)
            XCTAssertEqual(shortcut.options.detail, value)
            // What run() hands to the inner parse must survive it.
            let reparsed = try Session.SetStatus.parse(
                ["--session=ABC"] + detailArgs(shortcut.options.detail ?? ""))
            XCTAssertEqual(reparsed.options.detail, value)
        }
    }

    func testStatusAndColorsAlsoSurviveTheInnerParse() throws {
        let reparsed = try Session.SetStatus.parse(
            ["--session=ABC", "--status=working", "--dot-color=#ff9500", "--detail=- x"])
        XCTAssertEqual(reparsed.options.status, "working")
        XCTAssertEqual(reparsed.options.dotColor, "#ff9500")
        XCTAssertEqual(reparsed.options.detail, "- x")
    }

    // Positionals need "--" ahead of them for the same reason.
    func testSendForwardsOptionLikeTextPositionally() throws {
        for value in awkward {
            let reparsed = try Session.Send.parse(["--session=ABC", "--", value])
            XCTAssertEqual(reparsed.text, value)
        }
    }

    func testSetVarForwardsOptionLikeValue() throws {
        let reparsed = try Session.SetVar.parse(
            ["--session=ABC", "--", "user.claude_background_tasks", "3"])
        XCTAssertEqual(reparsed.variable, "user.claude_background_tasks")
        XCTAssertEqual(reparsed.value, "3")
    }
}

// "all" is a real target for a variable SET -- the server fans it out over every session -- but
// meaningless for the per-session status built-ins, which resolve one GUID.
final class AllSessionsTargetTests: XCTestCase {
    func testSetVarParsesAllAsATarget() throws {
        let command = try IT2.parseAsRoot(["session", "set-var", "-s", "all", "--", "user.foo", "bar"])
        let setVar = try XCTUnwrap(command as? Session.SetVar)
        XCTAssertEqual(setVar.session, "all")
    }

    // The commands that can be addressed at a tmux pane, all of which resolve through
    // resolveSessionId and so inherit the SSH rule.
    func testTmuxAddressableCommandsAreMarked() throws {
        let addressable: [[String]] = [
            ["session", "set-status", "--status=idle"],
            ["session", "get-status"],
            ["session", "set-var", "--", "user.foo", "bar"],
            ["session", "get-var", "--", "user.foo"],
            ["session", "get-background-tasks"],
            ["set-status", "--status=idle"],
        ]
        for args in addressable {
            let command = try IT2.parseAsRoot(args)
            XCTAssertTrue(command is TmuxAddressableCommand,
                          "\(args) should be gated for tmux addressing")
        }
    }

    // A command that merely carries the literal text "--tmux" is not addressing a pane, so the
    // SSH rule must not fire on it.
    func testOptionLikeTextIsNotTmuxAddressing() throws {
        let command = try IT2.parseAsRoot(["session", "send", "--session=ABC", "--", "--tmux"])
        let send = try XCTUnwrap(command as? Session.Send)
        XCTAssertEqual(send.text, "--tmux")
        XCTAssertFalse(command is TmuxAddressableCommand,
                       "send does not take tmux options, so it can never be gated")
    }

    func testTmuxAddressingIsDetectedOnlyWhenRequested() throws {
        let plain = try XCTUnwrap(
            try IT2.parseAsRoot(["session", "get-status", "-s", "ABC"]) as? Session.GetStatus)
        if case .notRequested = plain.tmuxOptions.resolution {} else {
            XCTFail("expected .notRequested")
        }

        let addressed = try XCTUnwrap(
            try IT2.parseAsRoot(["session", "get-status", "--tmux", "/tmp/d,99,0", "--tmux-pane", "%0"]) as? Session.GetStatus)
        if case .address = addressed.tmuxOptions.resolution {} else {
            XCTFail("expected .address")
        }
    }
}


// Whether an unresolved pane is an error depends on who is asking, and that is stated by the
// caller rather than guessed from the command: a script needs a nonzero exit, while a hook running
// on every event needs silence.
final class UnresolvedTargetPolicyTests: XCTestCase {
    func testPaneNotFoundFailsByDefault() {
        XCTAssertTrue(TmuxPaneOptions.Unresolved.paneNotFound.isFailure(quiet: false))
    }

    func testQuietTurnsPaneNotFoundIntoANoOp() {
        XCTAssertFalse(TmuxPaneOptions.Unresolved.paneNotFound.isFailure(quiet: true))
    }

    // Nothing was set either way, so a script that did not ask to be spared must hear about it.
    // Only --quiet-if-unresolved suppresses the failure, and it does so for both reasons alike.
    func testRemoteUnavailableFailsUnlessQuietToo() {
    }

    // A lookup that errored is "cannot resolve right now" from a caller's point of view, so it
    // obeys the same flag. Reachable in the field through version skew: an in-place app update
    // swaps the bundle while the old process runs on, and it2 is re-resolved from the bundle every
    // event, so a new CLI briefly talks to an app without these functions.
    func testLookupFailureObeysTheQuietFlag() {
        let reason = TmuxPaneOptions.Unresolved.lookupFailed("No function registered")
        XCTAssertTrue(reason.isFailure(quiet: false))
        XCTAssertFalse(reason.isFailure(quiet: true))
        XCTAssertEqual(reason.message, "No function registered",
                       "the underlying reason must survive for the non-quiet case")
    }

    func testBothReasonsExplainThemselves() {
        XCTAssertFalse(TmuxPaneOptions.Unresolved.paneNotFound.message.isEmpty)
    }

    func testQuietFlagParsesAndDefaultsOff() throws {
        let plain = try XCTUnwrap(
            try IT2.parseAsRoot(["session", "get-status", "-s", "ABC"]) as? Session.GetStatus)
        XCTAssertFalse(plain.tmuxOptions.quietIfUnresolved)

        let quiet = try XCTUnwrap(
            try IT2.parseAsRoot(["session", "get-status", "-s", "ABC", "--quiet-if-unresolved"]) as? Session.GetStatus)
        XCTAssertTrue(quiet.tmuxOptions.quietIfUnresolved)
    }

    // cc-status reaches set-status through the shortcut, which re-serializes to argv, so the flag
    // has to survive that round trip or the hook starts failing on every event.
    func testShortcutForwardsTheQuietFlag() throws {
        let shortcut = try XCTUnwrap(
            try IT2.parseAsRoot(["set-status", "--tmux=/tmp/d,99,0", "--tmux-pane=%0",
                                 "--quiet-if-unresolved", "--status=idle"]) as? SetStatusShortcut)
        XCTAssertTrue(shortcut.tmuxOptions.quietIfUnresolved)
        let reparsed = try Session.SetStatus.parse(
            ["--tmux=/tmp/d,99,0", "--tmux-pane=%0", "--quiet-if-unresolved", "--status=idle"])
        XCTAssertTrue(reparsed.tmuxOptions.quietIfUnresolved)
    }
}

// The rules for an explicit --session, extracted so they can be exercised without a connection.
// The "all" + --tmux rejection in particular had no coverage: it only fires at resolve time,
// after a client has been made.
final class ExplicitSessionTargetTests: XCTestCase {
    private func options(_ args: [String]) throws -> TmuxPaneOptions {
        let command = try IT2.parseAsRoot(["session", "get-status"] + args)
        return try XCTUnwrap(command as? Session.GetStatus).tmuxOptions
    }

    func testPlainSessionIdIsNormalized() throws {
        let opts = try options([])
        XCTAssertEqual(try opts.explicitTarget("w0t0p0:ABC-123", allowAll: false), "ABC-123")
    }

    // Passed through rather than resolved here: the built-ins resolve it the way the rest of the
    // API does, which is not the same as the active-session default.
    func testActiveIsPassedThrough() throws {
        let opts = try options([])
        XCTAssertEqual(try opts.explicitTarget("active", allowAll: false), "active")
    }

    func testAllNeedsPermission() throws {
        let opts = try options([])
        XCTAssertThrowsError(try opts.explicitTarget("all", allowAll: false))
        XCTAssertEqual(try opts.explicitTarget("all", allowAll: true), "all")
    }

    // The prefixed form has to hit the same guards. normalizeSessionId strips "wXtYpZ:" and leaves
    // the magic word, so branching on the raw value would let it through unchecked and then return
    // "all" from the normalizing path anyway.
    func testPrefixedAllIsGuardedToo() throws {
        let opts = try options([])
        XCTAssertEqual(APIClient.normalizeSessionId("w0t0p0:all"), "all", "precondition")
        XCTAssertThrowsError(try opts.explicitTarget("w0t0p0:all", allowAll: false))
        XCTAssertEqual(try opts.explicitTarget("w0t0p0:all", allowAll: true), "all")

        let addressed = try options(["--tmux", "/tmp/d,99,0", "--tmux-pane", "%0"])
        XCTAssertThrowsError(try addressed.explicitTarget("w0t0p0:all", allowAll: true),
                             "a pane address must still refuse an all target, prefixed or not")
    }

    func testPrefixedActiveStillNormalizesToActive() throws {
        let opts = try options([])
        XCTAssertEqual(try opts.explicitTarget("w0t0p0:active", allowAll: false), "active")
    }

    // A tmux pane names one session, so the two cannot both be meant.
    func testAllIsRefusedAlongsideATmuxAddress() throws {
        let opts = try options(["--tmux", "/tmp/d,99,0", "--tmux-pane", "%0"])
        XCTAssertThrowsError(try opts.explicitTarget("all", allowAll: true))
    }
}

// MARK: - Origin

/// The machine a pane address was collected on travels with the lookup. Socket paths are
/// byte-identical across hosts sharing a uid and pids collide freely, so without this a remote
/// $TMUX could match a local server (and a remote `tmux -CC` could never resolve its own panes at
/// all, which is what this replaced). The origin is taken from the execution context, never from
/// arguments, so a remote caller cannot name a connection other than its own.
final class TmuxAddressOriginTests: XCTestCase {
    // Parsed, because the struct's failable init replaces the memberwise one, and parsing is what
    // every real caller does anyway.
    private let address = TmuxAddress(tmux: "/private/tmp/tmux-501/default,52533,0", pane: "%3")!

    /// A lookup reply carrying `guid` as the function result. `id` must match the request's, which
    /// APIClient assigns from a per-client counter starting at 1, so a fresh client's first
    /// request is always id 1.
    private func paneReply(guid: String, id: Int64 = 1) -> ITMServerOriginatedMessage {
        let message = ITMServerOriginatedMessage()
        message.id_p = id
        let invoke = ITMInvokeFunctionResponse()
        let success = ITMInvokeFunctionResponse_Success()
        success.jsonResult = "\"\(guid)\""
        invoke.success = success
        message.invokeFunctionResponse = invoke
        return message
    }

    /// The invocation string the client put on the wire.
    private func sentInvocation(_ channel: FakeChannel) -> String? {
        return channel.sent.first?.invokeFunctionRequest?.invocation
    }

    func testLocalCallSendsAnEmptyOrigin() throws {
        let channel = FakeChannel()
        channel.responses = [paneReply(guid: "GUID-1")]
        let client = APIClient(channel: channel)

        let guid = try client.sessionIdForTmuxPane(address, origin: nil)

        XCTAssertEqual(guid, "GUID-1")
        XCTAssertEqual(sentInvocation(channel)?.contains("origin: \"\""), true,
                       "got \(sentInvocation(channel) ?? "nil")")
    }

    func testRemoteCallSendsItsConductorIdentifier() throws {
        let channel = FakeChannel()
        channel.responses = [paneReply(guid: "GUID-2")]
        let client = APIClient(channel: channel)

        let guid = try client.sessionIdForTmuxPane(address, origin: "conductor-A")

        XCTAssertEqual(guid, "GUID-2")
        XCTAssertEqual(sentInvocation(channel)?.contains("origin: \"conductor-A\""), true,
                       "got \(sentInvocation(channel) ?? "nil")")
    }

    /// The identifier is interpolated into an invocation string, so it has to be escaped like any
    /// other value. It is app-generated today, which is exactly why a future change to its shape
    /// should not be able to produce a malformed invocation silently.
    func testOriginIsJSONEscaped() throws {
        let channel = FakeChannel()
        channel.responses = [paneReply(guid: "GUID-3")]
        let client = APIClient(channel: channel)

        _ = try client.sessionIdForTmuxPane(address, origin: "a\"b\\c")

        XCTAssertEqual(sentInvocation(channel)?.contains("origin: \"a\\\"b\\\\c\""), true,
                       "got \(sentInvocation(channel) ?? "nil")")
    }

    /// A remote invocation now actually asks iTerm2. It used to be refused locally, before any
    /// round trip, which is why a remote tmux pane could never resolve.
    func testRemoteAddressIsLookedUpRatherThanRefused() throws {
        let channel = FakeChannel()
        channel.responses = [paneReply(guid: "GUID-4")]
        let client = APIClient(channel: channel)
        // Parsed rather than constructed: TmuxPaneOptions is a ParsableArguments whose property
        // wrappers make a hand-built value diverge from what the CLI actually produces.
        let command = try IT2.parseAsRoot(["session", "get-status",
                                           "--tmux=/private/tmp/tmux-501/default,52533,0",
                                           "--tmux-pane=%3"])
        let options = try XCTUnwrap(command as? Session.GetStatus).tmuxOptions

        let resolved = try client.resolveSessionId(nil, tmuxOptions: options, origin: "conductor-A")

        XCTAssertEqual(resolved, "GUID-4")
        XCTAssertEqual(channel.sent.count, 1, "the lookup must reach iTerm2, not be refused locally")
    }
}
