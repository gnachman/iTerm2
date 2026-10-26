//
//  TriggerReloadIdentityTests.swift
//  ModernTests
//
//  F-266: reloading a profile must keep each unchanged trigger's object (and
//  so its state, such as which partial line it already fired on). A
//  hand-written trigger, as in a Dynamic Profile, omits keys that Settings
//  always writes (regex, contentregex, matchType, …), and used to be matched
//  against the cached triggers by its raw dictionary, which never equals
//  the cached trigger's complete one, so every reload rebuilt it.
//

import XCTest
@testable import iTerm2SharedARC

final class TriggerReloadIdentityTests: XCTestCase {
    private func makeEvaluator() -> PTYTriggerEvaluator {
        return PTYTriggerEvaluator(queue: DispatchQueue.main)
    }

    func testHandWrittenTriggerSurvivesReload() throws {
        let handWritten: [String: Any] = [
            "regex": "QAPART",
            "action": "ScriptTrigger",
            "parameter": "true",
            "partial": true
        ]
        let evaluator = makeEvaluator()
        evaluator.load(fromProfileArray: [handWritten])
        let before = try XCTUnwrap(evaluator.triggers.first)

        evaluator.load(fromProfileArray: [handWritten])

        XCTAssertEqual(evaluator.triggers.count, 1)
        XCTAssertTrue(evaluator.triggers.first === before)
    }

    func testCompleteTriggerSurvivesReload() throws {
        let handWritten: [String: Any] = [
            "regex": "QAPART",
            "action": "ScriptTrigger",
            "parameter": "true",
            "partial": true
        ]
        let evaluator = makeEvaluator()
        evaluator.load(fromProfileArray: [handWritten])
        let before = try XCTUnwrap(evaluator.triggers.first)

        // The same trigger as Settings would save it.
        evaluator.load(fromProfileArray: [before.dictionaryValue()])

        XCTAssertTrue(evaluator.triggers.first === before)
    }

    func testChangedTriggerIsRebuilt() throws {
        let evaluator = makeEvaluator()
        evaluator.load(fromProfileArray: [["regex": "one", "action": "ScriptTrigger", "parameter": "true"]])
        let before = try XCTUnwrap(evaluator.triggers.first)

        evaluator.load(fromProfileArray: [["regex": "two", "action": "ScriptTrigger", "parameter": "true"]])

        let after = try XCTUnwrap(evaluator.triggers.first)
        XCTAssertFalse(after === before)
        XCTAssertEqual(after.regex, "two")
    }

    // Two identical triggers each keep their own object.
    func testDuplicateHandWrittenTriggersEachSurvive() throws {
        let handWritten: [String: Any] = ["regex": "x", "action": "ScriptTrigger", "parameter": "true"]
        let evaluator = makeEvaluator()
        evaluator.load(fromProfileArray: [handWritten, handWritten])
        let before = evaluator.triggers
        XCTAssertEqual(before.count, 2)
        XCTAssertFalse(before[0] === before[1])

        evaluator.load(fromProfileArray: [handWritten, handWritten])

        XCTAssertTrue(evaluator.triggers[0] === before[0])
        XCTAssertTrue(evaluator.triggers[1] === before[1])
    }
}
