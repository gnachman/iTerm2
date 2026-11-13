//
//  BuiltInFunctionRegistryTests.swift
//  ModernTests
//
//  How iTermBuiltInFunctions finds a function for a call: by name, and by whether the argument
//  names passed are ones the function takes, with every required one present. Optional arguments
//  must not make registration cost grow with the number of ways they can be combined.
//

import XCTest
@testable import iTerm2SharedARC

final class BuiltInFunctionRegistryTests: XCTestCase {
    private func makeFunction(name: String,
                              required: [String],
                              optional: [String],
                              record: @escaping ([AnyHashable: Any]) -> Void = { _ in }) -> iTermBuiltInFunction {
        var arguments = [String: AnyClass]()
        for argument in required + optional {
            arguments[argument] = NSString.self
        }
        return iTermBuiltInFunction(name: name,
                                    arguments: arguments,
                                    optionalArguments: Set(optional),
                                    defaultValues: [:],
                                    context: [],
                                    sideEffectsPlaceholder: nil) { parameters, completion in
            record(parameters)
            completion(name as NSString, nil)
        }
    }

    private struct Outcome {
        var result: Any?
        var error: NSError?
    }

    private func call(_ registry: iTermBuiltInFunctions,
                      _ name: String,
                      namespace: String = "iterm2",
                      _ parameters: [String: Any]) -> Outcome {
        var outcome = Outcome()
        registry.callFunction(withName: name,
                              namespace: namespace,
                              parameters: parameters,
                              scope: iTermVariableScope(),
                              sideEffectsAllowed: true) { result, error in
            outcome = Outcome(result: result, error: error as NSError?)
        }
        return outcome
    }

