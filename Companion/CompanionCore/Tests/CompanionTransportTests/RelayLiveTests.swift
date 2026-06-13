//
//  RelayLiveTests.swift
//  CompanionCore
//
//  End-to-end live test of the relay path: a Mac (responder) and a phone
//  (initiator) connect through a real running relay Worker, complete a Noise
//  XK handshake over the splice, and round-trip an encrypted message. The
//  relay only ever sees ciphertext.
//
//  Gated on the RELAY_TEST_ORIGIN environment variable so normal CI skips it;
//  to run it live, start the Worker (e.g. `wrangler dev` in the submodule) and:
//    RELAY_TEST_ORIGIN=http://localhost:8787 swift test --filter RelayLiveTests
//

import XCTest
import CryptoKit
import CompanionProtocol
import CompanionNoise
@testable import CompanionTransport

/// A one-shot async signal: waiters before or after `signal()` all proceed
/// once it fires. Used to gate the phone's join on the mac being parked,
/// without polling or sleeping.
private actor Gate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        guard !open else { return }
        open = true
        for w in waiters { w.resume() }
        waiters.removeAll()
    }

    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

final class RelayLiveTests: XCTestCase {
    private func relayOrigin() throws -> String {
        guard let origin = ProcessInfo.processInfo.environment["RELAY_TEST_ORIGIN"] else {
            throw XCTSkip("Set RELAY_TEST_ORIGIN (and run the relay Worker) to run the live relay test")
        }
        return origin
    }

    func test_pairOverRelayAndExchangeEncryptedMessage() async throws {
        let origin = try relayOrigin()

        // Mac identity + pairing id (the QR contents the phone would scan).
        let macStatic = try NoiseKeyPair.generate()
        let phoneStatic = try NoiseKeyPair.generate()
        let pid = (0..<8).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let rendezvous = PairingRendezvous(pairingID: pid)
        let roomName = RelayRoom.name(responderStaticPublicKey: macStatic.publicKey, pairingID: pid)
        let prologue = PairingCode(responderStaticPublicKey: macStatic.publicKey,
                                   pairingID: pid).handshakePrologue()

        // The mac must be parked before the phone sends Noise msg1, or the DO
        // drops msg1 pre-splice and the handshake hangs. The `parked` gate
        // fires from the listener's onParked hook; the phone waits on it
        // instead of guessing with a sleep.
        let parked = Gate()
        let listener = RelayTransportListener(relayOrigin: origin,
                                              roomName: roomName,
                                              onParked: { Task { await parked.signal() } })
        let connector = RelayTransportConnector(relayOrigin: origin,
                                                responderStaticKey: macStatic.publicKey)

        // Both sides run CONCURRENTLY: the mac's accept() blocks until the phone
        // sends its first Noise frame, and the phone's handshake is what sends
        // it, so they must make progress at the same time (awaiting the mac
        // before starting the phone would deadlock).
        async let macChannel: NoiseChannel = {
            let mac = try await listener.accept()
            return try await NoiseHandshake.perform(
                role: .responder, transport: mac,
                localKeyPair: macStatic, remoteStaticPublicKey: nil, prologue: prologue)
        }()
        async let phoneChannel: NoiseChannel = {
            await parked.wait()
            let phone = try await connector.connect(to: rendezvous, timeout: 15)
            return try await NoiseHandshake.perform(
                role: .initiator, transport: phone,
                localKeyPair: phoneStatic, remoteStaticPublicKey: macStatic.publicKey, prologue: prologue)
        }()

        let macCh = try await macChannel
        let phoneCh = try await phoneChannel

        // SAS confirmation, exactly as the apps do it on a fresh pairing: both
        // ends derive the same code from the handshake hash, and the mac's
        // verdict is the first frame on the channel.
        XCTAssertEqual(PairingSAS.code(handshakeHash: macCh.handshakeHash),
                       PairingSAS.code(handshakeHash: phoneCh.handshakeHash))
        try await macCh.send(PairingConfirmation.accepted.encoded())
        let verdict = try await phoneCh.receive()
        XCTAssertEqual(PairingConfirmation.decode(verdict), .accepted)

        // Application data round-trips through the encrypted channels.
        let ping = Data("hello over cloudflare".utf8)
        try await phoneCh.send(ping)
        let got = try await macCh.receive()
        XCTAssertEqual(got, ping)

        let pong = Data("ack from the mac".utf8)
        try await macCh.send(pong)
        let gotPong = try await phoneCh.receive()
        XCTAssertEqual(gotPong, pong)

        listener.stop()
    }

