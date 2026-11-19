//
//  EscapeHTMLBuiltInFunctionTests.swift
//  ModernTests
//
//  iterm2.escape_html(string:) makes a value safe to put in lightweight HTML,
//  such as a rich tab content line, so text like a job name can't be read as
//  markup.
//

import XCTest
@testable import iTerm2SharedARC

final class EscapeHTMLBuiltInFunctionTests: XCTestCase, iTermObject {
    private var scope: iTermVariableScope!
    private var variables: iTermVariables!

    override func setUp() {
        super.setUp()
        scope = iTermVariableScope()
        variables = iTermVariables(context: [], owner: self)
        scope.add(variables, toScopeNamed: nil)
        scope.setValue("<b>vim</b> & \"more\" 'stuff'", forVariableNamed: "jobName")
    }

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { scope }

    private func call(_ invocation: String) -> (Any?, Error?) {
        let expectation = XCTestExpectation(description: invocation)
        var output: Any?
        var outputError: Error?
        iTermScriptFunctionCall.callFunction(invocation,
                                             timeout: 1,
                                             sideEffectsAllowed: false,
                                             scope: scope,
                                             retainSelf: true) { value, error, _ in
            output = value
            outputError = error
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
        return (output, outputError)
    }

    func testEscapesMarkupCharacters() {
        let (value, error) = call("iterm2.escape_html(string: jobName)")
        XCTAssertNil(error)
        XCTAssertEqual(value as? String, "&lt;b&gt;vim&lt;/b&gt; &amp; &quot;more&quot; &#39;stuff&#39;")
    }

    // A value that isn't set, passed as name?, is empty rather than an error,
    // so a tab line shows nothing for it, as plain interpolation does.
    func testUnsetValueIsEmpty() {
        let (value, error) = call("iterm2.escape_html(string: notSet?)")
        XCTAssertNil(error)
        XCTAssertEqual(value as? String, "")
    }

    // Like plain interpolation, a number is shown as text.
    func testNumber() {
        let (value, error) = call("iterm2.escape_html(string: 3)")
        XCTAssertNil(error)
        XCTAssertEqual(value as? String, "3")
    }

    func testArray() {
        scope.setValue(["a", "<b>", NSNull()], forVariableNamed: "items")
        let (value, error) = call("iterm2.escape_html(string: items)")
        XCTAssertNil(error)
        XCTAssertEqual(value as? String, "[a, &lt;b&gt;, ]")
    }

    func testUnescapeUndoesEscape() {
        let raw = "&lt; <b> & \"q\" 'a'"
        XCTAssertEqual(EscapeHTMLBuiltInFunction.unescape(EscapeHTMLBuiltInFunction.escape(raw)), raw)
    }

    func testLeavesPlainTextAlone() {
        let (value, error) = call("iterm2.escape_html(string: \"claude ✻ Working\")")
        XCTAssertNil(error)
        XCTAssertEqual(value as? String, "claude ✻ Working")
    }

    func testEscapingRoundTripsThroughTheTabTitleParser() {
        let raw = "<b>vim</b> & \"more\" 'stuff'"
        let escaped = EscapeHTMLBuiltInFunction.escape(raw)
        let parsed = NSAttributedString.fromLightweightHTML(escaped, attributes: [:])
        XCTAssertEqual(parsed.string, raw)
    }
}
