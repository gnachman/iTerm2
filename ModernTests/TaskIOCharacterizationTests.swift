//
//  TaskIOCharacterizationTests.swift
//  iTerm2
//
//  Pins down how TaskNotifier services tasks today so a replacement can be held to the same
//  behavior. Each test gets its own TaskNotifier (not the shared instance) and real file
//  descriptors. The fake task mirrors PTYTask's processRead, processWrite, and brokenPipe.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Helpers

// Generous so a slow machine fails nothing. Passing tests never wait this long.
private let timeout: TimeInterval = 30

// Counts calls to select(2) so a test can wait until the loop has finished an iteration that
// began after some change of state. See flush().
private final class SelectProbe {
    private let condition = NSCondition()
    private var entries = 0
    private var scriptedErrors = [Int32]()

    var select: iTermTaskNotifierSelect {
        return { nfds, readfds, writefds, errorfds, timeout in
            self.condition.lock()
            self.entries += 1
            self.condition.broadcast()
            let error = self.scriptedErrors.isEmpty ? nil : self.scriptedErrors.removeFirst()
            self.condition.unlock()
            if let error {
                errno = error
                return -1
            }
            return Darwin.select(nfds, readfds, writefds, errorfds, timeout)
        }
    }

    var pendingFailures: Int {
        condition.lock()
        defer { condition.unlock() }
        return scriptedErrors.count
    }

    // The next calls to select fail with these errnos, one per call, without waiting.
    func failNextSelects(with errors: [Int32]) {
        condition.lock()
        scriptedErrors.append(contentsOf: errors)
        condition.unlock()
    }

    // Returns once the loop has completed an iteration whose fd sets were built after this was
    // called. Entry c+1 happens after now; the sets for entry c+2 are built after entry c+1
    // returns; that iteration's results are fully processed before entry c+3.
    @discardableResult
    func flush(_ notifier: TaskNotifier, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        condition.lock()
        let start = entries
        condition.unlock()
        for i in 1...3 {
            notifier.unblock()
            condition.lock()
            let deadline = Date(timeIntervalSinceNow: timeout)
            while entries < start + i {
                if !condition.wait(until: deadline) {
                    condition.unlock()
                    XCTFail("TaskNotifier did not complete an iteration", file: file, line: line)
                    return false
                }
            }
            condition.unlock()
        }
        return true
    }
}

// Waits for a condition that another thread makes true, without sleeping.
private final class Signal {
    private let condition = NSCondition()

    func notify(_ block: () -> Void) {
        condition.lock()
        block()
        condition.broadcast()
        condition.unlock()
    }

    @discardableResult
    func wait(file: StaticString = #filePath, line: UInt = #line, until predicate: () -> Bool) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !predicate() {
            if !condition.wait(until: deadline) {
                if predicate() {
                    return true
                }
                XCTFail("Timed out", file: file, line: line)
                return false
            }
        }
        return true
    }
}

// A pty in raw mode. The fake task owns the master; the test plays the role of the child on the
// slave.
private final class RawPTY {
    let master: Int32
    private(set) var slave: Int32

    init() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        var attributes = termios()
        tcgetattr(slave, &attributes)
        cfmakeraw(&attributes)
        tcsetattr(slave, TCSANOW, &attributes)
        for fd in [master, slave] {
            let flags = fcntl(fd, F_GETFL)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }
        self.master = master
        self.slave = slave
    }

    // Closing a tty waits for its pending output to drain. Discard it first so a test that stops
    // reading the master doesn't stall in close().
    func closeSlave() {
        if slave >= 0 {
            tcflush(slave, TCIOFLUSH)
            close(slave)
            slave = -1
        }
    }

    // Writes all of `data` to the slave. Fails the test instead of hanging if the notifier stops
    // draining the master.
    @discardableResult
    func writeToSlave(_ data: Data, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        return data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = write(slave, buffer.baseAddress! + offset, buffer.count - offset)
                if n >= 0 {
                    offset += n
                    continue
                }
                if errno == EINTR {
                    continue
                }
                if errno != EAGAIN || !waitUntil(deadline, events: Int16(POLLOUT)) {
                    XCTFail("Wrote \(offset) of \(buffer.count) bytes", file: file, line: line)
                    return false
                }
            }
            return true
        }
    }

    // Reads from the slave until `count` bytes have arrived. Fails the test instead of hanging if
    // they never do.
    func readFromSlave(count: Int, file: StaticString = #filePath, line: UInt = #line) -> Data {
        let deadline = Date(timeIntervalSinceNow: timeout)
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while result.count < count {
            let n = read(slave, &buffer, min(buffer.count, count - result.count))
            if n > 0 {
                result.append(buffer, count: n)
                continue
            }
            if n < 0 && errno == EINTR {
                continue
            }
            if n == 0 || errno != EAGAIN || !waitUntil(deadline, events: Int16(POLLIN)) {
                XCTFail("Read \(result.count) of \(count) bytes", file: file, line: line)
                break
            }
        }
        return result
    }

    // Waits for the slave to become ready. Returns false at the deadline.
    private func waitUntil(_ deadline: Date, events: Int16) -> Bool {
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                return false
            }
            var pfd = pollfd(fd: slave, events: events, revents: 0)
            let rc = poll(&pfd, 1, Int32(min(remaining * 1000 + 1, Double(Int32.max))))
            if rc > 0 {
                return true
            }
            if rc < 0 && errno != EINTR {
                return false
            }
        }
    }

    deinit {
        closeSlave()
        close(master)
    }
}

