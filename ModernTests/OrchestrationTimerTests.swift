//
//  OrchestrationTimerTests.swift
//  iTerm2 ModernTests
//
//  Covers the register_timer tool: a fire-once async watcher that targets no
//  session and reads nothing, delivering a timerFired status_update at a
//  wall-clock instant. These are offline: the time-argument validation is
//  extracted into the pure static OrchestratorDispatcher.resolveTimerFireDate
//  (mirroring resolveWatchTarget), so it's exercised here without a live
//  dispatcher; the fire/persistence/reconcile wiring is exercised by manual
//  driving (see the plan's verification section).
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class OrchestrationTimerTests: XCTestCase {

    // A far-future but within-cap reference so the format-and-reparse cases don't
    // trip the past-time or 30-day guards.
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - RegisterTimerArgs decoding

    func test_registerTimerArgs_decodesDelayForm() throws {
        let json = Data(#"{"delay_seconds":7200,"fire_at":null,"note":"run deploy","notify_user":true}"#.utf8)
        let args = try JSONDecoder().decode(RegisterTimerArgs.self, from: json)
        XCTAssertEqual(args.delaySeconds, 7200)
        XCTAssertNil(args.fireAt)
        XCTAssertEqual(args.note, "run deploy")
        XCTAssertEqual(args.notifyUser, true)
    }

    func test_registerTimerArgs_decodesAbsoluteForm() throws {
        let json = Data(#"{"delay_seconds":null,"fire_at":"2026-09-07T17:00:00-07:00","note":null}"#.utf8)
        let args = try JSONDecoder().decode(RegisterTimerArgs.self, from: json)
        XCTAssertNil(args.delaySeconds)
        XCTAssertEqual(args.fireAt, "2026-09-07T17:00:00-07:00")
        XCTAssertNil(args.note)
        XCTAssertNil(args.notifyUser)
    }

    // MARK: - resolveTimerFireDate (exactly-one policy)

    func test_resolveTimerFireDate_requiresExactlyOne() {
        let now = Date()
        XCTAssertThrowsError(try OrchestratorDispatcher.resolveTimerFireDate(
            delaySeconds: nil, fireAt: nil, now: now), "neither supplied must throw")
        XCTAssertThrowsError(try OrchestratorDispatcher.resolveTimerFireDate(
            delaySeconds: 60, fireAt: iso(now.addingTimeInterval(60)), now: now),
            "both supplied must throw")
    }

    // MARK: - resolveTimerFireDate (delay form)

    func test_resolveTimerFireDate_delay_returnsNowPlusDelay() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fire = try OrchestratorDispatcher.resolveTimerFireDate(
            delaySeconds: 90, fireAt: nil, now: now)
        XCTAssertEqual(fire.timeIntervalSince1970, now.timeIntervalSince1970 + 90, accuracy: 0.001)
    }

    func test_resolveTimerFireDate_delay_rejectsNonPositive() {
        let now = Date()
        XCTAssertThrowsError(try OrchestratorDispatcher.resolveTimerFireDate(
            delaySeconds: 0, fireAt: nil, now: now))
        XCTAssertThrowsError(try OrchestratorDispatcher.resolveTimerFireDate(
            delaySeconds: -5, fireAt: nil, now: now))
    }

    func test_resolveTimerFireDate_delay_rejectsBeyondCap() {
        let now = Date()
        let overCap = 31.0 * 24 * 3600
        XCTAssertThrowsError(try OrchestratorDispatcher.resolveTimerFireDate(
            delaySeconds: overCap, fireAt: nil, now: now))
        // Exactly at the cap is allowed.
        XCTAssertNoThrow(try OrchestratorDispatcher.resolveTimerFireDate(
            delaySeconds: 30.0 * 24 * 3600, fireAt: nil, now: now))
    }

    // MARK: - resolveTimerFireDate (absolute form)

    func test_resolveTimerFireDate_absolute_parsesWholeAndFractionalSeconds() throws {
        let now = Date()
        let target = now.addingTimeInterval(3600)
        // Whole-second ISO string (parseISO8601 falls back from the fractional
        // formatter to the plain one).
        let whole = try OrchestratorDispatcher.resolveTimerFireDate(
            delaySeconds: nil, fireAt: iso(target), now: now)
        XCTAssertEqual(whole.timeIntervalSince1970, target.timeIntervalSince1970, accuracy: 1.5)

        // Fractional-second ISO string is accepted too.
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let frac = try OrchestratorDispatcher.resolveTimerFireDate(
            delaySeconds: nil, fireAt: f.string(from: target), now: now)
        XCTAssertEqual(frac.timeIntervalSince1970, target.timeIntervalSince1970, accuracy: 1.5)
    }

    func test_resolveTimerFireDate_absolute_rejectsPast() {
        let now = Date()
        XCTAssertThrowsError(try OrchestratorDispatcher.resolveTimerFireDate(
            delaySeconds: nil, fireAt: iso(now.addingTimeInterval(-3600)), now: now))
    }

    func test_resolveTimerFireDate_absolute_rejectsUnparseable() {
        let now = Date()
        XCTAssertThrowsError(try OrchestratorDispatcher.resolveTimerFireDate(
            delaySeconds: nil, fireAt: "not a date", now: now))
        XCTAssertThrowsError(try OrchestratorDispatcher.resolveTimerFireDate(
            delaySeconds: nil, fireAt: "", now: now))
    }

    func test_resolveTimerFireDate_absolute_rejectsBeyondCap() {
        let now = Date()
        XCTAssertThrowsError(try OrchestratorDispatcher.resolveTimerFireDate(
            delaySeconds: nil, fireAt: iso(now.addingTimeInterval(40 * 24 * 3600)), now: now))
    }

    // MARK: - WorkgroupWatcher timer semantics

    private func timerWatcher(note: String? = nil, fireDate: Date = Date().addingTimeInterval(60)) -> WorkgroupWatcher {
        WorkgroupWatcher(watcherID: "t1", sessionGUID: "",
                         workgroupID: "session:timer", workgroupName: "Timer",
                         roleID: "timer", roleName: "Timer",
                         targetState: nil, registeredAt: Date(),
                         mode: .timer, condition: nil, notifyUser: nil,
                         fireDate: fireDate, note: note)
    }

    // A timer reads nothing: the reconcile/regate read gate must never deny it.
    func test_timerWatcher_readRequirementIsNone() {
        let r = timerWatcher().readRequirement
        XCTAssertFalse(r.needsScreen)
        XCTAssertFalse(r.needsState)
    }

    // effectiveMode drives the reconcile drop-exclusion and re-arm switch.
    func test_timerWatcher_effectiveModeIsTimer() {
        XCTAssertEqual(timerWatcher().effectiveMode, .timer)
    }

    func test_timerWatcher_goalDescriptionMentionsTimer() {
        XCTAssertTrue(timerWatcher().goalDescription.contains("timer"))
    }

    // fireDate / note / mode must survive the Codable round-trip that persists
    // watchers on the Chat.
    func test_timerWatcher_codableRoundTripsFireDateAndNote() throws {
        let original = timerWatcher(note: "run deploy",
                                    fireDate: Date(timeIntervalSince1970: 2_000_000))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkgroupWatcher.self, from: data)
        XCTAssertEqual(decoded.mode, .timer)
        XCTAssertEqual(decoded.note, "run deploy")
        XCTAssertEqual(decoded.fireDate?.timeIntervalSince1970 ?? 0,
                       2_000_000, accuracy: 0.001)
    }

    // MARK: - WatcherDescription encoding

    func test_watcherDescription_encodesFireAtForTimer_omitsWhenNil() throws {
        let timer = WatcherDescription(
            watcherID: "t1", workgroupID: "session:timer", workgroupName: "Timer",
            roleID: "timer", roleName: "Timer", targetState: nil, condition: nil,
            fireAt: "2026-09-07T17:00:00Z", registeredAt: "2026-09-07T15:00:00Z",
            note: "run deploy")
        let obj = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(timer)) as? [String: Any]
        XCTAssertEqual(obj?["fire_at"] as? String, "2026-09-07T17:00:00Z")
        XCTAssertEqual(obj?["note"] as? String, "run deploy")

        let watch = WatcherDescription(
            watcherID: "w1", workgroupID: "session:s", workgroupName: "S",
            roleID: "r", roleName: "S", targetState: .idle, condition: nil,
            fireAt: nil, registeredAt: "2026-09-07T15:00:00Z", note: nil)
        let watchObj = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(watch)) as? [String: Any]
        XCTAssertNil(watchObj?["fire_at"], "fire_at must be omitted for a non-timer watcher")
    }

    // MARK: - StatusUpdate timerFired reason

    func test_statusUpdate_timerFired_roundTrips() throws {
        let update = StatusUpdate(
            watcherID: "t1", workgroupID: "session:timer", workgroupName: "Timer",
            roleID: "timer", roleName: "Timer", reason: .timerFired,
            stateReached: "", timestamp: Date(timeIntervalSince1970: 3_000_000),
            detail: "Timer fired.")
        let decoded = try JSONDecoder().decode(
            StatusUpdate.self, from: JSONEncoder().encode(update))
        XCTAssertEqual(decoded.reason, .timerFired)
        XCTAssertEqual(StatusUpdate.Reason.timerFired.rawValue, "timerFired")
    }

    // MARK: - register_timer schema shape (both surfaces)

    func test_registerTimer_offeredOnBothSurfaces() {
        XCTAssertTrue(OrchestratorCommand.allToolDefinitions.contains { $0.name == "register_timer" },
                      "orchestration surface must offer register_timer")
        XCTAssertTrue(OrchestratorCommand.sessionBoundWatchToolDefinitions.contains { $0.name == "register_timer" },
                      "session-bound surface must offer register_timer")
    }

    // Strict-mode wire shape: additionalProperties false and every property is
    // required (matches how register_watch is shaped).
    func test_registerTimer_schemaIsStrict() throws {
        let def = try XCTUnwrap(OrchestratorCommand.allToolDefinitions.first { $0.name == "register_timer" })
        XCTAssertEqual(def.inputSchema["additionalProperties"] as? Bool, false)
        let props = try XCTUnwrap(def.inputSchema["properties"] as? [String: Any])
        let required = Set((def.inputSchema["required"] as? [String]) ?? [])
        XCTAssertNotNil(props["delay_seconds"])
        XCTAssertNotNil(props["fire_at"])
        XCTAssertNotNil(props["note"])
        XCTAssertEqual(Set(props.keys), required,
                       "strict mode: every property must be listed in required")
    }
}
