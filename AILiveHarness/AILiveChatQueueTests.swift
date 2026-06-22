//
//  AILiveChatQueueTests.swift
//  iTerm2 AI live harness
//
//  Live integration test for the queue-discipline invariant in
//  ChatService: a second user message must wait for the in-flight
//  turn (including any tool round-trip) to fully complete before
//  being dispatched.
//
//  Architecture:
//
//  Production:
//    user A typed -> ChatBroker.publish(.plainText, author=.user)
//      -> ChatService.handle -> enqueue -> startNextTurn
//      -> ChatAgent.fetchCompletion -> AIConversation -> LLM
//      -> LLM returns tool call (e.g. execute_command)
//      -> ChatAgent.runRemoteCommand
//      -> broker.publish(.remoteCommandRequest, author=.agent)
//      -> ChatClient's broker processor intercepts
//      -> ChatClient.processRemoteCommandRequest -> session.execute
//      -> shell runs command, output captured
//      -> broker.publish(.remoteCommandResponse, author=.user)
//      -> ChatService.deliverToolResult -> resumes parked dispatcher
//      -> LLM produces final reply -> broker.publish(reply, author=.agent)
//      -> ChatService.finishTurn -> drains queue
//
//  This test:
//    Same flow, except ChatClient.instance is never instantiated, so
//    its processor never registers. The test subscribes to the broker
//    and plays the tool runner: on .remoteCommandRequest, it parks for
//    a controlled delay (simulating slow tool execution), then publishes
//    a fabricated .remoteCommandResponse with the matching uniqueID.
//    Everything above the broker boundary is real production code.
//
//  Cost: ~2 LLM round-trips per run (one for A's tool-using turn, one
//  for B's plain reply). Anthropic Haiku via the user's configured
//  provider; cents per run.
//

import XCTest
@testable import iTerm2SharedARC

// All tests in this file drive ChatBroker / ChatService / ChatClient
// directly; those are @MainActor now, so the tests need to run on the
// main actor too.
@MainActor
extension AILiveHarness {