private func pattern(count: Int) -> Data {
    return Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ $0 / 251) })
}

// MARK: - Fake task

// Mirrors the parts of PTYTask that TaskNotifier interacts with.
private final class FakeTask: NSObject, iTermTask {
    private let lock = NSLock()
    private let signal = Signal()
    private weak var notifier: TaskNotifier?

    let fd: Int32
    let pidToWaitOn: pid_t
    var pid: pid_t { 0 }
    var sshIntegrationActive: Bool { false }

    private var _coprocess: Coprocess?
    private var _wantsRead = true
    private var _writeBuffer = Data()
    private var _received = Data()
    private var _readCalls = 0
    private var _zeroLengthReads = 0
    private var _brokenPipeCalls = 0
    private var _hasBrokenPipe = false
    private var _didRegisterCalls = 0
    private var _didRegisterOnMain = true
    private var _readGate: DispatchSemaphore?
    private var _isBlockedInRead = false

    init(fd: Int32, notifier: TaskNotifier, pidToWaitOn: pid_t = 0) {
        self.fd = fd
        self.notifier = notifier
        self.pidToWaitOn = pidToWaitOn
    }

    private func locked<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }

    // MARK: Test controls and observations

    func setWantsRead(_ value: Bool) {
        locked { _wantsRead = value }
    }

    // While set, processRead blocks until the semaphore is signaled.
    func setReadGate(_ gate: DispatchSemaphore?) {
        locked { _readGate = gate }
    }

    var received: Data { locked { _received } }
    var readCalls: Int { locked { _readCalls } }
    var zeroLengthReads: Int { locked { _zeroLengthReads } }
    var brokenPipeCalls: Int { locked { _brokenPipeCalls } }
    var didRegisterCalls: Int { locked { _didRegisterCalls } }
    var didRegisterOnMain: Bool { locked { _didRegisterOnMain } }
    var writeBufferCount: Int { locked { _writeBuffer.count } }
    var isBlockedInRead: Bool { locked { _isBlockedInRead } }
    var writeBufferIsEmpty: Bool { locked { _writeBuffer.isEmpty } }

    @discardableResult
    func waitForReceived(count: Int, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        return signal.wait(file: file, line: line) { locked { _received.count >= count } }
    }

    @discardableResult
    func waitForBrokenPipe(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        return signal.wait(file: file, line: line) { brokenPipeCalls > 0 }
    }

    @discardableResult
    func waitUntilBlockedInRead(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        return signal.wait(file: file, line: line) { isBlockedInRead }
    }

    @discardableResult
    func waitForDidRegister(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        return signal.wait(file: file, line: line) { didRegisterCalls > 0 }
    }

    // MARK: iTermTask

    var coprocess: Coprocess! {
        get { locked { _coprocess } }
        set { locked { _coprocess = newValue } }
    }

    var hasCoprocess: Bool { coprocess != nil }

    var wantsRead: Bool { locked { _wantsRead } }

    var wantsWrite: Bool { locked { !_writeBuffer.isEmpty } }

    var writeBufferHasRoom: Bool { locked { _writeBuffer.count < 1024 * 10 } }

    var hasBrokenPipe: Bool { locked { _hasBrokenPipe } }

    func processRead() {
        if let gate = locked({ _readGate }) {
            signal.notify { locked { _isBlockedInRead = true } }
            gate.wait()
            signal.notify { locked { _isBlockedInRead = false } }
        }
        // Same shape as -[PTYTask processRead]: up to four 1024-byte reads. EOF (read() == 0) and
        // hard errors end the task after delivering whatever was read.
        var buffer = [UInt8](repeating: 0, count: 1024 * 4)
        var bytesRead = 0
        var broken = false
        for _ in 0..<4 {
            let n = buffer.withUnsafeMutableBytes { pointer in
                Darwin.read(fd, pointer.baseAddress! + bytesRead, 1024)
            }
            if n == 0 {
                broken = true
                break
            }
            if n < 0 {
                if errno != EAGAIN && errno != EINTR {
                    broken = true
                }
                break
            }
            bytesRead += n
            if n < 1024 {
                break
            }
        }
        if !broken || bytesRead > 0 {
            let copro = coprocess
            signal.notify {
                locked {
                    _readCalls += 1
                    if bytesRead == 0 {
                        _zeroLengthReads += 1
                    }
                    _received.append(buffer, count: bytesRead)
                }
            }
            // Like -[PTYTask readTask:length:], send output to the coprocess.
            if let copro, bytesRead > 0 {
                objc_sync_enter(self)
                copro.outputBuffer.append(buffer, length: bytesRead)
                objc_sync_exit(self)
            }
        }
        if broken {
            brokenPipe()
        }
    }

    func processWrite() {
        lock.lock()
        let length = min(_writeBuffer.count, 1024)
        let written = _writeBuffer.withUnsafeBytes { pointer in
            Darwin.write(fd, pointer.baseAddress!, length)
        }
        let error = errno
        if written > 0 {
            _writeBuffer.removeFirst(written)
        }
        lock.unlock()
        if written < 0 && error != EAGAIN && error != EINTR {
            brokenPipe()
        }
    }

    // Like -[PTYTask brokenPipe], only the first call counts. brokenPipeCalls is the number of
    // times the task reported it, not the number of times the notifier invoked this.
    func brokenPipe() {
        var first = false
        signal.notify {
            locked {
                first = !_hasBrokenPipe
                _hasBrokenPipe = true
                if first {
                    _brokenPipeCalls += 1
                }
            }
        }
        notifier?.deregister(self)
    }

    func write(_ data: Data!, coprocess: Bool) {
        locked { _writeBuffer.append(data) }
        notifier?.unblock()
    }

    func didRegister() {
        let onMain = Thread.isMainThread
        signal.notify {
            locked {
                _didRegisterCalls += 1
                _didRegisterOnMain = _didRegisterOnMain && onMain
            }
        }
    }
}

