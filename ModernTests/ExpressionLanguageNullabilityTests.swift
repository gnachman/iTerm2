//
//  ExpressionLanguageNullabilityTests.swift
//  ModernTests
//
//  Documents the nullability claims of the expression language and variables
//  that the nullability sanitizer found false (unit N7 of
//  docs/swift-migration/nullability-triage.md). The Objective-C returns nil,
//  and accepts nil, by design; these tests pin what Swift sees.
//  iTermVariablesIndex is not visible to Swift; its claim is pinned in
//  VariablesIndexNullabilityTests.m.
//

import XCTest
@testable import iTerm2SharedARC

final class ExpressionLanguageNullabilityTests: XCTestCase {
    private class Owner: NSObject, iTermObject {
        func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
        func objectScope() -> iTermVariableScope? { nil }
    }
    private let owner = Owner()

    // -[iTermVariableRecordingScope recordedReferences] maps over the names the
    // scope recorded, a set it creates on the first lookup, so it is nil when
    // nothing was looked up. While the claim was nonnull the bridge gave Swift
    // an empty array instead.
    func testRecordedReferencesIsNilWhenNothingWasLookedUp() {
        let scope = iTermVariableRecordingScope(scope: iTermVariableScope())
        let references = scope.recordedReferences
        XCTAssertNil(references)
    }

    func testRecordedReferencesListsWhatWasLookedUp() throws {
        let scope = iTermVariableRecordingScope(scope: iTermVariableScope())
        _ = scope.value(forVariableName: "user.name")
        let references = scope.recordedReferences
        XCTAssertEqual(try XCTUnwrap(references).map { $0.path }, ["user.name"])
    }

    // The parameters below are inward, so Swift could not pass nil to them
    // before they were optional: these tests compile only because they are,
    // and none of them could fail before at run time. Each passes nil only
    // where the body hands it to nothing that Apple declares nonnull.

    // A nil namespace means the global namespace (iTermQualifiedFunctionName).
    func testNilNamespaceFindsAndCallsAGlobalFunction() {
        let registry = iTermBuiltInFunctions()
        let function = iTermBuiltInFunction(name: "f",
                                            arguments: ["a": NSString.self],
                                            optionalArguments: [],
                                            defaultValues: [:],
                                            context: [],
                                            sideEffectsPlaceholder: nil) { _, completion in
            completion("called" as NSString, nil)
        }
        registry.register(function, namespace: nil)

        XCTAssertTrue(registry.haveFunction(withName: "f", namespace: nil, arguments: ["a"]))
        XCTAssertFalse(registry.haveFunction(withName: "f", namespace: "iterm2", arguments: ["a"]))

        var result: Any?
        var error: Error?
        registry.callFunction(withName: "f",
                              namespace: nil,
                              parameters: ["a": "1"],
                              scope: iTermVariableScope(),
                              sideEffectsAllowed: true) { value, callError in
            result = value
            error = callError
        }
        XCTAssertNil(error)
        XCTAssertEqual(result as? String, "called")

        // An unknown function's error names it without a namespace.
        registry.callFunction(withName: "g",
                              namespace: nil,
                              parameters: ["a": "1"],
                              scope: iTermVariableScope(),
                              sideEffectsAllowed: true) { value, callError in
            result = value
            error = callError
        }
        XCTAssertNil(result)
        let reason = (error as NSError?)?.localizedFailureReason ?? ""
        XCTAssertTrue(reason.contains("g(a)"), reason)
        XCTAssertFalse(reason.contains(".g(a)"), reason)
    }

    // The invocation is only text for logs and error messages.
    func testEvaluatorAcceptsANilInvocation() {
        let evaluator = iTermExpressionEvaluator(parsedExpression: iTermParsedExpression(string: "hello"),
                                                 invocation: nil,
                                                 scope: iTermVariableScope())
        var value: Any?
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { evaluator in
            value = evaluator.value
            XCTAssertNil(evaluator.error)
        }
        XCTAssertEqual(value as? String, "hello")
    }

    // Semantic history builds an evaluator from a profile's script, which is
    // nil for a profile never edited there. It evaluates to no value.
    func testEvaluatorOfANilInterpolatedStringHasNoValue() {
        let evaluator = iTermExpressionEvaluator(interpolatedString: nil, scope: iTermVariableScope())
        var completed = false
        var value: Any?
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { evaluator in
            completed = true
            value = evaluator.value
            XCTAssertNil(evaluator.error)
        }
        XCTAssertTrue(completed)
        XCTAssertNil(value)
    }

    func testParsedExpressionOfANilStringIsAString() {
        XCTAssertEqual(iTermParsedExpression(string: nil).expressionType, .string)
    }

    // An undefined variable's value is nil; the result is a Nil expression.
    func testParsedExpressionOfANilObjectIsNil() {
        XCTAssertEqual(iTermParsedExpression(object: nil, errorReason: "reason").expressionType, .nil)
    }

    // Session variables that are not set yet arrive as nil.
    func testSessionTitleToleratesNilNamesAndSize() {
        func title(_ components: iTermTitleComponents, profileName: String? = nil) -> String {
            return iTermSessionTitleBuiltInFunction.title(forSessionName: nil,
                                                          profileName: profileName,
                                                          job: nil,
                                                          commandLine: nil,
                                                          pwd: nil,
                                                          tty: nil,
                                                          user: nil,
                                                          host: nil,
                                                          aiTitle: nil,
                                                          homeDirectory: nil,
                                                          tmuxPane: nil,
                                                          iconName: nil,
                                                          windowName: nil,
                                                          tmuxWindowName: nil,
                                                          tmuxWindowTitle: nil,
                                                          rows: nil,
                                                          columns: nil,
                                                          components: components,
                                                          isWindowTitle: false)
        }
        XCTAssertEqual(title([.sessionName, .job, .commandLine, .workingDirectory, .TTY, .user, .host]), " ")
        XCTAssertEqual(title(.profileAndSessionName, profileName: "Prof"), "Prof")
        // The size component's separator is an em dash, U+2014.
        XCTAssertEqual(title(.size), "  \u{2014} 0\u{2715}0")
    }

    // Clearing a variable passes nil through iTermVariables' file-local
    // methods, whose parameters are now nullable; under the nullability
    // sanitizer this used to be reported (and was suppressed).
    func testClearingAVariable() {
        let variables = iTermVariables(context: [], owner: owner)
        variables.setValue("x", forVariableNamed: "a")
        XCTAssertEqual(variables.value(forVariableName: "a") as? String, "x")
        variables.setValue(nil, forVariableNamed: "a")
        XCTAssertNil(variables.value(forVariableName: "a"))
    }
}
