//
//  RelayTransport.swift
//  CompanionCore
//
//  A MessageTransport that reaches the peer through the Cloudflare room relay
//  instead of the local network. Both devices open an outbound WebSocket to
//  the relay (so no inbound firewall holes are needed), complete the relay's
//  admission handshake, and are then spliced together; from that point the
//  WebSocket carries opaque binary frames exactly like any other transport,
//  and the Noise + RPC layers ride on top unchanged. The relay sees only
//  ciphertext. See docs/companion-relay-design.md.
//
//  Admission frames are JSON text messages (Hello/Challenge/Proof/Result);
//  once admitted, every frame is a binary WebSocket message = one transport
//  frame (the WS layer provides boundaries, so no length-prefix framing is
//  needed here).
//

import Foundation
import CompanionProtocol

/// The default keepalive ping interval: 15s, comfortably under the observed
/// ~30s idle-reap window, so a parked or quiet relay socket stays up. Public so
/// it can be the default for RelayTransportListener's public init.
public let relayKeepaliveDefaultIntervalNanos: UInt64 = 15_000_000_000

/// A keepalive that pings the socket so a parked or quiet relay socket is not
/// reaped by the edge. CRUCIALLY, when a ping fails it CANCELS the socket: a
/// half-open connection (after sleep/wake, a Wi-Fi change, or the edge reaping
/// the socket without a close frame) leaves a parked `receive()` blocked
/// forever with no error, so without this teardown the mac's accept() never
/// throws and the error-driven reconnect path never engages - the documented
/// "the normal receive()/accept() path surfaces the failure" contract.
/// Cancelling only a confirmed-dead socket never displaces a live bridge.
private func relayKeepalive(for ws: RelayWebSocket,
                            intervalNanos: UInt64 = relayKeepaliveDefaultIntervalNanos) -> RelayKeepalive {
    RelayKeepalive(intervalNanos: intervalNanos) { [weak ws] in
        guard let ws else { return false }
        if await ws.sendPing() {
            // Confirms the WS-to-edge link is alive. If this keeps logging
            // while the relay reports "mac offline", the splice/park died but the
            // socket did not -- the half-open-at-the-app-layer wedge.
            CompanionLog.log("relay keepalive ping ok")
            return true
        }
        // Ping failed -> the socket is dead. Tear it down so the parked
        // receive()/accept() throws and the caller's retry path engages.
        CompanionLog.log("relay keepalive ping FAILED -> cancelling socket")
        ws.cancel()
        return false
    }
}

/// One spliced relay connection, presented as a MessageTransport. The optional
/// pre-buffered first frame lets the responder (mac) return from accept() only
/// once the peer has actually sent something, matching local-network accept
/// semantics.
public final class RelayTransport: MessageTransport, @unchecked Sendable {
    /// The one-time relay registration token the DO minted at admission (phone
    /// role only). The phone presents it to /register to register its verifier;
    /// nil for the mac and for already-established rooms that mint none.
    public let registrationToken: String?

    private let ws: RelayWebSocket
    // Pings the socket so an idle splice (or a parked mac) is not reaped by the
    // edge. Stopped whenever the connection is signaled closed.
    private let keepalive: RelayKeepalive?
    private let lock = UnfairLock()
    private var pendingFirstFrame: Data?
    private var closed = false
    // Resolved once the connection is known to be gone (close() called, or a
    // receive/ error). Lets the mac listener wait for a live connection to end
    // before it parks again (see RelayTransportListener.accept).
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []
    private var closeSignaled = false
    // Waiters that receive() races the socket read against, so a close (e.g. from a
    // keepalive-detected death) unblocks an in-flight read even when ws.receive()
    // does not throw on cancel. Distinct from closeWaiters because these resume
    // WITHOUT side effects on the awaiter's cancellation (a normal read losing the
    // race must not signal the connection closed).
    private var closeAwaitWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var nextCloseAwaitID = 0