// MARK: - Tests

class TaskIOCharacterizationTests: XCTestCase {
    fileprivate var probe: SelectProbe!
    fileprivate var notifier: TaskNotifier!
    private var coprocessChanges = 0
    private let coprocessChangeSignal = Signal()
    // Nil when the notifier reaps with its dead pool.
    fileprivate var reaper: ChildReaper?
    // Pids the reaper has stopped watching, in order.
    fileprivate var reapedPids = [pid_t]()
    // Pids the reaper stopped watching without reaping (for example, not a child).
    fileprivate var abandonedPids = [pid_t]()
    fileprivate let reapSignal = Signal()

    // Subclasses override this to reap with a ChildReaper instead of the dead pool.
    fileprivate func makeReaper(didReap: @escaping (pid_t, Bool) -> Void) -> ChildReaper? {
        return nil
    }

    override func setUp() {
        super.setUp()
        probe = SelectProbe()
        reaper = makeReaper { [weak self] pid, reaped in
            guard let self else { return }
            reapSignal.notify {
                self.reapedPids.append(pid)
                if !reaped {
                    self.abandonedPids.append(pid)
                }
            }
        }
        let reapPid: ((pid_t) -> Void)? = reaper.map { reaper in { pid in reaper.reap(pid) } }
        notifier = TaskNotifier(forTestingWithSelect: probe.select,
                                coprocessChangeHandler: { [weak self] in
            guard let self else { return }
            coprocessChangeSignal.notify { self.coprocessChanges += 1 }
        },
                                reaper: reapPid)
        notifier.startForTesting()
    }

    override func tearDown() {
        XCTAssertTrue(notifier.stopForTesting(withTimeout: timeout))
        notifier = nil
        probe = nil
        reaper = nil
        super.tearDown()
    }

    // Deregisters and waits for the loop to stop using the task, so its fd can be closed safely.
    private func deregisterAndFlush(_ tasks: FakeTask..., file: StaticString = #filePath, line: UInt = #line) {
        for task in tasks {
            notifier.deregister(task)
        }
        XCTAssertTrue(probe.flush(notifier, file: file, line: line))
    }

