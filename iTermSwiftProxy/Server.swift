//
//  iTermSwiftPackages.swift
//  iTermSwiftPackages
//
//  Created by George Nachman on 6/29/25.
//

import Foundation
internal import NIOCore
internal import NIOHTTP1
internal import NIOPosix

public class Server {
    struct BindFailedError: Error {}
    public static let instance = Server()
    private let portFuture: EventLoopFuture<Int>
    private let group: EventLoopGroup
    private let lock = DispatchQueue(label: "server.port.lock")
    private var _port: Int?
    public weak var monitor: ConnectionMonitor?
    private var _logger: ((@autoclosure () -> String) -> ())?
    public var logger: ((@autoclosure () -> String) -> ())? {
        get {
            lock.sync { _logger }
        }
        set {
            lock.sync { _logger = newValue }
        }
    }

    private init() {
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let promise = group.next().makePromise(of: Int.self)
        self.portFuture = promise.futureResult
        portFuture.whenSuccess { [weak self] port in
            self?.lock.sync { self?._port = port }
        }
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(.init(SOL_SOCKET), .init(SO_REUSEADDR)), value: 1)
            .childChannelOption(ChannelOptions.socket(.init(SOL_SOCKET), .init(SO_REUSEADDR)), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(
                        ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes))
                    )
                    try channel.pipeline.syncOperations.addHandler(HTTPResponseEncoder())
                    let connectHandler = ConnectHandler(logger: self.logger)
                    connectHandler.monitor = self.monitor
                    try channel.pipeline.syncOperations.addHandler(connectHandler)
                }
            }
        tryToBind(bootstrap: bootstrap, port: 1912, attempsLeft: 10, promise: promise)
    }

    public var portIfRunning: Int? {
        return lock.sync { _port }
    }

    public func ensureRunning() async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            portFuture.whenSuccess { port in
                continuation.resume(returning: port)
            }
            portFuture.whenFailure { error in
                continuation.resume(throwing: error)
            }
        }
    }

    private func tryToBind(bootstrap: ServerBootstrap, port: Int, attempsLeft: Int, promise: EventLoopPromise<Int>) {
        let address: SocketAddress
        do {
            address = try SocketAddress(ipAddress: "127.0.0.1", port: port)
        } catch {
            promise.fail(error)
            return
        }
        bootstrap.bind(to: address).whenComplete { result in
            // Need to create this here for thread-safety purposes
            switch result {
            case .success(let channel):
                self.logger?("Listening on \(String(describing: channel.localAddress))")
                promise.succeed(port)
            case .failure(let error):
                self.logger?("Failed to bind 127.0.0.1:8080, \(error)")
                if attempsLeft == 0 {
                    promise.fail(error)
                    return
                }
                self.tryToBind(bootstrap: bootstrap,
                               port: port + 1,
                               attempsLeft: attempsLeft - 1,
                               promise: promise)
            }
        }
    }
}
