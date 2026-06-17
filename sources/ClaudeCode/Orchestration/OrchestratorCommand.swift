//
//  OrchestratorCommand.swift
//  iTerm2SharedARC
//

import Foundation

// The tool surface the chat-orchestration mode presents to the LLM.
// Mirrors AITerm's RemoteCommand in role but with a fundamentally
// different domain: instead of a single session's actions
// (.runCommand / .typeForYou / .actInWebBrowser), the orchestrator
// drives many workgroups, addresses sessions by their GUID, and
// supports multiplexed waits over a monitored set.
//
// Every session-acting tool addresses its target with a single
// session_guid string, copied verbatim from the per-turn
// <workgroups> snapshot (each role carries a session_guid field). A
// GUID is globally unique, so it pins exactly one session; the owning
// workgroup and role are derived app-side via
// WorkgroupIntrospection.resolve(sessionGuid:). This is the same way
// the session_* tool family addresses sessions, so the two families
// are consistent. Standalone sessions (those not in a user-defined
// workgroup) resolve to a synthetic single-session workgroup; the
// agent never has to know the difference.
//
// Permissions are still claimed at the workgroup level: approving a
// workgroup approves all its roles. A session-targeted write resolves
// the session to its workgroup scope (a real instance ID, or
// "session:<guid>" for a standalone session) before gating. Read-only
// / monitoring / blocking tools require no claim; write tools
// (.sendText, .interrupt, .addWorkgroupClipping) do; .startSession
// always prompts.

// MARK: - Args

struct ListSessionsInWorkgroupArgs: Codable {
    let workgroupID: String
    enum CodingKeys: String, CodingKey { case workgroupID = "workgroup_id" }
}

struct SendTextArgs: Codable {
    let sessionGuid: String
    let text: String
    // nil treated as true at the dispatcher.
    let appendNewline: Bool?

    enum CodingKeys: String, CodingKey {
        case sessionGuid = "session_guid"
        case text
        case appendNewline = "append_newline"
    }
}

struct GetScreenContentsArgs: Codable {
    let sessionGuid: String
    let lines: Int?  // nil → default 100

    enum CodingKeys: String, CodingKey {
        case sessionGuid = "session_guid"
        case lines
    }
}

struct RegisterWatchArgs: Codable {
    let sessionGuid: String
    // Exactly one of targetState / condition must be supplied; the
    // dispatcher validates and rejects otherwise.
    let targetState: SessionState?
    // Plain-English condition judged by reading the screen, e.g.
    // "emacs has exited and a shell prompt is showing".
    let condition: String?
    // The user asked to be alerted: push to the paired phone when the
    // watch fires.
    let notifyUser: Bool?
    enum CodingKeys: String, CodingKey {
        case sessionGuid = "session_guid"
        case targetState = "target_state"
        case condition
        case notifyUser = "notify_user"
    }
}

struct StartCodeReviewArgs: Codable {
    let sessionGuid: String
    // Pick the prompt by name from the user's saved prompts (see
    // the saved-prompts list in the system message). Mutually
    // exclusive with custom_prompt; if both are nil the dispatcher
    // uses the user's currently-default prompt.
    let promptName: String?
    // Free-form prompt text when no saved prompt fits the request.
    // Mutually exclusive with prompt_name.
    let customPrompt: String?
    enum CodingKeys: String, CodingKey {
        case sessionGuid = "session_guid"
        case promptName = "prompt_name"
        case customPrompt = "custom_prompt"
    }
}

struct AddClippingArgs: Codable {
    let workgroupID: String
    let type: String
    let title: String
    let detail: String
    enum CodingKeys: String, CodingKey {
        case workgroupID = "workgroup_id"
        case type
        case title
        case detail
    }
}

struct StartSessionArgs: Codable {
    let profile: String?
    let command: String?
    let cwd: String?
    let window: SpawnWindowChoice?  // nil → .tab
}

// MARK: - Enums

// SessionState moved to WorkgroupWatcher.swift (shared with the iOS
// companion app).

