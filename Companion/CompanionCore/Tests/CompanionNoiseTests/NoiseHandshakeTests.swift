//
//  NoiseHandshakeTests.swift
//  CompanionCore
//
//  Exercises the real noise-c XK handshake end to end over an in-memory
//  transport pair, then round-trips application data through the resulting
//  encrypted channels.
//

import XCTest
import CompanionProtocol
@testable import CompanionNoise

/// A bidirectional in-memory transport pair. Endpoint A sends to queue 1 and
/// receives from queue 0; endpoint B is the mirror image.
private actor TransportPipe {
    private var queues: [[Data]] = [[], []]
    private var waiters: [[CheckedContinuation<Data, Error>]] = [[], []]
    private var closed = false

    func send(to index: Int, _ data: Data) {
        if !waiters[index].isEmpty {
            waiters[index].removeFirst().resume(returning: data)
        } else {
            queues[index].append(data)
        }
    }

    func receive(at index: Int) async throws -> Data {
        if !queues[index].isEmpty {
            return queues[index].removeFirst()
        }
        if closed {
            throw TransportError.closed
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiters[index].append(continuation)
        }
    }

    func close() {
        closed = true
        for index in waiters.indices {
            for waiter in waiters[index] {
                waiter.resume(throwing: TransportError.closed)
            }
            waiters[index].removeAll()
        }
    }
}

private final class PipeEndpoint: MessageTransport, @unchecked Sendable {
    private let pipe: TransportPipe
    private let receiveIndex: Int
    private let sendIndex: Int

    init(pipe: TransportPipe, receiveIndex: Int, sendIndex: Int) {
        self.pipe = pipe
        self.receiveIndex = receiveIndex
        self.sendIndex = sendIndex
    }

    func send(_ frame: Data) async throws {
        await pipe.send(to: sendIndex, frame)
    }

    func receive() async throws -> Data {
        try await pipe.receive(at: receiveIndex)
    }

    func close() async {
        await pipe.close()
    }
}

final class NoiseHandshakeTests: XCTestCase {
    private func connectedPair() -> (phone: PipeEndpoint, mac: PipeEndpoint) {
        let pipe = TransportPipe()
        return (PipeEndpoint(pipe: pipe, receiveIndex: 0, sendIndex: 1),
                PipeEndpoint(pipe: pipe, receiveIndex: 1, sendIndex: 0))
    }

    func testKeyPairDerivationIsStable() throws {
        let generated = try NoiseKeyPair.generate()
        let rederived = try NoiseKeyPair.from(privateKey: generated.privateKey)
        XCTAssertEqual(generated.privateKey.count, 32)
        XCTAssertEqual(generated.publicKey.count, 32)
        XCTAssertEqual(generated.publicKey, rederived.publicKey)
    }

    func testHandshakeAndRoundTrip() async throws {
        let responderKeys = try NoiseKeyPair.generate()
        let initiatorKeys = try NoiseKeyPair.generate()
        let (phoneTransport, macTransport) = connectedPair()
        let prologue = Data("iterm2-companion/pid:abc123".utf8)

        async let phoneChannel = NoiseHandshake.perform(
            role: .initiator,
            transport: phoneTransport,
            localKeyPair: initiatorKeys,
            remoteStaticPublicKey: responderKeys.publicKey,
            prologue: prologue)
        async let macChannel = NoiseHandshake.perform(
            role: .responder,
            transport: macTransport,
            localKeyPair: responderKeys,
            remoteStaticPublicKey: nil,
            prologue: prologue)

        let phone = try await phoneChannel
        let mac = try await macChannel

        // Phone to mac.
        let hello = Data("hello from phone".utf8)
        try await phone.send(hello)
        let received = try await mac.receive()
        XCTAssertEqual(received, hello)

        // Mac to phone.
        let reply = Data("hi phone".utf8)
        try await mac.send(reply)
        let receivedReply = try await phone.receive()
        XCTAssertEqual(receivedReply, reply)

        // A frame far larger than one Noise message, to exercise chunking and
        // reassembly across multiple transport messages.
        let big = Data((0..<200_000).map { UInt8($0 & 0xFF) })
        try await phone.send(big)
        let receivedBig = try await mac.receive()
        XCTAssertEqual(receivedBig, big)
    }

    func testPrologueMismatchFails() async throws {
        let responderKeys = try NoiseKeyPair.generate()
        let initiatorKeys = try NoiseKeyPair.generate()
        let (phoneTransport, macTransport) = connectedPair()

        async let phoneChannel = NoiseHandshake.perform(
            role: .initiator,
            transport: phoneTransport,
            localKeyPair: initiatorKeys,
            remoteStaticPublicKey: responderKeys.publicKey,
            prologue: Data("phone-prologue".utf8))
        async let macChannel = NoiseHandshake.perform(
            role: .responder,
            transport: macTransport,
            localKeyPair: responderKeys,
            remoteStaticPublicKey: nil,
            prologue: Data("mac-prologue".utf8))

        // The mismatched prologue makes the MAC check on message 1 fail, so the
        // responder rejects the handshake. Await both so neither task leaks.
        var failed = false
        do {
            _ = try await macChannel
        } catch {
            failed = true
        }
        // Tear down the initiator regardless of where it is in the exchange.
        await phoneTransport.close()
        _ = try? await phoneChannel
        XCTAssertTrue(failed, "handshake should fail when prologues differ")
    }
}
