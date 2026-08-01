//
//  SessionBoundWatcherTests.swift
//  iTerm2 ModernTests
//
//  Watchers used to be reachable only from orchestration chats: the three
//  watch tools (register_watch / unregister_watch / list_watches) were
//  registered on the LLM only in OrchestrationToolProvider's .orchestration
//  arm, and register_watch required a session_guid the session-bound agent had
//  no way to obtain. These tests pin the pieces that let a chat linked to a
//  single terminal session register watchers on that session:
//
//   - RegisterWatchArgs.sessionGuid is optional, so a session-bound call that
//     omits it still decodes (the dispatcher fills in the linked session).
//   - OrchestratorDispatcher.resolveWatchTarget resolves the implicit target:
//     an explicit guid wins, else the chat's linked terminal session, else nil.
//   - OrchestratorCommand.sessionBoundWatchToolDefinitions expose the watch
//     tools WITHOUT a session_guid argument (the target is implicit).
//   - OrchestrationToolProvider.sessionBound registers those tools when (and
//     only when) the chat is terminal-linked (offerWatchers == true).
//
//  These are offline: the firing/persistence/reconciliation wiring inside the
//  live dispatcher is exercised by OrchestrationWatchReloadTests and manual
//  driving, not here.
//

import XCTest
@testable import iTerm2SharedARC

final class SessionBoundWatcherTests: XCTestCase {

    // MARK: - RegisterWatchArgs optional session_guid

