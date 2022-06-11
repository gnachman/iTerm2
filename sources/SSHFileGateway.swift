//
//  SSHFileGateway.swift
//  iTermFileProvider
//
//  Created by George Nachman on 6/5/22.
//

import Foundation
import AppKit
import FileProvider
import FileProviderService
import OSLog

@available(macOS 11.0, *)
let logger = Logger(subsystem: "com.googlecode.iterm2.SSHFileGateway", category: "default")

protocol SSHFileGatewayDelegate {
    @available(macOS 11.0, *)
    func handleSSHFileRequest(_ request: ExtensionToMainAppPayload.Event.Kind) async -> MainAppToExtensionPayload.Event.Kind
}

@available(macOS 11.0, *)
class SSHFileGateway {
    static let domainName = "iTerm2"
    static let domain = NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(SSHFileGateway.domainName),
                                             displayName: "SSH")
    static let instance = SSHFileGateway()
    var manager: NSFileProviderManager?
    var messages: [MainAppToExtensionPayload.Event] = []

    enum Exception: Error {
        case unavailable
    }

    init() {
        manager = nil
        NSFileProviderManager.add(Self.domain) { error in
            if let error = error {
                logger.error("NSFileProviderManager callback with error: \(error.localizedDescription, privacy: .public)")
                return
            }
            self.manager = NSFileProviderManager(for: Self.domain)!
        }
    }

    func proxy() async throws -> iTermFileProviderServiceV1 {
        guard let manager = manager else {
            throw Exception.unavailable
        }

        let url = try await manager.getUserVisibleURL(for: .rootContainer)
        NSLog("root url is \(url)")
        let services = try await FileManager().fileProviderServicesForItem(at: url)
        guard let service = services.values.first else {
            logger.error("No service for \(url, privacy: .public)")
            throw Exception.unavailable
        }
        let connection = try await service.fileProviderConnection()
        connection.remoteObjectInterface = iTermFileProviderServiceInterface
        connection.interruptionHandler = {
            logger.error("service connection interrupted")
        }
        connection.resume()
        guard let proxy = connection.remoteObjectProxy as? iTermFileProviderServiceV1 else {
            throw NSFileProviderError(.serverUnreachable)
         }
        return proxy
     }

    func start(delegate: SSHFileGatewayDelegate) {
        Task {
            while true {
                do {
                    let proxy = try await self.proxy()
                    try await run(proxy, delegate)
                } catch {
                    logger.error("Failed to start proxy: \(String(describing: error), privacy: .public)")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }

    private func run(_ proxy: iTermFileProviderServiceV1,
                     _ delegate: SSHFileGatewayDelegate) async throws {
        while true {
            let messages = self.messages
            self.messages.removeAll()
            logger.debug("Send to extension: \(messages.map { $0.debugDescription }.joined(separator: " | "), privacy: .public)")
            let e2m = try await proxy.poll(MainAppToExtension(events: messages)).value
            logger.debug("Poll returned with \(e2m.debugDescription, privacy: .public)")

            for request in e2m.events {
                let result = await delegate.handleSSHFileRequest(request.kind)

                let response = request.response(result)
                self.messages.append(response)
            }
        }
    }
}

