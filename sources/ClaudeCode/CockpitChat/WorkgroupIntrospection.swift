//
//  WorkgroupIntrospection.swift
//  iTerm2SharedARC
//

import Foundation

// Bridges the live iTerm2 workgroup model to the orchestrator's
// read-only JSON surface. Everything here is best-effort: workgroups
// can vanish between calls, sessions can terminate, the cc-status
// hook may not be installed. Each method returns whatever it can
// reasonably synthesize from the current live state.
//
// Synthetic single-session workgroups (for sessions not in any user-
// configured workgroup) get IDs prefixed with "session:" so they're
// visually distinct from real workgroup instance IDs (prefixed "wg-")
// and can round-trip back through the same target-resolution path.
// @MainActor: every helper here reads main-thread state (PTYSession
// fields, iTermWorkgroupController.instance, session.view, tabStatus,
// screen.terminalSoftAlternateScreenMode, clippings). Callers
// previously had to rely on convention; the annotation makes the
// contract a compile-time check so a future background-thread caller
// gets a clear error instead of a runtime race against AppKit.
@MainActor
enum WorkgroupIntrospection {

    static let syntheticWorkgroupIDPrefix = "session:"

    // The single role inside a synthetic workgroup. Chosen so the LLM
    // sees a stable name across all standalone sessions; the role name
    // is the session's display name when it has one, the synthetic ID
    // otherwise.
    static let syntheticRoleID = "default"

    // MARK: - Listing

    // Returns every workgroup the cockpit knows about. Real workgroups
    // come from iTermWorkgroupController.allInstances; every other live
    // session in the app gets wrapped in a synthetic single-session
    // workgroup so the LLM can address it via the same target shape.
    static func allWorkgroups() -> [WorkgroupSummary] {
        var summaries: [WorkgroupSummary] = []
        var coveredSessions: Set<ObjectIdentifier> = []

        for instance in iTermWorkgroupController.instance.allInstances {
            let summary = summary(forInstance: instance)
            summaries.append(summary)
            // Mark every member as covered (including non-realized
            // placeholders, which are simply skipped) so we don't also
            // wrap them as synthetic workgroups below.
            for member in instance.resolvedMembers() {
                if let session = member.session {
                    coveredSessions.insert(ObjectIdentifier(session))
                }
            }
        }

        for session in allSessions() {
            if coveredSessions.contains(ObjectIdentifier(session)) { continue }
            summaries.append(syntheticSummary(for: session))
        }
        return summaries
    }

    // Best-effort display name for a workgroup ID. Real workgroups
    // resolve via the controller's instance list; synthetic single-
    // session workgroups derive their name from the session itself.
    // Falls back to the raw ID when neither resolves (the workgroup
    // has been torn down).
    @MainActor
    static func displayName(forWorkgroupID workgroupID: String) -> String {
        if workgroupID.hasPrefix(syntheticWorkgroupIDPrefix) {
            let guid = String(workgroupID.dropFirst(syntheticWorkgroupIDPrefix.count))
            if let session = session(forGUID: guid) {
                return sessionDisplayName(session)
            }
            return workgroupID
        }
        if let instance = workgroupInstance(byID: workgroupID) {
            return workgroupName(for: instance)
        }
        return workgroupID
    }

    static func summary(forInstance instance: iTermWorkgroupInstance) -> WorkgroupSummary {
        let sessions = instance.resolvedMembers().compactMap { member -> SessionSummary? in
            guard let session = member.session else { return nil }
            return sessionSummary(roleID: member.roleID,
                                  roleName: displayName(member.displayName,
                                                         fallback: member.roleID),
                                  session: session)
        }
        return WorkgroupSummary(
            workgroupID: instance.instanceUniqueIdentifier,
            workgroupName: workgroupName(for: instance),
            sessions: sessions)
    }

    static func syntheticSummary(for session: PTYSession) -> WorkgroupSummary {
        let workgroupID = syntheticWorkgroupID(for: session)
        let roleName = sessionDisplayName(session)
        return WorkgroupSummary(
            workgroupID: workgroupID,
            workgroupName: roleName,
            sessions: [
                sessionSummary(roleID: syntheticRoleID,
                               roleName: roleName,
                               session: session)
            ])
    }

    // MARK: - Resolution

