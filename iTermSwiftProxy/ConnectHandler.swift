//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

internal import NIOCore
internal import NIOHTTP1
internal import NIOPosix

public protocol ConnectionMonitor: AnyObject {
    func connectionMonitorShouldConnect(method: String, host: String, port: Int, headers: [String: String]) -> Bool
}

final class ConnectHandler {
    private var upgradeState: State

    weak var monitor: ConnectionMonitor?
    private let logger: ((@autoclosure () -> String) -> ())?

    init(logger: ((@autoclosure () -> String) -> ())?) {
        self.upgradeState = .idle
        self.logger = logger
    }
}

extension ConnectHandler {
    fileprivate enum State {
        case idle
        case beganConnecting
        case awaitingEnd(connectResult: Channel)
        case awaitingConnection(pendingBytes: [NIOAny])
        case upgradeComplete(pendingBytes: [NIOAny])
        case upgradeFailed
    }
}

extension ConnectHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch self.upgradeState {
        case .idle:
            self.handleInitialMessage(context: context, data: self.unwrapInboundIn(data))

        case .beganConnecting:
            // We got .end, we're still waiting on the connection
            if case .end = self.unwrapInboundIn(data) {
                self.upgradeState = .awaitingConnection(pendingBytes: [])
                self.removeDecoder(context: context)
            }

        case .awaitingEnd(let peerChannel):
            if case .end = self.unwrapInboundIn(data) {
                // Upgrade has completed!
                self.upgradeState = .upgradeComplete(pendingBytes: [])
                self.removeDecoder(context: context)
                self.glue(peerChannel, context: context)
            }

        case .awaitingConnection(var pendingBytes):
            // We've seen end, this must not be HTTP anymore. Danger, Will Robinson! Do not unwrap.
            self.upgradeState = .awaitingConnection(pendingBytes: [])
            pendingBytes.append(data)
            self.upgradeState = .awaitingConnection(pendingBytes: pendingBytes)

        case .upgradeComplete(var pendingBytes):
            // We're currently delivering data, keep doing so.
            self.upgradeState = .upgradeComplete(pendingBytes: [])
            pendingBytes.append(data)
            self.upgradeState = .upgradeComplete(pendingBytes: pendingBytes)

        case .upgradeFailed:
            break
        }
    }

    func handlerAdded(context: ChannelHandlerContext) {
        // Add logger metadata.
        logger?("localAddress=\(String(describing: context.channel.localAddress)) remoteAddress=\(String(describing: context.channel.remoteAddress)) channel=\(ObjectIdentifier(context.channel))")
    }
}

extension ConnectHandler: RemovableChannelHandler {
    func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken) {
        var didRead = false

        // We are being removed, and need to deliver any pending bytes we may have if we're upgrading.
        while case .upgradeComplete(var pendingBytes) = self.upgradeState, pendingBytes.count > 0 {
            // Avoid a CoW while we pull some data out.
            self.upgradeState = .upgradeComplete(pendingBytes: [])
            let nextRead = pendingBytes.removeFirst()
            self.upgradeState = .upgradeComplete(pendingBytes: pendingBytes)

            context.fireChannelRead(nextRead)
            didRead = true
        }

        if didRead {
            context.fireChannelReadComplete()
        }

        self.logger?("Removing \(self) from pipeline")
        context.leavePipeline(removalToken: removalToken)
    }
}

extension ConnectHandler {
    private func handleInitialMessage(context: ChannelHandlerContext, data: InboundIn) {
        guard case .head(let head) = data else {
            self.logger?("Invalid HTTP message type \(data)")
            self.httpErrorAndClose(context: context)
            return
        }

        self.logger?("\(head.method) \(head.uri) \(head.version)")

        guard head.method == .CONNECT else {
            self.logger?("Invalid HTTP method: \(head.method)")
            self.httpErrorAndClose(context: context)
            return
        }

        let components = head.uri.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let host = components.first!  // There will always be a first.
        let port = components.last.flatMap { Int($0, radix: 10) } ?? 80  // Port 80 if not specified

        if let monitor {
            var headers: [String: String] = [:]
            for (name, value) in head.headers {
                headers[String(name)] = String(value)
            }
            let method = head.method.rawValue
            logger?("Requesting permission for \(method) \(head.uri)")
            let allow = monitor.connectionMonitorShouldConnect(method: method,
                                                               host: String(host),
                                                               port: port,
                                                               headers: headers)
            if !allow {
                logger?("DENY \(method) \(head.uri)")
                httpErrorAndClose(context: context)
                return
            }
            logger?("ALLOW \(method) \(head.uri)")
        }
        self.upgradeState = .beganConnecting
        self.connectTo(host: String(host), port: port, context: context)
    }

