//
//  EventTriggerEvaluatorTitleChangedTests.swift
//  iTerm2
//
//  Covers the Title Changed event trigger and the always-on built-in Codex
//  title-status trigger seeded by EventTriggerEvaluator.
//

import XCTest
@testable import iTerm2SharedARC

final class EventTriggerEvaluatorTitleChangedTests: XCTestCase {

    private var evaluator: EventTriggerEvaluator!
    private var fired: [(action: String, captures: [String])]!

    private let codexAction = "iTermCodexStatusTrigger"

    override func setUp() {
        super.setUp()
        evaluator = EventTriggerEvaluator(sessionDescription: "test")
        fired = []
        evaluator.fireTriggerHandler = { [weak self] trigger, captures, _ in
            self?.fired.append((action: trigger.action, captures: captures))
        }
    }

    override func tearDown() {
        evaluator = nil
        fired = nil
        super.tearDown()
    }

    private func loadUserTitleTrigger(titleRegex: String? = nil, disabled: Bool = false) {
        var eventParams: [String: Any] = [:]
        if let titleRegex {
            eventParams["titleRegex"] = titleRegex
        }
        let dict: [String: Any] = [
            "action": "AlertTrigger",
            "regex": "",
            "parameter": "test",
            "matchType": NSNumber(value: iTermTriggerMatchType.eventTitleChanged.rawValue),
            "disabled": NSNumber(value: disabled),
            "eventParams": eventParams
        ]
        evaluator.loadFromProfileArray([dict])
    }

    // MARK: - Built-in Codex trigger

    func testBuiltinCodexTriggerFiresOnEveryTitleChangeWithNoConfig() {
        evaluator.loadFromProfileArray([])
        evaluator.titleChanged(to: "\u{2807} working")
        XCTAssertEqual(fired.count, 1)
        XCTAssertEqual(fired.first?.action, codexAction)
        XCTAssertEqual(fired.first?.captures, ["\u{2807} working"])
    }

    func testBuiltinFiresRegardlessOfWhetherTitleLooksLikeCodex() {
        evaluator.loadFromProfileArray([])
        evaluator.titleChanged(to: "plain shell title")
        XCTAssertEqual(fired.count, 1)
        XCTAssertEqual(fired.first?.action, codexAction)
    }

    func testHasTitleChangedTriggerAlwaysTrue() {
        evaluator.loadFromProfileArray([])
        XCTAssertTrue(evaluator.hasTitleChangedTrigger)
    }

    func testDisabledEvaluatorSuppressesBuiltin() {
        evaluator.loadFromProfileArray([])
        evaluator.disabled = true
        evaluator.titleChanged(to: "anything")
        XCTAssertEqual(fired.count, 0)
    }

    // MARK: - User title-changed triggers (coexist with the built-in)

    func testUserTitleTriggerFiresAlongsideBuiltinWhenRegexMatches() {
        loadUserTitleTrigger(titleRegex: "error")
        evaluator.titleChanged(to: "an error happened")
        XCTAssertEqual(fired.count, 2)
        XCTAssertTrue(fired.contains { $0.action == codexAction })
        XCTAssertTrue(fired.contains { $0.action == "AlertTrigger" })
    }

    func testUserTitleTriggerSkippedWhenRegexDoesNotMatchButBuiltinStillFires() {
        loadUserTitleTrigger(titleRegex: "error")
        evaluator.titleChanged(to: "all good")
        XCTAssertEqual(fired.count, 1)
        XCTAssertEqual(fired.first?.action, codexAction)
    }

    func testUserTitleTriggerWithNoRegexFiresOnEveryTitle() {
        loadUserTitleTrigger()
        evaluator.titleChanged(to: "whatever")
        XCTAssertEqual(fired.filter { $0.action == "AlertTrigger" }.count, 1)
    }

    func testDisabledUserTriggerDoesNotFireButBuiltinDoes() {
        loadUserTitleTrigger(disabled: true)
        evaluator.titleChanged(to: "x")
        XCTAssertEqual(fired.count, 1)
        XCTAssertEqual(fired.first?.action, codexAction)
    }
}