    func testCallWithOnlyRequiredArguments() {
        let registry = iTermBuiltInFunctions()
        var seen = [[AnyHashable: Any]]()
        registry.register(makeFunction(name: "f", required: ["a"], optional: ["x", "y"]) { seen.append($0) },
                          namespace: "iterm2")
        let outcome = call(registry, "f", ["a": "1"])
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.result as? String, "f")
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?["a"] as? String, "1")
    }

    func testCallWithEverySubsetOfOptionalArguments() {
        let registry = iTermBuiltInFunctions()
        registry.register(makeFunction(name: "f", required: ["a"], optional: ["x", "y", "z"]), namespace: "iterm2")
        for optionals in [[], ["x"], ["y"], ["z"], ["x", "y"], ["x", "z"], ["y", "z"], ["x", "y", "z"]] {
            var parameters: [String: Any] = ["a": "1"]
            for name in optionals {
                parameters[name] = "v"
            }
            XCTAssertNil(call(registry, "f", parameters).error, "optionals=\(optionals)")
            XCTAssertTrue(registry.haveFunction(withName: "f", namespace: "iterm2", arguments: Array(parameters.keys)),
                          "optionals=\(optionals)")
        }
    }

    func testMissingRequiredArgumentIsUndeclared() {
        let registry = iTermBuiltInFunctions()
        registry.register(makeFunction(name: "f", required: ["a", "b"], optional: ["x"]), namespace: "iterm2")
        let outcome = call(registry, "f", ["a": "1", "x": "2"])
        XCTAssertEqual(outcome.error?.domain, "com.iterm2.bif")
        XCTAssertEqual(outcome.error?.code, 1)
        XCTAssertFalse(registry.haveFunction(withName: "f", namespace: "iterm2", arguments: ["a", "x"]))
    }

    func testUnknownArgumentIsUndeclared() {
        let registry = iTermBuiltInFunctions()
        registry.register(makeFunction(name: "f", required: ["a"], optional: ["x"]), namespace: "iterm2")
        let outcome = call(registry, "f", ["a": "1", "nope": "2"])
        XCTAssertEqual(outcome.error?.domain, "com.iterm2.bif")
        XCTAssertEqual(outcome.error?.code, 1)
        XCTAssertFalse(registry.haveFunction(withName: "f", namespace: "iterm2", arguments: ["a", "nope"]))
    }

    func testWrongNamespaceOrNameIsUndeclared() {
        let registry = iTermBuiltInFunctions()
        registry.register(makeFunction(name: "f", required: ["a"], optional: []), namespace: "iterm2")
        XCTAssertEqual(call(registry, "f", namespace: "other", ["a": "1"]).error?.code, 1)
        XCTAssertEqual(call(registry, "g", ["a": "1"]).error?.code, 1)
        XCTAssertFalse(registry.haveFunction(withName: "g", namespace: "iterm2", arguments: ["a"]))
    }

    func testTypeMismatchIsReported() {
        let registry = iTermBuiltInFunctions()
        registry.register(makeFunction(name: "f", required: ["a"], optional: ["x"]), namespace: "iterm2")
        let outcome = call(registry, "f", ["a": "1", "x": NSNumber(value: 3)])
        XCTAssertEqual(outcome.error?.code, 2)
    }

    func testNullOptionalArgumentIsAcceptedAndRemoved() {
        let registry = iTermBuiltInFunctions()
        var seen = [[AnyHashable: Any]]()
        registry.register(makeFunction(name: "f", required: ["a"], optional: ["x"]) { seen.append($0) },
                          namespace: "iterm2")
        XCTAssertNil(call(registry, "f", ["a": "1", "x": NSNull()]).error)
        XCTAssertNil(seen.first?["x"])
    }

    func testFunctionsWithTheSameNameAndDifferentRequiredArguments() {
        let registry = iTermBuiltInFunctions()
        registry.register(makeFunction(name: "f", required: ["a"], optional: []), namespace: "iterm2")
        registry.register(makeFunction(name: "f", required: ["b"], optional: ["x"]), namespace: "iterm2")
        XCTAssertNil(call(registry, "f", ["a": "1"]).error)
        XCTAssertNil(call(registry, "f", ["b": "1"]).error)
        XCTAssertNil(call(registry, "f", ["b": "1", "x": "2"]).error)
        XCTAssertEqual(call(registry, "f", ["a": "1", "x": "2"]).error?.code, 1)
    }

    func testSignatureLookupByQualifiedName() {
        let registry = iTermBuiltInFunctions()
        registry.register(makeFunction(name: "f", required: ["a"], optional: ["x"]), namespace: "iterm2")
        let signature = registry.signatureOfAnyRegisteredFunction(withName: "iterm2.f")
        XCTAssertTrue(signature?.hasPrefix("iterm2.f(") ?? false, signature ?? "nil")
        XCTAssertNil(registry.signatureOfAnyRegisteredFunction(withName: "iterm2.g"))
    }

    func testSignatureDictionaryListsAllArgumentsAndHidesPrivateFunctions() {
        let registry = iTermBuiltInFunctions()
        registry.register(makeFunction(name: "f", required: ["a"], optional: ["x"]), namespace: "iterm2")
        registry.register(makeFunction(name: "g", required: ["a"], optional: []), namespace: "iterm2.private")
        let dictionary = registry.registeredFunctionSignatureDictionary()
        XCTAssertEqual(dictionary["iterm2.f"].map { Set($0) }, ["a", "x"])
        XCTAssertNil(dictionary["iterm2.private.g"])
    }

    func testSavedStateRestoresWhatWasRegistered() {
        let registry = iTermBuiltInFunctions()
        registry.register(makeFunction(name: "f", required: ["a"], optional: []), namespace: "iterm2")
        let saved = registry.savedState()
        registry.register(makeFunction(name: "g", required: ["a"], optional: []), namespace: "iterm2")
        registry.register(makeFunction(name: "f", required: ["b"], optional: []), namespace: "iterm2")
        registry.restoreState(saved)
        XCTAssertTrue(registry.haveFunction(withName: "f", namespace: "iterm2", arguments: ["a"]))
        XCTAssertFalse(registry.haveFunction(withName: "f", namespace: "iterm2", arguments: ["b"]))
        XCTAssertFalse(registry.haveFunction(withName: "g", namespace: "iterm2", arguments: ["a"]))
    }

    // Registering used to add one entry per combination of optional arguments, so this function
    // alone would have needed 2^40 of them.
    func testManyOptionalArgumentsCostNothingToRegister() {
        let registry = iTermBuiltInFunctions()
        let optional = (0..<40).map { "opt\($0)" }
        registry.register(makeFunction(name: "f", required: ["a"], optional: optional), namespace: "iterm2")
        XCTAssertNil(call(registry, "f", ["a": "1"]).error)
        XCTAssertNil(call(registry, "f", ["a": "1", "opt7": "x", "opt39": "y"]).error)
        XCTAssertEqual(call(registry, "f", ["opt7": "x"]).error?.code, 1)
    }

    // MARK: - Methods

    // Sessions register methods the Python API calls by signature. run_coprocess takes an
    // optional argument (mute), and the API usually calls it without.
    func testMethodWithAnOptionalArgumentIsFoundWithAndWithoutIt() throws {
        let session = PTYSession(synthetic: false)!
        let registry = try XCTUnwrap(session.objectMethodRegistry())
        XCTAssertNotNil(registry.method(withSignature: "iterm2.run_coprocess(commandLine)"))
        XCTAssertNotNil(registry.method(withSignature: "iterm2.run_coprocess(commandLine,mute)"))
        XCTAssertNotNil(registry.method(withSignature: "iterm2.run_coprocess(mute,commandLine)"))
    }

    func testMethodIsNotFoundWithoutARequiredArgumentOrWithAnUnknownOne() throws {
        let session = PTYSession(synthetic: false)!
        let registry = try XCTUnwrap(session.objectMethodRegistry())
        XCTAssertNil(registry.method(withSignature: "iterm2.run_coprocess(mute)"))
        XCTAssertNil(registry.method(withSignature: "iterm2.run_coprocess()"))
        XCTAssertNil(registry.method(withSignature: "iterm2.run_coprocess(commandLine,nope)"))
        XCTAssertNil(registry.method(withSignature: "iterm2.no_such_method(commandLine)"))
        XCTAssertNil(registry.method(withSignature: "other.run_coprocess(commandLine)"))
    }

    func testMethodWithNoArgumentsIsFound() throws {
        let session = PTYSession(synthetic: false)!
        let registry = try XCTUnwrap(session.objectMethodRegistry())
        XCTAssertNotNil(registry.method(withSignature: "iterm2.get_coprocess()"))
        XCTAssertNil(registry.method(withSignature: "iterm2.get_coprocess(commandLine)"))
    }
}
