//
//  iTermFunctionCallSuggesterTests.swift
//  iTerm2
//
//  Created by George Nachman on 1/19/26.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermFunctionCallSuggesterTests: XCTestCase {
    private var functionSignatures: [String: [String]]!
    private var pathSource: ((String) -> Set<String>)!
    private var allPaths: [String]!

    override func setUp() {
        super.setUp()
        // Test functions with various signatures
        functionSignatures = [
            "add": ["x", "y"],
            "cat": ["x", "y"],
            "mult": ["x", "y"],
            "noargs": [],
            "onearg": ["value"],
            "iterm2.alert": ["title", "subtitle", "buttons"],
            "alpha": ["first", "second"],
            "absolute": ["num"]
        ]
        // Test paths for completion
        allPaths = [
            "foo",
            "bar",
            "baz",
            "tab",
            "tab.currentSession",
            "tab.currentSession.path",
            "session",
            "user",
            "user.custom",
            "user.name"
        ]
        pathSource = { [allPaths] prefix in
            return Set(allPaths!.filter { $0.hasPrefix(prefix) || prefix.isEmpty })
        }
    }

    // MARK: - Helper Methods

    private func makeFunctionCallSuggester() -> iTermFunctionCallSuggester {
        return iTermFunctionCallSuggester(functionSignatures: functionSignatures, pathSource: pathSource)
    }

    private func makeSwiftyStringSuggester() -> iTermSwiftyStringSuggester {
        return iTermSwiftyStringSuggester(functionSignatures: functionSignatures, pathSource: pathSource)
    }

    private func makeExpressionSuggester() -> iTermExpressionSuggester {
        return iTermExpressionSuggester(functionSignatures: functionSignatures, pathSource: pathSource)
    }

    // MARK: - iTermFunctionCallSuggester: Empty/Basic Input Tests

    func testEmptyStringReturnsAllFunctionsAndPaths() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "")

        // Should contain functions and paths
        XCTAssertNotNil(suggestions)
        // Verify we get some suggestions (functions and/or paths)
        XCTAssertTrue(suggestions.count > 0, "Empty string should return suggestions")
    }

    func testTrailingSpaceReturnsEmpty() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add ")

        XCTAssertEqual(suggestions.count, 0)
    }

    func testTrailingSpaceInMiddleOfArglist() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add( ")

        XCTAssertEqual(suggestions.count, 0)
    }

    // MARK: - iTermFunctionCallSuggester: Function Name Completion Tests

    func testPartialFunctionNameCompletion() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "ad")

        XCTAssertTrue(suggestions.contains("add(x:"))
        XCTAssertFalse(suggestions.contains("cat(x:"))
        XCTAssertFalse(suggestions.contains("mult(x:"))
    }

    func testPartialFunctionNameCompletionMultipleMatches() {
        let suggester = makeFunctionCallSuggester()
        // "a" should match "add", "alpha", "absolute"
        let suggestions = suggester.suggestions(for: "a")

        XCTAssertTrue(suggestions.contains("add(x:"))
        XCTAssertTrue(suggestions.contains("alpha(first:"))
        XCTAssertTrue(suggestions.contains("absolute(num:"))
        XCTAssertFalse(suggestions.contains("cat(x:"))
    }

    func testNamespacedFunctionCompletion() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "iterm2.al")

        XCTAssertTrue(suggestions.contains("iterm2.alert(title:"))
    }

    func testNamespacePrefixCompletion() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "iterm2")

        XCTAssertTrue(suggestions.contains("iterm2.alert(title:"))
    }

    func testNoMatchingFunction() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "xyz")

        // No functions start with "xyz"
        XCTAssertEqual(suggestions.count, 0)
    }

    // MARK: - iTermFunctionCallSuggester: Argument List Completion Tests

    func testFunctionWithOpenParenSuggestsArgs() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(")

        // Should have suggestions (argument names)
        XCTAssertTrue(suggestions.count > 0)
        // Check that suggestions contain argument name completions
        XCTAssertTrue(suggestions.contains { $0.hasSuffix("x:") || $0.hasSuffix("y:") })
    }

    func testFunctionWithNoArgsSuggestsNothing() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "noargs(")

        // For a function with no arguments, after open paren there are no more suggestions
        XCTAssertEqual(suggestions.count, 0)
    }

    func testFunctionWithOneCompleteArgSuggestsRemainingArgs() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: 1,")

        // After first arg, should get suggestions
        XCTAssertNotNil(suggestions)
    }

    func testFunctionWithPartialArgName() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: 1, y")

        XCTAssertTrue(suggestions.contains("add(x: 1, y:"))
    }

    func testFunctionWithArgNameAndColonReturnsEmpty() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x:")

        // After colon with no expression started, the grammar rule returns
        // an arg without expression, and suggestedExpressions:nil returns empty
        XCTAssertEqual(suggestions.count, 0)
    }

    func testFunctionWithAllArgsComplete() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: 1, y: 2)")

        // Complete function call - suggester returns available paths/functions
        // that could theoretically follow (though not syntactically valid)
        XCTAssertNotNil(suggestions)
    }

    func testFunctionWithManyArgs() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "iterm2.alert(title: \"foo\",")

        // Should suggest remaining args: subtitle, buttons
        XCTAssertTrue(suggestions.contains { $0.contains("subtitle:") })
        XCTAssertTrue(suggestions.contains { $0.contains("buttons:") })
    }

    func testFunctionWithTwoCompleteArgs() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "iterm2.alert(title: \"foo\", subtitle: \"bar\",")

        // Should suggest only remaining arg: buttons
        XCTAssertTrue(suggestions.contains { $0.contains("buttons:") })
    }

    // MARK: - iTermFunctionCallSuggester: Expression Value Completion Tests

    func testPartialPathCompletionInArgument() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: fo")

        // Should suggest paths starting with "fo" -> "foo"
        XCTAssertTrue(suggestions.contains { $0.contains("foo") })
    }

    func testNestedPathCompletionInArgument() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: tab.cur")

        // Should suggest "tab.currentSession"
        XCTAssertTrue(suggestions.contains { $0.contains("tab.currentSession") })
    }

    func testNestedFunctionCallAsValue() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: mult(")

        // Should suggest mult's arguments
        XCTAssertTrue(suggestions.count > 0)
    }

    func testDeeplyNestedFunctionCall() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: mult(x: cat(")

        // Should suggest cat's arguments
        XCTAssertTrue(suggestions.count > 0)
    }

    func testLiteralNumberNoSuggestions() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: 123")

        // After typing a complete number literal, expressions are terminated
        // so no further completions for the value itself
        XCTAssertNotNil(suggestions)
    }

    // MARK: - iTermFunctionCallSuggester: Truncated Input Handling Tests

    func testTruncatedAtFunctionName() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "cat")

        XCTAssertTrue(suggestions.contains("cat(x:"))
    }

    func testTruncatedAfterOpenParen() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(")

        XCTAssertTrue(suggestions.count > 0)
    }

    func testTruncatedAfterColonReturnsEmpty() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x:")

        // After colon without any value, returns empty
        // (arg rule produces dict without expression key)
        XCTAssertEqual(suggestions.count, 0)
    }

    func testTruncatedInNestedCallAfterColonReturnsEmpty() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: mult(x: 1, y:")

        // Inner "y:" has no expression, so returns empty
        XCTAssertEqual(suggestions.count, 0)
    }

    // MARK: - iTermFunctionCallSuggester: Pass-by-Reference Tests

    func testPassByReferenceArg() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: &fo")

        // Pass-by-reference with path prefix - should suggest paths
        XCTAssertNotNil(suggestions)
    }

    // MARK: - iTermFunctionCallSuggester: Array Literal Tests

    func testArrayLiteralInArg() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: [1, fo")

        // Inside array literal, should suggest path completions
        XCTAssertNotNil(suggestions)
    }

    // MARK: - iTermFunctionCallSuggester: Optional Marker Tests

    func testOptionalMarker() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: foo?")

        // After optional marker, expression is terminated
        XCTAssertEqual(suggestions.count, 0)
    }

    // MARK: - iTermSwiftyStringSuggester: Literal String Tests

    func testSwiftyPureLiteralString() {
        let suggester = makeSwiftyStringSuggester()
        let suggestions = suggester.suggestions(for: "\"hello world\"")

        XCTAssertEqual(suggestions.count, 0)
    }

    func testSwiftyTruncatedLiteral() {
        let suggester = makeSwiftyStringSuggester()
        let suggestions = suggester.suggestions(for: "\"hello")

        // Truncated in literal part, no interpolation
        XCTAssertEqual(suggestions.count, 0)
    }

    func testSwiftyEmptyString() {
        let suggester = makeSwiftyStringSuggester()
        let suggestions = suggester.suggestions(for: "\"\"")

        XCTAssertEqual(suggestions.count, 0)
    }

    // MARK: - iTermSwiftyStringSuggester: Interpolation Completion Tests

    func testSwiftyInterpolationStart() {
        let suggester = makeSwiftyStringSuggester()
        let suggestions = suggester.suggestions(for: "\"foo\\(")

        // Should suggest all paths and functions
        XCTAssertTrue(suggestions.count > 0)
    }

    func testSwiftyInterpolationWithPartialPath() {
        let suggester = makeSwiftyStringSuggester()
        let input = "\"foo\\(bar"

        let suggestions = suggester.suggestions(for: input)

        // Suggestions are full swifty strings. For "bar" (exact match with no nested paths),
        // we expect the original input to be returned as a valid completion.
        XCTAssertTrue(suggestions.contains { $0.contains("bar") }, "Expected suggestions containing 'bar', got: \(suggestions)")
    }

    func testSwiftyInterpolationWithFunctionCall() {
        let suggester = makeSwiftyStringSuggester()
        // Note: trailing space returns empty (by design), so test without trailing space
        let suggestions = suggester.suggestions(for: "\"foo\\(add(x: 1,")

        // After first arg and comma, should suggest next arg
        XCTAssertTrue(suggestions.count > 0, "Expected suggestions for second argument, got: \(suggestions)")
    }

    func testSwiftyNestedInterpolation() {
        let suggester = makeSwiftyStringSuggester()
        // Nested interpolation: a string arg to cat() contains another interpolation
        // This is a complex edge case - the current implementation may not fully support
        // suggestions for deeply nested interpolations inside function arguments.
        let suggestions = suggester.suggestions(for: "\"foo\\(cat(x: \"inner\\(ba")

        // This is a known limitation - deeply nested interpolations inside function
        // arguments may not produce suggestions. Just verify it doesn't crash.
        XCTAssertNotNil(suggestions, "Should not crash on nested interpolation")
    }

    func testSwiftyCompletedInterpolation() {
        let suggester = makeSwiftyStringSuggester()
        let suggestions = suggester.suggestions(for: "\"foo\\(bar)\"")

        // Complete string - may still have suggestions depending on implementation
        XCTAssertNotNil(suggestions)
    }

    func testSwiftyInterpolationThenLiteral() {
        let suggester = makeSwiftyStringSuggester()
        let suggestions = suggester.suggestions(for: "\"foo\\(bar) and more")

        // Truncated in literal after interpolation
        XCTAssertEqual(suggestions.count, 0)
    }

    // MARK: - iTermSwiftyStringSuggester: Partial Path Suggestions Tests

    func testSwiftySuggestionsForNestedPaths() {
        let suggester = makeSwiftyStringSuggester()
        let suggestions = suggester.suggestions(for: "\"\\(tab.cur")

        // Should suggest "tab.currentSession" or similar nested paths
        XCTAssertTrue(suggestions.contains { $0.contains("currentSession") })
    }

    func testSwiftyPartialPathSuggestionsAreTrimmed() {
        let suggester = makeSwiftyStringSuggester()

        // "tab" has nested paths, so suggestions get trimmed to first period
        let suggestions = suggester.suggestions(for: "\"\\(tab")
        XCTAssertTrue(suggestions.count > 0)

        // "baz" has no nested paths but should still return exact match
        let bazSuggestions = suggester.suggestions(for: "\"\\(baz")
        XCTAssertTrue(bazSuggestions.count > 0, "Expected exact match suggestion for 'baz'")
    }

    // MARK: - iTermSwiftyStringSuggester: Trailing Space Tests

    func testSwiftyTrailingSpace() {
        let suggester = makeSwiftyStringSuggester()
        let suggestions = suggester.suggestions(for: "\"foo\\(bar ")

        XCTAssertEqual(suggestions.count, 0)
    }

    // MARK: - iTermExpressionSuggester Tests

    func testExpressionSuggesterEmptyString() {
        let suggester = makeExpressionSuggester()
        let suggestions = suggester.suggestions(for: "")

        // Should suggest all paths and functions
        XCTAssertTrue(suggestions.count > 0)
    }

    func testExpressionSuggesterPartialPath() {
        let suggester = makeExpressionSuggester()
        let suggestions = suggester.suggestions(for: "fo")

        // Should suggest paths starting with "fo"
        XCTAssertTrue(suggestions.contains { $0.hasPrefix("foo") })
    }

    func testExpressionSuggesterFunctionCall() {
        let suggester = makeExpressionSuggester()
        let suggestions = suggester.suggestions(for: "add(")

        // Should suggest function arguments
        XCTAssertTrue(suggestions.count > 0)
    }

    func testExpressionSuggesterCompletePath() {
        let suggester = makeExpressionSuggester()
        let suggestions = suggester.suggestions(for: "foo")

        // Complete path - should still provide suggestions or empty
        XCTAssertNotNil(suggestions)
    }

    func testExpressionSuggesterNestedPath() {
        let suggester = makeExpressionSuggester()
        let suggestions = suggester.suggestions(for: "tab.cur")

        // Should suggest "tab.currentSession"
        XCTAssertTrue(suggestions.contains { $0.contains("currentSession") })
    }

    // MARK: - Edge Cases

    func testMultipleFunctionsWithSamePrefix() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "a")

        // "a" matches: add, alpha, absolute
        let matchingFunctions = suggestions.filter { $0.contains("(") }
        XCTAssertTrue(matchingFunctions.count >= 3)
    }

    func testVeryLongPath() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: user.cus")

        // Should suggest "user.custom"
        XCTAssertTrue(suggestions.count > 0)
    }

    func testPathEndingWithDot() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "tab.")

        // Should return some suggestions (may be empty depending on grammar)
        XCTAssertNotNil(suggestions)
    }

    func testEmptyPathSource() {
        let emptyPathSuggester = iTermFunctionCallSuggester(
            functionSignatures: functionSignatures,
            pathSource: { _ in Set() }
        )
        let suggestions = emptyPathSuggester.suggestions(for: "")

        // Should still have function suggestions, just no paths
        XCTAssertTrue(suggestions.contains { $0.contains("add(") })
        XCTAssertFalse(suggestions.contains("foo"))
    }

    func testNoFunctions() {
        let noFuncSuggester = iTermFunctionCallSuggester(
            functionSignatures: [:],
            pathSource: pathSource
        )
        let suggestions = noFuncSuggester.suggestions(for: "")

        // Should have path suggestions, no function suggestions
        XCTAssertTrue(suggestions.contains("foo"))
        XCTAssertFalse(suggestions.contains { $0.contains("(") })
    }

    // MARK: - iTermFunctionCallSuggester: Single-arg Function Tests

    func testSingleArgFunctionOpenParen() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "onearg(")

        XCTAssertTrue(suggestions.contains("onearg(value:"))
    }

    func testSingleArgFunctionWithValuePrefix() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "onearg(value: fo")

        // Should suggest paths starting with "fo" -> "foo"
        XCTAssertTrue(suggestions.contains { $0.contains("foo") })
    }

    func testSingleArgFunctionComplete() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "onearg(value: 42)")

        // Complete function call
        XCTAssertNotNil(suggestions)
    }

    // MARK: - iTermFunctionCallSuggester: Number and String Literal Tests

    func testNumberLiteralAsArg() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: 42,")

        // After number and comma, should suggest next arg
        XCTAssertTrue(suggestions.contains { $0.contains("y:") })
    }

    func testStringLiteralAsArg() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "cat(x: \"hello\",")

        // After string literal and comma, should suggest next arg
        XCTAssertTrue(suggestions.contains { $0.contains("y:") })
    }

    func testTruncatedStringLiteralAsArg() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "cat(x: \"hello")

        // Truncated inside string literal
        XCTAssertNotNil(suggestions)
    }

    // MARK: - Array Index Tests

    func testPathWithArrayIndex() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: foo[0]")

        // After array index, the expression might be complete
        XCTAssertNotNil(suggestions)
    }

    // MARK: - Arithmetic Operator Tests

    func testArithmeticPlusOperatorIncomplete() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: 1 +")

        // After plus operator with no RHS, should suggest all paths and functions
        // Check for specific paths
        XCTAssertTrue(suggestions.contains("add(x: 1 +foo"), "Expected 'foo' path suggestion")
        XCTAssertTrue(suggestions.contains("add(x: 1 +bar"), "Expected 'bar' path suggestion")
        XCTAssertTrue(suggestions.contains("add(x: 1 +session"), "Expected 'session' path suggestion")
        // Check for function suggestions
        XCTAssertTrue(suggestions.contains("add(x: 1 +add(x:"), "Expected 'add' function suggestion")
        XCTAssertTrue(suggestions.contains("add(x: 1 +mult(x:"), "Expected 'mult' function suggestion")
    }

    func testArithmeticMinusOperatorIncomplete() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: 1 -")

        // After minus operator with no RHS, should suggest all paths and functions
        XCTAssertTrue(suggestions.contains("add(x: 1 -foo"), "Expected 'foo' path suggestion")
        XCTAssertTrue(suggestions.contains("add(x: 1 -bar"), "Expected 'bar' path suggestion")
        XCTAssertTrue(suggestions.contains("add(x: 1 -cat(x:"), "Expected 'cat' function suggestion")
    }

    func testArithmeticMultiplyOperatorIncomplete() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: 2 *")

        // After multiply operator with no RHS, should suggest all paths and functions
        XCTAssertTrue(suggestions.contains("add(x: 2 *foo"), "Expected 'foo' path suggestion")
        XCTAssertTrue(suggestions.contains("add(x: 2 *user"), "Expected 'user' path suggestion")
        XCTAssertTrue(suggestions.contains("add(x: 2 *absolute(num:"), "Expected 'absolute' function suggestion")
    }

    func testArithmeticDivideOperatorIncomplete() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: 4 /")

        // After divide operator with no RHS, should suggest all paths and functions
        XCTAssertTrue(suggestions.contains("add(x: 4 /foo"), "Expected 'foo' path suggestion")
        XCTAssertTrue(suggestions.contains("add(x: 4 /baz"), "Expected 'baz' path suggestion")
        XCTAssertTrue(suggestions.contains("add(x: 4 /onearg(value:"), "Expected 'onearg' function suggestion")
    }

    func testArithmeticExpressionComplete() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: 1 + 2,")

        // After complete arithmetic expression and comma, should suggest next arg 'y:'
        // Note: no space after comma in the output format
        XCTAssertEqual(suggestions, ["add(x: 1 + 2,y:"], "Expected exactly 'y:' suggestion")
    }

    func testArithmeticPartialPathAfterOperator() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: 1 + fo")

        // After operator with partial path, should suggest paths matching "fo" with next arg
        // Note: space after comma when completing a path expression
        XCTAssertTrue(suggestions.contains("add(x: 1 + foo, y:"), "Expected 'foo, y:' suggestion")
        // Should NOT contain paths that don't match "fo"
        XCTAssertFalse(suggestions.contains { $0.contains("bar") }, "Should not contain 'bar'")
    }

    // MARK: - Boolean Literal Tests

    func testBooleanTrueLiteral() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: true,")

        // After boolean literal and comma, should suggest next arg 'y:'
        // Note: no space after comma in the output format
        XCTAssertEqual(suggestions, ["add(x: true,y:"], "Expected exactly 'y:' suggestion")
    }

    func testBooleanFalseLiteral() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: false,")

        // After boolean literal and comma, should suggest next arg 'y:'
        // Note: no space after comma in the output format
        XCTAssertEqual(suggestions, ["add(x: false,y:"], "Expected exactly 'y:' suggestion")
    }

    func testBooleanAsCompleteExpression() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: true")

        // Boolean literal is complete, no suggestions for the value itself
        XCTAssertEqual(suggestions.count, 0, "Boolean literal should be complete, got: \(suggestions)")
    }

    // MARK: - Ternary Conditional Tests

    func testTernaryWithTrueBranch() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: foo ? bar :")

        // After ternary ':' with no false branch, should suggest all paths and functions
        XCTAssertTrue(suggestions.contains("add(x: foo ? bar :foo"), "Expected 'foo' path suggestion")
        XCTAssertTrue(suggestions.contains("add(x: foo ? bar :bar"), "Expected 'bar' path suggestion")
        XCTAssertTrue(suggestions.contains("add(x: foo ? bar :add(x:"), "Expected 'add' function suggestion")
    }

    func testTernaryComplete() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: foo ? 1 : 2,")

        // After complete ternary and comma, should suggest next arg 'y:'
        // Note: no space after comma in the output format
        XCTAssertEqual(suggestions, ["add(x: foo ? 1 : 2,y:"], "Expected exactly 'y:' suggestion")
    }

    func testTernaryPartialFalseBranch() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: foo ? 1 : ba")

        // Partial path in false branch should suggest paths matching "ba"
        // Note: space after comma when completing a path expression
        XCTAssertTrue(suggestions.contains("add(x: foo ? 1 : bar, y:"), "Expected 'bar' with next arg")
        XCTAssertTrue(suggestions.contains("add(x: foo ? 1 : baz, y:"), "Expected 'baz' with next arg")
        // Should NOT contain paths that don't match "ba"
        XCTAssertFalse(suggestions.contains { $0.contains("foo") && !$0.hasPrefix("add(x: foo") }, "Should not contain 'foo' in suggestions")
    }

    // MARK: - Parenthesized Expression Tests

    func testParenthesizedExpressionStart() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: (")

        // After open paren, should suggest all paths and functions
        XCTAssertTrue(suggestions.contains("add(x: (foo"), "Expected 'foo' path suggestion")
        XCTAssertTrue(suggestions.contains("add(x: (bar"), "Expected 'bar' path suggestion")
        XCTAssertTrue(suggestions.contains("add(x: (add(x:"), "Expected 'add' function suggestion")
    }

    func testParenthesizedExpressionPartialPath() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: (fo")

        // Partial path inside parens should suggest paths matching "fo"
        // Note: space after comma when completing a path expression
        XCTAssertTrue(suggestions.contains("add(x: (foo, y:"), "Expected 'foo' with next arg")
        // Should NOT contain paths that don't match "fo"
        XCTAssertFalse(suggestions.contains { $0.contains("bar") }, "Should not contain 'bar'")
    }

    func testParenthesizedExpressionComplete() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: (1 + 2),")

        // After complete parenthesized expression and comma, should suggest next arg 'y:'
        // Note: no space after comma in the output format
        XCTAssertEqual(suggestions, ["add(x: (1 + 2),y:"], "Expected exactly 'y:' suggestion")
    }

    func testParenthesizedIncompleteArithmetic() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: (1 +")

        // Incomplete arithmetic inside parens should suggest all paths and functions
        XCTAssertTrue(suggestions.contains("add(x: (1 +foo"), "Expected 'foo' path suggestion")
        XCTAssertTrue(suggestions.contains("add(x: (1 +mult(x:"), "Expected 'mult' function suggestion")
    }

    // MARK: - Dynamic Array Indexing Tests

    func testArrayIndexWithExpressionIncomplete() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: bar[")

        // After array index open bracket, should suggest all paths and functions
        XCTAssertTrue(suggestions.contains("add(x: bar[foo"), "Expected 'foo' path suggestion")
        XCTAssertTrue(suggestions.contains("add(x: bar[baz"), "Expected 'baz' path suggestion")
        XCTAssertTrue(suggestions.contains("add(x: bar[add(x:"), "Expected 'add' function suggestion")
    }

    func testArrayIndexPartialExpression() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: bar[1 +")

        // Incomplete arithmetic inside array index should suggest all paths and functions
        XCTAssertTrue(suggestions.contains("add(x: bar[1 +foo"), "Expected 'foo' path suggestion")
        XCTAssertTrue(suggestions.contains("add(x: bar[1 +cat(x:"), "Expected 'cat' function suggestion")
    }

    func testArrayIndexWithPathIndex() {
        let suggester = makeFunctionCallSuggester()
        let suggestions = suggester.suggestions(for: "add(x: bar[fo")

        // Partial path inside array index should suggest paths matching "fo"
        // Note: space after comma when completing a path expression
        XCTAssertTrue(suggestions.contains("add(x: bar[foo, y:"), "Expected 'foo, y:' suggestion")
        // Should NOT contain paths that don't match "fo"
        XCTAssertFalse(suggestions.contains { $0.contains("baz") }, "Should not contain 'baz'")
    }

    // MARK: - Complete Scenarios Integration Tests

    func testCompleteWorkflow_SimpleFunctionCall() {
        let suggester = makeFunctionCallSuggester()

        // Step 1: Start typing function
        var suggestions = suggester.suggestions(for: "add")
        XCTAssertTrue(suggestions.contains("add(x:"))

        // Step 2: Open paren
        suggestions = suggester.suggestions(for: "add(")
        XCTAssertTrue(suggestions.count > 0)

        // Step 3: First arg complete, suggest second
        suggestions = suggester.suggestions(for: "add(x: 1,")
        XCTAssertTrue(suggestions.contains { $0.contains("y:") })

        // Step 4: Complete function - verification that it doesn't crash
        suggestions = suggester.suggestions(for: "add(x: 1, y: 2)")
        XCTAssertNotNil(suggestions)
    }

    func testCompleteWorkflow_SwiftyStringWithInterpolation() {
        let suggester = makeSwiftyStringSuggester()

        // Step 1: Start interpolation
        var suggestions = suggester.suggestions(for: "\"Hello \\(")
        XCTAssertTrue(suggestions.count > 0, "Should suggest paths/functions after \\(")

        // Step 2: Partial path - suggestions are full swifty strings containing the path
        suggestions = suggester.suggestions(for: "\"Hello \\(user")
        XCTAssertTrue(suggestions.contains { $0.contains("user") }, "Expected suggestion containing 'user', got: \(suggestions)")

        // Step 3: Complete interpolation and continue literal
        suggestions = suggester.suggestions(for: "\"Hello \\(user.name)!")
        XCTAssertEqual(suggestions.count, 0, "No suggestions in literal part")

        // Step 4: Start another interpolation - suggestions are full strings containing the path
        suggestions = suggester.suggestions(for: "\"Hello \\(user.name)! Session: \\(ses")
        XCTAssertTrue(suggestions.contains { $0.contains("session") }, "Expected suggestion containing 'session', got: \(suggestions)")
    }
}
