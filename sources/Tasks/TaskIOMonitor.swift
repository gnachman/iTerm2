//
//  TaskIOMonitor.swift
//  iTerm2
//
//  Services one task's file descriptor, and its coprocess's, with dispatch sources on a serial
//  queue of its own. Unlike TaskNotifier's select loop, a task that is slow to consume what it
//  reads never holds up another task. Nothing here blocks: when the task can't take more input,
//  the read source is suspended until the task says there is room again.
//
//  Each dispatch source holds a lease on the descriptor it watches until its cancel handler runs,
//  so closing the descriptor (for example, by -[Coprocess terminate]) waits until no source can use
//  it, and its number can't be reused while one does.
//

import Foundation

@objc(iTermTaskIOMonitor)
final class TaskIOMonitor: NSObject {
    private enum State {
        case idle
        case running
        case cancelled
    }

    // A dispatch source that tracks whether it is suspended, so suspends and resumes stay balanced.
    // A source must not be released or cancelled while suspended, so cancel() resumes it first.
    private final class Source {
        let source: DispatchSourceProtocol
        private(set) var suspended = false
        private var cancelled = false

        init(_ source: DispatchSourceProtocol, suspended: Bool) {
            self.source = source
            if suspended {
                suspend()
            }
        }

        // True if it is watching for events.
        var active: Bool {
            return !suspended && !cancelled
        }

        func suspend() {
            guard !suspended, !cancelled else {
                return
            }
            suspended = true
            source.suspend()
        }

        func resume() {
            guard suspended, !cancelled else {
                return
            }
            suspended = false
            source.resume()
        }

        func cancel() {
            guard !cancelled else {
                return
            }
            resume()
            cancelled = true
            source.cancel()
        }
    }

    private final class CoprocessIO {
        let coprocess: Coprocess
        let readFileDescriptor: Int32
        let writeFileDescriptor: Int32
        let read: Source
        let write: Source

        init(coprocess: Coprocess,
             readFileDescriptor: Int32,
             writeFileDescriptor: Int32,
             read: Source,
             write: Source) {
            self.coprocess = coprocess
            self.readFileDescriptor = readFileDescriptor
            self.writeFileDescriptor = writeFileDescriptor
            self.read = read
            self.write = write
        }

        func cancel() {
            read.cancel()
            write.cancel()
        }
    }

    let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Bool>()
    private let task: iTermTask
    private let fd: Int32
    // Taken at registration so the descriptor can't be closed before the sources exist. start()
    // hands them to the read and write sources.
    private var pendingLeases: (read: OwnedFileDescriptor.Lease, write: OwnedFileDescriptor.Lease)?
    private let reap: (pid_t) -> Void
    private let coprocessDidChange: () -> Void
    // Entered once for the monitor and once for each source. Empty once the monitor is cancelled
    // and every source's cancel handler has run, after which no file descriptor is used again.
    private let cancellation = DispatchGroup()

    // Access only on `queue`.
    private var state = State.idle
    private var readSource: Source?
    private var writeSource: Source?
    // A capacity-available callback is pending.
    private var awaitingReadCapacity = false
    private var coprocessIO: CoprocessIO?
    // Sources whose cancel handlers have not run yet, including ones no longer referenced above.
    private var liveSources = 0

    // `reap` is called with the pid of a coprocess that has ended. `coprocessDidChange` is called
    // after a coprocess that ended is removed from the task. Both are called on the monitor's queue.
    init(task: iTermTask,
         fileDescriptor: OwnedFileDescriptor,
         reap: @escaping (pid_t) -> Void,
         coprocessDidChange: @escaping () -> Void) {
        self.task = task
        if let read = fileDescriptor.lease(), let write = fileDescriptor.lease() {
            pendingLeases = (read: read, write: write)
            fd = read.fileDescriptor
        } else {
            fd = -1
        }
        self.reap = reap
        self.coprocessDidChange = coprocessDidChange
        queue = DispatchQueue(label: "com.iterm2.task-io", autoreleaseFrequency: .workItem)
        super.init()
        queue.setSpecific(key: queueKey, value: true)
        cancellation.enter()
    }