    /// Regression: the mac's accept loop asks for the next connection while the
    /// first is still live (to surface a reconnecting phone). The relay room has
    /// one mac slot with newest-wins displacement, so a naive second park would
    /// displace the mac's own live bridge and the connection would die. The
    /// listener must instead hold the second accept until the first closes.
    func test_macSecondAcceptDoesNotDisplaceLiveConnection() async throws {
        let origin = try relayOrigin()

        let macStatic = try NoiseKeyPair.generate()
        let phoneStatic = try NoiseKeyPair.generate()
        let pid = (0..<8).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let rendezvous = PairingRendezvous(pairingID: pid)
        let roomName = RelayRoom.name(responderStaticPublicKey: macStatic.publicKey, pairingID: pid)
        let prologue = PairingCode(responderStaticPublicKey: macStatic.publicKey,
                                   pairingID: pid).handshakePrologue()

        let parked = Gate()
        let listener = RelayTransportListener(relayOrigin: origin,
                                              roomName: roomName,
                                              onParked: { Task { await parked.signal() } })
        let connector = RelayTransportConnector(relayOrigin: origin,
                                                responderStaticKey: macStatic.publicKey)

        async let macChannel: NoiseChannel = {
            let mac = try await listener.accept()
            return try await NoiseHandshake.perform(
                role: .responder, transport: mac,
                localKeyPair: macStatic, remoteStaticPublicKey: nil, prologue: prologue)
        }()
        async let phoneChannel: NoiseChannel = {
            await parked.wait()
            let phone = try await connector.connect(to: rendezvous, timeout: 15)
            return try await NoiseHandshake.perform(
                role: .initiator, transport: phone,
                localKeyPair: phoneStatic, remoteStaticPublicKey: macStatic.publicKey, prologue: prologue)
        }()

        let macCh = try await macChannel
        let phoneCh = try await phoneChannel

        // Emulate the mac's "keep accepting" loop: request the next connection
        // while the first is still up. With the bug this displaces macCh.
        let secondAcceptReturned = Latch()
        let secondAccept = Task {
            let transport = try? await listener.accept()
            await secondAcceptReturned.set()
            return transport
        }
        // Let the second accept() reach its wait (or, with the bug, park and
        // displace) before we test the live connection.
        try await Task.sleep(nanoseconds: 300_000_000)

        // The original connection must still carry traffic both ways.
        let ping = Data("still alive after second accept".utf8)
        try await phoneCh.send(ping)
        let got = try await macCh.receive()
        XCTAssertEqual(got, ping)

        let pong = Data("mac still here".utf8)
        try await macCh.send(pong)
        let gotPong = try await phoneCh.receive()
        XCTAssertEqual(gotPong, pong)

        // And the second accept must still be pending: no phone has reconnected,
        // so it is correctly waiting rather than having displaced the live one.
        let returnedEarly = await secondAcceptReturned.value
        XCTAssertFalse(returnedEarly, "second accept() should block, not displace the live connection")

        secondAccept.cancel()
        listener.stop()
    }

    /// The mac-restart scenario: when the mac is not parked (still relaunching)
    /// the phone must be rejected rather than left to send its handshake into an
    /// empty room and time out; once the mac parks, the phone connects and the
    /// handshake completes.
    func test_phoneIsRejectedUntilMacParks() async throws {
        let origin = try relayOrigin()

        let macStatic = try NoiseKeyPair.generate()
        let phoneStatic = try NoiseKeyPair.generate()
        let pid = (0..<8).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let rendezvous = PairingRendezvous(pairingID: pid)
        let roomName = RelayRoom.name(responderStaticPublicKey: macStatic.publicKey, pairingID: pid)
        let prologue = PairingCode(responderStaticPublicKey: macStatic.publicKey,
                                   pairingID: pid).handshakePrologue()
        let connector = RelayTransportConnector(relayOrigin: origin,
                                                responderStaticKey: macStatic.publicKey)

        // No mac parked yet: the connect must fail fast, not hang.
        do {
            _ = try await connector.connect(to: rendezvous, timeout: 10)
            XCTFail("expected the relay to reject the phone while no mac is parked")
        } catch {
            // Expected: "mac offline".
        }

        // The mac parks; the phone's next attempt is admitted and handshakes.
        let parked = Gate()
        let listener = RelayTransportListener(relayOrigin: origin,
                                              roomName: roomName,
                                              onParked: { Task { await parked.signal() } })
        async let macChannel: NoiseChannel = {
            let t = try await listener.accept()
            return try await NoiseHandshake.perform(
                role: .responder, transport: t,
                localKeyPair: macStatic, remoteStaticPublicKey: nil, prologue: prologue)
        }()
        async let phoneChannel: NoiseChannel = {
            await parked.wait()
            let t = try await connector.connect(to: rendezvous, timeout: 10)
            return try await NoiseHandshake.perform(
                role: .initiator, transport: t,
                localKeyPair: phoneStatic, remoteStaticPublicKey: macStatic.publicKey, prologue: prologue)
        }()
        let macCh = try await macChannel
        let phoneCh = try await phoneChannel
        let ping = Data("mac is up now".utf8)
        try await phoneCh.send(ping)
        let got = try await macCh.receive()
        XCTAssertEqual(got, ping)
        listener.stop()
    }

