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

    // nonisolated: an immutable sentinel string with no main-thread state,
    // read by the nonisolated chat renderer (ChatViewController) too.
    nonisolated static let syntheticWorkgroupIDPrefix = "session:"

    // The single role inside a synthetic workgroup. Chosen so the LLM
    // sees a stable name across all standalone sessions; the role name
    // is the session's display name when it has one, the synthetic ID
    // otherwise.
    static let syntheticRoleID = "default"

    // Sentinel workgroup ID used by the spawn-approval prompt
    // (promptForSpawn). Not a real workgroup_id — by definition there
    // isn't a workgroup yet at spawn time. Carries the request through
    // the same workgroupPermissionRequest content type the workgroup
    // claim prompts use, but the chat renderer keys off this exact
    // string to pick the "Open a new session?" bubble copy instead of
    // "Allow agent to control workgroup …". Two sites must agree on
    // the literal — the dispatcher (OrchestratorDispatcher.promptForSpawn)
    // emits it, the renderer (ChatViewController) consumes it — so
    // it lives here next to the other orchestrator sentinel IDs.
    // nonisolated: an immutable sentinel string with no main-thread state,
    // read by the nonisolated chat renderer (ChatViewController) too.
    nonisolated static let spawnWorkgroupID = "spawn"

    // MARK: - Listing

    // Returns every workgroup the orchestrator knows about. Real workgroups
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

    // The (instance, session, role, workgroup) tuple a session GUID
    // resolves to. instance is nil for standalone sessions (which map
    // to a synthetic single-session workgroup).
    struct ResolvedTarget {
        let instance: iTermWorkgroupInstance?  // nil for synthetic
        let session: PTYSession
        let roleID: String
        let roleName: String
        let workgroupID: String
        let workgroupName: String
    }

    // Resolve a session GUID (copied verbatim from a snapshot's
    // session_guid field) to its full context. The GUID is globally
    // unique, so it pins exactly one session; the owning workgroup and
    // role are derived via context(for:) rather than supplied by the
    // caller. Returns nil only when no live session has that GUID.
    static func resolve(sessionGuid: String) -> ResolvedTarget? {
        guard let session = session(forGUID: sessionGuid),
              let ctx = context(for: session) else {
            return nil
        }
        return ResolvedTarget(
            instance: ctx.instance,
            session: session,
            roleID: ctx.roleID,
            roleName: ctx.roleName,
            workgroupID: ctx.workgroupID,
            workgroupName: ctx.workgroupName)
    }

    // The claim scope a write against this session gates on. Standalone
    // sessions claim at "session:<guid>" granularity; sessions inside a
    // real workgroup claim at the workgroup instance level so approving
    // a workgroup once approves all its roles (see the claim model in
    // OrchestratorCommand). Returns nil when no live session has that
    // GUID, in which case the caller surfaces an unknown_session error.
    static func claimScope(forSessionGuid guid: String) -> String? {
        guard let session = session(forGUID: guid),
              let ctx = context(for: session) else {
            return nil
        }
        return ctx.workgroupID
    }

    // The workgroup + role that owns `session`; the reverse of looking
    // a session up by GUID. Standalone sessions resolve to the synthetic
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
            statusSource: statusSource(for: resolved.session),
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
            statusSource: statusSource(for: session),
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
        return screenContents(forSession: resolved.session,
                              requestedLines: requestedLines)
    }

    // Session-based core, used directly by ScreenWatchPoller (which holds
    // a PTYSession, not a ResolvedTarget). The display-name fields on
    // ResolvedTarget aren't needed to render the screen, so the resolved
    // overload above just forwards here.
    static func screenContents(forSession session: PTYSession,
                               requestedLines: Int?) -> ScreenContents {
        let kind = kind(for: session)
        let pending = pendingActionDescription(for: session)
        let surface = screenSurface(for: session)
        let mouseReporting = scrollReportingSupported(for: session)
        // The (soft) alternate screen is the deciding factor, not `kind`:
        // a full-screen app repaints into scrollback, so the only
        // meaningful text is the current grid. This holds even for
        // claude-code sessions, which now run on the alternate screen
        // (their Ink frames would otherwise look like dozens of duplicate
        // screens in the transcript). Expose just the visible grid and let
        // the agent scroll the wheel to reveal older content.
        if surface == .alternate {
            return ScreenContents(text: snapshot(of: session),
                                  kind: kind,
                                  isSnapshot: true,
                                  screen: .alternate,
                                  mouseReporting: mouseReporting,
                                  pendingAction: pending)
        }
        // Primary screen: scrollback is real linear history.
        let text = trailingTranscript(of: session,
                                      lines: requestedLines ?? 100)
        return ScreenContents(text: text,
                              kind: kind,
                              isSnapshot: false,
                              screen: .primary,
                              mouseReporting: mouseReporting,
                              pendingAction: pending)
    }

    // Semantic screen surface: alternate when the program is on (or would
    // be on, per the soft flag) the alternate buffer. We use the soft flag
    // rather than which VT100Grid is actually visible so the answer
    // reflects the program's intent even when the user has disabled
    // iTerm2's alternate-screen feature. A soft-alternate session is
    // almost certainly a TUI.
    static func screenSurface(for session: PTYSession) -> ScreenSurface {
        return session.screen.terminalSoftAlternateScreenMode ? .alternate : .primary
    }

    // Whether the foreground program reports scroll-wheel events, i.e.
    // whether the scroll_wheel tool can do anything. This is the same
    // predicate the scroll path itself gates on (highlight-tracking mode
    // is excluded because it never reports scroll), so the mouse_reporting
    // hint we surface and the tool's real behavior agree. Reads
    // PTYSession's ObjC accessor so we don't reference the C MouseMode
    // enum from Swift.
    static func scrollReportingSupported(for session: PTYSession) -> Bool {
        return session.scrollWheelReportingEnabled
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
    // the orchestrator watches — which silently swallows watcher fires.
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

    // Whether the session exposes a machine-readable status source we
    // can build exact tab-status-transition watchers on. True only when
    // a recognized status string (idle/working/waiting) is currently
    // present — the cc-status hook and set_status triggers always keep
    // one set, even at idle. Sessions without that source (plain TUIs,
    // coding agents that don't emit OSC 21337, bare shells) return false,
    // and the dispatcher falls back to screen-observation watching for
    // them. A status-reporting session momentarily between strings would
    // be misread as statusless and get a screen poller instead; that's a
    // harmless degradation (the poller still works), not a correctness
    // bug, so we don't try to remember historical status here.
    static func reportsSessionStatus(_ session: PTYSession) -> Bool {
        guard let text = session.tabStatus?.statusText?.lowercased(),
              !text.isEmpty else {
            return false
        }
        return text == "idle" || text == "working" || text == "waiting"
    }

    // The agent-facing form of reportsSessionStatus, carried on
    // list_workgroups and get_state output so the agent can tell whether
    // `status` is authoritative before deciding how to watch a session.
    static func statusSource(for session: PTYSession) -> StatusSource {
        return reportsSessionStatus(session) ? .reported : .inferred
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
        // Visible-screen-only range: skip the scrollback portion of
        // the line index.
        let scrollback = session.screen.numberOfScrollbackLines()
        let height = session.screen.height()
        return extractScreenText(ofScreen: session.screen,
                                  fromLine: scrollback,
                                  toLine: scrollback + height)
    }

    private static func trailingTranscript(of session: PTYSession, lines: Int) -> String {
        // Clamp to a sane range. An LLM that asks for 0 / -1 / a huge
        // value to "see the whole buffer" would otherwise blow its own
        // context window and ours on a long-running shell. The schema
        // documents a default of 100; cap the request to 2000 lines to
        // bound the response size without being mean to legitimate
        // "give me a lot of context" calls.
        let total = session.screen.numberOfLines()
        let clamped = Int32(max(1, min(2000, lines)))
        let start = max(Int32(0), total - clamped)
        return extractScreenText(ofScreen: session.screen, fromLine: start, toLine: total)
    }

    // Markup tokens woven into the extracted text so the agent can tell
    // rendered decoration apart from real content. The angle-bracket
    // characters are U+27E8/U+27E9 (mathematical angle brackets), which
    // effectively never occur in real terminal output, so a literal
    // occurrence won't be confused with our markup. These tokens are
    // documented in the get_screen_contents tool description; keep the
    // two in sync.
    private static let dimOpenMarkup = "\u{27E8}dim\u{27E9}"
    private static let dimCloseMarkup = "\u{27E8}/dim\u{27E9}"
    private static let cursorMarkup = "\u{27E8}cursor\u{27E9}"
    private static let imagePlaceholder = "\u{27E8}image\u{27E9}"

    // Attribute key used to ferry the per-cell faint bit out of the
    // extractor's attributeProvider and into renderAttributed. Internal
    // (not private) only so unit tests can synthesize faint runs to feed
    // renderAttributed directly.
    static let faintAttributeKey = NSAttributedString.Key("iTermIntrospectionFaint")

    // Pull text for a half-open line range [fromLine, toLine) using
    // iTermTextExtractor. This is the same path PTYSession's
    // RemoteCommand surface and ToolCodecierge use, so we get real
    // Unicode (box-drawing, emoji, complex chars) instead of the
    // debug-dump character substitutions VT100Grid.compactLineDump
    // produces (`.` for empty cells, `?` for code>127). Empty cells
    // become spaces; trailing whitespace per line is stripped by the
    // extractor itself; trailing all-blank rows are stripped by
    // stripTrailingBlankLines below.
    //
    // For image cells the extractor doesn't have a string
    // representation, so we pass a non-nil attributeProvider to get
    // an NSAttributedString that carries NSTextAttachment markers at
    // image positions, then collapse consecutive cells of the same
    // image into a single ⟨image⟩ placeholder.
    //
    // The attributeProvider also tags faint (dim/SGR-2) cells so
    // renderAttributed can wrap them in ⟨dim⟩…⟨/dim⟩. Inline shell
    // suggestions (zsh-autosuggestions, fish autosuggest) and ghost
    // completions in TUIs like Claude Code are rendered faint; without
    // this marker they look byte-for-byte identical to text the user
    // actually typed, which routinely fools an agent reading the screen.
    // We also request the per-character grid coords so we can splice in
    // a ⟨cursor⟩ marker at the cursor's position.
    //
    // Takes the VT100Screen rather than the owning PTYSession so unit
    // tests can drive it with a screen built from raw terminal input.
    static func extractScreenText(ofScreen screen: VT100Screen,
                                  fromLine startY: Int32,
                                  toLine endY: Int32) -> String {
        guard endY > startY else { return "" }
        let extractor = iTermTextExtractor(dataSource: screen)
        let range = VT100GridWindowedRange(
            coordRange: VT100GridCoordRange(
                start: VT100GridCoord(x: 0, y: startY),
                end: VT100GridCoord(x: 0, y: endY)),
            columnWindow: VT100GridRange(location: 0, length: 0))
        let coords = GridCoordArray()
        let content = extractor.content(
            in: range,
            attributeProvider: { theChar, _, _ in
                ScreenCharIsFaint(theChar) ? [faintAttributeKey: true] : [:]
            },
            nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
            pad: false,
            includeLastNewline: false,
            trimTrailingWhitespace: true,
            cappedAtSize: -1,
            truncateTail: false,
            continuationChars: nil,
            coords: coords,
            deduplicateDECDHL: true)
        let raw: String
        if let attributed = content as? NSAttributedString {
            let cursorIndex = cursorMarkupIndex(coords: coords,
                                                screen: screen,
                                                fromLine: startY,
                                                toLine: endY,
                                                length: attributed.length)
            raw = renderAttributed(attributed, cursorIndex: cursorIndex)
        } else if let plain = content as? String {
            raw = plain
        } else {
            raw = ""
        }
        return stripTrailingBlankLines(raw)
    }

    // Returns the index into the attributed string where a ⟨cursor⟩
    // marker should be spliced, or nil if the cursor is outside the
    // extracted range. `coords` is the extractor's per-character grid
    // coordinate array; it stays length-aligned with the attributed
    // string (image attachments contribute one coord per
    // object-replacement char). cursorX/cursorY from the screen are
    // 1-based, matching PTYSession's own usage.
    //
    // Priority: (1) the first character at/after the cursor on the
    // cursor's own line — this lands the marker exactly before a faint
    // suggestion that begins at the cursor. (2) Otherwise just past the
    // last character on the cursor line — the common "cursor sits at end
    // of typed input, no suggestion" case, so the marker shouldn't jump
    // to the next line. (3) Otherwise the start of the next line, or end
    // of string. Coords are emitted in reading order (line-major), so a
    // single forward pass suffices.
    private static func cursorMarkupIndex(coords: GridCoordArray,
                                          screen: VT100Screen,
                                          fromLine startY: Int32,
                                          toLine endY: Int32,
                                          length: Int) -> Int? {
        let cursorY = Int32(screen.numberOfScrollbackLines())
            + Int32(screen.cursorY()) - 1
        guard cursorY >= startY, cursorY < endY else { return nil }
        let cursorX = Int32(screen.cursorX()) - 1
        let count = min(coords.count, length)
        var lastOnLineEnd: Int? = nil
        for i in 0..<count {
            let c = coords[i]
            if c.y < cursorY {
                continue
            }
            if c.y == cursorY {
                if c.x >= cursorX {
                    return i
                }
                lastOnLineEnd = i + 1
            } else {
                // Past the cursor line; everything on it has been seen.
                return lastOnLineEnd ?? i
            }
        }
        return lastOnLineEnd ?? length
    }

    // Walk an attributed string and emit text verbatim, replacing runs
    // of NSTextAttachment image cells with a single ⟨image⟩ placeholder
    // per distinct image, wrapping faint runs in ⟨dim⟩…⟨/dim⟩, and
    // splicing a ⟨cursor⟩ marker at cursorIndex. The extractor builds a
    // fresh NSTextAttachment per cell, but every cell of the same image
    // points its NSTextAttachment.image at the same NSImage instance, so
    // identity comparison dedupes consecutive image cells.
    // Internal (not private) so unit tests can verify ⟨image⟩ markup,
    // which is impractical to produce from a real screen in a test.
    static func renderAttributed(_ attributed: NSAttributedString,
                                 cursorIndex: Int?) -> String {
        let result = NSMutableString()
        var dimIsOpen = false
        var lastImageID: ObjectIdentifier? = nil
        let length = attributed.length
        var location = 0
        while location < length {
            var runRange = NSRange(location: 0, length: 0)
            let attrs = attributed.attributes(at: location, effectiveRange: &runRange)
            let runStart = location
            let runEnd = runRange.location + runRange.length
            let attachment = attrs[.attachment] as? NSTextAttachment
            let isImage = attachment != nil
            // Image cells carry no faint semantics; treat them as not dim.
            let wantDim = !isImage && (attrs[faintAttributeKey] as? Bool == true)
            if wantDim && !dimIsOpen {
                result.append(dimOpenMarkup)
                dimIsOpen = true
            } else if !wantDim && dimIsOpen {
                result.append(dimCloseMarkup)
                dimIsOpen = false
            }
            if let attachment {
                if let ci = cursorIndex, ci >= runStart, ci < runEnd {
                    result.append(cursorMarkup)
                }
                let id = attachment.image.map { ObjectIdentifier($0) }
                if id == nil || id != lastImageID {
                    result.append(imagePlaceholder)
                    lastImageID = id
                }
            } else {
                lastImageID = nil
                let runText = attributed.attributedSubstring(
                    from: NSRange(location: runStart, length: runEnd - runStart)).string as NSString
                if let ci = cursorIndex, ci >= runStart, ci < runEnd {
                    let splitOffset = ci - runStart
                    result.append(runText.substring(to: splitOffset))
                    result.append(cursorMarkup)
                    result.append(runText.substring(from: splitOffset))
                } else {
                    result.append(runText as String)
                }
            }
            location = runEnd
        }
        if dimIsOpen {
            result.append(dimCloseMarkup)
        }
        if cursorIndex == length {
            result.append(cursorMarkup)
        }
        return result as String
    }

    // Drop trailing rows that are all whitespace. The extractor
    // already trims trailing whitespace within a line, so a "blank
    // line" here is an empty string after split. Useful for snapshot
    // views of long-running TUIs whose bottom half is unused.
    private static func stripTrailingBlankLines(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        while let last = lines.last,
              last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