    init(ws: RelayWebSocket,
         firstFrame: Data? = nil,
         registrationToken: String? = nil,
         keepalive: RelayKeepalive? = nil) {
        self.ws = ws
        self.pendingFirstFrame = firstFrame
        self.registrationToken = registrationToken
        self.keepalive = keepalive
        // A keepalive-detected death hard-closes this transport so the bridge's
        // receive() unblocks and its owner re-parks; otherwise the mac goes
        // silently dark (present in its own mind, "offline" to the relay).
        keepalive?.setOnDeath { [weak self] in self?.cancelAndSignalClosed() }
    }

    public func send(_ frame: Data) async throws {
        // Once the connection is known gone, fail fast so the outbox stops feeding
        // a dead socket (whose buffered writes can otherwise "succeed" silently).
        if lock.withLock({ closeSignaled }) { throw TransportError.closed }
        do {
            try await ws.send(.data(frame))
        } catch {
            signalClosed()
            // Preserve a quota close (not transient churn) so the reconnect logic
            // can back off; everything else is the ordinary "connection gone".
            throw (error as? TransportError) == .quotaExceeded ? TransportError.quotaExceeded : TransportError.closed
        }
    }

    public func receive() async throws -> Data {
        if let buffered = lock.withLock({ () -> Data? in
            defer { pendingFirstFrame = nil }
            return pendingFirstFrame
        }) {
            return buffered
        }
        // Race the socket read against the close signal: a keepalive-detected death
        // (or close()) must unblock this even when ws.receive() does not throw on
        // cancel, which is what left the mac wedged streaming into a dead socket. A
        // task group is unusable here because it awaits its children on exit, so a
        // ws.receive() that ignores cancellation would still hang the group; instead
        // resume a one-shot continuation from whichever finishes first and abandon
        // the loser (it ends when the socket actually closes; bounded, once).
        let race = ReceiveRace()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            race.read = Task { [weak self] in
                await race.ready()
                guard let self else {
                    if race.claim() { cont.resume(throwing: TransportError.closed) }
                    return
                }
                do {
                    let message = try await self.ws.receive()
                    guard race.claim() else { return }
                    race.close?.cancel()
                    switch message {
                    case .data(let data):
                        cont.resume(returning: data)
                    case .text:
                        // Post-admission frames are always binary; a text frame is
                        // the relay closing or a protocol error.
                        self.signalClosed()
                        cont.resume(throwing: TransportError.malformedFrame)
                    }
                } catch {
                    guard race.claim() else { return }
                    race.close?.cancel()
                    self.signalClosed()
                    // Preserve a quota close so the caller (session/bridge receive
                    // loop) can back off instead of fast-retrying; else "gone".
                    cont.resume(throwing: (error as? TransportError) == .quotaExceeded
                                ? TransportError.quotaExceeded : TransportError.closed)
                }
            }
            race.close = Task { [weak self] in
                await race.ready()
                await self?.awaitClosed()
                guard race.claim() else { return }
                race.read?.cancel()
                cont.resume(throwing: TransportError.closed)
            }
            race.start()
        }
    }

    /// Resolve when the connection is signaled closed. Unlike waitUntilClosed(),
    /// cancelling the awaiting task (the loser of receive()'s race) just removes
    /// the waiter and resumes it -- it does NOT signal the connection closed, so a
    /// normal read winning the race cannot tear the connection down.
    private func awaitClosed() async {
        let id = lock.withLock { () -> Int in
            nextCloseAwaitID += 1
            return nextCloseAwaitID
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let alreadyClosed = lock.withLock { () -> Bool in
                    if closeSignaled { return true }
                    closeAwaitWaiters[id] = cont
                    return false
                }
                if alreadyClosed { cont.resume() }
            }
        } onCancel: {
            if let cont = lock.withLock({ closeAwaitWaiters.removeValue(forKey: id) }) {
                cont.resume()
            }
        }
    }

    public func close() async {
        cancelAndSignalClosed()
    }

    /// Resolves when this connection is gone. Returns immediately if it already
    /// is. Never throws. Also returns if the awaiting task is cancelled, so a
    /// listener tearing down can unblock an accept() that is waiting on a still
    /// live connection without having to close that connection.
    func waitUntilClosed() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let alreadyClosed = lock.withLock { () -> Bool in
                    if closeSignaled { return true }
                    closeWaiters.append(cont)
                    return false
                }
                if alreadyClosed { cont.resume() }
            }
        } onCancel: {
            // Resolve waiters; does not cancel the socket, so a live connection
            // handed to a bridge keeps working.
            signalClosed()
        }
    }

    /// Cancel the socket and mark the connection gone. Idempotent; safe to call
    /// from synchronous teardown (listener.stop()).
    func cancelAndSignalClosed() {
        let shouldCancel = lock.withLock { () -> Bool in
            if closed { return false }
            closed = true
            return true
        }
        if shouldCancel {
            ws.cancel()
        }
        signalClosed()
    }

    private func signalClosed() {
        let resumed = lock.withLock { () -> ([CheckedContinuation<Void, Never>],
                                             [CheckedContinuation<Void, Never>])? in
            if closeSignaled { return nil }
            closeSignaled = true
            let w = closeWaiters
            closeWaiters = []
            let a = Array(closeAwaitWaiters.values)
            closeAwaitWaiters = [:]
            return (w, a)
        }
        guard let (waiters, awaitWaiters) = resumed else { return }
        // The connection is gone: stop pinging it (idempotent).
        keepalive?.stop()
        for w in waiters { w.resume() }
        for w in awaitWaiters { w.resume() }
    }

    deinit {
        if !closed {
            ws.cancel()
        }
        signalClosed()
    }
}

