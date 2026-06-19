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

/// A keepalive that pings the socket every 15s, comfortably under the observed
/// ~30s idle-reap window, so a parked or quiet relay socket stays up. The ping
/// reports failure once the socket is gone, which ends the loop.
private func relayKeepalive(for ws: RelayWebSocket) -> RelayKeepalive {
    RelayKeepalive(intervalNanos: 15_000_000_000) { [weak ws] in
        guard let ws else { return false }
        return await ws.sendPing()
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

    init(ws: RelayWebSocket,
         firstFrame: Data? = nil,
         registrationToken: String? = nil,
         keepalive: RelayKeepalive? = nil) {
        self.ws = ws
        self.pendingFirstFrame = firstFrame
        self.registrationToken = registrationToken
        self.keepalive = keepalive
    }

    public func send(_ frame: Data) async throws {
        do {
            try await ws.send(.data(frame))
        } catch {
            signalClosed()
            throw TransportError.closed
        }
    }

    public func receive() async throws -> Data {
        if let buffered = lock.withLock({ () -> Data? in
            defer { pendingFirstFrame = nil }
            return pendingFirstFrame
        }) {
            return buffered
        }
        let message: RelayWebSocketMessage
        do {
            message = try await ws.receive()
        } catch {
            signalClosed()
            throw TransportError.closed
        }
        switch message {
        case .data(let data):
            return data
        case .text:
            // Post-admission frames are always binary; a text frame here is the
            // relay closing or a protocol error.
            signalClosed()
            throw TransportError.malformedFrame
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
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>]? in
            if closeSignaled { return nil }
            closeSignaled = true
            let w = closeWaiters
            closeWaiters = []
            return w
        }
        guard let waiters else { return }
        // The connection is gone: stop pinging it (idempotent).
        keepalive?.stop()
        for w in waiters { w.resume() }
    }

    deinit {
        if !closed {
            ws.cancel()
        }
        signalClosed()
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
                joinProof: (@Sendable (RelayAdmission.Challenge, String) throws -> RelayAdmission.Proof)? = nil) {
        self.relayOrigin = relayOrigin
        self.roomName = roomName
        self.webSocketFactory = webSocketFactory
        self.onParked = onParked
        self.joinProof = joinProof
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
            // and the room silently loses its mac.
            let keepalive = relayKeepalive(for: ws)
            keepalive.start()
            // Block until the phone actually joins and sends its first frame (Noise
            // msg1), so the combined listener doesn't treat an empty parked room as
            // an inbound connection.
            let firstMessage: RelayWebSocketMessage
            do {
                firstMessage = try await ws.receive()
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
