//
//  NWMessageTransportTests.swift
//  CompanionCore
//
//  Drives NWMessageTransport over a real localhost TCP connection (raw
//  NWListener, no Bonjour) and runs the Noise XK handshake across it, proving
//  the framing, transport, and crypto layers compose end to end on the wire.
//

import XCTest
import Network
import CompanionProtocol
import CompanionTransport
@testable import CompanionNoise

final class NWMessageTransportTests: XCTestCase {
    /// Start a listener on an ephemeral localhost port and return it together
    /// with an async source of its first inbound connection.
    private func makeListener() throws -> (listener: NWListener,
                                           port: () async throws -> NWEndpoint.Port,
                                           firstConnection: () async throws -> NWConnection) {
        let listener = try NWListener(using: .tcp)
        let queue = DispatchQueue(label: "test.listener")

        let connectionBox = Box<NWConnection>()
        let portBox = Box<NWEndpoint.Port>()

        listener.newConnectionHandler = { connection in
            connectionBox.put(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .ready = state, let port = listener.port {
                portBox.put(port)
            }
        }
        listener.start(queue: queue)

        return (listener, { try await portBox.value() }, { try await connectionBox.value() })
    }

    func testTCPLoopbackNoiseRoundTrip() async throws {
        let (listener, port, firstConnection) = try makeListener()
        defer { listener.cancel() }

        let listenPort = try await port()
        let clientConnection = NWConnection(
            host: .ipv4(.loopback), port: listenPort, using: .tcp)

        let clientTransport = NWMessageTransport(connection: clientConnection)
        async let serverConnection = firstConnection()

        try await clientTransport.start()
        let serverTransport = NWMessageTransport(connection: try await serverConnection)
        try await serverTransport.start()

        // Noise XK over the real TCP transports.
        let responderKeys = try NoiseKeyPair.generate()
        let initiatorKeys = try NoiseKeyPair.generate()
        let prologue = Data("pid:loopback".utf8)

        async let phoneChannel = NoiseHandshake.perform(
            role: .initiator,
            transport: clientTransport,
            localKeyPair: initiatorKeys,
            remoteStaticPublicKey: responderKeys.publicKey,
            prologue: prologue)
        async let macChannel = NoiseHandshake.perform(
            role: .responder,
            transport: serverTransport,
            localKeyPair: responderKeys,
            remoteStaticPublicKey: nil,
            prologue: prologue)

        let phone = try await phoneChannel
        let mac = try await macChannel

        let message = Data("companion over real tcp".utf8)
        try await phone.send(message)
        let received = try await mac.receive()
        XCTAssertEqual(received, message)

        // Reply, exercising the other direction and the length-prefix framer's
        // reassembly across TCP segment boundaries.
        let big = Data((0..<120_000).map { UInt8($0 & 0xFF) })
        try await mac.send(big)
        let receivedBig = try await phone.receive()
        XCTAssertEqual(receivedBig, big)

        await phone.close()
        await mac.close()
    }
}

/// A one-shot async box: the first put() satisfies any awaiting value().
private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    private var waiters = [CheckedContinuation<T, Error>]()

    func put(_ value: T) {
        lock.lock()
        if stored == nil {
            stored = value
        }
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        for waiter in pending {
            waiter.resume(returning: value)
        }
    }

    func value() async throws -> T {
        lock.lock()
        if let stored {
            lock.unlock()
            return stored
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
            lock.unlock()
        }
    }
}
