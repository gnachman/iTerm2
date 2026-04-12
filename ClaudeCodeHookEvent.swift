// ClaudeCodeHookEvent.swift
//
// Codable types representing all Claude Code hook event payloads.
//
// Reference: https://code.claude.com/docs/en/hooks
//
// Hook commands receive JSON on stdin. Every event includes a common set of
// base fields; each event type adds its own additional fields. This file
// models both layers so that any hook payload can be decoded with:
//
//     let event = try JSONDecoder().decode(ClaudeCodeHookEvent.self, from: data)
//

import Foundation

// MARK: - Top-Level Event

/// A single hook event received from Claude Code.
///
/// All events share the base fields (`sessionID`, `cwd`, etc.). The
/// `hookEventName` discriminator selects which event-specific fields are
/// present; those are decoded into the `payload` enum.
///
/// Reference: https://code.claude.com/docs/en/hooks#hook-input-data
public struct ClaudeCodeHookEvent: Codable, Sendable {
    /// Unique identifier for the Claude Code session.
    public let sessionID: String

    /// Path to the session's JSONL transcript file.
    public let transcriptPath: String?

    /// Working directory at the time the event fired.
    public let cwd: String?

    /// The active permission mode.
    public let permissionMode: PermissionMode?

    /// Discriminator identifying which hook event fired.
    public let hookEventName: HookEventName

    /// Subagent identifier, present only for events fired from a subagent.
    public let agentID: String?

    /// Subagent type, present only for events fired from a subagent.
    public let agentType: String?

    /// Event-specific fields, decoded based on `hookEventName`.
    public let payload: HookEventPayload

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case permissionMode = "permission_mode"
        case hookEventName = "hook_event_name"
        case agentID = "agent_id"
        case agentType = "agent_type"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        permissionMode = try container.decodeIfPresent(PermissionMode.self, forKey: .permissionMode)
        hookEventName = try container.decode(HookEventName.self, forKey: .hookEventName)
        agentID = try container.decodeIfPresent(String.self, forKey: .agentID)
        agentType = try container.decodeIfPresent(String.self, forKey: .agentType)

        // Decode event-specific payload from the same top-level object.
        payload = try HookEventPayload(from: decoder, eventName: hookEventName)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(transcriptPath, forKey: .transcriptPath)
        try container.encodeIfPresent(cwd, forKey: .cwd)
        try container.encodeIfPresent(permissionMode, forKey: .permissionMode)
        try container.encode(hookEventName, forKey: .hookEventName)
        try container.encodeIfPresent(agentID, forKey: .agentID)
        try container.encodeIfPresent(agentType, forKey: .agentType)
        try payload.encode(to: encoder)
    }
}

// MARK: - Enums

/// Claude Code permission modes.
/// Reference: https://code.claude.com/docs/en/hooks#hook-input-data
public enum PermissionMode: String, Codable, Sendable {
    case `default`
    case plan
    case acceptEdits
    case auto
    case dontAsk
    case bypassPermissions
}

/// All supported hook event names.
/// Reference: https://code.claude.com/docs/en/hooks#available-hook-events
public enum HookEventName: String, Codable, Sendable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case postToolUseFailure = "PostToolUseFailure"
    case permissionRequest = "PermissionRequest"
    case permissionDenied = "PermissionDenied"
    case notification = "Notification"
    case stop = "Stop"
    case stopFailure = "StopFailure"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
    case taskCreated = "TaskCreated"
    case taskCompleted = "TaskCompleted"
    case teammateIdle = "TeammateIdle"
    case instructionsLoaded = "InstructionsLoaded"
    case configChange = "ConfigChange"
    case cwdChanged = "CwdChanged"
    case fileChanged = "FileChanged"
    case worktreeCreate = "WorktreeCreate"
    case worktreeRemove = "WorktreeRemove"
    case preCompact = "PreCompact"
    case postCompact = "PostCompact"
    case elicitation = "Elicitation"
    case elicitationResult = "ElicitationResult"
}

