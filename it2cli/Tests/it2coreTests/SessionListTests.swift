import XCTest
import ProtobufRuntime
@testable import it2core

/// Integration-style test: drives the real `session list` command logic with a
/// fake channel and a capturing context, asserting both the requests it builds
/// and the text it formats.
final class SessionListTests: XCTestCase {
    private func listResponse(id: Int64, sessionId: String, title: String) -> ITMServerOriginatedMessage {
        return listResponse(id: id, sessionIds: [sessionId], title: title)
    }

    private func listResponse(id: Int64, sessionIds: [String], title: String) -> ITMServerOriginatedMessage {
        let root = ITMSplitTreeNode()
        for sessionId in sessionIds {
            let summary = ITMSessionSummary()
            summary.uniqueIdentifier = sessionId
            summary.title = title
            // No gridSize -> hasGridSize is false -> reported as 0x0.

            let link = ITMSplitTreeNode_SplitTreeLink()
            link.session = summary
            root.linksArray.add(link)
        }

        let tab = ITMListSessionsResponse_Tab()
        tab.tabId = "tab-1"
        tab.root = root

        let window = ITMListSessionsResponse_Window()
        window.windowId = "win-1"
        window.tabsArray.add(tab)

        let listResp = ITMListSessionsResponse()
        listResp.windowsArray.add(window)

        let message = ITMServerOriginatedMessage()
        message.id_p = id
        message.listSessionsResponse = listResp
        return message
    }

    private func variableResponse(id: Int64, name: String, tty: String) -> ITMServerOriginatedMessage {
        let vr = ITMVariableResponse()
        vr.status = .ok
        vr.valuesArray.add("\"\(name)\"") // values arrive JSON-quoted; the command trims quotes
        vr.valuesArray.add("\"\(tty)\"")

        let message = ITMServerOriginatedMessage()
        message.id_p = id
        message.variableResponse = vr
        return message
    }

    private func invokeResponse(id: Int64, jsonResult: String) -> ITMServerOriginatedMessage {
        let success = ITMInvokeFunctionResponse_Success()
        success.jsonResult = jsonResult
        let invoke = ITMInvokeFunctionResponse()
        invoke.success = success

        let message = ITMServerOriginatedMessage()
        message.id_p = id
        message.invokeFunctionResponse = invoke
        return message
    }

    private func invokeError(id: Int64, reason: String) -> ITMServerOriginatedMessage {
        let error = ITMInvokeFunctionResponse_Error()
        error.status = .failed
        error.errorReason = reason
        let invoke = ITMInvokeFunctionResponse()
        invoke.error = error

        let message = ITMServerOriginatedMessage()
        message.id_p = id
        message.invokeFunctionResponse = invoke
        return message
    }

    func testSessionListTabularOutput() throws {
        let channel = FakeChannel()
        channel.responses = [
            listResponse(id: 1, sessionId: "sess-1", title: "My Title"),
            variableResponse(id: 2, name: "myname", tty: "/dev/ttys001"),
        ]
        let capture = OutputCapture()

        var command = try Session.List.parse([])
        try command.run(capture.context(channel: channel))

        XCTAssertEqual(capture.out, ["sess-1\tmyname\tMy Title\t0x0\t/dev/ttys001"])

        // The command should issue exactly a ListSessions request then a Variable request.
        XCTAssertEqual(channel.sent.count, 2)
        XCTAssertEqual(channel.sent.first?.submessageOneOfCase, .listSessionsRequest)
        XCTAssertEqual(channel.sent.last?.submessageOneOfCase, .variableRequest)
        XCTAssertTrue(channel.disconnected, "run() should disconnect the client")
    }

    // --format replaces the columns with the interpolated string, evaluated in the
    // session's context, and skips the variable request the columns need. A probe
    // in the app context first checks that iterm2.interpolate exists.
    func testSessionListFormat() throws {
        let channel = FakeChannel()
        channel.responses = [
            listResponse(id: 1, sessionId: "sess-1", title: "My Title"),
            invokeResponse(id: 2, jsonResult: "\"\""),
            invokeResponse(id: 3, jsonResult: "\"\\/tmp\\/a b\\tvim\""),
        ]
        let capture = OutputCapture()

        let command = try Session.List.parse(["--format", "\\(session.path)\\t\\(session.jobName)"])
        try command.run(capture.context(channel: channel))

        XCTAssertEqual(capture.out, ["/tmp/a b\tvim"])
        XCTAssertEqual(capture.err, [])
        XCTAssertEqual(channel.sent.count, 3)
        let probe = channel.sent[1].invokeFunctionRequest
        XCTAssertEqual(probe?.invocation, "iterm2.interpolate(string: \"\")")
        XCTAssertNotNil(probe?.app)
        let invoke = channel.sent[2].invokeFunctionRequest
        XCTAssertEqual(invoke?.invocation,
                       "iterm2.interpolate(string: \"\\(session.path)\\t\\(session.jobName)\")")
        XCTAssertEqual(invoke?.session?.sessionId, "sess-1")
    }

