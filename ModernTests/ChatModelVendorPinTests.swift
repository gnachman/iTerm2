//
//  ChatModelVendorPinTests.swift
//  iTerm2 ModernTests
//
//  A chat's model pin carries its vendor (Chat.modelVendor). A chat pinned to an
//  Ollama tag that later disappears from Ollama's list must never be routed to a
//  cloud vendor; cloud-pinned chats keep their behavior. QA finding F-380.
//

import XCTest
@testable import iTerm2SharedARC

final class ChatModelVendorPinTests: XCTestCase {
    private let endpoint = LLMMetadata.defaultOllamaEndpoint
    private var savedRecommended: Any?
    private var savedVendor: Any?
    private var savedRegularModel: Any?
    private var savedManualModels: Any?
    private var savedFetcher: ((String, [[String: String]], TimeInterval, @escaping ([AIMetadata.Model]?) -> Void) -> Void)?
    private var savedRetryScheduler: ((TimeInterval, @escaping () -> Void) -> Void)?
    private var restoreCacheEntry: (() -> Void)?

    override func setUp() {
        super.setUp()
        savedRecommended = iTermPreferences.object(forKey: kPreferenceKeyUseRecommendedAIModel)
        savedVendor = iTermPreferences.object(forKey: kPreferenceKeyAIVendor)
        savedRegularModel = iTermPreferences.object(forKey: kPreferenceKeyAIOllamaRegularModel)
        savedManualModels = iTermPreferences.object(forKey: kPreferenceKeyAIManualModelConfigurations)
        iTermPreferences.setObject(nil, forKey: kPreferenceKeyAIManualModelConfigurations)
        // The reported configuration: the global default is a cloud vendor.
        iTermPreferences.setBool(true, forKey: kPreferenceKeyUseRecommendedAIModel)
        iTermPreferences.setObject(Int(iTermAIVendor.openAI.rawValue), forKey: kPreferenceKeyAIVendor)
        iTermPreferences.setObject(nil, forKey: kPreferenceKeyAIOllamaRegularModel)
        let cache = OllamaModelCache.shared
        savedFetcher = cache.fetcher
        savedRetryScheduler = cache.retryScheduler
        cache.fetcher = { _, _, _, _ in }
        cache.retryScheduler = { _, _ in }
        restoreCacheEntry = cache.replaceModelsForTesting([], endpoint: endpoint)
    }

    override func tearDown() {
        let cache = OllamaModelCache.shared
        restoreCacheEntry?()
        if let savedFetcher {
            cache.fetcher = savedFetcher
        }
        if let savedRetryScheduler {
            cache.retryScheduler = savedRetryScheduler
        }
        iTermPreferences.setObject(savedRecommended, forKey: kPreferenceKeyUseRecommendedAIModel)
        iTermPreferences.setObject(savedVendor, forKey: kPreferenceKeyAIVendor)
        iTermPreferences.setObject(savedRegularModel, forKey: kPreferenceKeyAIOllamaRegularModel)
        iTermPreferences.setObject(savedManualModels, forKey: kPreferenceKeyAIManualModelConfigurations)
        super.tearDown()
    }

    // Makes Ollama list exactly `tags`. tearDown's restore puts back the entry
    // saved in setUp.
    private func installOllamaTags(_ tags: [String]) {
        let entries = tags.map { "{\"name\":\"\($0)\",\"capabilities\":[\"tools\"],\"details\":{\"context_length\":32768}}" }
        let body = Data("{\"models\":[\(entries.joined(separator: ","))]}".utf8)
        _ = OllamaModelCache.shared.replaceModelsForTesting(
            OllamaModelDiscovery.models(fromTagsResponse: body, endpoint: endpoint),
            endpoint: endpoint)
    }

