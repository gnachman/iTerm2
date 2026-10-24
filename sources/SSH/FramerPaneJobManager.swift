//
//  FramerPaneJobManager.swift
//  iTerm2SharedARC
//
//  The task of a session whose program is a pane of another session's framer (see
//  Conductor+Panes.swift): a workgroup peer running on its leader's host over the leader's
//  connection, with no process on this Mac.
//
//  Output from the conductor goes into a pipe that the session reads like a process's pty, as
//  a tmux client's does, so parsing, coprocesses, logging and backpressure work as usual.
//  Input, size changes and kills go to the conductor. When the pane exits, or the connection
//  ends, the pipe closes and the session ends the way it does when a process exits.
//
//  The conductor is looked up each time, since the leader's is replaced when its connection
//  is recovered or iTerm2 restarts while the pane keeps running. Once the new one has
//  resynchronized with the framer, the pane reattaches to it.
//
//  Under flow control the pane has credit of its own, which comes back once this session has
//  executed its output: the session's token executor records what it runs in
//  `consumptionLedger`, and this passes it on to the conductor the pane is attached to.
//

import Foundation

@objc(iTermFramerPaneJobManager)
final class FramerPaneJobManager: NSObject, iTermJobManager, ConductorPaneClient {
    private let lock = NSLock()
    /// The pipe's read end, which the session's task reads the pane's output from.
    private var readEnd: OwnedFileDescriptor?
    private var writeFD: Int32 = -1
    /// Writes into the pipe block when the session's reader falls behind, so they happen here
    /// rather than on the main thread.
    private let writeQueue = DispatchQueue(label: "com.iterm2.framer-pane-write")
    /// The leader's conductor as of now.
    private let conductorProvider: @MainActor () -> Conductor?
    /// The session's size, sent when reattaching so the program redraws.
    private let gridSizeProvider: @MainActor () -> VT100GridSize?
    /// The conductor the pane is registered with. Nil until it starts or reattaches.
    private weak var attachedConductor: Conductor?
    private var reattaching = false
    private var ended = false
    /// The session was closed while its conductor could not take commands yet; the kill goes
    /// out once the pane is reattached.
    private var killWhenReattached = false
    /// Called with the pane's pid when it reattaches.
    var didReattach: ((Int32) -> Void)?
    /// Every pane session's, for telling a stranded pane from one with a session.
    @MainActor private static let all = NSHashTable<FramerPaneJobManager>.weakObjects()
    /// The pane's pid on the remote host, once it has started.
    private(set) var remotePID: Int32?
    /// The pane's exit status, once known.
    private(set) var exitCode: Int32?
    /// The session's executor records what it runs here (VT100ScreenMutableState
    /// consumptionLedger).
    @objc let consumptionLedger = FramerFlowLedger()

    var tty = "(framer pane)"
    var externallyVisiblePid: pid_t { 0 }
    var hasJob: Bool { true }
    var sessionRestorationIdentifier: Any? { nil }
    var pidToWaitOn: pid_t { 0 }
    var isSessionRestorationPossible: Bool { false }
    var queue: dispatch_queue_t? { nil }
    var isReadOnly: Bool { true }

    var ownedFileDescriptor: OwnedFileDescriptor? {
        lock.lock()
        defer { lock.unlock() }
        return readEnd
    }

    var ioAllowed: Bool { ownedFileDescriptor.map { !$0.isClosed } ?? false }

    static func available() -> Bool {
        true
    }

    @objc(initWithQueue:)
    required init(queue: DispatchQueue) {
        conductorProvider = { nil }
        gridSizeProvider = { nil }
        super.init()
    }

    /// Ready to receive the pane's output on `conductor`. Returns nil if no pipe could be made.
    convenience init?(conductor: Conductor) {
        self.init(conductorProvider: { [weak conductor] in conductor }, gridSizeProvider: { nil })
    }

