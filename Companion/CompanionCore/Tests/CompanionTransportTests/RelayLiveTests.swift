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

        let listener = RelayTransportListener(relayOrigin: origin, roomName: roomName)
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
            // A small head start so the mac is parked before the phone joins
            // (mirrors "park before showing the QR"); the DO persists either way.
            try await Task.sleep(nanoseconds: 300_000_000)
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
