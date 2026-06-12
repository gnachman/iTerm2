//
//  DeepSeek.swift
//  iTerm2
//
//  Created by George Nachman on 6/12/25.
//

struct DeepSeekRequestBuilder {
    var messages: [LLM.Message]
    var provider: LLMProvider
    var functions = [LLM.AnyFunction]()
    var stream: Bool
    var shouldThink: Bool? = nil

    private struct Body: Codable {
        var model: String?
        var messages = [Message]()
        var max_tokens: Int
        var temperature: Int? = 0
        var tools: [Tool]? = nil
        var function_call: String? = nil  // "none" and "auto" also allowed
        var stream: Bool
        var thinking: Thinking? = nil
    }

    private struct Thinking: Codable {
        enum Mode: String, Codable {
            case enabled
            case disabled
        }
        var type: Mode
    }

    struct Message: Codable {
        var role: Role? = .user
        var tool_call_id: String?
        var content: String?
        var tool_calls: [ToolCall]?
        // DeepSeek requires this echoed back on assistant turns when thinking
        // mode is enabled, or it returns 400 on multi-turn tool calls. Emitted
        // only when the source LLM.Message has a non-empty reasoningContent
        // (set by DeepSeekStreamingResponseParser / LLMModernResponseParser).
        // Every stored property of this Message is Optional<T>, so Swift's
        // synthesized Codable conformance already omits nil keys
        // (encodeIfPresent semantics) — that's the shape DeepSeek's API
        // expects for non-thinking conversations.
        var reasoning_content: String?

        struct ToolCall: Codable {
            var id: String?
            var type = "function"
            var function: LLM.FunctionCall
        }
        enum Role: String, Codable {
            case user
            case assistant
            case system
            case tool
        }

        init?(_ message: LLM.Message) {
            role = switch message.role {
            case .user: .user
            case .assistant: .assistant
            case .system: .system
            case .function: .tool
            case .none: nil
            }
            // Round-trip reasoning_content on assistant turns only. Skipping
            // user/tool roles avoids accidentally promoting display state into
            // a wire field the server doesn't accept there.
            if message.role == .assistant,
               let reasoning = message.reasoningContent,
               !reasoning.isEmpty {
                reasoning_content = reasoning
            }
            switch message.body {
            case .uninitialized:
                break
            case .text(let text):
                content = text
            case .functionCall(let call, id: let id):
                tool_calls = [ToolCall(id: id?.callID, function: call)]
            case .functionOutput(name: _, output: let output, id: let id):
                tool_call_id = id?.callID
                content = output
            case .attachment:
                content = ""
            case .multipart(let parts):
                // Walk subparts collecting text into content and any
                // .functionCall into tool_calls. parseNonStreamingResponse can
                // produce a [text-preamble, .functionCall(...)] multipart
                // assistant turn for any vendor whose response splits a turn
                // into multiple choice-messages (Anthropic, Gemini after the
                // 2026 parser refactor). If the conversation is then
                // round-tripped through this builder, we must not silently
                // drop the embedded function call.
                var contentParts: [String] = []
                var collectedToolCalls: [ToolCall] = []
                var collectedToolCallID: String?
                for part in parts {
                    switch part {
                    case .uninitialized, .multipart:
                        continue
                    case .text(let text):
                        contentParts.append(text)
                    case .functionCall(let call, let id):
                        collectedToolCalls.append(ToolCall(id: id?.callID ?? call.id,
                                                           function: call))
                    case .functionOutput(name: _, output: let output, id: let id):
                        // A multipart assistant turn shouldn't carry a
                        // function output, but if it ever does, surface its
                        // content and tool_call_id so the request remains
                        // valid rather than silently losing it.
                        if collectedToolCallID == nil {
                            collectedToolCallID = id?.callID
                        }
                        contentParts.append(output)
                    case .attachment(let attachment):
                        switch attachment.type {
                        case .code(let text):
                            contentParts.append(text)
                        case .statusUpdate:
                            continue
                        case .file(let file):
                            // TODO: lossyString here means binary attachments
                            // (images, PDFs, archives) get sent to DeepSeek as
                            // mangled UTF-8 wrapped in <iterm2:attachment>.
                            // DeepSeek doesn't have a vision API in iTerm2, so
                            // there's no good alternative; consider rejecting
                            // non-textual mimes upstream instead of silently
                            // shipping garbage.
                            var value = "<iterm2:attachment file=\"\(file.name)\" type=\"\(file.mimeType)\">\n"
                            value += file.content.lossyString
                            value += "\n</iterm2:attachment>"
                            contentParts.append(value)
                        case .fileID(id: _, name: let name):
                            contentParts.append("A file named \(name) (content unavailable)")
                        }
                    }
                }
                // A chat-completions message can be either an assistant tool
                // call (tool_calls) or a tool output (tool_call_id), not both.
                // No current parser produces a multipart body containing both
                // a .functionCall and a .functionOutput sibling. If a future
                // one ever does, prefer the assistant-call shape: drop the
                // tool_call_id and emit tool_calls. This is a deliberate
                // recovery rather than a crash because the alternative is
                // sending a wire-ambiguous message to the vendor (or aborting
                // the user's session over a hypothetical future parser bug).
                if !collectedToolCalls.isEmpty {
                    collectedToolCallID = nil
                }
                if !contentParts.isEmpty {
                    content = contentParts.joined(separator: "\n")
                }
                if !collectedToolCalls.isEmpty {
                    tool_calls = collectedToolCalls
                }
                if let collectedToolCallID {
                    tool_call_id = collectedToolCallID
                }
            }
            // A reasoning-only assistant turn (no content, no tool_calls, only
            // reasoning_content) is the persisted shape after the ChatListModel
            // .commit case harvests statusUpdate subparts from a streamed
            // reasoning-only response. We emit content="" so the wire body
            // preserves user→assistant→user alternation and the reasoning
            // round-trip survives. The shape was verified against the live
            // DeepSeek API by test_deepseek_thinking_reasoningOnlyAssistant_roundTrips
            // — DeepSeek accepts {"role":"assistant","content":"","reasoning_content":"..."}
            // and replies normally. Don't change this assignment without
            // re-running that live test.
            if role == .assistant
                && content == nil
                && tool_calls == nil
                && reasoning_content != nil {
                content = ""
            }
        }
    }

