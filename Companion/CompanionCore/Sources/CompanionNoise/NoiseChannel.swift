//
//  NoiseChannel.swift
//  CompanionCore
//
//  The encrypted transport produced by a completed Noise handshake. It is
//  itself a MessageTransport that wraps the underlying (plaintext) transport:
//  the RPC layer above sends and receives application frames here and never
//  sees ciphertext, while the underlying transport only ever carries Noise
//  transport messages.
//
//  Noise transport messages are capped at 65535 bytes, so an application frame
//  larger than one message is split into chunks. Each chunk's plaintext is
//  prefixed with a single continuation byte (1 = more chunks follow, 0 = last
//  chunk) so the receiver can reassemble the frame.
//

import Foundation
import CNoise
import CompanionProtocol

public final class NoiseChannel: MessageTransport, @unchecked Sendable {
    /// The handshake transcript digest (h), identical on both peers iff they
    /// completed the same handshake with no man in the middle. This is what the
    /// SAS pairing-confirmation code is derived from (PairingSAS).
    public let handshakeHash: Data

    private let transport: MessageTransport
    // noise-c CipherStates are not internally synchronized and carry a nonce
    // that must advance in lock-step with the peer, so all use is serialized.
    private let sendCipher: OpaquePointer
    private let receiveCipher: OpaquePointer
    private let sendLock = NSLock()
    private let receiveLock = NSLock()
    // Accumulates chunks of a multi-message frame until the final chunk.
    private var reassembly = Data()

    // Serializes whole sends (encrypt AND transmit). The receiver decrypts
    // with an implicit, strictly incrementing nonce, so a frame that reaches
    // the wire out of nonce order fails authentication on the other side and
    // tears the connection down. Holding sendLock only over encryption is not
    // enough: with concurrent callers, transmit order could diverge from
    // nonce order in the await window after the lock is released. Every send
    // therefore chains behind the previous one.
    private let sendChainLock = UnfairLock()
    private var sendChain: Task<Void, Error>?

    init(transport: MessageTransport,
         sendCipher: OpaquePointer,
         receiveCipher: OpaquePointer,
         handshakeHash: Data) {
        self.transport = transport
        self.sendCipher = sendCipher
        self.receiveCipher = receiveCipher
        self.handshakeHash = handshakeHash
    }

    deinit {
        noise_cipherstate_free(sendCipher)
        noise_cipherstate_free(receiveCipher)
    }

    public func send(_ frame: Data) async throws {
        let task: Task<Void, Error> = sendChainLock.withLock {
            let previous = sendChain
            let task = Task { [weak self] in
                // Wait for the predecessor regardless of its outcome; a
                // predecessor's failure is reported to its own caller.
                _ = try? await previous?.value
                guard let self else {
                    throw TransportError.closed
                }
                let messages = try self.encrypt(frame: frame)
                for message in messages {
                    try await self.transport.send(message)
                }
            }
            sendChain = task
            return task
        }
        try await task.value
    }

    public func receive() async throws -> Data {
        while true {
            let ciphertext = try await transport.receive()
            if let frame = try decrypt(message: ciphertext) {
                return frame
            }
        }
    }

    public func close() async {
        await transport.close()
    }

    private func encrypt(frame: Data) throws -> [Data] {
        sendLock.lock()
        defer { sendLock.unlock() }

        let mac = noise_cipherstate_get_mac_length(sendCipher)
        // Reserve one byte for the continuation flag and `mac` bytes for the tag.
        let maxChunk = NoiseProtocolName.maxNoiseMessageSize - mac - 1
        guard maxChunk > 0 else {
            throw TransportError.malformedFrame
        }

        var messages = [Data]()
        var offset = 0
        repeat {
            let end = min(offset + maxChunk, frame.count)
            let isLast = end >= frame.count
            let chunk = frame.subdata(in: offset..<end)

            // Layout: [continuation byte][chunk bytes][space for MAC].
            var plaintext = [UInt8]()
            plaintext.reserveCapacity(1 + chunk.count + mac)
            plaintext.append(isLast ? 0 : 1)
            plaintext.append(contentsOf: chunk)
            let payloadLength = plaintext.count
            plaintext.append(contentsOf: repeatElement(0, count: mac))

            let ciphertext: Data = try plaintext.withUnsafeMutableBufferPointer { ptr in
                var buffer = NoiseBuffer()
                buffer.data = ptr.baseAddress
                buffer.size = payloadLength
                buffer.max_size = ptr.count
                try noiseCheck(noise_cipherstate_encrypt(sendCipher, &buffer), "encrypt")
                return Data(bytes: ptr.baseAddress!, count: buffer.size)
            }
            messages.append(ciphertext)
            offset = end
        } while offset < frame.count

        return messages
    }

    /// Decrypt one Noise transport message. Returns the reassembled application
    /// frame when this message was the final chunk, or nil when more chunks are
    /// still expected.
    private func decrypt(message ciphertext: Data) throws -> Data? {
        receiveLock.lock()
        defer { receiveLock.unlock() }

        var bytes = [UInt8](ciphertext)
        let plaintext: [UInt8] = try bytes.withUnsafeMutableBufferPointer { ptr in
            var buffer = NoiseBuffer()
            buffer.data = ptr.baseAddress
            buffer.size = ptr.count
            buffer.max_size = ptr.count
            try noiseCheck(noise_cipherstate_decrypt(receiveCipher, &buffer), "decrypt")
            return Array(UnsafeBufferPointer(start: ptr.baseAddress, count: buffer.size))
        }

        guard let continuation = plaintext.first else {
            // Every chunk carries at least the continuation byte.
            throw TransportError.malformedFrame
        }
        reassembly.append(contentsOf: plaintext.dropFirst())
        if continuation == 0 {
            let frame = reassembly
            reassembly = Data()
            return frame
        }
        return nil
    }
}