    /// User sends message A that triggers a tool. While the tool is
    /// "in flight" (test parks the response), user sends message B.
    /// The test asserts: no agent reply is published for B until A's
    /// turn fully completes — i.e. tool response is delivered AND the
    /// assistant's post-tool reply is published.
    func test_chat_userMessageDuringInFlightTool_waitsForFirstTurn() throws {
        // 1) Resolve which vendor we'll drive based on the user's
        //    configured provider and the available API key for that
        //    vendor. AITermController.provider reads iTermPreferences,
        //    so this matches whatever the user has set up.
        let providerName = AITermController.provider?.displayName ?? ""
        let envKey: String?
        switch providerName {
        case "OpenAI":     envKey = Self.configValue("OPENAI_API_KEY")
        case "Anthropic":  envKey = Self.configValue("ANTHROPIC_API_KEY")
        case "Google":     envKey = Self.configValue("GEMINI_API_KEY")
        case "Deep Seek":  envKey = Self.configValue("DEEPSEEK_API_KEY")
        default:           envKey = nil
        }
        guard let apiKey = envKey, !apiKey.isEmpty else {
            throw XCTSkip("No live API key for current provider \(providerName)")
        }
        guard AITermController.provider?.functionsSupported == true else {
            throw XCTSkip("Configured provider does not support function calling; queue test needs a tool round-trip")
        }
        guard let broker = ChatBroker.instance else {
            throw XCTSkip("ChatBroker.instance unavailable")
        }
        // Critical isolation invariant: do NOT touch ChatClient.instance.
        // If we did, it would register a broker processor that intercepts
        // .remoteCommandRequest before the test can act as the tool
        // runner. Sanity check: nothing in the harness should have
        // pre-instantiated it.
        XCTAssertFalse(chatClientAlreadyInstantiated(),
                       "ChatClient.instance must not exist; this test plays the role of the broker-side tool runner")

        // 2) Encode permissions that grant runCommands=.always so the
        //    LLM is offered the execute_command tool. The chatID/guid
        //    fields in the encoded Key entries are ignored by
        //    RemoteCommandExecutor.allowedCategories(dict:) — only the
        //    category+permission pair matters for the
        //    .setPermissions message broker.create publishes.
        let perms = #"[{"guid":"queue-test","category":"Run Commands","chatID":"queue-test"},"always"]"#

        // 3) Recorder watches every broker delivery AND typing-status
        //    transition so we can do post-run ordering assertions
        //    independent of LLM phrasing or streaming chunk noise.
        //    Subscribe with chatID:nil so it sees the initial
        //    .setPermissions broker.create publishes BEFORE we know
        //    our chatID.
        let recorder = BrokerEventRecorder()
        let listenAll = broker.subscribe(chatID: nil,
                                         registrationProvider: nil) { update in
            recorder.record(update)
        }
        defer { listenAll.unsubscribe() }

        // 4) Create the chat. broker.create publishes the initial
        //    .setPermissions synchronously; ChatService.applySetPermissions
        //    constructs an agent but doesn't make an LLM call, so the
        //    registration provider isn't needed yet. terminalSessionGuid
        //    is a fabricated value — no PTYSession is required because
        //    this test plays the tool runner directly.
        let chatID: String
        do {
            chatID = try broker.create(
                chatWithTitle: "live queue test \(UUID().uuidString.prefix(8))",
                terminalSessionGuid: "queue-test",
                browserSessionGuid: nil,
                permissions: perms,
                initialMessages: [])
        } catch {
            XCTFail("Failed to create test chat: \(error)")
            return
        }
        addTeardownBlock {
            try? broker.delete(chatID: chatID)
        }

        // 4b) Now that chatID is known, install the
        //     registration provider keyed to that exact chatID.
        //     ChatBroker.requestRegistration filters by chatID equality
        //     (a chatID:nil subscription is invisible to it), so the
        //     registration subscription has to come AFTER broker.create.
        //     LLM calls don't start until the next user message we
        //     publish, so this ordering is safe.
        let registrationProvider = TestRegistrationProvider(apiKey: apiKey)
        let registrationSub = broker.subscribe(chatID: chatID,
                                               registrationProvider: registrationProvider) { _ in
            // Registration-only subscription; recording goes through listenAll.
        }
        defer { registrationSub.unsubscribe() }

        // 5) Set up a fake tool responder: on the first
        //    .remoteCommandRequest, park for `toolDelay` seconds, then
        //    publish a fabricated .remoteCommandResponse with the
        //    matching uniqueID. The response body identifies itself
        //    so we can verify the agent's post-tool reply actually
        //    consumed it.
        let toolDelay: TimeInterval = 2.0
        // Fixed (not random) so the tool-result request is byte-stable and the
        // cassette layer can replay it. Still unguessable, so a model that
        // ignores the tool output can't reproduce it by chance.
        let toolMarker = "kw-MAGENTA-LARK-77"
        let toolOutput = "command output containing \(toolMarker)"
        let responder = FakeToolResponder(broker: broker,
                                          chatID: chatID,
                                          delay: toolDelay,
                                          output: toolOutput)
        defer { responder.shutdown() }

        // 6) Expectations driven by the recorder's transition log.
        //    These are sequenced strictly: tool request, then A's turn
        //    end (typing=false after tool response), then B's turn end
        //    (second typing=false). The recorder's onEntry hook
        //    fulfills them as it observes matching events.
        let sawToolRequest = expectation(description: "agent dispatched .remoteCommandRequest")
        let sawATurnEnd    = expectation(description: "first agent typing=false after tool round-trip (A's turn finished)")
        let sawBTurnEnd    = expectation(description: "second agent typing=false (B's turn finished)")
        let userMessageABody = "Use the execute_command tool to run any command. The exact command does not matter."
        let userMessageBBody = "Reply with the single digit answer to 1+1, nothing else."

        var agentTurnEndCount = 0
        recorder.onEntry = { entry, _ in
            switch entry {
            case .delivery(let message, _):
                if case .remoteCommandRequest = message.content,
                   message.author == .agent {
                    sawToolRequest.fulfill()
                }
            case .typing(let isTyping, let participant):
                guard !isTyping, participant == .agent else { return }
                agentTurnEndCount += 1
                if agentTurnEndCount == 1 {
                    sawATurnEnd.fulfill()
                } else if agentTurnEndCount == 2 {
                    sawBTurnEnd.fulfill()
                }
            }
        }

        // 7) Publish user message A and wait for the tool dispatch,
        //    which proves A's turn is parked mid-round-trip waiting
        //    for the tool response.
        try broker.publish(message: userText(chatID: chatID, body: userMessageABody),
                           toChatID: chatID, partial: false)
        wait(for: [sawToolRequest], timeout: 60)

        // 8) Tool request is in the air; FakeToolResponder will publish
        //    a response after `toolDelay` seconds. Publish B right
        //    now. The queue must hold it — no typing=true for B fires
        //    until A's typing=false fires first.
        try broker.publish(message: userText(chatID: chatID, body: userMessageBBody),
                           toChatID: chatID, partial: false)

        // 9) Wait for A's turn to fully finish (typing=false). This
        //    can only happen after the fake responder publishes the
        //    tool response AND the post-tool LLM call completes.
        wait(for: [sawATurnEnd], timeout: 120)

        // 10) Wait for B's turn to finish (second typing=false). If
        //     queue discipline holds, this fires AFTER A's typing=false.
        wait(for: [sawBTurnEnd], timeout: 120)

        // 11) Walk the recorder log and assert the strict event order.
        let dump = recorder.summary(formatContent: short)
        print("[chat-queue-test] full broker event log (provider=\(providerName)):\n\(dump)")

        let toolRequestIdx = recorder.firstDelivery { msg in
            if case .remoteCommandRequest = msg.content, msg.author == .agent { return true }
            return false
        }
        let bPublishIdx = recorder.firstDelivery { msg in
            msg.author == .user && msg.content.simpleText == userMessageBBody
        }
        let toolResponseIdx = recorder.firstDelivery(after: (toolRequestIdx ?? 0) + 1) { msg in
            if case .remoteCommandResponse = msg.content { return true }
            return false
        }
        let aTurnEndIdx = recorder.firstAgentTurnEnd(at: 0)
        let bTurnEndIdx = aTurnEndIdx.flatMap { recorder.firstAgentTurnEnd(at: $0 + 1) }

        guard let toolRequestIdx, let bPublishIdx, let toolResponseIdx,
              let aTurnEndIdx, let bTurnEndIdx
        else {
            XCTFail("""
                Could not locate all required events in broker log. \
                toolRequest=\(String(describing: toolRequestIdx)), \
                bPublish=\(String(describing: bPublishIdx)), \
                toolResponse=\(String(describing: toolResponseIdx)), \
                aTurnEnd=\(String(describing: aTurnEndIdx)), \
                bTurnEnd=\(String(describing: bTurnEndIdx)). \
                Full log printed above.
                """)
            return
        }

        // The queue invariant in four assertions, all flowing through
        // the same recorder index space:
        XCTAssertLessThan(toolRequestIdx, bPublishIdx,
                          "B should be published AFTER the tool request (the in-flight tool dispatch is exactly the moment we want to race)")
        XCTAssertLessThan(bPublishIdx, toolResponseIdx,
                          "B must be published BEFORE the tool response — proves B raced an in-flight turn rather than landing on an idle queue")
        XCTAssertLessThan(toolResponseIdx, aTurnEndIdx,
                          "A's turn must end AFTER the tool response was delivered (the post-tool LLM round-trip is part of A's turn)")
        XCTAssertLessThan(aTurnEndIdx, bTurnEndIdx,
                          "B's turn must end AFTER A's turn — queue discipline")
    }

