//
//  SwiftyStringTextFieldRenameTests.swift
//  ModernTests
//
//  The Session Status tool's name label evaluates
//  \(iterm2.private.session_name(session: id)), whose “name” and
//  “profileName” arguments are default values the built-in function reads
//  from the scope only after the explicit “session” argument has been
//  evaluated asynchronously. Those late reads must still be observed, or
//  the label stops following a session rename.
//

import XCTest
@testable import iTerm2SharedARC

final class SwiftyStringTextFieldRenameTests: XCTestCase, iTermObject {
    // Localization unneeded
    private let interpolatedString = #"\(iterm2.private.session_name(session: id))"#

    private var scopes = [iTermVariableScope]()
    private var frames = [iTermVariables]()

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { scopes.first }

    override func tearDown() {
        scopes.removeAll()
        frames.removeAll()
        super.tearDown()
    }

    private func makeSessionScope(id: String, name: String) -> iTermVariableScope {
        let scope = iTermVariableScope()
        let variables = iTermVariables(context: [.session], owner: self)
        scope.add(variables, toScopeNamed: nil)
        scope.setValue(id, forVariableNamed: iTermVariableKeySessionID)
        scope.setValue(name, forVariableNamed: iTermVariableKeySessionName)
        scopes.append(scope)
        frames.append(variables)
        return scope
    }

    // Waits for the field to display `value`. The predicate is the update
    // itself, not a delay; the timeout only bounds a failure.
    private func waitUntil(_ field: NSTextField, shows value: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in field.stringValue == value },
            object: nil)
        let result = XCTWaiter().wait(for: [expectation], timeout: 10)
        XCTAssertEqual(result, .completed,
                       "Field shows “\(field.stringValue)”, expected “\(value)”",
                       file: file, line: line)
    }

    // Builds the evaluator inside its own autorelease pool, as a table
    // reload in the app does. Otherwise references left over from the
    // first (synchronous) evaluation survive in the test method's pool
    // and mask the bug.
    private func set(_ field: iTermSwiftyStringTextField, scope: iTermVariableScope) {
        autoreleasepool {
            field.set(interpolatedString: interpolatedString, scope: scope)
        }
    }

    // Waits for the field's evaluator to observe the session's “name”
    // variable, so a rename that follows is guaranteed to be noticed.
    // Without the fix it never holds, so the test fails deterministically
    // rather than racing the rename against the evaluation.
    private func waitUntilObservingName(_ field: iTermSwiftyStringTextField, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                (field.swiftyString?.refs ?? []).contains { $0.path == iTermVariableKeySessionName }
            },
            object: nil)
        let result = XCTWaiter().wait(for: [expectation], timeout: 10)
        XCTAssertEqual(result, .completed,
                       "Evaluator observes only \((field.swiftyString?.refs ?? []).map(\.path))",
                       file: file, line: line)
    }

    func test_renameUpdatesTheField() {
        let scope = makeSessionScope(id: "S1", name: "-zsh")
        let field = iTermSwiftyStringTextField(labelWithString: "")
        set(field, scope: scope)
        waitUntil(field, shows: "-zsh")
        waitUntilObservingName(field)

        scope.setValue("QA45C (-zsh)", forVariableNamed: iTermVariableKeySessionName)
        waitUntil(field, shows: "QA45C (-zsh)")
    }

    // While an asynchronous evaluation is in flight, its partial
    // dependencies must not replace ones an earlier evaluation already
    // established, or a rename landing in that window is lost. set()
    // runs a synchronous evaluation (which reads “name”) and then starts
    // an asynchronous one that has not read it yet when set() returns.
    func test_inFlightEvaluationKeepsEstablishedDependencies() {
        let scope = makeSessionScope(id: "S1", name: "-zsh")
        let field = iTermSwiftyStringTextField(labelWithString: "")
        set(field, scope: scope)
        let paths = (field.swiftyString?.refs ?? []).map(\.path)
        XCTAssertTrue(paths.contains(iTermVariableKeySessionName),
                      "In-flight evaluation dropped dependencies; observing only \(paths)")
    }

    // A table reload re-sets the cell with the same string and scope,
    // which reuses the evaluator. The reused evaluator must keep
    // following renames, including after a rename-triggered
    // reevaluation, which is asynchronous only.
    func test_renameAfterReuseUpdatesTheField() {
        let scope = makeSessionScope(id: "S1", name: "-zsh")
        let field = iTermSwiftyStringTextField(labelWithString: "")
        set(field, scope: scope)
        waitUntil(field, shows: "-zsh")
        waitUntilObservingName(field)
        let evaluator = field.swiftyString
        set(field, scope: scope)
        XCTAssertTrue(field.swiftyString === evaluator)

        scope.setValue("First", forVariableNamed: iTermVariableKeySessionName)
        waitUntil(field, shows: "First")
        waitUntilObservingName(field)

        set(field, scope: scope)
        XCTAssertTrue(field.swiftyString === evaluator)
        scope.setValue("Second", forVariableNamed: iTermVariableKeySessionName)
        waitUntil(field, shows: "Second")
    }

    // A recycled cell moved to a different session with the same
    // interpolated string shows, and follows, the new session's name.
    func test_recycledFieldFollowsTheNewSession() {
        let first = makeSessionScope(id: "S1", name: "one")
        let second = makeSessionScope(id: "S2", name: "two")
        let field = iTermSwiftyStringTextField(labelWithString: "")
        set(field, scope: first)
        waitUntil(field, shows: "one")

        set(field, scope: second)
        waitUntil(field, shows: "two")
        waitUntilObservingName(field)

        first.setValue("one renamed", forVariableNamed: iTermVariableKeySessionName)
        second.setValue("two renamed", forVariableNamed: iTermVariableKeySessionName)
        waitUntil(field, shows: "two renamed")
    }

    // Isolates the dependencies an asynchronous evaluation reads after it
    // starts: here the synchronous evaluation never reads “name”, so only
    // installing the asynchronous evaluation's dependencies when it
    // completes can make the evaluator observe it.
    func test_asyncOnlyReadIsObserved() {
        let scope = makeSessionScope(id: "S1", name: "before")
        let evaluator = LateReadEvaluator(string: "unused",
                                          scope: scope,
                                          sideEffectsAllowed: false,
                                          observer: { value, _ in value })
        let observing = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                evaluator.refs.contains { $0.path == iTermVariableKeySessionName }
            },
            object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [observing], timeout: 10), .completed,
                       "Evaluator observes only \(evaluator.refs.map(\.path))")

        scope.setValue("after", forVariableNamed: iTermVariableKeySessionName)
        let updated = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in evaluator.evaluationResult as? String == "after" },
            object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [updated], timeout: 10), .completed)
        evaluator.invalidate()
    }
}

// Reads “id” on every evaluation but reads “name” only when evaluating
// asynchronously, and only on a later main-queue pass, the way a built-in
// function reads its default arguments after its explicit ones.
private final class LateReadEvaluator: iTermGenericEvaluator {
    override func evaluateSynchronously(_ synchronously: Bool,
                                        sideEffectsAllowed: Bool,
                                        with scope: iTermVariableScope,
                                        completion: @escaping (Any?, Error?, Set<String>) -> Void) {
        _ = scope.value(forVariableName: iTermVariableKeySessionID)
        if synchronously {
            completion("sync", nil, [])
            return
        }
        DispatchQueue.main.async {
            completion(scope.value(forVariableName: iTermVariableKeySessionName), nil, [])
        }
    }

    override func expressionEvaluator(using scope: iTermVariableScope) -> iTermExpressionEvaluator {
        it_fatalError("Not used")
    }
}