    private func makeTempDB() throws -> (ChatDatabase, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("chatpintest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("chatdb.sqlite")
        return (try XCTUnwrap(ChatDatabase(url: url)), url)
    }

    // The raw modelVendor column for a chat, read straight from sqlite.
    private func storedVendorColumn(_ db: ChatDatabase, chatID: String) throws -> String? {
        let rs = try XCTUnwrap(try db.db.executeQuery("select modelVendor from Chat where uuid = ?",
                                                      withArguments: [chatID]))
        defer { rs.close() }
        XCTAssertTrue(rs.next(), "chat \(chatID) is stored")
        return rs.string(forColumn: "modelVendor")
    }

    // Opens the database again the way a relaunch would.
    private func reopen(_ db: ChatDatabase, url: URL) throws -> ChatDatabase {
        db.db.close()
        db.db.unlock()
        return try XCTUnwrap(ChatDatabase(url: url))
    }

    private func makeChat(id: String, modelName: String?, modelVendor: Int? = nil) -> Chat {
        var chat = Chat(title: "t", permissions: "")
        chat.id = id
        chat.modelName = modelName
        chat.modelVendor = modelVendor
        return chat
    }

    private var cloudName: String { AIMetadata.recommendedOpenAIModel.name }

    private func installManualModel(name: String, url: String, api: iTermAIAPI) {
        iTermPreferences.setObject([["id": UUID().uuidString,
                                     "name": name,
                                     "url": url,
                                     "api": Int(api.rawValue)]],
                                   forKey: kPreferenceKeyAIManualModelConfigurations)
    }

    // MARK: - Routing (AIConversation)

    // The reported bug: a chat pinned to the discovered tag qwen-fake:1b, whose tag
    // then disappears. The pin's name contains no "llama", so without the vendor
    // it resolved to nothing and the turn went to the global default (OpenAI).
    @MainActor
    func test_removedOllamaTag_neverRoutesToCloud() {
        installOllamaTags(["qwen-fake:1b"])
        XCTAssertEqual(LLMMetadata.inferredVendor(forPinnedModelNamed: "qwen-fake:1b"), .llama,
                       "the vendor stamped when the chat is pinned")
        installOllamaTags(["other-fake:2b"])

        switch AIConversation.pinnedProviderOverride(modelName: "qwen-fake:1b", vendor: .llama) {
        case .success(let provider):
            XCTFail("a gone Ollama model must not be sent; got \(String(describing: provider?.model.name)) (nil means the cloud default)")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("qwen-fake:1b"), error.message)
        }
        XCTAssertNil(ChatAgent.resolvedModel(named: "qwen-fake:1b", vendor: .llama))
    }

    // The same when Ollama lists nothing at all.
    func test_removedOllamaTag_emptyServer_neverRoutesToCloud() {
        guard case .failure = AIConversation.pinnedProviderOverride(modelName: "gemma-fake:3b", vendor: .llama) else {
            XCTFail("a gone Ollama model must not be sent")
            return
        }
    }

    // A deepseek-named Ollama tag must not go to DeepSeek's cloud API.
    func test_removedDeepSeekNamedOllamaTag_neverRoutesToDeepSeek() {
        guard case .failure = AIConversation.pinnedProviderOverride(modelName: "deepseek-r1:7b", vendor: .llama) else {
            XCTFail("a gone Ollama model named like a cloud model must not be sent to that cloud")
            return
        }
    }

    // A tag that is still listed resolves to the local server.
    func test_presentOllamaTag_routesLocally() {
        installOllamaTags(["qwen-fake:1b"])
        guard case .success(let provider) = AIConversation.pinnedProviderOverride(modelName: "qwen-fake:1b", vendor: .llama) else {
            XCTFail("a listed tag must resolve")
            return
        }
        XCTAssertEqual(provider?.model.vendor, .llama)
        XCTAssertEqual(provider?.model.url, endpoint)
    }

    // A cloud-pinned chat is unchanged.
    func test_cloudPin_unchanged() {
        guard case .success(let provider) = AIConversation.pinnedProviderOverride(modelName: cloudName, vendor: .openAI) else {
            XCTFail("a catalog model must resolve")
            return
        }
        XCTAssertEqual(provider?.model.name, cloudName)
        XCTAssertEqual(provider?.model.vendor, .openAI)
    }

    // A model retired from the catalog stays on its own vendor (as the chat UI
    // already did), never the global default's vendor.
    func test_retiredCloudPin_staysOnItsVendor() {
        guard case .success(let provider) = AIConversation.pinnedProviderOverride(modelName: "retired-model-f380", vendor: .anthropic) else {
            XCTFail("a retired cloud model falls back within its vendor")
            return
        }
        XCTAssertEqual(provider?.model.vendor, .anthropic)
    }

