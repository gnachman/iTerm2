//
//  TriggerUntrustedDictTests.swift
//  ModernTests
//
//  F-203: a trigger dictionary with no "regex" key (or a non-string one) used to
//  crash in -[Trigger setRegex:] because NSRegularExpression was given a nil
//  pattern. Event triggers in hand-written Dynamic Profiles commonly omit it.
//

import XCTest
@testable import iTerm2SharedARC

final class TriggerUntrustedDictTests: XCTestCase {
    private func notificationTriggerDict(regex: Any?) -> [String: Any] {
        var dict: [String: Any] = [
            "action": "AlertTrigger",
            "parameter": "test",
            "matchType": NSNumber(value: iTermTriggerMatchType.eventNotificationPosted.rawValue)
        ]
        if let regex {
            dict["regex"] = regex
        }
        return dict
    }

    // An event trigger does not use its regex, so omitting it must not stop it from loading
    // or firing.
    func testEventTriggerWithoutRegexLoadsAndFires() {
        let evaluator = EventTriggerEvaluator(sessionDescription: "test")
        var fired: [[String]] = []
        evaluator.fireTriggerHandler = { _, captures, _ in
            fired.append(captures)
        }
        evaluator.loadFromProfileArray([notificationTriggerDict(regex: nil)])
        XCTAssertTrue(evaluator.hasNotificationPostedTrigger)
        evaluator.notificationPosted(messages: ["Hello"])
        XCTAssertEqual(fired, [["Hello"]])
    }

    // A regex trigger with no regex is treated like one saved from Settings with an empty
    // regex field, which is stored as "".
    func testRegexTriggerWithoutRegexGetsEmptyRegex() {
        let dict: [String: Any] = [
            "action": "AlertTrigger",
            "parameter": "test",
            "matchType": NSNumber(value: iTermTriggerMatchType.regex.rawValue)
        ]
        guard let trigger = Trigger(fromUntrustedDict: dict) else {
            XCTFail("trigger should load")
            return
        }
        XCTAssertEqual(trigger.regex, "")
        XCTAssertEqual(trigger.dictionaryValue()["regex"] as? String, "")
    }

    // A regex of the wrong type is untrusted input and must be treated the same as a missing one.
    func testNonStringRegexGetsEmptyRegex() {
        guard let trigger = Trigger(fromUntrustedDict: notificationTriggerDict(regex: NSNumber(value: 5))) else {
            XCTFail("trigger should load")
            return
        }
        XCTAssertEqual(trigger.regex, "")
    }
}

// T-40: a trigger's parameter in an untrusted dictionary (e.g., a hand-written Dynamic Profile)
// was stored without a type check, so an array or dictionary there crashed Bounce and Mark
// triggers when they called -intValue on it, and Invoke Script Function used it as a string.
final class TriggerUntrustedParameterTests: XCTestCase {
    private func trigger(action: String, parameter: Any) -> Trigger? {
        return Trigger(fromUntrustedDict: ["action": action,
                                           "regex": "x",
                                           "parameter": parameter])
    }

    private let malformedParameters: [Any] = [
        ["a", "b"] as NSArray,
        ["k": "v"] as NSDictionary,
        NSNull()
    ]

    func testMalformedParametersAreDropped() {
        for action in ["BounceTrigger", "MarkTrigger", "iTermRPCTrigger", "SendTextTrigger", "HighlightTrigger"] {
            for parameter in malformedParameters {
                guard let trigger = trigger(action: action, parameter: parameter) else {
                    XCTFail("\(action) should load")
                    continue
                }
                XCTAssertNil(trigger.param, "\(action) with \(parameter)")
                // These used to crash for Bounce and Mark.
                _ = trigger.description
                _ = trigger.paramAttributedString()
            }
        }
    }

    func testNumberParameterIsKept() {
        guard let bounce = trigger(action: "BounceTrigger", parameter: NSNumber(value: 1)) else {
            XCTFail("trigger should load")
            return
        }
        XCTAssertEqual(bounce.param as? NSNumber, NSNumber(value: 1))
        XCTAssertEqual(bounce.description, "Bounce dock icon once")

        guard let mark = trigger(action: "MarkTrigger", parameter: NSNumber(value: 1)) else {
            XCTFail("trigger should load")
            return
        }
        XCTAssertEqual(mark.description, "Set Mark and stop scrolling")
    }

    // A string-parameter trigger given a number uses the number's text rather than nothing.
    func testNumberParameterBecomesTextForStringTriggers() {
        guard let sendText = trigger(action: "SendTextTrigger", parameter: NSNumber(value: 42)) else {
            XCTFail("trigger should load")
            return
        }
        let promise = sendText.paramWithBackreferencesReplaced(withValues: [],
                                                               absLine: 0,
                                                               scope: UnusedTriggerScopeProvider(),
                                                               useInterpolation: false)
        XCTAssertEqual(promise.maybeValue as String?, "42")
    }

    func testStringParameterIsKept() {
        guard let mark = trigger(action: "MarkTrigger", parameter: "1") else {
            XCTFail("trigger should load")
            return
        }
        XCTAssertEqual(mark.param as? String, "1")
        XCTAssertEqual(mark.description, "Set Mark and stop scrolling")

        guard let rpc = trigger(action: "iTermRPCTrigger", parameter: "f()") else {
            XCTFail("trigger should load")
            return
        }
        XCTAssertEqual(rpc.param as? String, "f()")
    }
}

private final class UnusedTriggerScopeProvider: NSObject, iTermTriggerScopeProvider, iTermTriggerCallbackScheduler {
    func performBlock(scope block: @escaping (iTermVariableScope, iTermObject) -> Void) {
        XCTFail("scope should not be needed without interpolation")
    }

    func triggerCallbackScheduler() -> iTermTriggerCallbackScheduler {
        return self
    }

    func scheduleTriggerCallback(_ block: @escaping () -> Void) {
        block()
    }
}
