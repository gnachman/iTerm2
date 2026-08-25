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
        // This test acts as the broker-side tool runner, so no processor
        // (notably ChatClient's, which exists at launch on a machine with a
        // paired companion) may intercept its messages.
        suspendBrokerProcessors(broker)

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
        // emitExecuting: represent a genuinely in-flight (running) tool. This
        // fixture uses a fabricated session guid, so remoteCommandParksOnUser
        // returns true (no resolvable session) and the command parks with
        // clearedTyping == true even though perms grant .always - a state a real
        // .always+resolvable-session auto-run never reaches. A real long-running
        // command publishes .executingCommand (ChatClient.performRemoteCommand),
        // so emitting it here matches production AND records the execution with
        // ChatService, so the #12984 abandon-pending-approval logic correctly
        // leaves this running tool alone and B waits for the turn as intended.
        let responder = FakeToolResponder(broker: broker,
                                          chatID: chatID,
                                          delay: toolDelay,
                                          output: toolOutput,
                                          emitExecuting: true)
        defer { responder.shutdown() }

        // 6) Expectations driven by the recorder's transition log.
        //    These are sequenced strictly: tool request, then A's turn
        //    end (turnLifecycle .ended after the tool round-trip), then
        //    B's turn end (second .ended). The recorder's onEntry hook
        //    fulfills them as it observes matching events. Turn boundaries
        //    are read from turnLifecycle, not typing edges, because typing
        //    now toggles false mid-turn when A parks for the tool result.
        let sawToolRequest = expectation(description: "agent dispatched .remoteCommandRequest")
        let sawATurnEnd    = expectation(description: "first agent turnLifecycle .ended after tool round-trip (A's turn finished)")
        let sawBTurnEnd    = expectation(description: "second agent turnLifecycle .ended (B's turn finished)")
        let userMessageABody = "Use the execute_command tool to run any command. The exact command does not matter."
        let userMessageBBody = "Reply with the single digit answer to 1+1, nothing else."

        var agentTurnEndCount = 0
        var toolRequestSeen = false
        recorder.onEntry = { entry, _ in
            switch entry {
            case .delivery(let message, _):
                // One-shot: a later turn can legitimately call the tool
                // again, and a second fulfill() would assert (crashing the
                // host, since asserts are enabled).
                if case .remoteCommandRequest = message.content,
                   message.author == .agent, !toolRequestSeen {
                    toolRequestSeen = true
                    sawToolRequest.fulfill()
                }
            case .typing:
                // Spinner hint only; not a turn boundary (fires false on a park).
                return
            case .turnLifecycle(let event):
                guard event == .ended else { return }
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
        //    now. The queue must hold it — B's turn does not start
        //    until A's turn ends first.
        try broker.publish(message: userText(chatID: chatID, body: userMessageBBody),
                           toChatID: chatID, partial: false)

        // 9) Wait for A's turn to fully finish (turnLifecycle .ended).
        //    This can only happen after the fake responder publishes the
        //    tool response AND the post-tool LLM call completes.
        wait(for: [sawATurnEnd], timeout: 120)

        // 10) Wait for B's turn to finish (second .ended). If queue
        //     discipline holds, this fires AFTER A's turn ends.
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
        suspendBrokerProcessors(broker)

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
        let sawBTurnEnd = expectation(description: "B's turn ends (turnLifecycle .ended)")
        var sawStream = false
        var bTurnStarted = false
        var bTurnEnded = false
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
            case .typing:
                // Spinner hint only; not a turn boundary.
                return
            case .turnLifecycle(let event):
                switch event {
                case .started:
                    if sawStream { bTurnStarted = true }
                case .ended:
                    if bTurnStarted, !bTurnEnded {
                        bTurnEnded = true
                        sawBTurnEnd.fulfill()
                    }
                case .unknownFuture:
                    return
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

    /// Repros GitLab issue #12984: the AI makes a tool call that needs
    /// approval, the user IGNORES the approval prompt, types a new
    /// message, and hits return — and the AI "just stops responding."
    ///
    /// Mechanism (same head-of-line wedge as the stop-then-send bug, but
    /// triggered by an ignored approval instead of Stop): an
    /// approval-gated tool call parks the in-flight turn.
    /// ChatAgent.reallyRunCommand stashes the dispatcher completion in
    /// pendingRemoteCommands and never calls it, so fetchCompletion's
    /// completion never fires and ChatService.finishTurn never pops the
    /// queue head. The ignored approval leaves that parked turn sitting at
    /// index 0 of pendingMessages indefinitely. The user's next message is
    /// enqueued behind it, but ChatService.enqueue only calls
    /// startNextTurn when queue.count == 1, so with the parked head still
    /// present the new message is never dispatched. The
    /// cancelPendingCommands() at the top of
    /// ChatAgent.fetchCompletionForRegularMessage — which WOULD clear the
    /// park — is only reached once the new message's turn actually runs,
    /// which it never does. So the queue is wedged and the chat goes
    /// silent.
    ///
    /// Test: grant Run Commands = .ask so the tool is exposed AND parks on
    /// approval. Send msg A that triggers the tool; wait for the
    /// .remoteCommandRequest (the approval prompt). DO NOT answer it — no
    /// tool responder is installed, so the approval is simply ignored.
    /// Send msg B and expect B's turn to dispatch (turnLifecycle .started
    /// after B). With the bug, B is enqueued behind the parked approval
    /// head, startNextTurn is never called for it, no turn ever starts, and
    /// this times out.
    ///
    /// FAILS on current main; PASSES once an ignored approval no longer
    /// wedges the queue (e.g. a human message enqueued behind a parked
    /// approval head resolves the park and lets the new turn start).
    func test_chat_ignoredApprovalThenSend_secondMessageStillDispatches() throws {
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
            throw XCTSkip("Configured provider does not support function calling; approval-park test needs a tool round-trip")
        }
        guard let broker = ChatBroker.instance else {
            throw XCTSkip("ChatBroker.instance unavailable")
        }
        suspendBrokerProcessors(broker)

        // Run Commands = .ask: exposes execute_command to the LLM AND makes the
        // call PARK on the user's approval (Permission.parksOnApproval is always
        // true for .ask). No FakeToolResponder is installed, so the parked
        // approval is never answered — exactly the "user ignores the request"
        // case from issue #12984.
        let perms = #"[{"guid":"queue-test","category":"Run Commands","chatID":"queue-test"},"ask"]"#

        let recorder = BrokerEventRecorder()
        let listenAll = broker.subscribe(chatID: nil, registrationProvider: nil) { update in
            recorder.record(update)
        }
        defer { listenAll.unsubscribe() }

        let chatID = try broker.create(
            chatWithTitle: "live ignored-approval test \(UUID().uuidString.prefix(8))",
            terminalSessionGuid: "queue-test",
            browserSessionGuid: nil,
            permissions: perms,
            initialMessages: [])
        addTeardownBlock { try? broker.delete(chatID: chatID) }

        let registrationProvider = TestRegistrationProvider(apiKey: apiKey)
        let registrationSub = broker.subscribe(chatID: chatID,
                                               registrationProvider: registrationProvider) { _ in }
        defer { registrationSub.unsubscribe() }

        let sawToolRequest = expectation(description: "agent dispatched .remoteCommandRequest (approval prompt)")
        let sawBTurnStarted = expectation(description: "B's turn dispatches (turnLifecycle .started after B) — the queue is no longer wedged")
        var toolRequestSeen = false
        var bTurnStarted = false
        // Flipped true right before B is published. A's turn started before that,
        // and abandoning the parked approval emits A's .ended followed by
        // startNextTurn(B)'s fresh .started, so the first .started after this flag
        // is B's turn dispatching. That is the exact thing the wedge prevents: with
        // the bug B enqueues behind the parked head, startNextTurn is never called
        // for it, and no .started ever fires after B. (Waiting on B's turn END
        // instead would be flaky: the model sometimes re-issues the tool on B's
        // turn and re-parks, so B legitimately may not end.)
        var bPublished = false
        recorder.onEntry = { entry, _ in
            switch entry {
            case .delivery(let message, _):
                if case .remoteCommandRequest = message.content,
                   message.author == .agent, !toolRequestSeen {
                    toolRequestSeen = true
                    sawToolRequest.fulfill()
                }
            case .typing:
                // Spinner hint only; toggles false on the approval park and is
                // not a turn boundary.
                return
            case .turnLifecycle(let event):
                if event == .started, bPublished, !bTurnStarted {
                    bTurnStarted = true
                    sawBTurnStarted.fulfill()
                }
            }
        }

        // (1) Send A; wait for the tool dispatch. The turn is now parked on the
        //     user's approval — which we deliberately never answer.
        try broker.publish(message: userText(chatID: chatID,
                                             body: "Use the execute_command tool to run any command. The exact command does not matter."),
                           toChatID: chatID, partial: false)
        wait(for: [sawToolRequest], timeout: 60)

        // (2) Ignore the approval prompt. Instead, type a new message and hit
        //     return — the exact repro steps from the issue.
        bPublished = true
        try broker.publish(message: userText(chatID: chatID,
                                             body: "Never mind that. Reply with the single digit answer to 1+1, nothing else."),
                           toChatID: chatID, partial: false)

        // (3) Expect B's turn to dispatch. With the bug, B is enqueued behind the
        //     parked approval head, startNextTurn is never called for it, no turn
        //     ever starts, and this times out (the AI "just stops responding").
        wait(for: [sawBTurnStarted], timeout: 90)

        let dump = recorder.summary(formatContent: short)
        print("[ignored-approval-test] broker log (provider=\(providerName)):\n\(dump)")
    }

    /// The other side of the #12984 fix: a command the user ALREADY APPROVED
    /// and that is now executing must NOT be abandoned when the user types a
    /// follow-up. This is "state 3" - at the agent level it is indistinguishable
    /// from an unanswered approval (both leave a parked, clearedTyping entry), so
    /// the naive fix would stop() the running command and orphan its result.
    /// ChatService avoids that by tracking .executingCommand, and the follow-up
    /// message must simply WAIT for the running command's turn to finish.
    ///
    /// Test: grant Run Commands = .ask so the call parks. The responder emits
    /// .executingCommand the instant it sees the request (simulating the user
    /// clicking Allow), then delays before publishing the response. While the
    /// command "runs", send msg B. Assert the strict order tool request -> B
    /// published -> tool RESPONSE delivered -> A's turn ends -> B's turn ends.
    /// The critical link is response-before-A's-turn-end: if the fix over-fired
    /// and abandoned the approved command, A's turn would end on the stop()
    /// BEFORE the (now orphaned) response, and that assertion would fail.
    func test_chat_approvedCommandExecutingThenSend_isNotAbandoned() throws {
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
            throw XCTSkip("Configured provider does not support function calling; approval-park test needs a tool round-trip")
        }
        guard let broker = ChatBroker.instance else {
            throw XCTSkip("ChatBroker.instance unavailable")
        }
        suspendBrokerProcessors(broker)

        // .ask so the call parks; the responder (emitExecuting: true) then plays
        // "user approved, command now running".
        let perms = #"[{"guid":"queue-test","category":"Run Commands","chatID":"queue-test"},"ask"]"#

        let recorder = BrokerEventRecorder()
        let listenAll = broker.subscribe(chatID: nil, registrationProvider: nil) { update in
            recorder.record(update)
        }
        defer { listenAll.unsubscribe() }

        let chatID = try broker.create(
            chatWithTitle: "live approved-executing test \(UUID().uuidString.prefix(8))",
            terminalSessionGuid: "queue-test",
            browserSessionGuid: nil,
            permissions: perms,
            initialMessages: [])
        addTeardownBlock { try? broker.delete(chatID: chatID) }

        let registrationProvider = TestRegistrationProvider(apiKey: apiKey)
        let registrationSub = broker.subscribe(chatID: chatID,
                                               registrationProvider: registrationProvider) { _ in }
        defer { registrationSub.unsubscribe() }

        let toolDelay: TimeInterval = 3.0
        let toolMarker = "kw-VIOLET-OTTER-42"
        let responder = FakeToolResponder(broker: broker,
                                          chatID: chatID,
                                          delay: toolDelay,
                                          output: "command output containing \(toolMarker)",
                                          emitExecuting: true)
        defer { responder.shutdown() }

        let sawToolRequest = expectation(description: "agent dispatched .remoteCommandRequest")
        let sawATurnEnd    = expectation(description: "first agent turnLifecycle .ended (A's turn finished after the tool round-trip)")
        let sawBTurnEnd    = expectation(description: "second agent turnLifecycle .ended (B's turn finished)")
        let userMessageBBody = "Reply with the single digit answer to 1+1, nothing else."
        var agentTurnEndCount = 0
        var toolRequestSeen = false
        recorder.onEntry = { entry, _ in
            switch entry {
            case .delivery(let message, _):
                if case .remoteCommandRequest = message.content,
                   message.author == .agent, !toolRequestSeen {
                    toolRequestSeen = true
                    sawToolRequest.fulfill()
                }
            case .typing:
                return
            case .turnLifecycle(let event):
                guard event == .ended else { return }
                agentTurnEndCount += 1
                if agentTurnEndCount == 1 {
                    sawATurnEnd.fulfill()
                } else if agentTurnEndCount == 2 {
                    sawBTurnEnd.fulfill()
                }
            }
        }

        // (1) Send A; wait for the tool dispatch. The responder has, by now, also
        //     published .executingCommand (approve + run).
        try broker.publish(message: userText(chatID: chatID,
                                             body: "Use the execute_command tool to run any command. The exact command does not matter."),
                           toChatID: chatID, partial: false)
        wait(for: [sawToolRequest], timeout: 60)

        // (2) Send B while the approved command is still running. It must WAIT for
        //     A's turn (the running command is not abandoned).
        try broker.publish(message: userText(chatID: chatID, body: userMessageBBody),
                           toChatID: chatID, partial: false)

        wait(for: [sawATurnEnd], timeout: 120)
        wait(for: [sawBTurnEnd], timeout: 120)

        let dump = recorder.summary(formatContent: short)
        print("[approved-executing-test] broker log (provider=\(providerName)):\n\(dump)")

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
                bTurnEnd=\(String(describing: bTurnEndIdx)). Full log printed above.
                """)
            return
        }

        XCTAssertLessThan(toolRequestIdx, bPublishIdx,
                          "B should be published after the tool request (we want to race the executing command)")
        XCTAssertLessThan(bPublishIdx, toolResponseIdx,
                          "B must be published before the tool response — proves B raced a still-running command")
        XCTAssertLessThan(toolResponseIdx, aTurnEndIdx,
                          "A's turn must end AFTER the tool response was consumed. If the approved command were wrongly abandoned, A's turn would end on stop() before the response and its result would be orphaned. (#12984 state 3)")
        XCTAssertLessThan(aTurnEndIdx, bTurnEndIdx,
                          "B's turn must end after A's — queue discipline")
    }

    /// Guards a #12984 balance bug in ChatService's execution tracking: the
    /// per-chat executingCommandCounts is incremented by an agent-authored
    /// .executingCommand but decremented only by a user .remoteCommandResponse,
    /// and those are not paired by identity. If the user presses Stop while an
    /// approved command is executing (count == 1) and that command never returns
    /// a response (a hung command, or a session that closed), agent.stop()
    /// resolves the parked completion internally and publishes NO response, so
    /// the count stays stuck above zero with no self-healing path. A stuck count
    /// silently disables the fix for that chat: the abandon gate
    /// executingCommandCounts[chatID] == nil is false forever, so the NEXT time
    /// the AI asks for approval and the user ignores it and types a new message,
    /// the queue wedges again exactly like the original bug.
    ///
    /// Test: drive the count to 1 by publishing the same .executingCommand
    /// ChatClient sends (a command started running), then press Stop WITHOUT ever
    /// publishing that command's response (it hung). Then run the ordinary
    /// ignored-approval-then-send repro. It must still abandon the park and
    /// dispatch the new message. With the leak, the stuck count skips the abandon
    /// and no turn ever starts after the follow-up — this times out.
    ///
    /// FAILS if Stop does not reset executingCommandCounts; PASSES once
    /// handleUserCommand(.stop) clears it.
    func test_chat_stopDuringExecutingCommand_doesNotWedgeLaterApproval() throws {
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
            throw XCTSkip("Configured provider does not support function calling; approval-park test needs a tool round-trip")
        }
        guard let broker = ChatBroker.instance else {
            throw XCTSkip("ChatBroker.instance unavailable")
        }
        suspendBrokerProcessors(broker)

        let perms = #"[{"guid":"queue-test","category":"Run Commands","chatID":"queue-test"},"ask"]"#

        let recorder = BrokerEventRecorder()
        let listenAll = broker.subscribe(chatID: nil, registrationProvider: nil) { update in
            recorder.record(update)
        }
        defer { listenAll.unsubscribe() }

        let chatID = try broker.create(
            chatWithTitle: "live stop-clears-executing test \(UUID().uuidString.prefix(8))",
            terminalSessionGuid: "queue-test",
            browserSessionGuid: nil,
            permissions: perms,
            initialMessages: [])
        addTeardownBlock { try? broker.delete(chatID: chatID) }

        let registrationProvider = TestRegistrationProvider(apiKey: apiKey)
        let registrationSub = broker.subscribe(chatID: chatID,
                                               registrationProvider: registrationProvider) { _ in }
        defer { registrationSub.unsubscribe() }

        // (1) Simulate an approved command that started running: publish the same
        //     .executingCommand ChatClient publishes, so ChatService records an
        //     execution in progress (count -> 1). Its response is never published
        //     (the command hangs), so nothing decrements it.
        let executing = Message(chatID: chatID,
                                author: .agent,
                                content: .clientLocal(.init(action: .executingCommand(sampleExecuteCommand()))),
                                sentDate: Date(),
                                uniqueID: UUID())
        try broker.publish(message: executing, toChatID: chatID, partial: false)

        // (2) User presses Stop. This must reset the stuck count; otherwise the
        //     abandon gate below stays disabled for this chat.
        try broker.publish(message: Message(chatID: chatID,
                                            author: .user,
                                            content: .userCommand(.stop),
                                            sentDate: Date(),
                                            uniqueID: UUID()),
                           toChatID: chatID, partial: false)

        // (3) The ordinary repro: the AI asks for approval, the user ignores it
        //     and sends a new message. This must still dispatch (it only does if
        //     Stop reset the count).
        let sawToolRequest = expectation(description: "agent dispatched .remoteCommandRequest (approval prompt)")
        let sawFollowupTurnStarted = expectation(description: "follow-up turn dispatches (turnLifecycle .started after it) — gate not wedged")
        var toolRequestSeen = false
        var followupTurnStarted = false
        var followupPublished = false
        recorder.onEntry = { entry, _ in
            switch entry {
            case .delivery(let message, _):
                if case .remoteCommandRequest = message.content,
                   message.author == .agent, !toolRequestSeen {
                    toolRequestSeen = true
                    sawToolRequest.fulfill()
                }
            case .typing:
                return
            case .turnLifecycle(let event):
                if event == .started, followupPublished, !followupTurnStarted {
                    followupTurnStarted = true
                    sawFollowupTurnStarted.fulfill()
                }
            }
        }

        try broker.publish(message: userText(chatID: chatID,
                                             body: "Use the execute_command tool to run any command. The exact command does not matter."),
                           toChatID: chatID, partial: false)
        wait(for: [sawToolRequest], timeout: 60)

        followupPublished = true
        try broker.publish(message: userText(chatID: chatID,
                                             body: "Never mind that. Reply with the single digit answer to 1+1, nothing else."),
                           toChatID: chatID, partial: false)

        // With the leak, the stuck count skips the abandon, the follow-up enqueues
        // behind the parked head, and no turn ever starts after it — times out.
        wait(for: [sawFollowupTurnStarted], timeout: 90)

        let dump = recorder.summary(formatContent: short)
        print("[stop-clears-executing-test] broker log (provider=\(providerName)):\n\(dump)")
    }

    /// The type-BEFORE-park ordering of #12984, which the message-arrival gate
    /// alone cannot catch. A user message enqueued while the turn is still
    /// WORKING (streaming, before any tool call) correctly waits behind the head;
    /// isAwaitingUserApproval is false at that instant, so the arrival gate does
    /// not fire. The turn THEN issues an approval-gated tool call and parks. With
    /// only the arrival gate, the queued message would stay wedged behind the
    /// parked head until the user answered the prompt or typed again. The
    /// park-arrival trigger (ChatAgent.onParkedOnUser -> ChatService) re-evaluates
    /// the wedge the instant the turn parks and abandons it so the queued message
    /// dispatches.
    ///
    /// Test: ask the model to stream a dozen lines of text and only THEN call the
    /// tool. Wait for the first streamed chunk (the turn is working, not parked),
    /// publish M1 so it enqueues behind the working head, then let the turn reach
    /// its tool call and park. M1's turn must dispatch. Non-vacuous: it asserts a
    /// tool request actually appeared (the head really parked) - and with the
    /// park-arrival trigger removed this times out (verified by hand), because M1
    /// was enqueued before the park and so never re-enters the arrival gate.
    func test_chat_typeWhileWorkingThenParks_dispatchesQueuedMessage() throws {
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
            throw XCTSkip("Configured provider does not support function calling; approval-park test needs a tool round-trip")
        }
        guard let broker = ChatBroker.instance else {
            throw XCTSkip("ChatBroker.instance unavailable")
        }
        suspendBrokerProcessors(broker)

        let perms = #"[{"guid":"queue-test","category":"Run Commands","chatID":"queue-test"},"ask"]"#

        let recorder = BrokerEventRecorder()
        let listenAll = broker.subscribe(chatID: nil, registrationProvider: nil) { update in
            recorder.record(update)
        }
        defer { listenAll.unsubscribe() }

        let chatID = try broker.create(
            chatWithTitle: "live type-before-park test \(UUID().uuidString.prefix(8))",
            terminalSessionGuid: "queue-test",
            browserSessionGuid: nil,
            permissions: perms,
            initialMessages: [])
        addTeardownBlock { try? broker.delete(chatID: chatID) }

        let registrationProvider = TestRegistrationProvider(apiKey: apiKey)
        let registrationSub = broker.subscribe(chatID: chatID,
                                               registrationProvider: registrationProvider) { _ in }
        defer { registrationSub.unsubscribe() }

        let sawAgentStreaming = expectation(description: "H emitted its first streamed text (working, not yet parked)")
        let sawToolRequest = expectation(description: "H issued the approval-gated tool call (the head parked)")
        let sawM1TurnStarted = expectation(description: "M1's turn dispatches (turnLifecycle .started after M1) — park-arrival trigger fired")
        var sawStream = false
        var toolRequestSeen = false
        var m1TurnStarted = false
        // Set true right before M1 is published, AFTER H is already streaming. H's
        // own .started fired at the very beginning, so the first .started after
        // this flag is M1's turn dispatching (H parks -> abandon -> H .ended ->
        // M1 .started).
        var m1Published = false
        recorder.onEntry = { entry, _ in
            switch entry {
            case .delivery(let message, _):
                if message.author == .agent, !sawStream {
                    switch message.content {
                    case .markdown, .plainText, .append:
                        sawStream = true
                        sawAgentStreaming.fulfill()
                    default:
                        break
                    }
                }
                if case .remoteCommandRequest = message.content,
                   message.author == .agent, !toolRequestSeen {
                    toolRequestSeen = true
                    sawToolRequest.fulfill()
                }
            case .typing:
                return
            case .turnLifecycle(let event):
                if event == .started, m1Published, !m1TurnStarted {
                    m1TurnStarted = true
                    sawM1TurnStarted.fulfill()
                }
            }
        }

        // (1) Start H: stream text first, tool call last.
        try broker.publish(message: userText(chatID: chatID,
                                             body: "Write the word thinking on 12 separate lines, one per line and nothing else on each line. Only after all 12 lines are written, call the execute_command tool to run any command."),
                           toChatID: chatID, partial: false)

        // (2) Wait until H is actively streaming (working, not parked), then enqueue
        //     M1 so it lands behind the working head - the arrival gate must NOT
        //     fire here because isAwaitingUserApproval is still false.
        wait(for: [sawAgentStreaming], timeout: 45)
        m1Published = true
        try broker.publish(message: userText(chatID: chatID,
                                             body: "Never mind that. Reply with the single digit answer to 1+1, nothing else."),
                           toChatID: chatID, partial: false)

        // (3) H finishes streaming, calls the tool, and parks. The park-arrival
        //     trigger must abandon it so M1 dispatches. With only the arrival gate,
        //     M1 stays wedged and this times out.
        wait(for: [sawToolRequest], timeout: 90)
        wait(for: [sawM1TurnStarted], timeout: 90)

        let dump = recorder.summary(formatContent: short)
        print("[type-before-park-test] broker log (provider=\(providerName)):\n\(dump)")
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
    ///   6. Assert: B's turn ends (turnLifecycle .ended fires for B).
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
        suspendBrokerProcessors(broker)

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
        let sawBTurnEnd    = expectation(description: "B's turn ends (turnLifecycle .ended)")
        var turnEndsAfterStop = 0
        var pressedStop = false
        var toolRequestSeen = false
        recorder.onEntry = { entry, _ in
            switch entry {
            case .delivery(let message, _):
                // One-shot: B's turn (or the orphan-response turn) can call
                // the tool again; a second fulfill() would assert and crash
                // the host.
                if case .remoteCommandRequest = message.content,
                   message.author == .agent, !toolRequestSeen {
                    toolRequestSeen = true
                    sawToolRequest.fulfill()
                }
            case .typing:
                // Spinner hint only; not a turn boundary (fires false on a park).
                return
            case .turnLifecycle(let event):
                guard event == .ended else { return }
                if pressedStop {
                    // First turn-end after stop = A's turn ending
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
        suspendBrokerProcessors(broker)

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
        let sawTurnEnd = expectation(description: "agent turn ends (turnLifecycle .ended)")
        var turnEnded = false
        recorder.onEntry = { entry, _ in
            if case .turnLifecycle(.ended) = entry, !turnEnded {
                turnEnded = true
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

    /// A standalone RemoteCommand for constructing a synthetic .executingCommand
    /// signal (no live PTYSession needed). Used to drive ChatService's execution
    /// count without a real command running. (GitLab #12984)
    private func sampleExecuteCommand() -> RemoteCommand {
        let callID = "call_exec_\(UUID().uuidString.prefix(8))"
        let llm = LLM.Message(
            role: .assistant,
            body: .functionCall(LLM.FunctionCall(name: "execute_command",
                                                 arguments: "{\"command\":\"sleep 999\"}",
                                                 id: callID,
                                                 thoughtSignature: nil),
                                id: seedFcid(callID)))
        return RemoteCommand(llmMessage: llm,
                             content: .executeCommand(.init(command: "sleep 999")))
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

    /// These tests play the broker-side tool runner themselves, so no broker
    /// processor may intercept their messages. That used to be "ensured" by
    /// assuming ChatClient.instance had never been created, but the guard was
    /// unenforceable (processors are anonymous closures) and the assumption
    /// is simply false on a machine with a paired companion device: the
    /// companion bridge and agent-activity notifier touch the lazily-creating
    /// ChatClient.instance at app launch, and its processor then wraps this
    /// fixture's .remoteCommandRequest (fabricated session guid, no live
    /// PTYSession) in .selectSessionRequest, which the recorder never
    /// matches. Suspend ALL processors for the test's duration and restore
    /// them on teardown; every test in this file was authored under the
    /// no-processor assumption.
    private func suspendBrokerProcessors(_ broker: ChatBroker) {
        let saved = broker.processors
        broker.processors = []
        addTeardownBlock { @MainActor in
            broker.processors = saved
        }
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
        case turnLifecycle(TurnEvent)
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
        case .turnLifecycle(let event):
            // The authoritative turn boundary. Turn-end detection keys on this
            // (not on typing edges) because typing is now a pure spinner hint
            // that toggles false mid-turn on a park.
            entry = .turnLifecycle(event)
        case .messagesRemoved:
            // Store truncation (edit/delete); not a queue-ordering event. Ignore.
            return
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
            case let .turnLifecycle(event):
                lines.append("  [\(idx)] turn:\(event.rawValue)")
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

    /// Index of the first agent turn-end (turnLifecycle .ended) at or after `at`.
    /// This is the authoritative turn boundary now that typing is a pure spinner
    /// hint that can toggle false mid-turn on a park.
    func firstAgentTurnEnd(at: Int = 0) -> Int? {
        for i in at..<entries.count {
            if case .turnLifecycle(.ended) = entries[i] {
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
    // When true, publish an agent-authored .executingCommand clientLocal the
    // instant the request is seen, before the delayed response. This simulates
    // the user APPROVING a parked .ask command so it starts running (what
    // ChatClient.performRemoteCommand does in production). ChatService keys its
    // "don't abandon a running approved command" logic on that signal, so this
    // is how a test drives state 3 (approved + executing) rather than state 2
    // (still awaiting Allow/Deny). (GitLab #12984)
    private let emitExecuting: Bool
    private var subscription: ChatBroker.Subscription?
    // One response per REQUEST, not one total: a later turn can re-issue
    // the tool (the interrupted-call filler in a rebuilt history invites a
    // retry), and if that call never got an answer the turn would park in
    // pendingRemoteCommands forever and the test would time out on turn-end.
    // Responding per-request keeps the ORPHAN semantics intact where they
    // matter: a response whose dispatcher was cleared by Stop is still an
    // orphan no matter how many requests get answered.
    private var respondedRequestIDs = Set<UUID>()

    init(broker: ChatBroker, chatID: String, delay: TimeInterval, output: String,
         emitExecuting: Bool = false) {
        self.broker = broker
        self.chatID = chatID
        self.delay = delay
        self.output = output
        self.emitExecuting = emitExecuting
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
        guard case .remoteCommandRequest(let payload, _) = message.content else { return }
        guard case .classic(let cmd) = payload else { return }
        guard respondedRequestIDs.insert(message.uniqueID).inserted else { return }
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
        if emitExecuting {
            // Mark the command as approved-and-running so ChatService records an
            // execution in progress for this chat (noteIfExecutingCommandStarted).
            let executing = Message(chatID: chatID,
                                    author: .agent,
                                    content: .clientLocal(.init(action: .executingCommand(cmd))),
                                    sentDate: Date(),
                                    uniqueID: UUID())
            try? broker.publish(message: executing, toChatID: chatID, partial: false)
        }
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
