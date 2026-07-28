//
//  AILiveBlobReplayTests.swift
//  iTerm2 AI live harness
//
//  Live integration test for blob-native replay driven through the REAL chat
//  stack: ChatBroker -> ChatService -> ChatAgent -> AIConversation -> LLM. Unlike
//  AILiveDriver (which drives a bare AITermController and never sets
//  blobReplayProvider), this exercises the actual read-side switch ChatAgent
//  installs, so it is the only automated coverage that a blob-spliced request is
//  ACCEPTED by a real vendor and that the prompt cache survives the splice.
//
//  A blob is captured only at a successful turn end, so blobCount == number of
//  turns is itself proof every turn was accepted (a rejected turn writes no blob).
//
//  Cost: ~3 Anthropic round-trips with a few-KB cached prefix. Cents per run.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
extension AILiveHarness {

    /// Three Anthropic turns through the real chat stack. Turn 1 seeds a secret in
    /// a large (reliably cacheable) message; turns 2-3 replay that history purely
    /// from stored blobs. Asserts: every turn was accepted (one blob per round),
    /// the model recalls the secret (the frozen history reached it), the stored
    /// blob bytes are spliced VERBATIM into later requests (byte-stable prefix =
    /// the cache-fix invariant), and the Anthropic prompt cache is READ on a later
    /// turn (blob replay did not churn the cached prefix).
    func test_chat_blobNativeReplay_multiTurnAnthropicAcceptedAndCached() throws {
        guard let apiKey = Self.blobConfigValue("ANTHROPIC_API_KEY"), !apiKey.isEmpty else {
            throw XCTSkip("No ANTHROPIC_API_KEY; blob-replay cache test is Anthropic-specific")
        }
        // Prefer a non-Haiku model: Haiku's minimum cacheable prefix (2048 tokens)
        // is larger, so Sonnet/Opus (1024) make the cache assertion robust.
        let anthropicModel =
            AIMetadata.instance.models.first(where: { $0.vendor == .anthropic && !$0.name.lowercased().contains("haiku") })
            ?? AIMetadata.instance.models.first(where: { $0.vendor == .anthropic })
        guard let anthropicModel else { throw XCTSkip("No Anthropic model in AIMetadata") }
        guard let broker = ChatBroker.instance else { throw XCTSkip("ChatBroker.instance unavailable") }
        Self.blobSuspendProcessors(broker, on: self)

        // Capture every request + response body across all turns.
        let wire = BlobWireCapture()
        iTermAIClient.liveObserver = { capture in
            switch capture.request.body {
            case .string(let s): wire.requests.append(s)
            case .bytes(let b): wire.requests.append("<\(b.count) bytes>")
            }
            if let response = capture.response {
                wire.responses.append(response.data)
            } else if !capture.streamChunks.isEmpty {
                wire.responses.append(capture.streamChunks.joined())
            }
        }
        defer { iTermAIClient.liveObserver = nil }

        let chatID = try broker.create(
            chatWithTitle: "live blob replay \(UUID().uuidString.prefix(8))",
            terminalSessionGuid: "blob-test",
            browserSessionGuid: nil,
            permissions: "",
            initialMessages: [])
        addTeardownBlock { try? broker.delete(chatID: chatID) }

        // Bind the chat to Anthropic up front. The provider binding locks to the
        // model of the FIRST turn (else the global default, which is whatever
        // vendor the machine is configured for), so without this a per-turn
        // configuration.model naming Anthropic is a forbidden cross-provider switch.
        try broker.listModel.setModel(chatID: chatID, modelName: anthropicModel.name)

        let registrationProvider = BlobTestRegistrationProvider(apiKey: apiKey)
        let registrationSub = broker.subscribe(chatID: chatID,
                                               registrationProvider: registrationProvider) { _ in }
        defer { registrationSub.unsubscribe() }

        // One turn: publish a user message pinned to Anthropic, wait for the turn to
        // fully end (turnLifecycle .ended).
        func runTurn(_ body: String) throws {
            let ended = expectation(description: "turn ends")
            var done = false
            let sub = broker.subscribe(chatID: chatID, registrationProvider: nil) { update in
                if case .turnLifecycle(let event) = update, event == .ended, !done {
                    done = true
                    ended.fulfill()
                }
            }
            defer { sub.unsubscribe() }
            var msg = Message(chatID: chatID, author: .user,
                              content: .plainText(body, context: nil),
                              sentDate: Date(), uniqueID: UUID())
            msg.configuration = Message.Configuration(hostedWebSearchEnabled: false,
                                                      vectorStoreIDs: [],
                                                      model: anthropicModel.name,
                                                      shouldThink: false)
            try broker.publish(message: msg, toChatID: chatID, partial: false)
            wait(for: [ended], timeout: 120)
        }

        // A large first message so the frozen prefix reliably exceeds Anthropic's
        // minimum cacheable size, and the recall in turn 3 is unambiguous.
        let secret = "PLUM-QUASAR-8842"
        let padding = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 250)
        try runTurn("Remember this secret code exactly: \(secret). Ignore the following filler: \(padding) Reply with only: OK")
        try runTurn("What is 2 + 2? Reply with only the digit.")
        try runTurn("What was the secret code I gave you earlier? Reply with only the code.")

