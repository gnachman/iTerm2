//
//  CompanionLink.swift
//  iTerm2
//
//  The network endpoint of one phone connection, kept OFF the main actor.
//
//  A modal alert started from a main-queue callout freezes the main dispatch
//  queue and every @MainActor job until it is dismissed. CompanionHostBridge is
//  @MainActor because its handlers read and write app state, so on its own it
//  goes silent for the whole time such an alert is up. The link owns the parts
//  that must keep working regardless: the receive loop, the outbox drain, and
//  the few messages that can be answered without app state (hello, ping, and
//  the relay room secret a connecting phone sends before its hello).
//  Everything else is forwarded, in wire order, to the bridge through `events`,
//  where it simply waits until the main actor runs again.
//
//  Main-actor code talks to the link only through nonisolated, synchronous
//  calls (send, poke, close). It must never reach the link with `Task { await
//  link... }`: a task created on the main actor starts on the main actor, so it
//  would be stuck behind the very freeze this type exists to survive.
//

import Foundation
import QuartzCore
import CompanionProtocol
import os

/// Whether AI is available on this Mac right now, readable from any thread.
/// CompanionPairingController.aiAvailable() must run on the main thread, so the
/// main actor publishes its result here and the link reads the copy.
final class CompanionAIAvailabilityCache: Sendable {
    static let shared = CompanionAIAvailabilityCache(false)

    private let storage: OSAllocatedUnfairLock<Bool>

    init(_ value: Bool) {
        storage = OSAllocatedUnfairLock(initialState: value)
    }

