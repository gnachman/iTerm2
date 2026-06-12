//
//  EventTriggerEvaluatorNotificationTests.swift
//  iTerm2
//
//  Created by George Nachman on 4/12/26.
//

import XCTest
@testable import iTerm2SharedARC

final class EventTriggerEvaluatorNotificationTests: XCTestCase {

    private var evaluator: EventTriggerEvaluator!
    private var firedCaptures: [[String]]!

    override func setUp() {
        super.setUp()
        evaluator = EventTriggerEvaluator(sessionDescription: "test")
        firedCaptures = []
        evaluator.fireTriggerHandler = { [weak self] _, captures, _ in
            self?.firedCaptures.append(captures)
        }
    }

    override func tearDown() {
        evaluator = nil
        firedCaptures = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func loadNotificationTrigger(messageRegex: String? = nil, disabled: Bool = false) {
        var eventParams: [String: Any] = [:]
        if let messageRegex {
            eventParams["messageRegex"] = messageRegex
        }
        let dict: [String: Any] = [
            "action": "AlertTrigger",
            "regex": "",
            "parameter": "test",
            "matchType": NSNumber(value: iTermTriggerMatchType.eventNotificationPosted.rawValue),
            "disabled": NSNumber(value: disabled),
            "eventParams": eventParams
        ]
        evaluator.loadFromProfileArray([dict])
    }

    // MARK: - Tests

    func testFiresForPlainMessage() {
        loadNotificationTrigger()
        evaluator.notificationPosted(messages: ["Hello world"])
        XCTAssertEqual(firedCaptures.count, 1)
        XCTAssertEqual(firedCaptures.first, ["Hello world"])
    }

    func testFiresWhenRegexMatchesMessage() {
        loadNotificationTrigger(messageRegex: "error")
        evaluator.notificationPosted(messages: ["An error occurred"])
        XCTAssertEqual(firedCaptures.count, 1)
    }

    func testDoesNotFireWhenRegexDoesNotMatch() {
        loadNotificationTrigger(messageRegex: "error")
        evaluator.notificationPosted(messages: ["Build succeeded"])
        XCTAssertEqual(firedCaptures.count, 0)
    }

    func testFiresWhenAnyMessageMatches() {
        loadNotificationTrigger(messageRegex: "warning")
        evaluator.notificationPosted(messages: ["Build Complete", "2 warning(s)", "Details"])
        XCTAssertEqual(firedCaptures.count, 1)
        XCTAssertEqual(firedCaptures.first, ["Build Complete", "2 warning(s)", "Details"])
    }

    func testDoesNotFireWhenNoMessageMatches() {
        loadNotificationTrigger(messageRegex: "error")
        evaluator.notificationPosted(messages: ["Build Complete", "No issues", "Done"])
        XCTAssertEqual(firedCaptures.count, 0)
    }

    func testEmptyRegexMatchesAll() {
        loadNotificationTrigger(messageRegex: "")
        evaluator.notificationPosted(messages: ["anything"])
        XCTAssertEqual(firedCaptures.count, 1)
    }

    func testNoRegexMatchesAll() {
        loadNotificationTrigger()
        evaluator.notificationPosted(messages: ["anything"])
        XCTAssertEqual(firedCaptures.count, 1)
    }

    func testDisabledTriggerDoesNotFire() {
        loadNotificationTrigger(disabled: true)
        evaluator.notificationPosted(messages: ["Hello"])
        XCTAssertEqual(firedCaptures.count, 0)
    }

    func testDisabledEvaluatorDoesNotFire() {
        loadNotificationTrigger()
        evaluator.disabled = true
        evaluator.notificationPosted(messages: ["Hello"])
        XCTAssertEqual(firedCaptures.count, 0)
    }

    func testHasNotificationPostedTrigger() {
        XCTAssertFalse(evaluator.hasNotificationPostedTrigger)
        loadNotificationTrigger()
        XCTAssertTrue(evaluator.hasNotificationPostedTrigger)
    }

    func testCapturedStringsContainsAllMessages() {
        loadNotificationTrigger()
        evaluator.notificationPosted(messages: ["Title", "Body", "Subtitle"])
        XCTAssertEqual(firedCaptures.count, 1)
        XCTAssertEqual(firedCaptures.first, ["Title", "Body", "Subtitle"])
    }
}
