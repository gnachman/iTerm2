//
//  OrchestratorClient.swift
//  iTerm2SharedARC
//

import Foundation

// Client-side counterpart to the agent's orchestration tool surface.
// Subscribes to the chat broker; when an agent publishes an
// orchestration tool call as .remoteCommandRequest(.external(...)),
// runs the actual side effects through OrchestratorDispatcher and
// publishes the .remoteCommandResponse that resumes the parked LLM
// completion in ChatAgent.handleRemoteCommandResponse.
//
// This is the architectural mirror of ChatClient for AITerm's
// session-bound RemoteCommand path: the broker is the single
// transport for both directions, and the agent (server side) never
// reaches into PTYSession, iTermController, the workgroup model, or
// any other app state directly. All of that lives in
// OrchestratorDispatcher, which is owned here on the client side.
//
// Dispatcher lifetime is per-chat: created lazily on the first
// orchestration tool request for a chat, torn down on chat deletion
// or when the chat is toggled out of orchestration mode (via
// dropDispatcher(forChatID:)).
//
// @MainActor: the broker is @MainActor and the dispatcher is
// @MainActor; pinning the client to main makes the contract a
// compile-time check.
@MainActor
final class OrchestratorClient {
    private static var _instance: OrchestratorClient?
    static var instance: OrchestratorClient? {
        if _instance == nil, let broker = ChatBroker.instance {
            _instance = OrchestratorClient(broker: broker)
        }
        return _instance
    }

    private let broker: ChatBroker
    private var subscription: ChatBroker.Subscription?
    private var dispatchers: [String: OrchestratorDispatcher] = [:]

    private init(broker: ChatBroker) {
        self.broker = broker
        self.subscription = broker.subscribe(
            chatID: nil,
            registrationProvider: nil
        ) { [weak self] update in
            // Broker callbacks can fire from arbitrary contexts (the
            // broker is @MainActor today and the publish-time fan-out
            // is synchronous, but the subscription closure is
            // declared non-isolated). Hop to main before touching
            // dispatcher state.
            Task { @MainActor in
                self?.handle(update: update)
            }
        }
        // Drop the per-chat dispatcher when the chat row is deleted.
        // Mirrors ChatService's chatWasDeleted observer; without
        // this, the dispatcher's NotificationCenter observers and
        // broker subscription leak for the rest of the process
        // lifetime since this client holds the only strong reference.
        NotificationCenter.default.addObserver(
            forName: ChatListModel.chatWasDeleted,
            object: nil,
            queue: nil) { [weak self] notification in
                // Post site is @MainActor (ChatListModel.delete),
                // delivery is synchronous on the posting thread.
                MainActor.assumeIsolated {
                    guard let chatID = notification.userInfo?[ChatListModel.chatIDUserInfoKey] as? String else {
                        return
                    }
                    self?.dropDispatcher(forChatID: chatID)
                }
            }
    }

    deinit {
        subscription?.unsubscribe()
        NotificationCenter.default.removeObserver(self)
    }

    // Called from ChatViewController.setOrchestrationEnabled(false)
    // when the user toggles a chat out of orchestration mode.
    // Mirrors ChatService.dropAgent so the dispatcher's per-chat
    // watcher state and broker subscription are released along with
    // the agent's tool-call surface.
    func dropDispatcher(forChatID chatID: String) {
        // Synchronously detach broker/observer state before dropping
        // the dict entry. An in-flight handleToolCall Task can still
        // hold a strong ref past the dict removal; without tearDown
        // that orphan would keep delivering tab-status notifications,
        // resume parked permission prompts as if they were live, and
        // publish a posthumous tool_result into a chat that's no
        // longer in orchestration mode.
        if let existing = dispatchers.removeValue(forKey: chatID) {
            existing.tearDown()
        }
    }

    // MARK: - Broker handler

    private func handle(update: ChatBroker.Update) {
        guard case let .delivery(message, chatID, _) = update else { return }
        guard message.author == .agent else { return }
        guard case let .remoteCommandRequest(payload, _) = message.content else { return }
        guard case let .external(ext) = payload else { return }
        let requestID = message.uniqueID
        Task { @MainActor [weak self] in
            await self?.dispatch(external: ext,
                                 requestID: requestID,
                                 chatID: chatID)
        }
    }

    // Runs the dispatcher for one external tool call and publishes
    // the response. The completion that the agent parked in
    // pendingRemoteCommands[requestID] is resumed when the broker
    // delivers the response back through
    // ChatService → ChatAgent.fetchCompletion →
    // handleRemoteCommandResponse.
    private func dispatch(external ext: ExternalRemoteCommand,
                          requestID: UUID,
                          chatID: String) async {
        let dispatcher = self.dispatcher(forChatID: chatID)
        let argsData = Data(ext.argsJSON.utf8)
        let resultData = await dispatcher.handleToolCall(
            name: ext.name,
            jsonArgs: argsData,
            llmMessage: ext.llmMessage)
        let resultString = String(decoding: resultData, as: UTF8.self)
        let functionCallID = ext.llmMessage.functionCallID
        do {
            try broker.publish(
                message: Message(
                    chatID: chatID,
                    author: .user,
                    content: .remoteCommandResponse(
                        .success(resultString),
                        requestID,
                        ext.name,
                        functionCallID),
                    sentDate: Date(),
                    uniqueID: UUID()),
                toChatID: chatID,
                partial: false)
        } catch {
            DLog("OrchestratorClient: failed to publish tool response: \(error)")
        }
    }

    private func dispatcher(forChatID chatID: String) -> OrchestratorDispatcher {
        if let existing = dispatchers[chatID] {
            return existing
        }
        let created = OrchestratorDispatcher(chatID: chatID, broker: broker)
        dispatchers[chatID] = created
        return created
    }
}