    // Waits for a child to exit without reaping it. The notifier may already have reaped it (its
    // dead pool is polled at the top of every iteration), which is also fine.
    fileprivate func waitForExitWithoutReaping(_ pid: pid_t, file: StaticString = #filePath, line: UInt = #line) {
        var info = siginfo_t()
        let rc = waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT)
        let error = errno
        XCTAssertTrue(rc == 0 || error == ECHILD, "waitid failed: \(error)", file: file, line: line)
    }

    // `pid` must already have exited and been handed to the notifier for reaping. Waits for it to
    // be reaped and then asserts that it was.
    fileprivate func assertEventuallyReaped(_ pid: pid_t, file: StaticString = #filePath, line: UInt = #line) {
        if reaper != nil {
            XCTAssertTrue(reapSignal.wait(file: file, line: line) { self.reapedPids.contains(pid) },
                          file: file,
                          line: line)
            reapSignal.notify {
                XCTAssertFalse(abandonedPids.contains(pid), "Something else reaped \(pid)", file: file, line: line)
            }
        } else {
            // The dead pool is polled at the top of every iteration.
            XCTAssertTrue(probe.flush(notifier, file: file, line: line))
        }
        assertReaped(pid, file: file, line: line)
    }

    // Asserts that `pid` no longer exists, which for a child means it has been reaped.
    fileprivate func assertReaped(_ pid: pid_t, file: StaticString = #filePath, line: UInt = #line) {
        let rc = kill(pid, 0)
        let error = errno
        XCTAssertEqual(rc, -1, "Process \(pid) still exists", file: file, line: line)
        XCTAssertEqual(error, ESRCH, file: file, line: line)
    }

    private func makeTask(pidToWaitOn: pid_t = 0) throws -> (FakeTask, RawPTY) {
        let pty = try RawPTY()
        let task = FakeTask(fd: pty.master, notifier: notifier, pidToWaitOn: pidToWaitOn)
        return (task, pty)
    }

    // MARK: Registration

    func testDidRegisterIsCalledOnMain() throws {
        let (task, pty) = try makeTask()
        notifier.register(task)
        let expectation = expectation(description: "didRegister")
        DispatchQueue.global().async {
            if task.waitForDidRegister() {
                expectation.fulfill()
            }
        }
        // didRegister is dispatched to main, so main must run.
        wait(for: [expectation], timeout: timeout)
        XCTAssertTrue(task.didRegisterOnMain)
        deregisterAndFlush(task)
        withExtendedLifetime(pty) {}
    }

    func testDeregisterTwiceIsHarmless() throws {
        let (task, pty) = try makeTask()
        notifier.register(task)
        notifier.deregister(task)
        notifier.deregister(task)
        XCTAssertTrue(probe.flush(notifier))
        withExtendedLifetime(pty) {}
    }

    func testDeregisterNeverRegisteredIsHarmless() throws {
        let (task, pty) = try makeTask()
        notifier.deregister(task)
        XCTAssertTrue(probe.flush(notifier))
        withExtendedLifetime(pty) {}
    }

    // Documents current behavior: a task registered twice is still read once per iteration,
    // because the loop skips an fd it has already handled. Deregistering once removes both
    // entries.
    func testDoubleRegistrationDeliversBytesOnce() throws {
        let (task, pty) = try makeTask()
        notifier.register(task)
        notifier.register(task)
        XCTAssertTrue(probe.flush(notifier))
        // Small enough for the tty to queue in one piece and for one processRead to drain, so a
        // second read in the same iteration would show up as a zero-length read.
        let expected = pattern(count: 50)
        pty.writeToSlave(expected)
        XCTAssertTrue(task.waitForReceived(count: expected.count))
        XCTAssertTrue(probe.flush(notifier))
        XCTAssertEqual(task.received, expected)
        XCTAssertEqual(task.readCalls, 1)
        XCTAssertEqual(task.zeroLengthReads, 0)

        notifier.deregister(task)
        XCTAssertTrue(probe.flush(notifier))
        pty.writeToSlave(Data("x".utf8))
        XCTAssertTrue(probe.flush(notifier))
        XCTAssertEqual(task.readCalls, 1, "One deregister removes a task that was registered twice")
    }

    func testRegisteringTwiceCallsDidRegisterOnce() throws {
        let (task, _) = try makeTask()
        notifier.register(task)
        notifier.register(task)
        // didRegister is dispatched to main. Main is FIFO, so once this runs, any didRegister
        // from either registration has already run.
        let drained = expectation(description: "main drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: timeout)
        XCTAssertEqual(task.didRegisterCalls, 1)
        deregisterAndFlush(task)
    }

    // MARK: Reading

    func testBytesAreDeliveredInOrder() throws {
        let (task, pty) = try makeTask()
        notifier.register(task)
        let expected = pattern(count: 256 * 1024)
        DispatchQueue.global().async {
            pty.writeToSlave(expected)
        }
        XCTAssertTrue(task.waitForReceived(count: expected.count))
        XCTAssertEqual(task.received, expected)
        deregisterAndFlush(task)
    }

    func testNoReadsWhileWantsReadIsFalse() throws {
        let (task, pty) = try makeTask()
        task.setWantsRead(false)
        notifier.register(task)
        XCTAssertTrue(probe.flush(notifier))
        pty.writeToSlave(Data("hello".utf8))
        XCTAssertTrue(probe.flush(notifier))
        XCTAssertEqual(task.readCalls, 0)

        // Like -[PTYTask setPaused:NO], the task changes its answer and unblocks.
        task.setWantsRead(true)
        notifier.unblock()
        XCTAssertTrue(task.waitForReceived(count: 5))
        XCTAssertEqual(task.received, Data("hello".utf8))
        deregisterAndFlush(task)
    }

    // A task that blocks in processRead (as PTYTask does when its TokenExecutor is full) stops
    // every other task from being read, because one thread services them all.
    // EXPECTED TO DIFFER on the per-task monitor backend, where the other task keeps reading.
    func testBlockedReadStallsOtherTasks() throws {
        let (blocker, blockerPTY) = try makeTask()
        let (other, otherPTY) = try makeTask()
        let gate = DispatchSemaphore(value: 0)
        blocker.setReadGate(gate)
        notifier.register(blocker)
        notifier.register(other)

        blockerPTY.writeToSlave(Data("a".utf8))
        XCTAssertTrue(blocker.waitUntilBlockedInRead())

        otherPTY.writeToSlave(Data("b".utf8))
        // Documentation only: absence can't be proven without a timed wait, so this passes on any
        // backend almost every time. The meaningful check is below: `other` is read only once
        // `blocker` is released. The per-task backend should instead assert that `other` is read
        // while the gate is still closed.
        XCTAssertEqual(other.readCalls, 0)

        blocker.setReadGate(nil)
        gate.signal()
        XCTAssertTrue(other.waitForReceived(count: 1))
        XCTAssertTrue(blocker.waitForReceived(count: 1))
        deregisterAndFlush(blocker, other)
    }

    // A failed select (for example EBADF when an fd is closed while registered) skips the rest of
    // the iteration and tries again. It does not stop the loop.
    func testFailedSelectIsRetried() throws {
        let (task, pty) = try makeTask()
        notifier.register(task)
        probe.failNextSelects(with: [EBADF, EINTR, EBADF])
        // Failed calls count as entries, so this returns only after all three have been consumed.
        // Every errno takes the same path (skip the rest of the iteration). Receiving data below
        // shows the loop went on to make a real call.
        XCTAssertTrue(probe.flush(notifier))
        XCTAssertEqual(probe.pendingFailures, 0)
        pty.writeToSlave(Data("hello".utf8))
        XCTAssertTrue(task.waitForReceived(count: 5))
        XCTAssertEqual(task.received, Data("hello".utf8))
        deregisterAndFlush(task)
    }

    // MARK: Writing

    func testWritesAreDeliveredInOrder() throws {
        let (task, pty) = try makeTask()
        notifier.register(task)
        let expected = pattern(count: 128 * 1024)
        let readExpectation = expectation(description: "read from slave")
        var actual = Data()
        DispatchQueue.global().async {
            actual = pty.readFromSlave(count: expected.count)
            readExpectation.fulfill()
        }
        // Many small writes, as keystrokes and pastes arrive.
        var offset = 0
        while offset < expected.count {
            let end = min(offset + 1000, expected.count)
            task.write(expected.subdata(in: offset..<end), coprocess: false)
            offset = end
        }
        wait(for: [readExpectation], timeout: timeout)
        XCTAssertEqual(actual, expected)
        deregisterAndFlush(task)
    }

    // While the slave isn't reading, the notifier writes until the pty is full and then stops
    // making progress without error. Writing resumes once the slave drains it.
    func testWriteResumesAfterPtyFills() throws {
        let (task, pty) = try makeTask()
        notifier.register(task)
        let expected = pattern(count: 512 * 1024)
        task.write(expected, coprocess: false)

        // Flush until a full iteration makes no progress. That happens only once the pty is full,
        // because select reports the master writable whenever there is room.
        var remaining = task.writeBufferCount
        while true {
            XCTAssertTrue(probe.flush(notifier))
            let now = task.writeBufferCount
            if now == remaining {
                break
            }
            remaining = now
        }
        XCTAssertGreaterThan(remaining, 0, "The pty should not hold 512KB")
        XCTAssertLessThan(remaining, expected.count, "Some bytes should have been written")
        XCTAssertEqual(task.brokenPipeCalls, 0)

        let actual = pty.readFromSlave(count: expected.count)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(task.brokenPipeCalls, 0)
        deregisterAndFlush(task)
    }

    // MARK: End of file

    // When the slave has no openers, a pty master is both readable (read() returns 0) and in the
    // select exception set. The loop may call brokenPipe for both in one iteration; the task
    // reports it once.
    func testSlaveCloseCausesBrokenPipe() throws {
        let (task, pty) = try makeTask()
        notifier.register(task)
        XCTAssertTrue(probe.flush(notifier))
        pty.closeSlave()
        XCTAssertTrue(task.waitForBrokenPipe())
        XCTAssertTrue(probe.flush(notifier))
        XCTAssertEqual(task.brokenPipeCalls, 1)
    }

    // A pipe at EOF is readable forever, but it is not in the exception set. Only processRead
    // seeing read() == 0 ends the task.
    func testPipeEOFCausesBrokenPipe() throws {
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else {
            XCTFail("pipe() failed: \(errno)")
            return
        }
        let flags = fcntl(fds[0], F_GETFL)
        _ = fcntl(fds[0], F_SETFL, flags | O_NONBLOCK)
        defer {
            close(fds[0])
        }
        let task = FakeTask(fd: fds[0], notifier: notifier)
        notifier.register(task)
        close(fds[1])
        XCTAssertTrue(task.waitForBrokenPipe())
        XCTAssertTrue(probe.flush(notifier))
        XCTAssertEqual(task.brokenPipeCalls, 1)
        XCTAssertEqual(task.zeroLengthReads, 0)
    }

    // MARK: Reaping

    func testWaitForPidReapsChild() throws {
        let pid = try spawn("/usr/bin/true", [])
        // Wait for it to exit without reaping it.
        var info = siginfo_t()
        XCTAssertEqual(waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT), 0)
        XCTAssertEqual(kill(pid, 0), 0, "An unreaped zombie still exists")

        notifier.wait(forPid: pid)
        assertEventuallyReaped(pid)
    }

    // A pid that is still running stays in the dead pool and is reaped after it exits.
    func testWaitForPidReapsChildThatExitsLater() throws {
        let pid = try spawn("/bin/cat", [], stdin: .pipe)
        notifier.wait(forPid: pid.pid)
        XCTAssertTrue(probe.flush(notifier))
        XCTAssertEqual(kill(pid.pid, 0), 0, "Still running")

        // Kill it rather than relying on EOF on stdin, which another process could hold open.
        close(pid.stdin)
        kill(pid.pid, SIGKILL)
        waitForExitWithoutReaping(pid.pid)
        assertEventuallyReaped(pid.pid)
    }

    // Deregistering a task reaps its pidToWaitOn.
    func testDeregisterReapsPidToWaitOn() throws {
        let pid = try spawn("/usr/bin/true", [])
        let (task, pty) = try makeTask(pidToWaitOn: pid)
        notifier.register(task)
        waitForExitWithoutReaping(pid)
        XCTAssertEqual(kill(pid, 0), 0, "An unreaped zombie still exists")

        deregisterAndFlush(task)
        assertEventuallyReaped(pid)
        withExtendedLifetime(pty) {}
    }

    // waitpid treats 0 as "any child in my process group", so waiting for pid 0 must not reap an
    // unrelated child.
    func testWaitForPidZeroReapsNothing() throws {
        let pid = try spawn("/usr/bin/true", [])
        waitForExitWithoutReaping(pid)

        notifier.wait(forPid: 0)
        XCTAssertTrue(probe.flush(notifier))
        XCTAssertEqual(kill(pid, 0), 0, "The zombie must not have been reaped")

        var status: Int32 = 0
        XCTAssertEqual(waitpid(pid, &status, 0), pid)
    }

    // MARK: Coprocesses

    // Deregistering a task that still has a coprocess reaps the coprocess.
    func testDeregisterReapsCoprocess() throws {
        let (task, pty) = try makeTask()
        let cat = try makeCatCoprocess()
        let pid = cat.pid
        task.coprocess = cat
        notifier.register(task)
        XCTAssertTrue(probe.flush(notifier))

        // While the coprocess is alive the loop can't see its EOF, so only deregistration hands
        // it over for reaping.
        deregisterAndFlush(task)
        cat.terminate()
        kill(pid, SIGKILL)
        waitForExitWithoutReaping(pid)
        assertEventuallyReaped(pid)
        withExtendedLifetime(pty) {}
    }

    // Bytes the task reads go to the coprocess; its output comes back through writeTask.
    func testCoprocessRoundTrip() throws {
        let (task, pty) = try makeTask()
        let cat = try makeCatCoprocess()
        task.coprocess = cat
        notifier.register(task)

        let expected = pattern(count: 20000)
        DispatchQueue.global().async {
            pty.writeToSlave(expected)
        }
        // pty slave -> task -> cat -> task.writeTask -> pty slave
        let echoed = pty.readFromSlave(count: expected.count)
        XCTAssertEqual(echoed, expected)
        XCTAssertEqual(task.received, expected)

        deregisterAndFlush(task)
        let pid = cat.pid
        cat.terminate()
        notifier.wait(forPid: pid)
        // Let the notifier reap cat so no zombie is left in the test host.
        waitForExitWithoutReaping(pid)
        assertEventuallyReaped(pid)
        withExtendedLifetime(pty) {}
    }

    // When the coprocess exits, the loop terminates it, removes it from the task, adds it to the
    // dead pool, and reports the change.
    func testCoprocessEOF() throws {
        let (task, pty) = try makeTask()
        let cat = try makeCatCoprocess()
        let pid = cat.pid
        task.coprocess = cat
        notifier.register(task)
        XCTAssertTrue(probe.flush(notifier))

        kill(pid, SIGKILL)
        XCTAssertTrue(coprocessChangeSignal.wait { self.coprocessChanges > 0 })
        XCTAssertNil(task.coprocess)
        XCTAssertEqual(cat.pid, -1)

        waitForExitWithoutReaping(pid)
        assertEventuallyReaped(pid)

        deregisterAndFlush(task)
        withExtendedLifetime(pty) {}
    }

    // The coprocess reads the child's stderr until EOF and must then close it. Each coprocess used
    // to leak this fd.
    func testCoprocessClosesStderrAfterEOF() throws {
        // The child waits for a line on stdin so the fd is still open when the test inspects it.
        let coprocess = try makeCoprocess("/bin/sh", ["-c", "read x; echo oops >&2"])
        let pid = coprocess.pid
        let errorFd = coprocess.errorFileDescriptorForTesting
        var before = stat()
        XCTAssertEqual(fstat(errorFd, &before), 0)
        XCTAssertEqual(Darwin.write(coprocess.outputFd, "\n", 1), 1)

        let done = expectation(description: "error output complete")
        var errors: String?
        coprocess.notify(whenErrorOutputIsComplete: { output in
            errors = output
            done.fulfill()
        })
        wait(for: [done], timeout: timeout)
        // The test host's environment may make the child log other things to stderr first.
        XCTAssertTrue(errors?.hasSuffix("oops\n\n") ?? false, errors ?? "nil")

        // Closed, or reused for something else. Either way it is no longer the pipe.
        var after = stat()
        if fstat(errorFd, &after) == 0 {
            XCTAssertFalse(after.st_dev == before.st_dev && after.st_ino == before.st_ino)
        } else {
            XCTAssertEqual(errno, EBADF)
        }

        coprocess.terminate()
        // Nothing else reaps this child: it was never handed to a notifier.
        var status: Int32 = 0
        XCTAssertEqual(waitpid(pid, &status, 0), pid)
    }

    // MARK: Process helpers

    fileprivate enum Stdin {
        case devNull
        case pipe
        case fileDescriptor(Int32)
    }

    fileprivate struct Spawned {
        var pid: pid_t
        // The write end of the child's stdin when Stdin.pipe was requested, otherwise -1.
        var stdin: Int32
    }

    fileprivate func spawn(_ path: String, _ args: [String]) throws -> pid_t {
        return try spawn(path, args, stdin: .devNull).pid
    }

    fileprivate func spawn(_ path: String,
                           _ args: [String],
                           stdin: Stdin,
                           stdout: Int32? = nil,
                           stderr: Int32? = nil) throws -> Spawned {
        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }

        var parentStdin: Int32 = -1
        var closeAfterSpawn = [Int32]()
        defer { closeAfterSpawn.forEach { close($0) } }
        switch stdin {
        case .devNull:
            posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        case .pipe:
            var fds: [Int32] = [-1, -1]
            guard pipe(&fds) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            posix_spawn_file_actions_adddup2(&actions, fds[0], 0)
            parentStdin = fds[1]
            closeAfterSpawn.append(fds[0])
        case .fileDescriptor(let fd):
            posix_spawn_file_actions_adddup2(&actions, fd, 0)
        }
        if let stdout {
            posix_spawn_file_actions_adddup2(&actions, stdout, 1)
        }
        if let stderr {
            posix_spawn_file_actions_adddup2(&actions, stderr, 2)
        }

        var attributes: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Only the descriptors set up above are inherited.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

        let argv = ([path] + args).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, path, &actions, &attributes, argv, environ)
        guard rc == 0 else {
            if parentStdin >= 0 {
                close(parentStdin)
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(rc))
        }
        return Spawned(pid: pid, stdin: parentStdin)
    }

    // A coprocess running cat, wired like +[Coprocess launchedCoprocessWithCommand:environment:]
    // but without touching user defaults.
    private func makeCatCoprocess() throws -> Coprocess {
        return try makeCoprocess("/bin/cat", [])
    }

    private func makeCoprocess(_ path: String, _ args: [String]) throws -> Coprocess {
        var fds = [Int32]()
        func makePipe() throws -> (read: Int32, write: Int32) {
            var pair: [Int32] = [-1, -1]
            guard pipe(&pair) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            fds.append(contentsOf: pair)
            return (pair[0], pair[1])
        }
        let spawned: Spawned
        let toCat, fromCat, errors: (read: Int32, write: Int32)
        do {
            toCat = try makePipe()
            fromCat = try makePipe()
            errors = try makePipe()
            for fd in [toCat.write, fromCat.read, errors.read] {
                _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            }
            spawned = try spawn(path,
                                args,
                                stdin: .fileDescriptor(toCat.read),
                                stdout: fromCat.write,
                                stderr: errors.write)
        } catch {
            fds.forEach { close($0) }
            throw error
        }
        // The child has its own copies of these.
        close(toCat.read)
        close(fromCat.write)
        close(errors.write)
        // The coprocess owns the rest.
        return Coprocess(pid: spawned.pid,
                         command: path,
                         outputFd: toCat.write,
                         inputFd: fromCat.read,
                         errorFd: errors.read)
    }
}