    override var description: String {
        return "<TaskIOMonitor: \(Unmanaged.passUnretained(self).toOpaque()) fd=\(fd) task=\(task)>"
    }

    // False if the descriptor was already closed when the monitor was made, so it has nothing to
    // service.
    var hasFileDescriptor: Bool {
        return fd >= 0
    }

    // Any thread. Starts servicing the task.
    func start() {
        queue.async { [self] in
            guard state == .idle else {
                return
            }
            DLog("Start \(self)")
            state = .running
            guard let leases = pendingLeases else {
                // The registry doesn't register a monitor without a descriptor.
                return
            }
            pendingLeases = nil
            readSource = makeSource(DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue),
                                    lease: leases.read,
                                    suspended: false) { [weak self] in
                self?.handleRead()
            }
            writeSource = makeSource(DispatchSource.makeWriteSource(fileDescriptor: fd, queue: queue),
                                     lease: leases.write,
                                     suspended: true) { [weak self] in
                self?.handleWrite()
            }
            update()
        }
    }

    // Any thread. Stops servicing the task. Safe to call more than once. When called on the
    // monitor's queue (for example, from the task's brokenPipe) no event handler runs after it
    // returns.
    func cancel() {
        onQueue { [self] in
            guard state != .cancelled else {
                return
            }
            DLog("Cancel \(self)")
            state = .cancelled
            // Cancelled before it started.
            pendingLeases?.read.release()
            pendingLeases?.write.release()
            pendingLeases = nil
            readSource?.cancel()
            writeSource?.cancel()
            coprocessIO?.cancel()
            readSource = nil
            writeSource = nil
            coprocessIO = nil
            cancellation.leave()
        }
    }

    // Any thread. Runs `block` on the monitor's queue once the monitor has been cancelled and no
    // longer uses any file descriptor.
    func notifyWhenCancelled(_ block: @escaping () -> Void) {
        cancellation.notify(queue: queue, execute: block)
    }

    // Any thread. Call after something changes what the task's wantsRead, wantsWrite, or
    // coprocess return. This is the counterpart of -[TaskNotifier unblock].
    func taskStateDidChange() {
        queue.async { [self] in
            update()
        }
    }

    // Testing only. Calls `completion` on the monitor's queue once nothing is ready that one of
    // its active sources would handle, and every source it stopped using has let go of its
    // descriptor. This waits for events the kernel has not delivered yet, so call it only when
    // nothing else is adding input.
    func flushForTesting(_ completion: @escaping () -> Void) {
        queue.async { [self] in
            if state == .cancelled {
                notifyWhenCancelled(completion)
            } else if hasPendingEvents() || hasRetiringSources() {
                flushForTesting(completion)
            } else {
                completion()
            }
        }
    }

    // MARK: - Private

    private func onQueue(_ block: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) == true {
            block()
        } else {
            queue.async(execute: block)
        }
    }

    // The source holds `lease` until its cancel handler runs, after which it can't use the
    // descriptor.
    private func makeSource(_ source: DispatchSourceProtocol,
                            lease: OwnedFileDescriptor.Lease,
                            suspended: Bool,
                            handler: @escaping () -> Void) -> Source {
        dispatchPrecondition(condition: .onQueue(queue))
        cancellation.enter()
        liveSources += 1
        source.setEventHandler(handler: handler)
        // Strongly captures the monitor, which keeps it alive until every source is done.
        source.setCancelHandler { [self] in
            lease.release()
            liveSources -= 1
            cancellation.leave()
        }
        let result = Source(source, suspended: suspended)
        source.activate()
        return result
    }

    // Reconciles the sources with the task's current state. Sources that may have work are
    // resumed, and their handlers suspend them again if there turns out to be nothing to do.
    private func update() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard state == .running else {
            return
        }
        if !awaitingReadCapacity && task.wantsRead {
            readSource?.resume()
        }
        if task.wantsWrite {
            writeSource?.resume()
        }
        updateCoprocess()
    }

    private func handleRead() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard state == .running else {
            return
        }
        // Not reading while paused also means EOF isn't noticed until the task is unpaused.
        guard task.wantsRead else {
            readSource?.suspend()
            return
        }
        guard task.hasReadCapacity else {
            readSource?.suspend()
            awaitReadCapacity()
            return
        }
        task.processRead()
        // processRead may have queued output for the coprocess.
        updateCoprocess()
    }

    private func awaitReadCapacity() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !awaitingReadCapacity else {
            return
        }
        DLog("\(self) waits for read capacity")
        awaitingReadCapacity = true
        task.notifyWhenReadCapacityAvailable(on: queue) { [weak self] in
            guard let self else {
                return
            }
            // This may run while there is still no capacity. The read handler checks again.
            awaitingReadCapacity = false
            update()
        }
    }

    private func handleWrite() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard state == .running else {
            return
        }
        if task.wantsWrite {
            // This calls brokenPipe on a write error, which cancels the monitor.
            task.processWrite()
        }
        guard state == .running else {
            return
        }
        if !task.wantsWrite {
            writeSource?.suspend()
        }
        // Draining the write buffer may have made room for the coprocess's output.
        updateCoprocess()
    }

    // MARK: Coprocess

    private func updateCoprocess() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard state == .running else {
            return
        }
        // PTYTask terminates and replaces its coprocess while synchronized on itself.
        objc_sync_enter(task)
        defer {
            objc_sync_exit(task)
        }
        let current: Coprocess? = task.coprocess
        if coprocessIO?.coprocess !== current {
            coprocessIO?.cancel()
            coprocessIO = nil
            if let current, current.pid >= 0 {
                coprocessIO = makeCoprocessIO(current)
            }
        }
        guard let coprocessIO else {
            return
        }
        let coprocess = coprocessIO.coprocess
        if coprocess.eof {
            finishCoprocess(coprocessIO)
            return
        }
        if coprocess.wantToRead() && task.writeBufferHasRoom {
            coprocessIO.read.resume()
        } else {
            coprocessIO.read.suspend()
        }
        if coprocess.wantToWrite() {
            coprocessIO.write.resume()
        } else {
            coprocessIO.write.suspend()
        }
    }

    // Returns nil if the coprocess's pipes are already closed.
    private func makeCoprocessIO(_ coprocess: Coprocess) -> CoprocessIO? {
        guard let readLease = coprocess.ownedReadFileDescriptor.lease(),
              let writeLease = coprocess.ownedWriteFileDescriptor.lease() else {
            DLog("\(self) can't service coprocess \(coprocess), which is closed")
            return nil
        }
        DLog("\(self) starts servicing coprocess \(coprocess)")
        let readFileDescriptor = readLease.fileDescriptor
        let writeFileDescriptor = writeLease.fileDescriptor
        let read = makeSource(DispatchSource.makeReadSource(fileDescriptor: readFileDescriptor,
                                                            queue: queue),
                              lease: readLease,
                              suspended: true) { [weak self] in
            self?.handleCoprocessRead()
        }
        let write = makeSource(DispatchSource.makeWriteSource(fileDescriptor: writeFileDescriptor,
                                                              queue: queue),
                               lease: writeLease,
                               suspended: true) { [weak self] in
            self?.handleCoprocessWrite()
        }
        return CoprocessIO(coprocess: coprocess,
                           readFileDescriptor: readFileDescriptor,
                           writeFileDescriptor: writeFileDescriptor,
                           read: read,
                           write: write)
    }

    private func handleCoprocessRead() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard state == .running, let coprocess = coprocessIO?.coprocess else {
            return
        }
        var output: Data?
        objc_sync_enter(task)
        if task.coprocess === coprocess && !coprocess.eof {
            coprocess.read()
            if coprocess.inputBuffer.length > 0 {
                output = Data(bytes: coprocess.inputBuffer.bytes, count: coprocess.inputBuffer.length)
                coprocess.inputBuffer.length = 0
            }
        }
        objc_sync_exit(task)
        if let output {
            task.write(output, coprocess: true)
        }
        // Handles EOF and stops reading if the task's write buffer is now full.
        updateCoprocess()
    }

    private func handleCoprocessWrite() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard state == .running, let coprocess = coprocessIO?.coprocess else {
            return
        }
        objc_sync_enter(task)
        if task.coprocess === coprocess && !coprocess.eof {
            coprocess.write()
        }
        objc_sync_exit(task)
        updateCoprocess()
    }

    // Call while synchronized on the task. The coprocess's output has ended, so it is done.
    private func finishCoprocess(_ io: CoprocessIO) {
        dispatchPrecondition(condition: .onQueue(queue))
        let coprocess = io.coprocess
        DLog("EOF on coprocess \(coprocess) of \(self)")
        io.cancel()
        coprocessIO = nil
        // terminate() signals the pid, so it must not be reaped (and possibly reused) first.
        let pid = coprocess.pid
        coprocess.terminate()
        reap(pid)
        task.coprocess = nil
        coprocessDidChange()
    }

    // Whether a source that is no longer in use has yet to run its cancel handler.
    private func hasRetiringSources() -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        let inUse = (readSource == nil ? 0 : 1) + (writeSource == nil ? 0 : 1) + (coprocessIO == nil ? 0 : 2)
        return liveSources > inUse
    }

    // Whether an active source has an event that its handler has not processed yet.
    private func hasPendingEvents() -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        guard state == .running else {
            return false
        }
        var pollfds = [pollfd]()
        func add(_ fd: Int32, _ source: Source?, _ events: Int32) {
            if let source, source.active {
                pollfds.append(pollfd(fd: fd, events: Int16(events), revents: 0))
            }
        }
        add(fd, readSource, POLLIN)
        add(fd, writeSource, POLLOUT)
        if let coprocessIO {
            add(coprocessIO.readFileDescriptor, coprocessIO.read, POLLIN)
            add(coprocessIO.writeFileDescriptor, coprocessIO.write, POLLOUT)
        }
        guard !pollfds.isEmpty, poll(&pollfds, nfds_t(pollfds.count), 0) > 0 else {
            return false
        }
        // A source also fires at end of file, which poll reports as POLLHUP or POLLERR.
        let ready = Int16(POLLIN | POLLOUT | POLLHUP | POLLERR)
        return pollfds.contains { $0.revents & ready != 0 }
    }
}