/// Notification subtypes.
/// Reference: https://code.claude.com/docs/en/hooks — Notification matcher values.
public enum NotificationType: String, Codable, Sendable {
    case permissionPrompt = "permission_prompt"
    case idlePrompt = "idle_prompt"
    case authSuccess = "auth_success"
    case elicitationDialog = "elicitation_dialog"
}

/// SessionStart source values (also used as matcher).
/// Reference: https://code.claude.com/docs/en/hooks — SessionStart matcher values.
public enum SessionStartSource: String, Codable, Sendable {
    case startup
    case resume
    case clear
    case compact
}

/// SessionEnd reason values (also used as matcher).
/// Reference: https://code.claude.com/docs/en/hooks — SessionEnd matcher values.
public enum SessionEndReason: String, Codable, Sendable {
    case clear
    case resume
    case logout
    case promptInputExit = "prompt_input_exit"
    case bypassPermissionsDisabled = "bypass_permissions_disabled"
    case other
}

/// StopFailure error type values (also used as matcher).
/// Reference: https://code.claude.com/docs/en/hooks — StopFailure matcher values.
public enum StopFailureErrorType: String, Codable, Sendable {
    case rateLimit = "rate_limit"
    case authenticationFailed = "authentication_failed"
    case billingError = "billing_error"
    case invalidRequest = "invalid_request"
    case serverError = "server_error"
    case maxOutputTokens = "max_output_tokens"
    case unknown
}

/// InstructionsLoaded memory types.
/// Reference: https://code.claude.com/docs/en/hooks — InstructionsLoaded fields.
public enum InstructionsMemoryType: String, Codable, Sendable {
    case user = "User"
    case project = "Project"
    case local = "Local"
    case managed = "Managed"
}

/// InstructionsLoaded load reason values (also used as matcher).
/// Reference: https://code.claude.com/docs/en/hooks — InstructionsLoaded matcher values.
public enum InstructionsLoadReason: String, Codable, Sendable {
    case sessionStart = "session_start"
    case nestedTraversal = "nested_traversal"
    case pathGlobMatch = "path_glob_match"
    case include
    case compact
}

/// Compact trigger values (PreCompact / PostCompact matcher).
/// Reference: https://code.claude.com/docs/en/hooks — PreCompact matcher values.
public enum CompactTrigger: String, Codable, Sendable {
    case manual
    case auto
}

// MARK: - Event-Specific Payloads

/// Discriminated union of event-specific fields.
///
/// The additional fields are decoded from the same top-level JSON object
/// as the base fields — Claude Code uses a flat structure, not a nested
/// "payload" key.
public enum HookEventPayload: Sendable {
    /// https://code.claude.com/docs/en/hooks — SessionStart
    case sessionStart(SessionStartPayload)

    /// https://code.claude.com/docs/en/hooks — SessionEnd
    case sessionEnd(SessionEndPayload)

    /// https://code.claude.com/docs/en/hooks — UserPromptSubmit
    case userPromptSubmit(UserPromptSubmitPayload)

    /// https://code.claude.com/docs/en/hooks — PreToolUse
    case preToolUse(ToolUsePayload)

    /// https://code.claude.com/docs/en/hooks — PostToolUse
    case postToolUse(PostToolUsePayload)

    /// https://code.claude.com/docs/en/hooks — PostToolUseFailure
    case postToolUseFailure(PostToolUseFailurePayload)

    /// https://code.claude.com/docs/en/hooks — PermissionRequest
    case permissionRequest(PermissionRequestPayload)

    /// https://code.claude.com/docs/en/hooks — PermissionDenied
    case permissionDenied(PermissionDeniedPayload)

    /// https://code.claude.com/docs/en/hooks — Notification
    case notification(NotificationPayload)

    /// https://code.claude.com/docs/en/hooks — Stop
    case stop(StopPayload)

    /// https://code.claude.com/docs/en/hooks — StopFailure
    case stopFailure(StopFailurePayload)

