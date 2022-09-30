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
let logger = iTermLogger()

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
        log("proxy(): Trying to start proxy")
        guard let manager = manager else {
            log("proxy(): Can't start proxy: no manager yet.")
            throw Exception.unavailable
        }

        let url = try await manager.getUserVisibleURL(for: .rootContainer)
        log("proxy(): root url is \(url)")
        let services = try await FileManager().fileProviderServicesForItem(at: url)
        guard let service = services.values.first else {
            log("proxy(): No service for \(url)")
            throw Exception.unavailable
        }
        let connection = try await service.fileProviderConnection()
        connection.remoteObjectInterface = iTermFileProviderServiceInterface
        connection.interruptionHandler = {
            log("proxy(): service connection interrupted")
        }
        connection.resume()
        guard let proxy = connection.remoteObjectProxy as? iTermFileProviderServiceV1 else {
            log("proxy(): throw serverUnreachable with ROP \(String(describing: connection.remoteObjectProxy))")
            throw NSFileProviderError(.serverUnreachable)
         }
        log("proxy(): success")
        return proxy
     }

    func start(delegate: SSHFileGatewayDelegate) {
        if started {
            return
        }
        started = true
        log("start(): Set manager to nil and will remove it prior to adding")
        manager = nil
        NSFileProviderManager.remove(Self.domain) { removeError in
            log("start(): Remove domain: \(String(describing: removeError))")

            NSFileProviderManager.add(Self.domain) { error in
                if let error = error {
                    log("start(): NSFileProviderManager callback with error: \(error.localizedDescription)")
                    return
                }
                log("start(): Domain added")
                self.manager = NSFileProviderManager(for: Self.domain)!
                log("start(): manager is now \(String(describing: self.manager))")
            }
        }
        Task {
            while true {
                do {
                    log("creating proxy…")
                    let proxy = try await self.proxy()
                    log("have proxy! call run on it.")
                    try await run(proxy, delegate)
                } catch {
                    log("Failed to start proxy: \(String(describing: error))")
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
            log("Send to extension: \(messages.map { $0.debugDescription }.joined(separator: " | "))")
            let e2m = try await proxy.poll(MainAppToExtension(events: messages)).value
            log("Poll returned with \(e2m.debugDescription)")

            for request in e2m.events {
                let result = await delegate.handleSSHFileRequest(request.kind)

                let response = request.response(result)
                self.messages.append(response)
            }
        }
    }
}

