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
import QuartzCore
import CompanionProtocol
import CompanionNoise

@MainActor
final class CompanionHostBridge {
    private let transport: MessageTransport
    private var receiveTask: Task<Void, Never>?
    private var subscriptions: [String: ChatBroker.Subscription] = [:]
    /// Control frames drain ahead of media so input/replies never wait behind a
    /// video backlog; media is never dropped (see CompanionPriorityOutbox).
    private var outbox: CompanionPriorityOutbox<HostEnvelope>?
    private var outboxTask: Task<Void, Never>?

    /// One live video stream and the main-thread timer driving it.
    private final class StreamContext {
        let streamer: CompanionSessionStreamer
        let guid: String
        let timer: Timer
        var lastChange: TimeInterval
        init(streamer: CompanionSessionStreamer, guid: String, timer: Timer, lastChange: TimeInterval) {
            self.streamer = streamer
            self.guid = guid
            self.timer = timer
            self.lastChange = lastChange
        }
    }
    private var streams: [UInt32: StreamContext] = [:]
    private var streamIDForGuid: [String: UInt32] = [:]
    private var nextStreamID: UInt32 = 1

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

    /// Called exactly once, on this connection's FIRST request, to classify it
    /// for the presence warning: `solicited` is true only for a messagesSince
    /// that presented a valid one-time push nonce (the mac's own NSE fetch).
    /// Any other first request - subscribe, publish, a nonce-less or bad-nonce
    /// messagesSince - is unsolicited (the owner warns). See docs/push.txt.
    var onConnectionClassified: (@MainActor (_ solicited: Bool) -> Void)?
    private var didClassify = false

    /// Report the connection's classification once; later requests are ignored.
    private func classifyOnce(solicited: Bool) {
        guard !didClassify else { return }
        didClassify = true
        onConnectionClassified?(solicited)
    }

    /// Called when the peer's `.hello` shows the apps are version-incompatible, so
    /// the mac can show an upgrade alert. The verdict is from the MAC's side:
    /// .peerMustUpgrade -> upgrade the phone app; .selfMustUpgrade -> upgrade
    /// iTerm2. Not called when compatible.
    var onVersionIncompatible: (@MainActor (_ verdict: CompanionProtocolVersion.Compatibility) -> Void)?
    /// Set once an incompatible hello is seen: the bridge then serves nothing but
    /// a re-hello, so a stale peer cannot drive an out-of-date protocol.
    private var versionBlocked = false

    init(transport: MessageTransport) {
        self.transport = transport
    }