    /// https://code.claude.com/docs/en/hooks — SubagentStart
    case subagentStart(SubagentStartPayload)

    /// https://code.claude.com/docs/en/hooks — SubagentStop
    case subagentStop(SubagentStopPayload)

    /// https://code.claude.com/docs/en/hooks — TaskCreated
    case taskCreated(TaskCreatedPayload)

    /// https://code.claude.com/docs/en/hooks — TaskCompleted
    case taskCompleted(TaskCompletedPayload)

    /// https://code.claude.com/docs/en/hooks — TeammateIdle
    case teammateIdle(TeammateIdlePayload)

    /// https://code.claude.com/docs/en/hooks — InstructionsLoaded
    case instructionsLoaded(InstructionsLoadedPayload)

    /// https://code.claude.com/docs/en/hooks — ConfigChange
    case configChange(ConfigChangePayload)

    /// https://code.claude.com/docs/en/hooks — CwdChanged
    case cwdChanged(CwdChangedPayload)

    /// https://code.claude.com/docs/en/hooks — FileChanged
    case fileChanged(FileChangedPayload)

    /// https://code.claude.com/docs/en/hooks — WorktreeCreate
    case worktreeCreate(WorktreeCreatePayload)

    /// https://code.claude.com/docs/en/hooks — WorktreeRemove
    case worktreeRemove(WorktreeRemovePayload)

    /// https://code.claude.com/docs/en/hooks — PreCompact
    case preCompact(PreCompactPayload)

    /// https://code.claude.com/docs/en/hooks — PostCompact
    case postCompact(PostCompactPayload)

    /// https://code.claude.com/docs/en/hooks — Elicitation
    case elicitation(ElicitationPayload)

    /// https://code.claude.com/docs/en/hooks — ElicitationResult
    case elicitationResult(ElicitationResultPayload)