        let db = broker.listModel.chatDatabase
        try Self.skipIfTransientVendorError(
            broker.listModel.messages(forChat: chatID, createIfNeeded: false).map { Array($0) } ?? [])

        // 1) Every turn was accepted: a blob is captured only at a successful turn
        //    end, so three blobs == three accepted turns (a rejection writes none).
        XCTAssertEqual(db.blobCount(inChat: chatID), 3,
                       "one blob per successfully completed round; fewer means a turn was rejected")

        // 2) The frozen history reached the model: it recalls the secret from a round
        //    that turns 2-3 replayed purely from blobs. Read the assembled reply from
        //    the DB (not raw SSE, whose token deltas can split the code).
        let messages: [Message] = broker.listModel.messages(forChat: chatID, createIfNeeded: false)
            .map { Array($0) } ?? []
        let lastAgentText = messages.reversed().first(where: { $0.author == .agent })
            .flatMap { Self.blobText($0.content) } ?? ""
        XCTAssertTrue(lastAgentText.contains(secret),
                      "model must recall the secret from blob-replayed history; got: \(lastAgentText)")

        // 2b) Real per-round token weights were captured by subtraction (#9): the
        //     first round has no prior turn to diff against (nil -> byte estimate),
        //     but the later rounds carry a real, positive delta-derived tokenCount.
        let capturedBlobs = db.blobs(inChat: chatID)
        XCTAssertTrue(capturedBlobs.dropFirst().allSatisfy { ($0.tokenCount ?? 0) > 0 },
                      "rounds after the first must carry a real vendor-usage-derived tokenCount: "
                      + "\(capturedBlobs.map { $0.tokenCount as Any })")

        // 3) Stored blob bytes are spliced VERBATIM into later requests (byte-stable
        //    prefix = the cache-fix invariant). The first round's inner bytes must
        //    appear in a later turn's request body.
        let blobs = db.blobs(inChat: chatID)
        try XCTSkipIf(blobs.isEmpty, "no blobs captured; earlier assertion already failed")
        let firstRoundInner = String(decoding: try ChatBlobAssembler.stitchInner([blobs[0]]), as: UTF8.self)
        XCTAssertFalse(firstRoundInner.isEmpty)
        XCTAssertTrue(wire.requests.dropFirst().contains { $0.contains(firstRoundInner) },
                      "a later request must splice the first round's stored blob bytes verbatim")

