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

struct Sleeper {
    private var stream: AsyncStream<Void>? = nil
    private var unblock: () -> ()
    private var iter: AsyncStream<Void>.AsyncIterator? = nil
    private var count = 0
    init() {
        unblock = {}
        stream = AsyncStream<Void> { continuation in
            unblock = {
                continuation.yield()
            }
        }
        iter = stream!.makeAsyncIterator()
    }

    mutating func wait() async {
        await iter!.next()
        count -= 1
        precondition(count == 0)
    }

    mutating func wake() {
        if count > 0 {
            return
        }
        count += 1
        unblock()
    }
}

struct ChunkingQueue<T> {
    private var elements = [T]()
    private var sleeper = Sleeper()

    mutating func drain() async -> [T] {
        while elements.isEmpty {
            await sleeper.wait()
        }
        return drainIfPossible()
    }

    mutating func drainIfPossible() -> [T] {
        let result = elements
        elements.removeAll()
        return result
    }

    mutating func append(_ element: T) {
        elements.append(element)
        sleeper.wake()
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

    weak var ext: FileProviderExtension?
    let listeners = NSHashTable<NSXPCListener>()
    private var queue = ChunkingQueue<ExtensionToMainAppPayload.Event>()

    // eventID -> request
    private var outstandingRequests = [String: ExtensionOriginatedRequest]()
    init(_ ext: FileProviderExtension) {
        self.ext = ext
    }

    // Handle poll from main app.
    func poll(_ wrapper: MainAppToExtension) async throws -> ExtensionToMainApp {
        alive = true
        let m2e = wrapper.value
        logger.debug("FileProviderServiceServer: poll \(m2e.debugDescription, privacy: .public)")
        let e2m: [ExtensionToMainAppPayload.Event]
        if m2e.events.isEmpty {
            logger.debug("FileProviderServiceServer: draining")
            e2m = await queue.drain()
        } else {
            e2m = queue.drainIfPossible()
        }
        logger.debug("FileProviderServiceServer: will handle: \(m2e.debugDescription, privacy: .public)")
        for event in m2e.events {
            handle(event)
        }
        return ExtensionToMainApp(events: e2m)
    }

    private func handle(_ event: MainAppToExtensionPayload.Event) {
        logger.debug("FileProviderServiceServer: handle \(event.debugDescription, privacy: .public)")
        outstandingRequests.removeValue(forKey: event.eventID)?.handler(event.kind)
    }

    private func enqueue(_ e2m: ExtensionToMainAppPayload.Event) {
        queue.append(e2m)
    }

    func sendRequest(_ kindToSend: ExtensionToMainAppPayload.Event.Kind,
                     handler: @escaping (MainAppToExtensionPayload.Event.Kind) -> ()) throws {
        if !alive {
            throw Exception.notReady
        }
        let request = ExtensionOriginatedRequest(outboundEvent: ExtensionToMainAppPayload.Event(kind: kindToSend),
                                                 handler: handler)
        logger.debug("FileProviderServiceServer: sendRequest \(request.outboundEvent.debugDescription, privacy: .public)")
        outstandingRequests[request.outboundEvent.eventID] = request
        queue.append(request.outboundEvent)
    }
}