    init(from decoder: Decoder, eventName: HookEventName) throws {
        switch eventName {
        case .sessionStart:
            self = .sessionStart(try SessionStartPayload(from: decoder))
        case .sessionEnd:
            self = .sessionEnd(try SessionEndPayload(from: decoder))
        case .userPromptSubmit:
            self = .userPromptSubmit(try UserPromptSubmitPayload(from: decoder))
        case .preToolUse:
            self = .preToolUse(try ToolUsePayload(from: decoder))
        case .postToolUse:
            self = .postToolUse(try PostToolUsePayload(from: decoder))
        case .postToolUseFailure:
            self = .postToolUseFailure(try PostToolUseFailurePayload(from: decoder))
        case .permissionRequest:
            self = .permissionRequest(try PermissionRequestPayload(from: decoder))
        case .permissionDenied:
            self = .permissionDenied(try PermissionDeniedPayload(from: decoder))
        case .notification:
            self = .notification(try NotificationPayload(from: decoder))
        case .stop:
            self = .stop(try StopPayload(from: decoder))
        case .stopFailure:
            self = .stopFailure(try StopFailurePayload(from: decoder))
        case .subagentStart:
            self = .subagentStart(try SubagentStartPayload(from: decoder))
        case .subagentStop:
            self = .subagentStop(try SubagentStopPayload(from: decoder))
        case .taskCreated:
            self = .taskCreated(try TaskCreatedPayload(from: decoder))
        case .taskCompleted:
            self = .taskCompleted(try TaskCompletedPayload(from: decoder))
        case .teammateIdle:
            self = .teammateIdle(try TeammateIdlePayload(from: decoder))
        case .instructionsLoaded:
            self = .instructionsLoaded(try InstructionsLoadedPayload(from: decoder))
        case .configChange:
            self = .configChange(try ConfigChangePayload(from: decoder))
        case .cwdChanged:
            self = .cwdChanged(try CwdChangedPayload(from: decoder))
        case .fileChanged:
            self = .fileChanged(try FileChangedPayload(from: decoder))
        case .worktreeCreate:
            self = .worktreeCreate(try WorktreeCreatePayload(from: decoder))
        case .worktreeRemove:
            self = .worktreeRemove(try WorktreeRemovePayload(from: decoder))
        case .preCompact:
            self = .preCompact(try PreCompactPayload(from: decoder))
        case .postCompact:
            self = .postCompact(try PostCompactPayload(from: decoder))
        case .elicitation:
            self = .elicitation(try ElicitationPayload(from: decoder))
        case .elicitationResult:
            self = .elicitationResult(try ElicitationResultPayload(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .sessionStart(let p): try p.encode(to: encoder)
        case .sessionEnd(let p): try p.encode(to: encoder)
        case .userPromptSubmit(let p): try p.encode(to: encoder)
        case .preToolUse(let p): try p.encode(to: encoder)
        case .postToolUse(let p): try p.encode(to: encoder)
        case .postToolUseFailure(let p): try p.encode(to: encoder)
        case .permissionRequest(let p): try p.encode(to: encoder)
        case .permissionDenied(let p): try p.encode(to: encoder)
        case .notification(let p): try p.encode(to: encoder)
        case .stop(let p): try p.encode(to: encoder)
        case .stopFailure(let p): try p.encode(to: encoder)
        case .subagentStart(let p): try p.encode(to: encoder)
        case .subagentStop(let p): try p.encode(to: encoder)
        case .taskCreated(let p): try p.encode(to: encoder)
        case .taskCompleted(let p): try p.encode(to: encoder)
        case .teammateIdle(let p): try p.encode(to: encoder)
        case .instructionsLoaded(let p): try p.encode(to: encoder)
        case .configChange(let p): try p.encode(to: encoder)
        case .cwdChanged(let p): try p.encode(to: encoder)
        case .fileChanged(let p): try p.encode(to: encoder)
        case .worktreeCreate(let p): try p.encode(to: encoder)
        case .worktreeRemove(let p): try p.encode(to: encoder)
        case .preCompact(let p): try p.encode(to: encoder)
        case .postCompact(let p): try p.encode(to: encoder)
        case .elicitation(let p): try p.encode(to: encoder)
        case .elicitationResult(let p): try p.encode(to: encoder)
        }
    }
}

// MARK: - Payload Structs

/// SessionStart: fires when a session begins or resumes.
/// Matcher values: startup, resume, clear, compact.
public struct SessionStartPayload: Codable, Sendable {
    public let source: SessionStartSource?
    public let model: String?

    private enum CodingKeys: String, CodingKey {
        case source
        case model
    }
}

/// SessionEnd: fires when a session ends.
/// Matcher values: clear, resume, logout, prompt_input_exit,
/// bypass_permissions_disabled, other.
public struct SessionEndPayload: Codable, Sendable {
    public let reason: SessionEndReason?

    private enum CodingKeys: String, CodingKey {
        case reason
    }
}

/// UserPromptSubmit: fires when the user submits a prompt, before Claude
/// processes it.
public struct UserPromptSubmitPayload: Codable, Sendable {
    public let prompt: String?

    private enum CodingKeys: String, CodingKey {
        case prompt
    }
}

/// Shared fields for PreToolUse (and base of PostToolUse / PostToolUseFailure).
/// Matcher values: tool names — Bash, Edit, Write, Read, Glob, Grep, Agent,
/// WebFetch, WebSearch, mcp__<server>__<tool>, etc.
public struct ToolUsePayload: Codable, Sendable {
    public let toolName: String?
    /// Tool-specific input; structure varies per tool.
    public let toolInput: AnyCodable?
    public let toolUseID: String?

    private enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolUseID = "tool_use_id"
    }
}

/// PostToolUse: fires after a tool call succeeds.
/// Matcher values: tool names (same as PreToolUse).
public struct PostToolUsePayload: Codable, Sendable {
    public let toolName: String?
    public let toolInput: AnyCodable?
    public let toolResponse: AnyCodable?
    public let toolUseID: String?

    private enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolResponse = "tool_response"
        case toolUseID = "tool_use_id"
    }
}