    /// One full pairing: mac parks (fresh listener, like the controller's
    /// accept-one-then-exit), phone connects, both run the Noise handshake
    /// concurrently. Returns the live channels and the phone's transport (so a
    /// test can close it to simulate the phone going away).
    private func pairCycle(origin: String,
                           roomName: String,
                           rendezvous: PairingRendezvous,
                           prologue: Data,
                           macStatic: NoiseKeyPair,
                           phoneStatic: NoiseKeyPair) async throws
        -> (mac: NoiseChannel, phone: NoiseChannel, phoneTransport: MessageTransport) {
        let parked = Gate()
        let listener = RelayTransportListener(relayOrigin: origin,
                                              roomName: roomName,
                                              onParked: { Task { await parked.signal() } })
        let connector = RelayTransportConnector(relayOrigin: origin,
                                                responderStaticKey: macStatic.publicKey)
        async let macChannel: NoiseChannel = {
            let t = try await listener.accept()
            return try await NoiseHandshake.perform(
                role: .responder, transport: t,
                localKeyPair: macStatic, remoteStaticPublicKey: nil, prologue: prologue)
        }()
        async let phoneSide: (NoiseChannel, MessageTransport) = {
            await parked.wait()
            let t = try await connector.connect(to: rendezvous, timeout: 15)
            let ch = try await NoiseHandshake.perform(
                role: .initiator, transport: t,
                localKeyPair: phoneStatic, remoteStaticPublicKey: macStatic.publicKey, prologue: prologue)
            return (ch, t)
        }()
        let macCh = try await macChannel
        let (phoneCh, phoneT) = try await phoneSide
        return (macCh, phoneCh, phoneT)
    }

    /// Returns true if the channel reports closed within the timeout, false if
    /// it is still readable (i.e. the mac never learned the phone left).
    private func channelClosed(_ channel: NoiseChannel, within seconds: Double) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do { _ = try await channel.receive(); return false } catch { return true }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    /// The full reconnect cycle that the device exercises: pair, use the link,
    /// the phone goes away, the mac must learn it left (relay peer-close), then
    /// the phone reconnects and the link works again. This is the behaviour that
    /// was failing on a real phone restart.
    func test_reconnectAfterPhoneDisconnect() async throws {
        let origin = try relayOrigin()

        let macStatic = try NoiseKeyPair.generate()
        let phoneStatic = try NoiseKeyPair.generate()
        let pid = (0..<8).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let rendezvous = PairingRendezvous(pairingID: pid)
        let roomName = RelayRoom.name(responderStaticPublicKey: macStatic.publicKey, pairingID: pid)
        let prologue = PairingCode(responderStaticPublicKey: macStatic.publicKey,
                                   pairingID: pid).handshakePrologue()

        // First connection works.
        let first = try await pairCycle(origin: origin, roomName: roomName, rendezvous: rendezvous,
                                        prologue: prologue, macStatic: macStatic, phoneStatic: phoneStatic)
        try await first.phone.send(Data("ping-1".utf8))
        let got1 = try await first.mac.receive()
        XCTAssertEqual(got1, Data("ping-1".utf8))

        // Phone goes away (app killed): close its socket.
        await first.phoneTransport.close()

        // The mac's socket to the relay is still healthy, so it only learns the
        // phone left if the relay closes its peer. If this times out, reconnect
        // can never work, the mac sits on a dead bridge.
        let learnedPhoneLeft = await channelClosed(first.mac, within: 8)
        XCTAssertTrue(learnedPhoneLeft, "mac never learned the phone left (relay peer-close missing)")

        // The phone reconnects; the link must work again.
        let second = try await pairCycle(origin: origin, roomName: roomName, rendezvous: rendezvous,
                                         prologue: prologue, macStatic: macStatic, phoneStatic: phoneStatic)
        try await second.phone.send(Data("ping-2".utf8))
        let got2 = try await second.mac.receive()
        XCTAssertEqual(got2, Data("ping-2".utf8))

        await second.phoneTransport.close()
    }
}

/// A one-shot boolean that flips to true and stays there. Used to observe
/// whether a background accept() has returned.
private actor Latch {
    private(set) var value = false
    func set() { value = true }
}
