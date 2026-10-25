//
//  TaskInputQueue.swift
//  iTerm2
//
//  Bytes a task reads from memory instead of from a file descriptor. A tmux pane's session appends
//  the output its gateway parses from %output, and the pane's TaskIOMonitor reads it from here.
//  This takes the place of the pipe that tmux panes use with TaskNotifier's select loop.
//

import Foundation

@objc(iTermTaskInputQueue)
final class TaskInputQueue: NSObject {
    private struct State {
        // Unread bytes, oldest first, starting at chunks[head]. The first `offset` bytes of that
        // chunk have been read. Chunks before `head` are spent; they are dropped in batches so a
        // long backlog of small chunks doesn't cost a shift per chunk.
        var chunks = [Data]()
        var head = 0
        var offset = 0
        var count = 0
        var closed = false
        var readabilityHandlers = [Int: () -> Void]()
        var nextToken = 0
        var budget: ByteBudget?
    }
    private let state = MutableAtomicObject(State())

    override var description: String {
        let (count, closed) = state.access { ($0.count, $0.closed) }
        return "<TaskInputQueue: \(Unmanaged.passUnretained(self).toOpaque()) count=\(count) closed=\(closed)>"
    }

    // Any thread. Whether a read would return bytes or report the end of the input.
    @objc var isReadable: Bool {
        return state.access { $0.count > 0 || $0.closed }
    }

    @objc var isClosed: Bool {
        return state.access { $0.closed }
    }

    // Any thread. Unread bytes count against this, so a tmux gateway can stop reading while its
    // panes have too much waiting. Changing it moves the unread bytes to the new budget.
    @objc var budget: ByteBudget? {
        get {
            return state.access { $0.budget }
        }
        set {
            state.mutableAccess { state in
                state.budget?.give(state.count)
                state.budget = newValue
                newValue?.take(state.count)
            }
        }
    }

    // Any thread. `handler` is called after bytes are appended and when the queue is closed,
    // without the queue's lock held, on the thread that did it. Returns a token for
    // removeReadabilityHandler(_:). Each reader adds its own, so one that stops reading (such as
    // a task's previous monitor) can't remove another's.
    func addReadabilityHandler(_ handler: @escaping () -> Void) -> Int {
        return state.mutableAccess { state in
            let token = state.nextToken
            state.nextToken += 1
            state.readabilityHandlers[token] = handler
            return token
        }
    }

    // Any thread. The handler is not called again once this returns, unless a call is in progress.
    func removeReadabilityHandler(_ token: Int) {
        state.mutableAccess { _ = $0.readabilityHandlers.removeValue(forKey: token) }
    }

    // Any thread. Adds bytes for the task to read. Ignored once the queue is closed.
    @objc(appendData:)
    func append(_ data: Data) {
        guard !data.isEmpty else {
            return
        }
        let handlers = state.mutableAccess { state -> [() -> Void] in
            guard !state.closed else {
                return []
            }
            state.chunks.append(data)
            state.count += data.count
            state.budget?.take(data.count)
            return Array(state.readabilityHandlers.values)
        }
        handlers.forEach { $0() }
    }

    // Any thread. Ends the input. Bytes not read yet are discarded, and reads report the end of
    // the input from now on.
    @objc
    func close() {
        let (handlers, discarded) = state.mutableAccess { state -> ([() -> Void], Int?) in
            guard !state.closed else {
                return ([], nil)
            }
            let discarded = state.count
            state.budget?.give(discarded)
            state.closed = true
            state.chunks = []
            state.head = 0
            state.offset = 0
            state.count = 0
            return (Array(state.readabilityHandlers.values), discarded)
        }
        if let discarded {
            RLog("Closed \(self), discarding \(discarded) unread bytes")
        }
        handlers.forEach { $0() }
    }

    // Any thread. Copies up to `maxLength` of the oldest unread bytes into `buffer` and returns how
    // many it copied. Sets `endOfFile` once the queue is closed.
    @objc(readInto:maxLength:endOfFile:)
    func read(into buffer: UnsafeMutableRawPointer,
              maxLength: Int,
              endOfFile: UnsafeMutablePointer<ObjCBool>) -> Int {
        return state.mutableAccess { state in
            endOfFile.pointee = ObjCBool(state.closed)
            var copied = 0
            while copied < maxLength, state.head < state.chunks.count {
                let chunk = state.chunks[state.head]
                let length = min(maxLength - copied, chunk.count - state.offset)
                chunk.withUnsafeBytes { bytes in
                    (buffer + copied).copyMemory(from: bytes.baseAddress! + state.offset,
                                                 byteCount: length)
                }
                copied += length
                state.offset += length
                if state.offset == chunk.count {
                    state.head += 1
                    state.offset = 0
                }
            }
            if state.head == state.chunks.count {
                state.chunks.removeAll(keepingCapacity: true)
                state.head = 0
            } else if state.head >= 64 && state.head * 2 >= state.chunks.count {
                state.chunks.removeFirst(state.head)
                state.head = 0
            }
            state.count -= copied
            state.budget?.give(copied)
            return copied
        }
    }
}