/// PostToolUseFailure: fires after a tool call fails.
/// Matcher values: tool names (same as PreToolUse).
public struct PostToolUseFailurePayload: Codable, Sendable {
    public let toolName: String?
    public let toolInput: AnyCodable?
    public let toolUseID: String?
    public let error: String?
    public let isInterrupt: Bool?

    private enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolUseID = "tool_use_id"
        case error
        case isInterrupt = "is_interrupt"
    }
}

/// PermissionRequest: fires when a tool permission dialog is about to appear.
/// Matcher values: tool names.
public struct PermissionRequestPayload: Codable, Sendable {
    public let toolName: String?
    public let toolInput: AnyCodable?
    /// Array of permission suggestion objects.
    public let permissionSuggestions: [AnyCodable]?

    private enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case permissionSuggestions = "permission_suggestions"
    }
}

/// PermissionDenied: fires when a tool call is denied by the auto mode
/// classifier.
/// Matcher values: tool names.
public struct PermissionDeniedPayload: Codable, Sendable {
    public let toolName: String?
    public let toolInput: AnyCodable?
    public let toolUseID: String?
    public let reason: String?

    private enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolUseID = "tool_use_id"
        case reason
    }
}

/// Notification: fires when Claude Code sends a user-facing notification.
/// Matcher values: permission_prompt, idle_prompt, auth_success,
/// elicitation_dialog.
public struct NotificationPayload: Codable, Sendable {
    public let message: String?
    public let title: String?
    public let notificationType: NotificationType?

    private enum CodingKeys: String, CodingKey {
        case message
        case title
        case notificationType = "notification_type"
    }
}

/// Stop: fires when Claude finishes responding.
public struct StopPayload: Codable, Sendable {
    public let stopReason: String?
    public let stopHookActive: Bool?

    private enum CodingKeys: String, CodingKey {
        case stopReason = "stop_reason"
        case stopHookActive = "stop_hook_active"
    }
}

/// StopFailure: fires when a turn ends due to an API error.
/// Matcher values: rate_limit, authentication_failed, billing_error,
/// invalid_request, server_error, max_output_tokens, unknown.
public struct StopFailurePayload: Codable, Sendable {
    public let errorType: StopFailureErrorType?

    private enum CodingKeys: String, CodingKey {
        case errorType = "error_type"
    }
}

/// SubagentStart: fires when a subagent is spawned.
/// Matcher values: agent type names (Bash, Explore, Plan, or custom).
public struct SubagentStartPayload: Codable, Sendable {
    // agent_id and agent_type are in the base fields for subagent events.
}

/// SubagentStop: fires when a subagent finishes.
/// Matcher values: agent type names (same as SubagentStart).
public struct SubagentStopPayload: Codable, Sendable {
    public let stopHookActive: Bool?
    public let agentTranscriptPath: String?
    public let lastAssistantMessage: String?

    private enum CodingKeys: String, CodingKey {
        case stopHookActive = "stop_hook_active"
        case agentTranscriptPath = "agent_transcript_path"
        case lastAssistantMessage = "last_assistant_message"
    }
}

/// TaskCreated: fires when a task is being created via TaskCreate.
public struct TaskCreatedPayload: Codable, Sendable {
    public let taskID: String?
    public let taskSubject: String?
    public let taskDescription: String?
    public let teammateName: String?
    public let teamName: String?

    private enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case taskSubject = "task_subject"
        case taskDescription = "task_description"
        case teammateName = "teammate_name"
        case teamName = "team_name"
    }
}

/// TaskCompleted: fires when a task is being marked completed.
public struct TaskCompletedPayload: Codable, Sendable {
    public let taskID: String?
    public let taskSubject: String?

    private enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case taskSubject = "task_subject"
    }
}

/// TeammateIdle: fires when an agent team teammate is about to go idle.
public struct TeammateIdlePayload: Codable, Sendable {
    public let teammateName: String?
    public let teamName: String?

    private enum CodingKeys: String, CodingKey {
        case teammateName = "teammate_name"
        case teamName = "team_name"
    }
}