    func start() {
        ChatBroker.instance?.ensureServiceRunning()
        RLog("CDIAG bridge start (phone connected, bridge live)")

        let outbox = CompanionPriorityOutbox<HostEnvelope>()
        self.outbox = outbox
        outboxTask = Task { [transport] in
            // CDIAG: temporary diagnostic counters/heartbeat. If a send wedges
            // (half-open splice), the heartbeat below stops logging while the
            // bridge believes it is still connected -- the signal we need.
            var mediaFrames = 0
            var mediaBytes = 0
            var controlFrames = 0
            var lastHeartbeat = CACurrentMediaTime()
            RLog("CDIAG bridge outbox drain started")
            drain: while true {
                let data: Data
                let isMedia: Bool
                switch await outbox.next() {
                case .finished:
                    break drain
                case .control(let envelope):
                    isMedia = false
                    do {
                        data = try WireCoding.encode(envelope)
                    } catch {
                        RLog("Companion bridge: DROPPING unencodable envelope: \(error)")
                        continue
                    }
                case .media(let payload):
                    isMedia = true
                    // Control frames stay bare JSON; media frames carry the marker.
                    data = CompanionFrameChannel.frameMedia(payload)
                }
                do {
                    try await transport.send(data)
                } catch {
                    RLog("CDIAG bridge outbox send FAILED (outbox dead) after \(mediaFrames) media/\(controlFrames) control: \(error)")
                    break drain
                }
                if isMedia {
                    mediaFrames += 1
                    mediaBytes += data.count
                } else {
                    controlFrames += 1
                }
                let now = CACurrentMediaTime()
                if now - lastHeartbeat >= 5 {
                    RLog("CDIAG bridge outbox alive: sent \(mediaFrames) media (\(mediaBytes) B), \(controlFrames) control")
                    lastHeartbeat = now
                }
            }
            RLog("CDIAG bridge outbox drained/exited: \(mediaFrames) media, \(controlFrames) control total")
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
        RLog("Companion bridge: announcing unpair")
        onClose = nil
        endAllStreams(reason: .sessionClosed)
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
        endAllStreams(reason: .sessionClosed)
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
        RLog("Companion bridge: sending .requestNotificationPermission (requestID \(requestID)) to phone")
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
        // CDIAG: if the relay splice goes half-open during streaming, receive()
        // can block forever -- we'd see "started" but never "receive FAILED" or
        // "exited", confirming the wedge (no teardown, no re-park).
        RLog("CDIAG bridge receiveLoop started")
        while true {
            let frame: Data
            do {
                frame = try await transport.receive()
            } catch {
                RLog("CDIAG bridge receiveLoop receive() FAILED (drop detected): \(error)")
                break
            }
            guard let envelope = try? WireCoding.decode(ClientEnvelope.self, from: frame) else {
                // A frame we cannot decode (newer phone) is dropped, not fatal.
                continue
            }
            handle(envelope)
        }
        RLog("CDIAG bridge receiveLoop exited -> teardownStreams + onClose (will re-park)")
        teardownStreams()
        onClose?()
    }

    private func handle(_ envelope: ClientEnvelope) {
        let requestID = envelope.requestID
        // An incompatible peer is served nothing but a re-hello: the phone shows
        // an upgrade panel and disconnects, but refuse here too so a stale peer
        // cannot drive an out-of-date protocol.
        if versionBlocked {
            if case .hello(let revision, let minimumPeer) = envelope.payload {
                handleHello(peerRevision: revision, peerMinimumPeer: minimumPeer, requestID: requestID)
            } else {
                send(.error(CompanionError(code: .badRequest, message: "Companion app upgrade required")),
                     requestID: requestID)
            }
            return
        }
        // Classify the connection on its first request (for the presence
        // warning). messagesSince classifies itself based on its nonce; .hello is
        // a control handshake (neutral); every other request is interactive
        // presence -> unsolicited.
        switch envelope.payload {
        case .messagesSince, .syncSince, .hello:
            break  // messagesSince/syncSince classify after their nonce check; hello is neutral
        default:
            classifyOnce(solicited: false)
        }
        switch envelope.payload {
        case .unsupported:
            // A message type this mac build doesn't recognize (newer phone). The
            // envelope still decoded, so reply with a correlated error rather than
            // dropping it silently.
            RLog("Companion bridge: unsupported client message (peer is newer)")
            send(.error(CompanionError(code: .badRequest, message: "Unsupported request; app upgrade required")),
                 requestID: requestID)
        case .hello(let revision, let minimumPeer):
            handleHello(peerRevision: revision, peerMinimumPeer: minimumPeer, requestID: requestID)
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
                RLog("Companion bridge: stored relay room secret")
                send(.relayRoomSecretStored, requestID: requestID)
            } catch {
                RLog("Companion bridge: failed to store room secret: \(error)")
                send(.error(CompanionError(code: .internalError, message: "\(error)")),
                     requestID: requestID)
            }
        case .messagesSince(let collapseToken, let seq, let limit, let nonce):
            handleMessagesSince(collapseToken: collapseToken, seq: seq, limit: limit,
                                nonce: nonce, requestID: requestID)
        case .syncSince(let messageSeq, let alertSeq, let limit, let nonce):
            handleSyncSince(messageSeq: messageSeq, alertSeq: alertSeq, limit: limit,
                            nonce: nonce, requestID: requestID)
        case .unpairing:
            RLog("Companion bridge: peer is unpairing")
            onPeerUnpaired?()
        case .startSessionStream(let sessionGuid, let params):
            handleStartSessionStream(guid: sessionGuid, params: params, requestID: requestID)
        case .stopSessionStream(let streamID):
            endStream(streamID, reason: .stoppedByClient)
        case .requestKeyframe(let streamID):
            streams[streamID]?.streamer.requestKeyframe()
        case .updateStreamParams:
            // Frame-rate / bitrate adaptation is handled in a later milestone.
            break
        case .streamAck(let streamID, let lastPTSMilliseconds, let queueDepth):
            streams[streamID]?.streamer.noteAck(ptsMilliseconds: lastPTSMilliseconds, queueDepth: queueDepth)
        case .selectionGesture(let streamID, let phase, let mode, let point):
            handleSelectionGesture(streamID: streamID, phase: phase, mode: mode, point: point)
        case .clearSelection(let streamID):
            handleClearSelection(streamID: streamID)
        case .copySelection(let sessionGuid):
            handleCopySelection(guid: sessionGuid, requestID: requestID)
        }
    }

    // MARK: Live streaming