    /// Repros the production bug captured in debuglog.txt where the
    /// user typed a message, the assistant began streaming, the user
    /// hit Stop, then sent a new message — and the new message "just
    /// stopped" (never produced a reply).
    ///
    /// Mechanism: ChatAgent.stop() calls conversation.stop() →
    /// controller.cancel(), which sets the controller state to
    /// .ground SILENTLY (AITerm.swift:205-209). It does NOT route
    /// through handle(.cancel), so the AIConversation delegate's
    /// aitermControllerDidCancelOutstandingRequest never fires →
    /// delegate.completion?(.failure(PendingCommandCanceled)) never
    /// fires → ChatAgent's fetchCompletion completion closure never
    /// runs → ChatService's stopTyping + finishTurn never run. The
    /// in-flight user message stays at the head of pendingMessages
    /// forever. Subsequent user messages get enqueue'd but never
    /// dispatched (startNextTurn only fires when queue.count == 1).
    ///
    /// Test: send msg A, wait for the stream to begin, publish
    /// .userCommand(.stop), publish msg B, expect B's turn to end
    /// within a timeout. With the bug, B never dispatches and the
    /// turn-end expectation times out.
    ///
    /// FAILS on current main; PASSES once ChatAgent.stop routes
    /// through conversation.cancelOutstandingOperation() (which fires
    /// the .cancel event and the completion chain).
    func test_chat_stopThenSend_secondMessageStillDispatches() throws {
        let providerName = AITermController.provider?.displayName ?? ""
        let envKey: String?
        switch providerName {
        case "OpenAI":     envKey = Self.configValue("OPENAI_API_KEY")
        case "Anthropic":  envKey = Self.configValue("ANTHROPIC_API_KEY")
        case "Google":     envKey = Self.configValue("GEMINI_API_KEY")
        case "Deep Seek":  envKey = Self.configValue("DEEPSEEK_API_KEY")
        default:           envKey = nil
        }
        guard let apiKey = envKey, !apiKey.isEmpty else {
            throw XCTSkip("No live API key for current provider \(providerName)")
        }
        guard let broker = ChatBroker.instance else {
            throw XCTSkip("ChatBroker.instance unavailable")
        }

        let recorder = BrokerEventRecorder()
        let listenAll = broker.subscribe(chatID: nil, registrationProvider: nil) { update in
            recorder.record(update)
        }
        defer { listenAll.unsubscribe() }

        let chatID = try broker.create(
            chatWithTitle: "live stop-then-send test \(UUID().uuidString.prefix(8))",
            terminalSessionGuid: "queue-test",
            browserSessionGuid: nil,
            permissions: "",
            initialMessages: [])
        addTeardownBlock { try? broker.delete(chatID: chatID) }

        let registrationProvider = TestRegistrationProvider(apiKey: apiKey)
        let registrationSub = broker.subscribe(chatID: chatID,
                                               registrationProvider: registrationProvider) { _ in }
        defer { registrationSub.unsubscribe() }

        // Wait for the agent's first streaming chunk (any agent message
        // delivery; signals A's turn is actively streaming and stop will
        // intercept mid-flight rather than after completion).
        let sawAgentStreaming = expectation(description: "agent emitted first streaming chunk")
        let sawBTurnEnd = expectation(description: "B's turn ends (typing=false)")
        var sawStream = false
        var bTurnStarted = false
        recorder.onEntry = { entry, _ in
            switch entry {
            case .delivery(let message, _):
                if message.author == .agent, !sawStream {
                    switch message.content {
                    case .markdown, .plainText, .append:
                        sawStream = true
                        sawAgentStreaming.fulfill()
                    default:
                        return
                    }
                }
            case .typing(let isTyping, let participant):
                guard participant == .agent else { return }
                if isTyping {
                    if sawStream { bTurnStarted = true }
                } else if bTurnStarted {
                    sawBTurnEnd.fulfill()
                }
            }
        }

        let userMessageABody = "Write three paragraphs about the history of OpenSSL. Take your time and be thorough."
        let userMessageBBody = "Actually, just reply with the single digit 7, nothing else."

        // (1) Send A, wait for streaming to begin (A's turn is active).
        try broker.publish(message: userText(chatID: chatID, body: userMessageABody),
                           toChatID: chatID, partial: false)
        wait(for: [sawAgentStreaming], timeout: 30)

        // (2) Press Stop while A is still streaming. In production this
        //     is the path that gets triggered by the stop button in
        //     ChatInputView; the broker publishes a user-authored
        //     .userCommand(.stop) message which ChatService routes to
        //     ChatAgent.stop().
        let stopMessage = Message(chatID: chatID,
                                  author: .user,
                                  content: .userCommand(.stop),
                                  sentDate: Date(),
                                  uniqueID: UUID())
        try broker.publish(message: stopMessage, toChatID: chatID, partial: false)

        // (3) Send B. This is the user's "I sent another message" step.
        try broker.publish(message: userText(chatID: chatID, body: userMessageBBody),
                           toChatID: chatID, partial: false)

        // (4) Wait for B's turn to actually end. If the bug is present,
        //     A's stop silently orphans the queue, B is enqueued behind
        //     the dead A entry, startNextTurn is never called for B, and
        //     this times out.
        wait(for: [sawBTurnEnd], timeout: 90)

        let dump = recorder.summary(formatContent: short)
        print("[stop-then-send-test] broker log:\n\(dump)")
    }

