//
//  SubexpressionTests.swift
//  iTerm2
//
//  Created by George Nachman on 1/18/26.
//

import XCTest
@testable import iTerm2SharedARC

final class SubexpressionTests: XCTestCase, iTermObject {
    private var savedBIFs: Any?
    private var scope: iTermVariableScope!

    override func setUp() {
        super.setUp()
        savedBIFs = iTermBuiltInFunctions.sharedInstance().savedState()

        // Register test functions
        registerTestFunctions()

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

    private func registerTestFunctions() {
        let add = iTermBuiltInFunction(
            name: "add",
            arguments: ["x": NSNumber.self, "y": NSNumber.self],
            optionalArguments: [],
            defaultValues: [:],
            context: [],
            sideEffectsPlaceholder: nil
        ) { parameters, completion in
            let x = (parameters["x"] as? NSNumber)?.doubleValue ?? 0
            let y = (parameters["y"] as? NSNumber)?.doubleValue ?? 0
            completion(NSNumber(value: x + y), nil)
        }
        iTermBuiltInFunctions.sharedInstance().register(add, namespace: nil)

        let mult = iTermBuiltInFunction(
            name: "mult",
            arguments: ["x": NSNumber.self, "y": NSNumber.self],
            optionalArguments: [],
            defaultValues: [:],
            context: [],
            sideEffectsPlaceholder: nil
        ) { parameters, completion in
            let x = (parameters["x"] as? NSNumber)?.doubleValue ?? 0
            let y = (parameters["y"] as? NSNumber)?.doubleValue ?? 0
            completion(NSNumber(value: x * y), nil)
        }
        iTermBuiltInFunctions.sharedInstance().register(mult, namespace: nil)

        let returnsNil = iTermBuiltInFunction(
            name: "returnsNil",
            arguments: [:],
            optionalArguments: [],
            defaultValues: [:],
            context: [],
            sideEffectsPlaceholder: nil
        ) { _, completion in
            completion(nil, nil)
        }
        iTermBuiltInFunctions.sharedInstance().register(returnsNil, namespace: nil)
    }

    // MARK: - iTermObject

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { nil }

    // MARK: - Unary Operations (Negation)

    func testNegationOfLiteral() {
        let expr = Subexpression(negated: Subexpression(number: 5))
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, -5)
    }

