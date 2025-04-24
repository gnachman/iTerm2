//
//  ChannelClient.swift
//  iTerm2
//
//  Created by George Nachman on 4/13/25.
//

import Foundation
import Darwin

@objc(iTermChannelClient)
class ChannelClient: NSObject {
    let uid: String
    let conductor: Conductor?
    let mux: UnixDomainSocketMux

    @objc(initWithID:conductor:error:)
    init(uid: String, conductor: Conductor?) throws {
        self.uid = uid
        self.conductor = conductor
        mux = if conductor != nil {
            Self.connectOverSSH()
        } else {
            try Self.connectLocally(uid)
        }
    }

    private static func connectOverSSH() -> UnixDomainSocketMux {
        it_fatalError("Not implemented")
    }

    private static func connectLocally(_ uid: String) throws -> UnixDomainSocketMux {
        return try UnixDomainSocketMux(id: uid)
    }

    var fd: Int32 {
        mux.fileno
    }
}

// MARK: - Message Framer

fileprivate class MessageFramer {
    // Maps (writer_id, message_id) to a list of segments
    private var messages: [Key: [Data?]] = [:]

    struct Header {
        var writerId: UInt32
        var messageId: UInt32
        var totalSegments: UInt16
        var segmentIndex: UInt16
    }

    struct Segment {
        var writerId: UInt32
        var messageId: UInt32
        var message: Data
    }

    struct Key: Hashable {
        var writerId: UInt32
        var messageId: UInt32
    }

    // Returns a segment if the entire message can be reconstructed.
    func addSegment(header: Header, data: Data) -> Segment? {
        let key = Key(writerId: header.writerId, messageId: header.messageId)

        if messages[key] == nil {
            messages[key] = [Data?](repeating: nil, count: Int(header.totalSegments))
        }

        messages[key]?[Int(header.segmentIndex)] = data

        // Check if all segments are received
        if let segments = messages[key], segments.allSatisfy({ $0 != nil }) {
            let completeMessage = segments.compactMap { $0 }.reduce(Data(), +)
            messages.removeValue(forKey: key)
            return Segment(writerId: header.writerId,
                           messageId: header.messageId,
                           message: completeMessage)
        }

        return nil
    }
}

// MARK: - Unix Domain Socket Multiplexer

class UnixDomainSocketMux {
    // Socket header format constants
    private static let HEADER_FORMAT_SIZE = 12 // 4 + 4 + 2 + 2 bytes
    private static let MAX_DATAGRAM_SIZE = 1024
    private static let MAX_PAYLOAD_SIZE = MAX_DATAGRAM_SIZE - HEADER_FORMAT_SIZE

    private let socketPath: String
    private let peerPath: String
    private var socket: Int32 = -1
    private let framer = MessageFramer()
    private let writerId: UInt32
    private var messageCounter: UInt32 = 0
    private(set) var isConnected = false
    private var sunPathSize: Int { MemoryLayout.size(ofValue: sockaddr_un().sun_path) }

    private let id: String
    private let serverPath: String
    private let clientPath: String

    // MARK: - Initialization

