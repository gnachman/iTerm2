import Foundation
#if canImport(ProtobufRuntime)
import ProtobufRuntime  // standalone SwiftPM build; in-app the types come via the bridging header
#endif

/// A bidirectional channel that carries API messages between the CLI and iTerm2.
///
/// `SocketChannel` talks to a running iTerm2 over its local unix domain socket.
/// A future in-process implementation will hand messages straight to
/// iTermAPIServer when the command tree is embedded inside the app (so `it2`
/// can work over SSH integration).
public protocol APIChannel {
    /// Send a request. The caller assigns `id_p`; the channel only transports.
    func send(_ request: ITMClientOriginatedMessage) throws
    /// Block until the next server message is available and return it.
    func receiveMessage() throws -> ITMServerOriginatedMessage
    func disconnect()
}

/// `APIChannel` backed by a WebSocket over iTerm2's local unix domain socket.
final class SocketChannel: APIChannel {
    private let ws: WebSocketClient

    private init(ws: WebSocketClient) {
        self.ws = ws
    }

    static func connect() throws -> SocketChannel {
        let socket: SocketConnection
        let cookie: String?
        let key: String?
        switch CookieAuth.policy {
        case .appleScript:
            socket = try SocketConnection.connect()
            (cookie, key) = CookieAuth.getCredentials()
        case .agentHook:
            // Credentials first: getting them can wait for the user to answer a consent prompt,
            // and iTerm2 drops a connection that sends nothing for 30 seconds.
            let path = SocketConnection.resolvePath()
            (cookie, key) = CookieAuth.getCredentials()
            socket = try SocketConnection.connect(toPath: path)
        }
        let ws = WebSocketClient(socket: socket)

        do {
            try ws.handshake(cookie: cookie, key: key)
        } catch {
            socket.disconnect()
            throw error
        }

        return SocketChannel(ws: ws)
    }

    func send(_ request: ITMClientOriginatedMessage) throws {
        guard let data = request.data() else {
            throw IT2Error.apiError("Failed to serialize request")
        }
        try ws.sendBinary(data)
    }

    func receiveMessage() throws -> ITMServerOriginatedMessage {
        let data = try ws.receiveBinary()
        return try ITMServerOriginatedMessage.parse(from: data)
    }

    func disconnect() {
        ws.disconnect()
    }
}