    var value: Bool {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}

/// How a connection is classified for the presence warning. See
/// CompanionHostBridge.onConnectionClassified.
enum CompanionConnectionClassification: Equatable {
    case solicited
    case unsolicited
}

actor CompanionLink {
    enum Event {
        /// A decoded message from the phone, in wire order. `handledByLink` is
        /// true when the link already answered it (hello, ping, relayRoomSecret);
        /// the bridge then only does its bookkeeping and must not answer again.
        case envelope(ClientEnvelope, handledByLink: Bool)
        /// The link answered a hello. `blocked` is true when the peer is
        /// version-incompatible. Follows that hello's `.envelope`.
        case helloCompleted(peerRevision: Int, blocked: Bool)
        /// The hello just completed was incompatible. Follows `.helloCompleted`.
        case versionIncompatible(CompanionProtocolVersion.Compatibility)
        /// The connection ended. Always the last event. The error is nil for a
        /// deliberate local close and non-nil when the connection dropped.
        case closed(Error?)
    }

    /// Something the link should re-examine. Pokes carry no payload: the link
    /// rereads the current state and compares it with what it last sent, so a
    /// duplicated or reordered poke is harmless.
    enum Poke: Sendable {
        case aiAvailability
    }

    /// Outbound frames. Lock-protected, so main-actor code and encoder threads
    /// enqueue synchronously and enqueue order is wire order.
    nonisolated let outbox = CompanionPriorityOutbox<HostEnvelope>()

    /// Single consumer: the @MainActor bridge.
    nonisolated let events: AsyncStream<Event>

    /// State that nonisolated entry points and the drain task share with the
    /// actor. Never held across a suspension point.
    private struct Shared: Sendable {
        var started = false
        var localCloseRequested = false
        /// Set once the connection has ended; `closeError` is then final.
        var finished = false
        var closeError: Error?
        var closeWaiters: [CheckedContinuation<Error?, Never>] = []
        var drainTask: Task<Void, Never>?
        /// While true the drain sends the peer nothing but hello, error, and
        /// unpaired. Mirrors `versionBlocked` for the drain task, which is not
        /// on the actor. The bridge learns of a blocked peer through an event
        /// that lags while the main actor is busy; this closes that gap.
        var versionBlocked = false
    }

    private nonisolated let shared = OSAllocatedUnfairLock(initialState: Shared())
    private nonisolated let transport: MessageTransport
    private nonisolated let aiAvailability: CompanionAIAvailabilityCache
    private nonisolated let wantsNotificationPermission: @Sendable () -> Bool
    private nonisolated let storeRoomSecret: @Sendable (Data) throws -> Void
    private nonisolated let eventsContinuation: AsyncStream<Event>.Continuation
    private nonisolated let pokes: AsyncStream<Poke>
    private nonisolated let pokesContinuation: AsyncStream<Poke>.Continuation

    // Actor-isolated protocol state.
    private var helloSent = false
    private var versionBlocked = false
    /// The AI availability last advertised to this phone (seeded by the hello
    /// reply). nil until the first hello is answered.
    private var lastSentAIAvailable: Bool?

    init(transport: MessageTransport,
         aiAvailability: CompanionAIAvailabilityCache,
         wantsNotificationPermission: @escaping @Sendable () -> Bool,
         storeRoomSecret: @escaping @Sendable (Data) throws -> Void) {
        self.transport = transport
        self.aiAvailability = aiAvailability
        self.wantsNotificationPermission = wantsNotificationPermission
        self.storeRoomSecret = storeRoomSecret
        (events, eventsContinuation) = AsyncStream<Event>.makeStream()
        (pokes, pokesContinuation) = AsyncStream<Poke>.makeStream()
    }

    /// The production room secret store. The phone re-sends the secret on every
    /// connect, so skip the keychain write when it is the one already held.
    static let storeRoomSecretIfChanged: @Sendable (Data) throws -> Void = { secret in
        if CompanionMacIdentity.pairedRoomSecret() == secret {
            return
        }
        try CompanionMacIdentity.storePairedRoomSecret(secret)
    }

    // MARK: Nonisolated entry points

    /// Start receiving and sending. Safe to call from the main actor even if it
    /// is about to freeze: the tasks are detached, so none of them starts on
    /// the caller's actor.
    nonisolated func start() {
        let outbox = self.outbox
        let transport = self.transport
        let lock = self.shared
        let alreadyStarted = lock.withLock { state -> Bool in
            if state.started || state.finished {
                return true
            }
            state.started = true
            state.drainTask = Task.detached {
                await Self.drain(outbox: outbox, transport: transport, shared: lock)
            }
            return false
        }
        guard !alreadyStarted else { return }
        Task.detached { [self] in
            await self.receiveLoop()
        }
        Task.detached { [self] in
            for await poke in self.pokes {
                await self.handle(poke)
            }
        }
    }

    /// Enqueue one control message for the phone. Synchronous: call order is
    /// wire order among control frames.
    nonisolated func send(_ payload: CompanionHostMessage, requestID: UInt64?) {
        outbox.enqueueControl(HostEnvelope(requestID: requestID, payload: payload))
    }

    nonisolated func poke(_ kind: Poke) {
        pokesContinuation.yield(kind)
    }

    /// Close the connection without a farewell. Idempotent.
    nonisolated func close() {
        let (alreadyRequested, started) = shared.withLock { shared -> (Bool, Bool) in
            let result = (shared.localCloseRequested, shared.started)
            shared.localCloseRequested = true
            return result
        }
        guard !alreadyRequested else { return }
        outbox.finish()
        let transport = self.transport
        Task.detached {
            // When started, the receive loop sees this and reports the close.
            await transport.close()
        }
        if !started {
            // No receive loop is running to notice, so report it here.
            finish(error: nil)
        }
    }

    /// Send `.unpaired`, wait until it is on the wire, then close. The farewell
    /// reaches the phone even if it is version-blocked.
    nonisolated func sendFarewellAndClose() async {
        let (alreadyRequested, drainTask) = shared.withLock { shared -> (Bool, Task<Void, Never>?) in
            let result = (shared.localCloseRequested, shared.drainTask)
            shared.localCloseRequested = true
            return result
        }
        guard !alreadyRequested else { return }
        send(.unpaired, requestID: nil)
        outbox.finish()
        // The drain exits once it has sent everything enqueued before finish(),
        // including the farewell. Close only AFTER that: closing the transport
        // first would race the farewell against the connection teardown.
        await drainTask?.value
        DLog("Companion link: farewell flushed; closing transport")
        await transport.close()
        if drainTask == nil {
            finish(error: nil)
        }
    }

    /// Suspends until the connection has ended, then returns what `.closed`
    /// carried.
    nonisolated func waitUntilClosed() async -> Error? {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Error?, Never>) in
            let result = shared.withLock { shared -> (finished: Bool, error: Error?) in
                if shared.finished {
                    return (true, shared.closeError)
                }
                shared.closeWaiters.append(continuation)
                return (false, nil)
            }
            if result.finished {
                continuation.resume(returning: result.error)
            }
        }
    }

    // MARK: Drain

    private static func isAllowedWhileVersionBlocked(_ payload: CompanionHostMessage) -> Bool {
        switch payload {
        case .hello, .error, .unpaired:
            return true
        default:
            return false
        }
    }

    private static func drain(outbox: CompanionPriorityOutbox<HostEnvelope>,
                              transport: MessageTransport,
                              shared: OSAllocatedUnfairLock<Shared>) async {
        // Diagnostic counters/heartbeat. If a send wedges (half-open splice),
        // the heartbeat below stops logging while the link believes it is still
        // connected -- the signal we need.
        var mediaFrames = 0
        var mediaBytes = 0
        var controlFrames = 0
        var lastHeartbeat = CACurrentMediaTime()
        RLog("link outbox drain started")
        drain: while true {
            let data: Data
            let isMedia: Bool
            let item = await outbox.next()
            let blocked = shared.withLock { $0.versionBlocked }
            switch item {
            case .finished:
                break drain
            case .control(let envelope):
                isMedia = false
                if blocked && !isAllowedWhileVersionBlocked(envelope.payload) {
                    DLog("Companion link: dropping a frame for a version-blocked peer")
                    continue
                }
                do {
                    data = try WireCoding.encode(envelope)
                } catch {
                    RLog("Companion link: DROPPING unencodable envelope: \(error)")
                    continue
                }
            case .media(let payload):
                isMedia = true
                if blocked {
                    continue
                }
                // Control frames stay bare JSON; media frames carry the marker.
                data = CompanionFrameChannel.frameMedia(payload)
            }
            do {
                try await transport.send(data)
            } catch {
                RLog("link outbox send FAILED (outbox dead) after \(mediaFrames) media/\(controlFrames) control: \(error)")
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
                RLog("link outbox alive: sent \(mediaFrames) media (\(mediaBytes) B), \(controlFrames) control")
                lastHeartbeat = now
            }
        }
        RLog("link outbox drained/exited: \(mediaFrames) media, \(controlFrames) control total")
    }

    // MARK: Receive

    private func receiveLoop() async {
        // If the relay splice goes half-open during streaming, receive() can
        // block forever -- we'd see "started" but never "receive FAILED" or
        // "exited", confirming the wedge (no teardown, no re-park).
        RLog("link receiveLoop started")
        let dropError: Error
        while true {
            let frame: Data
            do {
                frame = try await transport.receive()
            } catch {
                RLog("link receiveLoop receive() ended: \(error)")
                dropError = error
                break
            }
            guard let envelope = try? WireCoding.decode(ClientEnvelope.self, from: frame) else {
                // A frame we cannot decode (newer phone) is dropped, not fatal.
                continue
            }
            handle(envelope)
        }
        let closedLocally = shared.withLock { $0.localCloseRequested }
        RLog("link receiveLoop exited (closedLocally=\(closedLocally))")
        outbox.finish()
        finish(error: closedLocally ? nil : dropError)
    }

    private func handle(_ envelope: ClientEnvelope) {
        let requestID = envelope.requestID
        // An incompatible peer is served nothing but a re-hello: the phone shows
        // an upgrade panel and disconnects, but refuse here too so a stale peer
        // cannot drive an out-of-date protocol.
        if versionBlocked {
            if case .hello(let revision, let minimumPeer) = envelope.payload {
                handleHello(envelope, peerRevision: revision, peerMinimumPeer: minimumPeer)
            } else {
                send(.error(CompanionError(code: .badRequest, message: "Companion app upgrade required")),
                     requestID: requestID)
            }
            return
        }
        switch envelope.payload {
        case .hello(let revision, let minimumPeer):
            handleHello(envelope, peerRevision: revision, peerMinimumPeer: minimumPeer)
        case .ping:
            send(.pong, requestID: requestID)
            eventsContinuation.yield(.envelope(envelope, handledByLink: true))
        case .relayRoomSecret(let secret):
            // A connecting phone couriers this BEFORE its hello and waits for
            // the ack, so it has to be answered here or the phone could never
            // reach hello while the main actor is frozen.
            // Persist the secret so the mac can sign its relay parks, then ack so
            // the phone may register its verifier. Idempotent (re-sent every
            // connect); a store failure simply withholds the ack, and the phone
            // retries on the next connection.
            do {
                try storeRoomSecret(secret)
                RLog("Companion link: stored relay room secret")
                send(.relayRoomSecretStored, requestID: requestID)
            } catch {
                RLog("Companion link: failed to store room secret: \(error)")
                send(.error(CompanionError(code: .internalError, message: "\(error)")),
                     requestID: requestID)
            }
            eventsContinuation.yield(.envelope(envelope, handledByLink: true))
        default:
            eventsContinuation.yield(.envelope(envelope, handledByLink: false))
        }
    }

    private func handleHello(_ envelope: ClientEnvelope, peerRevision: Int, peerMinimumPeer: Int) {
        let aiAvailable = aiAvailability.value
        let verdict = CompanionProtocolVersion.evaluate(peerRevision: peerRevision,
                                                        peerMinimumPeer: peerMinimumPeer)
        let blocked = (verdict != .compatible)
        // Update the gate BEFORE enqueueing the reply, so nothing queued behind
        // the reply can slip out to a peer that was just found incompatible.
        versionBlocked = blocked
        shared.withLock { $0.versionBlocked = blocked }
        // The reply carries the current availability, and seeds the value later
        // change events are compared against. handle(_: Poke) does nothing until
        // helloSent, so an aiAvailabilityChanged can never precede this reply.
        lastSentAIAvailable = aiAvailable
        helloSent = true
        send(.hello(revision: CompanionProtocolVersion.current,
                    minimumPeer: CompanionProtocolVersion.minimumPeer,
                    wantsNotificationPermission: wantsNotificationPermission(),
                    aiAvailable: aiAvailable),
             requestID: envelope.requestID)
        RLog("Companion link: hello peer(rev=\(peerRevision), min=\(peerMinimumPeer)) -> \(verdict)")
        eventsContinuation.yield(.envelope(envelope, handledByLink: true))
        eventsContinuation.yield(.helloCompleted(peerRevision: peerRevision, blocked: blocked))
        if blocked {
            eventsContinuation.yield(.versionIncompatible(verdict))
        }
    }

    // MARK: Pokes

    private func handle(_ poke: Poke) {
        switch poke {
        case .aiAvailability:
            // No-op before the first hello: the hello reply carries the current
            // availability. After it, send only when the value actually changed,
            // so unrelated settings writes on the mac do not spam the phone.
            guard helloSent, let lastSentAIAvailable else { return }
            let available = aiAvailability.value
            guard available != lastSentAIAvailable else { return }
            self.lastSentAIAvailable = available
            RLog("Companion link: AI availability changed to \(available); notifying phone")
            send(.aiAvailabilityChanged(available: available), requestID: nil)
        }
    }

    // MARK: Ending

    /// Report the end of the connection, once. Later calls do nothing.
    private nonisolated func finish(error: Error?) {
        let waiters = shared.withLock { shared -> [CheckedContinuation<Error?, Never>]? in
            if shared.finished {
                return nil
            }
            shared.finished = true
            shared.closeError = error
            let waiters = shared.closeWaiters
            shared.closeWaiters = []
            return waiters
        }
        guard let waiters else { return }
        eventsContinuation.yield(.closed(error))
        eventsContinuation.finish()
        pokesContinuation.finish()
        for waiter in waiters {
            waiter.resume(returning: error)
        }
    }
}