        // 4) The Anthropic prompt cache is read on a later turn: blob replay keeps
        //    the prefix byte-stable, so the cached [tools+system(+history)] prefix is
        //    re-read rather than re-created every turn (the original bug).
        var totalCacheRead = 0
        for (i, response) in wire.responses.enumerated() {
            let read = Self.blobUsageInt(response, "cache_read_input_tokens")
            let creation = Self.blobUsageInt(response, "cache_creation_input_tokens")
            print("[blob-replay] request \(i): cache_read=\(read) cache_creation=\(creation)")
            totalCacheRead += read
        }
        XCTAssertGreaterThan(totalCacheRead, 0,
                             "prompt cache must be READ on a later turn; blob replay must not churn the cached prefix")
    }

    /// A tool-using round replayed from a blob. Turn 1 runs a tool (one round =
    /// user + assistant [text, tool_use] + tool_result + final assistant, all in ONE
    /// blob). Turn 2 replays that round purely from the blob; Anthropic must accept
    /// the spliced tool_use/tool_result pairing (a broken pairing 400s) and the model
    /// must recall what the tool did. This is the mutator-B / tool-adjacency proof the
    /// offline byte-tests can't give (only a real vendor enforces the pairing).
    func test_chat_blobNativeReplay_toolRoundReplaysAndIsAccepted() throws {
        guard let apiKey = Self.blobConfigValue("ANTHROPIC_API_KEY"), !apiKey.isEmpty else {
            throw XCTSkip("No ANTHROPIC_API_KEY")
        }
        let anthropicModel =
            AIMetadata.instance.models.first(where: { $0.vendor == .anthropic && !$0.name.lowercased().contains("haiku") })
            ?? AIMetadata.instance.models.first(where: { $0.vendor == .anthropic })
        guard let anthropicModel, anthropicModel.features.contains(.functionCalling) else {
            throw XCTSkip("No function-calling Anthropic model in AIMetadata")
        }
        guard let broker = ChatBroker.instance else { throw XCTSkip("ChatBroker.instance unavailable") }
        Self.blobSuspendProcessors(broker, on: self)

        let wire = BlobWireCapture()
        iTermAIClient.liveObserver = { capture in
            switch capture.request.body {
            case .string(let s): wire.requests.append(s)
            case .bytes(let b): wire.requests.append("<\(b.count) bytes>")
            }
            if let response = capture.response { wire.responses.append(response.data) }
            else if !capture.streamChunks.isEmpty { wire.responses.append(capture.streamChunks.joined()) }
        }
        defer { iTermAIClient.liveObserver = nil }

        // Grant Run Commands so the execute_command tool is offered.
        let perms = #"[{"guid":"blob-tool-test","category":"Run Commands","chatID":"blob-tool-test"},"always"]"#
        let chatID = try broker.create(
            chatWithTitle: "live blob tool replay \(UUID().uuidString.prefix(8))",
            terminalSessionGuid: "blob-tool-test",
            browserSessionGuid: nil,
            permissions: perms,
            initialMessages: [])
        addTeardownBlock { try? broker.delete(chatID: chatID) }
        try broker.listModel.setModel(chatID: chatID, modelName: anthropicModel.name)

        let registrationProvider = BlobTestRegistrationProvider(apiKey: apiKey)
        let registrationSub = broker.subscribe(chatID: chatID, registrationProvider: registrationProvider) { _ in }
        defer { registrationSub.unsubscribe() }

        // Auto-answer the tool with a distinctive marker the model can echo back.
        let toolMarker = "TOOLOUT-ZEPHYR-5107"
        let responder = BlobFakeToolResponder(broker: broker, chatID: chatID,
                                              output: "command output: \(toolMarker)")
        defer { responder.shutdown() }

        func runTurn(_ body: String) throws {
            let ended = expectation(description: "turn ends")
            var done = false
            let sub = broker.subscribe(chatID: chatID, registrationProvider: nil) { update in
                if case .turnLifecycle(let event) = update, event == .ended, !done {
                    done = true; ended.fulfill()
                }
            }
            defer { sub.unsubscribe() }
            var msg = Message(chatID: chatID, author: .user, content: .plainText(body, context: nil),
                              sentDate: Date(), uniqueID: UUID())
            msg.configuration = Message.Configuration(hostedWebSearchEnabled: false, vectorStoreIDs: [],
                                                      model: anthropicModel.name, shouldThink: false)
            try broker.publish(message: msg, toChatID: chatID, partial: false)
            wait(for: [ended], timeout: 120)
        }

        try runTurn("Use the execute_command tool to run a command (any command is fine), then tell me you did it. Reply OK when done.")
        try runTurn("What was in the output of the command you ran earlier? Reply with just the marker string from it.")

        let db = broker.listModel.chatDatabase
        try Self.skipIfTransientVendorError(
            broker.listModel.messages(forChat: chatID, createIfNeeded: false).map { Array($0) } ?? [])

        // Both turns accepted (a rejected turn writes no blob). Turn 2 only succeeds
        // if the tool round replayed from turn 1's blob was accepted by Anthropic.
        XCTAssertEqual(db.blobCount(inChat: chatID), 2,
                       "both rounds captured; turn 2 replaying the tool round from a blob must be accepted")

        // Turn 1's blob is the tool round: it must carry the assistant tool_use block
        // AND the tool_result, together (the pairing the vendor enforces).
        let blobs = db.blobs(inChat: chatID)
        try XCTSkipIf(blobs.isEmpty, "no blobs; earlier assertion already failed")
        let firstRound = String(decoding: blobs[0].payload, as: UTF8.self)
        XCTAssertTrue(firstRound.contains("tool_use"), "the tool round's blob must carry the assistant tool_use block")
        XCTAssertTrue(firstRound.contains("tool_result"), "the tool round's blob must carry the tool_result")

        // The tool round's stored bytes are spliced verbatim into turn 2's request.
        let firstRoundInner = String(decoding: try ChatBlobAssembler.stitchInner([blobs[0]]), as: UTF8.self)
        XCTAssertTrue(wire.requests.dropFirst().contains { $0.contains(firstRoundInner) },
                      "turn 2 must splice the tool round's stored blob bytes verbatim")

        // The model recalled the tool output, so the replayed tool_result reached it.
        let messages: [Message] = broker.listModel.messages(forChat: chatID, createIfNeeded: false)
            .map { Array($0) } ?? []
        let lastAgentText = messages.reversed().first(where: { $0.author == .agent })
            .flatMap { Self.blobText($0.content) } ?? ""
        XCTAssertTrue(lastAgentText.contains(toolMarker),
                      "model must recall the tool output from the blob-replayed tool_result; got: \(lastAgentText)")
    }

    /// Second protocol/vendor: DeepSeek uses the chatCompletions wire shape (a
    /// different splice path than Anthropic, and the strict tool-adjacency vendor
    /// from issue #12883). Proves a real non-Anthropic vendor accepts the frozen
    /// history spliced into its messages array across turns. No cache assertion
    /// (DeepSeek has no prompt-cache pricing).
    func test_chat_blobNativeReplay_multiTurnDeepSeekAccepted() throws {
        guard let apiKey = Self.blobConfigValue("DEEPSEEK_API_KEY"), !apiKey.isEmpty else {
            throw XCTSkip("No DEEPSEEK_API_KEY")
        }
        let deepSeekModel =
            AIMetadata.instance.models.first(where: { $0.vendor == .deepSeek && !$0.features.contains(.configurableThinking) })
            ?? AIMetadata.instance.models.first(where: { $0.vendor == .deepSeek })
        guard let deepSeekModel else { throw XCTSkip("No DeepSeek model in AIMetadata") }
        guard let broker = ChatBroker.instance else { throw XCTSkip("ChatBroker.instance unavailable") }
        Self.blobSuspendProcessors(broker, on: self)

        let wire = BlobWireCapture()
        iTermAIClient.liveObserver = { capture in
            switch capture.request.body {
            case .string(let s): wire.requests.append(s)
            case .bytes(let b): wire.requests.append("<\(b.count) bytes>")
            }
            if let response = capture.response { wire.responses.append(response.data) }
            else if !capture.streamChunks.isEmpty { wire.responses.append(capture.streamChunks.joined()) }
        }
        defer { iTermAIClient.liveObserver = nil }

        let chatID = try broker.create(
            chatWithTitle: "live blob deepseek \(UUID().uuidString.prefix(8))",
            terminalSessionGuid: "blob-ds-test",
            browserSessionGuid: nil,
            permissions: "",
            initialMessages: [])
        addTeardownBlock { try? broker.delete(chatID: chatID) }
        try broker.listModel.setModel(chatID: chatID, modelName: deepSeekModel.name)

        let registrationProvider = BlobTestRegistrationProvider(apiKey: apiKey)
        let registrationSub = broker.subscribe(chatID: chatID, registrationProvider: registrationProvider) { _ in }
        defer { registrationSub.unsubscribe() }

        func runTurn(_ body: String) throws {
            let ended = expectation(description: "turn ends")
            var done = false
            let sub = broker.subscribe(chatID: chatID, registrationProvider: nil) { update in
                if case .turnLifecycle(let event) = update, event == .ended, !done {
                    done = true; ended.fulfill()
                }
            }
            defer { sub.unsubscribe() }
            var msg = Message(chatID: chatID, author: .user, content: .plainText(body, context: nil),
                              sentDate: Date(), uniqueID: UUID())
            msg.configuration = Message.Configuration(hostedWebSearchEnabled: false, vectorStoreIDs: [],
                                                      model: deepSeekModel.name, shouldThink: false)
            try broker.publish(message: msg, toChatID: chatID, partial: false)
            wait(for: [ended], timeout: 120)
        }

        let secret = "OTTER-NIMBUS-3390"
        try runTurn("Remember this secret code exactly: \(secret). Reply with only: OK")
        try runTurn("What is 3 + 4? Reply with only the digit.")
        try runTurn("What was the secret code I gave you earlier? Reply with only the code.")

        let db = broker.listModel.chatDatabase
        try Self.skipIfTransientVendorError(
            broker.listModel.messages(forChat: chatID, createIfNeeded: false).map { Array($0) } ?? [])
        XCTAssertEqual(db.blobCount(inChat: chatID), 3, "one blob per accepted round")

        let messages: [Message] = broker.listModel.messages(forChat: chatID, createIfNeeded: false)
            .map { Array($0) } ?? []
        let lastAgentText = messages.reversed().first(where: { $0.author == .agent })
            .flatMap { Self.blobText($0.content) } ?? ""
        XCTAssertTrue(lastAgentText.contains(secret),
                      "DeepSeek must recall the secret from blob-replayed history; got: \(lastAgentText)")

        let blobs = db.blobs(inChat: chatID)
        try XCTSkipIf(blobs.isEmpty, "no blobs; earlier assertion already failed")
        let firstRoundInner = String(decoding: try ChatBlobAssembler.stitchInner([blobs[0]]), as: UTF8.self)
        XCTAssertTrue(wire.requests.dropFirst().contains { $0.contains(firstRoundInner) },
                      "a later DeepSeek request must splice the first round's stored blob bytes verbatim")
    }

    /// Third splice path: Gemini uses the `contents` array with system carried
    /// separately (afterCount 0), distinct from both Anthropic and chatCompletions.
    /// Proves the verbatim splice is accepted by Gemini across turns.
    func test_chat_blobNativeReplay_multiTurnGeminiAccepted() throws {
        guard let apiKey = Self.blobConfigValue("GEMINI_API_KEY"), !apiKey.isEmpty else {
            throw XCTSkip("No GEMINI_API_KEY")
        }
        guard let geminiModel = AIMetadata.instance.models.first(where: { $0.vendor == .gemini }) else {
            throw XCTSkip("No Gemini model in AIMetadata")
        }
        guard let broker = ChatBroker.instance else { throw XCTSkip("ChatBroker.instance unavailable") }
        Self.blobSuspendProcessors(broker, on: self)

        let wire = BlobWireCapture()
        iTermAIClient.liveObserver = { capture in
            switch capture.request.body {
            case .string(let s): wire.requests.append(s)
            case .bytes(let b): wire.requests.append("<\(b.count) bytes>")
            }
            if let response = capture.response { wire.responses.append(response.data) }
            else if !capture.streamChunks.isEmpty { wire.responses.append(capture.streamChunks.joined()) }
        }
        defer { iTermAIClient.liveObserver = nil }

        let chatID = try broker.create(
            chatWithTitle: "live blob gemini \(UUID().uuidString.prefix(8))",
            terminalSessionGuid: "blob-gm-test",
            browserSessionGuid: nil,
            permissions: "",
            initialMessages: [])
        addTeardownBlock { try? broker.delete(chatID: chatID) }
        try broker.listModel.setModel(chatID: chatID, modelName: geminiModel.name)

        let registrationProvider = BlobTestRegistrationProvider(apiKey: apiKey)
        let registrationSub = broker.subscribe(chatID: chatID, registrationProvider: registrationProvider) { _ in }
        defer { registrationSub.unsubscribe() }

        func runTurn(_ body: String) throws {
            let ended = expectation(description: "turn ends")
            var done = false
            let sub = broker.subscribe(chatID: chatID, registrationProvider: nil) { update in
                if case .turnLifecycle(let event) = update, event == .ended, !done {
                    done = true; ended.fulfill()
                }
            }
            defer { sub.unsubscribe() }
            var msg = Message(chatID: chatID, author: .user, content: .plainText(body, context: nil),
                              sentDate: Date(), uniqueID: UUID())
            msg.configuration = Message.Configuration(hostedWebSearchEnabled: false, vectorStoreIDs: [],
                                                      model: geminiModel.name, shouldThink: false)
            try broker.publish(message: msg, toChatID: chatID, partial: false)
            wait(for: [ended], timeout: 120)
        }

        let secret = "FALCON-COMET-7714"
        try runTurn("Remember this secret code exactly: \(secret). Reply with only: OK")
        try runTurn("What is 5 + 6? Reply with only the number.")
        try runTurn("What was the secret code I gave you earlier? Reply with only the code.")

        let db = broker.listModel.chatDatabase
        try Self.skipIfTransientVendorError(
            broker.listModel.messages(forChat: chatID, createIfNeeded: false).map { Array($0) } ?? [])
        XCTAssertEqual(db.blobCount(inChat: chatID), 3, "one blob per accepted round")

        let messages: [Message] = broker.listModel.messages(forChat: chatID, createIfNeeded: false)
            .map { Array($0) } ?? []
        let lastAgentText = messages.reversed().first(where: { $0.author == .agent })
            .flatMap { Self.blobText($0.content) } ?? ""
        XCTAssertTrue(lastAgentText.contains(secret),
                      "Gemini must recall the secret from blob-replayed history; got: \(lastAgentText)")

        let blobs = db.blobs(inChat: chatID)
        try XCTSkipIf(blobs.isEmpty, "no blobs; earlier assertion already failed")
        let firstRoundInner = String(decoding: try ChatBlobAssembler.stitchInner([blobs[0]]), as: UTF8.self)
        XCTAssertTrue(wire.requests.dropFirst().contains { $0.contains(firstRoundInner) },
                      "a later Gemini request must splice the first round's stored blob bytes verbatim")
    }

    /// Phase 4 (recovery TARGET): the full stateless Responses replay that a
    /// post-expiry retry sends must be accepted by OpenAI and carry the history. A
    /// fresh agent's first turn sets its system message, which nulls
    /// previous_response_id, so this turn IS a full replay of the seeded history with
    /// the id omitted - the exact request the retry re-issues on an unusable id.
    /// Asserts OpenAI accepts it (a blob is captured only on success) and the model
    /// uses the replayed history (recalls the seeded name). This also closes the
    /// last live splice-path gap (Responses `input` array).
    ///
    /// NOTE the auto-retry TRIGGER (classifying an unusable id and re-issuing) is
    /// covered by ChatAgentExpiryTests, not here: the stack never puts a BAD id on
    /// the wire without a real server-side expiry (systemMessageDirty nulls it on
    /// turn 1; turns 2+ use the valid in-memory id; `store` is always on), and adding
    /// a production seam just to force one is not worth it.
    func test_chat_responses_fullStatelessReplayAcceptedWithIdOmitted() throws {
        guard let apiKey = Self.blobConfigValue("OPENAI_API_KEY"), !apiKey.isEmpty else {
            throw XCTSkip("No OPENAI_API_KEY")
        }
        guard let responsesModel = AIMetadata.instance.models.first(where: { $0.api == .responses }) else {
            throw XCTSkip("No Responses-API model in AIMetadata")
        }
        guard let broker = ChatBroker.instance else { throw XCTSkip("ChatBroker.instance unavailable") }
        Self.blobSuspendProcessors(broker, on: self)

        let wire = BlobWireCapture()
        iTermAIClient.liveObserver = { capture in
            switch capture.request.body {
            case .string(let s): wire.requests.append(s)
            case .bytes(let b): wire.requests.append("<\(b.count) bytes>")
            }
            if let response = capture.response { wire.responses.append(response.data) }
            else if !capture.streamChunks.isEmpty { wire.responses.append(capture.streamChunks.joined()) }
        }
        defer { iTermAIClient.liveObserver = nil }

        // Seed a prior exchange the full replay must carry to the model.
        let name = "Zorbax"
        let seedAssistant = Message(chatID: "seed", author: .agent,
                                    content: .markdown("Nice to meet you, \(name)!"),
                                    sentDate: Date(), uniqueID: UUID())
        let seedUser = Message(chatID: "seed", author: .user,
                               content: .markdown("My name is \(name). Please remember it."),
                               sentDate: Date(), uniqueID: UUID())

        let chatID = try broker.create(
            chatWithTitle: "live responses full-replay \(UUID().uuidString.prefix(8))",
            terminalSessionGuid: "blob-resp-test",
            browserSessionGuid: nil,
            permissions: "",
            initialMessages: [seedUser, seedAssistant])
        addTeardownBlock { try? broker.delete(chatID: chatID) }
        try broker.listModel.setModel(chatID: chatID, modelName: responsesModel.name)

        let registrationProvider = BlobTestRegistrationProvider(apiKey: apiKey)
        let registrationSub = broker.subscribe(chatID: chatID, registrationProvider: registrationProvider) { _ in }
        defer { registrationSub.unsubscribe() }

        let ended = expectation(description: "turn ends")
        var done = false
        let sub = broker.subscribe(chatID: chatID, registrationProvider: nil) { update in
            if case .turnLifecycle(let event) = update, event == .ended, !done { done = true; ended.fulfill() }
        }
        defer { sub.unsubscribe() }
        var msg = Message(chatID: chatID, author: .user,
                          content: .plainText("What is my name? Reply with only the name.", context: nil),
                          sentDate: Date(), uniqueID: UUID())
        msg.configuration = Message.Configuration(hostedWebSearchEnabled: false, vectorStoreIDs: [],
                                                  model: responsesModel.name, shouldThink: false)
        try broker.publish(message: msg, toChatID: chatID, partial: false)
        wait(for: [ended], timeout: 120)

        let db = broker.listModel.chatDatabase
        try Self.skipIfTransientVendorError(
            broker.listModel.messages(forChat: chatID, createIfNeeded: false).map { Array($0) } ?? [])

        // A full stateless replay: no previous_response_id on the wire.
        XCTAssertFalse(wire.requests.isEmpty)
        XCTAssertTrue(wire.requests.allSatisfy { !$0.contains("previous_response_id") },
                      "a full stateless replay must omit previous_response_id")

        // OpenAI accepted it (a blob is captured only on a successful turn end).
        XCTAssertGreaterThanOrEqual(db.blobCount(inChat: chatID), 1,
                                    "the full stateless replay must be accepted (a rejected turn writes no blob)")

        // The replayed history reached the model: it recalls the seeded name.
        let messages: [Message] = broker.listModel.messages(forChat: chatID, createIfNeeded: false)
            .map { Array($0) } ?? []
        let lastAgentText = messages.reversed().first(where: { $0.author == .agent })
            .flatMap { Self.blobText($0.content) } ?? ""
        XCTAssertTrue(lastAgentText.contains(name),
                      "model must recall the seeded name from the full replay; got: \(lastAgentText)")
    }

    /// Phase 5 (migration, end-to-end): a legacy chat that predates blobs (seeded
    /// history, blobProtocol nil) migrates on its FIRST turn - capture reconstructs
    /// the whole history via translate() and freezes every round - then is blob-native
    /// on the next turn. Asserts the seeded round is frozen (blobCount covers it), the
    /// next turn splices the migrated seed round's bytes verbatim, and the model
    /// recalls the seeded fact across the migration.
    func test_chat_legacyChatMigratesToBlobsOnFirstTurn() throws {
        guard let apiKey = Self.blobConfigValue("ANTHROPIC_API_KEY"), !apiKey.isEmpty else {
            throw XCTSkip("No ANTHROPIC_API_KEY")
        }
        let anthropicModel =
            AIMetadata.instance.models.first(where: { $0.vendor == .anthropic && !$0.name.lowercased().contains("haiku") })
            ?? AIMetadata.instance.models.first(where: { $0.vendor == .anthropic })
        guard let anthropicModel else { throw XCTSkip("No Anthropic model in AIMetadata") }
        guard let broker = ChatBroker.instance else { throw XCTSkip("ChatBroker.instance unavailable") }
        Self.blobSuspendProcessors(broker, on: self)

        let wire = BlobWireCapture()
        iTermAIClient.liveObserver = { capture in
            switch capture.request.body {
            case .string(let s): wire.requests.append(s)
            case .bytes(let b): wire.requests.append("<\(b.count) bytes>")
            }
            if let response = capture.response { wire.responses.append(response.data) }
            else if !capture.streamChunks.isEmpty { wire.responses.append(capture.streamChunks.joined()) }
        }
        defer { iTermAIClient.liveObserver = nil }

        // A legacy chat: seeded prior exchange, NO blobs. This is the shape a chat
        // reloaded from before the blob feature has.
        let secret = "MARMOT-VECTOR-6021"
        let seedUser = Message(chatID: "seed", author: .user,
                               content: .markdown("Please remember this code exactly: \(secret)."),
                               sentDate: Date(), uniqueID: UUID())
        let seedAssistant = Message(chatID: "seed", author: .agent,
                                    content: .markdown("Got it, I will remember \(secret)."),
                                    sentDate: Date(), uniqueID: UUID())

        let chatID = try broker.create(
            chatWithTitle: "live legacy migration \(UUID().uuidString.prefix(8))",
            terminalSessionGuid: "blob-migrate-test",
            browserSessionGuid: nil,
            permissions: "",
            initialMessages: [seedUser, seedAssistant])
        addTeardownBlock { try? broker.delete(chatID: chatID) }
        try broker.listModel.setModel(chatID: chatID, modelName: anthropicModel.name)

        let db = broker.listModel.chatDatabase
        XCTAssertEqual(db.blobCount(inChat: chatID), 0, "a seeded legacy chat starts with no blobs")

        let registrationProvider = BlobTestRegistrationProvider(apiKey: apiKey)
        let registrationSub = broker.subscribe(chatID: chatID, registrationProvider: registrationProvider) { _ in }
        defer { registrationSub.unsubscribe() }

        func runTurn(_ body: String) throws {
            let ended = expectation(description: "turn ends")
            var done = false
            let sub = broker.subscribe(chatID: chatID, registrationProvider: nil) { update in
                if case .turnLifecycle(let event) = update, event == .ended, !done { done = true; ended.fulfill() }
            }
            defer { sub.unsubscribe() }
            var msg = Message(chatID: chatID, author: .user, content: .plainText(body, context: nil),
                              sentDate: Date(), uniqueID: UUID())
            msg.configuration = Message.Configuration(hostedWebSearchEnabled: false, vectorStoreIDs: [],
                                                      model: anthropicModel.name, shouldThink: false)
            try broker.publish(message: msg, toChatID: chatID, partial: false)
            wait(for: [ended], timeout: 120)
        }

        // Turn 1 migrates: the seeded round + this turn's round are both frozen.
        try runTurn("What is 8 + 9? Reply with only the number.")
        try Self.skipIfTransientVendorError(
            broker.listModel.messages(forChat: chatID, createIfNeeded: false).map { Array($0) } ?? [])
        XCTAssertGreaterThanOrEqual(db.blobCount(inChat: chatID), 2,
                                    "first turn must migrate the seeded round AND freeze this turn's round")

        // The seeded (round-0) blob must carry the secret it migrated.
        let migratedFirstRound = String(decoding: db.blobs(inChat: chatID)[0].payload, as: UTF8.self)
        XCTAssertTrue(migratedFirstRound.contains(secret), "the migrated first round must encode the seeded content")

        // Turn 2 is blob-native: it splices the migrated seed round's bytes verbatim.
        let requestsBeforeTurn2 = wire.requests.count
        try runTurn("What was the code I gave you at the start? Reply with only the code.")
        try Self.skipIfTransientVendorError(
            broker.listModel.messages(forChat: chatID, createIfNeeded: false).map { Array($0) } ?? [])
        let firstRoundInner = String(decoding: try ChatBlobAssembler.stitchInner([db.blobs(inChat: chatID)[0]]), as: UTF8.self)
        XCTAssertTrue(wire.requests[requestsBeforeTurn2...].contains { $0.contains(firstRoundInner) },
                      "turn 2 must splice the MIGRATED first round's blob bytes verbatim (now blob-native)")

        // The model recalls the seeded secret across the migration.
        let messages: [Message] = broker.listModel.messages(forChat: chatID, createIfNeeded: false)
            .map { Array($0) } ?? []
        let lastAgentText = messages.reversed().first(where: { $0.author == .agent })
            .flatMap { Self.blobText($0.content) } ?? ""
        XCTAssertTrue(lastAgentText.contains(secret),
                      "model must recall the seeded secret after migration; got: \(lastAgentText)")
    }

    // MARK: - Helpers (file-local; the queue test's private helpers are not visible here)

    private static func blobConfigValue(_ key: String) -> String? {
        let configPath = AILiveHarness.configFilePath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            return nil
        }
        return json[key]
    }

    /// These tests play no broker-side tool runner, but a paired-companion machine
    /// has ChatClient's processor installed at launch; suspend all processors so it
    /// can't wrap this fixture's traffic. Restored on teardown.
    private static func blobSuspendProcessors(_ broker: ChatBroker, on test: XCTestCase) {
        let saved = broker.processors
        broker.processors = []
        test.addTeardownBlock { @MainActor in
            broker.processors = saved
        }
    }

    /// Skip (don't fail) when a turn hit a TRANSIENT vendor error (capacity/rate
    /// limit), since these tests drive ChatAgent, which has no 503 retry. Only the
    /// transient set is matched, so a real splice rejection (an HTTP 400 like broken
    /// tool adjacency) still FAILS rather than being masked. `messages` are the
    /// chat's committed messages (ChatAgent commits vendor errors as an agent reply).
    private static func skipIfTransientVendorError(_ messages: [Message]) throws {
        let transient = ["status 503", "status 502", "status 500", "status 429",
                         "high demand", "overloaded", "experiencing", "try again later",
                         "RESOURCE_EXHAUSTED", "UNAVAILABLE"]
        for message in messages where message.author == .agent {
            guard let text = blobText(message.content) else { continue }
            if let hit = transient.first(where: { text.contains($0) }) {
                throw XCTSkip("transient vendor error during live run (\(hit)): \(text.prefix(160))")
            }
        }
    }

    private static func blobText(_ content: Message.Content) -> String? {
        switch content {
        case .plainText(let s, _): return s
        case .markdown(let s): return s
        default: return nil
        }
    }

    /// Extract the integer value of a `"field":N` usage entry from an Anthropic
    /// response body (streaming SSE or single JSON). Returns 0 if absent.
    private static func blobUsageInt(_ body: String, _ field: String) -> Int {
        guard let r = body.range(of: "\"\(field)\":") else { return 0 }
        let after = body[r.upperBound...].prefix(24).drop(while: { $0 == " " })
        let digits = after.prefix(while: { $0.isNumber })
        return Int(digits) ?? 0
    }
}