    // Find the (instance, session, roleName) triple a target refers to,
    // or nil if it can't be resolved. Accepts both the runtime instance
    // ID ("wg-...") and a synthetic ID ("session:<guid>"); accepts role
    // by either roleID or display name (case-insensitive).
    struct ResolvedTarget {
        let instance: iTermWorkgroupInstance?  // nil for synthetic
        let session: PTYSession
        let roleID: String
        let roleName: String
        let workgroupID: String
        let workgroupName: String
    }

    // List role display names available on a workgroup. Used to build
    // a "did you mean: X, Y, Z" hint in the unknown_role error so the
    // agent can self-correct without re-calling list_workgroups.
    // Returns an empty array for synthetic single-session workgroups
    // (caller already accepts any role there) and for unknown
    // workgroup IDs.
    static func availableRoleNames(forWorkgroupID workgroupID: String) -> [String] {
        if workgroupID.hasPrefix(syntheticWorkgroupIDPrefix) {
            return []
        }
        guard let instance = workgroupInstance(byID: workgroupID) else {
            return []
        }
        return instance.resolvedMembers().compactMap { member -> String? in
            guard member.session != nil else { return nil }
            return displayName(member.displayName, fallback: member.roleID)
        }
    }

    static func resolve(target: OrchestratorTarget) -> ResolvedTarget? {
        // Synthetic single-session workgroup.
        if target.workgroupID.hasPrefix(syntheticWorkgroupIDPrefix) {
            let guid = String(target.workgroupID.dropFirst(syntheticWorkgroupIDPrefix.count))
            guard let session = session(forGUID: guid) else { return nil }
            // Synthetic workgroups have exactly one role; accept any
            // role name the model offered as long as a session exists.
            let name = sessionDisplayName(session)
            return ResolvedTarget(
                instance: nil,
                session: session,
                roleID: syntheticRoleID,
                roleName: name,
                workgroupID: target.workgroupID,
                workgroupName: name)
        }

        // Real workgroup. Look up by runtime instance ID.
        guard let instance = workgroupInstance(byID: target.workgroupID) else {
            return nil
        }
        let needle = target.role.lowercased()
        for member in instance.resolvedMembers() {
            guard let session = member.session else { continue }
            if member.roleID.lowercased() == needle
                || member.displayName.lowercased() == needle {
                return ResolvedTarget(
                    instance: instance,
                    session: session,
                    roleID: member.roleID,
                    roleName: displayName(member.displayName, fallback: member.roleID),
                    workgroupID: instance.instanceUniqueIdentifier,
                    workgroupName: workgroupName(for: instance))
            }
        }
        return nil
    }

    // Reverse of resolve(target:) — finds the workgroup + role that
    // owns `session`. Standalone sessions resolve to the synthetic
    // single-session workgroup. Returns nil only if the session has
    // exited and isn't reachable through iTermController anymore.
    struct SessionContext {
        let instance: iTermWorkgroupInstance?  // nil for synthetic
        let workgroupID: String
        let workgroupName: String
        let roleID: String
        let roleName: String
    }

    @MainActor
    static func context(for session: PTYSession) -> SessionContext? {
        for instance in iTermWorkgroupController.instance.allInstances {
            for member in instance.resolvedMembers() {
                if member.session === session {
                    return SessionContext(
                        instance: instance,
                        workgroupID: instance.instanceUniqueIdentifier,
                        workgroupName: workgroupName(for: instance),
                        roleID: member.roleID,
                        roleName: displayName(member.displayName, fallback: member.roleID))
                }
            }
        }
        // Standalone session — synthetic single-session workgroup.
        let name = sessionDisplayName(session)
        return SessionContext(
            instance: nil,
            workgroupID: syntheticWorkgroupID(for: session),
            workgroupName: name,
            roleID: syntheticRoleID,
            roleName: name)
    }

    // MARK: - Per-session info

    // Builds the SessionStateInfo that get_state returns for a target.
    static func stateInfo(for resolved: ResolvedTarget) -> SessionStateInfo {
        return SessionStateInfo(
            workgroupID: resolved.workgroupID,
            workgroupName: resolved.workgroupName,
            roleID: resolved.roleID,
            roleName: resolved.roleName,
            kind: kind(for: resolved.session),
            status: state(for: resolved.session),
            lastActivityISO: nil,
            currentCommand: currentCommand(for: resolved.session),
            lastMessage: lastMessage(for: resolved.session),
            pendingAction: pendingActionDescription(for: resolved.session))
    }