// Runs every test above with a ChildReaper doing the reaping instead of the dead pool.
final class TaskIOCharacterizationWithChildReaperTests: TaskIOCharacterizationTests {
    fileprivate override func makeReaper(didReap: @escaping (pid_t, Bool) -> Void) -> ChildReaper? {
        return ChildReaper(didReap: didReap)
    }

    func testReapingTheSamePidTwiceReportsOnce() throws {
        let child = try spawn("/bin/cat", [], stdin: .pipe)
        notifier.wait(forPid: child.pid)
        notifier.wait(forPid: child.pid)
        close(child.stdin)
        kill(child.pid, SIGKILL)
        assertEventuallyReaped(child.pid)

        // Anything else the reaper had queued for this pid has run by the time this one is done.
        let marker = try spawn("/usr/bin/true", [])
        notifier.wait(forPid: marker)
        assertEventuallyReaped(marker)
        reapSignal.notify {
            XCTAssertEqual(reapedPids, [child.pid, marker])
        }
    }

    // A pid that is not a child can't be waited on, so the reaper stops watching it.
    func testReapingAProcessThatIsNotAChildGivesUp() throws {
        notifier.wait(forPid: 1)
        XCTAssertTrue(reapSignal.wait { self.reapedPids == [1] })
        reapSignal.notify {
            XCTAssertEqual(abandonedPids, [1])
        }
    }