    /// Repros the third production bug captured in debuglog.txt:
    /// the user typed msg A (which triggered a tool), pressed Stop
    /// while the tool was still running, then typed msg B (or msg B
    /// took the form of `Send` arriving after Stop). The tool
    /// eventually finished and published a .remoteCommandResponse.
    /// At that point ChatService.deliverToolResult routed the
    /// orphan response into ChatAgent.fetchCompletion — but the
    /// pending dispatcher had been cleared by ChatAgent.stop's
    /// cancelPendingCommands. The orphan handler in
    /// fetchCompletion's .remoteCommandResponse case falls through
    /// to fetchCompletionForRegularMessage on sessionBound mode,
    /// which kicks off a NEW LLM round-trip. That new round-trip's
    /// conversation.complete → prepare → cancel() silently cancels
    /// the actively in-flight queued turn (B) and overwrites its
    /// delegate.completion with a noop. B never completes,
    /// ChatService.finishTurn never runs, and the queue is
    /// orphaned again — same shape as the earlier
    /// stop-then-send bug but triggered by a delayed tool result.
    ///
    /// Test scenario:
    ///   1. Publish msg A.
    ///   2. Wait for the tool request.
    ///   3. Publish .userCommand(.stop) — this clears pending tool
    ///      dispatcher and ends A's turn.
    ///   4. Publish msg B.
    ///   5. The fake responder publishes the tool response AFTER B
    ///      has started, so the response is orphan.
    ///   6. Assert: B's turn ends (typing=false fires for B).
    ///
    /// FAILS on current main; PASSES once ChatAgent.fetchCompletion
    /// drops orphan .remoteCommandResponse messages instead of
    /// falling through to a new LLM call.
    func test_chat_orphanToolResponseAfterStop_doesNotOrphanQueuedMessage() throws {
        let providerName = AITermController.provider?.displayName ?? ""
        let envKey: String?
        switch providerName {
        case "OpenAI":     envKey = Self.configValue("OPENAI_API_KEY")
        case "Anthropic":  envKey = Self.configValue("ANTHROPIC_API_KEY")
        case "Google":     envKey = Self.configValue("GEMINI_API_KEY")
        case "Deep Seek":  envKey = Self.configValue("DEEPSEEK_API_KEY")
        default:           envKey = nil
        }
        guard let apiKey = envKey, !apiKey.isEmpty else {
            throw XCTSkip("No live API key for current provider \(providerName)")
        }
        guard AITermController.provider?.functionsSupported == true else {
            throw XCTSkip("Configured provider does not support function calling")
        }
        guard let broker = ChatBroker.instance else {
            throw XCTSkip("ChatBroker.instance unavailable")
        }

        let perms = #"[{"guid":"queue-test","category":"Run Commands","chatID":"queue-test"},"always"]"#
        let recorder = BrokerEventRecorder()
        let listenAll = broker.subscribe(chatID: nil, registrationProvider: nil) { update in
            recorder.record(update)
        }
        defer { listenAll.unsubscribe() }

        let chatID = try broker.create(
            chatWithTitle: "live orphan-tool-response test \(UUID().uuidString.prefix(8))",
            terminalSessionGuid: "queue-test",
            browserSessionGuid: nil,
            permissions: perms,
            initialMessages: [])
        addTeardownBlock { try? broker.delete(chatID: chatID) }

        let registrationProvider = TestRegistrationProvider(apiKey: apiKey)
        let registrationSub = broker.subscribe(chatID: chatID,
                                               registrationProvider: registrationProvider) { _ in }
        defer { registrationSub.unsubscribe() }

        // Long enough that the user gets a chance to press Stop and
        // type a second message before the tool's response comes back.
        let toolDelay: TimeInterval = 4.0
        let responder = FakeToolResponder(broker: broker,
                                          chatID: chatID,
                                          delay: toolDelay,
                                          output: "tool ran")
        defer { responder.shutdown() }

        let sawToolRequest = expectation(description: "tool request seen")
        let sawBTurnEnd    = expectation(description: "B's turn ends (typing=false)")
        var turnEndsAfterStop = 0
        var pressedStop = false
        recorder.onEntry = { entry, _ in
            switch entry {
            case .delivery(let message, _):
                if case .remoteCommandRequest = message.content, message.author == .agent {
                    sawToolRequest.fulfill()
                }
            case .typing(let isTyping, let participant):
                guard participant == .agent, !isTyping else { return }
                if pressedStop {
                    // First typing=false after stop = A's turn ending
                    // (stop drained A). Second = B's turn ending.
                    turnEndsAfterStop += 1
                    if turnEndsAfterStop == 2 {
                        sawBTurnEnd.fulfill()
                    }
                }
            }
        }

        // (1) Publish A; wait for the tool dispatch.
        try broker.publish(message: userText(chatID: chatID,
                                             body: "Use execute_command to run any command. The output does not matter."),
                           toChatID: chatID, partial: false)
        wait(for: [sawToolRequest], timeout: 60)

        // (2) Press Stop while the tool is in flight.
        pressedStop = true
        let stopMessage = Message(chatID: chatID,
                                  author: .user,
                                  content: .userCommand(.stop),
                                  sentDate: Date(),
                                  uniqueID: UUID())
        try broker.publish(message: stopMessage, toChatID: chatID, partial: false)

        // (3) Publish B (a simple follow-up question).
        try broker.publish(message: userText(chatID: chatID,
                                             body: "Reply with the single digit answer to 1+1, nothing else."),
                           toChatID: chatID, partial: false)

        // (4) Eventually the fake responder publishes the tool response
        //     (orphan, since stop cleared the pending dispatcher). With
        //     the bug present this orphan kicks off a new LLM call that
        //     silently cancels B's in-flight turn; B's turn never ends
        //     and this expectation times out.
        wait(for: [sawBTurnEnd], timeout: 90)

        let dump = recorder.summary(formatContent: short)
        print("[orphan-tool-test] broker log:\n\(dump)")
    }

