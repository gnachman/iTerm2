//
//  SetStatusBuiltInFunctionTests.swift
//  ModernTests
//
//  The contract between it2 and iTerm2 for the session status built-ins:
//  what set_status makes of its arguments, and the JSON that the setters and
//  get_session_status answer with, which cc-status parses without a schema of
//  its own.
//

import XCTest
@testable import iTerm2SharedARC

final class SetStatusBuiltInFunctionTests: XCTestCase {
    // MARK: - Arguments

    func testTurnOpenArgumentSetsTheFlag() throws {
        let open = try SetStatusBuiltInFunction.update(from: ["turn_open": NSNumber(value: true)])
        XCTAssertEqual(open.turnOpenPresence, .set)
        XCTAssertTrue(open.turnOpen)

        let closed = try SetStatusBuiltInFunction.update(from: ["turn_open": NSNumber(value: false)])
        XCTAssertEqual(closed.turnOpenPresence, .set)
        XCTAssertFalse(closed.turnOpen)
    }

    func testOmittedTurnOpenLeavesTheFlagAlone() throws {
        let update = try SetStatusBuiltInFunction.update(from: ["status": "working"])
        XCTAssertEqual(update.turnOpenPresence, .notSet)
        XCTAssertEqual(update.statusPresence, .set)
        XCTAssertEqual(update.status, "working")
    }

    func testDeltaArgumentBecomesADelta() throws {
        let update = try SetStatusBuiltInFunction.update(from: ["background_tasks_delta": NSNumber(value: -1)])
        XCTAssertEqual(update.backgroundTasksPresence, .notSet)
        XCTAssertEqual(update.backgroundTasksDelta, -1)
    }

    func testCountAndDeltaTogetherAreRefused() {
        XCTAssertThrowsError(try SetStatusBuiltInFunction.update(from: [
            "background_tasks": NSNumber(value: 2),
            "background_tasks_delta": NSNumber(value: 1),
        ]))
    }

    /// cc-status writes idle on the strength of a status it read a moment
    /// earlier. The arguments carry what it assumed so iTerm2 can drop the
    /// update if a prompt reopened the turn in between.
    func testPreconditionArgumentsBecomePreconditions() throws {
        let update = try SetStatusBuiltInFunction.update(from: [
            "status": "idle",
            "if_turn_open": NSNumber(value: false),
            "if_background_tasks": NSNumber(value: 0),
        ])
        XCTAssertEqual(update.requiredTurnOpen, NSNumber(value: false))
        XCTAssertEqual(update.requiredBackgroundTasks, NSNumber(value: 0))
    }

    func testOmittedPreconditionsLeaveNone() throws {
        let update = try SetStatusBuiltInFunction.update(from: ["status": "idle"])
        XCTAssertNil(update.requiredTurnOpen)
        XCTAssertNil(update.requiredBackgroundTasks)
    }

    func testInvalidColorIsRefused() {
        XCTAssertThrowsError(try SetStatusBuiltInFunction.update(from: ["dot_color": "orange"]))
        XCTAssertThrowsError(try SetStatusBuiltInFunction.update(from: ["text_color": "#12"]))
    }

    // MARK: - Result

    /// Serializes the way iTermAPIHelper does for an invoke_function result,
    /// then parses the way cc-status does.
    private func roundTrip(_ status: iTermSessionTabStatus?) throws -> [String: Any] {
        let dictionary = SetStatusBuiltInFunction.statusDictionary(for: status)
        let json = try XCTUnwrap(JSONSerialization.it_jsonString(for: dictionary))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    func testResultBeforeAnyStatusIsAllUnknown() throws {
        let parsed = try roundTrip(nil)
        XCTAssertEqual(Set(parsed.keys),
                       ["status", "text_color", "dot_color", "detail", "background_tasks", "turn_open"])
        XCTAssertTrue(parsed["status"] is NSNull)
        XCTAssertTrue(parsed["text_color"] is NSNull)
        XCTAssertTrue(parsed["dot_color"] is NSNull)
        XCTAssertTrue(parsed["detail"] is NSNull)
        XCTAssertEqual(parsed["background_tasks"] as? Int, 0)
        XCTAssertTrue(parsed["turn_open"] is NSNull)
        // cc-status reads an unset turn as unknown, never as closed.
        XCTAssertNil(parsed["turn_open"] as? Bool)
    }

    func testResultCarriesEveryField() throws {
        let status = iTermSessionTabStatus(sessionID: "s")
        let update = VT100TabStatusUpdate()
        update.statusPresence = .set
        update.status = "working"
        update.detailPresence = .set
        update.detail = "1 background task running"
        update.backgroundTasksPresence = .set
        update.backgroundTasks = 1
        update.turnOpenPresence = .set
        update.turnOpen = false
        _ = status.apply(update)

        let parsed = try roundTrip(status)
        XCTAssertEqual(parsed["status"] as? String, "working")
        XCTAssertEqual(parsed["detail"] as? String, "1 background task running")
        XCTAssertEqual(parsed["background_tasks"] as? Int, 1)
        // A Swift Bool must come out as JSON false, not 0: cc-status asks
        // for a Bool and would otherwise read the closed turn as unknown.
        XCTAssertEqual(parsed["turn_open"] as? Bool, false)
        let json = try XCTUnwrap(JSONSerialization.it_jsonString(for: SetStatusBuiltInFunction.statusDictionary(for: status)))
        XCTAssertTrue(json.contains("\"turn_open\":false"), json)
    }

    func testResultReflectsAnAppliedDelta() throws {
        let status = iTermSessionTabStatus(sessionID: "s")
        let seed = VT100TabStatusUpdate()
        seed.backgroundTasksPresence = .set
        seed.backgroundTasks = 2
        seed.turnOpenPresence = .set
        seed.turnOpen = true
        _ = status.apply(seed)
        _ = status.apply(try SetStatusBuiltInFunction.update(from: ["background_tasks_delta": NSNumber(value: -1)]))

        let parsed = try roundTrip(status)
        XCTAssertEqual(parsed["background_tasks"] as? Int, 1)
        XCTAssertEqual(parsed["turn_open"] as? Bool, true)
        XCTAssertTrue(parsed["status"] is NSNull)
    }
}