extension CompanionHostBridge {
    /// How a link event classifies the connection for the presence warning, or
    /// nil when it does not classify it at all. The bridge applies the first
    /// non-nil result of a connection and ignores the rest.
    ///
    /// - hello is neutral, and so is `.helloCompleted`: the phone's notification
    ///   extension says hello before it presents its push nonce, and classifying
    ///   at hello would warn the user about their own Mac's fetch.
    /// - messagesSince and syncSince are solicited only with a nonce that
    ///   `nonceIsOutstanding` recognizes.
    /// - An incompatible hello counts as solicited so the presence toast does
    ///   not appear on top of the upgrade alert.
    /// - Every other request, including a ping the link already answered, is
    ///   interactive use of the phone: unsolicited.
    nonisolated static func connectionClassification(
        for event: CompanionLink.Event,
        nonceIsOutstanding: (String) -> Bool) -> CompanionConnectionClassification? {
        switch event {
        case .helloCompleted, .closed:
            return nil
        case .versionIncompatible:
            return .solicited
        case .envelope(let envelope, _):
            switch envelope.payload {
            case .hello:
                return nil
            case .messagesSince(_, _, _, let nonce), .syncSince(_, _, _, let nonce):
                let solicited = nonce.map { nonceIsOutstanding($0) } ?? false
                return solicited ? .solicited : .unsolicited
            default:
                return .unsolicited
            }
        }
    }
}