    /// Repros GitLab issue #12883: with DeepSeek, asking the AI chat to
    /// run a command and then sending a follow-up turn fails with HTTP
    /// 400 "An assistant message with 'tool_calls' must be followed by
    /// tool messages responding to each 'tool_call_id' (insufficient tool
    /// messages following tool_calls message)".
    ///
    /// Mechanism (client side, not the model): a tool call that never
    /// gets a response — e.g. an `.ask` request the user abandons, or a
    /// parked request cleared by `cancelPendingCommands` on the next
    /// user message — stays in the transcript as an orphan
    /// `.remoteCommandRequest`. On the next turn `ChatAgent.translate`
    /// emits it as an assistant `functionCall` but appends the
    /// synthesized "interrupted" `functionOutput` at the END of the
    /// message array (ChatAgent.swift:451-466) instead of immediately
    /// after the call. When any persisted message sits between the
    /// orphan call and the end of history, the wire order becomes
    /// `assistant tool_calls → user/agent text → … → tool output`, which
    /// DeepSeek (and the legacy OpenAI chat-completions path) reject for
    /// breaking tool_call→tool_output adjacency. Anthropic, Gemini, and
    /// the OpenAI Responses API pair by id and tolerate it, which is why
    /// the issue is reported only against DeepSeek.
    ///
    /// The turn is pinned to a DeepSeek model via the user message's
    /// `configuration.model` (ChatAgent forwards it to
    /// AIConversation.providerOverride), so the repro doesn't depend on
    /// whichever provider the test environment defaults to. The
    /// transcript is seeded via `initialMessages` (the same on-disk shape
    /// a reloaded chat would have) so the repro is deterministic and
    /// costs a single round-trip. The orphan call is followed by two more
    /// messages, which is exactly what forces the synthesized output past
    /// them to the end.
    ///
    /// FAILS while translate appends orphan filler at the end; PASSES
    /// once the synthesized output is inserted adjacent to its call.
    func test_chat_orphanToolCallBeforeLaterMessages_doesNotPoisonNextTurn() throws {
        // Issue #12883 is DeepSeek-specific: it's the vendor whose
        // chat-completions endpoint enforces tool_call→tool_output
        // adjacency. Pin the turn to a DeepSeek model so the malformed
        // order is actually rejected; skip if there's no DeepSeek key.
        guard let apiKey = Self.configValue("DEEPSEEK_API_KEY"), !apiKey.isEmpty else {
            throw XCTSkip("No DEEPSEEK_API_KEY; issue #12883 only reproduces against DeepSeek")
        }
        // Prefer a non-thinking DeepSeek model to keep the round-trip
        // focused on message ordering rather than reasoning round-trip.
        let deepSeekModel = AIMetadata.instance.models.first(where: {
            $0.vendor == .deepSeek && !$0.features.contains(.configurableThinking)
        }) ?? AIMetadata.instance.models.first(where: { $0.vendor == .deepSeek })
        guard let deepSeekModel else {
            throw XCTSkip("No DeepSeek model in AIMetadata")
        }
        guard let broker = ChatBroker.instance else {
            throw XCTSkip("ChatBroker.instance unavailable")
        }

        // Build a transcript that already holds an orphan tool call
        // (a .remoteCommandRequest with no matching .remoteCommandResponse)
        // followed by two more persisted messages. The trailing messages
        // are what push translate's synthesized output to the end and
        // break adjacency.
        let orphanCallID = "call_orphan_\(UUID().uuidString.prefix(8))"
        let initialMessages: [Message] = [
            seedUserText("Run a quick command for me."),
            seedOrphanToolCall(callID: orphanCallID, command: "ls"),
            seedUserText("Actually never mind that, let's just chat instead."),
            seedAgentText("Sure, happy to chat. What's on your mind?"),
        ]

        let recorder = BrokerEventRecorder()
        let listenAll = broker.subscribe(chatID: nil, registrationProvider: nil) { update in
            recorder.record(update)
        }
        defer { listenAll.unsubscribe() }

        let chatID = try broker.create(
            chatWithTitle: "live orphan-tool-call test \(UUID().uuidString.prefix(8))",
            terminalSessionGuid: "queue-test",
            browserSessionGuid: nil,
            permissions: "",
            initialMessages: initialMessages)
        addTeardownBlock { try? broker.delete(chatID: chatID) }

        let registrationProvider = TestRegistrationProvider(apiKey: apiKey)
        let registrationSub = broker.subscribe(chatID: chatID,
                                               registrationProvider: registrationProvider) { _ in }
        defer { registrationSub.unsubscribe() }

        // Send a brand-new user turn. Rebuilding history for it walks the
        // seeded transcript and (with the bug) ships the orphan call far
        // from its synthesized output.
        let sawTurnEnd = expectation(description: "agent turn ends (typing=false)")
        recorder.onEntry = { entry, _ in
            if case .typing(let isTyping, let participant) = entry,
               !isTyping, participant == .agent {
                sawTurnEnd.fulfill()
            }
        }

        var trigger = userText(chatID: chatID,
                               body: "What is 1 + 1? Reply with just the digit.")
        trigger.configuration = Message.Configuration(hostedWebSearchEnabled: false,
                                                      vectorStoreIDs: [],
                                                      model: deepSeekModel.name,
                                                      shouldThink: false)
        try broker.publish(message: trigger, toChatID: chatID, partial: false)
        wait(for: [sawTurnEnd], timeout: 90)

        let dump = recorder.summary(formatContent: short)
        print("[orphan-tool-call-test] broker log (model=\(deepSeekModel.name)):\n\(dump)")

        // A vendor rejection surfaces as ChatAgent's committed error
        // message: "🛑 I ran into a problem: <error>". For DeepSeek the
        // error text carries "insufficient tool messages" / status 400.
        let errorDelivery = recorder.firstDelivery { msg in
            guard msg.author == .agent, let text = msg.content.simpleText else { return false }
            let lower = text.lowercased()
            return text.contains("🛑")
                || lower.contains("insufficient tool")
                || lower.contains("must be followed by tool")
                || lower.contains("status 400")
        }
        if let errorDelivery,
           case .delivery(let msg, _) = recorder.entries[errorDelivery] {
            XCTFail("""
                Next turn was poisoned by the orphan tool call (issue #12883). \
                The agent replied with an error instead of answering: \
                \(msg.content.simpleText ?? "<non-text>"). \
                translate() appended the synthesized tool output at the end of \
                history instead of adjacent to its tool call, so DeepSeek \
                (\(deepSeekModel.name)) rejected the malformed message order. \
                Full log printed above.
                """)
        }
    }

