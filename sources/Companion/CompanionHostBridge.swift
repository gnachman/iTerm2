//
//  CompanionHostBridge.swift
//  iTerm2
//
//  The server end of the companion protocol. Given an established (Noise-
//  encrypted) transport, it decodes client requests and drives iTerm2's chat
//  system: listing chats and sessions, creating and deleting chats, publishing
//  user messages, and streaming chat updates back to the phone. It is the
//  mac-side mirror of the phone's CompanionSession.
//
//  The wire carries the real model types (Chat, Message); the only filtering
//  is hiddenFromClient, mirroring what the Mac's own chat UI renders.
//
//  Everything here runs on the main actor because ChatClient, ChatBroker, and
//  iTermController all require it. All outbound traffic is enqueued
//  synchronously (in main-actor order) onto a single outbox stream drained by
//  one task, so frames reach the transport in exactly the order they were
//  produced: replies never interleave with each other, and streamed .append
//  deltas cannot arrive scrambled.
//

import Foundation
import CompanionProtocol
import CompanionNoise

@MainActor
final class CompanionHostBridge {
    private let transport: MessageTransport
    private var receiveTask: Task<Void, Never>?
    private var subscriptions: [String: ChatBroker.Subscription] = [:]
    private var outbox: AsyncStream<HostEnvelope>.Continuation?
    private var outboxTask: Task<Void, Never>?

    /// Host-initiated requests to the phone (today: the notification
    /// permission prompt), keyed by a host-side request id and resolved when
    /// the phone's response arrives. nil = the bridge died first.
    private var permissionWaiters: [UInt64: CheckedContinuation<CompanionPushAuthorization?, Never>] = [:]

    /// Chat-list change observers driving unsolicited .chatListChanged pushes.
    private var chatListObservers: [any NSObjectProtocol] = []
    private var chatListPushTask: Task<Void, Never>?
    private var nextHostRequestID: UInt64 = 1

    /// Called once the transport closes remotely, so the owner can drop this
    /// bridge. A user-initiated stop() does not fire it.
    var onClose: (@MainActor () -> Void)?

    /// Called when the phone announces it is unpairing.
    var onPeerUnpaired: (@MainActor () -> Void)?

    init(transport: MessageTransport) {
        self.transport = transport
    }

    func start() {
        ChatBroker.instance?.ensureServiceRunning()

        var continuation: AsyncStream<HostEnvelope>.Continuation!
        let stream = AsyncStream<HostEnvelope> { continuation = $0 }
        outbox = continuation
        outboxTask = Task { [transport] in
            for await envelope in stream {
                let data: Data
                do {
                    data = try WireCoding.encode(envelope)
                } catch {
                    DLog("Companion bridge: DROPPING unencodable envelope: \(error)")
                    continue
                }
                do {
                    try await transport.send(data)
                } catch {
                    DLog("Companion bridge: outbox send failed; outbox is dead: \(error)")
                    break
                }
            }
            DLog("Companion bridge: outbox drained")
        }

        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop()
        }

