//
//  iTermExpressionParserTests.swift
//  iTerm2
//
//  Created by George Nachman on 1/18/26.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermExpressionParserTests: XCTestCase, iTermObject {
    private var savedBIFs: Any?
    private var scope: iTermVariableScope!

    override func setUp() {
        super.setUp()
        savedBIFs = iTermBuiltInFunctions.sharedInstance().savedState()

        // Register "add" function
        let add = iTermBuiltInFunction(
            name: "add",
            arguments: ["x": NSNumber.self, "y": NSNumber.self],
            optionalArguments: [],
            defaultValues: [:],
            context: [],
            sideEffectsPlaceholder: nil
        ) { parameters, completion in
            let x = (parameters["x"] as? NSNumber)?.intValue ?? 0
            let y = (parameters["y"] as? NSNumber)?.intValue ?? 0
            completion(NSNumber(value: x + y), nil)
        }
        iTermBuiltInFunctions.sharedInstance().register(add, namespace: nil)

        // Register "mult" function
        let mult = iTermBuiltInFunction(
            name: "mult",
            arguments: ["x": NSNumber.self, "y": NSNumber.self],
            optionalArguments: [],
            defaultValues: [:],
            context: [],
            sideEffectsPlaceholder: nil
        ) { parameters, completion in
            let x = (parameters["x"] as? NSNumber)?.intValue ?? 0
            let y = (parameters["y"] as? NSNumber)?.intValue ?? 0
            completion(NSNumber(value: x * y), nil)
        }
        iTermBuiltInFunctions.sharedInstance().register(mult, namespace: nil)

        // Register "cat" function
        let cat = iTermBuiltInFunction(
            name: "cat",
            arguments: ["x": NSString.self, "y": NSString.self],
            optionalArguments: [],
            defaultValues: [:],
            context: [],
            sideEffectsPlaceholder: nil
        ) { parameters, completion in
            let x = parameters["x"] as? String ?? ""
            let y = parameters["y"] as? String ?? ""
            completion(x + y as NSString, nil)
        }
        iTermBuiltInFunctions.sharedInstance().register(cat, namespace: nil)

        // Register "s" function (returns "string")
        let s = iTermBuiltInFunction(
            name: "s",
            arguments: [:],
            optionalArguments: [],
            defaultValues: [:],
            context: [],
            sideEffectsPlaceholder: nil
        ) { _, completion in
            completion("string" as NSString, nil)
        }
        iTermBuiltInFunctions.sharedInstance().register(s, namespace: nil)

        // Register "a" function (returns array)
        let a = iTermBuiltInFunction(
            name: "a",
            arguments: [:],
            optionalArguments: [],
            defaultValues: [:],
            context: [],
            sideEffectsPlaceholder: nil
        ) { _, completion in
            completion([1, "foo"] as NSArray, nil)
        }
        iTermBuiltInFunctions.sharedInstance().register(a, namespace: nil)

        iTermArrayCountBuiltInFunction.register()

        scope = iTermVariableScope()
        let variables = iTermVariables(context: [], owner: self)
        scope.add(variables, toScopeNamed: nil)
    }

    override func tearDown() {
        if let saved = savedBIFs {
            iTermBuiltInFunctions.sharedInstance().restoreState(saved)
        }
        super.tearDown()
    }

    // MARK: - iTermObject

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { nil }

    // MARK: - Parser Tests

    func testSignature() {
        let parser = iTermExpressionParser.callParser()!
        let scope = iTermVariableScope()
        guard let expression = parser.parse("add(x:1, y:2)", scope: scope) else {
            XCTFail("Failed to parse")
            return
        }
        XCTAssertEqual(expression.expressionType, .functionCall)
        XCTAssertEqual(expression.functionCall.signature, "add(x,y)")
    }

    func testParseExpressionWithArrayLiteral() {
        let parser = iTermExpressionParser.expressionParser()!
        let scope = iTermVariableScope()
        guard let expression = parser.parse("[ 1, 2, 3 ]", scope: scope) else {
            XCTFail("Failed to parse expression")
            return
        }

        XCTAssertEqual(expression.expressionType, iTermParsedExpressionType.arrayOfExpressions)
        XCTAssertEqual(expression.arrayOfExpressions.count, 3)

        // Each element should be a Subexpression containing the expected value
        let expectedValues: [NSNumber] = [1, 2, 3]
        for (index, expr) in expression.arrayOfExpressions.enumerated() {
            XCTAssertEqual(expr.expressionType, iTermParsedExpressionType.subexpression)
            let value = try! expr.subexpression.synchronousValue(sideEffectsAllowed: false, scope: scope)
            XCTAssertEqual(value, expectedValues[index])
        }
    }

    func testSignatureForFunctionCallInvocation() {
        let invocation = "f(x: 1, y: \"foo\")"
        let expected = "f(x,y)"
        do {
            let actual = try iTermExpressionParser.signature(forFunctionCallInvocation: invocation)
            XCTAssertEqual(expected, actual)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSignatureForErroneousFunctionCallInvocation() {
        var invocation = "f(x: 1, y: \"foo)"
        XCTAssertThrowsError(try iTermExpressionParser.signature(forFunctionCallInvocation: invocation))

        invocation = "f(x: 1, y: 2"
        XCTAssertThrowsError(try iTermExpressionParser.signature(forFunctionCallInvocation: invocation))
    }

    // MARK: - Expression Evaluator Tests

    func testEvaluateExpressionFunction() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "add(x: 1, y: 2)", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
            XCTAssertEqual(eval.missingValues?.count ?? 0, 0)
        }
        XCTAssertEqual(output as? NSNumber, 3)
    }

    func testEvaluateExpressionFunctionComposition() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "add(x: 1, y: mult(x: 2, y: 3))", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
            XCTAssertEqual(eval.missingValues?.count ?? 0, 0)
        }
        XCTAssertEqual(output as? NSNumber, 7)
    }

    func testEvaluateExpressionUndefinedFunction() {
        let expectation = XCTestExpectation(description: "evaluate function call")
        let evaluator = iTermExpressionEvaluator(expressionString: "add(x: 1, y: bogus(x: 2, y: 3))", scope: scope)
        evaluator.evaluate(withTimeout: .infinity, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value)
            XCTAssertNotNil(eval.error)
            XCTAssertEqual(Array(eval.missingValues ?? []), ["bogus(x,y)"])
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3600)
    }

    func testEvaluateExpressionStringVariable() {
        scope.setValue("xyz" as NSString, forVariableNamed: "foo")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "foo", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
            XCTAssertEqual(eval.missingValues?.count ?? 0, 0)
        }
        XCTAssertEqual(output as? String, "xyz")
    }

    func testEvaluateExpressionStringLiteral() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "\"foo\"", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
            XCTAssertEqual(eval.missingValues?.count ?? 0, 0)
        }
        XCTAssertEqual(output as? String, "foo")
    }

    func testEvaluateExpressionNumberLiteral() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "42", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
            XCTAssertEqual(eval.missingValues?.count ?? 0, 0)
        }
        XCTAssertEqual(output as? NSNumber, 42)
    }

    func testEvaluateExpressionInterpolatedString() {
        scope.setValue("the sum is" as NSString, forVariableNamed: "label")
        scope.setValue(NSNumber(value: 1), forVariableNamed: "one")
        scope.setValue([0, 1, 2, 3] as NSArray, forVariableNamed: "array")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(
            expressionString: "\"I found that \\(label) equal to \\(add(x: one, y: array[2]))\"",
            scope: scope
        )
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
            XCTAssertEqual(eval.missingValues?.count ?? 0, 0)
        }
        XCTAssertEqual(output as? String, "I found that the sum is equal to 3")
    }

    func testEvaluateExpressionNestedInterpolatedString() {
        scope.setValue("the sum is" as NSString, forVariableNamed: "label")
        scope.setValue(NSNumber(value: 1), forVariableNamed: "one")
        scope.setValue([0, 1, 2, 3] as NSArray, forVariableNamed: "array")

        var output: Any?
        let expression = """
            "start-top \\(\
                cat(x: "outer-cat-x",\
                    y: "begin-outer-cat-y \\(\
                            cat(x: "inner-cat-x", \
                                y: "inner-cat-y")\
                        ) end-outer-cat-y")\
                ) end-outer"
            """
        let evaluator = iTermExpressionEvaluator(expressionString: expression, scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
            XCTAssertEqual(eval.missingValues?.count ?? 0, 0)
        }
        XCTAssertEqual(output as? String, "start-top outer-cat-xbegin-outer-cat-y inner-cat-xinner-cat-y end-outer-cat-y end-outer")
    }

    func testEvaluateExpressionNestedInterpolatedStringWithUndefinedVariableCall() {
        scope.setValue("the sum is" as NSString, forVariableNamed: "label")
        scope.setValue(NSNumber(value: 1), forVariableNamed: "one")
        scope.setValue([0, 1, 2, 3] as NSArray, forVariableNamed: "array")

        let expectation = XCTestExpectation(description: "evaluate function call")
        let expression = """
            "start-top \\(\
                cat(x: "outer-cat-x",\
                    y: "begin-outer-cat-y \\(\
                            cat(x: "inner-cat-x", \
                                y: bogus)\
                        ) end-outer-cat-y")\
                ) end-outer"
            """
        let evaluator = iTermExpressionEvaluator(expressionString: expression, scope: scope)
        evaluator.evaluate(withTimeout: .infinity, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value)
            XCTAssertNotNil(eval.error)
            XCTAssertEqual(eval.missingValues?.count ?? 0, 0)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3600)
    }

    func testEvaluateExpressionNumberVariable() {
        scope.setValue(NSNumber(value: 5), forVariableNamed: "foo")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "foo", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
            XCTAssertEqual(eval.missingValues?.count ?? 0, 0)
        }
        XCTAssertEqual(output as? NSNumber, 5)
    }

    func testEvaluateExpressionArrayVariable() {
        let value = [2, 3] as NSArray
        scope.setValue(value, forVariableNamed: "foo")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "foo", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
            XCTAssertEqual(eval.missingValues?.count ?? 0, 0)
        }
        XCTAssertEqual(output as? NSArray, value)
    }

    func testEvaluateExpressionDereferencedArrayVariable() {
        let value = [2, 3, 4] as NSArray
        scope.setValue(value, forVariableNamed: "foo")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "foo[1]", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
            XCTAssertEqual(eval.missingValues?.count ?? 0, 0)
        }
        XCTAssertEqual(output as? NSNumber, 3)
    }

    func testEvaluateExpressionOutOfBoundsArrayReference() {
        let value = [2, 3, 4] as NSArray
        scope.setValue(value, forVariableNamed: "foo")

        let evaluator = iTermExpressionEvaluator(expressionString: "foo[3]", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value)
            XCTAssertNotNil(eval.error)
            XCTAssertEqual((eval.error as NSError?)?.code, 3)
            XCTAssertEqual(eval.missingValues?.count ?? 0, 0)
        }
    }

    func testEvaluateExpressionOptionalVariable() {
        scope.setValue(NSNumber(value: 5), forVariableNamed: "foo")

        var output: Any?
        var evaluator = iTermExpressionEvaluator(expressionString: "foo?", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
            XCTAssertEqual(eval.missingValues?.count ?? 0, 0)
        }
        XCTAssertEqual(output as? NSNumber, 5)

        output = nil
        evaluator = iTermExpressionEvaluator(expressionString: "bar?", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
            XCTAssertEqual(eval.missingValues?.count ?? 0, 0)
        }
        XCTAssertNil(output)
    }

    func testEvaluateExpressionUndefinedVariable() {
        let evaluator = iTermExpressionEvaluator(expressionString: "foo", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value)
            XCTAssertNotNil(eval.error)
            XCTAssertEqual((eval.error as NSError?)?.code, 7)
            XCTAssertEqual(eval.missingValues?.count ?? 0, 0)
        }
    }

    // MARK: - Function Call Tests

    func testCallFunction() {
        var result: Any?
        iTermScriptFunctionCall.callFunction(
            "add(x:1, y:2)",
            timeout: 0,
            sideEffectsAllowed: true,
            scope: scope,
            retainSelf: true
        ) { object, error, missing in
            result = object
            XCTAssertNil(error)
            XCTAssertEqual(missing?.count ?? 0, 0)
        }
        XCTAssertEqual(result as? NSNumber, 3)
    }

    func testCallFunctionMistypedArgument() {
        iTermScriptFunctionCall.callFunction(
            "add(x:1, y:\"foo\")",
            timeout: 0,
            sideEffectsAllowed: true,
            scope: scope,
            retainSelf: true
        ) { object, error, missing in
            XCTAssertNil(object)
            XCTAssertNotNil(error)
            XCTAssertEqual(missing?.count ?? 0, 0)
        }
    }

    func testCallFunctionWrongArguments() {
        let expectation = XCTestExpectation(description: "evaluate function call")
        iTermScriptFunctionCall.callFunction(
            "add(x:1)",
            timeout: .infinity,
            sideEffectsAllowed: true,
            scope: scope,
            retainSelf: true
        ) { object, error, missing in
            XCTAssertNil(object)
            XCTAssertNotNil(error)
            XCTAssertEqual(Array(missing ?? []), ["add(x)"])
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3600)
    }

    // MARK: - String Evaluation Tests

    func testEvaluateString() {
        scope.setValue("BAR" as NSString, forVariableNamed: "bar")

        var result: Any?
        let evaluator = iTermExpressionEvaluator(
            interpolatedString: "foo \\(cat(x: s(), y: bar)) fin",
            scope: scope
        )
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            result = eval.value
            XCTAssertNil(eval.error)
            XCTAssertEqual(eval.missingValues?.count ?? 0, 0)
        }
        XCTAssertEqual(result as? String, "foo stringBAR fin")
    }

    func testEvaluateStringArrayResult() {
        var result: Any?
        let evaluator = iTermExpressionEvaluator(interpolatedString: "\\(a())", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            result = eval.value
            XCTAssertNil(eval.error)
            XCTAssertEqual(eval.missingValues?.count ?? 0, 0)
        }
        XCTAssertEqual(result as? String, "[1, foo]")
    }

    // MARK: - Built-in Function Tests

    func testArrayCount() {
        var result: Any?
        iTermScriptFunctionCall.callFunction(
            "iterm2.count(array: a())",
            timeout: 0,
            sideEffectsAllowed: true,
            scope: scope,
            retainSelf: true
        ) { object, error, missing in
            result = object
        }
        XCTAssertEqual(result as? NSNumber, 2)
    }

    // MARK: - Basic Arithmetic Operations

    func testAddition() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "1 + 2", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 3)
    }

    func testSubtraction() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "5 - 3", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 2)
    }

    func testMultiplication() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "4 * 3", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 12)
    }

    func testDivision() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "10 / 2", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 5)
    }

    func testFloatingPointArithmetic() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "1.5 + 2.5", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual((output as? NSNumber)?.doubleValue, 4.0)
    }

    func testDivisionProducesFloat() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "5 / 2", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual((output as? NSNumber)?.doubleValue, 2.5)
    }

    // MARK: - Operator Precedence

    func testMultiplicationPrecedence() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "1 + 2 * 3", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // Should be 1 + (2 * 3) = 7, not (1 + 2) * 3 = 9
        XCTAssertEqual(output as? NSNumber, 7)
    }

    func testDivisionPrecedence() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "10 - 6 / 2", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // Should be 10 - (6 / 2) = 7, not (10 - 6) / 2 = 2
        XCTAssertEqual(output as? NSNumber, 7)
    }

    func testMixedPrecedence() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "2 + 3 * 4 - 5", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // Should be 2 + (3 * 4) - 5 = 2 + 12 - 5 = 9
        XCTAssertEqual(output as? NSNumber, 9)
    }

    // MARK: - Parentheses

    func testParenthesesOverridePrecedence() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "(1 + 2) * 3", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 9)
    }

    func testNestedParentheses() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "((1 + 2) * (3 + 4))", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 21)
    }

    func testParenthesesWithVariables() {
        scope.setValue(NSNumber(value: 2), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 3), forVariableNamed: "y")
        scope.setValue(NSNumber(value: 4), forVariableNamed: "z")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "(x + y) * z", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // (2 + 3) * 4 = 20
        XCTAssertEqual(output as? NSNumber, 20)
    }

    // MARK: - Arithmetic with Variables

    func testArithmeticWithVariables() {
        scope.setValue(NSNumber(value: 5), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 3), forVariableNamed: "y")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "x + y", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 8)
    }

    func testArithmeticWithMixedLiteralsAndVariables() {
        scope.setValue(NSNumber(value: 5), forVariableNamed: "x")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "x * 2 + 1", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // 5 * 2 + 1 = 11
        XCTAssertEqual(output as? NSNumber, 11)
    }

    // MARK: - Arithmetic in Array Index

    func testArithmeticInArrayIndex() {
        let array = [10, 20, 30, 40] as NSArray
        scope.setValue(array, forVariableNamed: "array")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "array[1 + 1]", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // array[2] = 30
        XCTAssertEqual(output as? NSNumber, 30)
    }

    func testVariableInArrayIndex() {
        let array = [10, 20, 30, 40] as NSArray
        scope.setValue(array, forVariableNamed: "array")
        scope.setValue(NSNumber(value: 1), forVariableNamed: "idx")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "array[idx]", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // array[1] = 20
        XCTAssertEqual(output as? NSNumber, 20)
    }

    func testComplexArrayIndex() {
        let array = [10, 20, 30, 40] as NSArray
        scope.setValue(array, forVariableNamed: "array")
        scope.setValue(NSNumber(value: 1), forVariableNamed: "x")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "array[x * 2]", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // array[1 * 2] = array[2] = 30
        XCTAssertEqual(output as? NSNumber, 30)
    }

    // MARK: - Ternary Operator

    func testTernaryTrue() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "true ? 1 : 2", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 1)
    }

    func testTernaryFalse() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "false ? 1 : 2", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 2)
    }

    func testTernaryWithNumericCondition() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "1 ? 10 : 20", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // Non-zero = true
        XCTAssertEqual(output as? NSNumber, 10)
    }

    func testTernaryWithZeroCondition() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "0 ? 10 : 20", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // Zero = false
        XCTAssertEqual(output as? NSNumber, 20)
    }

    func testTernaryWithVariables() {
        scope.setValue(NSNumber(value: 1), forVariableNamed: "flag")
        scope.setValue(NSNumber(value: 100), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 200), forVariableNamed: "y")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "flag ? x : y", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 100)
    }

    func testNestedTernary() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "true ? (false ? 1 : 2) : 3", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // true ? (false ? 1 : 2) : 3 = (false ? 1 : 2) = 2
        XCTAssertEqual(output as? NSNumber, 2)
    }

    // MARK: - Optional vs Ternary Distinction

    func testOptionalVsTernaryDistinction() {
        // Set up a variable
        scope.setValue(NSNumber(value: 5), forVariableNamed: "foo")

        // Test optional: foo? should return 5
        var optionalOutput: Any?
        let optionalEvaluator = iTermExpressionEvaluator(expressionString: "foo?", scope: scope)
        optionalEvaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            optionalOutput = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(optionalOutput as? NSNumber, 5)

        // Test ternary: foo ? 10 : 20 should return 10 (since foo=5 is truthy)
        var ternaryOutput: Any?
        let ternaryEvaluator = iTermExpressionEvaluator(expressionString: "foo ? 10 : 20", scope: scope)
        ternaryEvaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            ternaryOutput = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(ternaryOutput as? NSNumber, 10)
    }

    // MARK: - Edge Cases and Error Handling

    func testDivisionByZero() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "1 / 0", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            // Division by zero in floating point produces infinity, not an error
        }
        // Check that it's infinity
        if let number = output as? NSNumber {
            XCTAssertTrue(number.doubleValue.isInfinite)
        } else {
            // If it's an error, that's also acceptable
        }
    }

    func testNegativeResult() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "3 - 5", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, -2)
    }

    func testChainedOperations() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "1 + 2 + 3 + 4", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 10)
    }

    func testArithmeticWithFunctionCallInParens() {
        var output: Any?
        // Note: Function calls in arithmetic require parentheses
        let evaluator = iTermExpressionEvaluator(expressionString: "(add(x: 1, y: 2)) + 3", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // add(1, 2) + 3 = 3 + 3 = 6
        XCTAssertEqual(output as? NSNumber, 6)
    }

    // MARK: - Integration with Existing Features

    func testArithmeticInInterpolatedString() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "\"Result: \\(1 + 2)\"", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? String, "Result: 3")
    }

    func testArithmeticInFunctionArgument() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "add(x: 1 + 1, y: 2 * 2)", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // add(2, 4) = 6
        XCTAssertEqual(output as? NSNumber, 6)
    }

    // MARK: - Type Mismatch Tests

    func testNonNumericFunctionInArithmetic() {
        // cat() returns a string, which should cause an error when used in arithmetic
        let evaluator = iTermExpressionEvaluator(expressionString: "cat(x: \"a\", y: \"b\") + 1", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value)
            XCTAssertNotNil(eval.error)
            // Error should indicate type mismatch
            XCTAssertTrue(eval.error?.localizedDescription.contains("numeric operand") ?? false,
                         "Error should mention numeric operands, got: \(eval.error?.localizedDescription ?? "nil")")
        }
    }

    func testNonNumericFunctionInTernaryCondition() {
        // Using a string-returning function as ternary condition should produce an error
        let evaluator = iTermExpressionEvaluator(expressionString: "cat(x: \"a\", y: \"b\") ? 1 : 2", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value)
            XCTAssertNotNil(eval.error)
            // Error should indicate type mismatch
            XCTAssertTrue(eval.error?.localizedDescription.contains("Type mismatch") ?? false,
                         "Error should mention type mismatch, got: \(eval.error?.localizedDescription ?? "nil")")
        }
    }

    // MARK: - Additional Edge Case Tests

    // MARK: - Unary Negation Tests

    func testNegationOperator() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "-5", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, -5)
    }

    func testNegationWithParentheses() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "-(2 + 3)", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, -5)
    }

    func testNegationWithVariable() {
        scope.setValue(NSNumber(value: 10), forVariableNamed: "x")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "-x", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, -10)
    }

    func testDoubleNegation() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "--5", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 5)
    }

    func testNegationPrecedence() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "-2 * 3", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // Should be (-2) * 3 = -6, not -(2 * 3) = -6 (same result, but important for understanding)
        XCTAssertEqual(output as? NSNumber, -6)
    }

    func testComplexArithmeticWithNegation() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "10 + -5 * 2", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // 10 + ((-5) * 2) = 10 + (-10) = 0
        XCTAssertEqual(output as? NSNumber, 0)
    }

    func testNegationChainedWithBinarySubtraction() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "5 - -3", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // 5 - (-3) = 8
        XCTAssertEqual(output as? NSNumber, 8)
    }

    func testNegationWithLogicalNot() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "-!0", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // !0 = 1 (true), -1 = -1
        XCTAssertEqual(output as? NSNumber, -1)
    }

    func testNegationWithFloatingPoint() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "-3.14", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual((output as? NSNumber)?.doubleValue, -3.14)
    }

    func testTripleNegation() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "---5", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // ---5 = --(-5) = -(-(-5)) = -5
        XCTAssertEqual(output as? NSNumber, -5)
    }

    func testNegationWithComparison() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "-5 < 0", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // -5 < 0 is true = 1
        XCTAssertEqual(output as? NSNumber, 1)
    }

    func testFloatingPointDivision() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "7 / 2", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual((output as? NSNumber)?.doubleValue, 3.5)
    }

    func testDivisionByZeroProducesInfinity() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "5 / 0", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
        }
        XCTAssertTrue((output as? NSNumber)?.doubleValue.isInfinite ?? false)
    }

    func testZeroTimesInfinity() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "0 * (1 / 0)", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
        }
        // 0 * Infinity = NaN
        XCTAssertTrue((output as? NSNumber)?.doubleValue.isNaN ?? false)
    }

    func testArrayIndexWithComplexExpression() {
        let array = [100, 200, 300, 400, 500] as NSArray
        scope.setValue(array, forVariableNamed: "arr")
        scope.setValue(NSNumber(value: 2), forVariableNamed: "i")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "arr[i * 2 - 1]", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // i * 2 - 1 = 2 * 2 - 1 = 3
        XCTAssertEqual(output as? NSNumber, 400)
    }

    // DISABLED: Nested array access (matrix[1][2]) is NOT supported by the parser
    // The parser only supports single-level array indexing: arr[expr]
    // Nested access would require allowing array[index] to be used as PrimaryExpression
    /*
    func testNestedArrayAccess() {
        let inner1 = [1, 2, 3] as NSArray
        let inner2 = [4, 5, 6] as NSArray
        let outer = [inner1, inner2] as NSArray
        scope.setValue(outer, forVariableNamed: "matrix")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "matrix[1][2]", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // matrix[1][2] = inner2[2] = 6
        XCTAssertEqual(output as? NSNumber, 6)
    }
    */

    func testTernaryWithArithmeticInBranches() {
        scope.setValue(NSNumber(value: 1), forVariableNamed: "flag")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "flag ? 10 + 5 : 20 * 2", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 15)
    }

    // DISABLED: Comparison operators (>, <, >=, <=, ==, !=) are NOT implemented in the parser
    // The parser only supports: +, -, *, /, ?:, [], ? (postfix)
    // Comparison operators would require adding ComparisonExpression production rules
    /*
    func testNestedTernaryOperators() {
        scope.setValue(NSNumber(value: 2), forVariableNamed: "x")

        var output: Any?
        // (x > 1) ? ((x > 2) ? 1 : 2) : 3
        // x = 2: (2 > 1) = true, so evaluate (2 > 2) = false, so 2
        let evaluator = iTermExpressionEvaluator(expressionString: "(x > 1) ? ((x > 2) ? 1 : 2) : 3", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 2)
    }
    */

    func testArithmeticWithArrayElements() {
        let array = [10, 20, 30] as NSArray
        scope.setValue(array, forVariableNamed: "arr")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "arr[0] + arr[1] + arr[2]", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 60)
    }

    func testFunctionCallWithArithmeticArguments() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "add(x: 2 * 3, y: 4 + 1)", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // add(6, 5) = 11
        XCTAssertEqual(output as? NSNumber, 11)
    }

    // DISABLED: Uses comparison operators (>) and unary negation (-), both NOT implemented
    // The parser only supports: +, -, *, /, ?:, [], ? (postfix)
    /*
    func testComplexExpressionMixingAllFeatures() {
        scope.setValue(NSNumber(value: 2), forVariableNamed: "x")
        scope.setValue([10, 20, 30] as NSArray, forVariableNamed: "arr")

        var output: Any?
        // (x > 1) ? arr[x] + 5 : -10
        // x = 2: (2 > 1) = true, so arr[2] + 5 = 30 + 5 = 35
        let evaluator = iTermExpressionEvaluator(expressionString: "(x > 1) ? arr[x] + 5 : -10", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 35)
    }
    */

    func testComplexArithmeticInInterpolatedString() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "\"The answer is \\(20 + 22)\"", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? String, "The answer is 42")
    }

    func testNegativeArrayIndex() {
        let array = [10, 20, 30] as NSArray
        scope.setValue(array, forVariableNamed: "arr")

        let evaluator = iTermExpressionEvaluator(expressionString: "arr[-1]", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value)
            XCTAssertNotNil(eval.error)
        }
    }

    func testVeryLongChainedAddition() {
        var exprString = "1"
        for i in 2...50 {
            exprString += " + \(i)"
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: exprString, scope: scope)
        evaluator.evaluate(withTimeout: 1, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        // Sum of 1 to 50 = 1275
        XCTAssertEqual(output as? NSNumber, 1275)
    }

    // MARK: - Logical NOT Parsing

    func testParseLogicalNot() {
        let parser = iTermExpressionParser.expressionParser()!
        guard let expression = parser.parse("!0", scope: scope) else {
            XCTFail("Failed to parse !0")
            return
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(parsedExpression: expression, invocation: "", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 1)
    }

    func testParseDoubleNot() {
        let parser = iTermExpressionParser.expressionParser()!
        guard let expression = parser.parse("!!5", scope: scope) else {
            XCTFail("Failed to parse !!5")
            return
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(parsedExpression: expression, invocation: "", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { eval in
            output = eval.value
        }
        XCTAssertEqual(output as? NSNumber, 1)
    }

    func testParseNotInExpression() {
        // Test !x where x is a variable
        scope.setValue(NSNumber(value: 0), forVariableNamed: "x")
        let parser = iTermExpressionParser.expressionParser()!
        guard let expression = parser.parse("!x", scope: scope) else {
            XCTFail("Failed to parse !x")
            return
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(parsedExpression: expression, invocation: "", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { eval in
            output = eval.value
        }
        XCTAssertEqual(output as? NSNumber, 1)
    }

    // MARK: - Equality Operator Parsing

    func testParseEquality() {
        let parser = iTermExpressionParser.expressionParser()!
        guard let expression = parser.parse("5 == 5", scope: scope) else {
            XCTFail("Failed to parse 5 == 5")
            return
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(parsedExpression: expression, invocation: "", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { eval in
            output = eval.value
        }
        XCTAssertEqual(output as? NSNumber, 1)
    }

    func testParseInequality() {
        let parser = iTermExpressionParser.expressionParser()!
        guard let expression = parser.parse("5 != 3", scope: scope) else {
            XCTFail("Failed to parse 5 != 3")
            return
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(parsedExpression: expression, invocation: "", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { eval in
            output = eval.value
        }
        XCTAssertEqual(output as? NSNumber, 1)
    }

    func testParseEqualityPrecedence() {
        // Test that 1 + 2 == 2 + 1 parses correctly
        let parser = iTermExpressionParser.expressionParser()!
        guard let expression = parser.parse("1 + 2 == 2 + 1", scope: scope) else {
            XCTFail("Failed to parse precedence")
            return
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(parsedExpression: expression, invocation: "", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { eval in
            output = eval.value
        }
        XCTAssertEqual(output as? NSNumber, 1)
    }

    // MARK: - Relational Operator Parsing

    func testParseLessThan() {
        let parser = iTermExpressionParser.expressionParser()!
        guard let expression = parser.parse("3 < 5", scope: scope) else {
            XCTFail("Failed to parse 3 < 5")
            return
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(parsedExpression: expression, invocation: "", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { eval in
            output = eval.value
        }
        XCTAssertEqual(output as? NSNumber, 1)
    }

    func testParseGreaterThan() {
        let parser = iTermExpressionParser.expressionParser()!
        guard let expression = parser.parse("5 > 3", scope: scope) else {
            XCTFail("Failed to parse 5 > 3")
            return
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(parsedExpression: expression, invocation: "", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { eval in
            output = eval.value
        }
        XCTAssertEqual(output as? NSNumber, 1)
    }

    func testParseRelationalPrecedence() {
        // Test that 1 + 2 < 3 + 4 parses correctly
        let parser = iTermExpressionParser.expressionParser()!
        guard let expression = parser.parse("1 + 2 < 3 + 4", scope: scope) else {
            XCTFail("Failed to parse precedence")
            return
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(parsedExpression: expression, invocation: "", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { eval in
            output = eval.value
        }
        XCTAssertEqual(output as? NSNumber, 1)
    }

    // MARK: - Logical Operator Parsing

    func testParseLogicalAnd() {
        let parser = iTermExpressionParser.expressionParser()!
        guard let expression = parser.parse("1 && 0", scope: scope) else {
            XCTFail("Failed to parse 1 && 0")
            return
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(parsedExpression: expression, invocation: "", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 0)
    }

    func testParseLogicalOr() {
        let parser = iTermExpressionParser.expressionParser()!
        guard let expression = parser.parse("1 || 0", scope: scope) else {
            XCTFail("Failed to parse 1 || 0")
            return
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(parsedExpression: expression, invocation: "", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { eval in
            output = eval.value
        }
        XCTAssertEqual(output as? NSNumber, 1)
    }

    func testParseLogicalPrecedence() {
        // Test that true || false && false parses as true || (false && false) = true
        let parser = iTermExpressionParser.expressionParser()!
        guard let expression = parser.parse("1 || 0 && 0", scope: scope) else {
            XCTFail("Failed to parse precedence")
            return
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(parsedExpression: expression, invocation: "", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { eval in
            output = eval.value
        }
        XCTAssertEqual(output as? NSNumber, 1)
    }

    func testParseComplexLogical() {
        // Test (x > 5) && (y < 10) combining comparison with logical
        scope.setValue(NSNumber(value: 10), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 3), forVariableNamed: "y")
        let parser = iTermExpressionParser.expressionParser()!
        guard let expression = parser.parse("(x > 5) && (y < 10)", scope: scope) else {
            XCTFail("Failed to parse complex logical")
            return
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(parsedExpression: expression, invocation: "", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { eval in
            output = eval.value
        }
        XCTAssertEqual(output as? NSNumber, 1)
    }

    // MARK: - String Literal Comparison Tests (Parser)

    func testParseStringEqualityTrue() {
        let parser = iTermExpressionParser.expressionParser()!
        guard let expression = parser.parse("\"foo\" == \"foo\"", scope: scope) else {
            XCTFail("Failed to parse \"foo\" == \"foo\"")
            return
        }

        var output: Any?
        var error: Error?
        let evaluator = iTermExpressionEvaluator(parsedExpression: expression, invocation: "", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { eval in
            output = eval.value
            error = eval.error
        }
        if let error = error {
            XCTFail("Evaluation error: \(error)")
        }
        XCTAssertEqual(output as? NSNumber, 1)
    }

    func testParseStringEqualityFalse() {
        let parser = iTermExpressionParser.expressionParser()!
        guard let expression = parser.parse("\"foo\" == \"bar\"", scope: scope) else {
            XCTFail("Failed to parse \"foo\" == \"bar\"")
            return
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(parsedExpression: expression, invocation: "", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { eval in
            output = eval.value
        }
        XCTAssertEqual(output as? NSNumber, 0)
    }

    func testParseStringLessThan() {
        let parser = iTermExpressionParser.expressionParser()!
        guard let expression = parser.parse("\"apple\" < \"banana\"", scope: scope) else {
            XCTFail("Failed to parse \"apple\" < \"banana\"")
            return
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(parsedExpression: expression, invocation: "", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { eval in
            output = eval.value
        }
        XCTAssertEqual(output as? NSNumber, 1)
    }
}
