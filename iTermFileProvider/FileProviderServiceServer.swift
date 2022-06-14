//
//  FileProviderServiceServer.swift
//  iTermFileProvider
//
//  Created by George Nachman on 6/5/22.
//

import Foundation
import FileProvider
import FileProviderService

fileprivate func synchronized<T>(_ lock: AnyObject, _ closure: () throws -> T) rethrows -> T {
  objc_sync_enter(lock)
  defer { objc_sync_exit(lock) }
  return try closure()
}

actor ChunkingQueue<T> where T: CustomDebugStringConvertible {
    private var elements = [T]()
    private var completion: ((Result<[T], Error>) -> ())?

    enum Exception: Error {
        case superceded
    }

    func drain() async throws -> [T] {
        return try await withCheckedThrowingContinuation { continuation in
            get {
                switch $0 {
                case .failure(let error):
                    log("ChunkingQueue: drain failed")
                    continuation.resume(with: .failure(error))
                case .success(let value):
                    log("ChunkingQueue: drain succeeded")
                    continuation.resume(with: .success(value))
                }
            }
        }
    }

    func tryDrain() -> [T] {
        evictIfNeeded()
        defer {
            elements.removeAll()
        }
        return elements
    }

    private func evictIfNeeded() {
        if let existing = self.completion {
            self.completion = nil
            log("ChunkingQueue: evicting. nil completion.")
            existing(.failure(Exception.superceded))
        }
    }

    private func get(_ completion: @escaping (Result<[T], Error>) -> ()) {
        evictIfNeeded()
        log("ChunkingQueue: get: Set completion")
        self.completion = completion
        completeIfPossible()
    }

    private func completeIfPossible() {
        guard let completion = completion else {
            log("ChunkingQueue: completeIfPossible: no completion registered")
            return
        }
        guard !elements.isEmpty else {
            log("ChunkingQueue: completeIfPossible: queue is empty")
            return
        }
        log("ChunkingQueue: completeIfPossible: nil completion before calling existing handler")
        self.completion = nil
        let result = elements
        elements.removeAll()
        log("ChunkingQueue: draining \(result)")
        completion(.success(result))
    }

    func append(_ element: T) {
        log("ChunkingQueue: append(\(element.debugDescription))")
        elements.append(element)
        completeIfPossible()
    }
}

struct ExtensionOriginatedRequest {
    let outboundEvent: ExtensionToMainAppPayload.Event
    let handler: (MainAppToExtensionPayload.Event.Kind) -> ()
}

extension MainAppToExtensionPayload.Event {
    func response(_ kind: ExtensionToMainAppPayload.Event.Kind) -> ExtensionToMainAppPayload.Event {
        return ExtensionToMainAppPayload.Event(kind: kind, eventID: eventID)
    }
}

class FileProviderService: NSObject, NSFileProviderServiceSource, NSXPCListenerDelegate, iTermFileProviderServiceV1 {
    enum Exception: Error {
        case notReady
    }

    private(set) var alive = false
    var serviceName: NSFileProviderServiceName {
        iTermFileProviderServiceName
    }

    func makeListenerEndpoint() throws -> NSXPCListenerEndpoint {
        let listener = NSXPCListener.anonymous()
        listener.delegate = self
        synchronized(self) {
            listeners.add(listener)
        }

        listener.resume()
        return listener.endpoint
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = iTermFileProviderServiceInterface
        newConnection.exportedObject = self

        synchronized(self) {
            listeners.remove(listener)
        }

        newConnection.resume()
        return true
    }

    let listeners = NSHashTable<NSXPCListener>()
    private var queue = ChunkingQueue<ExtensionToMainAppPayload.Event>()

    // eventID -> request
    private var outstandingRequests = [String: ExtensionOriginatedRequest]()

    // Handle poll from main app.
    func poll(_ wrapper: MainAppToExtension) async throws -> ExtensionToMainApp {
        log("FileProviderServiceServer: Starting")
        alive = true
        let m2e = wrapper.value
        log("FileProviderServiceServer: poll \(m2e.debugDescription)")
        let e2m: [ExtensionToMainAppPayload.Event]
        if m2e.events.isEmpty {
            log("FileProviderServiceServer: draining")
            e2m = try await queue.drain()
        } else {
            log("FileProviderServiceServer: tryDrain (there are \(m2e.events.count) main->extension events to handle if queue is empty)")
            e2m = await queue.tryDrain()
        }
        log("FileProviderServiceServer: will handle: \(m2e.debugDescription)")
        for event in m2e.events {
            handle(event)
        }
        log("FileProviderServiceServer: poll returning")
        return ExtensionToMainApp(events: e2m)
    }

    private func handle(_ event: MainAppToExtensionPayload.Event) {
        log("FileProviderServiceServer: handle \(event.debugDescription)")
        outstandingRequests.removeValue(forKey: event.eventID)?.handler(event.kind)
    }

    private func enqueue(_ e2m: ExtensionToMainAppPayload.Event) {
        Task {
            await queue.append(e2m)
        }
    }

    func sendRequest(_ kindToSend: ExtensionToMainAppPayload.Event.Kind,
                     handler: @escaping (MainAppToExtensionPayload.Event.Kind) -> ()) throws {
        if !alive {
            log("FileProviderServiceServer: not yet alive so sendRequest returning serverUnreachable.")
            throw NSFileProviderError(.serverUnreachable)
        }
        let request = ExtensionOriginatedRequest(outboundEvent: ExtensionToMainAppPayload.Event(kind: kindToSend),
                                                 handler: handler)
        log("FileProviderServiceServer: sendRequest \(request.outboundEvent.debugDescription)")
        outstandingRequests[request.outboundEvent.eventID] = request
        Task {
            await queue.append(request.outboundEvent)
        }
    }
}