    /// Drive the session's real iTermSelection from a phone gesture. The resulting
    /// highlight is rendered into the stream (we mark the stream dirty so a frame
    /// goes out promptly). Runs on the main actor, where PTYTextView is safe.
    private func handleSelectionGesture(streamID: UInt32,
                                        phase: CompanionSelectionPhase,
                                        mode: CompanionSelectionMode,
                                        point: CompanionSelectionPoint) {
        guard let context = streams[streamID],
              let session = iTermController.sharedInstance().anySession(withGUID: context.guid),
              let textview = session.textview else {
            return
        }
        let coord = VT100GridAbsCoordMake(Int32(clamping: point.column), point.absLine)
        // Word/line/smart snapping queries the data source, which a buried session
        // detaches; re-attach for the operation, mirroring the frame source.
        let wasDetached = textview.dataSource == nil
        if wasDetached { textview.dataSource = session.screen }
        defer { if wasDetached { textview.dataSource = nil } }

        var moved = true
        switch phase {
        case .begin:
            textview.selection?.begin(at: coord, mode: mode.iTermSelectionMode,
                                      resume: false, append: false)
        case .move:
            moved = textview.selection?.moveEndpoint(to: coord) ?? false
        case .end:
            moved = textview.selection?.moveEndpoint(to: coord) ?? false
            textview.selection?.endLive()
        }
        RLog("CDIAG sel recv phase=\(phase) col=\(point.column) line=\(point.absLine) moved=\(moved) has=\(textview.selection?.hasSelection ?? false) live=\(textview.selection?.live ?? false)")
        // Only react when the selection actually changed: a no-op move neither
        // alters the rendered frame nor needs a selectionRange reply, and emitting
        // either just adds to the flood that backs up the link.
        let changed = (phase != .move) || moved
        if changed {
            context.streamer.screenDidChange()
            sendSelectionRange(streamID: streamID, textview: textview)
        }
    }

    private func handleClearSelection(streamID: UInt32) {
        guard let context = streams[streamID],
              let session = iTermController.sharedInstance().anySession(withGUID: context.guid),
              let textview = session.textview else {
            return
        }
        textview.selection?.clear()
        context.streamer.screenDidChange()
        sendSelectionRange(streamID: streamID, textview: textview)
    }

    /// Report the session's current selection span (or nil) so the phone can draw
    /// and move handles.
    private func sendSelectionRange(streamID: UInt32, textview: PTYTextView) {
        let range: CompanionSelectionRange?
        if let selection = textview.selection, selection.hasSelection {
            let span = selection.spanningAbsRange
            range = CompanionSelectionRange(
                start: CompanionSelectionPoint(absLine: span.start.y, column: Int(span.start.x)),
                end: CompanionSelectionPoint(absLine: span.end.y, column: Int(span.end.x)))
        } else {
            range = nil
        }
        // Latest-wins state: ride the coalescing lane so a fast drag's updates
        // collapse to the newest and never starve the media frame that actually
        // shows the selection. Keyed per stream.
        outbox?.enqueueCoalescingControl(HostEnvelope(requestID: nil, payload: .selectionRange(streamID: streamID, range: range)),
                                         key: "selectionRange.\(streamID)")
    }

    private func handleCopySelection(guid: String, requestID: UInt64?) {
        let text = iTermController.sharedInstance().anySession(withGUID: guid)?.textview?.selectedText
        send(.selectionText(text: text ?? ""), requestID: requestID)
    }