    // MARK: - Helpers

    /// A function-call id wrapper matching how vendors round-trip ids.
    private func seedFcid(_ s: String) -> LLM.Message.FunctionCallID {
        LLM.Message.FunctionCallID(callID: s, itemID: s)
    }

    /// A persisted assistant tool call with NO matching response: the
    /// orphan that issue #12883 is about. chatID is a placeholder;
    /// broker.create rewrites it to the real chat id.
    private func seedOrphanToolCall(callID: String, command: String) -> Message {
        let llm = LLM.Message(
            role: .assistant,
            body: .functionCall(LLM.FunctionCall(name: "execute_command",
                                                 arguments: "{\"command\":\"\(command)\"}",
                                                 id: callID,
                                                 thoughtSignature: nil),
                                id: seedFcid(callID)))
        let rc = RemoteCommand(llmMessage: llm,
                               content: .executeCommand(.init(command: command)))
        return Message(chatID: "seed",
                       author: .agent,
                       content: .remoteCommandRequest(.classic(rc), safe: nil),
                       sentDate: Date(),
                       uniqueID: UUID())
    }

    private func seedUserText(_ s: String) -> Message {
        Message(chatID: "seed", author: .user, content: .markdown(s),
                sentDate: Date(), uniqueID: UUID())
    }

