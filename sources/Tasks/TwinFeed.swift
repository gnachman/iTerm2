//
//  TwinFeed.swift
//  iTerm2SharedARC
//
//  A twin session's task reads a copy of what a live session's task reads.
//

import Foundation

/// The job manager of a twin session's task. The task reads the bytes a live session's task
/// read, from a pipe or an input queue that a `TwinFeed` fills. There is no program.
@objc(iTermTwinJobManager)
final class TwinJobManager: iTermTmuxJobManager {
    override var description: String {
        return "<TwinJobManager: \(Unmanaged.passUnretained(self).toOpaque()) fd=\(String(describing: ownedFileDescriptor)) inputQueue=\(String(describing: inputQueue))>"
    }
}

/// Copies what a live session's task reads to a twin session's task. The live task must never
/// wait for the twin, so the copy stops when the twin falls too far behind.
@objc(iTermTwinFeed)
final class TwinFeed: NSObject {
    private static let maximumPendingBytes = 32 * 1024 * 1024

    private let queue = DispatchQueue(label: "com.iterm2.twin-feed")
    // Blocking, so the twin's task reading it limits how fast the queue writes.
    private let writeHandle: FileHandle?
    private let inputQueue: TaskInputQueue?
    private struct State {
        var pendingBytes = 0
        var stopped = false
    }
    private let state = MutableAtomicObject(State())

    /// Main queue. Called once if the twin falls too far behind. The feed has stopped by then.
    @objc var fellBehind: (() -> Void)?

    private init(writeHandle: FileHandle?, inputQueue: TaskInputQueue?) {
        self.writeHandle = writeHandle
        self.inputQueue = inputQueue
    }

    /// Makes `task` read what this feed is given. Returns nil if that is not possible.
    @objc(feedReadByTask:)
    static func feed(readBy task: PTYTask) -> TwinFeed? {
        if TaskNotifier.usesTaskIOMonitors() {
            let inputQueue = TaskInputQueue()
            let feed = TwinFeed(writeHandle: nil, inputQueue: inputQueue)
            task.readingTwinFeed = feed
            task.readTwinOutput(from: inputQueue)
            return feed
        }
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else {
            DLog("pipe failed: \(String(cString: strerror(errno)))")
            return nil
        }
        // The task notifier must not block reading it.
        _ = fcntl(fds[0], F_SETFL, fcntl(fds[0], F_GETFL) | O_NONBLOCK)
        _ = fcntl(fds[1], F_SETFL, fcntl(fds[1], F_GETFL) & ~O_NONBLOCK)
        let feed = TwinFeed(writeHandle: FileHandle(fileDescriptor: fds[1], closeOnDealloc: true),
                            inputQueue: nil)
        task.readingTwinFeed = feed
        task.readTwinOutput(from: OwnedFileDescriptor(fds[0]))
        return feed
    }

    /// Any thread. Bytes given to the twin that it has not parsed yet.
    @objc var pendingByteCount: Int {
        return state.access { $0.pendingBytes }
    }

    /// The twin task's reading thread. The twin parsed this many bytes.
    @objc(twinDidRead:)
    func twinDidRead(_ length: Int32) {
        state.mutableAccess { $0.pendingBytes -= Int(length) }
    }

    /// The live task's reading thread. Copies the bytes for the twin. Returns false when the twin
    /// fell too far behind, in which case the feed stops.
    @objc(appendBytes:length:)
    func append(_ bytes: UnsafePointer<CChar>, length: Int32) -> Bool {
        guard length > 0 else {
            return true
        }
        let count = Int(length)
        let accepted = state.mutableAccess { state -> Bool? in
            if state.stopped {
                return nil
            }
            if state.pendingBytes + count > Self.maximumPendingBytes {
                state.stopped = true
                return false
            }
            state.pendingBytes += count
            return true
        }
        guard let accepted else {
            return true
        }
        guard accepted else {
            RLog("Twin fell behind. Stop feeding it.")
            giveUp()
            return false
        }
        let data = Data(bytes: bytes, count: count)
        if let inputQueue {
            inputQueue.append(data)
            return true
        }
        queue.async { [weak self] in
            guard let self else {
                return
            }
            guard !self.state.access({ $0.stopped }) else {
                return
            }
            do {
                try self.writeHandle?.write(contentsOf: data)
            } catch {
                let first = self.state.mutableAccess { state -> Bool in
                    defer { state.stopped = true }
                    return !state.stopped
                }
                if first {
                    RLog("Writing to the twin failed: \(error)")
                    self.giveUp()
                }
            }
        }
        return true
    }

    /// The twin no longer gets every byte, so it stops and its window replaces it.
    private func giveUp() {
        close()
        // The live task may let go of the feed now, so keep it until the callback ran.
        DispatchQueue.main.async {
            self.fellBehind?()
            self.fellBehind = nil
        }
    }

    /// Any thread. Ends the twin's input, so its task reads the end of the file.
    @objc func close() {
        state.mutableAccess { $0.stopped = true }
        inputQueue?.close()
        queue.async { [writeHandle] in
            try? writeHandle?.close()
        }
    }
}