enum SpawnWindowChoice: String, Codable {
    case new
    case current
    case tab
}

enum SessionKind: String, Codable {
    case claudeCode = "claude-code"  // hook events are the source of truth
    case shell                       // linear scrollback is the source of truth
    case tui                         // interactive app; only the rendered screen is meaningful
    case other                       // fallback when classification fails
}

// Where a session's idle/working/waiting status comes from. Surfaced on
// list_workgroups and get_state so the agent knows whether `status` is
// authoritative (the program announces it via OSC 21337 / the cc-status
// hook) or a guess derived from indicators, and can pick the right
// register_watch form accordingly.
enum StatusSource: String, Codable {
    case reported   // machine-readable; state watchers fire on exact transitions
    case inferred   // best-effort guess; state watchers fall back to screen observation
}

// MARK: - Tool names

// Single source of truth for the wire-format tool names. Both the
// dispatcher's decoder and the static tool-definition list reference
// these via rawValue so a rename only needs to happen here. Switching
// on this in the dispatcher also makes adding a new tool a compile
// error until the dispatch arm is added.
enum ToolName: String, CaseIterable {
    case listWorkgroups = "list_workgroups"
    case getState = "get_state"
    case getScreenContents = "get_screen_contents"
    case listWorkgroupClippings = "list_workgroup_clippings"
    case sendText = "send_text"
    case interrupt = "interrupt"
    case addWorkgroupClipping = "add_workgroup_clipping"
    case startSession = "start_session"
    case startCodeReview = "start_code_review"
    case registerWatch = "register_watch"
    case unregisterWatch = "unregister_watch"
    case listWatches = "list_watches"
    case notify = "notify"
    case requestNotificationPermission = "request_notification_permission"
}

// MARK: - Command

enum OrchestratorCommand {
    // Discovery
    case listWorkgroups
    case getState(sessionGuid: String)
    case getScreenContents(GetScreenContentsArgs)
    case listWorkgroupClippings(workgroupID: String, typeFilter: String?)

    // Action
    case sendText(SendTextArgs)
    case interrupt(sessionGuid: String)
    case addWorkgroupClipping(AddClippingArgs)
    // Convenience action: populate the Code Review prompt overlay
    // with the chosen prompt and start the review. Auto-registers a
    // watcher for the Code Review role reaching .idle so the agent
    // gets a status_update when the review completes.
    case startCodeReview(StartCodeReviewArgs)

    // Spawn
    case startSession(StartSessionArgs)

    // Async watchers. Non-blocking — register_watch returns
    // immediately; iTerm2 delivers a status_update message into the
    // chat when the watched condition fires.
    case registerWatch(RegisterWatchArgs)
    case unregisterWatch(watcherID: String)
    case listWatches

    // Push a notification to the user's paired companion phone. Only
    // offered to the model while a companion phone is paired.
    case notify(NotifyArgs)

    // Ask the user (via their connected phone) for notification permission.
    // Only offered while a phone is connected but cannot yet receive pushes.
    case requestNotificationPermission

    // Categorization drives the safety/dispatch policy.
    enum Category {
        case readOnly       // no claim, no special handling
        case watcher        // no claim, manipulates the async watch list
        case write          // requires the target workgroup to be claimed
        case spawn          // start_session. gated by gateSpawn:
                            // auto-approved when safe, prompts otherwise
    }

    var category: Category {
        switch self {
        case .listWorkgroups, .getState, .getScreenContents,
                .listWorkgroupClippings:
            return .readOnly
        case .sendText, .interrupt, .addWorkgroupClipping, .startCodeReview:
            return .write
        case .startSession:
            return .spawn
        case .registerWatch, .unregisterWatch, .listWatches:
            return .watcher
        case .notify, .requestNotificationPermission:
            // These touch the user's own phone, not a session, so they
            // need no claim or prompt (iOS shows its own permission UI).
            return .readOnly
        }
    }