/// One-shot arbiter for receive()'s read-vs-close race: the first of the two
/// tasks to claim() wins and resumes the continuation; the other backs off. Holds
/// both tasks so the winner can cancel the loser.
///
/// An unstructured Task can begin executing on another thread before the assignment
/// `race.close = Task {...}` finishes on the spawning thread, so a task must not
/// touch its peer reference until BOTH are stored. Each arm therefore awaits
/// `ready()` (opened by `start()` after both assignments) before doing its work;
/// once past that gate the winner always observes and cancels its peer.
final class ReceiveRace: @unchecked Sendable {
    private let lock = UnfairLock()
    private var done = false
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    var read: Task<Void, Never>?
    var close: Task<Void, Never>?

    func claim() -> Bool {
        lock.withLock {
            if done { return false }
            done = true
            return true
        }
    }

    /// Open the gate after both `read` and `close` have been assigned.
    func start() {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            started = true
            let w = startWaiters
            startWaiters = []
            return w
        }
        for w in waiters { w.resume() }
    }

    /// Suspend until `start()` opens the gate, so a task never reads a peer
    /// reference that has not been assigned yet.
    func ready() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let already = lock.withLock { () -> Bool in
                if started { return true }
                startWaiters.append(cont)
                return false
            }
            if already { cont.resume() }
        }
    }
}

/// A one-shot awaitable used while a mac is parked (before a RelayTransport exists
/// to own the close signal): the keepalive fires it when a ping fails, unblocking
/// the parked read even on a half-open socket that ignores ws.cancel().
private final class ParkedDeathSignal: @unchecked Sendable {
    private let lock = UnfairLock()
    private var fired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func fire() {
        let toResume = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            if fired { return [] }
            fired = true
            let w = waiters
            waiters = []
            return w
        }
        for w in toResume { w.resume() }
    }

    func wait() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let already = lock.withLock { () -> Bool in
                    if fired { return true }
                    waiters.append(cont)
                    return false
                }
                if already { cont.resume() }
            }
        } onCancel: {
            fire()
        }
    }
}