    // A manual model on a local server whose API the user changes (which changes
    // its vendor) keeps going to the user's server, not the old vendor's cloud.
    func test_manualModelVendorChange_honorsUsersServer() {
        let url = "http://localhost:1234/v1/chat/completions"
        installManualModel(name: "my-local-f380", url: url, api: .chatCompletions)
        // Its host-guessed vendor (OpenAI) is not stamped: if the manual model were
        // removed, a stamped .openAI would send the chat to OpenAI's cloud.
        XCTAssertEqual(LLMMetadata.model(named: "my-local-f380")?.vendor, .openAI, "precondition")
        let pinnedVendor = LLMMetadata.inferredVendor(forPinnedModelNamed: "my-local-f380")
        XCTAssertNil(pinnedVendor)
        installManualModel(name: "my-local-f380", url: url, api: .llama)
        XCTAssertEqual(LLMMetadata.model(named: "my-local-f380")?.vendor, .llama,
                       "precondition: the edit changed the model's vendor")

        guard case .success(let provider) = AIConversation.pinnedProviderOverride(modelName: "my-local-f380", vendor: pinnedVendor) else {
            XCTFail("the edited manual model must resolve")
            return
        }
        XCTAssertEqual(provider?.model.name, "my-local-f380")
        XCTAssertEqual(provider?.model.url, url)
        // Re-pinning the same name picks up the new vendor.
        XCTAssertEqual(ChatListModel.vendorForNewPin(modelName: "my-local-f380",
                                                     previousName: "my-local-f380",
                                                     previousVendor: pinnedVendor.map { Int($0.rawValue) }),
                       Int(iTermAIVendor.llama.rawValue))
        // An edit made while stamped with a cloud vendor is honored too.
        guard case .success(let stamped) = AIConversation.pinnedProviderOverride(modelName: "my-local-f380", vendor: .openAI) else {
            XCTFail("the edited manual model must resolve")
            return
        }
        XCTAssertEqual(stamped?.model.url, url)
    }

    // Switching a chat from an Ollama or cloud pin to a manual model on a local
    // OpenAI-compatible server leaves the vendor unstamped rather than inheriting
    // the previous pin's: .llama would fail every turn, and .openAI would send the
    // chat to OpenAI's cloud if the manual model were later removed.
    @MainActor
    func test_setModel_toUnstampedManualModel_clearsVendor() throws {
        installOllamaTags(["qwen-fake:1b"])
        let url = "http://localhost:1234/v1/chat/completions"
        installManualModel(name: "my-local-f380", url: url, api: .chatCompletions)
        let (db, _) = try makeTempDB()
        let listModel = try XCTUnwrap(ChatListModel(database: db))
        for (id, first) in [("fromOllama", "qwen-fake:1b"), ("fromCloud", cloudName)] {
            try listModel.add(chat: makeChat(id: id, modelName: nil))
            try listModel.setModel(chatID: id, modelName: first)
            XCTAssertNotNil(listModel.modelVendor(forChatID: id), "precondition")
            try listModel.setModel(chatID: id, modelName: "my-local-f380")
            XCTAssertNil(listModel.modelVendor(forChatID: id), id)
            guard case .success(let provider) = AIConversation.pinnedProviderOverride(
                modelName: "my-local-f380", vendor: listModel.modelVendor(forChatID: id)) else {
                XCTFail("the manual model must resolve")
                continue
            }
            XCTAssertEqual(provider?.model.url, url)
        }
    }

    // A same-named manual model of another vendor doesn't shadow an Ollama tag
    // that is still installed.
    func test_presentOllamaTag_notShadowedBySameNamedCloudModel() {
        installOllamaTags(["qwen-fake:1b"])
        installManualModel(name: "qwen-fake:1b", url: "https://api.openai.com/v1/chat/completions",
                           api: .chatCompletions)
        guard case .success(let provider) = AIConversation.pinnedProviderOverride(modelName: "qwen-fake:1b", vendor: .llama) else {
            XCTFail("the installed tag must resolve")
            return
        }
        XCTAssertEqual(provider?.model.vendor, .llama)
        XCTAssertEqual(provider?.model.url, endpoint)
    }

    // A chat on a local model whose tag is gone must not resolve to a same-named
    // model of another vendor that appears later.
    func test_goneOllamaTag_doesNotResolveToSameNamedCloudModel() {
        installManualModel(name: "qwen-fake:1b", url: "https://api.openai.com/v1/chat/completions",
                           api: .chatCompletions)
        XCTAssertEqual(LLMMetadata.model(named: "qwen-fake:1b")?.vendor, .openAI, "precondition")
        guard case .failure = AIConversation.pinnedProviderOverride(modelName: "qwen-fake:1b", vendor: .llama) else {
            XCTFail("a local pin must not resolve to a cloud model of the same name")
            return
        }
        XCTAssertEqual(ChatListModel.vendorForNewPin(modelName: "qwen-fake:1b",
                                                     previousName: "qwen-fake:1b",
                                                     previousVendor: Int(iTermAIVendor.llama.rawValue)),
                       Int(iTermAIVendor.llama.rawValue))
    }

    // Legacy pins with no known vendor keep their old behavior.
    func test_legacyPinWithoutVendor_unchanged() {
        guard case .success(nil) = AIConversation.pinnedProviderOverride(modelName: "some-retired-model", vendor: nil) else {
            XCTFail("an unclassifiable legacy pin keeps falling back to the global default")
            return
        }
    }

