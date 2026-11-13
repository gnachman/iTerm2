//
//  EventTriggerEvaluatorFiringStateTests.swift
//  ModernTests
//
//  A session's event triggers can fire before its screen can perform actions (a split pane's new
//  session joins its tab before it is set up) and after it terminates (its tab's variables keep
//  changing while the rest of a closing window is torn down). PTYSession holds fires until the
//  session is set up and stops them when it terminates.
//

import XCTest
@testable import iTerm2SharedARC

final class EventTriggerEvaluatorFiringStateTests: XCTestCase, iTermObject {
    private var evaluator: EventTriggerEvaluator!
    private var scope: iTermVariableScope!
    private var fired: [[String]]!

    override func setUp() {
        super.setUp()
        scope = iTermVariableScope()
        scope.add(iTermVariables(context: .session, owner: self), toScopeNamed: nil)
        fired = []
        evaluator = EventTriggerEvaluator(sessionDescription: "test")
        evaluator.fireTriggerHandler = { [weak self] _, captures, _ in
            self?.fired.append(captures)
        }
        evaluator.variableScope = scope
    }

    override func tearDown() {
        evaluator = nil
        scope = nil
        fired = nil
        super.tearDown()
    }

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { nil }

    private func loadTriggers() {
        evaluator.loadFromProfileArray([
            [
                "action": "AlertTrigger",
                "regex": "",
                "parameter": "test",
                "matchType": NSNumber(value: iTermTriggerMatchType.eventVariableChanged.rawValue),
                "eventParams": [kTriggerVariableNameKey: "watched"]
            ],
            [
                "action": "AlertTrigger",
                "regex": "",
                "parameter": "test",
                "matchType": NSNumber(value: iTermTriggerMatchType.eventBellReceived.rawValue)
            ]
        ])
    }

    func testLiveByDefault() {
        loadTriggers()
        scope.setValue("1", forVariableNamed: "watched")
        XCTAssertEqual(fired, [["1", "watched"]])
    }

    func testHeldFiresAreDeliveredInOrderOnResume() {
        evaluator.holdFiring()
        loadTriggers()
        scope.setValue("1", forVariableNamed: "watched")
        evaluator.bellReceived()
        XCTAssertEqual(fired, [])

        evaluator.resumeFiring()
        XCTAssertEqual(fired, [["1", "watched"], []])

        scope.setValue("2", forVariableNamed: "watched")
        XCTAssertEqual(fired.last, ["2", "watched"])
        XCTAssertEqual(fired.count, 3)
    }

    func testStoppedDropsHeldAndLaterFires() {
        evaluator.holdFiring()
        loadTriggers()
        scope.setValue("1", forVariableNamed: "watched")
        evaluator.stopFiring()
        scope.setValue("2", forVariableNamed: "watched")
        evaluator.bellReceived()
        XCTAssertEqual(fired, [])
    }

    func testReloadWhileStoppedDoesNotObserve() {
        loadTriggers()
        evaluator.stopFiring()
        loadTriggers()
        scope.setValue("1", forVariableNamed: "watched")
        XCTAssertEqual(fired, [])
    }

    func testResumeAfterStopObservesAgain() {
        loadTriggers()
        evaluator.stopFiring()
        scope.setValue("1", forVariableNamed: "watched")
        evaluator.resumeFiring()
        XCTAssertEqual(fired, [])

        scope.setValue("2", forVariableNamed: "watched")
        XCTAssertEqual(fired, [["2", "watched"]])
    }
}
