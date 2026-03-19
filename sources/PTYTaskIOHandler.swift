import Foundation

/// Bytes per read chunk, matching MAXRW in PTYTask.m.
private let kMaxReadWrite: Int = 1024

// MARK: - Delegate Protocol

/// Delegate protocol for PTYTaskIOHandler. PTYTask implements this to bridge
/// dispatch source events back to its internal state.
///
/// Predicate methods are called from any queue and must be thread-safe.
/// Event methods are called on the handler's ioQueue.
@objc protocol PTYTaskIOHandlerDelegate: AnyObject {
    // MARK: State predicates (any queue, thread-safe)

    /// Whether reading should be enabled. Checks paused, ioAllowed, backpressure.
    func ioHandlerShouldRead(_ handler: PTYTaskIOHandler) -> Bool

    /// Whether writing should be enabled. Checks paused, ioAllowed, buffer has data.
    func ioHandlerShouldWrite(_ handler: PTYTaskIOHandler) -> Bool

    /// Whether the coprocess read source should be resumed.
    func ioHandlerShouldResumeCoprocessRead(_ handler: PTYTaskIOHandler) -> Bool

    /// Whether the coprocess write source should be resumed.
    func ioHandlerShouldResumeCoprocessWrite(_ handler: PTYTaskIOHandler) -> Bool

    // MARK: PTY read events (ioQueue)

    /// Data was read from the PTY file descriptor.
    func ioHandler(_ handler: PTYTaskIOHandler, didReadData buffer: UnsafePointer<CChar>, length: Int32)

    /// A broken pipe (EOF or fatal read error) was detected on the PTY fd.
    func ioHandlerDidDetectBrokenPipe(_ handler: PTYTaskIOHandler)

    // MARK: PTY write events (ioQueue)

    /// The write source fired; drain the write buffer now.
    func ioHandlerDrainWriteBuffer(_ handler: PTYTaskIOHandler)

    // MARK: Coprocess events (ioQueue)

    /// The coprocess read source fired. Delegate should read from the coprocess,
    /// handle EOF, and route data as needed.
    func ioHandlerHandleCoprocessRead(_ handler: PTYTaskIOHandler)

    /// The coprocess write source fired. Delegate should flush coprocess output buffer.
    func ioHandlerHandleCoprocessWrite(_ handler: PTYTaskIOHandler)
}

// MARK: - PTYTaskIOHandler

/// Manages dispatch sources for PTY I/O in the fairness scheduler path.
///
/// Owns the ioQueue, read/write dispatch sources, and coprocess dispatch sources.
/// All source event handlers run on the serial ioQueue. The delegate (PTYTask)
/// provides state predicates and receives event callbacks.
///
/// This class has no dependency on TaskNotifier.
@objc class PTYTaskIOHandler: NSObject {

    @objc weak var delegate: PTYTaskIOHandlerDelegate?

    /// The PTY file descriptor. Set at init, immutable.
    private let fd: Int32

    /// The child process PID for exit monitoring. 0 if unknown (e.g., tmux tasks).
    private let childPid: pid_t

    /// Serial queue for all dispatch source handlers.
    let ioQueue: DispatchQueue
    private let ioQueueKey = DispatchSpecificKey<Void>()

    // MARK: Primary dispatch sources

    // Access on ioQueue only (after start)
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?

    /// Monitors the child process for exit. When the read source is suspended
    /// (for backpressure, pause, or copy mode), EOF delivery is blocked. The
    /// proc source detects process exit independently and force-resumes the
    /// read source so EOF can be delivered without polling.
    // Access on ioQueue only (after start)
    private var procSource: DispatchSourceProcess?

    // Access on ioQueue only
    private var readSourceSuspended = true
    private var writeSourceSuspended = true

    /// Set when the proc source fires. Once true, the read source is never
    /// re-suspended — it must remain active to drain remaining data and
    /// detect EOF.
    // Access on ioQueue only
    private var processExited = false

