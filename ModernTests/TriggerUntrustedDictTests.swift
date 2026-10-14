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