    /// Ready to receive the pane's output on whatever conductor `conductorProvider` gives.
    /// Returns nil if no pipe could be made.
    init?(conductorProvider: @escaping @MainActor () -> Conductor?,
          gridSizeProvider: @escaping @MainActor () -> VT100GridSize?) {
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else {
            return nil
        }
        // The session reads without blocking; the writer may block (see writeQueue).
        _ = fcntl(fds[0], F_SETFL, fcntl(fds[0], F_GETFL) | O_NONBLOCK)
        _ = fcntl(fds[0], F_SETFD, FD_CLOEXEC)
        _ = fcntl(fds[1], F_SETFD, FD_CLOEXEC)
        readEnd = OwnedFileDescriptor(fds[0])
        writeFD = fds[1]
        self.conductorProvider = conductorProvider
        self.gridSizeProvider = gridSizeProvider
        super.init()
        MainActor.assumeIsolated {
            Self.all.add(self)
        }
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(conductorDidResynchronize(_:)),
                                               name: Conductor.didResynchronizeNotification,
                                               object: nil)
    }

    deinit {
        if writeFD >= 0 {
            close(writeFD)
        }
        readEnd?.close()
    }

    override var description: String {
        return "<\(Self.self): \(it_addressString) fd=\(ownedFileDescriptor?.unsafeFileDescriptor ?? -1) remotePID=\(remotePID.map(String.init) ?? "none")>"
    }

    /// The pane started with this pid.
    @MainActor
    func paneDidStart(pid: Int32) {
        remotePID = pid
        attachedConductor = conductorProvider()
        reportConsumption()
    }

    /// Passes what the session executes on to the conductor the pane is attached to, as the
    /// pane's flow's consumption.
    @MainActor
    private func reportConsumption() {
        guard let pid = remotePID, attachedConductor != nil else {
            consumptionLedger.deactivate()
            return
        }
        let ledger = consumptionLedger
        ledger.activate { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let conductor = self.attachedConductor else {
                    return
                }
                for event in ledger.takeEvents() {
                    if case let .executed(time, bytes) = event {
                        conductor.flowPaneDidConsume(pid, bytes: bytes, now: time)
                    }
                }
            }
        }
    }

    /// A restored session whose pane, `pid`, may still be running: it reattaches once the
    /// leader's conductor is ready.
    @MainActor
    func restore(pid: Int32) {
        remotePID = pid
        attachedConductor = nil
        reattachIfNeeded()
    }

    @objc private func conductorDidResynchronize(_ notification: Notification) {
        MainActor.assumeIsolated {
            reattachIfNeeded()
        }
    }

    /// Reattaches to the leader's current conductor if the pane is not registered with it and
    /// that conductor can take commands.
    @MainActor
    func reattachIfNeeded() {
        guard let pid = remotePID,
              !reattaching,
              !ended,
              let conductor = conductorProvider(),
              conductor !== attachedConductor,
              conductor.framing,
              !conductor.awaitingResynchronization else {
            return
        }
        DLog("Reattach pane \(pid) to \(conductor)")
        reattaching = true
        conductor.reattachPane(pid, client: self) { [weak self, weak conductor] outcome in
            guard let self else {
                return
            }
            self.reattaching = false
            switch outcome {
            case .gone:
                // Gone while iTerm2 was away, with no exit to report.
                self.closeWriteEnd()
                return
            case .unknown:
                // The connection ended or was reset first. The next conductor to resynchronize
                // gets another try.
                DLog("Could not tell whether pane \(pid) is running")
                return
            case .reattached:
                break
            }
            if self.killWhenReattached {
                self.killWhenReattached = false
                conductor?.killPane(pid)
            }
            self.attachedConductor = conductor
            self.reportConsumption()
            if let size = self.gridSizeProvider() {
                // Also makes the program redraw what this session missed.
                conductor?.resizePane(pid, rows: Int(size.height), cols: Int(size.width))
            }
            self.didReattach?(pid)
        }
    }

    /// The pids of panes on `conductor` that sessions have or are waiting to reattach to. A
    /// session that cannot tell yet which conductor its pane is on, because its leader has not
    /// been restored, claims its pid on every conductor.
    @MainActor
    static func claimedPIDs(on conductor: Conductor) -> Set<Int32> {
        var result = Set<Int32>()
        for manager in all.allObjects {
            guard !manager.ended, let pid = manager.remotePID else {
                continue
            }
            let current = manager.conductorProvider()
            if current == nil || current === conductor {
                result.insert(pid)
            }
        }
        return result
    }

    /// Gives every pane session waiting to reattach another chance, for one whose leader was
    /// restored after its conductor resynchronized.
    @MainActor
    static func reattachAllIfNeeded() {
        for manager in all.allObjects {
            manager.reattachIfNeeded()
        }
    }

    // MARK: - From the session

    /// Input for the program. Called on any thread.
    @objc(forwardData:)
    func forward(_ data: Data) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let pid = self.remotePID, let conductor = self.conductorProvider() else {
                    return
                }
                conductor.sendToPane(pid, data: data)
            }
        }
    }

    @objc(setGridSize:)
    func setGridSize(_ size: VT100GridSize) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let pid = self.remotePID, let conductor = self.conductorProvider() else {
                    return
                }
                conductor.resizePane(pid, rows: Int(size.height), cols: Int(size.width))
            }
        }
    }

    func kill(with mode: iTermJobManagerKillingMode) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                guard let pid = self.remotePID, let conductor = self.conductorProvider() else {
                    // Nothing on the host to kill: end the session now.
                    self.closeWriteEnd()
                    return
                }
                if conductor.awaitingResynchronization || conductor !== self.attachedConductor {
                    // It would be lost: a restored or recovered conductor aborts what it was
                    // sent before resynchronizing. Kill it once reattached.
                    DLog("Kill pane \(pid) once reattached")
                    self.killWhenReattached = true
                    self.reattachIfNeeded()
                    return
                }
                conductor.killPane(pid)
            }
        }
    }

    // MARK: - From the conductor

    func conductorPaneDidOutput(_ data: Data) {
        writeQueue.async { [weak self] in
            self?.writeAll(data)
        }
    }

    func conductorPaneDidExit(code: Int32) {
        exitCode = code
        ended = true
        consumptionLedger.deactivate()
        closeWriteEnd()
    }

    func conductorPaneDidLoseConnection() {
        ended = true
        consumptionLedger.deactivate()
        closeWriteEnd()
    }

    // MARK: - iTermJobManager

    func forkAndExec(with ttyState: iTermTTYState,
                     argpath: String!,
                     argv: [String]!,
                     initialPwd: String!,
                     newEnviron: [String]!,
                     task: (any iTermTask)!,
                     completion: ((iTermJobManagerForkAndExecStatus, NSNumber?) -> Void)!) {
        it_fatalError("A framer pane has no local process")
    }

    func attach(toServer serverConnection: iTermGeneralServerConnection,
                withProcessID thePid: NSNumber!,
                task: (any iTermTask)!,
                completion: ((iTermJobManagerAttachResults) -> Void)!) {
        it_fatalError("A framer pane has no local process")
    }

    func attach(toServer serverConnection: iTermGeneralServerConnection,
                withProcessID thePid: NSNumber!,
                task: (any iTermTask)!) -> iTermJobManagerAttachResults {
        it_fatalError("A framer pane has no local process")
    }

    func closeFileDescriptor() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let readEnd, !readEnd.isClosed else {
            return false
        }
        readEnd.close()
        self.readEnd = nil
        return true
    }

    // MARK: - Private

    /// After what was already queued, so the session reads all of the output first.
    private func closeWriteEnd() {
        writeQueue.async { [weak self] in
            guard let self else {
                return
            }
            self.lock.lock()
            let fd = self.writeFD
            self.writeFD = -1
            self.lock.unlock()
            if fd >= 0 {
                close(fd)
            }
        }
    }

    private func writeAll(_ data: Data) {
        lock.lock()
        let fd = writeFD
        lock.unlock()
        guard fd >= 0 else {
            return
        }
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if n < 0 {
                    if errno == EINTR {
                        continue
                    }
                    // The session closed its end: it has ended.
                    return
                }
                offset += n
            }
        }
    }
}
