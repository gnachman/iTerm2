//
//  AIChatToolCallRepair.swift
//  iTerm2
//
//  Created by George Nachman on 5/27/26.
//

// When an AI chat prompt is rebuilt from the persisted transcript, every
// tool_result must be paired with a tool_use the vendor can recognise, or the
// vendor rejects the request (e.g. Anthropic 400 "unexpected tool_use_id
// found in tool_result blocks", Gemini "functionResponse without matching
// functionCall"). Two distinct hazards have to be neutralised on every reload,
// regardless of which vendor the prompt happens to fly to:
//
//   - Auto-approved ("always") commands historically squelched the
//     remoteCommandRequest from the transcript while still persisting the
//     remoteCommandResponse, so the rebuilt prompt contains an orphan
//     tool_result. That bug predates v3.6.10, so conversations serialized by
//     shipping builds already contain orphans on disk.
//   - Gemini (and the legacy OpenAI function_call path) deserialize their
//     tool calls with both the inner FunctionCall.id and the wrapper
//     FunctionCallID set to nil (Gemini.swift parser). Those nils flow into
//     the persisted .remoteCommandResponse, and on reload arrive here as a
//     functionOutput with no id at all. Such a result cannot be paired by id,
//     but those vendors pair by adjacency: every functionResponse Part must
//     come right after its functionCall Part.
//
// The repair runs at prompt-build time and never rewrites stored rows, so it
// heals old and new conversations on every vendor without any serialization
// change.
enum AIChatToolCallRepair {
    // The output body used to stand in for a tool call whose result never
    // arrived (an abandoned `.ask`, or a parked request cleared on the next
    // user message). Shared with ChatAgent.translate so the live reload path
    // and the repair pass emit identical filler text.
    static let interruptedToolCallOutput =
        "[iTerm2 was restarted before this tool call completed. "
        + "The call did not finish; assume no side effects took place "
        + "and re-issue if needed.]"

    // Repair both orphan directions a rebuilt prompt can contain: a tool_result
    // with no matching tool_use, and a tool_use with no matching tool_result.
    // Results are repaired first so a synthesized tool_use (paired with its
    // result) is never itself mistaken for an orphan call.
    static func repairingOrphanedToolPairs(_ messages: [LLM.Message]) -> [LLM.Message] {
        return repairingOrphanedToolCalls(repairingOrphanedToolResults(messages))
    }

    // Walk the rebuilt prompt and ensure every tool_result has a partner the
    // vendor will accept. For results that carry a call id (Anthropic / OpenAI
    // Responses style), require a matching prior tool_use of the same id and
    // synthesize one immediately before the result otherwise. For results that
    // carry no id (Gemini / legacy OpenAI), require the immediately preceding
    // emitted message to be a tool_use; synthesize a nil-id tool_use just
    // before the result if it isn't. Well-formed pairs are passed through
    // untouched, and no id is paired twice.
    static func repairingOrphanedToolResults(_ messages: [LLM.Message]) -> [LLM.Message] {
        var seenToolUseCallIDs = Set<String>()
        var result = [LLM.Message]()
        result.reserveCapacity(messages.count)

        for message in messages {
            // Record every tool_use the message itself supplies first, so a
            // (rare) multipart message that bundles both a tool_use and its
            // result self-pairs without us inserting a redundant synthetic.
            for callID in providedToolUseCallIDs(message.body) {
                seenToolUseCallIDs.insert(callID)
            }
            if let consumed = consumedToolResult(message.body) {
                if let id = consumed.id {
                    // Id-based pairing (Anthropic, OpenAI Responses).
                    if !seenToolUseCallIDs.contains(id.callID) {
                        result.append(synthesizedToolUse(name: consumed.name,
                                                         wrapperID: id,
                                                         innerCallID: id.callID))
                        seenToolUseCallIDs.insert(id.callID)
                    }
                } else if !lastEmittedMessageIsToolUse(result) {
                    // Position-based pairing (Gemini, legacy OpenAI). We have
                    // nothing to match on, so the only thing that makes the
                    // pair recoverable is adjacency.
                    result.append(synthesizedToolUse(name: consumed.name,
                                                     wrapperID: nil,
                                                     innerCallID: nil))
                }
            }
            result.append(message)
        }
        return result
    }