    // How a .write tool's claim is determined. Session-targeted writes
    // carry a session_guid that the dispatcher resolves to its
    // workgroup scope before gating; add_workgroup_clipping is
    // workgroup-scoped and claims its workgroup_id directly. Other
    // tools need no claim.
    enum ClaimRequirement {
        case none
        case workgroup(String)   // claim this workgroup_id directly
        case session(String)     // resolve this session_guid to its scope
    }

    var claimRequirement: ClaimRequirement {
        switch self {
        case .sendText(let args):
            return .session(args.sessionGuid)
        case .interrupt(let sessionGuid):
            return .session(sessionGuid)
        case .startCodeReview(let args):
            return .session(args.sessionGuid)
        case .addWorkgroupClipping(let args):
            return .workgroup(args.workgroupID)
        case .listWorkgroups, .getState, .getScreenContents,
                .listWorkgroupClippings,
                .startSession,
                .registerWatch, .unregisterWatch, .listWatches,
                .notify, .requestNotificationPermission:
            return .none
        }
    }
}

// MARK: - Notify

struct NotifyArgs: Codable {
    let title: String
    let body: String
}

// MARK: - Result

// Per-tool result types. Each Codable so the dispatcher can serialize
// them as the tool-use response back to the model.
//
// Custom encode(to:) for snake_case on the wire. Synthesized Codable
// for an enum with associated values uses Swift's camelCase property
// labels verbatim ("workgroupID"), which clashes with the snake_case
// convention used by tool inputs ("workgroup_id"). The custom encoder
// emits a single-key envelope per case with the case name in
// snake_case, and the associated payload encoded directly (its own
// CodingKeys already use snake_case for nested fields). Decode is not
// implemented because the result is outbound-only.
enum OrchestratorResult: Encodable {
    case ack
    case workgroups([WorkgroupSummary])
    case sessionState(SessionStateInfo)
    case screenContents(ScreenContents)
    case clippings([ClippingInfo])
    case startedSession(sessionGuid: String)
    case watcherRegistered(WatcherDescription)
    case watcherList([WatcherDescription])
    case error(code: String, message: String)

    private enum EnvelopeKey: String, CodingKey {
        case ack
        case workgroups
        case sessionState = "session_state"
        case screenContents = "screen_contents"
        case clippings
        case startedSession = "started_session"
        case watcherRegistered = "watcher_registered"
        case watcherList = "watcher_list"
        case error
    }

    private struct StartedSessionPayload: Encodable {
        let sessionGuid: String
        enum CodingKeys: String, CodingKey {
            case sessionGuid = "session_guid"
        }
    }

    private struct ErrorPayload: Encodable {
        let code: String
        let message: String
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: EnvelopeKey.self)
        switch self {
        case .ack:
            try c.encode(true, forKey: .ack)
        case .workgroups(let v):
            try c.encode(v, forKey: .workgroups)
        case .sessionState(let v):
            try c.encode(v, forKey: .sessionState)
        case .screenContents(let v):
            try c.encode(v, forKey: .screenContents)
        case .clippings(let v):
            try c.encode(v, forKey: .clippings)
        case .startedSession(let sessionGuid):
            try c.encode(StartedSessionPayload(sessionGuid: sessionGuid),
                         forKey: .startedSession)
        case .watcherRegistered(let v):
            try c.encode(v, forKey: .watcherRegistered)
        case .watcherList(let v):
            try c.encode(v, forKey: .watcherList)
        case .error(let code, let message):
            try c.encode(ErrorPayload(code: code, message: message), forKey: .error)
        }
    }
}

// Public-facing description of a registered watcher. Used as
// register_watch's response (the agent gets the assigned watcher_id
// and a copy of the params it asked for) and as each entry in
// list_watches.
struct WatcherDescription: Codable {
    let watcherID: String
    let workgroupID: String
    let workgroupName: String
    let roleID: String
    let roleName: String
    // Exactly one of targetState / condition is set, mirroring the
    // register_watch form that created the watcher.
    let targetState: SessionState?
    let condition: String?
    let registeredAt: String  // ISO 8601
    enum CodingKeys: String, CodingKey {
        case watcherID = "watcher_id"
        case workgroupID = "workgroup_id"
        case workgroupName = "workgroup_name"
        case roleID = "role_id"
        case roleName = "role_name"
        case targetState = "target_state"
        case condition
        case registeredAt = "registered_at"
    }
}

