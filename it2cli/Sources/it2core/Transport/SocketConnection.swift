import Foundation

/// Raw POSIX unix domain socket connection.
class SocketConnection {
    private var fd: Int32 = -1

    /// Connect to the iTerm2 API unix domain socket.
    static func connect() throws -> SocketConnection {
        let socketPath = Self.socketPath()
        let conn = SocketConnection()

        conn.fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard conn.fd >= 0 else {
            throw IT2Error.connectionError("Failed to create socket: \(String(cString: strerror(errno)))")
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(conn.fd)
            throw IT2Error.connectionError("Socket path too long")
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dest, src.baseAddress!, pathBytes.count)
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(conn.fd, sockPtr, addrLen)
            }
        }

        guard result == 0 else {
            let err = String(cString: strerror(errno))
            Darwin.close(conn.fd)
            throw IT2Error.connectionError("Failed to connect to iTerm2 socket at \(socketPath): \(err)\nMake sure iTerm2 is running and the Python API is enabled in Settings > General > Magic.")
        }

        // Set a 30-second read timeout to avoid hanging forever.
        var timeout = timeval(tv_sec: 30, tv_usec: 0)
        setsockopt(conn.fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        return conn
    }

    /// Send raw bytes.
    func send(_ data: Data) throws {
        try data.withUnsafeBytes { buf in
            var sent = 0
            let total = buf.count
            let ptr = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            while sent < total {
                let n = Darwin.send(fd, ptr + sent, total - sent, 0)
                guard n > 0 else {
                    throw IT2Error.connectionError("Socket send failed: \(String(cString: strerror(errno)))")
                }
                sent += n
            }
        }
    }

    /// Receive exactly `count` bytes.
    func recv(count: Int) throws -> Data {
        var buffer = Data(count: count)
        var received = 0
        try buffer.withUnsafeMutableBytes { buf in
            let ptr = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            while received < count {
                let n = Darwin.recv(fd, ptr + received, count - received, 0)
                guard n > 0 else {
                    if n == 0 {
                        throw IT2Error.connectionError("Connection closed by iTerm2")
                    }
                    throw IT2Error.connectionError("Socket recv failed: \(String(cString: strerror(errno)))")
                }
                received += n
            }
        }
        return buffer
    }

    func recvUntil(_ delimiter: Data) throws -> Data {
        var accumulated = Data()
        accumulated.reserveCapacity(512)
        var chunk = Data(count: 256)
        while true {
            let n = chunk.withUnsafeMutableBytes { buf in
                Darwin.recv(fd, buf.baseAddress!, 256, 0)
            }
            guard n > 0 else {
                if n == 0 {
                    throw IT2Error.connectionError("Connection closed by iTerm2")
                }
                throw IT2Error.connectionError("Socket recv failed: \(String(cString: strerror(errno)))")
            }
            accumulated.append(chunk.prefix(n))
            if accumulated.count >= delimiter.count &&
               accumulated.suffix(delimiter.count) == delimiter {
                return accumulated
            }
            if accumulated.count > 65536 {
                throw IT2Error.connectionError("Response header too large")
            }
        }
    }

    func disconnect() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    deinit {
        disconnect()
    }

    // MARK: - Private

    private static func socketPath() -> String {
        let appSupport = NSSearchPathForDirectoriesInDomains(
            .applicationSupportDirectory, .userDomainMask, true
        ).first!
        let suite = ProcessInfo.processInfo.environment["IT2_SUITE"] ?? "iTerm2"
        return "\(appSupport)/\(suite)/private/socket"
    }
}