/// Race a parked socket read against a keepalive-detected death, so a hard network
/// drop fails the parked accept() instead of hanging forever. Mirrors
/// RelayTransport.receive(): a task group is unusable (it awaits its children on
/// exit, so a receive() ignoring cancellation would still hang it), so resume a
/// one-shot continuation from whichever finishes first and abandon the loser.
private func receiveParked(ws: RelayWebSocket, death: ParkedDeathSignal) async throws -> RelayWebSocketMessage {
    let race = ReceiveRace()
    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<RelayWebSocketMessage, Error>) in
        race.read = Task {
            await race.ready()
            do {
                let message = try await ws.receive()
                guard race.claim() else { return }
                race.close?.cancel()
                cont.resume(returning: message)
            } catch {
                guard race.claim() else { return }
                race.close?.cancel()
                cont.resume(throwing: error)
            }
        }
        race.close = Task {
            await race.ready()
            await death.wait()
            guard race.claim() else { return }
            race.read?.cancel()
            cont.resume(throwing: TransportError.closed)
        }
        race.start()
    }
}

/// Shared admission: open a WebSocket to the relay room and run the
/// Hello -> Challenge -> Proof -> Result handshake. Returns the Result and the
/// connected task on success.
enum RelayAdmissionClient {
    /// The admission protocol version this build speaks.
    static let protocolVersion = 1

    /// Builds the WebSocket URL for a relay origin. Production origins are
    /// https:// -> wss://; http://localhost is allowed (ws://) for `wrangler
    /// dev` integration tests. The https-only policy is enforced upstream when
    /// the relay origin is parsed from the QR (PairingCode).
    static func socketURL(relayOrigin: String) throws -> URL {
        if relayOrigin.hasPrefix("https://"),
           let url = URL(string: "wss://" + relayOrigin.dropFirst("https://".count) + "/") {
            return url
        }
        if relayOrigin.hasPrefix("http://"),
           let url = URL(string: "ws://" + relayOrigin.dropFirst("http://".count) + "/") {
            return url
        }
        throw TransportError.connectionFailed("Invalid relay origin: \(relayOrigin)")
    }

    /// Run admission on a freshly created (un-resumed) socket. `proofFor` is given
    /// the Challenge and returns the Proof to send.
    static func admit(
        ws: RelayWebSocket,
        role: RelayAdmission.Role,
        nonDisplacing: Bool = false,
        proofFor: (RelayAdmission.Challenge) throws -> RelayAdmission.Proof
    ) async throws -> RelayAdmission.Result {
        ws.resume()

        // Pass nil (not false) when displacing so the field is omitted: the wire
        // stays identical to pre-nonDisplacing clients and older relays.
        try await sendJSON(ws, RelayAdmission.Hello(v: protocolVersion,
                                                    role: role,
                                                    nonDisplacing: nonDisplacing ? true : nil))
        let challenge: RelayAdmission.Challenge = try await receiveJSON(ws)
        let proof = try proofFor(challenge)
        try await sendJSON(ws, proof)
        let result: RelayAdmission.Result = try await receiveJSON(ws)
        guard result.ok else {
            ws.cancel()
            throw TransportError.connectionFailed("Relay refused admission: \(result.error ?? "unknown")")
        }
        return result
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static func sendJSON<T: Encodable>(_ ws: RelayWebSocket, _ value: T) async throws {
        let data = try encoder.encode(value)
        let text = String(decoding: data, as: UTF8.self)
        try await ws.send(.text(text))
    }

    private static func receiveJSON<T: Decodable>(_ ws: RelayWebSocket) async throws -> T {
        let data: Data
        switch try await ws.receive() {
        case .text(let s): data = Data(s.utf8)
        case .data(let d): data = d
        }
        return try decoder.decode(T.self, from: data)
    }
}

/// Phone side: connect to the relay room and join as the phone. For first-time
/// pairing the proof is empty (open mode); a `joinProof` closure can supply a
/// signature for reconnecting to an established room.
public struct RelayTransportConnector: TransportConnector {
    public let transportName = "relay"
    private let relayOrigin: String
    private let responderStaticKey: Data
    private let joinProof: (@Sendable (RelayAdmission.Challenge, _ roomName: String) throws -> RelayAdmission.Proof)?
    private let nonDisplacing: Bool
    private let webSocketFactory: RelayWebSocketFactory