    // macOS has been seen to leave an exited child unreapable for a while (see
    // iTermMonoServerJobManager's killServerIfRunning). The reaper must keep retrying without
    // blocking its queue.
    func testRetriesWhenAnExitedChildIsNotYetReapable() throws {
        let lock = NSLock()
        var calls = 0
        var sawBlockingWait = false
        let signal = Signal()
        var reaped = [pid_t: Bool]()
        let reaper = ChildReaper(didReap: { pid, success in
            signal.notify { reaped[pid] = success }
        }, waitpid: { pid, status, options in
            var n = 0
            signal.notify {
                lock.lock()
                calls += 1
                n = calls
                if options & WNOHANG == 0 {
                    sawBlockingWait = true
                }
                lock.unlock()
            }
            // Pretend the first three calls found nothing to reap, as in the macOS bug.
            if n <= 3 {
                return 0
            }
            return Darwin.waitpid(pid, status, options)
        })
        let child = try spawn("/bin/cat", [], stdin: .pipe)
        reaper.reap(child.pid)
        // The first call is the check made right after the exit source is armed. Kill the child
        // only after that, so the exit is seen by the source.
        XCTAssertTrue(signal.wait {
            lock.lock()
            defer { lock.unlock() }
            return calls >= 1
        })
        close(child.stdin)
        kill(child.pid, SIGKILL)

        XCTAssertTrue(signal.wait { reaped[child.pid] != nil })
        signal.notify {
            XCTAssertEqual(reaped[child.pid], true)
        }
        assertReaped(child.pid)
        lock.lock()
        XCTAssertGreaterThan(calls, 3)
        XCTAssertFalse(sawBlockingWait)
        lock.unlock()
    }