    // MARK: Coprocess dispatch sources

    // Access on ioQueue only (after setupCoprocessSources)
    private var coprocessReadSource: DispatchSourceRead?
    private var coprocessWriteSource: DispatchSourceWrite?

    // Access on ioQueue only
    private var coprocessReadSourceSuspended = false
    private var coprocessWriteSourceSuspended = false

    // MARK: - Init

    @objc init(fd: Int32, pid: pid_t) {
        precondition(fd >= 0, "PTYTaskIOHandler requires a valid fd")
        self.fd = fd
        self.childPid = pid
        self.ioQueue = DispatchQueue(label: "com.iterm2.pty-io")
        super.init()
        ioQueue.setSpecific(key: ioQueueKey, value: ())
    }

    // MARK: - Lifecycle

    /// Main queue. Creates read and write dispatch sources on the fd.
    /// Sources start suspended; updateReadSourceState/updateWriteSourceState
    /// resume them if conditions allow.
    @objc func start() {
        // Read source — starts suspended, resumed by updateReadSourceState when
        // delegate says reading is allowed. Provides backpressure by suspending
        // when the token pipeline is full.
        let rs = DispatchSource.makeReadSource(fileDescriptor: fd, queue: ioQueue)
        rs.setEventHandler { [weak self] in
            self?.handleReadEvent()
        }
        rs.resume()   // Must resume before we can suspend
        rs.suspend()  // Start suspended
        readSource = rs
        readSourceSuspended = true

        // Write source
        let ws = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: ioQueue)
        ws.setEventHandler { [weak self] in
            self?.handleWriteEvent()
        }
        ws.resume()
        ws.suspend()
        writeSource = ws
        writeSourceSuspended = true

        // Process exit source — detects child exit so we can force-resume
        // the read source for EOF delivery even when suspended for
        // backpressure, pause, or copy mode.
        if childPid > 0 {
            let ps = DispatchSource.makeProcessSource(
                identifier: childPid,
                eventMask: .exit,
                queue: ioQueue)
            ps.setEventHandler { [weak self] in
                self?.handleProcessExit()
            }
            ps.resume()
            procSource = ps
        }

