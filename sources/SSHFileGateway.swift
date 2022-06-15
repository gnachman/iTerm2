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
actor SSHFileGateway {
    static let domainName = "iTerm2"
    static let domain = NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(SSHFileGateway.domainName),
                                             displayName: "SSH")
    private var started = false
    var manager: NSFileProviderManager?
    var messages: [MainAppToExtensionPayload.Event] = []

    enum Exception: Error {
        case unavailable
    }

    init() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name("iTermRemoveFileProvider"),
                                               object: nil,
                                               queue: nil) { _ in
            Task {
                log("Remove file provider requested")
                NSFileProviderManager.remove(Self.domain) { removeError in
                    if let removeError = removeError {
                        log("Failed to remove file provider per request: \(removeError.localizedDescription)")
                    } else {
                        log("Succeeded in removing file provider")
                    }
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("iTermAddFileProvider"),
                                               object: nil,
                                               queue: nil) { _ in
            Task {
                log("Add file provider requested")
                NSFileProviderManager.add(Self.domain) { addError in
                    if let addError = addError {
                        log("Failed to add file provider per request: \(addError.localizedDescription)")
                    } else {
                        log("Succeeded in adding file provider")
                    }
                }
            }
        }
    }

    func proxy() async throws -> iTermFileProviderServiceV1 {
        guard let manager = manager else {
            throw Exception.unavailable
        }

        let url = try await manager.getUserVisibleURL(for: .rootContainer)
        log("root url is \(url)")
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
        if started {
            return
        }
        started = true
        manager = nil
        NSFileProviderManager.remove(Self.domain) { removeError in
            log("Remove domain: \(String(describing: removeError))")

            NSFileProviderManager.add(Self.domain) { error in
                if let error = error {
                    logger.error("NSFileProviderManager callback with error: \(error.localizedDescription, privacy: .public)")
                    return
                }
                log("Domain added")
                self.manager = NSFileProviderManager(for: Self.domain)!
            }
        }
        Task {
            while true {
                do {
                    logger.error("creating proxy…")
                    let proxy = try await self.proxy()
                    logger.error("have proxy! call run on it.")
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
        log("SSHFileGateway starting")
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

