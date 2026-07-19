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
        /// Last selection pushed to the phone, to detect changes (mac-side or phone)
        /// and push a selectionRange so it can reload affected history tiles.
        var lastSentSelectionRange: CompanionSelectionRange?
        /// The stream generation last observed while driving. A genuine generation
        /// bump (resize/reflow/font change) makes the phone discard its selection, so
        /// when this advances the selection is re-pushed even if its value is unchanged.
        var lastConfigGeneration: UInt32 = 0
        /// The fixed endpoint of an in-progress character-mode drag (raw, inclusive),
        /// set at .begin and used to rebuild the range by document order on each move.
        var selectionAnchor: VT100GridAbsCoord?
        /// The half-open range last applied for the drag, so an unchanged move is a
        /// no-op (no re-begin, no selectionRange flood).
        var lastAppliedCharRange: (start: VT100GridAbsCoord, end: VT100GridAbsCoord)?
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
    /// bridge. A user-initiated stop() does not fire it. Carries the terminating
    /// transport error (e.g. `.quotaExceeded`) so the owner can distinguish a relay
    /// quota teardown from ordinary loss and back off; nil when unavailable.
    var onClose: (@MainActor (Error?) -> Void)?

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
        RLog("bridge start (phone connected, bridge live)")

        let outbox = CompanionPriorityOutbox<HostEnvelope>()
        self.outbox = outbox
        outboxTask = Task { [transport] in
            // Diagnostic counters/heartbeat. If a send wedges
            // (half-open splice), the heartbeat below stops logging while the
            // bridge believes it is still connected -- the signal we need.
            var mediaFrames = 0
            var mediaBytes = 0
            var controlFrames = 0
            var lastHeartbeat = CACurrentMediaTime()
            RLog("bridge outbox drain started")
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
                    RLog("bridge outbox send FAILED (outbox dead) after \(mediaFrames) media/\(controlFrames) control: \(error)")
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
                    RLog("bridge outbox alive: sent \(mediaFrames) media (\(mediaBytes) B), \(controlFrames) control")
                    lastHeartbeat = now
                }
            }
            RLog("bridge outbox drained/exited: \(mediaFrames) media, \(controlFrames) control total")
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
        // Resolve any in-flight host-initiated request (e.g. the notification
        // permission prompt) so its awaiting task doesn't hang after we tear down.
        let waiters = permissionWaiters
        permissionWaiters.removeAll()
        for (_, waiter) in waiters {
            waiter.resume(returning: nil)
        }
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
        // If the relay splice goes half-open during streaming, receive()
        // can block forever -- we'd see "started" but never "receive FAILED" or
        // "exited", confirming the wedge (no teardown, no re-park).
        RLog("bridge receiveLoop started")
        var dropError: Error?
        while true {
            let frame: Data
            do {
                frame = try await transport.receive()
            } catch {
                RLog("bridge receiveLoop receive() FAILED (drop detected): \(error)")
                dropError = error
                break
            }
            guard let envelope = try? WireCoding.decode(ClientEnvelope.self, from: frame) else {
                // A frame we cannot decode (newer phone) is dropped, not fatal.
                continue
            }
            handle(envelope)
        }
        RLog("bridge receiveLoop exited -> teardownStreams + onClose (will re-park)")
        teardownStreams()
        onClose?(dropError)
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
                CompanionChatMuteRegistry.forget(chatID: chatID)
            } catch {
                // The phone removed the row optimistically; tell it the Mac
                // disagrees so it can resync instead of silently diverging.
                send(.error(CompanionError(code: .internalError, message: "\(error)")),
                     requestID: requestID)
            }
        case .setChatMuted(let chatID, let muted):
            // The phone toggled the row optimistically; persist so the push
            // path (agent-activity notifier + syncSince) honors it even while
            // the phone is unreachable.
            CompanionChatMuteRegistry.setMuted(muted, chatID: chatID)
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
        case .fetchHistoryTile(let streamID, let firstAbsLine, let lineCount, let generationId):
            handleFetchHistoryTile(streamID: streamID,
                                   firstAbsLine: firstAbsLine,
                                   lineCount: lineCount,
                                   generationId: generationId,
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
        case .updateStreamParams(let streamID, let params):
            // Only the frame-rate cap adapts on a running stream. Per-frame quality
            // (bits per pixel) is deliberately NOT touched: a terminal feed must stay
            // legible, so FPS is the sole flexible dimension. The maxBitrate field is
            // ignored here (it is only an upper bound applied when the stream starts).
            // Lowering the cap takes effect immediately (the pacer coalesces);
            // raising it is bounded by the main-thread driving timer, which is fixed
            // at the stream's initial rate, so the supported direction is downward.
            streams[streamID]?.streamer.updateFrameRateCap(params.maxFrameRate)
        case .streamAck(let streamID, let lastPTSMilliseconds, let queueDepth):
            streams[streamID]?.streamer.noteAck(ptsMilliseconds: lastPTSMilliseconds, queueDepth: queueDepth)
        case .reportScrollWheel(let streamID, let up, let lines):
            handleReportScrollWheel(streamID: streamID, up: up, lines: lines)
        case .selectionGesture(let streamID, let phase, let mode, let point):
            handleSelectionGesture(streamID: streamID, phase: phase, mode: mode, point: point)
        case .clearSelection(let streamID):
            handleClearSelection(streamID: streamID)
        case .copySelection(let sessionGuid):
            handleCopySelection(guid: sessionGuid, requestID: requestID)
        case .selectAllInStream(let streamID):
            handleSelectAll(streamID: streamID)
        case .pasteText(let sessionGuid, let text):
            iTermController.sharedInstance().anySession(forReference: sessionGuid)?.paste(text, flags: [])
        case .sendKey(let sessionGuid, let event):
            handleSendKey(guid: sessionGuid, event: event)
        case .resizeSession(let sessionGuid, let columns, let rows):
            handleResizeSession(guid: sessionGuid, columns: columns, rows: rows)
        case .fetchAutoProvideConsent(let sessionGuid):
            send(.autoProvideConsent(satisfied: Self.autoProvideConsentSatisfied(sessionGuid: sessionGuid)),
                 requestID: requestID)
        case .grantAutoProvideConsent(let chatID):
            handleGrantAutoProvideConsent(chatID: chatID)
        }
    }

    /// Whether auto-providing terminal state + the visible screen is already in
    /// effect for the chat the phone would send to for this session: the session's
    /// most recent session-bound chat if one exists, else a new chat (whose
    /// permissions start at the global default). Both Check Terminal State and View
    /// Contents must be "provided automatically" (.always).
    static func autoProvideConsentSatisfied(sessionGuid: String) -> Bool {
        // Auto-send is gated on the global consent too (ChatAgent.shouldSuppressAutoProvide),
        // so "satisfied" must require it; otherwise the phone would skip its
        // "Share This Session?" modal while the mac still suppresses the auto-send.
        guard iTermUserDefaults.autoProvideConsent == .granted else { return false }
        let rce = RemoteCommandExecutor.instance
        // An empty chatID has no per-chat override, so permission() falls back to the
        // global default - exactly what a not-yet-created chat would inherit.
        let chatID = ChatListModel.instance?.mostRecentChat(forGuid: sessionGuid)?.id ?? ""
        return rce.permission(chatID: chatID, inSessionGuid: sessionGuid, category: .checkTerminalState) == .always
            && rce.permission(chatID: chatID, inSessionGuid: sessionGuid, category: .viewContents) == .always
    }

    /// Grant "provided automatically" for Check Terminal State and View Contents on an
    /// already-resolved session-bound chat, so its turns carry the terminal state and
    /// visible screen. The phone sends this after the user approves its consent modal.
    private func handleGrantAutoProvideConsent(chatID: String) {
        guard let listModel = ChatListModel.instance,
              let guid = listModel.chat(id: chatID)?.terminalSessionGuid else {
            RLog("grantAutoProvideConsent: chat \(chatID) has no linked session; ignoring")
            return
        }
        for category in [RemoteCommand.Content.PermissionCategory.checkTerminalState, .viewContents] {
            try? listModel.setPermission(chat: chatID, permission: .always, guid: guid, category: category)
        }
        // The phone showed its own "Share This Session?" consent modal, so this is an
        // explicit informed consent: record it globally so the mac's auto-send gate
        // (ChatAgent.shouldSuppressAutoProvide) lets it through.
        iTermUserDefaults.autoProvideConsent = .granted
        RLog("grantAutoProvideConsent: granted provided-automatically for chat \(chatID) session \(guid)")
    }

    /// Resize a session's grid on behalf of the phone. The phone computes a
    /// legible column count for its screen and how many rows fill it; we clamp to
    /// sane bounds so a stale or hostile peer cannot request an absurd grid, then
    /// drive the same terminal-initiated resize path the escape sequence uses.
    private func handleResizeSession(guid: String, columns: Int, rows: Int) {
        guard let session = iTermController.sharedInstance().anySession(forReference: guid) else {
            return
        }
        // Re-validate server-side rather than trusting the phone's (advisory, and
        // possibly stale) UI gate: reallySetCellSize: applies none of the guards
        // screenSetSize: does, and the delegate only re-checks full screen -- not the
        // width lock. This single check covers full screen, width-locked, and
        // non-resizable window types authoritatively, so a width-locked session
        // cannot be resized from the phone even if its button was left enabled.
        guard session.companionSessionCanResizeWindow() else {
            return
        }
        let clampedColumns = Int32(min(max(columns, 1), 4096))
        let clampedRows = Int32(min(max(rows, 1), 4096))
        // reallySetCellSize: reads proposedSize.width as the row count and
        // proposedSize.height as the column count (see PTYSession.h).
        session.reallySetCellSize(VT100GridSize(width: clampedRows, height: clampedColumns))
    }

    /// Inject one key press from the phone's on-screen keyboard. Ordinary typed text
    /// (no modifier) is written as literal input; a single modified character or a
    /// named special key is synthesized into a key event and run through the
    /// session's own key mapper so control/option encodings honor the profile and
    /// special keys honor the terminal's cursor/keypad/key-reporting modes.
    private func handleSendKey(guid: String, event: CompanionKeyEvent) {
        guard let session = iTermController.sharedInstance().anySession(forReference: guid) else {
            DLog("sendKey: no session for guid \(guid); dropping key \(event.key)")
            return
        }
        // Route every key - including ordinary typed text, one event per character -
        // through the session's key mapper rather than writing text literally. The
        // mapper is the only thing that knows the current key-reporting mode, so a
        // full-screen app that turned on a CSI-u mode (report all keys as escape
        // codes, disambiguate escape, ...) sees correctly-encoded keys.
        //
        // Exception: a character with no single-keystroke mapping on the mac's layout
        // (accented letter, emoji, dead-key result) synthesizes to a key code the CSI-u
        // mapper would mis-derive; those are passed as literalText so the mac writes the
        // correct character verbatim - but still behind the same accept-gate and
        // broadcast suppression as the mapped keys (see CompanionKeyEvent.literalFallback).
        for keyEvent in event.makeKeyDownEvents() {
            session.injectSynthesizedKeyEvent(keyEvent,
                                              literalText: CompanionKeyEvent.literalFallback(for: keyEvent))
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
              let session = iTermController.sharedInstance().anySession(forReference: context.guid),
              let textview = session.textview else {
            return
        }
        // Clamp the absolute line to the available buffer so a hostile or stale peer
        // cannot point iTermSelection at a line outside [firstAbs, firstAbs+lines).
        // The column is clamped downstream (inclusiveCharacterRange / iTermSelection).
        let clampedAbsLine = Self.clampAbsLine(point.absLine,
                                               firstAbs: session.screen.totalScrollbackOverflow(),
                                               lineCount: Int64(session.screen.numberOfLines()))
        let coord = VT100GridAbsCoordMake(Int32(clamping: point.column), clampedAbsLine)
        // Word/line/smart snapping queries the data source, which a buried session
        // detaches; re-attach for the operation, mirroring the frame source.
        let wasDetached = textview.dataSource == nil
        if wasDetached { textview.dataSource = session.screen }
        defer { if wasDetached { textview.dataSource = nil } }

        let changed: Bool
        if mode == .character {
            let gridWidth = Int(textview.dataSource?.width() ?? 0)
            changed = applyCharacterSelection(context: context, textview: textview,
                                              phase: phase, coord: coord, gridWidth: gridWidth)
        } else {
            // Word/line/smart selections snap to whole-token boundaries, so there is
            // no single-cell exclusivity to reconcile: drive iTermSelection's live
            // selection directly.
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
            changed = (phase != .move) || moved
        }
        // Only react when the selection actually changed: a no-op move neither
        // alters the rendered frame nor needs a selectionRange reply, and emitting
        // either just adds to the flood that backs up the link.
        if changed {
            context.streamer.screenDidChange()
            sendSelectionRange(streamID: streamID, textview: textview)
        }
    }

    /// Apply a character-mode selection from the phone. The phone sends raw inclusive
    /// coordinates (the anchor at .begin, the live point on move/end); the range is
    /// rebuilt by document order so exclusivity is correct in every drag direction.
    /// Returns whether the applied range changed (so a no-op move is dropped).
    private func applyCharacterSelection(context: StreamContext, textview: PTYTextView,
                                         phase: CompanionSelectionPhase,
                                         coord: VT100GridAbsCoord, gridWidth: Int) -> Bool {
        let anchor: VT100GridAbsCoord
        switch phase {
        case .begin:
            context.selectionAnchor = coord
            context.lastAppliedCharRange = nil
            anchor = coord
        case .move, .end:
            anchor = context.selectionAnchor ?? coord
        }
        let range = Self.inclusiveCharacterRange(anchor: anchor, live: coord, gridWidth: gridWidth)
        var changed = true
        if let last = context.lastAppliedCharRange,
           last.start.x == range.start.x, last.start.y == range.start.y,
           last.end.x == range.end.x, last.end.y == range.end.y {
            changed = false
        } else {
            textview.selection?.begin(at: range.start, mode: .kiTermSelectionModeCharacter,
                                      resume: false, append: false)
            _ = textview.selection?.moveEndpoint(to: range.end)
            context.lastAppliedCharRange = range
        }
        if phase == .end {
            textview.selection?.endLive()
            context.selectionAnchor = nil
            context.lastAppliedCharRange = nil
            changed = true   // always broadcast the finalized selection
        } else if phase == .begin {
            changed = true   // a fresh begin always establishes a selection
        }
        return changed
    }

    /// Forget an in-progress character-drag's anchor and last-applied range. Call
    /// whenever the selection is cleared or replaced OUTSIDE the gesture path, so a
    /// later phone .move that happens to recompute the same range is not dropped as a
    /// no-op (which would make the drag look dead until the finger crosses a cell).
    private func resetSelectionDragState(_ context: StreamContext) {
        context.selectionAnchor = nil
        context.lastAppliedCharRange = nil
    }

    private func handleSelectAll(streamID: UInt32) {
        guard let context = streams[streamID],
              let session = iTermController.sharedInstance().anySession(forReference: context.guid),
              let textview = session.textview else {
            return
        }
        let wasDetached = textview.dataSource == nil
        if wasDetached { textview.dataSource = session.screen }
        defer { if wasDetached { textview.dataSource = nil } }
        textview.selectAll(nil)
        resetSelectionDragState(context)
        context.streamer.screenDidChange()
        sendSelectionRange(streamID: streamID, textview: textview)
    }

    private func handleClearSelection(streamID: UInt32) {
        guard let context = streams[streamID],
              let session = iTermController.sharedInstance().anySession(forReference: context.guid),
              let textview = session.textview else {
            return
        }
        textview.selection?.clear()
        resetSelectionDragState(context)
        context.streamer.screenDidChange()
        sendSelectionRange(streamID: streamID, textview: textview)
    }

    /// Report the session's current selection span (or nil) so the phone can draw
    /// and move handles.
    /// iTermSelection's end x is EXCLUSIVE (one past the last selected cell; select
    /// all yields end.x == gridWidth). The phone treats the wire end as the
    /// inclusive last cell, so convert here. An exclusive end at column 0 means the
    /// previous line is selected through its last cell.
    nonisolated static func inclusiveSelectionEnd(exclusiveColumn column: Int, absLine: Int64,
                                                  gridWidth: Int) -> (column: Int, absLine: Int64) {
        if column > 0 { return (column - 1, absLine) }
        return (max(0, gridWidth - 1), absLine - 1)
    }

    /// Clamp an absolute line to the buffer's available range [firstAbs,
    /// firstAbs+lineCount). An empty buffer (lineCount <= 0) clamps to firstAbs.
    nonisolated static func clampAbsLine(_ absLine: Int64, firstAbs: Int64, lineCount: Int64) -> Int64 {
        guard lineCount > 0 else { return firstAbs }
        return min(max(absLine, firstAbs), firstAbs + lineCount - 1)
    }

    struct SelectionPushDecision: Equatable {
        /// The selection changed from a non-gesture source, so an in-progress drag's
        /// state is stale and must be forgotten.
        var resetDragState: Bool
        /// The current selection should be (re)sent to the phone.
        var push: Bool
    }

    /// Decide how driveStream reacts to the current selection. A value change means it
    /// came from elsewhere (a phone gesture pushes inline and updates lastSent), so
    /// reset the drag and push. A generation bump forces a re-push of the SAME value
    /// (the phone discarded it) but must NOT reset the drag, so a resize mid-drag
    /// keeps the anchor.
    nonisolated static func selectionPushDecision(current: CompanionSelectionRange?,
                                                  lastSent: CompanionSelectionRange?,
                                                  generationBumped: Bool) -> SelectionPushDecision {
        let valueChanged = (current != lastSent)
        return SelectionPushDecision(resetDragState: valueChanged,
                                     push: valueChanged || generationBumped)
    }

    /// Given the two inclusive endpoints of a character-mode selection (the fixed
    /// anchor and the live point, in either order), return the half-open range
    /// iTermSelection needs: start at the earlier cell (inclusive), end one past the
    /// later cell (exclusive). Ordering the coordinates HERE, before iTermSelection's
    /// own unflip, is what makes the exclusive +1 land on the endpoint that actually
    /// ends up in the END role, so backward and endpoint-crossing drags include the
    /// cell under the finger instead of dropping or collapsing it.
    nonisolated static func inclusiveCharacterRange(anchor: VT100GridAbsCoord,
                                                    live: VT100GridAbsCoord,
                                                    gridWidth: Int)
    -> (start: VT100GridAbsCoord, end: VT100GridAbsCoord) {
        // Clamp columns before the exclusive +1 so a hostile peer sending a column
        // near Int32.max cannot wrap to Int32.min and hand iTermSelection a nonsense
        // coordinate. With a known width the last valid inclusive column is width-1
        // (so the exclusive end is at most width); without one, cap short of the
        // Int32 max headroom for the +1.
        let maxColumn: Int32 = gridWidth > 0 ? Int32(clamping: gridWidth - 1) : Int32.max - 1
        func clampColumn(_ c: VT100GridAbsCoord) -> VT100GridAbsCoord {
            VT100GridAbsCoordMake(min(max(c.x, 0), maxColumn), c.y)
        }
        let a = clampColumn(anchor)
        let l = clampColumn(live)
        let anchorFirst = a.y < l.y || (a.y == l.y && a.x <= l.x)
        let lo = anchorFirst ? a : l
        let hi = anchorFirst ? l : a
        return (lo, VT100GridAbsCoordMake(hi.x &+ 1, hi.y))
    }

    /// The unsolicited state snapshots to send to a phone that has just
    /// subscribed, in addition to `.history`, so a turn already in flight is
    /// reflected on the phone. Pure so it is unit-testable without a live bridge.
    /// `agentTyping` is TypingStatusModel's current value for the chat.
    ///
    /// Both snapshots are sent ONLY when BOTH ends are at turnLifecycleRevision
    /// (gated on the min of this mac's own `current` and the peer's revision). Such
    /// a phone treats typing as a spinner-only hint and drives its reply
    /// notification off the explicit turnLifecycle boundary. Both ends matter: the
    /// phone keys that behavior on the MAC's revision (it must see macRevision >=
    /// turnLifecycleRevision, i.e. our `current`), and a legacy phone lacks the gate
    /// entirely - it would mis-arm its reply trigger from a typing(true) snapshot,
    /// reintroducing the "false fires from replayed-but-incomplete state" the
    /// reconnect handler's resetWatchedReplyState() deliberately prevents. So a
    /// legacy pairing gets nothing. At current < turnLifecycleRevision the min is <
    /// the threshold, so this is dormant until the version bump.
    ///
    /// - `agentTyping` (TypingStatusModel): re-seeds the spinner. False during a
    ///   park (a park clears typing), which is correct - no spinner while waiting.
    /// - `turnInProgress` (TurnStatusModel): seeds turnLifecycle(.started) so the
    ///   phone's reply trigger is armed for a turn it joined mid-flight. Stays true
    ///   ACROSS a park (that is why TurnStatusModel exists), so a phone subscribing
    ///   during a park still fires when the turn eventually ends, rather than
    ///   dropping the reply on the trigger's turnStarted guard.
    /// Whether a peer consumes the explicit turnLifecycle event: BOTH ends must be
    /// at turnLifecycleRevision. The phone keys its "typing is spinner-only, drive
    /// boundaries off turnLifecycle" behavior on the MAC's revision, and a legacy
    /// phone lacks the gate entirely. The ONE predicate every turnLifecycle SEND
    /// site routes through - the subscribe seed (turnLifecycle(.started)) and the
    /// live-forward boundary (turnLifecycle(.ended)) - so they can't diverge: a
    /// phone seeded .started must be the same phone that later receives the live
    /// .ended, or the reply never fires.
    nonisolated static func peerConsumesTurnLifecycle(localRevision: Int, peerRevision: Int) -> Bool {
        min(localRevision, peerRevision) >= CompanionProtocolVersion.turnLifecycleRevision
    }

    nonisolated static func subscribeSnapshotMessages(chatID: String,
                                                      agentTyping: Bool,
                                                      turnInProgress: Bool,
                                                      localRevision: Int,
                                                      peerRevision: Int) -> [CompanionHostMessage] {
        guard peerConsumesTurnLifecycle(localRevision: localRevision, peerRevision: peerRevision) else {
            return []
        }
        var messages: [CompanionHostMessage] = []
        if agentTyping {
            messages.append(.typingStatus(isTyping: true, participant: .agent, chatID: chatID))
        }
        if turnInProgress {
            messages.append(.turnLifecycle(event: .started, chatID: chatID))
        }
        return messages
    }

    private func currentSelectionRange(_ textview: PTYTextView) -> CompanionSelectionRange? {
        guard let selection = textview.selection, selection.hasSelection else { return nil }
        let span = selection.spanningAbsRange
        let gridWidth = Int(textview.dataSource?.width() ?? 0)
        let end = Self.inclusiveSelectionEnd(exclusiveColumn: Int(span.end.x), absLine: span.end.y,
                                             gridWidth: gridWidth)
        return CompanionSelectionRange(
            start: CompanionSelectionPoint(absLine: span.start.y, column: Int(span.start.x)),
            end: CompanionSelectionPoint(absLine: end.absLine, column: end.column))
    }

    private func sendSelectionRange(streamID: UInt32, textview: PTYTextView) {
        let range = currentSelectionRange(textview)
        streams[streamID]?.lastSentSelectionRange = range
        RLog("Companion selectionRange push stream=\(streamID) range=\(range.map { "(\($0.start.column),\($0.start.absLine))..(\($0.end.column),\($0.end.absLine))" } ?? "none")")
        // Latest-wins state: ride the coalescing lane so a fast drag's updates
        // collapse to the newest and never starve the media frame that actually
        // shows the selection. Keyed per stream.
        outbox?.enqueueCoalescingControl(HostEnvelope(requestID: nil, payload: .selectionRange(streamID: streamID, range: range)),
                                         key: "selectionRange.\(streamID)")
    }

    private func handleCopySelection(guid: String, requestID: UInt64?) {
        let text = iTermController.sharedInstance().anySession(forReference: guid)?.textview?.selectedText
        send(.selectionText(text: text ?? ""), requestID: requestID)
    }

    /// Translate a phone scroll gesture (over an alt-screen app with mouse reporting)
    /// into terminal mouse-wheel reports. Resolves the session from the stream and
    /// drives the existing PTYSession primitive, which re-checks that reporting is
    /// enabled and caps the notch count, so a stale peer cannot inject bytes when the
    /// user has reporting off.
    private func handleReportScrollWheel(streamID: UInt32, up: Bool, lines: Int) {
        guard let context = streams[streamID],
              let session = iTermController.sharedInstance().anySession(forReference: context.guid) else {
            return
        }
        _ = session.reportScrollWheelForOrchestrator(up: up, lines: lines)
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
        // The phone may cap the bitrate; otherwise the streamer scales it to the
        // rendered resolution (a fixed rate collapses quality as the window grows).
        // A phone-supplied cap is only an upper bound: the resolution-aware target
        // still applies below it.
        let bitrateCeiling = params.maxBitrate.map { max(100_000, min($0, 40_000_000)) }
            ?? CompanionSessionStreamer.defaultBitrateCeiling
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
            bitrateCeiling: bitrateCeiling,
            onConfig: { config in
                outboxRef?.enqueueControl(HostEnvelope(requestID: nil, payload: .streamConfig(config)))
            },
            onMedia: { frame in
                outboxRef?.enqueueMedia(frame.encoded(version: mediaVersion))
            },
            onExtentChanged: { firstAbsLine, totalLines in
                // Latest-wins on the coalescing lane: only the newest window matters.
                outboxRef?.enqueueCoalescingControl(
                    HostEnvelope(requestID: nil,
                                 payload: .streamExtent(streamID: streamID, firstAbsLine: firstAbsLine, totalLines: totalLines)),
                    key: "streamExtent.\(streamID)")
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
        RLog("stream \(streamID) START guid=\(guid) fps=\(frameRate)")
        send(.streamStarted(CompanionStreamStarted(streamID: streamID, codec: .hevc)),
             requestID: requestID)
        // Tell the phone about any pre-existing selection on subscribe: the history
        // tiles are rendered with it, so the phone must know which tiles carry the
        // highlight to invalidate them correctly when the selection later changes.
        if let textview = session.textview {
            sendSelectionRange(streamID: streamID, textview: textview)
        }
    }

    private func driveStream(_ streamID: UInt32) {
        guard let context = streams[streamID] else { return }
        guard let session = iTermController.sharedInstance().anySession(forReference: context.guid) else {
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
        // A genuine generation bump (resize/reflow/font change) makes the phone
        // discard its selection, so the current range must be re-pushed even if its
        // value is unchanged, to restore the handles the phone dropped.
        let generation = context.streamer.currentGenerationId
        let generationBumped = generation != context.lastConfigGeneration
        context.lastConfigGeneration = generation
        // Detect a selection change from any source (mac-side Cmd-A/drag as well as
        // phone gestures) and push it, so the phone reloads the affected history
        // tiles; the live band already reflects it via the rendered video.
        if let textview = session.textview {
            let current = currentSelectionRange(textview)
            let decision = Self.selectionPushDecision(current: current,
                                                      lastSent: context.lastSentSelectionRange,
                                                      generationBumped: generationBumped)
            // Only forget an in-progress drag when the change came from ELSEWHERE (a
            // real value change: mac Cmd-A, a click). A bump-forced re-push of the
            // SAME value must NOT reset the drag, or a resize mid-drag would wipe the
            // anchor and collapse the selection to the cell under the finger.
            if decision.resetDragState {
                resetSelectionDragState(context)
            }
            if decision.push {
                sendSelectionRange(streamID: streamID, textview: textview)
            }
        }
        context.streamer.tick(nowMilliseconds: UInt64(max(0, CACurrentMediaTime() * 1000)))
    }

    private func endStream(_ streamID: UInt32, reason: CompanionStreamEndReason) {
        guard let context = streams.removeValue(forKey: streamID) else { return }
        RLog("stream \(streamID) END reason=\(reason)")
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
        // Snapshot current live state (unsolicited), so a turn already in flight
        // when the phone subscribes is reflected there. Sent after history in the
        // same synchronous main-actor block, so it strictly precedes any live
        // delivery from the subscription above. Gated on the peer's revision (see
        // subscribeSnapshotMessages) so a legacy phone can't mis-arm its reply
        // trigger from the snapshot.
        let agentTyping = TypingStatusModel.instance.isTyping(participant: .agent, chatID: chatID)
        let turnInProgress = TurnStatusModel.instance.inProgress(chatID: chatID)
        for message in Self.subscribeSnapshotMessages(chatID: chatID,
                                                       agentTyping: agentTyping,
                                                       turnInProgress: turnInProgress,
                                                       localRevision: CompanionProtocolVersion.current,
                                                       peerRevision: CompanionPushRegistry.peerRevision) {
            send(message, requestID: nil)
        }
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
        // A muted chat's messages never become notifications, even when another
        // chat's activity fired the wakeup. They still count toward the floor
        // targets above, so they are consumed silently rather than deferred
        // (unmuting does not retroactively notify).
        let mutedIDs = CompanionChatMuteRegistry.mutedChatIDs
        var mutedDropCounts = [String: Int]()
        for row in messageRows {
            if mutedIDs.contains(row.message.chatID) {
                mutedDropCounts[row.message.chatID, default: 0] += 1
                continue
            }
            infoByUniqueID[row.message.uniqueID] = (row.seq, row.message.sentDate)
            if byChat[row.message.chatID] == nil { chatOrder.append(row.message.chatID) }
            byChat[row.message.chatID, default: []].append(row.message)
        }
        if !mutedDropCounts.isEmpty {
            let detail = mutedDropCounts.sorted { $0.key < $1.key }
                .map { "\($0.key) x\($0.value)" }
                .joined(separator: ", ")
            RLog("Companion bridge: syncSince dropped muted-chat message(s): \(detail)")
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
        // Advance the global wakeup coordinator's record of how far the NSE has now
        // fetched, so its stateless render check reasons about the phone's real floor
        // and a trailing wakeup fires only if renderable content remains above it.
        CompanionWakeupCoordinator.shared.noteNSEFetch(messageFloor: messageFloorTarget,
                                                       alertFloor: alertFloorTarget,
                                                       messageReset: messageReset,
                                                       alertReset: alertReset)
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
        case .turnLifecycle(let event):
            // Forward only to a peer that CONSUMES turnLifecycle - the SAME predicate
            // the subscribe seed uses (peerConsumesTurnLifecycle), so the .started
            // seed and this live .ended can never diverge. Others infer boundaries
            // from the typing edges we still emit. Dormant until `current` reaches
            // turnLifecycleRevision (then min(current, peer) reduces to peer).
            guard Self.peerConsumesTurnLifecycle(localRevision: CompanionProtocolVersion.current,
                                                 peerRevision: CompanionPushRegistry.peerRevision) else {
                return
            }
            send(.turnLifecycle(event: event, chatID: chatID), requestID: nil)
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
            // Store the reload-durable stableID (mirroring ChatViewController.link)
            // so a phone-linked chat survives a shell reload that rotates the guid.
            let session = iTermController.sharedInstance().anySession(forReference: guid)
            let reference = session?.stableID ?? guid
            if terminal {
                try listModel.setTerminalGuid(for: chatID, to: reference)
            } else {
                try listModel.setBrowserGuid(for: chatID, to: reference)
            }
            let name = session?.name ?? guid
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
                  let session = iTermController.sharedInstance().anySession(forReference: guid) else {
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
        guard let session = iTermController.sharedInstance().anySession(forReference: guid),
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

    /// Render a scrollback tile addressed by absolute line for the live canvas.
    /// The request is clamped to what is currently available; the reply reports the
    /// range actually covered plus the current window (oldest absolute line + total
    /// lines), so the phone can size its canvas and resolve eviction races.
    private func handleFetchHistoryTile(streamID: UInt32,
                                        firstAbsLine: Int64,
                                        lineCount: Int,
                                        generationId: UInt32,
                                        requestID: UInt64?) {
        RLog("Companion historyTile req stream=\(streamID) firstAbs=\(firstAbsLine) lineCount=\(lineCount) gen=\(generationId)")
        guard let context = streams[streamID],
              let session = iTermController.sharedInstance().anySession(forReference: context.guid),
              let textview = session.textview else {
            RLog("Companion historyTile FAIL: no such stream \(streamID)")
            send(.error(CompanionError(code: .badRequest, message: "No such stream.")), requestID: requestID)
            return
        }
        let overflow = session.screen.totalScrollbackOverflow()
        let total = Int(session.screen.numberOfLines())
        let window = CompanionHistoryWindow(firstAbsLine: overflow, lineCount: total)
        // Entirely evicted (or empty): reply with a 0-line tile carrying the window
        // so the phone marks the region unavailable without erroring.
        guard let covered = window.clamped(absLine: firstAbsLine, count: min(lineCount, Self.maxContentLines)) else {
            RLog("Companion historyTile EVICTED firstAbs=\(firstAbsLine) window=[\(overflow),\(overflow + Int64(total))) -> 0 lines")
            send(.historyTile(CompanionHistoryTile(streamID: streamID, generationId: generationId,
                                                   firstAbsLine: max(firstAbsLine, overflow), lineCount: 0,
                                                   windowFirstAbsLine: overflow, windowLineCount: total,
                                                   pngData: Data())),
                 requestID: requestID)
            return
        }
        let relativeFirst = Int(covered.absLine - overflow)
        // Detached sessions (buried/parked) render zero lines; re-attach for the
        // render and restore after, as handleFetchSessionContent does.
        let wasDetached = textview.dataSource == nil
        if wasDetached { textview.dataSource = session.screen }
        defer { if wasDetached { textview.dataSource = nil } }
        let backgroundColor = session.processedBackgroundColor ?? .black
        // Render with the current selection so scrollback shows the same highlight
        // as the live band; the phone refetches affected tiles when it changes.
        guard let image = textview.renderImage(withLines: NSRange(location: relativeFirst, length: covered.count),
                                               includeMargins: false,
                                               backgroundColor: backgroundColor,
                                               showCursor: false,
                                               includeSelection: true) else {
            RLog("Companion historyTile FAIL render covered=[\(covered.absLine),+\(covered.count)) rel=\(relativeFirst) total=\(total) detached=\(wasDetached) frame=\(NSStringFromRect(textview.frame))")
            send(.error(CompanionError(code: .internalError, message: "Rendering the session content failed.")),
                 requestID: requestID)
            return
        }
        let pngData = image.dataForFile(of: .png)
        RLog("Companion historyTile OK covered=[\(covered.absLine),+\(covered.count)) overflow=\(overflow) total=\(total) bytes=\(pngData.count)")
        send(.historyTile(CompanionHistoryTile(streamID: streamID, generationId: generationId,
                                               firstAbsLine: covered.absLine, lineCount: covered.count,
                                               windowFirstAbsLine: overflow, windowLineCount: total,
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
                                            sessionGuid: session.stableID,
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
        let mutedIDs = CompanionChatMuteRegistry.mutedChatIDs
        RLog("Companion bridge: chat list (\(model.count) chat(s); muted: "
             + (mutedIDs.isEmpty ? "none" : mutedIDs.sorted().joined(separator: ", ")) + ")")
        var result = [CompanionChatListEntry]()
        for index in 0..<model.count {
            let chat = model.chat(at: index)
            result.append(CompanionChatListEntry(
                chat: chat,
                snippet: model.snippet(forChatID: chat.id, maxLength: Self.snippetLength),
                muted: mutedIDs.contains(chat.id)))
        }
        return result
    }

    private func entry(forChatID chatID: String) -> CompanionChatListEntry? {
        guard let chat = ChatListModel.instance?.chat(id: chatID) else { return nil }
        return CompanionChatListEntry(
            chat: chat,
            snippet: ChatListModel.instance?.snippet(forChatID: chatID,
                                                     maxLength: Self.snippetLength),
            muted: CompanionChatMuteRegistry.isMuted(chatID: chatID))
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