private final class BlobTestRegistrationProvider: AIRegistrationProvider {
    let apiKey: String
    init(apiKey: String) { self.apiKey = apiKey }
    func registrationProviderRequestRegistration(_ completion: @escaping (AITermController.Registration?) -> ()) {
        completion(AITermController.Registration(apiKey: apiKey))
    }
}

/// Reference-type sink for the liveObserver closure to accumulate wire bodies.
private final class BlobWireCapture {
    var requests: [String] = []
    var responses: [String] = []
}

/// Broker-side tool runner: answers each execute_command request with a fixed
/// output, round-tripping the function-call id so the reconstructed tool_result
/// is well-formed. One response per request (a replayed round can re-invoke).
@MainActor
private final class BlobFakeToolResponder {
    private let broker: ChatBroker
    private let chatID: String
    private let output: String
    private var subscription: ChatBroker.Subscription?
    private var respondedRequestIDs = Set<UUID>()

    init(broker: ChatBroker, chatID: String, output: String) {
        self.broker = broker
        self.chatID = chatID
        self.output = output
        subscription = broker.subscribe(chatID: chatID, registrationProvider: nil) { [weak self] update in
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
        let response = Message(
            chatID: chatID,
            author: .user,
            content: .remoteCommandResponse(.success(output),
                                            message.uniqueID,
                                            cmd.content.functionName,
                                            cmd.llmMessage.functionCallID),
            sentDate: Date(),
            uniqueID: UUID())
        try? broker.publish(message: response, toChatID: chatID, partial: false)
    }
}
