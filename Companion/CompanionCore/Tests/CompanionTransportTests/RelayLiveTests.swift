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
}