/// InstructionsLoaded: fires when a CLAUDE.md or .claude/rules/*.md file
/// is loaded.
/// Matcher values: session_start, nested_traversal, path_glob_match,
/// include, compact.
public struct InstructionsLoadedPayload: Codable, Sendable {
    public let filePath: String?
    public let memoryType: InstructionsMemoryType?
    public let loadReason: InstructionsLoadReason?
    public let globs: [String]?
    public let triggerFilePath: String?
    public let parentFilePath: String?

    private enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case memoryType = "memory_type"
        case loadReason = "load_reason"
        case globs
        case triggerFilePath = "trigger_file_path"
        case parentFilePath = "parent_file_path"
    }
}

/// ConfigChange: fires when a configuration file changes during a session.
/// Matcher values: user_settings, project_settings, local_settings,
/// policy_settings, skills.
public struct ConfigChangePayload: Codable, Sendable {
    public let configSource: String?

    private enum CodingKeys: String, CodingKey {
        case configSource = "config_source"
    }
}

/// CwdChanged: fires when the working directory changes.
public struct CwdChangedPayload: Codable, Sendable {
    public let oldCwd: String?
    public let newCwd: String?

    private enum CodingKeys: String, CodingKey {
        case oldCwd = "old_cwd"
        case newCwd = "new_cwd"
    }
}

/// FileChanged: fires when a watched file changes on disk.
/// Matcher values: literal filenames (e.g. ".envrc|.env"), not regex.
public struct FileChangedPayload: Codable, Sendable {
    public let filePath: String?
    public let changeType: String?

    private enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case changeType = "change_type"
    }
}

/// WorktreeCreate: fires when a git worktree is being created.
public struct WorktreeCreatePayload: Codable, Sendable {
    public let worktreePath: String?
    public let branch: String?

    private enum CodingKeys: String, CodingKey {
        case worktreePath = "worktree_path"
        case branch
    }
}

/// WorktreeRemove: fires when a git worktree is being removed.
public struct WorktreeRemovePayload: Codable, Sendable {
    public let worktreePath: String?

    private enum CodingKeys: String, CodingKey {
        case worktreePath = "worktree_path"
    }
}

/// PreCompact: fires before context compaction.
/// Matcher values: manual, auto.
public struct PreCompactPayload: Codable, Sendable {
    public let trigger: CompactTrigger?
    public let customInstructions: String?

    private enum CodingKeys: String, CodingKey {
        case trigger
        case customInstructions = "custom_instructions"
    }
}

/// PostCompact: fires after context compaction completes.
/// Matcher values: manual, auto.
public struct PostCompactPayload: Codable, Sendable {
    public let trigger: CompactTrigger?

    private enum CodingKeys: String, CodingKey {
        case trigger
    }
}

/// Elicitation: fires when an MCP server requests user input.
/// Matcher values: MCP server names.
public struct ElicitationPayload: Codable, Sendable {
    public let serverName: String?
    public let requestType: String?
    public let requestData: AnyCodable?

    private enum CodingKeys: String, CodingKey {
        case serverName = "server_name"
        case requestType = "request_type"
        case requestData = "request_data"
    }
}

/// ElicitationResult: fires after the user responds to an elicitation.
/// Matcher values: MCP server names.
public struct ElicitationResultPayload: Codable, Sendable {
    public let serverName: String?
    public let userResponse: AnyCodable?

    private enum CodingKeys: String, CodingKey {
        case serverName = "server_name"
        case userResponse = "user_response"
    }
}

// MARK: - AnyCodable

/// Type-erased Codable wrapper for arbitrary JSON values.
///
/// Used for fields whose structure varies (tool_input, tool_response, etc.).
public enum AnyCodable: Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodable])
    case object([String: AnyCodable])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([AnyCodable].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: AnyCodable].self) {
            self = .object(v)
        } else {
            throw DecodingError.typeMismatch(
                AnyCodable.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported JSON value"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}
