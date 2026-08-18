//
//  ToolProvider.swift
//  iTerm2SharedARC
//

import Foundation

// A pluggable source of LLM tools and chat-flavor behaviors for
// ChatAgent. Each provider declares its tools to the AIConversation
// and may optionally transform the outgoing user body. The system
// prompt is owned by ChatAgent and read from the user-customizable
// kPreferenceKeyAIPromptAIChat... preference keys; providers don't
// override it. Message-history translation is mode-agnostic and lives
// on ChatAgent: a chat's persisted history can carry messages from
// any era (session-bound, orchestration, both) and the translator
// handles every Message.Content variant uniformly.
//
// Providers hold no chat state themselves; they close over whatever
// pieces of the agent they need at construction time.
protocol ToolProvider: AnyObject {
    // Add this provider's tools to the conversation. May be called
    // multiple times across the agent's lifetime when filtering
    // relevant to the provider changes (e.g. session-bound
    // permission updates). Must not call removeAllFunctions; the
    // agent does that before iterating across its provider set.
    @MainActor
    func registerTools(on conversation: inout AIConversation)

    // Optional: volatile per-turn context this provider wants the model
    // to see, regenerated fresh every turn and NOT persisted into chat
    // history. Default is nil. The orchestrator provider returns the
    // current <workgroups> snapshot so the LLM sees live workgroup state
    // without round-tripping a list_workgroups tool call. The agent routes
    // this into AnthropicRequestBuilder.trailingVolatileText, which appends
    // it AFTER the rolling cache breakpoint so it never invalidates the
    // cached history prefix (see AIChatTrailingVolatileTests). It must NOT
    // be baked into the user body: that lands it inside the cached prefix,
    // and because it changes every turn it re-caches the whole history each
    // turn (the bug documented in AIChatHistoryCacheStabilityTests).
    //
    // @MainActor: orchestration implementations read main-thread state
    // (workgroup snapshot via iTermWorkgroupController). The compiler
    // contract beats relying on every caller path to be main today.
    @MainActor
    func volatileContext() -> String?
}

// Defaults that make the optional hooks truly optional for providers
// that only care about tool registration.
extension ToolProvider {
    @MainActor
    func volatileContext() -> String? { nil }
}