        // Initial state sync
        updateReadSourceState()
        updateWriteSourceState()
    }

    /// Any queue. Tears down all sources (primary + coprocess + proc).
    @objc func teardown() {
        teardownCoprocessSources()
        syncOnIOQueue { [self] in
            let ps = procSource
            procSource = nil
            // Proc source is never suspended — cancel directly.
            ps?.cancel()
            cancelAndNilSource(&readSource, suspended: &readSourceSuspended)
            cancelAndNilSource(&writeSource, suspended: &writeSourceSuspended)
        }
    }

    // MARK: - State Updates (any queue)

    /// Any queue. Snapshots shouldRead from delegate, dispatches to ioQueue.
    @objc func updateReadSourceState() {
        // Never re-suspend after processExited: must drain remaining data and
        // deliver EOF. For pid <= 0 (tmux), there is no proc source — but
        // there is also no child process to exit. EOF arrives when the tmux
        // server closes the fd; GCD queues that event and delivers it when
        // the read source is next resumed (e.g., user unpauses). This matches
        // legacy select() behavior where paused fds are omitted from the read set.
        let shouldRead = delegate?.ioHandlerShouldRead(self) ?? false
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.setSourceSuspended(&self.readSource,
                                    suspended: &self.readSourceSuspended,
                                    shouldResume: shouldRead || self.processExited)
        }
    }

    /// Any queue. Snapshots shouldWrite from delegate, dispatches to ioQueue.
    @objc func updateWriteSourceState() {
        let shouldWrite = delegate?.ioHandlerShouldWrite(self) ?? false
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.setSourceSuspended(&self.writeSource,
                                    suspended: &self.writeSourceSuspended,
                                    shouldResume: shouldWrite)
        }
    }

    /// Any queue. Called when data is added to the write buffer.
    @objc func writeBufferDidChange() {
        updateWriteSourceState()
    }

    // MARK: - Coprocess Source Management

    /// Sets up coprocess dispatch sources for the given file descriptors.
    /// Requires start() to have been called first (ioQueue must exist).
    @objc func setupCoprocessSources(readFd: Int32, writeFd: Int32) {
        guard readFd >= 0, writeFd >= 0 else { return }

        // Tear down any existing coprocess sources before creating new ones.
        teardownCoprocessSources()

        // Create sources outside ioQueue (just object construction),
        // then assign references and flags on ioQueue to avoid racing
        // with event handlers and updateCoprocess*SourceState.

        // Read source — reads coprocess stdout, feeds data back as PTY input
        let crs = DispatchSource.makeReadSource(fileDescriptor: readFd, queue: ioQueue)
        crs.setEventHandler { [weak self] in
            self?.handleCoprocessReadEvent()
        }
        crs.resume()
        crs.suspend()

        // Write source — flushes outputBuffer to coprocess stdin
        let cws = DispatchSource.makeWriteSource(fileDescriptor: writeFd, queue: ioQueue)
        cws.setEventHandler { [weak self] in
            self?.handleCoprocessWriteEvent()
        }
        cws.resume()
        cws.suspend()

        syncOnIOQueue { [self] in
            coprocessReadSource = crs
            coprocessReadSourceSuspended = true
            coprocessWriteSource = cws
            coprocessWriteSourceSuspended = true
        }

        updateCoprocessReadSourceState()
        updateCoprocessWriteSourceState()
    }

    /// Any queue. Tears down coprocess dispatch sources.
    @objc func teardownCoprocessSources() {
        syncOnIOQueue { [self] in
            cancelAndNilSource(&coprocessReadSource, suspended: &coprocessReadSourceSuspended)
            cancelAndNilSource(&coprocessWriteSource, suspended: &coprocessWriteSourceSuspended)
        }
    }

    /// Any queue. Snapshots coprocess read predicate, dispatches to ioQueue.
    @objc func updateCoprocessReadSourceState() {
        let shouldResume = delegate?.ioHandlerShouldResumeCoprocessRead(self) ?? false
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.setSourceSuspended(&self.coprocessReadSource,
                                    suspended: &self.coprocessReadSourceSuspended,
                                    shouldResume: shouldResume)
        }
    }

    /// Any queue. Snapshots coprocess write predicate, dispatches to ioQueue.
    @objc func updateCoprocessWriteSourceState() {
        let shouldResume = delegate?.ioHandlerShouldResumeCoprocessWrite(self) ?? false
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.setSourceSuspended(&self.coprocessWriteSource,
                                    suspended: &self.coprocessWriteSourceSuspended,
                                    shouldResume: shouldResume)
        }
    }

    // MARK: - Private Event Handlers (ioQueue)

    /// The child process exited. Force-resume the read source so it can
    /// drain remaining data and detect EOF, even if currently suspended for
    /// backpressure, pause, or copy mode.
    ///
    /// Edge case: if the user is in copy mode when the process exits, we
    /// resume the read source and deliver the broken pipe. This matches
    /// legacy TaskNotifier behavior where select() detects EOF regardless
    /// of pause state.
    private func handleProcessExit() {
        processExited = true
        if readSourceSuspended, let rs = readSource {
            rs.resume()
            readSourceSuspended = false
        }
    }

    /// Read up to 4 * kMaxReadWrite bytes from the PTY fd per event.
    private func handleReadEvent() {
        let iterations = 4
        let bufferSize = kMaxReadWrite * iterations
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var totalBytesRead: Int = 0
        var gotEOF = false

        for _ in 0..<iterations {
            let n = Darwin.read(fd, buffer.advanced(by: totalBytesRead), kMaxReadWrite)
            if n < 0 {
                if errno != EAGAIN && errno != EINTR {
                    delegate?.ioHandlerDidDetectBrokenPipe(self)
                    return
                }
                // EAGAIN/EINTR - stop reading but process what we have
                break
            }
            if n == 0 {
                // EOF - PTY slave side closed (child exited).
                gotEOF = true
                break
            }
            totalBytesRead += n
            if n < kMaxReadWrite {
                // Got less than requested - no more data available
                break
            }
        }

        if totalBytesRead > 0 {
            delegate?.ioHandler(self, didReadData: buffer, length: Int32(totalBytesRead))
            // Re-check state after read (backpressure may have increased)
            updateReadSourceState()
        }

        if gotEOF {
            delegate?.ioHandlerDidDetectBrokenPipe(self)
        }
    }

    /// Write source fired; delegate drains the write buffer.
    private func handleWriteEvent() {
        delegate?.ioHandlerDrainWriteBuffer(self)
        // Re-check state after write (buffer may now be empty)
        updateWriteSourceState()
        // Write buffer shrank — coprocess read source may now be eligible to resume
        updateCoprocessReadSourceState()
    }

    /// Coprocess read source fired; delegate handles the I/O.
    private func handleCoprocessReadEvent() {
        delegate?.ioHandlerHandleCoprocessRead(self)
        updateCoprocessReadSourceState()
    }

    /// Coprocess write source fired; delegate flushes the output buffer.
    private func handleCoprocessWriteEvent() {
        delegate?.ioHandlerHandleCoprocessWrite(self)
        updateCoprocessWriteSourceState()
    }

    // MARK: - Private Helpers

    /// Whether we are currently executing on this handler's ioQueue.
    private var isOnIOQueue: Bool {
        DispatchQueue.getSpecific(key: ioQueueKey) != nil
    }

    /// Run a block on ioQueue. Executes inline if already on ioQueue,
    /// otherwise dispatches synchronously.
    private func syncOnIOQueue(_ block: () -> Void) {
        if isOnIOQueue {
            block()
        } else {
            ioQueue.sync(execute: block)
        }
    }

    /// ioQueue only. Suspend or resume a source based on `shouldResume`.
    /// No-op if the source is nil or already in the desired state.
    private func setSourceSuspended(_ source: inout (some DispatchSourceProtocol)?,
                                    suspended: inout Bool,
                                    shouldResume: Bool) {
        guard let s = source else { return }
        if shouldResume && suspended {
            s.resume()
            suspended = false
        } else if !shouldResume && !suspended {
            s.suspend()
            suspended = true
        }
    }

    /// ioQueue only. Resume a suspended source (per GCD rules), cancel it,
    /// then nil the reference.
    private func cancelAndNilSource(_ source: inout (some DispatchSourceProtocol)?,
                                    suspended: inout Bool) {
        guard let s = source else { return }
        if suspended {
            s.resume()
        }
        s.cancel()
        source = nil
        suspended = false
    }
}

// MARK: - Test Accessors

extension PTYTaskIOHandler {
    @objc var testHasReadSource: Bool { readSource != nil }
    @objc var testHasWriteSource: Bool { writeSource != nil }
    @objc var testIsReadSourceSuspended: Bool { readSourceSuspended }
    @objc var testIsWriteSourceSuspended: Bool { writeSourceSuspended }

    @objc var testHasCoprocessReadSource: Bool { coprocessReadSource != nil }
    @objc var testHasCoprocessWriteSource: Bool { coprocessWriteSource != nil }
    @objc var testIsCoprocessReadSourceSuspended: Bool { coprocessReadSourceSuspended }
    @objc var testIsCoprocessWriteSourceSuspended: Bool { coprocessWriteSourceSuspended }

    /// Synchronously wait for the ioQueue to drain all pending work.
    @objc func testWaitForIOQueue() {
        ioQueue.sync {}
    }

    /// Simulates process exit for tests that use pipes instead of real child
    /// processes. Dispatches handleProcessExit() on the ioQueue.
    @objc func testSimulateProcessExit() {
        ioQueue.async { [weak self] in
            self?.handleProcessExit()
        }
    }
}