    /// - responderStaticKey: the mac's static public key (rs from the QR),
    ///   needed to derive the room pseudonym.
    /// - joinProof: nil for pairing (empty proof); supply for established-room
    ///   reconnects to return a signed proof.
    /// - nonDisplacing: when true, the relay rejects the join if the phone slot
    ///   is occupied instead of displacing it. Set only by the NSE, so it yields
    ///   to a foreground app; the app uses the default (false) and reclaims the
    ///   slot.
    /// - webSocketFactory: supplies the outbound socket; defaults to URLSession.
    public init(relayOrigin: String,
                responderStaticKey: Data,
                joinProof: (@Sendable (RelayAdmission.Challenge, String) throws -> RelayAdmission.Proof)? = nil,
                nonDisplacing: Bool = false,
                webSocketFactory: RelayWebSocketFactory = URLSessionRelayWebSocketFactory()) {
        self.relayOrigin = relayOrigin
        self.responderStaticKey = responderStaticKey
        self.joinProof = joinProof
        self.nonDisplacing = nonDisplacing
        self.webSocketFactory = webSocketFactory
    }

    public func connect(to rendezvous: PairingRendezvous,
                        timeout: TimeInterval) async throws -> MessageTransport {
        let roomName = RelayRoom.name(responderStaticPublicKey: responderStaticKey,
                                      pairingID: rendezvous.pairingID)
        let url = try RelayAdmissionClient.socketURL(relayOrigin: relayOrigin)
        let ws = webSocketFactory.makeWebSocket(url: url,
                                                headers: ["x-relay-room": roomName],
                                                timeout: timeout)
        // In a transport race, the loser's task is cancelled; tear the socket
        // down so a half-open relay join doesn't linger (and free the room slot).
        return try await withTaskCancellationHandler {
            let result = try await RelayAdmissionClient.admit(ws: ws,
                                                              role: .phone,
                                                              nonDisplacing: nonDisplacing) { challenge in
                try joinProof?(challenge, roomName) ?? RelayAdmission.Proof(ticket: nil, signature: nil)
            }
            let keepalive = relayKeepalive(for: ws)
            keepalive.start()
            return RelayTransport(ws: ws, registrationToken: result.registrationToken, keepalive: keepalive)
        } onCancel: {
            ws.cancel()
        }
    }
}

/// Mac side: park in the relay room as the mac, then wait for the phone to send
/// its first frame before returning, so accept() resolves only when a peer is
/// actually present (matching local-network accept semantics).
///
/// The relay room has exactly one mac slot, and a new park displaces the
/// current holder (newest-wins). So unlike a local-network listener, this one
/// must NOT park again while a connection it already handed out is still live,
/// or it would displace its own bridge. accept() therefore serializes: the
/// second and later calls wait for the previously-issued transport to close
/// before parking. A reconnecting phone is surfaced when that transport ends
/// (the relay closes the mac socket once the phone's side goes away).
public final class RelayTransportListener: TransportListener, @unchecked Sendable {
    public let transportName = "relay"
    private let relayOrigin: String
    private let roomName: String
    private let webSocketFactory: RelayWebSocketFactory
    private let onParked: (@Sendable () -> Void)?
    private let joinProof: (@Sendable (RelayAdmission.Challenge, _ roomName: String) throws -> RelayAdmission.Proof)?
    private let keepaliveIntervalNanos: UInt64
    private let lock = UnfairLock()
    private var stopped = false
    private var current: RelayWebSocket?
    private var previous: RelayTransport?

    /// - onParked: invoked once admission completes and the listener is parked
    ///   in the room (before it blocks awaiting the peer's first frame). The
    ///   mac is now reachable through the relay; the phone may join.
    /// - joinProof: signs the mac's park for an established room (where the relay
    ///   requires every join to be signed); nil/empty for pairing-mode rooms.
    /// - webSocketFactory: supplies the outbound socket; defaults to URLSession.
    public init(relayOrigin: String,
                roomName: String,
                webSocketFactory: RelayWebSocketFactory = URLSessionRelayWebSocketFactory(),
                onParked: (@Sendable () -> Void)? = nil,
                joinProof: (@Sendable (RelayAdmission.Challenge, String) throws -> RelayAdmission.Proof)? = nil,
                keepaliveIntervalNanos: UInt64 = relayKeepaliveDefaultIntervalNanos) {
        self.relayOrigin = relayOrigin
        self.roomName = roomName
        self.webSocketFactory = webSocketFactory
        self.onParked = onParked
        self.joinProof = joinProof
        self.keepaliveIntervalNanos = keepaliveIntervalNanos
    }