    init(baseDir: String = "~/.iterm2", id: String) throws {
        let expandedBaseDir = (baseDir as NSString).expandingTildeInPath

        self.id = id
        self.serverPath = "\(expandedBaseDir)/server-\(id)"
        self.clientPath = "\(expandedBaseDir)/client-\(id)"

        DLog("Client mode: id=\(id)")

        // Client binds to client_path and knows server_path
        let peerPath = serverPath

        self.socketPath = (clientPath as NSString).expandingTildeInPath
        self.peerPath = (peerPath as NSString).expandingTildeInPath
        self.writerId = UInt32(getpid())

        // Check for valid paths
        if socketPath.isEmpty {
            throw SocketError.invalidPath("Client mode requires a socketPath to bind to")
        }

        if peerPath.isEmpty {
            throw SocketError.invalidPath("Client mode requires a peerPath")
        }

        // Create socket
        socket = Darwin.socket(AF_UNIX, SOCK_DGRAM, 0)
        if socket == -1 {
            throw SocketError.socketCreationFailed("Failed to create socket: \(StrError())")
        }

        // Create directory if needed
        let directory = (self.socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        // Clean up any existing socket file
        if FileManager.default.fileExists(atPath: self.socketPath) {
            DLog("Unlinking existing socket at \(self.socketPath)")
            try? FileManager.default.removeItem(atPath: self.socketPath)
        }

        // Bind socket
        DLog("Binding to \(self.socketPath)")
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            self.socketPath.withCString { cString in
                strncpy(ptr, cString, sunPathSize)
            }
        }

        let size = MemoryLayout<sockaddr_un>.size
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(socket, sockaddrPtr, socklen_t(size))
            }
        }

        if bindResult == -1 {
            Darwin.close(socket)
            throw SocketError.bindFailed("Failed to bind to \(self.socketPath): \(StrError())")
        }

        // Set non-blocking mode
        var flags = fcntl(socket, F_GETFL)
        flags |= O_NONBLOCK
        let result = fcntl(socket, F_SETFL, flags)
        if result == -1 {
            DLog("Failed to set socket to non-blocking mode: \(StrError())")
        }

        _ = send(message: Data())
    }

    // MARK: - Communication

    func send(message: Data) -> Int {
        do {
            return try reallySend(message: message)
        } catch {
            DLog("Send error: \(error.localizedDescription)")
            return 0
        }
    }

    func receive() -> Data? {
        return reallyReceive()?.message
    }

    // MARK: - Send Message

    func reallySend(message: Data) throws -> Int {
        messageCounter += 1
        let messageId = messageCounter
        let totalSegments = max(1, Int(ceil(Double(message.count) / Double(UnixDomainSocketMux.MAX_PAYLOAD_SIZE))))

        NSLog("Sending message \(messageId) in \(totalSegments) segments to \(peerPath)")

        var bytesSent = 0

        for segIndex in 0..<totalSegments {
            let start = segIndex * UnixDomainSocketMux.MAX_PAYLOAD_SIZE
            let end = min(start + UnixDomainSocketMux.MAX_PAYLOAD_SIZE, message.count)
            let segment = message[start..<end]

            // Create header
            var header = Data(capacity: UnixDomainSocketMux.HEADER_FORMAT_SIZE)
            var writerId = self.writerId
            var messageIdValue = messageId
            var totalSegmentsValue = UInt16(totalSegments)
            var segIndexValue = UInt16(segIndex)

            // Convert to network byte order
            writerId = CFSwapInt32HostToBig(writerId)
            messageIdValue = CFSwapInt32HostToBig(messageIdValue)
            totalSegmentsValue = CFSwapInt16HostToBig(totalSegmentsValue)
            segIndexValue = CFSwapInt16HostToBig(segIndexValue)

            header.append(contentsOf: withUnsafeBytes(of: writerId) { Array($0) })
            header.append(contentsOf: withUnsafeBytes(of: messageIdValue) { Array($0) })
            header.append(contentsOf: withUnsafeBytes(of: totalSegmentsValue) { Array($0) })
            header.append(contentsOf: withUnsafeBytes(of: segIndexValue) { Array($0) })

            // Prepare packet
            let packet = header + segment

            // Create socket address for destination
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)

            _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
                peerPath.withCString { cString in
                    strncpy(ptr, cString, sunPathSize)
                }
            }

            // Send packet
            let sent = packet.withUnsafeBytes { bufferPtr in
                withUnsafePointer(to: &addr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        Darwin.sendto(socket, bufferPtr.baseAddress, bufferPtr.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
            }

            if sent == -1 {
                if errno == ECONNREFUSED {
                    DLog("Connection refused - peer has disconnected")
                    isConnected = false
                    return bytesSent
                }
                throw SocketError.sendFailed("Failed to send packet: \(StrError())")
            }

            bytesSent += Int(sent) - UnixDomainSocketMux.HEADER_FORMAT_SIZE // Don't count header bytes
        }

        return bytesSent
    }

    // MARK: - Receive Message

    private func reallyReceive() -> MessageFramer.Segment? {
        var buffer = [UInt8](repeating: 0, count: UnixDomainSocketMux.MAX_DATAGRAM_SIZE)
        var addr = sockaddr_un()
        var addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        DLog("Receiving message on \(socketPath)")

        let received = withUnsafeMutablePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.recvfrom(
                    socket,
                    &buffer,
                    buffer.count,
                    0,
                    sockaddrPtr,
                    &addrLen
                )
            }
        }

        // Handle errors
        if received < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK {
                // No data available (non-blocking socket)
                return nil
            } else {
                DLog("Error receiving data: \(StrError())")
                return nil
            }
        }

        isConnected = true

        // Check if we have enough data for a header
        if received < UnixDomainSocketMux.HEADER_FORMAT_SIZE {
            DLog("Short datagram: \(received) < \(UnixDomainSocketMux.HEADER_FORMAT_SIZE)")
            return nil
        }

        // Extract and parse header
        let headerData = Data(buffer[0..<UnixDomainSocketMux.HEADER_FORMAT_SIZE])
        var writerId: UInt32 = 0
        var messageId: UInt32 = 0
        var totalSegments: UInt16 = 0
        var segmentIndex: UInt16 = 0

        headerData.withUnsafeBytes { ptr in
            writerId = CFSwapInt32BigToHost(ptr.load(as: UInt32.self))
            messageId = CFSwapInt32BigToHost(ptr.load(fromByteOffset: 4, as: UInt32.self))
            totalSegments = CFSwapInt16BigToHost(ptr.load(fromByteOffset: 8, as: UInt16.self))
            segmentIndex = CFSwapInt16BigToHost(ptr.load(fromByteOffset: 10, as: UInt16.self))
        }

        // Extract payload
        let payload = Data(buffer[UnixDomainSocketMux.HEADER_FORMAT_SIZE..<Int(received)])

        NSLog("Received segment \(segmentIndex)/\(totalSegments) of message \(messageId) from \(writerId)")

        // Process with message framer
        return framer.addSegment(
            header: MessageFramer.Header(writerId: writerId,
                                         messageId: messageId,
                                         totalSegments: totalSegments,
                                         segmentIndex: segmentIndex),
            data: payload
        )
    }

    // MARK: - Socket Operations

    var fileno: Int32 {
        socket
    }

    func close() {
        Darwin.close(socket)
        if FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
    }

    // MARK: - Errors

    enum SocketError: Error {
        case invalidPath(String)
        case socketCreationFailed(String)
        case bindFailed(String)
        case sendFailed(String)
        case receiveFailed(String)
    }
}

func StrError() -> String {
    if let ptr = strerror(errno), let nsstring = NSString(utf8String: ptr) {
        return nsstring as String
    }
    return "No error"
}