    private func handleStartSessionStream(guid: String,
                                          params: CompanionStreamParams,
                                          requestID: UInt64?) {
        guard params.supportedCodecs.contains(.hevc) else {
            send(.error(CompanionError(code: .badRequest,
                                       message: "No supported video codec (HEVC required)")),
                 requestID: requestID)
            return
        }
        guard let session = contentSession(guid: guid, requestID: requestID) else {
            return  // contentSession already replied with an error
        }
        // One stream per session: replace any existing one.
        if let existing = streamIDForGuid[guid] {
            endStream(existing, reason: .superseded)
        }

        let streamID = nextStreamID
        nextStreamID &+= 1
        let frameRate = params.maxFrameRate > 0 ? min(params.maxFrameRate, 60) : 30
        let bitRate = params.maxBitrate.map { max(100_000, min($0, 8_000_000)) } ?? 1_000_000
        // Emit the highest media-frame version both sides understand: a phone that
        // advertises nothing predates versioned frames and only decodes version 1
        // (no per-frame geometry), while a current phone gets version 2.
        let mediaVersion = UInt8(clamping: min(Int(CompanionMediaFrame.version),
                                               max(1, params.maxMediaFrameVersion ?? 1)))

        // Capture the Sendable outbox continuation, not self: the encoder's
        // callbacks fire on a VideoToolbox thread, and yielding to the stream is
        // thread-safe whereas touching the main-actor bridge would not be.
        let outboxRef = outbox
        let streamer = CompanionSessionStreamer(
            streamID: streamID,
            source: CompanionTerminalFrameSource(session: session),
            maxFrameRate: frameRate,
            averageBitRate: bitRate,
            onConfig: { config in
                outboxRef?.enqueueControl(HostEnvelope(requestID: nil, payload: .streamConfig(config)))
            },
            onMedia: { frame in
                outboxRef?.enqueueMedia(frame.encoded(version: mediaVersion))
            },
            onDataLimitReached: { [weak self] in
                // Called on the main thread from the streamer's tick.
                self?.endStream(streamID, reason: .dataLimitReached)
            })
        streamer.start()

        // A main-thread timer at the frame-rate cap drives the stream: mark dirty
        // only when the session's content-change timestamp advanced, then tick.
        // The pacer coalesces and enforces the cap, so a static screen emits nothing.
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / frameRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.driveStream(streamID)
            }
        }
        streams[streamID] = StreamContext(streamer: streamer, guid: guid, timer: timer,
                                          lastChange: max(session.screenContentsLastChangedAt,
                                                          session.view?.lastRedrawRequestedAt ?? 0))
        streamIDForGuid[guid] = streamID
        RLog("CDIAG stream \(streamID) START guid=\(guid) fps=\(frameRate)")
        send(.streamStarted(CompanionStreamStarted(streamID: streamID, codec: .hevc)),
             requestID: requestID)
    }

    private func driveStream(_ streamID: UInt32) {
        guard let context = streams[streamID] else { return }
        guard let session = iTermController.sharedInstance().anySession(withGUID: context.guid) else {
            endStream(streamID, reason: .sessionClosed)
            return
        }
        // Emit on any visual change: grid content (screenContentsLastChangedAt,
        // bumped under every renderer) OR a redraw request that does not change
        // content, such as a selection or cursor change (lastRedrawRequestedAt).
        let changedAt = max(session.screenContentsLastChangedAt,
                            session.view?.lastRedrawRequestedAt ?? 0)
        if changedAt > context.lastChange {
            context.lastChange = changedAt
            context.streamer.screenDidChange()
        }
        context.streamer.tick(nowMilliseconds: UInt64(max(0, CACurrentMediaTime() * 1000)))
    }

    private func endStream(_ streamID: UInt32, reason: CompanionStreamEndReason) {
        guard let context = streams.removeValue(forKey: streamID) else { return }
        RLog("CDIAG stream \(streamID) END reason=\(reason)")
        context.timer.invalidate()
        context.streamer.stop()
        if streamIDForGuid[context.guid] == streamID {
            streamIDForGuid[context.guid] = nil
        }
        send(.streamEnded(streamID: streamID, reason: reason), requestID: nil)
    }

    private func endAllStreams(reason: CompanionStreamEndReason) {
        for streamID in Array(streams.keys) {
            endStream(streamID, reason: reason)
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
                RLog("Companion bridge: chat \(chatID) created in orchestration mode")
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
    /// Version handshake. Always reply with our hello (so the phone can evaluate
    /// from its side), then evaluate from ours; on incompatibility, block further
    /// service and ask the mac to show an upgrade alert.
    private func handleHello(peerRevision: Int, peerMinimumPeer: Int, requestID: UInt64?) {
        send(.hello(revision: CompanionProtocolVersion.current,
                    minimumPeer: CompanionProtocolVersion.minimumPeer,
                    wantsNotificationPermission: CompanionPushRegistry.alertsEverEnabled),
             requestID: requestID)
        let verdict = CompanionProtocolVersion.evaluate(peerRevision: peerRevision,
                                                        peerMinimumPeer: peerMinimumPeer)
        versionBlocked = (verdict != .compatible)
        // Persist the peer's revision ONLY for a compatible handshake. Push-time
        // capability checks (canSendAlertsToPhone / supportsContentlessWakeup) key
        // off the stored revision, so persisting a too-new peer's revision while we
        // have declared ourselves incompatible (.selfMustUpgrade) would enable the
        // alert UI and send wakeups to a peer we just refused to talk to. On
        // incompatibility we reset it to 0 so those gates read false.
        CompanionPushRegistry.setPeerRevision(verdict == .compatible ? peerRevision : 0)
        RLog("Companion bridge: hello peer(rev=\(peerRevision), min=\(peerMinimumPeer)) -> \(verdict)")
        guard verdict != .compatible else { return }
        // Don't also pop the presence toast for an incompatible peer; the alert
        // is the user-facing signal. (solicited:true suppresses the toast.)
        classifyOnce(solicited: true)
        onVersionIncompatible?(verdict)
    }

    /// token -> chatID for the CURRENT room secret, so resolving a pushed collapse
    /// token is O(1) amortized rather than an HMAC over every chat on every fetch
    /// (repeated on retries). Main-actor-isolated (the whole class is), so no lock.
    private static var tokenCache: (roomSecret: Data, map: [String: String])?

    /// Resolve a collapse token to its chatID. Rebuilds the cache when the room
    /// secret rotates, or on a miss (a chat may have been created since the cache
    /// was built). A stale entry for a deleted chat resolves to a chatID the
    /// caller then fails to look up - an empty reply, which is correct.
    private static func resolveChatID(forToken token: String,
                                      roomSecret: Data,
                                      model: ChatListModel) -> String? {
        func rebuilt() -> [String: String] {
            var map = [String: String](minimumCapacity: model.count)
            for index in 0..<model.count {
                let chat = model.chat(at: index)
                map[CompanionCollapseToken.make(roomSecret: roomSecret, chatID: chat.id)] = chat.id
            }
            tokenCache = (roomSecret, map)
            return map
        }
        let map: [String: String]
        if let cache = tokenCache, cache.roomSecret == roomSecret {
            map = cache.map
        } else {
            map = rebuilt()
        }
        if let chatID = map[token] { return chatID }
        return rebuilt()[token]   // miss: a chat may be new; rebuild once and retry
    }

    private func handleMessagesSince(collapseToken: String,
                                     seq: Int64,
                                     limit rawLimit: Int,
                                     nonce: String?,
                                     requestID: UInt64?) {
        // Classify FIRST, before any early return: a connection that presents a
        // valid one-time push nonce is the mac's OWN solicited NSE fetch (no
        // presence warning); a missing/forged nonce is unsolicited (warn), even
        // if the fetch then errors. Use a NON-consuming peek here: the transient
        // error paths below leave the watermark untouched so the NSE retries the
        // SAME push, and the nonce must still be recognized on that retry - so it
        // is consumed only past the transient guards, on a path that actually
        // serves a reply. (consume is single-use to block replay after serving.)
        let solicited = nonce.map { CompanionPushNonceRegistry.shared.contains($0) } ?? false
        classifyOnce(solicited: solicited)

        // Clamp the wire-supplied limit before any arithmetic or prefix(): it is
        // untrusted (any paired device sets it). A negative value would trap
        // Sequence.prefix(_:), and a value near Int.max would overflow the *20
        // window multiply below - both crashing the main-actor bridge.
        let limit = min(max(rawLimit, 1), 500)
        // Flow logging only; never message content. The token prefix lets you
        // correlate with the push-sender's "delivered mutable (collapse ...)".
        RLog("Companion bridge: messagesSince request (collapse \(collapseToken.prefix(8)), seq=\(seq), limit=\(limit))")

        // Transient mac-side failures (creds not loaded yet, chat model not
        // built at startup) reply .error, NOT an empty success: the NSE rethrows
        // .error and shows the fallback WITHOUT touching its per-chat watermark,
        // so a startup race can't look like "nothing new" and drop the cursor.
        // The nonce is NOT consumed on these paths (see above), so the retry is
        // still recognized as solicited.
        guard let roomSecret = CompanionMacIdentity.pairedRoomSecret() else {
            RLog("Companion bridge: messagesSince -> error (no room secret stored)")
            send(.error(CompanionError(code: .internalError, message: "No room secret stored")),
                 requestID: requestID)
            return
        }
        guard let model = ChatListModel.instance, let db = ChatDatabase.instance else {
            RLog("Companion bridge: messagesSince -> error (chat system unavailable)")
            send(.error(CompanionError(code: .internalError, message: "Chat system unavailable")),
                 requestID: requestID)
            return
        }
        // Resolve the pushed collapse token to a chat via a cached
        // token -> chatID map (see resolveChatID), instead of recomputing
        // HMAC(roomSecret, chatID) for every chat on every fetch. The chatID
        // never crossed the wire.
        guard let chatID = Self.resolveChatID(forToken: collapseToken, roomSecret: roomSecret, model: model),
              let chat = model.chat(id: chatID) else {
            // Genuine "no such chat" (deleted, or the app never synced it): an
            // empty success -> the NSE shows the fallback. maxSeq 0 is safe
            // because the watermark is max-merged and never lowered (section 8). A
            // served reply, so burn the single-use nonce.
            if let nonce { _ = CompanionPushNonceRegistry.shared.consume(nonce) }
            RLog("Companion bridge: messagesSince -> no chat matched the collapse token (of \(model.count) chats); empty reply")
            send(.messagesSince(chatName: "", previews: [], maxSeq: 0, truncated: false, reset: false),
                 requestID: requestID)
            return
        }
        // Over-fetch a window (hiddenFromClient can't be filtered in SQL) so
        // hidden bookkeeping rows don't crowd out visible ones.
        let windowLimit = limit * 20
        // A query FAILURE (nil, distinct from an empty result) is transient -
        // handle it like the guards above: reply .error, do NOT consume the nonce
        // (so the NSE's retry of this push is still recognized as solicited), and
        // do NOT compute reset. A maxSeq of 0 from an error must never look like a
        // chat-DB rewind (seq > maxSeq) and force the phone's watermark to 0.
        guard let probe = db.messagesSince(chatID: chat.id, sinceSeq: seq, windowLimit: windowLimit) else {
            RLog("Companion bridge: messagesSince -> error (chat database query failed)")
            send(.error(CompanionError(code: .internalError, message: "Chat database unavailable")),
                 requestID: requestID)
            return
        }
        let maxSeq = probe.maxSeq
        // The phone's watermark is PAST the chat's tip: the chat DB was lost or
        // recreated and seq restarted below it. reset is computed ONLY from a
        // SUCCESSFUL fetch, so a query error can never be confused with a rewind.
        // Signal a reset (only possible for a resolved chat, so it can't be
        // confused with the maxSeq:0 of a no-such-chat reply) and re-fetch from
        // the start so the NSE shows the current newest and resets its stale-high
        // watermark down to maxSeq.
        let reset = seq > maxSeq
        let windowMessages: [Message]
        if reset {
            guard let refetched = db.messagesSince(chatID: chat.id, sinceSeq: 0, windowLimit: windowLimit) else {
                RLog("Companion bridge: messagesSince -> error (reset re-fetch failed)")
                send(.error(CompanionError(code: .internalError, message: "Chat database unavailable")),
                     requestID: requestID)
                return
            }
            windowMessages = refetched.messages
        } else {
            windowMessages = probe.messages
        }
        let result = MessagesSinceResponder.summarize(
            fetched: windowMessages,
            limit: limit,
            bodyMaxLength: 200,
            // Render @<guid> mentions to the live session/workgroup name, the
            // same names the chat UI shows, so the lock screen never shows a raw
            // guid. nil (unresolved) -> "[defunct session]".
            resolveMention: { OrchestrationMentionRenderer.resolve(identifier: $0)?.displayName })
        let truncated = result.truncated || windowMessages.count >= windowLimit
        // Every DB read succeeded and we are about to serve a real reply -> burn
        // the single-use nonce (after this, a replay can't suppress a warning).
        if let nonce { _ = CompanionPushNonceRegistry.shared.consume(nonce) }
        // Counts/flags only; never chat title or message bodies.
        RLog("Companion bridge: messagesSince -> \(result.previews.count) preview(s), maxSeq=\(maxSeq), truncated=\(truncated), reset=\(reset)")
        send(.messagesSince(chatName: chat.title,
                            previews: result.previews,
                            maxSeq: maxSeq,
                            truncated: truncated,
                            reset: reset),
             requestID: requestID)
    }

    /// Contentless-wakeup (revision >= 2): on a wakeup the NSE asks for everything
    /// new across ALL chats (seq > messageSeq) and alerts (seq > alertSeq) in one
    /// round trip. Mirrors handleMessagesSince's transient-error discipline (reply
    /// .error without consuming the nonce, so the NSE's retry of the same wakeup is
    /// still recognized as solicited); the nonce is burned only when a real reply
    /// is served. The per-item chatID is safe here: it crosses the Noise channel,
    /// never the APNs payload.
    private func handleSyncSince(messageSeq: Int64,
                                 alertSeq: Int64,
                                 limit rawLimit: Int,
                                 nonce: String?,
                                 requestID: UInt64?) {
        let solicited = nonce.map { CompanionPushNonceRegistry.shared.contains($0) } ?? false
        classifyOnce(solicited: solicited)

        let limit = min(max(rawLimit, 1), 500)
        RLog("Companion bridge: syncSince request (messageSeq=\(messageSeq), alertSeq=\(alertSeq), limit=\(limit))")

        func serveError(_ message: String) {
            RLog("Companion bridge: syncSince -> error (\(message))")
            send(.error(CompanionError(code: .internalError, message: message)), requestID: requestID)
        }

        guard let model = ChatListModel.instance, let db = ChatDatabase.instance else {
            serveError("Chat system unavailable")
            return
        }

        // --- Messages across all chats ---
        // A negative message floor is the phone's FIRST-RUN signal (post-upgrade):
        // show the newest `limit` as a teaser and jump the floor to the global tip,
        // skipping the backlog rather than notifying it window-by-window. A normal
        // run drains OLDEST-first within a window and advances the floor only to the
        // highest seq it actually covered, so a truncated window never buries the
        // tail (the tail drains on the next wakeup).
        let firstRun = messageSeq < 0
        let windowLimit = limit * 20
        let messageWindow = firstRun ? limit : windowLimit
        guard let probe = db.messagesSinceGlobal(sinceSeq: max(messageSeq, 0),
                                                 windowLimit: messageWindow,
                                                 ascending: !firstRun) else {
            serveError("Chat database unavailable")
            return
        }
        let globalMessageTip = probe.maxSeq
        // Reset: the phone's floor is past the tip (the store was lost/recreated and
        // seq rewound). Do NOT re-notify the rewound content; resync silently -
        // return no message items, signal a reset so the NSE clears its stale-high
        // per-chat watermarks, and float the floor to the new tip.
        let messageReset = !firstRun && messageSeq > globalMessageTip
        let messageRows: [(seq: Int64, message: Message)]
        let messageTruncated: Bool
        let messageFloorTarget: Int64
        if messageReset {
            messageRows = []
            messageTruncated = false
            messageFloorTarget = globalMessageTip
        } else if firstRun {
            messageRows = probe.rows                       // newest `limit`, DESC
            messageTruncated = probe.rows.count >= limit   // more backlog exists
            messageFloorTarget = globalMessageTip          // jump to tip, skip backlog
        } else {
            messageRows = probe.rows                        // oldest window, ASC
            messageTruncated = probe.rows.count >= windowLimit
            // Advance the floor ONLY to the highest seq we covered in the window
            // (its last ASC row); the tail above it drains next wakeup. When not
            // truncated we covered everything above the floor, so jump to the tip.
            messageFloorTarget = messageTruncated ? (probe.rows.last?.seq ?? globalMessageTip)
                                                  : globalMessageTip
        }

        // --- Alerts (oldest-first drain; window >= store prune cap, so the window
        // never truncates and no alert is skipped past the floor). ---
        guard let alertProbe = db.alertsSince(sinceSeq: max(alertSeq, 0), limit: windowLimit) else {
            serveError("Alert store unavailable")
            return
        }
        let globalAlertTip = alertProbe.maxSeq
        let alertReset = alertSeq > globalAlertTip
        let alertRows: [CompanionAlertRecord]
        let alertFloorTarget: Int64
        let alertTruncated: Bool
        if alertReset {
            alertRows = []
            alertFloorTarget = globalAlertTip
            alertTruncated = false
        } else {
            alertRows = alertProbe.alerts
            alertTruncated = alertProbe.alerts.count >= windowLimit
            alertFloorTarget = alertTruncated ? (alertProbe.alerts.last?.seq ?? globalAlertTip)
                                              : globalAlertTip
        }

        // Build message items: group the window by chat so the visibility + snippet
        // + mention rendering in MessagesSinceResponder.summarize runs per-chat
        // (exactly as the per-chat push). No per-chat cap here (limit = window): the
        // floor advances to the window's covered seq, so dropping a notifiable
        // message within the window would bury it. Each item is paired with its
        // sort key (message sentDate / alert createdDate); we sort ALL items
        // (messages + alerts) by wall-clock time below, because the two have
        // separate seq spaces and the NSE relies on one global order to pick the
        // anchor (oldest) and the sound/"+ more" (newest).
        var infoByUniqueID = [UUID: (seq: Int64, date: Date)](minimumCapacity: messageRows.count)
        var byChat = [String: [Message]]()
        var chatOrder = [String]()
        for row in messageRows {
            infoByUniqueID[row.message.uniqueID] = (row.seq, row.message.sentDate)
            if byChat[row.message.chatID] == nil { chatOrder.append(row.message.chatID) }
            byChat[row.message.chatID, default: []].append(row.message)
        }
        var dated = [(item: CompanionSyncItem, date: Date)]()
        for chatID in chatOrder {
            // Side-effect-free title lookup: chat(id:) would reconfigure the global
            // RemoteCommandExecutor permission singleton, which a background fetch
            // must never do.
            guard let chatTitle = model.title(forChatID: chatID) else { continue }
            // summarize expects newest-first; sort the slice by seq DESC regardless
            // of the fetch order (ASC normal run / DESC first run).
            let slice = (byChat[chatID] ?? []).sorted {
                (infoByUniqueID[$0.uniqueID]?.seq ?? 0) > (infoByUniqueID[$1.uniqueID]?.seq ?? 0)
            }
            let result = MessagesSinceResponder.summarize(
                fetched: slice,
                limit: messageWindow,
                bodyMaxLength: 200,
                resolveMention: { OrchestrationMentionRenderer.resolve(identifier: $0)?.displayName })
            for preview in result.previews {
                let info = infoByUniqueID[preview.uniqueID]
                dated.append((.message(CompanionSyncMessageItem(
                    chatID: chatID,
                    chatName: chatTitle,
                    uniqueID: preview.uniqueID,
                    author: preview.author.rawValue,
                    body: preview.body,
                    seq: info?.seq ?? 0)),
                    info?.date ?? Date.distantPast))
            }
        }
        for alert in alertRows {
            dated.append((.alert(CompanionSyncAlertItem(
                alertID: alert.uniqueID,
                threadKey: alert.threadKey,
                title: alert.title,
                body: alert.body,
                seq: alert.seq)),
                alert.createdDate))
        }
        // Global time order (oldest first). The enumerated-index tiebreaker makes it
        // explicitly stable, so same-timestamp items keep their per-chat / fetch
        // order regardless of the sort's stability guarantees.
        let items = dated.enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map { $0.element.item }
        // `truncated` only feeds the NSE's "+ more" hint now; the floor targets above
        // already guarantee the tail is not skipped. Reflect EITHER stream being
        // truncated (alerts can't truncate while the window exceeds the prune cap,
        // but fold it in so a future sizing change can't silently drop the hint).
        let truncated = messageTruncated || alertTruncated

        // Served a real reply -> burn the single-use nonce.
        if let nonce { _ = CompanionPushNonceRegistry.shared.consume(nonce) }
        RLog("Companion bridge: syncSince -> \(items.count) item(s), messageFloor=\(messageFloorTarget), alertFloor=\(alertFloorTarget), firstRun=\(firstRun), messageReset=\(messageReset), alertReset=\(alertReset), truncated=\(truncated)")
        send(.syncSince(items: items,
                        maxMessageSeq: messageFloorTarget,
                        maxAlertSeq: alertFloorTarget,
                        messageReset: messageReset,
                        alertReset: alertReset,
                        truncated: truncated),
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
            RLog("Companion bridge: linked \(terminal ? "terminal" : "browser") session \(guid) to chat \(chatID)")
        } catch {
            RLog("Companion bridge: linkSession failed: \(error)")
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
            RLog("Companion bridge: select-session resolved with \(sessionGuid); republishing original")
            performLinkSession(chatID: chatID, guid: sessionGuid, terminal: terminal)
            try? client.publish(message: originalMessage, toChatID: chatID, partial: false)
        } else {
            RLog("Companion bridge: select-session declined")
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
            RLog("Companion bridge: remoteCommandDecision for unknown message \(messageUniqueID)")
            return
        }
        RLog("Companion bridge: remote command decision \(decision.rawValue) for \(messageUniqueID)")
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
                                              // Exclude the right gutter (accessory panels / timestamp
                                              // slot) so it matches the rendered tile width.
                                              width: Double(textview.widthExcludingRightGutter()),
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
            RLog("Companion bridge: render failed for \(guid): wasDetached=\(wasDetached) lines=\(totalLines) frame=\(NSStringFromRect(textview.frame))")
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
    /// transmit order among control frames, which always precede pending media.
    private func send(_ payload: CompanionHostMessage, requestID: UInt64?) {
        outbox?.enqueueControl(HostEnvelope(requestID: requestID, payload: payload))
    }
}

private extension CompanionSelectionMode {
    /// Map the wire selection mode to iTerm2's. Box selection is not exposed to the
    /// phone, so there is no inverse for it.
    var iTermSelectionMode: iTermSelectionMode {
        switch self {
        case .character: return .kiTermSelectionModeCharacter
        case .word: return .kiTermSelectionModeWord
        case .line: return .kiTermSelectionModeWholeLine
        case .smart: return .kiTermSelectionModeSmart
        }
    }
}