    func testNegationOfVariable() {
        scope.setValue(NSNumber(value: 3), forVariableNamed: "x")

        let indirectValue = IndirectValue(path: "x")
        let varExpr = Subexpression(indirectValue: indirectValue)
        let expr = Subexpression(negated: varExpr)

        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, -3)
    }

    func testNegationOfExpression() {
        let twoExpr = Subexpression(number: 2)
        let threeExpr = Subexpression(number: 3)
        let sumExpr = Subexpression(lhs: twoExpr, plus: threeExpr)
        let expr = Subexpression(negated: sumExpr)

        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, -5)
    }

    func testNegationOfFunctionCall() {
        let expectation = XCTestExpectation(description: "evaluate negated function call")

        let parser = iTermExpressionParser.callParser()!
        guard let parsedExpr = parser.parse("add(x:1, y:2)", scope: scope) else {
            XCTFail("Failed to parse")
            return
        }

        let funcExpr = Subexpression(functionCall: parsedExpr.functionCall)
        let expr = Subexpression(negated: funcExpr)

        expr.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: true, scope: scope) { result in
            result.whenFirst { value in
                XCTAssertEqual((value as! NSNumber).intValue, -3)
            } second: { error in
                XCTFail("Got error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testDoubleNegation() {
        let fiveExpr = Subexpression(number: 5)
        let negOnce = Subexpression(negated: fiveExpr)
        let expr = Subexpression(negated: negOnce)

        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 5)
    }

    func testNegationOfZero() {
        let expr = Subexpression(negated: Subexpression(number: 0))
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 0)
    }

    func testNegationOfInfinity() {
        let infExpr = Subexpression(number: NSNumber(value: Double.infinity))
        let expr = Subexpression(negated: infExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertTrue(result.doubleValue.isInfinite)
        XCTAssertTrue(result.doubleValue < 0)
    }

    // MARK: - Async vs Sync Evaluation Paths

    func testRequiresAsyncForFunctionCall() {
        let parser = iTermExpressionParser.callParser()!
        guard let parsedExpr = parser.parse("add(x:1, y:2)", scope: scope) else {
            XCTFail("Failed to parse")
            return
        }

        let expr = Subexpression(functionCall: parsedExpr.functionCall)
        XCTAssertTrue(expr.requiresAsyncEvaluation)
        XCTAssertTrue(expr.containsAnyFunctionCall)
    }

    func testSyncForLiteralsOnly() {
        let oneExpr = Subexpression(number: 1)
        let twoExpr = Subexpression(number: 2)
        let expr = Subexpression(lhs: oneExpr, plus: twoExpr)

        XCTAssertFalse(expr.requiresAsyncEvaluation)
        XCTAssertFalse(expr.containsAnyFunctionCall)
    }

    func testSyncWithVariables() {
        scope.setValue(NSNumber(value: 5), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 3), forVariableNamed: "y")

        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, plus: yExpr)

        XCTAssertFalse(expr.requiresAsyncEvaluation)
        XCTAssertFalse(expr.containsAnyFunctionCall)

        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 8)
    }

    func testAsyncPropagatesToParent() {
        let parser = iTermExpressionParser.callParser()!
        guard let parsedExpr = parser.parse("add(x:1, y:2)", scope: scope) else {
            XCTFail("Failed to parse")
            return
        }

        let funcExpr = Subexpression(functionCall: parsedExpr.functionCall)
        let oneExpr = Subexpression(number: 1)
        let expr = Subexpression(lhs: oneExpr, plus: funcExpr)

        XCTAssertTrue(expr.requiresAsyncEvaluation)
        XCTAssertTrue(expr.containsAnyFunctionCall)
    }

    func testContainsFunctionCallPropagation() {
        let parser = iTermExpressionParser.callParser()!
        guard let parsedExpr = parser.parse("add(x:1, y:2)", scope: scope) else {
            XCTFail("Failed to parse")
            return
        }

        let funcExpr = Subexpression(functionCall: parsedExpr.functionCall)
        let twoExpr = Subexpression(number: 2)
        let threeExpr = Subexpression(number: 3)

        // (add(1,2) + 2) * 3
        let sum = Subexpression(lhs: funcExpr, plus: twoExpr)
        let product = Subexpression(lhs: sum, times: threeExpr)

        XCTAssertTrue(product.containsAnyFunctionCall)
        XCTAssertTrue(product.requiresAsyncEvaluation)
    }

    // MARK: - Binary Operation Tests

    func testBinaryOperationCrashRegression() {
        // Regression test for line 279 crash bug
        let expectation = XCTestExpectation(description: "binary operation completes")

        scope.setValue(NSNumber(value: 5), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 3), forVariableNamed: "y")

        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, plus: yExpr)

        expr.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { value in
                XCTAssertEqual((value as! NSNumber).intValue, 8)
            } second: { error in
                XCTFail("Got error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testBinaryAsyncEvaluationWithVariables() {
        let expectation = XCTestExpectation(description: "async binary evaluation")

        scope.setValue(NSNumber(value: 10), forVariableNamed: "a")
        scope.setValue(NSNumber(value: 7), forVariableNamed: "b")

        let aExpr = Subexpression(indirectValue: IndirectValue(path: "a"))
        let bExpr = Subexpression(indirectValue: IndirectValue(path: "b"))
        let expr = Subexpression(lhs: aExpr, minus: bExpr)

        expr.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { value in
                XCTAssertEqual((value as! NSNumber).intValue, 3)
            } second: { error in
                XCTFail("Got error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testBinaryAsyncWithFunctionCalls() {
        let expectation = XCTestExpectation(description: "binary with function calls")

        let parser = iTermExpressionParser.callParser()!
        guard let addExpr = parser.parse("add(x:1, y:2)", scope: scope),
              let multExpr = parser.parse("mult(x:3, y:4)", scope: scope) else {
            XCTFail("Failed to parse")
            return
        }

        let leftExpr = Subexpression(functionCall: addExpr.functionCall)
        let rightExpr = Subexpression(functionCall: multExpr.functionCall)
        let expr = Subexpression(lhs: leftExpr, plus: rightExpr)

        XCTAssertTrue(expr.requiresAsyncEvaluation)

        expr.evaluate(invocation: "test", receiver: nil, timeout: 1, sideEffectsAllowed: true, scope: scope) { result in
            result.whenFirst { value in
                XCTAssertEqual((value as! NSNumber).intValue, 15) // 3 + 12
            } second: { error in
                XCTFail("Got error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    // MARK: - Ternary Operation Tests

    func testTernaryAsyncShortCircuit() {
        let expectation = XCTestExpectation(description: "ternary short circuit")

        let trueExpr = Subexpression(number: 1)
        let tenExpr = Subexpression(number: 10)
        let twentyExpr = Subexpression(number: 20)
        let expr = Subexpression(condition: trueExpr, whenTrue: tenExpr, whenFalse: twentyExpr)

        expr.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { value in
                XCTAssertEqual((value as! NSNumber).intValue, 10)
            } second: { error in
                XCTFail("Got error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testTernarySyncNoShortCircuit() {
        // In sync path, both branches are evaluated
        let trueExpr = Subexpression(number: 1)
        let tenExpr = Subexpression(number: 10)
        let twentyExpr = Subexpression(number: 20)
        let expr = Subexpression(condition: trueExpr, whenTrue: tenExpr, whenFalse: twentyExpr)

        XCTAssertFalse(expr.requiresAsyncEvaluation)

        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 10)
    }

    func testTernaryWithVariableCondition() {
        scope.setValue(NSNumber(value: 0), forVariableNamed: "flag")

        let flagExpr = Subexpression(indirectValue: IndirectValue(path: "flag"))
        let yesExpr = Subexpression(number: 100)
        let noExpr = Subexpression(number: 200)
        let expr = Subexpression(condition: flagExpr, whenTrue: yesExpr, whenFalse: noExpr)

        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 200) // flag is 0 (false)
    }

    // MARK: - Edge Cases

    func testVeryLargeNumber() {
        // NOTE: 999999999999999999.0 gets rounded to 1e+18 in IEEE 754 double precision
        // Adding 1 to 1e+18 doesn't change the value due to precision limits (1 is insignificant at that scale)
        // Test that operations on very large numbers work without crashing, not that they're precise
        let largeNum = NSNumber(value: 999999999999999999.0)
        let oneExpr = Subexpression(number: 1)
        let largeExpr = Subexpression(number: largeNum)
        let expr = Subexpression(lhs: largeExpr, plus: oneExpr)

        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        // Just verify we got a result close to the original (precision loss is expected)
        XCTAssertGreaterThanOrEqual(result.doubleValue, largeNum.doubleValue)
        XCTAssertFalse(result.doubleValue.isNaN)
        XCTAssertFalse(result.doubleValue.isInfinite)
    }

    func testVerySmallNumber() {
        // Similar to testVeryLargeNumber, precision loss is expected at this scale
        let smallNum = NSNumber(value: -999999999999999999.0)
        let oneExpr = Subexpression(number: 1)
        let smallExpr = Subexpression(number: smallNum)
        let expr = Subexpression(lhs: smallExpr, minus: oneExpr)

        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        // Just verify we got a result close to the original (precision loss is expected)
        XCTAssertLessThanOrEqual(result.doubleValue, smallNum.doubleValue)
        XCTAssertFalse(result.doubleValue.isNaN)
        XCTAssertFalse(result.doubleValue.isInfinite)
    }

    func testDoubleOverflow() {
        let maxNum = NSNumber(value: Double.greatestFiniteMagnitude)
        let twoExpr = Subexpression(number: 2)
        let maxExpr = Subexpression(number: maxNum)
        let expr = Subexpression(lhs: maxExpr, times: twoExpr)

        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertTrue(result.doubleValue.isInfinite)
    }

    func testZeroDivideByZero() {
        let zeroExpr1 = Subexpression(number: 0)
        let zeroExpr2 = Subexpression(number: 0)
        let expr = Subexpression(lhs: zeroExpr1, dividedBy: zeroExpr2)

        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertTrue(result.doubleValue.isNaN)
    }

    func testInfinityArithmetic() {
        let infExpr = Subexpression(number: NSNumber(value: Double.infinity))
        let fiveExpr = Subexpression(number: 5)
        let expr = Subexpression(lhs: infExpr, plus: fiveExpr)

        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertTrue(result.doubleValue.isInfinite)
    }

    func testNaNPropagation() {
        let nanExpr = Subexpression(number: NSNumber(value: Double.nan))
        let fiveExpr = Subexpression(number: 5)
        let expr = Subexpression(lhs: nanExpr, plus: fiveExpr)

        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertTrue(result.doubleValue.isNaN)
    }

    // MARK: - Error Propagation

    func testUnaryOperationErrorPropagation() {
        let expectation = XCTestExpectation(description: "unary error propagation")

        let undefinedExpr = Subexpression(indirectValue: IndirectValue(path: "undefinedVar"))
        let expr = Subexpression(negated: undefinedExpr)

        expr.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { _ in
                XCTFail("Should have gotten error")
            } second: { error in
                XCTAssertNotNil(error)
                XCTAssertTrue(error.localizedDescription.contains("undefinedVar"))
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testBinaryLeftSideError() {
        let expectation = XCTestExpectation(description: "binary left error")

        let undefinedExpr = Subexpression(indirectValue: IndirectValue(path: "undefinedVar"))
        let fiveExpr = Subexpression(number: 5)
        let expr = Subexpression(lhs: undefinedExpr, plus: fiveExpr)

        expr.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { _ in
                XCTFail("Should have gotten error")
            } second: { error in
                XCTAssertNotNil(error)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testBinaryRightSideError() {
        let expectation = XCTestExpectation(description: "binary right error")

        let fiveExpr = Subexpression(number: 5)
        let undefinedExpr = Subexpression(indirectValue: IndirectValue(path: "undefinedVar"))
        let expr = Subexpression(lhs: fiveExpr, plus: undefinedExpr)

        expr.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { _ in
                XCTFail("Should have gotten error")
            } second: { error in
                XCTAssertNotNil(error)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testTernaryConditionError() {
        let expectation = XCTestExpectation(description: "ternary condition error")

        let undefinedExpr = Subexpression(indirectValue: IndirectValue(path: "undefinedVar"))
        let tenExpr = Subexpression(number: 10)
        let twentyExpr = Subexpression(number: 20)
        let expr = Subexpression(condition: undefinedExpr, whenTrue: tenExpr, whenFalse: twentyExpr)

        expr.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { _ in
                XCTFail("Should have gotten error")
            } second: { error in
                XCTAssertNotNil(error)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    // MARK: - Complex Expressions

    func testDeeplyNestedExpression() {
        var expr = Subexpression(number: 1)
        for i in 2...100 {
            let nextExpr = Subexpression(number: NSNumber(value: i))
            expr = Subexpression(lhs: expr, plus: nextExpr)
        }

        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 5050) // Sum 1 to 100
    }

    func testComplexMixedExpression() {
        scope.setValue(NSNumber(value: 2), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 3), forVariableNamed: "y")

        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let fiveExpr = Subexpression(number: 5)
        let tenExpr = Subexpression(number: 10)

        // (x + y) * 5 - 10 = (2 + 3) * 5 - 10 = 25 - 10 = 15
        let sum = Subexpression(lhs: xExpr, plus: yExpr)
        let product = Subexpression(lhs: sum, times: fiveExpr)
        let expr = Subexpression(lhs: product, minus: tenExpr)

        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 15)
    }

    // MARK: - Edge Cases with nil

    func testTernaryWithFunctionReturningNilViaDirect() {
        let expectation = XCTestExpectation(description: "ternary with nil function - direct")

        let parser = iTermExpressionParser.callParser()!
        guard let parsedExpr = parser.parse("returnsNil()", scope: scope) else {
            XCTFail("Failed to parse")
            return
        }

        let nilFuncExpr = Subexpression(functionCall: parsedExpr.functionCall)
        let oneExpr = Subexpression(number: 1)
        let twoExpr = Subexpression(number: 2)
        let expr = Subexpression(condition: nilFuncExpr, whenTrue: oneExpr, whenFalse: twoExpr)

        expr.evaluate(invocation: "test", receiver: nil, timeout: 1, sideEffectsAllowed: true, scope: scope) { result in
            result.whenFirst { value in
                XCTFail("Expected error for nil in ternary condition, but got value: \(value)")
            } second: { error in
                XCTAssertNotNil(error)
                XCTAssertTrue(error.localizedDescription.contains("expected number") ||
                             error.localizedDescription.contains("Type mismatch"))
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    func testTernaryWithFunctionReturningNilViaParser() {
        // This tests the full pipeline through iTermExpressionEvaluator with synchronous evaluation
        let evaluator = iTermExpressionEvaluator(expressionString: "returnsNil() ? 1 : 2", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            if let _ = eval.value {
                // If it doesn't crash and returns a value, that's acceptable
                // (nil might be treated as false, resulting in 2)
            } else if let error = eval.error {
                // Error is also acceptable
                XCTAssertNotNil(error)
            } else {
                XCTFail("Should have either value or error")
            }
        }
    }

    func testTernaryWithNilInArrayIndex() {
        // This is the crash case - ternary with nil-returning function used as array index
        scope.setValue([10, 20, 30] as NSArray, forVariableNamed: "foo")

        scope.setValue(NSNull(), forVariableNamed: "y")
        let evaluator = iTermExpressionEvaluator(expressionString: "foo[y ? 1 : 2]", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            if let _ = eval.value {
                // If it doesn't crash and returns a value, that's acceptable
            } else if let error = eval.error {
                // Error is expected - nil in arithmetic context
                XCTAssertNotNil(error)
            } else {
                XCTFail("Should have either value or error")
            }
        }
    }

    // MARK: - Type Error Propagation

    func testStringVariableInAddition() {
        scope.setValue("hello" as NSString, forVariableNamed: "str")

        let evaluator = iTermExpressionEvaluator(expressionString: "str + 5", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "String + number should fail")
            XCTAssertNotNil(eval.error, "Should produce type error")
            if let error = eval.error {
                let desc = error.localizedDescription.lowercased()
                XCTAssertTrue(
                    desc.contains("number") || desc.contains("string") || desc.contains("type") || desc.contains("expected") || desc.contains("nil") || desc.contains("operand"),
                    "Error message should mention type issue: \(error.localizedDescription)"
                )
            }
        }
    }

    func testArrayVariableInMultiplication() {
        scope.setValue([1, 2, 3] as NSArray, forVariableNamed: "arr")

        let evaluator = iTermExpressionEvaluator(expressionString: "arr * 2", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "Array * number should fail")
            XCTAssertNotNil(eval.error, "Should produce type error")
            if let error = eval.error {
                let desc = error.localizedDescription.lowercased()
                XCTAssertTrue(
                    desc.contains("number") || desc.contains("array") || desc.contains("type") || desc.contains("expected") || desc.contains("nil") || desc.contains("operand"),
                    "Error message should mention type issue: \(error.localizedDescription)"
                )
            }
        }
    }

    func testTypeErrorPropagationInComplexExpression() {
        scope.setValue("world" as NSString, forVariableNamed: "str")

        // (10 + str) * 5 - type error in subexpression should propagate
        let evaluator = iTermExpressionEvaluator(expressionString: "(10 + str) * 5", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "Type error in subexpression should propagate")
            XCTAssertNotNil(eval.error, "Should produce error from inner type mismatch")
        }
    }

    func testTypeErrorInTernaryCondition() {
        scope.setValue("test" as NSString, forVariableNamed: "str")

        // (str + 1) ? 10 : 20 - condition has type error
        let evaluator = iTermExpressionEvaluator(expressionString: "(str + 1) ? 10 : 20", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "Type error in condition should fail")
            XCTAssertNotNil(eval.error, "Should produce error from condition type mismatch")
        }
    }

    func testTypeErrorInTernaryTrueBranch() {
        scope.setValue("hello" as NSString, forVariableNamed: "str")

        // 1 ? (str * 2) : 20 - type error in true branch
        let evaluator = iTermExpressionEvaluator(expressionString: "1 ? (str * 2) : 20", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "Type error in true branch should fail when evaluated")
            XCTAssertNotNil(eval.error, "Should produce error from true branch type mismatch")
        }
    }

    // MARK: - Logical NOT Operator

    func testLogicalNotNumber() {
        // !5 should return 0 (false)
        let expr = Subexpression(logicalNot: Subexpression(number: 5))
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 0)
    }

    func testLogicalNotZero() {
        // !0 should return 1 (true)
        let expr = Subexpression(logicalNot: Subexpression(number: 0))
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 1)
    }

    func testLogicalNotString() {
        // !string should error
        scope.setValue("foo" as NSString, forVariableNamed: "x")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let expr = Subexpression(logicalNot: xExpr)
        XCTAssertThrowsError(try expr.synchronousValue(sideEffectsAllowed: false, scope: scope)) { error in
            // Verify error message mentions type mismatch
            XCTAssertTrue(error.localizedDescription.contains("non-NSNumber") ||
                         error.localizedDescription.contains("Logical not") ||
                         error.localizedDescription.contains("operand"))
        }
    }

    func testLogicalNotArray() {
        // !array should error
        scope.setValue([1, 2, 3] as NSArray, forVariableNamed: "arr")
        let arrExpr = Subexpression(indirectValue: IndirectValue(path: "arr"))
        let expr = Subexpression(logicalNot: arrExpr)
        XCTAssertThrowsError(try expr.synchronousValue(sideEffectsAllowed: false, scope: scope))
    }

    func testLogicalNotNull() {
        // !null should error
        scope.setValue(NSNull(), forVariableNamed: "x")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let expr = Subexpression(logicalNot: xExpr)
        XCTAssertThrowsError(try expr.synchronousValue(sideEffectsAllowed: false, scope: scope))
    }

    func testDoubleNot() {
        // !!1 should return 1
        let inner = Subexpression(logicalNot: Subexpression(number: 1))
        let expr = Subexpression(logicalNot: inner)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 1)
    }

    func testLogicalNotNegativeNumber() {
        // !(-5) should return 0 (any non-zero is truthy)
        let expr = Subexpression(logicalNot: Subexpression(number: -5))
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 0)
    }

    // MARK: - Equality Operators

    func testEqualityNumbersSame() {
        scope.setValue(NSNumber(value: 5), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 5), forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, equalTo: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, true)
    }

    func testEqualityNumbersDifferent() {
        scope.setValue(NSNumber(value: 5), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 3), forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, equalTo: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, false)
    }

    func testInequalityNumbers() {
        scope.setValue(NSNumber(value: 5), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 3), forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, notEqualTo: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, true)
    }

    func testEqualityStringsSame() {
        scope.setValue("foo" as NSString, forVariableNamed: "x")
        scope.setValue("foo" as NSString, forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, equalTo: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, true)
    }

    func testEqualityStringsDifferent() {
        scope.setValue("foo" as NSString, forVariableNamed: "x")
        scope.setValue("bar" as NSString, forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, equalTo: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, false)
    }

    func testEqualityArraysSame() {
        scope.setValue([1, 2, 3] as NSArray, forVariableNamed: "x")
        scope.setValue([1, 2, 3] as NSArray, forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, equalTo: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, true)
    }

    func testEqualityArraysDifferent() {
        scope.setValue([1, 2] as NSArray, forVariableNamed: "x")
        scope.setValue([1, 3] as NSArray, forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, equalTo: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, false)
    }

    func testEqualityDifferentTypes() {
        // 3 == "3" should return false (different types)
        scope.setValue(NSNumber(value: 3), forVariableNamed: "x")
        scope.setValue("3" as NSString, forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, equalTo: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, false)
    }

    func testInequalityDifferentTypes() {
        // 3 != "3" should return true (different types)
        scope.setValue(NSNumber(value: 3), forVariableNamed: "x")
        scope.setValue("3" as NSString, forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, notEqualTo: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, true)
    }

    func testEqualityNull() {
        // null == null should return true
        scope.setValue(NSNull(), forVariableNamed: "x")
        scope.setValue(NSNull(), forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, equalTo: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, true)
    }

    func testEqualityNaN() {
        // NaN == NaN should return false (IEEE 754)
        let nan1 = Subexpression(lhs: Subexpression(number: 0), dividedBy: Subexpression(number: 0))
        let nan2 = Subexpression(lhs: Subexpression(number: 0), dividedBy: Subexpression(number: 0))
        let expr = Subexpression(lhs: nan1, equalTo: nan2)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, false)
    }

    // MARK: - Relational Operators

    func testLessThanNumbers() {
        scope.setValue(NSNumber(value: 3), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 5), forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, lessThan: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, true)
    }

    func testLessThanNumbersFalse() {
        scope.setValue(NSNumber(value: 5), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 3), forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, lessThan: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, false)
    }

    func testGreaterThanNumbers() {
        scope.setValue(NSNumber(value: 5), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 3), forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, greaterThan: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, true)
    }

    func testLessThanOrEqualNumbers() {
        scope.setValue(NSNumber(value: 5), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 5), forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, lessThanOrEqual: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, true)
    }

    func testGreaterThanOrEqualNumbers() {
        scope.setValue(NSNumber(value: 5), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 5), forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, greaterThanOrEqual: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, true)
    }

    func testLessThanStrings() {
        scope.setValue("apple" as NSString, forVariableNamed: "x")
        scope.setValue("banana" as NSString, forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, lessThan: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, true)
    }

    func testGreaterThanStrings() {
        scope.setValue("banana" as NSString, forVariableNamed: "x")
        scope.setValue("apple" as NSString, forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, greaterThan: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, true)
    }

    func testLessThanArrays() {
        scope.setValue([1, 2] as NSArray, forVariableNamed: "x")
        scope.setValue([1, 3] as NSArray, forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, lessThan: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, true)
    }

    func testLessThanNull() {
        // null < 5 should return false
        scope.setValue(NSNull(), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 5), forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, lessThan: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, false)
    }

    func testLessOrEqualNull() {
        // null <= null should return true
        scope.setValue(NSNull(), forVariableNamed: "x")
        scope.setValue(NSNull(), forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, lessThanOrEqual: yExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, true)
    }

    func testLessThanDifferentTypes() {
        // 3 < "5" should error
        scope.setValue(NSNumber(value: 3), forVariableNamed: "x")
        scope.setValue("5" as NSString, forVariableNamed: "y")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let yExpr = Subexpression(indirectValue: IndirectValue(path: "y"))
        let expr = Subexpression(lhs: xExpr, lessThan: yExpr)
        XCTAssertThrowsError(try expr.synchronousValue(sideEffectsAllowed: false, scope: scope))
    }

    func testLessThanNaN() {
        // NaN < 5 should return false (IEEE 754)
        let nan = Subexpression(lhs: Subexpression(number: 0), dividedBy: Subexpression(number: 0))
        let expr = Subexpression(lhs: nan, lessThan: Subexpression(number: 5))
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, false)
    }

    func testGreaterThanInfinity() {
        // Infinity > 1000 should return true
        let inf = Subexpression(lhs: Subexpression(number: 1), dividedBy: Subexpression(number: 0))
        let expr = Subexpression(lhs: inf, greaterThan: Subexpression(number: 1000))
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.boolValue, true)
    }

    // MARK: - Logical Operators

    func testLogicalAndTrueTrue() {
        // 1 && 1 should return true (1)
        let expr = Subexpression(lhs: Subexpression(number: 1), logicalAnd: Subexpression(number: 1))
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 1)
    }

    func testLogicalAndTrueFalse() {
        // 1 && 0 should return false (0)
        let expr = Subexpression(lhs: Subexpression(number: 1), logicalAnd: Subexpression(number: 0))
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 0)
    }

    func testLogicalAndFalseFalse() {
        // 0 && 0 should return false (0)
        let expr = Subexpression(lhs: Subexpression(number: 0), logicalAnd: Subexpression(number: 0))
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 0)
    }

    func testLogicalAndFalseTrue() {
        // 0 && 1 should return false (0)
        let expr = Subexpression(lhs: Subexpression(number: 0), logicalAnd: Subexpression(number: 1))
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 0)
    }

    func testLogicalOrTrueTrue() {
        // 1 || 1 should return true (1)
        let expr = Subexpression(lhs: Subexpression(number: 1), logicalOr: Subexpression(number: 1))
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 1)
    }

    func testLogicalOrTrueFalse() {
        // 1 || 0 should return true (1)
        let expr = Subexpression(lhs: Subexpression(number: 1), logicalOr: Subexpression(number: 0))
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 1)
    }

    func testLogicalOrFalseFalse() {
        // 0 || 0 should return false (0)
        let expr = Subexpression(lhs: Subexpression(number: 0), logicalOr: Subexpression(number: 0))
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 0)
    }

    func testLogicalOrFalseTrue() {
        // 0 || 1 should return true (1)
        let expr = Subexpression(lhs: Subexpression(number: 0), logicalOr: Subexpression(number: 1))
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 1)
    }

    func testLogicalAndString() {
        // "foo" && 1 should error (strings not allowed in logical operations)
        scope.setValue("foo" as NSString, forVariableNamed: "x")
        let xExpr = Subexpression(indirectValue: IndirectValue(path: "x"))
        let expr = Subexpression(lhs: xExpr, logicalAnd: Subexpression(number: 1))
        XCTAssertThrowsError(try expr.synchronousValue(sideEffectsAllowed: false, scope: scope))
    }

    func testLogicalOrArray() {
        // [1,2] || 0 should error (arrays not allowed in logical operations)
        scope.setValue([1, 2] as NSArray, forVariableNamed: "arr")
        let arrExpr = Subexpression(indirectValue: IndirectValue(path: "arr"))
        let expr = Subexpression(lhs: arrExpr, logicalOr: Subexpression(number: 0))
        XCTAssertThrowsError(try expr.synchronousValue(sideEffectsAllowed: false, scope: scope))
    }

    func testLogicalAndWithNegativeNumbers() {
        // -5 && -3 should return true (both non-zero)
        let expr = Subexpression(lhs: Subexpression(number: -5), logicalAnd: Subexpression(number: -3))
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 1)
    }

    func testLogicalOrWithNegativeNumbers() {
        // -5 || 0 should return true
        let expr = Subexpression(lhs: Subexpression(number: -5), logicalOr: Subexpression(number: 0))
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 1)
    }

    func testLogicalAndPrecedence() {
        // Test that && has lower precedence than comparison
        // (5 > 3) && (2 < 4) should return true
        scope.setValue(NSNumber(value: 5), forVariableNamed: "a")
        scope.setValue(NSNumber(value: 3), forVariableNamed: "b")
        scope.setValue(NSNumber(value: 2), forVariableNamed: "c")
        scope.setValue(NSNumber(value: 4), forVariableNamed: "d")
        let aExpr = Subexpression(indirectValue: IndirectValue(path: "a"))
        let bExpr = Subexpression(indirectValue: IndirectValue(path: "b"))
        let cExpr = Subexpression(indirectValue: IndirectValue(path: "c"))
        let dExpr = Subexpression(indirectValue: IndirectValue(path: "d"))
        let lhs = Subexpression(lhs: aExpr, greaterThan: bExpr)
        let rhs = Subexpression(lhs: cExpr, lessThan: dExpr)
        let expr = Subexpression(lhs: lhs, logicalAnd: rhs)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 1)
    }

    func testLogicalOrPrecedence() {
        // Test || precedence with comparisons
        // (5 < 3) || (2 < 4) should return true
        scope.setValue(NSNumber(value: 5), forVariableNamed: "a")
        scope.setValue(NSNumber(value: 3), forVariableNamed: "b")
        scope.setValue(NSNumber(value: 2), forVariableNamed: "c")
        scope.setValue(NSNumber(value: 4), forVariableNamed: "d")
        let aExpr = Subexpression(indirectValue: IndirectValue(path: "a"))
        let bExpr = Subexpression(indirectValue: IndirectValue(path: "b"))
        let cExpr = Subexpression(indirectValue: IndirectValue(path: "c"))
        let dExpr = Subexpression(indirectValue: IndirectValue(path: "d"))
        let lhs = Subexpression(lhs: aExpr, lessThan: bExpr)
        let rhs = Subexpression(lhs: cExpr, lessThan: dExpr)
        let expr = Subexpression(lhs: lhs, logicalOr: rhs)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 1)
    }

    func testLogicalAndOrCombined() {
        // Test || has lower precedence than &&
        // true || false && false should parse as true || (false && false) = true
        let trueExpr = Subexpression(number: 1)
        let falseExpr1 = Subexpression(number: 0)
        let falseExpr2 = Subexpression(number: 0)
        let andExpr = Subexpression(lhs: falseExpr1, logicalAnd: falseExpr2)
        let expr = Subexpression(lhs: trueExpr, logicalOr: andExpr)
        let result = try! expr.synchronousValue(sideEffectsAllowed: false, scope: scope)
        XCTAssertEqual(result.intValue, 1)
    }
}