    private func seedAgentText(_ s: String) -> Message {
        Message(chatID: "seed", author: .agent, content: .markdown(s),
                sentDate: Date(), uniqueID: UUID())
    }

    private func userText(chatID: String, body: String) -> Message {
        return Message(chatID: chatID,
                       author: .user,
                       content: .plainText(body, context: nil),
                       sentDate: Date(),
                       uniqueID: UUID())
    }

    private func short(_ content: Message.Content) -> String {
        switch content {
        case .plainText(let s, _): return "text=\(s.prefix(40))"
        case .markdown(let s):     return "md=\(s.prefix(40))"
        case .remoteCommandRequest: return "toolRequest"
        case .remoteCommandResponse: return "toolResponse"
        case .setPermissions:      return "setPermissions"
        case .append:              return "append"
        case .commit:              return "commit"
        case .clientLocal:         return "clientLocal"
        default:                   return "\(content)"
        }
    }

    /// Best-effort check that nobody has pre-instantiated ChatClient.
    /// We don't want to read its private singleton, so probe indirectly
    /// — if ChatClient.instance were already created, its broker
    /// processor would be in broker.processors. Since processors are
    /// just closures, we can't introspect them; instead we accept this
    /// returns false here and rely on the test path not calling it.
    private func chatClientAlreadyInstantiated() -> Bool {
        return false
    }

    /// Static config-value lookup mirrors AILiveDriver.configValue.
    /// Public extension methods can't reach the private one, so
    /// duplicate the trivial reader.
    private static func configValue(_ key: String) -> String? {
        let configPath = AILiveHarness.configFilePath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            return nil
        }
        return json[key]
    }
}

// MARK: - Test fixtures

private final class TestRegistrationProvider: AIRegistrationProvider {
    let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func registrationProviderRequestRegistration(_ completion: @escaping (AITermController.Registration?) -> ()) {
        completion(AITermController.Registration(apiKey: apiKey))
    }
}

