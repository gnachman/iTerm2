import Foundation
import CoreServices

/// The stream operations are confined to the watcher's serial worker queue.
protocol iTermFileTreeWatchStream: AnyObject {
    func start() -> Bool
    func close()
}

/// FSEvents registration can block in the daemon. The caller only updates desired state;
/// stream creation, registration, stopping and destruction all run on a dedicated queue.
final class iTermFileTreeWatcher {
    typealias StreamFactory = (String, DispatchQueue, @escaping ([String]) -> Void) -> iTermFileTreeWatchStream?
    private struct Request: Equatable {
        let root: String?
        let identifier: UUID
    }

    /// This lock protects only request identity, and is never held during native stream work.
    private final class Requests {
        private let lock = NSLock()
        private var current = Request(root: nil, identifier: UUID())

        func replace(root: String?, force: Bool = false) -> Request? {
            lock.lock()
            defer { lock.unlock() }
            guard force || root != current.root else { return nil }
            current = Request(root: root, identifier: UUID())
            return current
        }
        func isCurrent(_ request: Request) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return current == request
        }
        func failed(_ request: Request) {
            lock.lock()
            defer { lock.unlock() }
            if current == request { current = Request(root: nil, identifier: UUID()) }
        }
    }

    /// Owned by queued operations after the public watcher is released. Native callbacks do
    /// not retain this worker, so its active stream cannot form a retain cycle through context.
    private final class Worker {
        let queue: DispatchQueue
        let requests: Requests
        let makeStream: StreamFactory
        let onEvents: (String, [String]) -> Void
        private var active: iTermFileTreeWatchStream?

        init(queue: DispatchQueue, requests: Requests, makeStream: @escaping StreamFactory,
             onEvents: @escaping (String, [String]) -> Void) {
            self.queue = queue
            self.requests = requests
            self.makeStream = makeStream
            self.onEvents = onEvents
        }
        func apply(_ request: Request) {
            guard requests.isCurrent(request) else { return }
            active?.close()
            active = nil
            guard let root = request.root, requests.isCurrent(request) else { return }
            let requests = self.requests
            let onEvents = self.onEvents
            let deliver: ([String]) -> Void = { paths in
                guard requests.isCurrent(request) else { return }
                DispatchQueue.main.async {
                    guard requests.isCurrent(request) else { return }
                    onEvents(root, paths)
                }
            }
            guard let stream = makeStream(root, queue, deliver) else {
                requests.failed(request)
                return
            }
            // A new request can supersede a slow create or daemon registration.
            guard requests.isCurrent(request) else { stream.close(); return }
            let started = stream.start()
            if started && requests.isCurrent(request) {
                active = stream
            } else {
                stream.close()
                if !started { requests.failed(request) }
            }
        }
    }

    private let requests = Requests()
    private let worker: Worker

    init(queue: DispatchQueue = DispatchQueue(label: "com.iterm2.file-tree-watch", qos: .utility),
         makeStream: @escaping StreamFactory = { root, queue, events in
             iTermFileTreeNativeWatchStream(root: root, queue: queue, onEvents: events)
         }, onEvents: @escaping (String, [String]) -> Void) {
        worker = Worker(queue: queue, requests: requests, makeStream: makeStream, onEvents: onEvents)
    }

    func watch(root: String) { update(root: root) }
    func stop() { update(root: nil) }

    private func update(root: String?) {
        guard let request = requests.replace(root: root) else { return }
        let worker = self.worker
        worker.queue.async { worker.apply(request) }
    }

    deinit {
        // Capture a live worker value, never the deinitializing watcher. Callbacks are
        // rejected immediately; even a blocked registration is retired when it returns.
        if let request = requests.replace(root: nil, force: true) {
            let worker = self.worker
            worker.queue.async { worker.apply(request) }
        }
    }
}

private final class iTermFileTreeNativeWatchStream: iTermFileTreeWatchStream {
    private final class Context {
        let onEvents: ([String]) -> Void
        init(onEvents: @escaping ([String]) -> Void) { self.onEvents = onEvents }
    }
    private var stream: FSEventStreamRef?
    private var started = false

    init?(root: String, queue: DispatchQueue, onEvents: @escaping ([String]) -> Void) {
        let context = Context(onEvents: onEvents)
        var nativeContext = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(context).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<Context>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                if let info { Unmanaged<Context>.fromOpaque(info).release() }
            },
            copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, { _, info, count, paths, _, _ in
            guard let info else { return }
            let context = Unmanaged<Context>.fromOpaque(info).takeUnretainedValue()
            // UseCFTypes supplies a CFArray of CFStrings under the Get rule. Copy the
            // bridged Swift strings before returning; no borrowed native buffer escapes.
            let array = Unmanaged<NSArray>.fromOpaque(paths).takeUnretainedValue()
            guard array.count == count else { return }
            let copied = array.compactMap { value -> String? in
                guard let path = value as? String else { return nil }
                return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
            }
            if !copied.isEmpty { context.onEvents(copied) }
        }, &nativeContext, [root] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
    }

    func start() -> Bool {
        guard let stream else { return false }
        started = FSEventStreamStart(stream)
        return started
    }

    func close() {
        guard let stream else { return }
        self.stream = nil
        if started { FSEventStreamStop(stream) }
        // Invalidate while still scheduled, as required by FSEventStreamSetDispatchQueue.
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    deinit { close() }
}
