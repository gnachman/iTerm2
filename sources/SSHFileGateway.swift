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
                do {
                    try await NSFileProviderManager.remove(Self.domain)
                    log("Succeeded in removing file provider")
                } catch {
                    log("Failed to remove file provider per request: \(error.localizedDescription)")
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("iTermAddFileProvider"),
                                               object: nil,
                                               queue: nil) { _ in
            Task {
                log("Add file provider requested")
                do {
                    try await NSFileProviderManager.add(Self.domain)
                    log("Succeeded in adding file provider")
                } catch {
                    log("Failed to add file provider per request: \(error.localizedDescription)")
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

        FileManager().getFileProviderServicesForItem(at: url) { services, error in

        }

        return try await withCheckedThrowingContinuation { checkedContinuation in
            FileManager().getFileProviderServicesForItem(at: url) { services, error in
                SSHFileGateway.handleServices(services,
                                              error: error,
                                              checkedContinuation: checkedContinuation)
            }
        }
     }

    private static func handleServices(_ services: [NSFileProviderServiceName: NSFileProviderService]?,
                                       error: Error?,
                                       checkedContinuation: CheckedContinuation<iTermFileProviderServiceV1, Error>) {
        if let error {
            checkedContinuation.resume(with: .failure(error))
            return
        }
        guard let service = services?.values.first else {
            log("proxy(): No service found")
            checkedContinuation.resume(with: .failure(Exception.unavailable))
            return
        }

        service.getFileProviderConnection { xpcConnection, xpcError in
            guard let connection = xpcConnection else {
                checkedContinuation.resume(with: .failure(xpcError!))
                return
            }
            connection.remoteObjectInterface = iTermFileProviderServiceInterface
            connection.interruptionHandler = {
                log("proxy(): service connection interrupted")
            }
            connection.resume()
            guard let proxy = connection.remoteObjectProxy as? iTermFileProviderServiceV1 else {
                log("proxy(): throw serverUnreachable with ROP \(String(describing: connection.remoteObjectProxy))")
                checkedContinuation.resume(with: .failure(NSFileProviderError(.serverUnreachable)))
                return
            }
            log("proxy(): success")
            checkedContinuation.resume(with: .success(proxy))
        }
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

