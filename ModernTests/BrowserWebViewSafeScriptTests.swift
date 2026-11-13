//
//  BrowserWebViewSafeScriptTests.swift
//  ModernTests
//

import JavaScriptCore
import XCTest
@testable import iTerm2SharedARC

// safelyEvaluateJavaScript wraps each script as `return <script>`. A script that began with a
// comment line became `return // comment`, which automatic semicolon insertion turns into a bare
// `return`, so the script silently never ran. That broke Reader Mode and Remove Distractions.
final class BrowserWebViewSafeScriptTests: XCTestCase {
    private func evaluate(_ script: String) -> JSValue? {
        let context = JSContext()!
        return context.evaluateScript(iTermBrowserWebView.makeSafe(script))
    }

    func testScriptStartingWithLineCommentRuns() {
        let result = evaluate("// Explain the script\n(function() { return 42; })();")
        XCTAssertEqual(result?.toInt32(), 42)
    }

    func testScriptStartingWithBlockAndLineCommentsRuns() {
        let result = evaluate("/*\n * License\n */\n\n  // More\n(function() { return 'ran'; })();")
        XCTAssertEqual(result?.toString(), "ran")
    }

    func testScriptWithoutLeadingCommentIsUnchanged() {
        XCTAssertEqual(evaluate("1 + 1")?.toInt32(), 2)
    }

    func testUndefinedResultBecomesNull() {
        XCTAssertTrue(evaluate("// nothing\n(function() {})()")?.isNull ?? false)
    }

    func testCommentMarkersLaterInTheScriptAreLeftAlone() {
        XCTAssertEqual(evaluate("// c\n(function() { return '//x' + '/*y*/'; })()")?.toString(), "//x/*y*/")
    }
}