// Result of get_screen_contents. Carries the kind of the underlying
// session so the agent knows how to read the text:
//   - .shell: linear transcript; trailing lines are most recent
//   - .tui: snapshot of the current rendered display; no history is
//     preserved between calls. each call returns whatever's on
//     screen *now*
//   - .claudeCode: synthesized from recent hook events (assistant
//     messages, tool calls), not the raw Ink-rendered frame
//   - .other: best-effort scrollback
//
// The `is_snapshot` flag is the bottom-line signal the agent should
// react to. true means "don't assume any history is here". but
// `kind` carries the why.
struct ScreenContents: Codable {
    let text: String
    let kind: SessionKind
    let isSnapshot: Bool
    // Same surface as SessionStateInfo.pendingAction. Mirrored here
    // because the agent often calls get_screen_contents to figure
    // out what's going on; the screen alone won't tell it that a
    // prompt overlay is up (the overlay is an NSView, not in the PTY
    // buffer), so we surface it explicitly.
    let pendingAction: String?
    enum CodingKeys: String, CodingKey {
        case text
        case kind
        case isSnapshot = "is_snapshot"
        case pendingAction = "pending_action"
    }
}

struct WorkgroupSummary: Codable {
    let workgroupID: String
    let workgroupName: String
    let sessions: [SessionSummary]
    enum CodingKeys: String, CodingKey {
        case workgroupID = "workgroup_id"
        case workgroupName = "workgroup_name"
        case sessions
    }
}

struct SessionSummary: Codable {
    let roleID: String
    let roleName: String
    // Raw PTYSession GUID. Exposed so the agent can pass it to the
    // session_<command> tools that take a session_guid directly,
    // bypassing workgroup-role addressing when that's more natural.
    let sessionGuid: String
    let kind: SessionKind
    let status: SessionState
    // Whether `status` is announced by the program (reported) or a
    // best-effort guess (inferred). See StatusSource.
    let statusSource: StatusSource
    let lastActivityISO: String?
    let currentCommand: String?
    // Same surface as SessionStateInfo.pendingAction. Carried on the
    // snapshot so the agent doesn't have to call get_state on every
    // .waiting role to find out what it's blocked on — without this,
    // `status: "waiting"` invites guesses like "send 'yes'".
    let pendingAction: String?
    enum CodingKeys: String, CodingKey {
        case roleID = "role_id"
        case roleName = "role_name"
        case sessionGuid = "session_guid"
        case kind
        case status
        case statusSource = "status_source"
        case lastActivityISO = "last_activity_iso"
        case currentCommand = "current_command"
        case pendingAction = "pending_action"
    }
}

struct SessionStateInfo: Codable {
    let workgroupID: String
    let workgroupName: String
    let roleID: String
    let roleName: String
    let kind: SessionKind
    let status: SessionState
    // Whether `status` is announced by the program (reported) or a
    // best-effort guess (inferred). See StatusSource.
    let statusSource: StatusSource
    let lastActivityISO: String?
    let currentCommand: String?
    let lastMessage: String?  // last cc-status detail for CC sessions
    // Non-nil when the role is blocked on a UI affordance the agent
    // can act on (e.g. the Code Review prompt overlay). The string
    // describes what's expected and how to unblock it; the agent
    // shouldn't try to infer this from screen contents.
    let pendingAction: String?
    enum CodingKeys: String, CodingKey {
        case workgroupID = "workgroup_id"
        case workgroupName = "workgroup_name"
        case roleID = "role_id"
        case roleName = "role_name"
        case kind
        case status
        case statusSource = "status_source"
        case lastActivityISO = "last_activity_iso"
        case currentCommand = "current_command"
        case lastMessage = "last_message"
        case pendingAction = "pending_action"
    }
}

struct ClippingInfo: Codable {
    let type: String
    let title: String
    let detail: String
}

