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
