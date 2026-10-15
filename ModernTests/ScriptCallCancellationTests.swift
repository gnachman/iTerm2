//
//  ScriptCallCancellationTests.swift
//  ModernTests
//
//  A built-in method that waits on the user (load_url and browser_eval_js wait on a
//  permission prompt) must learn when the script call that invoked it times out, so a
//  late approval doesn't act after the script was told the call failed. These drive a
//  method call through iTermScriptFunctionCall, the path InvokeFunctionRequest takes.
//

import XCTest
@testable import iTerm2SharedARC

@objc(iTermScriptCallCancellationTestTarget)
final class ScriptCallCancellationTestTarget: NSObject, iTermObject {
    private let scope = iTermVariableScope()
    private var registry: iTermBuiltInFunctions?
    private(set) var variables: iTermVariables!

    // Saved by hold so a test can finish the call or inspect the cancellation.
    var heldCompletion: ((Any?, Error?) -> Void)?
    var heldCancellation: iTermScriptCallCancellation?
    var holdCount = 0
    var onHold: (() -> Void)?

    override init() {
        super.init()
        variables = iTermVariables(context: [], owner: self)
        scope.add(variables, toScopeNamed: nil)
        let registry = iTermBuiltInFunctions()
        let method = iTermBuiltInMethod(name: "hold",
                                        defaultValues: [:],
                                        types: [:],
                                        optionalArguments: Set(),
                                        context: [],
                                        sideEffectsPlaceholder: nil,
                                        target: self,
                                        action: #selector(hold(withCompletion:cancellation:)))
        registry.register(method, namespace: "test")
        self.registry = registry
    }

    @objc func hold(withCompletion completion: @escaping (Any?, Error?) -> Void,
                    cancellation: iTermScriptCallCancellation?) {
        holdCount += 1
        heldCompletion = completion
        heldCancellation = cancellation
        onHold?()
    }

    // MARK: - iTermObject

    func objectMethodRegistry() -> iTermBuiltInFunctions? { registry }
    func objectScope() -> iTermVariableScope? { scope }
}

final class ScriptCallCancellationTests: XCTestCase {
    // The variables index holds its values weakly, so the entry goes away with the target.
    private let receiver = "ScriptCallCancellationTests-" + UUID().uuidString
    private var target: ScriptCallCancellationTestTarget!

    override func setUp() {
        super.setUp()
        target = ScriptCallCancellationTestTarget()
        // Registers the target under `receiver`, the way sessions register under their IDs.
        _ = target.variables.setValue(receiver, forVariableNamed: "id")
        target.variables.primaryKey = "id"
    }

    override func tearDown() {
        target = nil
        super.tearDown()
    }

    private func callHold(timeout: TimeInterval,
                          completion: @escaping (Any?, Error?) -> Void) {
        iTermScriptFunctionCall.callMethod("test.hold()",
                                           receiver: receiver,
                                           timeout: timeout,
                                           sideEffectsAllowed: true,
                                           retainSelf: true) { value, error, _ in
            completion(value, error)
        }
    }

    func testMethodIsToldWhenTheCallTimesOut() {
        let held = expectation(description: "method invoked")
        target.onHold = { held.fulfill() }
        let timedOut = expectation(description: "call timed out")
        callHold(timeout: 0.05) { _, error in
            let nsError = error as NSError?
            XCTAssertEqual(nsError?.domain, "com.iterm2.call")
            XCTAssertEqual(nsError?.code, 2)
            timedOut.fulfill()
        }
        wait(for: [held, timedOut], timeout: 30)
        XCTAssertEqual(target.holdCount, 1)
        XCTAssertEqual(target.heldCancellation?.isCancelled, true)
    }

    func testCancellationIsNotPartOfTheMethodSignatureAndStaysClearOnSuccess() {
        let held = expectation(description: "method invoked")
        target.onHold = { held.fulfill() }
        let finished = expectation(description: "call finished")
        callHold(timeout: 30) { value, error in
            XCTAssertNil(error)
            XCTAssertEqual(value as? String, "done")
            finished.fulfill()
        }
        wait(for: [held], timeout: 30)
        XCTAssertNotNil(target.heldCancellation)
        XCTAssertEqual(target.heldCancellation?.isCancelled, false)
        target.heldCompletion?("done", nil)
        wait(for: [finished], timeout: 30)
        XCTAssertEqual(target.heldCancellation?.isCancelled, false)
    }
}