    func testSessionListFormatWithJSON() throws {
        let channel = FakeChannel()
        channel.responses = [
            listResponse(id: 1, sessionId: "sess-1", title: "My Title"),
            invokeResponse(id: 2, jsonResult: "\"\""),
            invokeResponse(id: 3, jsonResult: "\"/tmp\""),
            variableResponse(id: 4, name: "myname", tty: "/dev/ttys001"),
        ]
        let capture = OutputCapture()

        let command = try Session.List.parse(["--json", "--format", "\\(session.path)"])
        try command.run(capture.context(channel: channel))

        let data = try XCTUnwrap(capture.out.joined(separator: "\n").data(using: .utf8))
        let sessions = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?["formatted"] as? String, "/tmp")
        XCTAssertEqual(sessions.first?["name"] as? String, "myname")
    }

    // An iTerm2 too old to have iterm2.interpolate fails the probe, so the listing
    // stops with that reason before evaluating anything.
    func testSessionListFormatUnsupported() throws {
        let channel = FakeChannel()
        channel.responses = [
            listResponse(id: 1, sessionId: "sess-1", title: "My Title"),
            invokeError(id: 2, reason: "No function registered for invocation"),
        ]
        let capture = OutputCapture()

        let command = try Session.List.parse(["--format", "\\(session.path)"])
        XCTAssertThrowsError(try command.run(capture.context(channel: channel))) { error in
            XCTAssertTrue("\(error)".contains("doesn’t support --format"), "\(error)")
        }
        XCTAssertEqual(channel.sent.count, 2)
        XCTAssertEqual(capture.out, [])
    }

    // A session that fails (for example, one that closed during the listing) gets
    // an empty line, like an undefined variable, and the others still print.
    func testSessionListFormatOneSessionFails() throws {
        let channel = FakeChannel()
        channel.responses = [
            listResponse(id: 1, sessionIds: ["sess-1", "sess-2"], title: "My Title"),
            invokeResponse(id: 2, jsonResult: "\"\""),
            invokeResponse(id: 3, jsonResult: "\"/tmp\""),
            invokeError(id: 4, reason: "No such session"),
        ]
        let capture = OutputCapture()

        let command = try Session.List.parse(["--format", "\\(session.path)"])
        try command.run(capture.context(channel: channel))

        XCTAssertEqual(capture.out, ["/tmp", ""])
        XCTAssertEqual(capture.err.count, 1)
        XCTAssertTrue(capture.err.first?.contains("No such session") ?? false, "\(capture.err)")
        XCTAssertTrue(capture.err.first?.contains("sess-2") ?? false, "\(capture.err)")
    }

    // A transport failure partway through (iTerm2 quitting, say) is not one
    // session's failure: it must end the listing rather than blank the sessions
    // after it and exit 0 with output that looks complete.
    func testSessionListFormatConnectionDropsMidListing() throws {
        let channel = FakeChannel()
        channel.responses = [
            listResponse(id: 1, sessionIds: ["sess-1", "sess-2", "sess-3"], title: "My Title"),
            invokeResponse(id: 2, jsonResult: "\"\""),
            invokeResponse(id: 3, jsonResult: "\"/tmp\""),
            // Nothing more: the channel throws on the next receive.
        ]
        let capture = OutputCapture()

        let command = try Session.List.parse(["--format", "\\(session.path)"])
        XCTAssertThrowsError(try command.run(capture.context(channel: channel)))
        XCTAssertEqual(capture.out, [])
        XCTAssertEqual(capture.err, [])
    }

    // When every session fails the format itself is broken, so the listing fails
    // without printing anything.
    func testSessionListFormatAllSessionsFail() throws {
        let channel = FakeChannel()
        channel.responses = [
            listResponse(id: 1, sessionIds: ["sess-1", "sess-2"], title: "My Title"),
            invokeResponse(id: 2, jsonResult: "\"\""),
            invokeError(id: 3, reason: "Syntax error"),
            invokeError(id: 4, reason: "Syntax error"),
        ]
        let capture = OutputCapture()

        let command = try Session.List.parse(["--format", "\\(session.path"])
        XCTAssertThrowsError(try command.run(capture.context(channel: channel))) { error in
            XCTAssertTrue("\(error)".contains("Syntax error"), "\(error)")
        }
        XCTAssertEqual(capture.out, [])
        XCTAssertEqual(capture.err, [])
    }

    // MARK: - swiftyStringLiteral

    func testSwiftyStringLiteralPlain() {
        XCTAssertEqual(swiftyStringLiteral("abc"), "\"abc\"")
    }

    func testSwiftyStringLiteralEscapesBareQuote() {
        XCTAssertEqual(swiftyStringLiteral("say \"hi\""), "\"say \\\"hi\\\"\"")
    }

    func testSwiftyStringLiteralKeepsExistingEscapes() {
        XCTAssertEqual(swiftyStringLiteral("a\\tb\\\"c"), "\"a\\tb\\\"c\"")
    }

    func testSwiftyStringLiteralEscapesTrailingBackslash() {
        XCTAssertEqual(swiftyStringLiteral("a\\"), "\"a\\\\\"")
    }

    func testSwiftyStringLiteralLeavesQuotesInExpressions() {
        let body = "\\(f(x: \"a)\")) \"\\(g(y: \"\\(h(z: \"q\"))\"))"
        let expected = "\"\\(f(x: \"a)\")) \\\"\\(g(y: \"\\(h(z: \"q\"))\"))\""
        XCTAssertEqual(swiftyStringLiteral(body), expected)
    }
}