@objc(iTermTaskIOMonitorRegistration)
enum TaskIOMonitorRegistration: Int {
    case registered
    case alreadyRegistered
    // The task has no open file descriptor, so it was not registered.
    case noFileDescriptor
}

// Owns the monitors of registered tasks.
@objc(iTermTaskIOMonitorRegistry)
final class TaskIOMonitorRegistry: NSObject {
    private struct State {
        // Keyed by task. A monitor keeps its task alive, so a key can't be reused while it is here.
        var monitors = [ObjectIdentifier: TaskIOMonitor]()
        // Monitors that were cancelled and may still be using their file descriptors, keyed by
        // monitor.
        var cancelling = [ObjectIdentifier: (task: ObjectIdentifier, monitor: TaskIOMonitor)]()
    }
    private let state = MutableAtomicObject(State())
    private let reap: (pid_t) -> Void
    private let coprocessDidChange: () -> Void

    // `reap` and `coprocessDidChange` are called on a monitor's queue.
    @objc(initWithReaper:coprocessChangeHandler:)
    init(reap: @escaping (pid_t) -> Void, coprocessDidChange: @escaping () -> Void) {
        self.reap = reap
        self.coprocessDidChange = coprocessDidChange
    }

    // Any thread.
    @objc(registerTask:)
    func register(_ task: iTermTask) -> TaskIOMonitorRegistration {
        // The monitor leases the descriptor as it is made, so it can't be closed between this
        // check and the sources being created.
        guard let fileDescriptor = task.ownedFileDescriptor else {
            return .noFileDescriptor
        }
        let monitor = TaskIOMonitor(task: task,
                                    fileDescriptor: fileDescriptor,
                                    reap: reap,
                                    coprocessDidChange: coprocessDidChange)
        guard monitor.hasFileDescriptor else {
            return .noFileDescriptor
        }
        let added = state.mutableAccess { state in
            let key = ObjectIdentifier(task)
            if state.monitors[key] != nil {
                return false
            }
            state.monitors[key] = monitor
            // Start before anyone else can find it, so nothing queued on it runs before it starts.
            monitor.start()
            return true
        }
        guard added else {
            DLog("Ignore redundant registration of \(task)")
            return .alreadyRegistered
        }
        RLog("Register \(task) with \(monitor)")
        return .registered
    }