    // The mirror image of repairingOrphanedToolResults: ensure every tool_use
    // has a tool_result the vendor will accept after it. OpenAI-style
    // chat-completions vendors (DeepSeek, legacy OpenAI) reject an assistant
    // tool_calls message that isn't immediately followed by a tool message for
    // each tool_call_id with HTTP 400 "insufficient tool messages following
    // tool_calls message" (GitLab #12883). A persisted tool call can lose its
    // result when it never completed: an `.ask` the user abandoned, or a parked
    // request cleared by cancelPendingCommands on the next user message. For a
    // call that carries an id, "answered" means some tool_result anywhere
    // carries that id; for a nil-id (Gemini / legacy OpenAI) call it means the
    // immediately following message is a tool_result, matching the adjacency
    // those vendors pair on. Unanswered calls get a synthesized interrupted
    // output inserted immediately after them; well-formed pairs pass through.
    static func repairingOrphanedToolCalls(_ messages: [LLM.Message]) -> [LLM.Message] {
        // Every callID some tool_result answers (id-based pairing). Computed up
        // front: a result legitimately follows its call, so orphan-hood can't be
        // decided in a single forward pass without looking ahead.
        var answeredCallIDs = Set<String>()
        for message in messages {
            answeredCallIDs.formUnion(consumedToolResultCallIDs(message.body))
        }
        var result = [LLM.Message]()
        result.reserveCapacity(messages.count)
        for (index, message) in messages.enumerated() {
            result.append(message)
            // Only the bare functionCall shape occurs on the reload/restore
            // path (one per .remoteCommandRequest). Leave multipart and other
            // bodies untouched rather than guess where to splice a result.
            guard case .functionCall(let call, let wrapper) = message.body else {
                continue
            }
            let callID = call.id ?? wrapper?.callID
            let answered: Bool
            let outputID: LLM.Message.FunctionCallID?
            if let callID {
                answered = answeredCallIDs.contains(callID)
                // Mirror what the result side expects: a result keyed off the
                // same callID. Reuse the call's wrapper when it has one so the
                // itemID round-trips; otherwise synthesize from the inner id.
                outputID = wrapper ?? LLM.Message.FunctionCallID(callID: callID, itemID: callID)
            } else {
                // Position-based (nil-id Gemini / legacy OpenAI): the call is
                // paired iff a tool_result immediately follows it.
                answered = (index + 1 < messages.count) && bodyIsToolResult(messages[index + 1].body)
                outputID = nil
            }
            if !answered {
                result.append(LLM.Message(
                    role: .function,
                    body: .functionOutput(name: call.name ?? "",
                                          output: interruptedToolCallOutput,
                                          id: outputID)))
            }
        }
        return result
    }

    // MARK: - Private

    // Every callID this message answers as a tool_result (id-based), recursing
    // into multipart. Used to decide whether a tool_use is orphaned.
    private static func consumedToolResultCallIDs(_ body: LLM.Message.Body) -> [String] {
        switch body {
        case .functionOutput(_, _, let id):
            return id.map { [$0.callID] } ?? []
        case .multipart(let parts):
            return parts.flatMap { consumedToolResultCallIDs($0) }
        case .uninitialized, .text, .functionCall, .attachment:
            return []
        }
    }

    // True when the body carries a tool_result (directly or, defensively,
    // inside a multipart). Used for the nil-id adjacency check.
    private static func bodyIsToolResult(_ body: LLM.Message.Body) -> Bool {
        return consumedToolResult(body) != nil
    }

    // A placeholder tool_use to pair with an orphaned result. The real request
    // is unrecoverable by the time we reload: an auto-approved command dropped
    // it from history, and the executing-command record that still holds the
    // arguments is client-local and never reaches the prompt. Empty arguments
    // are good enough to satisfy the vendor's pairing requirement; the command
    // itself is usually echoed in the tool output anyway.
    //
    // The inner FunctionCall.id MUST mirror whatever the result carries: for
    // id-based vendors the Anthropic serializer keys a tool_use block off
    // FunctionCall.id (CompletionsAnthropic.swift) and a nil inner id would
    // serialize the synthesized call as plain text, leaving the result orphaned
    // all over again. For nil-id (Gemini-shaped) results, passing nil is
    // correct: the serializer emits an id-less functionCall Part, and Gemini
    // pairs by adjacency rather than id.
    private static func synthesizedToolUse(name: String,
                                           wrapperID: LLM.Message.FunctionCallID?,
                                           innerCallID: String?) -> LLM.Message {
        let call = LLM.FunctionCall(name: name,
                                    arguments: "{}",
                                    id: innerCallID,
                                    thoughtSignature: nil)
        return LLM.Message(role: .assistant, body: .functionCall(call, id: wrapperID))
    }

    // True when the most recently emitted message is itself a tool_use (a
    // bare functionCall body, or a multipart whose last part is one). Used to
    // satisfy the adjacency rule that id-less vendors enforce.
    private static func lastEmittedMessageIsToolUse(_ result: [LLM.Message]) -> Bool {
        guard let last = result.last else { return false }
        switch last.body {
        case .functionCall:
            return true
        case .multipart(let parts):
            if case .functionCall = parts.last { return true }
            return false
        case .uninitialized, .text, .functionOutput, .attachment:
            return false
        }
    }

    // The tool-call ids this message supplies as tool_use blocks.
    private static func providedToolUseCallIDs(_ body: LLM.Message.Body) -> [String] {
        switch body {
        case .functionCall(let call, let id):
            // Match how the Anthropic serializer pairs blocks: prefer the inner
            // id it actually emits, falling back to the wrapper. Nil-id calls
            // (Gemini-shaped) contribute nothing; they're paired by adjacency.
            if let inner = call.id {
                return [inner]
            }
            return id.map { [$0.callID] } ?? []
        case .multipart(let parts):
            return parts.flatMap { providedToolUseCallIDs($0) }
        case .uninitialized, .text, .functionOutput, .attachment:
            return []
        }
    }

    // The tool_result this message consumes, with its function name so a
    // placeholder tool_use can be synthesized. In the reload path each
    // remoteCommandResponse becomes its own single-body functionOutput
    // (MessageToPromptStateMachine), so a message carries at most one tool
    // result; the multipart scan is defensive and returns the first.
    private static func consumedToolResult(_ body: LLM.Message.Body) -> (name: String, id: LLM.Message.FunctionCallID?)? {
        switch body {
        case .functionOutput(let name, _, let id):
            return (name, id)
        case .multipart(let parts):
            for part in parts {
                if let found = consumedToolResult(part) {
                    return found
                }
            }
            return nil
        case .uninitialized, .text, .functionCall, .attachment:
            return nil
        }
    }
}