    // A session-bound register_watch call carries no session_guid (the target
    // is the chat's one linked session). It must still decode.
    func test_registerWatchArgs_decodesWithoutSessionGuid() throws {
        let json = Data(#"{"target_state":"idle"}"#.utf8)
        let args = try JSONDecoder().decode(RegisterWatchArgs.self, from: json)
        XCTAssertNil(args.sessionGuid)
        XCTAssertEqual(args.targetState, .idle)
        XCTAssertNil(args.condition)
    }

    // The orchestration form still round-trips its explicit session_guid.
    func test_registerWatchArgs_decodesWithSessionGuid() throws {
        let json = Data(#"{"session_guid":"G1","condition":"build finished"}"#.utf8)
        let args = try JSONDecoder().decode(RegisterWatchArgs.self, from: json)
        XCTAssertEqual(args.sessionGuid, "G1")
        XCTAssertNil(args.targetState)
        XCTAssertEqual(args.condition, "build finished")
    }

    // MARK: - resolveWatchTarget (target policy)

    // Orchestration chats must supply an explicit session_guid and can target
    // any session; there is no linked terminal to fall back to.
    func test_resolveWatchTarget_orchestration_requiresExplicit() throws {
        XCTAssertEqual(
            try OrchestratorDispatcher.resolveWatchTarget(
                explicit: "G1", orchestrationEnabled: true, linkedTerminal: nil),
            "G1")
        XCTAssertThrowsError(
            try OrchestratorDispatcher.resolveWatchTarget(
                explicit: nil, orchestrationEnabled: true, linkedTerminal: nil))
        XCTAssertThrowsError(
            try OrchestratorDispatcher.resolveWatchTarget(
                explicit: "", orchestrationEnabled: true, linkedTerminal: nil))
    }

    // Session-bound chats always target the linked session. An omitted or empty
    // session_guid resolves to the linked session; an explicit guid that
    // matches is accepted.
    func test_resolveWatchTarget_sessionBound_usesLinkedSession() throws {
        XCTAssertEqual(
            try OrchestratorDispatcher.resolveWatchTarget(
                explicit: nil, orchestrationEnabled: false, linkedTerminal: "LINK"),
            "LINK")
        XCTAssertEqual(
            try OrchestratorDispatcher.resolveWatchTarget(
                explicit: "", orchestrationEnabled: false, linkedTerminal: "LINK"),
            "LINK")
        XCTAssertEqual(
            try OrchestratorDispatcher.resolveWatchTarget(
                explicit: "LINK", orchestrationEnabled: false, linkedTerminal: "LINK"),
            "LINK")
    }

    // The security boundary: a session-bound chat may NOT watch a different
    // session by smuggling in a foreign session_guid. It's rejected, not
    // silently honored.
    func test_resolveWatchTarget_sessionBound_rejectsForeignGuid() {
        XCTAssertThrowsError(
            try OrchestratorDispatcher.resolveWatchTarget(
                explicit: "OTHER", orchestrationEnabled: false, linkedTerminal: "LINK"))
    }

    // An unlinked session-bound chat has nothing to watch.
    func test_resolveWatchTarget_sessionBound_errorsWhenUnlinked() {
        XCTAssertThrowsError(
            try OrchestratorDispatcher.resolveWatchTarget(
                explicit: nil, orchestrationEnabled: false, linkedTerminal: nil))
    }

    // MARK: - watchReadRequirement (which categories a watch form reads)

    // A condition watch reads the screen (View Contents) and nothing else.
    func test_watchReadRequirement_conditionReadsScreenOnly() {
        let r = OrchestratorDispatcher.watchReadRequirement(
            condition: true, sessionReportsStatus: true)
        XCTAssertTrue(r.needsScreen)
        XCTAssertFalse(r.needsState)
        // Independent of whether the session reports status.
        let r2 = OrchestratorDispatcher.watchReadRequirement(
            condition: true, sessionReportsStatus: false)
        XCTAssertTrue(r2.needsScreen)
        XCTAssertFalse(r2.needsState)
    }

    // A target_state watch on a status-reporting session reads only the reported
    // state (Check Terminal State) -- it fires on the transition, no screen read.
    func test_watchReadRequirement_targetStateReportingReadsStateOnly() {
        let r = OrchestratorDispatcher.watchReadRequirement(
            condition: false, sessionReportsStatus: true)
        XCTAssertFalse(r.needsScreen)
        XCTAssertTrue(r.needsState)
    }

    // A target_state watch on a session that reports NO machine-readable status
    // can only be satisfied by reading the screen, so it needs BOTH.
    func test_watchReadRequirement_targetStateStatuslessReadsBoth() {
        let r = OrchestratorDispatcher.watchReadRequirement(
            condition: false, sessionReportsStatus: false)
        XCTAssertTrue(r.needsScreen)
        XCTAssertTrue(r.needsState)
    }

    // WorkgroupWatcher.readRequirement (the runtime derivation from a watcher's
    // frozen shape) must agree with the registration-time watchReadRequirement,
    // so reconcile/regate enforce the same policy the register gate did.
    func test_workgroupWatcher_readRequirement_matchesRegistrationPolicy() {
        func watcher(condition: String?, targetState: SessionState?, mode: WatchMode) -> WorkgroupWatcher {
            WorkgroupWatcher(watcherID: "w", sessionGUID: "s", workgroupID: "session:s",
                             workgroupName: "S", roleID: "r", roleName: "S",
                             targetState: targetState, registeredAt: Date(),
                             mode: mode, condition: condition)
        }
        // condition (always screenPoll): screen only.
        let cond = watcher(condition: "build done", targetState: nil, mode: .screenPoll).readRequirement
        XCTAssertTrue(cond.needsScreen); XCTAssertFalse(cond.needsState)
        // target_state, tab-status (reporting session): state only.
        let tab = watcher(condition: nil, targetState: .idle, mode: .tabStatus).readRequirement
        XCTAssertFalse(tab.needsScreen); XCTAssertTrue(tab.needsState)
        // target_state, screenPoll (statusless session): both.
        let poll = watcher(condition: nil, targetState: .idle, mode: .screenPoll).readRequirement
        XCTAssertTrue(poll.needsScreen); XCTAssertTrue(poll.needsState)
    }

    // MARK: - watchFormSatisfiable (offer/guidance policy shared with the gate)

    func test_watchFormSatisfiable_conditionNeedsViewContents() {
        let req = OrchestratorDispatcher.watchReadRequirement(condition: true, sessionReportsStatus: true)
        XCTAssertTrue(OrchestratorDispatcher.watchFormSatisfiable(
            requirement: req, viewContentsPermitted: true, checkTerminalStatePermitted: false))
        XCTAssertFalse(OrchestratorDispatcher.watchFormSatisfiable(
            requirement: req, viewContentsPermitted: false, checkTerminalStatePermitted: true))
    }

    func test_watchFormSatisfiable_targetStateReportingNeedsCheckState() {
        let req = OrchestratorDispatcher.watchReadRequirement(condition: false, sessionReportsStatus: true)
        XCTAssertTrue(OrchestratorDispatcher.watchFormSatisfiable(
            requirement: req, viewContentsPermitted: false, checkTerminalStatePermitted: true))
        XCTAssertFalse(OrchestratorDispatcher.watchFormSatisfiable(
            requirement: req, viewContentsPermitted: true, checkTerminalStatePermitted: false))
    }

    func test_watchFormSatisfiable_targetStateStatuslessNeedsBoth() {
        let req = OrchestratorDispatcher.watchReadRequirement(condition: false, sessionReportsStatus: false)
        XCTAssertFalse(OrchestratorDispatcher.watchFormSatisfiable(
            requirement: req, viewContentsPermitted: true, checkTerminalStatePermitted: false))
        XCTAssertFalse(OrchestratorDispatcher.watchFormSatisfiable(
            requirement: req, viewContentsPermitted: false, checkTerminalStatePermitted: true))
        XCTAssertTrue(OrchestratorDispatcher.watchFormSatisfiable(
            requirement: req, viewContentsPermitted: true, checkTerminalStatePermitted: true))
    }

    // MARK: - watcherTargetLabel (status_update text)

    func test_watcherTargetLabel_collapsesSyntheticWorkgroup() {
        // A standalone session is a synthetic single-session workgroup (ID
        // prefixed "session:"); collapse so the text isn't "Terminal in
        // Terminal".
        XCTAssertEqual(
            OrchestratorDispatcher.watcherTargetLabel(
                role: "Terminal", workgroup: "Terminal", workgroupID: "session:ptys_ABC"),
            "Terminal")
        // A real workgroup keeps the "role in workgroup" form.
        XCTAssertEqual(
            OrchestratorDispatcher.watcherTargetLabel(
                role: "Code Review", workgroup: "myproj", workgroupID: "wg-123"),
            "Code Review in myproj")
    }

    // The issue-D case: a REAL workgroup whose role name happens to equal its
    // workgroup name must NOT be collapsed -- the qualifier is meaningful.
    func test_watcherTargetLabel_realWorkgroupWithMatchingNamesNotCollapsed() {
        XCTAssertEqual(
            OrchestratorDispatcher.watcherTargetLabel(
                role: "Build", workgroup: "Build", workgroupID: "wg-build"),
            "Build in Build")
    }

    // MARK: - register_watch description (shared spine, per-surface differences)

    // The orchestration and session-bound register_watch descriptions are built
    // from one shared spine (registerWatchDescription). Guard that the spine is
    // present in both and that the intended per-surface differences hold, so the
    // factoring can't silently drift them apart again.
    func test_registerWatchDescriptions_shareSpineAndDifferPerSurface() throws {
        func registerDesc(_ defs: [ToolDefinition]) throws -> String {
            try XCTUnwrap(defs.first { $0.name == "register_watch" }).description
        }
        let orch = try registerDesc(OrchestratorCommand.allToolDefinitions)
        let sb = try registerDesc(OrchestratorCommand.sessionBoundWatchToolDefinitions)

        // Shared spine present verbatim in both.
        for shared in ["treat that as a system event from iTerm2 (not a new user request)",
                       "Watchers are de-duplicated on (session, target_state, condition)",
                       "If the goal is already satisfied at registration time, the watcher fires immediately."] {
            XCTAssertTrue(orch.contains(shared), "orchestration missing shared spine: \(shared)")
            XCTAssertTrue(sb.contains(shared), "session-bound missing shared spine: \(shared)")
        }

        // Orchestration-only vocabulary stays out of the session-bound copy.
        XCTAssertTrue(orch.contains("status_source"))
        XCTAssertFalse(sb.contains("status_source"))

        // Blocking clause: orchestration is unconditionally non-blocking; the
        // session-bound copy is honest about the one-time Ask consent wait.
        XCTAssertTrue(orch.contains("This call returns immediately and does NOT block your turn."))
        XCTAssertTrue(sb.contains("View Contents permission is set to Ask"))
        XCTAssertFalse(sb.contains("This call returns immediately and does NOT block your turn."))
    }

    // MARK: - sessionBoundWatchToolDefinitions schema shape

    func test_sessionBoundWatchToolDefinitions_registerWatchOmitsSessionGuid() throws {
        let defs = OrchestratorCommand.sessionBoundWatchToolDefinitions
        let names = defs.map { $0.name }
        XCTAssertTrue(names.contains("register_watch"))
        XCTAssertTrue(names.contains("unregister_watch"))
        XCTAssertTrue(names.contains("list_watches"))

        let register = try XCTUnwrap(defs.first { $0.name == "register_watch" })
        let properties = try XCTUnwrap(register.inputSchema["properties"] as? [String: Any])
        XCTAssertNil(properties["session_guid"],
                     "the session-bound register_watch must not ask for a session_guid; the target is the linked session")
        XCTAssertNotNil(properties["target_state"])
        XCTAssertNotNil(properties["condition"])

        let required = (register.inputSchema["required"] as? [String]) ?? []
        XCTAssertFalse(required.contains("session_guid"),
                       "session_guid must not be required in the session-bound form")
    }

    func test_sessionBoundWatchToolDefinitions_unregisterAndListShapes() throws {
        let defs = OrchestratorCommand.sessionBoundWatchToolDefinitions
        let unregister = try XCTUnwrap(defs.first { $0.name == "unregister_watch" })
        let unregisterRequired = (unregister.inputSchema["required"] as? [String]) ?? []
        XCTAssertTrue(unregisterRequired.contains("watcher_id"))

        let list = try XCTUnwrap(defs.first { $0.name == "list_watches" })
        let listProps = (list.inputSchema["properties"] as? [String: Any]) ?? [:]
        XCTAssertTrue(listProps.isEmpty, "list_watches takes no arguments")
    }

    // MARK: - Provider registration is gated on terminal linkage

    @MainActor
    private func registeredToolNames(offerWatchers: Bool) -> [String] {
        var conversation = AIConversation(registrationProvider: nil, messages: [])
        let provider = OrchestrationToolProvider.sessionBound(
            enableRequestHandler: { _ in },
            externalInvoker: { _, _, _, _ in },
            offerWatchers: { offerWatchers })
        provider.registerTools(on: &conversation)
        return conversation.controller.functions.map { $0.decl.name }
    }

    @MainActor
    func test_sessionBoundProvider_registersWatchTools_whenTerminalLinked() {
        let names = registeredToolNames(offerWatchers: true)
        XCTAssertTrue(names.contains("register_watch"))
        XCTAssertTrue(names.contains("unregister_watch"))
        XCTAssertTrue(names.contains("list_watches"))
        // The enable-request tool is always present in session-bound mode.
        XCTAssertTrue(names.contains("request_orchestration_enable"))
    }

    @MainActor
    func test_sessionBoundProvider_omitsWatchTools_whenNotTerminalLinked() {
        let names = registeredToolNames(offerWatchers: false)
        XCTAssertFalse(names.contains("register_watch"))
        XCTAssertFalse(names.contains("unregister_watch"))
        XCTAssertFalse(names.contains("list_watches"))
        XCTAssertTrue(names.contains("request_orchestration_enable"),
                      "the enable-request tool is offered regardless of watcher availability")
    }
}