    // Any thread. Safe to call for a task that is not registered.
    @objc(deregisterTask:)
    func deregister(_ task: iTermTask) {
        let monitor = state.mutableAccess { state -> TaskIOMonitor? in
            let key = ObjectIdentifier(task)
            guard let monitor = state.monitors.removeValue(forKey: key) else {
                return nil
            }
            state.cancelling[ObjectIdentifier(monitor)] = (task: key, monitor: monitor)
            return monitor
        }
        guard let monitor else {
            return
        }
        RLog("Deregister \(task) from \(monitor)")
        monitor.cancel()
        monitor.notifyWhenCancelled { [weak self] in
            guard let self else {
                return
            }
            // Return the removed entry so it is released after unlocking. Releasing a task can
            // deregister it, which would take this lock again.
            let removed = state.mutableAccess { state in
                state.cancelling.removeValue(forKey: ObjectIdentifier(monitor))
            }
            withExtendedLifetime(removed) {}
        }
    }

    // Any thread. See TaskIOMonitor.taskStateDidChange().
    @objc(unblockTask:)
    func unblock(_ task: iTermTask) {
        let monitor = state.access { state in
            state.monitors[ObjectIdentifier(task)]
        }
        monitor?.taskStateDidChange()
    }

    // Testing only. Waits until every registered monitor has handled whatever is ready and every
    // deregistered monitor has stopped using its file descriptors. Returns false on timeout.
    @objc(flushForTestingWithTimeout:)
    func flushForTesting(timeout: TimeInterval) -> Bool {
        let (running, stopping) = state.access { state in
            (Array(state.monitors.values), state.cancelling.values.map { $0.monitor })
        }
        return flush(running: running, stopping: stopping, timeout: timeout)
    }

    // Testing only. Like flushForTesting(timeout:), but only for `task`'s monitors, so other tasks
    // may keep adding input meanwhile.
    @objc(flushTaskForTesting:timeout:)
    func flushForTesting(task: iTermTask, timeout: TimeInterval) -> Bool {
        let key = ObjectIdentifier(task)
        let (running, stopping) = state.access { state in
            (state.monitors[key].map { [$0] } ?? [],
             state.cancelling.values.filter { $0.task == key }.map { $0.monitor })
        }
        return flush(running: running, stopping: stopping, timeout: timeout)
    }

    private func flush(running: [TaskIOMonitor],
                       stopping: [TaskIOMonitor],
                       timeout: TimeInterval) -> Bool {
        let group = DispatchGroup()
        for monitor in running {
            group.enter()
            monitor.flushForTesting {
                group.leave()
            }
        }
        for monitor in stopping {
            group.enter()
            monitor.notifyWhenCancelled {
                group.leave()
            }
        }
        return group.wait(timeout: .now() + timeout) == .success
    }
}