    struct Tool: Codable {
        var type = "function"
        var function: ChatGPTFunctionDeclaration
    }

    func body() throws -> Data {
        // Tokens are about 4 letters each. Allow enough tokens to include both the query and an
        // answer the same length as the query.
        let maybeDecls = functions.isEmpty ? nil : functions.map {
            Tool(function: $0.decl)
        }
        // Only thinking-capable models (DeepSeek v4) get an explicit `thinking`
        // block. For v4 we always emit one so the server-side default (enabled)
        // never leaks through: shouldThink == true → enabled, otherwise disabled.
        // Older DeepSeek models (chat/coder/reasoner) have no server-side
        // thinking default and the field isn't documented on those endpoints,
        // so omit it entirely rather than guessing they tolerate an unknown key.
        // The reasoning_content round-trip required by DeepSeek when thinking
        // is on is handled by Message.reasoning_content (sourced from
        // LLM.Message.reasoningContent on assistant turns).
        // https://api-docs.deepseek.com/guides/thinking_mode#input-and-output-parameters
        let thinkingBlock: Thinking? = provider.model.features.contains(.configurableThinking)
            ? Thinking(type: shouldThink == true ? .enabled : .disabled)
            : nil
        let body = Body(
            model: provider.dynamicModelsSupported ? provider.model.name : nil,
            messages: messages.compactMap { Message($0) },
            max_tokens: provider.maxTokens(functions: functions, messages: messages),
            tools: maybeDecls,
            function_call: functions.isEmpty ? nil : "auto",
            stream: stream,
            thinking: thinkingBlock)
        DLog("REQUEST:\n\(body)")
        if body.max_tokens < 2 {
            throw AIError.requestTooLarge
        }
        let bodyEncoder = JSONEncoder()
        let bodyData = try! bodyEncoder.encode(body)
        return bodyData

    }
}