    // Requests made while a pid is still being watched count as one, even if the reaper only gets
    // to them after it has reaped the pid. Otherwise the late one would watch a pid that no longer
    // exists, or that already belongs to another process.
    func testRequestsMadeBeforeTheReapCountAsOne() throws {
        let child = try spawn("/usr/bin/true", [])
        let queue = DispatchQueue(label: "TaskIOCharacterizationTests.reaper")
        // Nothing can throw while it is suspended, which would release it suspended and crash.
        queue.suspend()
        let signal = Signal()
        var reports = [String]()
        let reaper = ChildReaper(didReap: { pid, success in
            signal.notify { reports.append("\(pid) \(success)") }
        }, queue: queue)
        reaper.reap(child)
        reaper.reap(child)
        waitForExitWithoutReaping(child)
        queue.resume()

        let marker = try spawn("/usr/bin/true", [])
        reaper.reap(marker)
        XCTAssertTrue(signal.wait { reports.count >= 2 && reports.last == "\(marker) true" })
        signal.notify {
            XCTAssertEqual(reports, ["\(child) true", "\(marker) true"])
        }
    }

    // A request made after the pid was reaped is a new request.
    func testRequestAfterTheReapIsNew() throws {
        let signal = Signal()
        var reports = [String]()
        let reaper = ChildReaper(didReap: { pid, success in
            signal.notify { reports.append("\(pid) \(success)") }
        })
        let child = try spawn("/usr/bin/true", [])
        reaper.reap(child)
        XCTAssertTrue(signal.wait { reports.count == 1 })
        reaper.reap(child)
        // Nothing has that pid now (or it is not this process's child), so it gives up.
        XCTAssertTrue(signal.wait { reports.count == 2 })
        signal.notify {
            XCTAssertEqual(reports, ["\(child) true", "\(child) false"])
        }
    }

    // waitpid treats 0 and negative pids as process groups, which would reap other code's children.
    func testNonPositivePidsAreIgnored() throws {
        reaper?.reap(0)
        reaper?.reap(-1)
        let marker = try spawn("/usr/bin/true", [])
        reaper?.reap(marker)
        assertEventuallyReaped(marker)
        reapSignal.notify {
            XCTAssertEqual(reapedPids, [marker])
        }
    }
}