    private func connectTo(host: String, port: Int, context: ChannelHandlerContext) {
        self.logger?("Connecting to \(host):\(port)")

        ClientBootstrap(group: context.eventLoop)
            .connect(host: String(host), port: port).assumeIsolatedUnsafeUnchecked().whenComplete { result in
                switch result {
                case .success(let channel):
                    self.connectSucceeded(channel: channel, context: context)
                case .failure(let error):
                    self.connectFailed(error: error, context: context)
                }
            }
    }

    private func connectSucceeded(channel: Channel, context: ChannelHandlerContext) {
        self.logger?("Connected to \(String(describing: channel.remoteAddress))")

        switch self.upgradeState {
        case .beganConnecting:
            // Ok, we have a channel, let's wait for end.
            self.upgradeState = .awaitingEnd(connectResult: channel)

        case .awaitingConnection(let pendingBytes):
            // Upgrade complete! Begin gluing the connection together.
            self.upgradeState = .upgradeComplete(pendingBytes: pendingBytes)
            self.glue(channel, context: context)

        case .awaitingEnd(let peerChannel):
            // This case is a logic error, close already connected peer channel.
            peerChannel.close(mode: .all, promise: nil)
            context.close(promise: nil)

        case .idle, .upgradeFailed, .upgradeComplete:
            // These cases are logic errors, but let's be careful and just shut the connection.
            context.close(promise: nil)
        }
    }

    private func connectFailed(error: Error, context: ChannelHandlerContext) {
        self.logger?("Connect failed: \(error)")

        switch self.upgradeState {
        case .beganConnecting, .awaitingConnection:
            // We still have a somewhat active connection here in HTTP mode, and can report failure.
            self.httpErrorAndClose(context: context)

        case .awaitingEnd(let peerChannel):
            // This case is a logic error, close already connected peer channel.
            peerChannel.close(mode: .all, promise: nil)
            context.close(promise: nil)

        case .idle, .upgradeFailed, .upgradeComplete:
            // Most of these cases are logic errors, but let's be careful and just shut the connection.
            context.close(promise: nil)
        }

        context.fireErrorCaught(error)
    }

    private func glue(_ peerChannel: Channel, context: ChannelHandlerContext) {
        self.logger?("Gluing together \(ObjectIdentifier(context.channel)) and \(ObjectIdentifier(peerChannel))")

        // Ok, upgrade has completed! We now need to begin the upgrade process.
        // First, send the 200 message.
        // This content-length header is MUST NOT, but we need to workaround NIO's insistence that we set one.
        let headers = HTTPHeaders([("Content-Length", "0")])
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .ok, headers: headers)
        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)

        // Now remove the HTTP encoder.
        self.removeEncoder(context: context)

        // Now we need to glue our channel and the peer channel together.
        let (localGlue, peerGlue) = GlueHandler.matchedPair()
        do {
            try context.channel.pipeline.syncOperations.addHandler(localGlue)
            try peerChannel.pipeline.syncOperations.addHandler(peerGlue)
            context.pipeline.syncOperations.removeHandler(self, promise: nil)
        } catch {
            // Close connected peer channel before closing our channel.
            peerChannel.close(mode: .all, promise: nil)
            context.close(promise: nil)
        }
    }

    private func httpErrorAndClose(context: ChannelHandlerContext) {
        self.upgradeState = .upgradeFailed

        let headers = HTTPHeaders([("Content-Length", "0"), ("Connection", "close")])
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .badRequest, headers: headers)
        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil))).assumeIsolatedUnsafeUnchecked().whenComplete {
            (_: Result<Void, Error>) in
            context.close(mode: .output, promise: nil)
        }
    }

    private func removeDecoder(context: ChannelHandlerContext) {
        // We drop the future on the floor here as these handlers must all be in our own pipeline, and this should
        // therefore succeed fast.
        if let byteToMessageHandlerContext = try? context.pipeline.syncOperations.context(
            handlerType: ByteToMessageHandler<HTTPRequestDecoder>.self
        ) {
            context.pipeline.syncOperations.removeHandler(context: byteToMessageHandlerContext, promise: nil)
        }
    }

    private func removeEncoder(context: ChannelHandlerContext) {
        if let httpResponseEncoderContext = try? context.pipeline.syncOperations.context(
            handlerType: HTTPResponseEncoder.self
        ) {
            context.pipeline.syncOperations.removeHandler(context: httpResponseEncoderContext, promise: nil)
        }
    }
}
