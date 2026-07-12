import Foundation

/// Minimal WebSocket client over a raw socket connection.
/// Implements just enough of RFC 6455 for binary message exchange with iTerm2.
class WebSocketClient {
    private let socket: SocketConnection

    init(socket: SocketConnection) {
        self.socket = socket
    }

    /// Perform the HTTP upgrade handshake.
    func handshake(cookie: String?, key: String?) throws {
        let secKey = generateSecWebSocketKey()

        var headers = [
            "GET / HTTP/1.1",
            "Host: localhost",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Version: 13",
            "Sec-WebSocket-Key: \(secKey)",
            "Sec-WebSocket-Protocol: api.iterm2.com",
            "Origin: ws://localhost/",
            "x-iterm2-library-version: swift 1.0",
            "x-iterm2-advisory-name: it2",
            "x-iterm2-disable-auth-ui: true",
        ]

        if let cookie = cookie {
            headers.append("x-iterm2-cookie: \(cookie)")
        }
        if let key = key {
            headers.append("x-iterm2-key: \(key)")
        }

        let request = headers.joined(separator: "\r\n") + "\r\n\r\n"
        try socket.send(Data(request.utf8))

        // Read until we get the end of HTTP headers
        let headerEnd = Data("\r\n\r\n".utf8)
        let responseData = try socket.recvUntil(headerEnd)

        guard let responseStr = String(data: responseData, encoding: .utf8) else {
            throw IT2Error.connectionError("Invalid HTTP response from iTerm2")
        }

        guard responseStr.contains("101") else {
            if responseStr.contains("401") {
                throw IT2Error.connectionError("Authentication failed. Ensure iTerm2 Python API is enabled: Settings > General > Magic > Enable Python API")
            }
            throw IT2Error.connectionError("WebSocket handshake failed: \(responseStr.prefix(200))")
        }
    }

    /// Send a binary WebSocket frame.
    func sendBinary(_ data: Data) throws {
        // Header (2-10 bytes) + mask (4 bytes) + payload
        var frame = Data()
        frame.reserveCapacity(14 + data.count)

        // FIN + binary opcode
        frame.append(0x82)

        // Mask bit always set for client frames + payload length
        let length = data.count
        if length < 126 {
            frame.append(UInt8(length) | 0x80)
        } else if length < 65536 {
            frame.append(126 | 0x80)
            frame.append(UInt8((length >> 8) & 0xFF))
            frame.append(UInt8(length & 0xFF))
        } else {
            frame.append(127 | 0x80)
            for i in (0..<8).reversed() {
                frame.append(UInt8((length >> (i * 8)) & 0xFF))
            }
        }

        // Masking key (4 random bytes)
        var maskKey = [UInt8](repeating: 0, count: 4)
        _ = SecRandomCopyBytes(kSecRandomDefault, 4, &maskKey)
        frame.append(contentsOf: maskKey)

        // Masked payload
        for (i, byte) in data.enumerated() {
            frame.append(byte ^ maskKey[i % 4])
        }

        try socket.send(frame)
    }

    /// Receive a binary WebSocket frame. Returns the unmasked payload.
    func receiveBinary() throws -> Data {
        // Read first 2 bytes: FIN/opcode + mask/length
        let header = try socket.recv(count: 2)
        let opcode = header[0] & 0x0F
        let masked = (header[1] & 0x80) != 0
        var payloadLength = UInt64(header[1] & 0x7F)

        if payloadLength == 126 {
            let ext = try socket.recv(count: 2)
            payloadLength = UInt64(ext[0]) << 8 | UInt64(ext[1])
        } else if payloadLength == 127 {
            let ext = try socket.recv(count: 8)
            payloadLength = 0
            for i in 0..<8 {
                payloadLength = (payloadLength << 8) | UInt64(ext[i])
            }
        }

        // Read mask key if present (server shouldn't mask, but handle it)
        var maskKey: [UInt8]?
        if masked {
            let keyData = try socket.recv(count: 4)
            maskKey = [UInt8](keyData)
        }

        // Read payload
        guard payloadLength <= 100_000_000 else {
            throw IT2Error.connectionError("WebSocket frame too large: \(payloadLength) bytes")
        }
        var payload = try socket.recv(count: Int(payloadLength))

        // Unmask if needed
        if let key = maskKey {
            for i in 0..<payload.count {
                payload[i] ^= key[i % 4]
            }
        }

        // Handle control frames
        if opcode == 0x08 { // Close
            throw IT2Error.connectionError("Server closed WebSocket connection")
        }
        if opcode == 0x09 { // Ping — send pong
            try sendPong(payload)
            return try receiveBinary() // Read next frame
        }

        return payload
    }

    func disconnect() {
        // Send close frame (best effort)
        var closeFrame = Data([0x88, 0x80]) // FIN + close opcode, masked, 0 length
        closeFrame.append(contentsOf: [0, 0, 0, 0]) // mask key
        try? socket.send(closeFrame)
        socket.disconnect()
    }

    // MARK: - Private

    private func sendPong(_ payload: Data) throws {
        var frame = Data()
        frame.append(0x8A) // FIN + pong
        let length = payload.count
        frame.append(UInt8(length) | 0x80) // masked
        var maskKey = [UInt8](repeating: 0, count: 4)
        _ = SecRandomCopyBytes(kSecRandomDefault, 4, &maskKey)
        frame.append(contentsOf: maskKey)
        for (i, byte) in payload.enumerated() {
            frame.append(byte ^ maskKey[i % 4])
        }
        try socket.send(frame)
    }

    private func generateSecWebSocketKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &bytes)
        return Data(bytes).base64EncodedString()
    }
}