        // Keep the phone's chat list fresh: any list-level change (rename,
        // icon generated, create/delete/reorder) pushes a debounced snapshot.
        // metadataDidChange fires for all of those; chatWasDeleted is the
        // one removal signal that doesn't also post metadata.
        let center = NotificationCenter.default
        for name in [ChatListModel.metadataDidChange, ChatListModel.chatWasDeleted] {
            chatListObservers.append(center.addObserver(forName: name,
                                                        object: nil,
                                                        queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleChatListPush()
                }
            })
        }
    }

    /// Coalesce bursts (a rename immediately invalidates the icon, which
    /// regenerates moments later) into one snapshot after a quiet moment.
    private func scheduleChatListPush() {
        chatListPushTask?.cancel()
        chatListPushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.chatListPushTask = nil
            self.send(.chatListChanged(chats: self.chatEntries()), requestID: nil)
        }
    }

    /// Tell the phone it has been unpaired, flush the outbox so the message
    /// actually reaches the wire, then tear down. Used by unpair; a plain
    /// stop() would race the farewell against the connection close.
    func announceUnpairedAndStop() async {
        DLog("Companion bridge: announcing unpair")
        onClose = nil
        for observer in chatListObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        chatListObservers.removeAll()
        chatListPushTask?.cancel()
        chatListPushTask = nil
        for subscription in subscriptions.values {
            subscription.unsubscribe()
        }
        subscriptions.removeAll()
        send(.unpaired, requestID: nil)
        outbox?.finish()
        outbox = nil
        // Drain: the outbox task exits once it has sent everything enqueued
        // before finish(), including the farewell.
        await outboxTask?.value
        outboxTask = nil
        DLog("Companion bridge: farewell flushed; closing transport")
        // Tear down the receive side only AFTER the farewell is on the wire:
        // cancelling the receive task cancels the underlying connection (its
        // onCancel treats cancellation as abandoning the transport), which
        // would kill the farewell if done first.
        receiveTask?.cancel()
        receiveTask = nil
        await transport.close()
    }

    func stop() {
        // A user-initiated stop is not a remote disconnect; don't report one.
        onClose = nil
        receiveTask?.cancel()
        receiveTask = nil
        teardownStreams()
        let transport = self.transport
        Task { await transport.close() }
    }

    private func teardownStreams() {
        for observer in chatListObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        chatListObservers.removeAll()
        chatListPushTask?.cancel()
        chatListPushTask = nil
        for subscription in subscriptions.values {
            subscription.unsubscribe()
        }
        subscriptions.removeAll()
        outbox?.finish()
        outbox = nil
        outboxTask?.cancel()
        outboxTask = nil
        let waiters = permissionWaiters
        permissionWaiters.removeAll()
        for (_, waiter) in waiters {
            waiter.resume(returning: nil)
        }
    }

    /// Ask the phone to prompt the user for notification permission. Returns
    /// the resulting authorization, or nil if the phone didn't answer within
    /// two minutes (or the connection died). The permission dialog is in the
    /// user's hands, hence the generous deadline.
    func requestNotificationPermission() async -> CompanionPushAuthorization? {
        let requestID = nextHostRequestID
        nextHostRequestID += 1
        send(.requestNotificationPermission(requestID: requestID), requestID: nil)
        return await withCheckedContinuation { continuation in
            permissionWaiters[requestID] = continuation
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                self?.permissionWaiters.removeValue(forKey: requestID)?
                    .resume(returning: nil)
            }
        }
    }

    // MARK: Receive loop

    private func runReceiveLoop() async {
        while true {
            let frame: Data
            do {
                frame = try await transport.receive()
            } catch {
                break
            }
            guard let envelope = try? WireCoding.decode(ClientEnvelope.self, from: frame) else {
                // A frame we cannot decode (newer phone) is dropped, not fatal.
                continue
            }
            handle(envelope)
        }
        teardownStreams()
        onClose?()
    }

    private func handle(_ envelope: ClientEnvelope) {
        let requestID = envelope.requestID
        switch envelope.payload {
        case .listChatsAndSessions:
            send(.chatsAndSessions(chats: chatEntries(),
                                   sessions: CompanionSessionLister.sessions()),
                 requestID: requestID)
        case .createChat(let title, let mode):
            handleCreate(title: title, mode: mode, requestID: requestID)
        case .deleteChat(let chatID):
            do {
                guard let client = ChatClient.instance else {
                    throw CompanionMacError.chatSystemUnavailable
                }
                try client.delete(chatID: chatID)
            } catch {
                // The phone removed the row optimistically; tell it the Mac
                // disagrees so it can resync instead of silently diverging.
                send(.error(CompanionError(code: .internalError, message: "\(error)")),
                     requestID: requestID)
            }
        case .subscribe(let chatID):
            handleSubscribe(chatID: chatID, requestID: requestID)
        case .unsubscribe(let chatID):
            subscriptions[chatID]?.unsubscribe()
            subscriptions[chatID] = nil
        case .publish(let message, let chatID, _):
            handlePublish(message: message, toChatID: chatID)
        case .selectSessionResponse(let chatID, let originalMessage, let sessionGuid, let terminal):
            handleSelectSessionResponse(chatID: chatID,
                                        originalMessage: originalMessage,
                                        sessionGuid: sessionGuid,
                                        terminal: terminal)
        case .remoteCommandDecision(let chatID, let messageUniqueID, let decision):
            handleRemoteCommandDecision(chatID: chatID,
                                        messageUniqueID: messageUniqueID,
                                        decision: decision)
        case .linkSession(let chatID, let sessionGuid, let terminal):
            performLinkSession(chatID: chatID, guid: sessionGuid, terminal: terminal)
        case .resolveMentions(let identifiers):
            send(.mentionsResolved(identifiers.map { Self.resolveMention($0) }),
                 requestID: requestID)
        case .fetchSessionScreenInfo(let sessionGuid):
            handleFetchSessionScreenInfo(guid: sessionGuid, requestID: requestID)
        case .fetchSessionContent(let sessionGuid, let firstLine, let lineCount):
            handleFetchSessionContent(guid: sessionGuid,
                                      firstLine: firstLine,
                                      lineCount: lineCount,
                                      requestID: requestID)
        case .fetchWorkgroupInfo(let workgroupID):
            handleFetchWorkgroupInfo(workgroupID: workgroupID, requestID: requestID)
        case .fetchSessionTree:
            send(.sessionTree(CompanionSessionLister.tree()), requestID: requestID)
        case .pushStatus(let authorization, let token, let relaySecret, let sandbox):
            CompanionPushRegistry.update(authorization: authorization,
                                         token: token,
                                         relaySecret: relaySecret,
                                         sandbox: sandbox)
        case .notificationPermissionResponse(let permissionRequestID, let authorization):
            permissionWaiters.removeValue(forKey: permissionRequestID)?
                .resume(returning: authorization)
        case .ping:
            send(.pong, requestID: requestID)
        case .relayRoomSecret(let secret):
            // Persist the couriered room secret so the mac can sign its relay
            // parks, then ack so the phone may register its verifier. Idempotent
            // (re-sent every connect); a store failure simply withholds the ack,
            // and the phone retries on the next connection.
            do {
                try CompanionMacIdentity.storePairedRoomSecret(secret)
                DLog("Companion bridge: stored relay room secret")
                send(.relayRoomSecretStored, requestID: requestID)
            } catch {
                DLog("Companion bridge: failed to store room secret: \(error)")
                send(.error(CompanionError(code: .internalError, message: "\(error)")),
                     requestID: requestID)
            }
        case .messagesSince(let collapseToken, let seq, let limit):
            handleMessagesSince(collapseToken: collapseToken, seq: seq, limit: limit, requestID: requestID)
        case .unpairing:
            DLog("Companion bridge: peer is unpairing")
            onPeerUnpaired?()
        }
    }

    // MARK: Handlers

    private func handleCreate(title: String,
                              mode: CompanionNewChatMode,
                              requestID: UInt64?) {
        guard let client = ChatClient.instance else {
            send(.error(CompanionError(code: .notPaired, message: "Chat system unavailable")),
                 requestID: requestID)
            return
        }
        let terminalSessionGuid: String?
        switch mode {
        case .orchestrator:
            terminalSessionGuid = nil
        case .session(let guid):
            terminalSessionGuid = guid
        }
        do {
            let chatID = try client.create(chatWithTitle: title,
                                           terminalSessionGuid: terminalSessionGuid,
                                           browserSessionGuid: nil,
                                           initialMessages: [],
                                           permissions: "")
            if case .orchestrator = mode {
                // create() already spun up a session-bound agent (its internal
                // setPermissions publish reaches ChatService), and an existing
                // agent never re-reads the flag. Mirror the mac toggle's exact
                // sequence: drop the agent and dispatcher FIRST, then set the
                // flag, so the next turn builds an orchestration-mode agent.
                ChatService.instance?.dropAgent(forChatID: chatID)
                OrchestratorClient.instance?.dropDispatcher(forChatID: chatID)
                try ChatListModel.instance?.setOrchestrationEnabled(true, forChatID: chatID)
                DLog("Companion bridge: chat \(chatID) created in orchestration mode")
            }
            if let entry = entry(forChatID: chatID) {
                send(.chatCreated(entry: entry), requestID: requestID)
            } else {
                send(.error(CompanionError(code: .internalError, message: "Chat was not created")),
                     requestID: requestID)
            }
        } catch {
            send(.error(CompanionError(code: .internalError, message: "\(error)")),
                 requestID: requestID)
        }
    }

    private func handleSubscribe(chatID: String, requestID: UInt64?) {
        // Install the subscription BEFORE snapshotting history, with no
        // suspension point in between: both happen synchronously on the main
        // actor, so no message published by other main-actor code can fall
        // into a gap between "not in the history snapshot" and "not yet
        // subscribed". A delivery that lands after the subscription but
        // before the snapshot appears in both; the phone dedupes by uniqueID.
        subscriptions[chatID]?.unsubscribe()
        if let client = ChatClient.instance {
            subscriptions[chatID] = client.subscribe(chatID: chatID,
                                                     registrationProvider: nil) { [weak self] update in
                self?.handleBrokerUpdate(update, chatID: chatID)
            }
        }
        let maxSeq = ChatDatabase.instance?.maxSeq(chatID: chatID) ?? 0
        send(.history(chatID: chatID, messages: history(chatID: chatID), maxSeq: maxSeq),
             requestID: requestID)
    }

    /// Relay-push: resolve the opaque per-chat collapse token back to a chat,
    /// fetch its messages with seq > the phone's watermark, and reply with short
    /// attachment-free previews + the chat's title + its max seq. Any
    /// unresolvable case (no room secret, chat system unavailable, token matches
    /// no chat) replies with empty previews, which the NSE renders as the generic
    /// fallback. See docs/push.txt section 2.
    private func handleMessagesSince(collapseToken: String,
                                     seq: Int64,
                                     limit rawLimit: Int,
                                     requestID: UInt64?) {
        // Clamp the wire-supplied limit before any arithmetic or prefix(): it is
        // untrusted (any paired device sets it). A negative value would trap
        // Sequence.prefix(_:), and a value near Int.max would overflow the *20
        // window multiply below - both crashing the main-actor bridge.
        let limit = min(max(rawLimit, 1), 500)
        // Flow logging only; never message content. The token prefix lets you
        // correlate with the push-sender's "delivered mutable (collapse ...)".
        DLog("Companion bridge: messagesSince request (collapse \(collapseToken.prefix(8)), seq=\(seq), limit=\(limit))")

        // Transient mac-side failures (creds not loaded yet, chat model not
        // built at startup) reply .error, NOT an empty success: the NSE rethrows
        // .error and shows the fallback WITHOUT touching its per-chat watermark,
        // so a startup race can't look like "nothing new" and drop the cursor.
        guard let roomSecret = CompanionMacIdentity.pairedRoomSecret() else {
            DLog("Companion bridge: messagesSince -> error (no room secret stored)")
            send(.error(CompanionError(code: .internalError, message: "No room secret stored")),
                 requestID: requestID)
            return
        }
        guard let model = ChatListModel.instance, let db = ChatDatabase.instance else {
            DLog("Companion bridge: messagesSince -> error (chat system unavailable)")
            send(.error(CompanionError(code: .internalError, message: "Chat system unavailable")),
                 requestID: requestID)
            return
        }
        // Recompute HMAC(roomSecret, chatID) over the mac's chats to find the
        // one whose token the phone pushed. The chatID never crossed the wire.
        var resolved: Chat?
        for index in 0..<model.count {
            let chat = model.chat(at: index)
            if CompanionCollapseToken.make(roomSecret: roomSecret, chatID: chat.id) == collapseToken {
                resolved = chat
                break
            }
        }
        guard let chat = resolved else {
            // Genuine "no such chat" (deleted, or the app never synced it): an
            // empty success -> the NSE shows the fallback. maxSeq 0 is safe
            // because the watermark is max-merged and never lowered (section 8).
            DLog("Companion bridge: messagesSince -> no chat matched the collapse token (of \(model.count) chats); empty reply")
            send(.messagesSince(chatName: "", previews: [], maxSeq: 0, truncated: false, reset: false),
                 requestID: requestID)
            return
        }
        // Over-fetch a window (hiddenFromClient can't be filtered in SQL) so
        // hidden bookkeeping rows don't crowd out visible ones.
        let windowLimit = limit * 20
        let probe = db.messagesSince(chatID: chat.id, sinceSeq: seq, windowLimit: windowLimit)
        let maxSeq = probe.maxSeq
        // The phone's watermark is PAST the chat's tip: the chat DB was lost or
        // recreated and seq restarted below it. Signal a reset (only possible for
        // a resolved chat, so it can't be confused with the maxSeq:0 of a
        // no-such-chat reply) and re-fetch from the start so the NSE shows the
        // current newest and resets its stale-high watermark down to maxSeq.
        let reset = seq > maxSeq
        let windowMessages = reset
            ? db.messagesSince(chatID: chat.id, sinceSeq: 0, windowLimit: windowLimit).messages
            : probe.messages
        let result = MessagesSinceResponder.summarize(fetched: windowMessages,
                                                      limit: limit,
                                                      bodyMaxLength: 200)
        let truncated = result.truncated || windowMessages.count >= windowLimit
        // Counts/flags only; never chat title or message bodies.
        DLog("Companion bridge: messagesSince -> \(result.previews.count) preview(s), maxSeq=\(maxSeq), truncated=\(truncated), reset=\(reset)")
        send(.messagesSince(chatName: chat.title,
                            previews: result.previews,
                            maxSeq: maxSeq,
                            truncated: truncated,
                            reset: reset),
             requestID: requestID)
    }

    private func handlePublish(message: Message, toChatID chatID: String) {
        // The phone only sends user-authored content; ignore anything else.
        guard message.author == .user else {
            return
        }
        // Publish the phone's Message verbatim so its uniqueID survives the
        // round trip: the delivery then matches the phone's optimistic local
        // echo (which upserts by uniqueID) instead of duplicating the bubble.
        var toPublish = message
        toPublish.chatID = chatID
        try? ChatClient.instance?.publish(message: toPublish, toChatID: chatID, partial: false)
    }

    private func handleBrokerUpdate(_ update: ChatBroker.Update, chatID: String) {
        switch update {
        case .delivery(let message, let deliveredChatID, _):
            // Mirror the Mac UI: bookkeeping messages are not rendered there
            // and are not forwarded here. Streaming .append deltas are visible
            // (not hidden) and flow through.
            guard !message.hiddenFromClient else { return }
            send(.delivery(message: message,
                           chatID: deliveredChatID,
                           partial: Self.isPartial(message.content)),
                 requestID: nil)
        case .typingStatus(let isTyping, let participant):
            send(.typingStatus(isTyping: isTyping, participant: participant, chatID: chatID),
                 requestID: nil)
        }
    }

    private static func isPartial(_ content: Message.Content) -> Bool {
        switch content {
        case .append, .appendAttachment:
            return true
        default:
            return false
        }
    }

    // MARK: Interactive message responses (mirroring ChatViewController)

    private func performLinkSession(chatID: String, guid: String, terminal: Bool) {
        guard let listModel = ChatListModel.instance else { return }
        do {
            if terminal {
                try listModel.setTerminalGuid(for: chatID, to: guid)
            } else {
                try listModel.setBrowserGuid(for: chatID, to: guid)
            }
            let name = iTermController.sharedInstance().anySession(withGUID: guid)?.name ?? guid
            try ChatClient.instance?.publishNotice(
                chatID: chatID,
                notice: "This chat has been linked to \(terminal ? "terminal" : "browser") session “\(name)”.")
            DLog("Companion bridge: linked \(terminal ? "terminal" : "browser") session \(guid) to chat \(chatID)")
        } catch {
            DLog("Companion bridge: linkSession failed: \(error)")
            send(.error(CompanionError(code: .internalError, message: "\(error)")), requestID: nil)
        }
    }

    private func declineRemoteCommand(chatID: String,
                                      requestUUID: UUID,
                                      message: Message,
                                      text: String) {
        try? ChatClient.instance?.respondSuccessfullyToRemoteCommandRequest(
            inChat: chatID,
            requestUUID: requestUUID,
            message: text,
            functionCallName: message.functionCallName ?? "Unknown function call name",
            functionCallID: message.functionCallID,
            userNotice: nil)
    }

    private func handleSelectSessionResponse(chatID: String,
                                             originalMessage: Message,
                                             sessionGuid: String?,
                                             terminal: Bool) {
        guard let client = ChatClient.instance else { return }
        if let sessionGuid {
            DLog("Companion bridge: select-session resolved with \(sessionGuid); republishing original")
            performLinkSession(chatID: chatID, guid: sessionGuid, terminal: terminal)
            try? client.publish(message: originalMessage, toChatID: chatID, partial: false)
        } else {
            DLog("Companion bridge: select-session declined")
            declineRemoteCommand(chatID: chatID,
                                 requestUUID: originalMessage.uniqueID,
                                 message: originalMessage,
                                 text: "The user declined to allow this function call to execute.")
        }
    }

    private func handleRemoteCommandDecision(chatID: String,
                                             messageUniqueID: UUID,
                                             decision: CompanionRemoteCommandDecision) {
        guard let client = ChatClient.instance,
              let listModel = ChatListModel.instance,
              let messages = listModel.messages(forChat: chatID, createIfNeeded: false) else {
            return
        }
        var found: Message?
        for index in 0..<messages.count where messages[index].uniqueID == messageUniqueID {
            found = messages[index]
            break
        }
        guard let message = found,
              case .remoteCommandRequest(let payload, _) = message.content,
              let remoteCommand = payload.classic else {
            DLog("Companion bridge: remoteCommandDecision for unknown message \(messageUniqueID)")
            return
        }
        DLog("Companion bridge: remote command decision \(decision.rawValue) for \(messageUniqueID)")
        let category = remoteCommand.content.permissionCategory
        let browser = category.isBrowserSpecific
        let guid = browser ? listModel.chat(id: chatID)?.browserSessionGuid
                           : listModel.chat(id: chatID)?.terminalSessionGuid
        switch decision {
        case .denyOnce, .denyAlways:
            if decision == .denyAlways, let guid {
                try? listModel.setPermission(chat: chatID,
                                             permission: .never,
                                             guid: guid,
                                             category: category)
            }
            declineRemoteCommand(chatID: chatID,
                                 requestUUID: messageUniqueID,
                                 message: message,
                                 text: "The user declined to allow this function call to execute.")
        case .allowOnce, .allowAlways:
            guard let guid,
                  let session = iTermController.sharedInstance().anySession(withGUID: guid) else {
                try? client.publishNotice(chatID: chatID,
                                          notice: "This chat is not linked to any \(browser ? "web browser" : "terminal") session.")
                declineRemoteCommand(chatID: chatID,
                                     requestUUID: messageUniqueID,
                                     message: message,
                                     text: "The user did not link a \(browser ? "web browser" : "terminal") session to chat, so the function could not be run.")
                return
            }
            if decision == .allowAlways {
                try? listModel.setPermission(chat: chatID,
                                             permission: .always,
                                             guid: guid,
                                             category: category)
            }
            try? client.performRemoteCommand(remoteCommand,
                                             in: session,
                                             chatID: chatID,
                                             messageUniqueID: messageUniqueID)
        }
    }

    // MARK: Mentions and session content

    private static func resolveMention(_ identifier: String) -> CompanionMentionResolution {
        guard let resolved = OrchestrationMentionRenderer.resolve(identifier: identifier) else {
            return CompanionMentionResolution(identifier: identifier,
                                              displayName: nil,
                                              sessionGuid: nil,
                                              workgroupID: nil)
        }
        return CompanionMentionResolution(identifier: identifier,
                                          displayName: resolved.displayName,
                                          sessionGuid: resolved.revealGuid,
                                          workgroupID: resolved.workgroupID)
    }

    /// Looks a session up for the content APIs, reporting a typed error to the
    /// phone when it is gone (sessions can close while the phone views them)
    /// or cannot render yet (a workgroup member whose session has not
    /// launched has a zero-size textview, which renders nothing).
    private func contentSession(guid: String, requestID: UInt64?) -> PTYSession? {
        guard let session = iTermController.sharedInstance().anySession(withGUID: guid),
              let textview = session.textview else {
            send(.error(CompanionError(code: .unknownSession,
                                       message: "That session no longer exists. It may have been closed.")),
                 requestID: requestID)
            return nil
        }
        guard textview.frame.width > 0 else {
            send(.error(CompanionError(code: .unknownSession,
                                       message: "That session hasn’t started running yet, so there is nothing to show.")),
                 requestID: requestID)
            return nil
        }
        return session
    }

    private func handleFetchSessionScreenInfo(guid: String, requestID: UInt64?) {
        guard let session = contentSession(guid: guid, requestID: requestID),
              let textview = session.textview else {
            return
        }
        let info = CompanionSessionScreenInfo(guid: guid,
                                              name: session.name,
                                              lineCount: Int(session.screen.numberOfLines()),
                                              columns: Int(session.columns),
                                              width: Double(textview.frame.width),
                                              lineHeight: Double(textview.lineHeight),
                                              // Matches the fallback the offscreen renderer uses
                                              // for windowless (buried/peer) sessions.
                                              scale: Double(textview.window?.backingScaleFactor ?? 2.0))
        send(.sessionScreenInfo(info), requestID: requestID)
    }

    /// Upper bound on lines per content request, so one request cannot render
    /// (and frame) an arbitrarily large bitmap.
    private static let maxContentLines = 200

    private func handleFetchSessionContent(guid: String,
                                           firstLine: Int,
                                           lineCount: Int,
                                           requestID: UInt64?) {
        guard let session = contentSession(guid: guid, requestID: requestID),
              let textview = session.textview else {
            return
        }
        let totalLines = Int(session.screen.numberOfLines())
        let first = max(0, firstLine)
        let count = min(min(lineCount, Self.maxContentLines), totalLines - first)
        guard count > 0 else {
            send(.error(CompanionError(code: .badRequest,
                                       message: "The requested lines are out of range.")),
                 requestID: requestID)
            return
        }
        // A buried session (or a workgroup peer parked off screen, or one in
        // its undoable-termination window) has its textview's dataSource
        // detached, so the renderer sees zero lines and fails. The screen
        // object still holds the content; re-attach it for the duration of
        // the render and restore the detached state afterwards. The Mac UI
        // never hits this because revealing a session disinters it first.
        let wasDetached = textview.dataSource == nil
        if wasDetached {
            textview.dataSource = session.screen
        }
        defer {
            if wasDetached {
                textview.dataSource = nil
            }
        }
        // Renderer skips the background fill when bgColor is nil, leaving
        // margins transparent; fall back to black so tiles look continuous.
        let backgroundColor = session.processedBackgroundColor ?? .black
        guard let image = textview.renderImage(withLines: NSRange(location: first, length: count),
                                               includeMargins: false,
                                               backgroundColor: backgroundColor,
                                               showCursor: false) else {
            DLog("Companion bridge: render failed for \(guid): wasDetached=\(wasDetached) lines=\(totalLines) frame=\(NSStringFromRect(textview.frame))")
            send(.error(CompanionError(code: .internalError,
                                       message: "Rendering the session content failed.")),
                 requestID: requestID)
            return
        }
        let pngData = image.dataForFile(of: .png)
        guard !pngData.isEmpty else {
            send(.error(CompanionError(code: .internalError,
                                       message: "Encoding the session content failed.")),
                 requestID: requestID)
            return
        }
        send(.sessionContent(CompanionSessionContent(guid: guid,
                                                     firstLine: first,
                                                     lineCount: count,
                                                     pngData: pngData)),
             requestID: requestID)
    }

    private func handleFetchWorkgroupInfo(workgroupID: String, requestID: UInt64?) {
        guard let instance = iTermWorkgroupController.instance.allInstances
            .first(where: { $0.instanceUniqueIdentifier == workgroupID }) else {
            send(.error(CompanionError(code: .unknownSession,
                                       message: "That workgroup no longer exists.")),
                 requestID: requestID)
            return
        }
        let members = instance.resolvedMembers().map { member -> CompanionWorkgroupMember in
            let roleName = member.displayName.isEmpty ? member.roleID : member.displayName
            guard let session = member.session else {
                // The member's session has not been realized yet (or exited).
                return CompanionWorkgroupMember(roleName: roleName,
                                                sessionGuid: nil,
                                                sessionName: nil,
                                                statusText: nil,
                                                detailText: nil,
                                                state: .unknown)
            }
            let status = session.tabStatus
            return CompanionWorkgroupMember(roleName: roleName,
                                            sessionGuid: session.guid,
                                            sessionName: session.name,
                                            statusText: status?.statusText?.nilIfEmpty,
                                            detailText: status?.detailText?.nilIfEmpty,
                                            state: WorkgroupIntrospection.state(for: session))
        }
        let rawName = instance.workgroup.name
        send(.workgroupInfo(CompanionWorkgroupInfo(
            workgroupID: workgroupID,
            name: rawName.isEmpty ? "Untitled workgroup" : rawName,
            members: members)),
             requestID: requestID)
    }

    // MARK: Model projection

    /// The phone's chat rows show two lines of snippet; the Mac default (40,
    /// sized for its narrow sidebar) truncates far short of that.
    private static let snippetLength = 200

    private func chatEntries() -> [CompanionChatListEntry] {
        guard let model = ChatListModel.instance else { return [] }
        var result = [CompanionChatListEntry]()
        for index in 0..<model.count {
            let chat = model.chat(at: index)
            result.append(CompanionChatListEntry(
                chat: chat,
                snippet: model.snippet(forChatID: chat.id, maxLength: Self.snippetLength)))
        }
        return result
    }

    private func entry(forChatID chatID: String) -> CompanionChatListEntry? {
        guard let chat = ChatListModel.instance?.chat(id: chatID) else { return nil }
        return CompanionChatListEntry(
            chat: chat,
            snippet: ChatListModel.instance?.snippet(forChatID: chatID,
                                                     maxLength: Self.snippetLength))
    }

    private func history(chatID: String) -> [Message] {
        guard let model = ChatListModel.instance,
              let messages = model.messages(forChat: chatID, createIfNeeded: false) else {
            return []
        }
        var result = [Message]()
        for index in 0..<messages.count where !messages[index].hiddenFromClient {
            result.append(messages[index])
        }
        return result
    }

    // MARK: Sending

    /// Enqueue one envelope. Synchronous: enqueue order (main-actor order) is
    /// transmit order.
    private func send(_ payload: CompanionHostMessage, requestID: UInt64?) {
        outbox?.yield(HostEnvelope(requestID: requestID, payload: payload))
    }
}
