//
//  PTYTriggerEvaluatorEventTriggerExclusionTests.swift
//  ModernTests
//
//  Issue 13245: event triggers (match type >= 100, such as the Enter and Exit
//  Workgroup triggers the Claude Code integration adds) are fired by
//  EventTriggerEvaluator. PTYTriggerEvaluator must not also keep them: it would
//  try them against every line of output, where they can never match, and
//  their presence alone makes it build the line's string on every cursor move
//  and lets the slow-triggers warning fire. Edit Session pairs the evaluator's
//  per-trigger stats with the profile's triggers, so it has to skip the ones
//  the evaluator leaves out.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYTriggerEvaluatorEventTriggerExclusionTests: XCTestCase {
    // The same shape as the Enter Workgroup trigger from the issue.
    private let enterWorkgroupTrigger: [String: Any] = [
        "action": "iTermEnterWorkgroupTrigger",
        "matchType": NSNumber(value: iTermTriggerMatchType.eventJobStarted.rawValue),
        "parameter": "builtin.claudeCode",
        "partial": false,
        "eventParams": ["jobName": "claude"],
        "contentregex": "",
        "regex": "",
        "disabled": false
    ]

    // The same shape as the Exit Workgroup trigger from the issue.
    private let exitWorkgroupTrigger: [String: Any] = [
        "action": "iTermExitWorkgroupTrigger",
        "matchType": NSNumber(value: iTermTriggerMatchType.eventJobEnded.rawValue),
        "parameter": "",
        "partial": false,
        "eventParams": ["jobName": "claude", "leaderOnly": true],
        "contentregex": "",
        "regex": "",
        "disabled": false
    ]

    private let regexTrigger: [String: Any] = [
        "regex": "QAREGEX",
        "action": "ScriptTrigger",
        "parameter": "true"
    ]

    private func makeEvaluator() -> PTYTriggerEvaluator {
        return PTYTriggerEvaluator(queue: DispatchQueue.main)
    }

    func testEventTriggersAreNotEvaluatedAgainstLines() {
        let evaluator = makeEvaluator()
        evaluator.load(fromProfileArray: [enterWorkgroupTrigger, exitWorkgroupTrigger])

        XCTAssertEqual(evaluator.triggers.count, 0)
        XCTAssertFalse(evaluator.haveTriggersOrExpectations)
    }

    func testRegexTriggerIsKeptAlongsideEventTriggers() {
        let evaluator = makeEvaluator()
        evaluator.load(fromProfileArray: [enterWorkgroupTrigger, regexTrigger, exitWorkgroupTrigger])

        XCTAssertEqual(evaluator.triggers.map { $0.regex }, ["QAREGEX"])
        XCTAssertTrue(evaluator.haveTriggersOrExpectations)
    }

    func testEventEvaluatorStillLoadsEventTriggers() {
        let evaluator = EventTriggerEvaluator(sessionDescription: "test")
        evaluator.loadFromProfileArray([enterWorkgroupTrigger, regexTrigger, exitWorkgroupTrigger])

        XCTAssertTrue(evaluator.hasJobStartedTrigger)
    }

    // Edit Session pairs trigger stats with the profile's triggers by index.
    func testStatsIndexesSkipEventTriggers() {
        let dicts = [enterWorkgroupTrigger, regexTrigger, exitWorkgroupTrigger, regexTrigger].map { $0 as NSDictionary }
        let evaluator = makeEvaluator()
        evaluator.load(fromProfileArray: dicts)

        let indexes = PTYSession.indexesOfEvaluatedTriggers(in: dicts)

        XCTAssertEqual(indexes, [1, 3])
        XCTAssertEqual(indexes.count, evaluator.triggers.count)
    }

    func testStatsAreAddedToEvaluatedTriggersOnly() throws {
        let dicts = [enterWorkgroupTrigger, regexTrigger].map { $0 as NSDictionary }
        let stat = iTermHistogram()
        stat.addValue(5)

        let result = try XCTUnwrap(PTYSession.triggerDicts(dicts, addingStats: [stat]))

        XCTAssertNil(result[0][kTriggerPerformanceKey])
        XCTAssertNotNil(result[1][kTriggerPerformanceKey])
    }

    func testStatsThatDoNotLineUpAreDropped() {
        let dicts = [enterWorkgroupTrigger, regexTrigger].map { $0 as NSDictionary }

        XCTAssertNil(PTYSession.triggerDicts(dicts, addingStats: []))
    }
}