    static func sessionSummary(roleID: String,
                               roleName: String,
                               session: PTYSession) -> SessionSummary {
        return SessionSummary(
            roleID: roleID,
            roleName: roleName,
            sessionGuid: session.guid,
            kind: kind(for: session),
            status: state(for: session),
            lastActivityISO: nil,
            currentCommand: currentCommand(for: session),
            pendingAction: pendingActionDescription(for: session))
    }

    // MARK: - Screen contents

    // Returns trailing scrollback + visible screen as a single string,
    // optionally trimmed to the last `lines` rows. For interactive TUIs
    // the result is a point-in-time snapshot of the rendered screen;
    // for shells it's the linear transcript. Kind classification is
    // returned alongside so the LLM knows how to read the text.
    static func screenContents(for resolved: ResolvedTarget,
                               requestedLines: Int?) -> ScreenContents {
        let session = resolved.session
        let kind = kind(for: session)
        let pending = pendingActionDescription(for: session)
        switch kind {
        case .tui:
            return ScreenContents(text: snapshot(of: session),
                                  kind: .tui,
                                  isSnapshot: true,
                                  pendingAction: pending)
        case .shell, .claudeCode, .other:
            let text = trailingTranscript(of: session,
                                          lines: requestedLines ?? 100)
            return ScreenContents(text: text,
                                  kind: kind,
                                  isSnapshot: false,
                                  pendingAction: pending)
        }
    }

    // MARK: - Clippings

    // Pulls clippings off the workgroup's leader session. For real
    // workgroups that's the peer group's leader (PTYSession.clippings
    // auto-delegates via the peer port). For synthetic single-session
    // workgroups, the clippings live directly on the session.
    static func clippings(forWorkgroupID workgroupID: String,
                          typeFilter: String?) -> [ClippingInfo]? {
        let clippings: [PTYSessionClipping]
        if workgroupID.hasPrefix(syntheticWorkgroupIDPrefix) {
            let guid = String(workgroupID.dropFirst(syntheticWorkgroupIDPrefix.count))
            guard let session = session(forGUID: guid) else { return nil }
            clippings = session.clippings
        } else {
            guard let instance = workgroupInstance(byID: workgroupID),
                  let leader = instance.mainSession else {
                return nil
            }
            clippings = leader.clippings
        }
        let filtered: [PTYSessionClipping]
        if let typeFilter, !typeFilter.isEmpty {
            filtered = clippings.filter { $0.type == typeFilter }
        } else {
            filtered = clippings
        }
        return filtered.map {
            ClippingInfo(type: $0.type, title: $0.title, detail: $0.detail)
        }
    }

    // MARK: - Internals

    private static func workgroupInstance(byID id: String) -> iTermWorkgroupInstance? {
        return iTermWorkgroupController.instance.allInstances
            .first { $0.instanceUniqueIdentifier == id }
    }

    private static func session(forGUID guid: String) -> PTYSession? {
        // anySession(withGUID:) covers peer-port sessions (Code Review, Diff,
        // side-pane peers) which allSessions() does not enumerate. allSessions()
        // remains the right source for enumeration paths that explicitly walk
        // standalone tab/split sessions only.
        return iTermController.sharedInstance()?.anySession(withGUID: guid)
    }

    private static func allSessions() -> [PTYSession] {
        return iTermController.sharedInstance()?.allSessions() ?? []
    }

    private static func syntheticWorkgroupID(for session: PTYSession) -> String {
        return syntheticWorkgroupIDPrefix + session.guid
    }

    private static func workgroupName(for instance: iTermWorkgroupInstance) -> String {
        let raw = instance.workgroup.name
        return raw.isEmpty ? instance.instanceUniqueIdentifier : raw
    }

    private static func sessionDisplayName(_ session: PTYSession) -> String {
        return session.name.isEmpty ? session.guid : session.name
    }

    private static func displayName(_ name: String, fallback: String) -> String {
        return name.isEmpty ? fallback : name
    }

    // Heuristic kind classification:
    //   - claude-code if GlobalJobMonitor sees "claude" as the
    //     foreground job for this session
    //   - tui if the session is on the soft alternate screen, which
    //     reliably indicates a full-screen TUI (vim, less, htop, etc.).
    //     We must not include scrollback for these because intermediate
    //     vim frames get pushed there on repaint and would look like
    //     duplicate screens.
    //   - other otherwise. Distinguishing shell vs other without a
    //     reliable signal would mislead the LLM; "other" lets it know
    //     to call get_screen_contents and read the text.
    private static func kind(for session: PTYSession) -> SessionKind {
        let claudeGUIDs = GlobalJobMonitor.instance.sessionGUIDs(runningJob: "claude")
        if claudeGUIDs.contains(session.guid) {
            return .claudeCode
        }
        if session.screen.terminalSoftAlternateScreenMode {
            return .tui
        }
        return .other
    }