    // MARK: - Inference

    func test_inferredVendor() {
        installOllamaTags(["qwen-fake:1b"])
        XCTAssertEqual(LLMMetadata.inferredVendor(forPinnedModelNamed: cloudName), .openAI)
        XCTAssertEqual(LLMMetadata.inferredVendor(forPinnedModelNamed: "qwen-fake:1b"), .llama)
        XCTAssertEqual(LLMMetadata.inferredVendor(forPinnedModelNamed: "llama-gone:1b"), .llama)
        XCTAssertEqual(LLMMetadata.inferredVendor(forPinnedModelNamed: LLMMetadata.pendingOllamaModelName), .llama)
        XCTAssertEqual(LLMMetadata.inferredVendor(forPinnedModelNamed: "gone-fake:2b"), .llama,
                       "an unresolved name:tag is an Ollama tag")
        XCTAssertEqual(LLMMetadata.inferredVendor(forPinnedModelNamed: "deepseek-r1:7b"), .llama,
                       "an unresolved deepseek-named tag is Ollama's, not DeepSeek's")
        XCTAssertNil(LLMMetadata.inferredVendor(forPinnedModelNamed: "some-retired-model"))
        XCTAssertNil(LLMMetadata.inferredVendor(forPinnedModelNamed: nil))
    }

    // MARK: - Provider binding

    // A turn naming a cloud model in a chat bound to a gone Ollama tag must be
    // rejected. Without the stored vendor the bound name's vendor was unknown and
    // the binding let any turn through.
    func test_binding_goneOllamaPin_rejectsCloudTurn() {
        installOllamaTags(["other-fake:2b"])
        let verdict = ChatProviderBinding.evaluate(
            boundModelName: "qwen-fake:1b",
            turnModelName: cloudName,
            defaultModelName: cloudName,
            vendor: ChatProviderBinding.vendorResolver(boundModelName: "qwen-fake:1b", boundVendor: .llama))
        guard case .reject = verdict else {
            XCTFail("expected reject, got \(verdict)")
            return
        }
        // Switching to another local model is still allowed.
        let local = ChatProviderBinding.evaluate(
            boundModelName: "qwen-fake:1b",
            turnModelName: "other-fake:2b",
            defaultModelName: cloudName,
            vendor: ChatProviderBinding.vendorResolver(boundModelName: "qwen-fake:1b", boundVendor: .llama))
        XCTAssertEqual(local, .proceed(modelName: "other-fake:2b", bindChatTo: nil))
    }

    // MARK: - Chat UI fallback

    @MainActor
    func test_uiFallback_goneOllamaPin_staysOnOllama() {
        installOllamaTags(["other-fake:2b"])
        let model = ChatViewController.fallbackModel(forUnresolvedPinNamed: "qwen-fake:1b", vendor: .llama)
        XCTAssertEqual(model?.name, "qwen-fake:1b", "the chat keeps its own model rather than a different local one")
        XCTAssertEqual(model?.vendor, .llama)
        XCTAssertEqual(model?.url, endpoint)
    }

    @MainActor
    func test_uiFallback_cloudAndLegacy_unchanged() {
        XCTAssertEqual(ChatViewController.fallbackModel(forUnresolvedPinNamed: "retired-model-f380", vendor: .anthropic)?.vendor,
                       .anthropic)
        XCTAssertEqual(ChatViewController.fallbackModel(forUnresolvedPinNamed: "gpt-retired", vendor: nil)?.vendor,
                       .openAI)
        XCTAssertEqual(ChatViewController.fallbackModel(forUnresolvedPinNamed: "claude-retired", vendor: nil)?.vendor,
                       .anthropic)
    }

    // MARK: - Renaming and icon

    @MainActor
    func test_renamingAndIcon_carryVendor() {
        let messages = [AITermController.Message(role: .user, content: "private question")]
        XCTAssertEqual(ChatAgent.renamingConversation(messages: messages, modelName: "qwen-fake:1b",
                                                      modelVendor: .llama).modelVendor, .llama)
        XCTAssertEqual(ChatIconGenerator.svgConversation(prompt: "draw", modelName: "qwen-fake:1b",
                                                         modelVendor: .llama).modelVendor, .llama)
    }

    // MARK: - Persistence and migration