    public func accept() async throws -> MessageTransport {
        if lock.withLock({ stopped }) {
            throw TransportError.closed
        }
        // One mac slot, newest-wins: do not park again until the connection we
        // last handed out has ended, or we would displace our own live bridge.
        // The wait returns on cancellation too (stop() cancels the accept task),
        // and crucially does NOT close that live connection.
        if let prev = lock.withLock({ previous }) {
            await prev.waitUntilClosed()
        }
        if Task.isCancelled || lock.withLock({ stopped }) {
            throw TransportError.closed
        }
        let url = try RelayAdmissionClient.socketURL(relayOrigin: relayOrigin)
        let ws = webSocketFactory.makeWebSocket(url: url,
                                                headers: ["x-relay-room": roomName],
                                                timeout: nil)
        // `current` is the in-flight park (a socket being admitted / awaiting the
        // peer's first frame), NOT a handed-out connection. It is cleared the
        // moment accept() returns, so stop() never cancels a live bridge.
        lock.withLock { current = ws }

        // In a combined-listener race, the loser's accept task is cancelled;
        // tear the parked socket down so the mac releases the room's mac slot
        // instead of leaving a dangling park.
        let deathSignal = ParkedDeathSignal()
        return try await withTaskCancellationHandler {
            defer { lock.withLock { if current === ws { current = nil } } }
            _ = try await RelayAdmissionClient.admit(ws: ws, role: .mac) { challenge in
                try joinProof?(challenge, roomName) ?? RelayAdmission.Proof(ticket: nil, signature: nil)
            }
            // Parked: the mac now holds the mac slot and is reachable through the
            // relay. Signal before blocking, since the next step waits on the peer.
            onParked?()
            // Keep the parked socket alive while it waits, possibly long, for the
            // phone to scan and send msg1; otherwise the edge reaps it (~30s idle)
            // and the room silently loses its mac. A failed ping cancels the socket,
            // and its death fires the signal below, so this parked receive() throws
            // even on a half-open socket that ignores cancellation (a hard network
            // drop) instead of hanging forever. There is no RelayTransport yet to own
            // the close signal, so the park wires the keepalive's death directly.
            let keepalive = relayKeepalive(for: ws, intervalNanos: keepaliveIntervalNanos)
            keepalive.setOnDeath { deathSignal.fire() }
            keepalive.start()
            // Block until the phone actually joins and sends its first frame (Noise
            // msg1), so the combined listener doesn't treat an empty parked room as
            // an inbound connection.
            let firstMessage: RelayWebSocketMessage
            do {
                firstMessage = try await receiveParked(ws: ws, death: deathSignal)
            } catch {
                keepalive.stop()
                throw error
            }
            let firstFrame: Data
            switch firstMessage {
            case .data(let d): firstFrame = d
            case .text: keepalive.stop(); throw TransportError.malformedFrame
            }
            let transport = RelayTransport(ws: ws, firstFrame: firstFrame, keepalive: keepalive)
            lock.withLock { previous = transport }
            return transport
        } onCancel: {
            ws.cancel()
            // Unblock the parked read even if the socket ignores cancel.
            deathSignal.fire()
        }
    }

    public func stop() {
        // Cancel only the in-flight park, never a handed-out (live) connection:
        // that one belongs to the bridge, which tears it down on its own. A
        // blocked accept() is unblocked by cancelling its task (the acceptLoop
        // does this), which makes waitUntilClosed return.
        let ws = lock.withLock { () -> RelayWebSocket? in
            stopped = true
            let w = current
            current = nil
            previous = nil
            return w
        }
        ws?.cancel()
    }
}