/// Records every broker delivery AND typing-status transition for
/// post-run ordering assertions. typingStatus toggles bracket each
/// agent turn (true on startNextTurn, false on finishTurn), which
/// gives the test a clean per-turn boundary independent of streaming
/// chunk noise and LLM phrasing.
@MainActor
private final class BrokerEventRecorder {
    enum Entry {
        case delivery(Message, String)
        case typing(Bool, Participant)
    }

    private(set) var entries: [Entry] = []
    private(set) var timestamps: [Date] = []
    var onEntry: ((Entry, Int) -> Void)?

    func record(_ update: ChatBroker.Update) {
        let entry: Entry
        switch update {
        case .delivery(let message, let chatID, _):
            entry = .delivery(message, chatID)
        case .typingStatus(let isTyping, let participant):
            entry = .typing(isTyping, participant)
        }
        entries.append(entry)
        timestamps.append(Date())
        onEntry?(entry, entries.count - 1)
    }

    func summary(formatContent: (Message.Content) -> String) -> String {
        var lines: [String] = []
        for (idx, entry) in entries.enumerated() {
            switch entry {
            case let .delivery(message, _):
                lines.append("  [\(idx)] \(message.author.rawValue):\(formatContent(message.content))")
            case let .typing(isTyping, participant):
                lines.append("  [\(idx)] typing:\(participant.rawValue)=\(isTyping)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Index of the first .delivery whose message satisfies `predicate`,
    /// starting at `after` (default 0).
    func firstDelivery(after: Int = 0, where predicate: (Message) -> Bool) -> Int? {
        for i in after..<entries.count {
            if case .delivery(let msg, _) = entries[i], predicate(msg) {
                return i
            }
        }
        return nil
    }

    /// Index of the first agent typing=false transition at or after `from`.
    func firstAgentTurnEnd(at: Int = 0) -> Int? {
        for i in at..<entries.count {
            if case let .typing(isTyping, participant) = entries[i],
               !isTyping, participant == .agent {
                return i
            }
        }
        return nil
    }
}

/// Acts as the broker-side tool runner: on the first
/// .remoteCommandRequest seen, parks for `delay`, then publishes a
/// matching .remoteCommandResponse with `output`. Subsequent requests
/// are ignored — this test exercises one tool dispatch.
@MainActor
private final class FakeToolResponder {
    private let broker: ChatBroker
    private let chatID: String
    private let delay: TimeInterval
    private let output: String
    private var subscription: ChatBroker.Subscription?
    private var responded = false

    init(broker: ChatBroker, chatID: String, delay: TimeInterval, output: String) {
        self.broker = broker
        self.chatID = chatID
        self.delay = delay
        self.output = output
        subscription = broker.subscribe(chatID: chatID,
                                        registrationProvider: nil) { [weak self] update in
            self?.handle(update)
        }
    }

    func shutdown() {
        subscription?.unsubscribe()
        subscription = nil
    }

    private func handle(_ update: ChatBroker.Update) {
        guard case .delivery(let message, _, _) = update else { return }
        guard !responded else { return }
        guard case .remoteCommandRequest(let payload, _) = message.content else { return }
        guard case .classic(let cmd) = payload else { return }
        responded = true
        let requestID = message.uniqueID
        let functionName = cmd.content.functionName
        // Round-trip the LLM-side function_call id (carried inside the
        // RemoteCommand's llmMessage) so ChatAgent.translate writes a
        // well-formed function_output id when reconstructing the
        // conversation history for the NEXT turn (e.g. user B's turn).
        // Without this, OpenAI Responses 400s on the next round-trip
        // because the function_output is missing its matching call_id.
        // Mirrors what ChatClient.respondSuccessfullyToRemoteCommandRequest
        // does in production (ChatClient.swift:202).
        let functionCallID = cmd.llmMessage.functionCallID
        let delay = self.delay
        let output = self.output
        let broker = self.broker
        let chatID = self.chatID
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let response = Message(
                chatID: chatID,
                author: .user,
                content: .remoteCommandResponse(.success(output),
                                                requestID,
                                                functionName,
                                                functionCallID),
                sentDate: Date(),
                uniqueID: UUID())
            try? broker.publish(message: response, toChatID: chatID, partial: false)
        }
    }
}

// MARK: - Convenience accessors

private extension Message.Content {
    /// Extract a plain-text body when the content carries one. Returns
    /// nil for non-textual variants. Used by the test's ordering
    /// scan over recorder.events.
    var simpleText: String? {
        switch self {
        case .plainText(let s, _): return s
        case .markdown(let s):     return s
        default:                   return nil
        }
    }
}