    @MainActor
    func test_setModel_stampsVendor_andPersists() throws {
        installOllamaTags(["qwen-fake:1b"])
        let (db, _) = try makeTempDB()
        let listModel = try XCTUnwrap(ChatListModel(database: db))
        try listModel.add(chat: makeChat(id: "A", modelName: nil))
        try listModel.setModel(chatID: "A", modelName: "qwen-fake:1b")
        XCTAssertEqual(listModel.modelVendor(forChatID: "A"), .llama)

        XCTAssertEqual(try storedVendorColumn(db, chatID: "A"), String(iTermAIVendor.llama.rawValue))

        // The tag disappears; re-setting the same name keeps the vendor.
        installOllamaTags([])
        try listModel.setModel(chatID: "A", modelName: "qwen-fake:1b")
        XCTAssertEqual(listModel.modelVendor(forChatID: "A"), .llama)

        // Switching to a cloud model restamps.
        try listModel.setModel(chatID: "A", modelName: cloudName)
        XCTAssertEqual(listModel.modelVendor(forChatID: "A"), .openAI)
    }

    func test_vendorForNewPin_unknownNameKeepsPreviousVendor() {
        XCTAssertEqual(ChatListModel.vendorForNewPin(modelName: "some-unknown",
                                                     previousName: "qwen-fake:1b",
                                                     previousVendor: Int(iTermAIVendor.llama.rawValue)),
                       Int(iTermAIVendor.llama.rawValue))
        XCTAssertNil(ChatListModel.vendorForNewPin(modelName: nil, previousName: "x", previousVendor: 3))
    }

    // Chats pinned before the vendor was stored get it backfilled when the list
    // model loads, wherever the name still identifies the vendor.
    @MainActor
    func test_backfill_existingChats() throws {
        installOllamaTags(["qwen-fake:1b"])
        let (db, url) = try makeTempDB()
        do {
            let listModel = try XCTUnwrap(ChatListModel(database: db))
            // Rows written by a version that predates modelVendor.
            try listModel.add(chat: makeChat(id: "ollama", modelName: "qwen-fake:1b"))
            try listModel.add(chat: makeChat(id: "cloud", modelName: cloudName))
            try listModel.add(chat: makeChat(id: "llamaName", modelName: "llama-gone:1b"))
            try listModel.add(chat: makeChat(id: "goneTag", modelName: "qwen-gone:4b"))
            try listModel.add(chat: makeChat(id: "unknown", modelName: "some-retired-model"))
            try listModel.add(chat: makeChat(id: "none", modelName: nil))
            try listModel.add(chat: makeChat(id: "stamped", modelName: cloudName,
                                             modelVendor: Int(iTermAIVendor.openAI.rawValue)))
            // An older build changed these chats' models without touching the vendor.
            try listModel.add(chat: makeChat(id: "staleCloud", modelName: "qwen-fake:1b",
                                             modelVendor: Int(iTermAIVendor.openAI.rawValue)))
            try listModel.add(chat: makeChat(id: "staleLlama", modelName: cloudName,
                                             modelVendor: Int(iTermAIVendor.llama.rawValue)))
        }
        let reopened = try reopen(db, url: url)
        let listModel = try XCTUnwrap(ChatListModel(database: reopened))
        XCTAssertEqual(listModel.modelVendor(forChatID: "ollama"), .llama)
        XCTAssertEqual(listModel.modelVendor(forChatID: "cloud"), .openAI)
        XCTAssertEqual(listModel.modelVendor(forChatID: "llamaName"), .llama)
        XCTAssertEqual(listModel.modelVendor(forChatID: "goneTag"), .llama,
                       "a legacy chat whose tag was already removed")
        XCTAssertNil(listModel.modelVendor(forChatID: "unknown"))
        XCTAssertNil(listModel.modelVendor(forChatID: "none"))
        XCTAssertEqual(listModel.modelVendor(forChatID: "stamped"), .openAI)
        XCTAssertEqual(listModel.modelVendor(forChatID: "staleCloud"), .llama, "a stale cloud vendor is corrected")
        XCTAssertEqual(listModel.modelVendor(forChatID: "staleLlama"), .llama, "a stored Ollama vendor never moves to a cloud vendor")
        XCTAssertEqual(listModel.modelName(forChatID: "cloud"), cloudName, "the pin itself is unchanged")

        // And the backfill was persisted, and survives a relaunch.
        XCTAssertEqual(try storedVendorColumn(reopened, chatID: "ollama"), String(iTermAIVendor.llama.rawValue))
        XCTAssertNil(try storedVendorColumn(reopened, chatID: "unknown"))
        let relaunched = try reopen(reopened, url: url)
        let chat = try XCTUnwrap(relaunched.chats?.first { $0.id == "ollama" })
        XCTAssertEqual(chat.modelVendor, Int(iTermAIVendor.llama.rawValue))
        XCTAssertEqual(chat.modelName, "qwen-fake:1b")
    }
}