struct DeepSeekResponseParser: LLMResponseParser {
    mutating func parse(data: Data) throws -> (any LLM.AnyResponse)? {
        var lastException: Error?
        for parser: LLMResponseParser in [LLMModernResponseParser(), LlamaResponseParser()] {
            do {
                var temp = parser
                return try temp.parse(data: data)
            } catch {
                lastException = error
            }
        }
        if let lastException {
            throw lastException
        } else {
            return nil
        }
    }
    
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return (nil, "")
    }
}

struct DeepSeekStreamingResponseParser: LLMStreamingResponseParser {
    struct DeepSeekStreamingResponse: Codable, LLM.AnyStreamingResponse {
        var newlyCreatedResponseID: String? { nil }
        var ignore: Bool { false }
        var isStreamingResponse: Bool { true }

        let id: String?
        let object: String?
        let created: TimeInterval?
        let model: String?
        let choices: [UpdateChoice]

        struct UpdateChoice: Codable {
            // The delta holds the incremental text update.
            let delta: Delta
            let index: Int
            // For update chunks, finish_reason is nil.
            let finish_reason: String?

            struct Delta: Codable {
                var role: LLM.Role?
                var content: String?
                var tool_calls: [ToolCall]?
                // DeepSeek streams reasoning as its own incremental field,
                // distinct from `content`. A single delta carries either
                // reasoning or content, never both interleaved.
                var reasoning_content: String?

                struct ToolCall: Codable {
                    var index: Int
                    var id: String?
                    var type: String?  // "function"
                    var function: LLM.FunctionCall?
                }
            }
        }

        var choiceMessages: [LLM.Message] {
            // `choices` is the n-sampling alternatives axis; iTerm2 never
            // requests n > 1, so surface only the first.
            guard let choice = choices.first else { return [] }
            if choice.finish_reason == "tool_calls" {
                // Sent at the end of a function call
                return []
            }
            // Reasoning deltas typically arrive in their own deltas (DeepSeek
            // docs describe `reasoning_content` and `content` as separate
            // streams), but the parser handles co-arrival defensively: if a
            // single delta carries both, surface both messages so AITermController
            // applies them in order. Surfaces reasoning via the existing
            // .statusUpdate(.reasoningSummaryUpdate) attachment path so the chat
            // cell renders it the same way OpenAI reasoning summaries do, and
            // also stashes the reasoning string on LLM.Message.reasoningContent
            // so the accumulator in AITerm.swift can fold it into the final
            // assistant turn for round-trip on the next request.
            var messages: [LLM.Message] = []
            if let reasoningDelta = choice.delta.reasoning_content, !reasoningDelta.isEmpty {
                var msg = LLM.Message(
                    role: .assistant,
                    body: .attachment(.init(
                        inline: true,
                        id: "deepseek-reasoning",
                        type: .statusUpdate(.reasoningSummaryUpdate(reasoningDelta)))))
                msg.reasoningContent = reasoningDelta
                messages.append(msg)
            }
            if let call = choice.delta.tool_calls?.first {
                let function = call.function
                let functionCall = LLM.FunctionCall(
                    name: function?.name,
                    arguments: function?.arguments,
                    id: call.id)
                messages.append(LLM.Message(
                    role: .assistant,
                    content: choice.delta.content,
                    functionCallID: call.id.map { .init(callID: $0, itemID: "") },
                    function_call: functionCall))
            } else if messages.isEmpty || choice.delta.content != nil {
                // Emit a content message when there's actual content, or when
                // there's no reasoning message yet (preserves the prior empty-delta
                // behavior of returning a placeholder assistant message).
                messages.append(LLM.Message(
                    role: .assistant,
                    content: choice.delta.content))
            }
            return messages
        }
    }
    var parsedResponse: DeepSeekStreamingResponse?

    mutating func parse(data: Data) throws -> LLM.AnyStreamingResponse? {
        let decoder = JSONDecoder()
        let response =  try decoder.decode(DeepSeekStreamingResponse.self, from: data)
        DLog("RESPONSE:\n\(response)")
        parsedResponse = response
        return response
    }
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return SplitServerSentEvents(from: rawInput)
    }
}