    // Status reflects whether the role's *program* is doing anything.
    // Primary signal is tabStatus.statusText, which the cc-status
    // hook (and triggers using `set_status`) write as explicit
    // "idle"/"working"/"waiting" strings. cc-status always sets a
    // dot color even at idle, so hasIndicator alone is misleading —
    // a green idle dot still reads as "indicator set" and would
    // make every Claude Code session look perpetually working.
    //
    // .waiting is intentionally NOT used for the Code Review
    // prompt-overlay case — the program hasn't launched, so it isn't
    // really "waiting on input" in the runtime sense the agent
    // probably thinks of. Conditions like "overlay is up; send the
    // review prompt" are surfaced via pendingActionDescription
    // instead, so the actionable hint is its own field and doesn't
    // overload `status`.
    static func state(for session: PTYSession) -> SessionState {
        guard let status = session.tabStatus else { return .unknown }
        return state(forTabStatus: status)
    }

    // Direct-from-tabStatus variant used by OrchestratorDispatcher's tab-
    // status notification handler. The notification's `object` is already
    // the iTermSessionTabStatus, so we don't need to (and shouldn't) look
    // up the owning PTYSession again. Workgroup peer-port sessions don't
    // appear in iTermController.sharedInstance().allSessions(), so trying
    // to recover the session from a guid returns nil for the very roles
    // the cockpit watches — which silently swallows watcher fires.
    static func state(forTabStatus status: iTermSessionTabStatus) -> SessionState {
        if let text = status.statusText?.lowercased(), !text.isEmpty {
            switch text {
            case "idle": return .idle
            case "working": return .working
            case "waiting": return .waiting
            default: break  // unrecognized status text — fall through
            }
        }
        // No status text from the hook / trigger: fall back to
        // indicator state. Indicator alone has weak semantics but
        // is the best we can do for sessions without a status source.
        if status.hasIndicator { return .working }
        return .idle
    }

    // Human-readable hint describing what the role is currently
    // awaiting. Returned alongside the structured state on get_state
    // and get_screen_contents so the agent knows what action to take
    // without having to memorize iTerm2-internal conventions.
    static func pendingActionDescription(for session: PTYSession) -> String? {
        if session.view?.codeReviewPromptOverlay != nil {
            return "The Code Review prompt overlay is showing. Call send_text "
                + "on this role with the review prompt; your text becomes the "
                + "prompt and the review starts immediately."
        }
        return nil
    }

    private static func currentCommand(for session: PTYSession) -> String? {
        return session.genericScope
            .value(forVariableName: "jobName") as? String
    }

    static func lastMessage(for session: PTYSession) -> String? {
        guard let status = session.tabStatus else { return nil }
        if let detail = status.detailText, !detail.isEmpty { return detail }
        if let text = status.statusText, !text.isEmpty { return text }
        return nil
    }

    private static func snapshot(of session: PTYSession) -> String {
        return stripTrailingSpaces(session.screen.compactLineDump())
    }

    private static func trailingTranscript(of session: PTYSession, lines: Int) -> String {
        // Clamp to a sane range. An LLM that asks for 0 / -1 / a huge
        // value to "see the whole buffer" would otherwise blow its own
        // context window and ours on a long-running shell. The schema
        // documents a default of 100; cap the request to 2000 lines to
        // bound the response size without being mean to legitimate
        // "give me a lot of context" calls.
        let clamped = max(1, min(2000, lines))
        let full = session.screen.compactLineDumpWithHistory()
        let allLines = full.components(separatedBy: "\n")
        let trimmed = allLines.count <= clamped
            ? full
            : allLines.suffix(clamped).joined(separator: "\n")
        return stripTrailingSpaces(trimmed)
    }

    // Compact line dumps right-pad every row to the terminal width.
    // The padding is just noise for an LLM reader and inflates the
    // payload, so trim it on each line before returning.
    private static func stripTrailingSpaces(_ text: String) -> String {
        return text
            .components(separatedBy: "\n")
            .map { line in
                var end = line.endIndex
                while end > line.startIndex {
                    let prev = line.index(before: end)
                    if line[prev] != " " { break }
                    end = prev
                }
                return String(line[..<end])
            }
            .joined(separator: "\n")
    }
}
