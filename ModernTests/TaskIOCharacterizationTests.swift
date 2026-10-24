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
    private static let openptyLock = NSLock()
    // Closed when this is deallocated, once nothing (such as a monitor) is using it.
    let master: OwnedFileDescriptor
    private(set) var slave: Int32

    init() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        // openpty occasionally fails (errno -6) when several threads call it at once.
        Self.openptyLock.lock()
        let rc = openpty(&master, &slave, nil, nil, nil)
        let error = errno
        Self.openptyLock.unlock()
        guard rc == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(error))
        }
        var attributes = termios()
        tcgetattr(slave, &attributes)
        cfmakeraw(&attributes)
        tcsetattr(slave, TCSANOW, &attributes)
        for fd in [master, slave] {
            let flags = fcntl(fd, F_GETFL)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }
        self.master = OwnedFileDescriptor(master)
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
        master.close()
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

    let ownedFileDescriptor: OwnedFileDescriptor?
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
    // Stands in for the session's TokenExecutor. Each read that delivers bytes takes a slot.
    private var _budget: TokenBudget?
    // Reads that found the budget full. Delivering them would have blocked a real session.
    private var _readsWithoutCapacity = 0
    private var _consumer: DispatchQueue?
    private var _slotsTaken = 0

    init(fd: OwnedFileDescriptor, notifier: TaskNotifier, pidToWaitOn: pid_t = 0) {
        ownedFileDescriptor = fd
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

    // Reads take slots from `budget`. If `consumer` is given, each slot is released on it, like a
    // TokenExecutor executing what was read. Otherwise the test releases them.
    func setBudget(_ budget: TokenBudget?, consumer: DispatchQueue? = nil) {
        locked {
            _budget = budget
            _consumer = consumer
        }
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
    var readsWithoutCapacity: Int { locked { _readsWithoutCapacity } }
    // Reads that took a budget slot.
    var slotsTaken: Int { locked { _slotsTaken } }

    @discardableResult
    func waitForSlotsTaken(_ count: Int, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        return signal.wait(file: file, line: line) { slotsTaken >= count }
    }

    @discardableResult
    func waitForCoprocessRemoved(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        return signal.wait(file: file, line: line) { coprocess == nil }
    }

    // Like -[PTYTask stopCoprocess]. Returns the pid handed over for reaping, if any.
    @discardableResult
    func stopCoprocess() -> pid_t? {
        objc_sync_enter(self)
        let copro = coprocess
        let pid = copro?.pid ?? -1
        copro?.terminate()
        coprocess = nil
        objc_sync_exit(self)
        notifier?.unblockTask(self)
        guard pid > 0 else {
            return nil
        }
        notifier?.wait(forPid: pid)
        return pid
    }

    @discardableResult
    func waitForReceived(count: Int, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        return signal.wait(file: file, line: line) { locked { _received.count >= count } }
    }

    @discardableResult
    func waitForReadCalls(_ count: Int, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        return signal.wait(file: file, line: line) { readCalls >= count }
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
        set { signal.notify { locked { _coprocess = newValue } } }
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
                // Like PTYTask, treat a closed descriptor as a read error.
                var n = -1
                if !(ownedFileDescriptor?.withFileDescriptor { fd in
                    n = Darwin.read(fd, pointer.baseAddress! + bytesRead, 1024)
                } ?? false) {
                    errno = EBADF
                }
                return n
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
                    if let _budget, bytesRead > 0 {
                        if !_budget.tryAcquire() {
                            _readsWithoutCapacity += 1
                        } else {
                            _slotsTaken += 1
                            if let _consumer {
                                _consumer.async {
                                    _budget.release()
                                }
                            }
                        }
                    }
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
            var n = -1
            if !(ownedFileDescriptor?.withFileDescriptor { fd in
                n = Darwin.write(fd, pointer.baseAddress!, length)
            } ?? false) {
                errno = EBADF
            }
            return n
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
        notifier?.unblockTask(self)
    }

    var hasReadCapacity: Bool {
        locked { _budget?.hasCapacity ?? true }
    }

    func notifyWhenReadCapacityAvailable(on queue: DispatchQueue!, block: (() -> Void)!) {
        if let budget = locked({ _budget }) {
            budget.notifyWhenCapacityAvailable(on: queue, block)
        } else {
            queue.async(execute: block)
        }
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

    // Subclasses override this to use another implementation.
    fileprivate func makeNotifier(coprocessChangeHandler: @escaping () -> Void,
                                  reaper: ((pid_t) -> Void)?) -> TaskNotifier {
        return TaskNotifier(forTestingWithSelect: probe.select,
                            coprocessChangeHandler: coprocessChangeHandler,
                            reaper: reaper)
    }

    // Returns once the notifier has handled everything that was ready when this was called, and
    // has stopped using the file descriptors of tasks deregistered before it was called.
    @discardableResult
    fileprivate func flush(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        return probe.flush(notifier, file: file, line: line)
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
        notifier = makeNotifier(coprocessChangeHandler: { [weak self] in
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
    fileprivate func deregisterAndFlush(_ tasks: FakeTask..., file: StaticString = #filePath, line: UInt = #line) {
        for task in tasks {
            notifier.deregister(task)
        }
        XCTAssertTrue(flush(file: file, line: line))
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
            XCTAssertTrue(flush(file: file, line: line))
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

    fileprivate func makeTask(pidToWaitOn: pid_t = 0) throws -> (FakeTask, RawPTY) {
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
        XCTAssertTrue(flush())
        withExtendedLifetime(pty) {}
    }

    func testDeregisterNeverRegisteredIsHarmless() throws {
        let (task, pty) = try makeTask()
        notifier.deregister(task)
        XCTAssertTrue(flush())
        withExtendedLifetime(pty) {}
    }

    // Documents current behavior: a task registered twice is still read once per iteration,
    // because the loop skips an fd it has already handled. Deregistering once removes both
    // entries.
    func testDoubleRegistrationDeliversBytesOnce() throws {
        let (task, pty) = try makeTask()
        notifier.register(task)
        notifier.register(task)
        XCTAssertTrue(flush())
        // Small enough for the tty to queue in one piece and for one processRead to drain, so a
        // second read in the same iteration would show up as a zero-length read.
        let expected = pattern(count: 50)
        pty.writeToSlave(expected)
        XCTAssertTrue(task.waitForReceived(count: expected.count))
        XCTAssertTrue(flush())
        XCTAssertEqual(task.received, expected)
        XCTAssertEqual(task.readCalls, 1)
        XCTAssertEqual(task.zeroLengthReads, 0)

        notifier.deregister(task)
        XCTAssertTrue(flush())
        pty.writeToSlave(Data("x".utf8))
        XCTAssertTrue(flush())
        XCTAssertEqual(task.readCalls, 1, "One deregister removes a task that was registered twice")
    }

    func testRegisteringTwiceCallsDidRegisterOnce() throws {
        let (task, pty) = try makeTask()
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
        withExtendedLifetime(pty) {}
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
        XCTAssertTrue(flush())
        pty.writeToSlave(Data("hello".utf8))
        XCTAssertTrue(flush())
        XCTAssertEqual(task.readCalls, 0)

        // Like -[PTYTask setPaused:NO], the task changes its answer and unblocks.
        task.setWantsRead(true)
        notifier.unblockTask(task)
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
        XCTAssertTrue(flush())
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
            XCTAssertTrue(flush())
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
        XCTAssertTrue(flush())
        pty.closeSlave()
        XCTAssertTrue(task.waitForBrokenPipe())
        XCTAssertTrue(flush())
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
        let task = FakeTask(fd: OwnedFileDescriptor(fds[0]), notifier: notifier)
        notifier.register(task)
        close(fds[1])
        XCTAssertTrue(task.waitForBrokenPipe())
        XCTAssertTrue(flush())
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
        XCTAssertTrue(flush())
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
        XCTAssertTrue(flush())
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
        XCTAssertTrue(flush())

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
        XCTAssertTrue(flush())

        kill(pid, SIGKILL)
        XCTAssertTrue(coprocessChangeSignal.wait { self.coprocessChanges > 0 })
        XCTAssertNil(task.coprocess)
        XCTAssertEqual(cat.pid, -1)

        waitForExitWithoutReaping(pid)
        assertEventuallyReaped(pid)

        deregisterAndFlush(task)
        withExtendedLifetime(pty) {}
    }

    // A coprocess that goes away closes its pipes, even if something else still holds their
    // wrappers and it was never terminated.
    func testDeallocatingACoprocessClosesItsPipes() throws {
        var pid: pid_t = -1
        var read: OwnedFileDescriptor?
        var write: OwnedFileDescriptor?
        weak var weakCat: Coprocess?
        try autoreleasepool {
            let cat = try makeCatCoprocess()
            weakCat = cat
            pid = cat.pid
            read = cat.ownedReadFileDescriptor
            write = cat.ownedWriteFileDescriptor
            // The stderr reader keeps the coprocess alive until the child's stderr closes.
            kill(pid, SIGKILL)
        }
        // The reader lets go of it on a background queue at some point after EOF.
        let deallocated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in weakCat == nil },
                                                    object: nil)
        wait(for: [deallocated], timeout: timeout)
        XCTAssertEqual(read?.isClosed, true)
        XCTAssertEqual(write?.isClosed, true)
        var status: Int32 = 0
        XCTAssertEqual(waitpid(pid, &status, 0), pid)
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
        XCTAssertTrue(coprocess.ownedWriteFileDescriptor.withFileDescriptor { fd in
            XCTAssertEqual(Darwin.write(fd, "\n", 1), 1)
        })

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
    fileprivate func makeCatCoprocess() throws -> Coprocess {
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
class TaskIOCharacterizationWithChildReaperTests: TaskIOCharacterizationTests {
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

// Runs every test above with task I/O monitors instead of the select loop.
final class TaskIOMonitorCharacterizationTests: TaskIOCharacterizationWithChildReaperTests {
    fileprivate override func makeNotifier(coprocessChangeHandler: @escaping () -> Void,
                                           reaper: ((pid_t) -> Void)?) -> TaskNotifier {
        return TaskNotifier(forTestingWithTaskIOMonitorsAndCoprocessChangeHandler: coprocessChangeHandler,
                            reaper: reaper)
    }

    @discardableResult
    fileprivate override func flush(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let ok = notifier.flushForTesting(withTimeout: timeout)
        XCTAssertTrue(ok, "Monitors did not become idle", file: file, line: line)
        return ok
    }

    override func testFailedSelectIsRetried() throws {
        throw XCTSkip("There is no select loop")
    }

    override func testBlockedReadStallsOtherTasks() throws {
        throw XCTSkip("See testBlockedReadDoesNotStallOtherTasks")
    }

    // Each task has its own queue, so a task blocked in processRead doesn't hold up another.
    func testBlockedReadDoesNotStallOtherTasks() throws {
        let (blocker, blockerPTY) = try makeTask()
        let (other, otherPTY) = try makeTask()
        let gate = DispatchSemaphore(value: 0)
        blocker.setReadGate(gate)
        notifier.register(blocker)
        notifier.register(other)

        blockerPTY.writeToSlave(Data("a".utf8))
        XCTAssertTrue(blocker.waitUntilBlockedInRead())
        otherPTY.writeToSlave(Data("b".utf8))
        XCTAssertTrue(other.waitForReceived(count: 1))
        XCTAssertTrue(blocker.isBlockedInRead)

        blocker.setReadGate(nil)
        gate.signal()
        XCTAssertTrue(blocker.waitForReceived(count: 1))
        deregisterAndFlush(blocker, other)
    }

    // When the task can't take more input, the monitor stops reading instead of blocking, and
    // starts again once there is room.
    func testFullBudgetStopsReadingUntilThereIsRoom() throws {
        let (task, pty) = try makeTask()
        let budget = TokenBudget(capacity: 2)
        task.setBudget(budget)
        notifier.register(task)
        // Wait for each read so every byte takes a slot of its own.
        pty.writeToSlave(Data("a".utf8))
        XCTAssertTrue(task.waitForReceived(count: 1))
        pty.writeToSlave(Data("b".utf8))
        XCTAssertTrue(task.waitForReceived(count: 2))
        XCTAssertFalse(budget.hasCapacity)

        pty.writeToSlave(Data("c".utf8))
        // Flushing waits for the monitor to handle the readable fd, which it does by not reading.
        XCTAssertTrue(flush())
        XCTAssertEqual(task.received, Data("ab".utf8))

        // One of two slots in use is the low watermark.
        budget.release()
        XCTAssertTrue(task.waitForReceived(count: 3))
        XCTAssertEqual(task.received, Data("abc".utf8))
        XCTAssertEqual(task.readsWithoutCapacity, 0)
        deregisterAndFlush(task)
    }

    // A flood with a consumer that stops and starts loses and reorders nothing, and never reads
    // without room for what it reads.
    func testFloodWithStalledConsumer() throws {
        let (task, pty) = try makeTask()
        let budget = TokenBudget(capacity: 4)
        let consumer = DispatchQueue(label: "TaskIOMonitorCharacterizationTests.consumer")
        consumer.suspend()
        task.setBudget(budget, consumer: consumer)
        notifier.register(task)

        let expected = pattern(count: 256 * 1024)
        let written = expectation(description: "written")
        DispatchQueue.global().async {
            pty.writeToSlave(expected)
            written.fulfill()
        }
        // The consumer isn't running, so reading stops once the budget is full.
        XCTAssertTrue(task.waitForReadCalls(4))
        XCTAssertTrue(flush())
        XCTAssertEqual(task.readCalls, 4)
        XCTAssertLessThan(task.received.count, expected.count)

        consumer.resume()
        XCTAssertTrue(task.waitForReceived(count: expected.count))
        wait(for: [written], timeout: timeout)
        XCTAssertEqual(task.received, expected)
        XCTAssertEqual(task.readsWithoutCapacity, 0)
        deregisterAndFlush(task)
    }

    // A monitor cancelled while it waits for room must resume its read source before cancelling
    // it, or the source's cancel handler never runs and the flush times out.
    func testDeregisterWhileWaitingForRoom() throws {
        let (task, pty) = try makeTask()
        let budget = TokenBudget(capacity: 1)
        task.setBudget(budget)
        notifier.register(task)
        pty.writeToSlave(Data("a".utf8))
        XCTAssertTrue(task.waitForReceived(count: 1))
        pty.writeToSlave(Data("b".utf8))
        XCTAssertTrue(flush())
        XCTAssertEqual(task.readCalls, 1)

        deregisterAndFlush(task)
        budget.release()
        XCTAssertEqual(task.received, Data("a".utf8))
    }

    // What `fd` refers to, or nil if it is not open. Comparing identities shows whether a number
    // still refers to the same file, since the test host may reuse a closed number at any time.
    private func identity(_ fd: Int32) -> [Int64]? {
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            return nil
        }
        return [Int64(info.st_dev), Int64(bitPattern: info.st_ino), Int64(info.st_rdev)]
    }

    // Closing the pty while it is registered must not close it under the monitor's sources. It is
    // closed once the monitor is done with it.
    func testClosingWhileRegisteredWaitsForTheMonitor() throws {
        let (task, pty) = try makeTask()
        var number: Int32 = -1
        pty.master.withFileDescriptor { number = $0 }
        let original = identity(number)
        XCTAssertNotNil(original)
        notifier.register(task)
        XCTAssertTrue(flush())

        pty.master.close()
        XCTAssertEqual(task.ownedFileDescriptor?.isClosed, true)
        XCTAssertEqual(identity(number), original, "Closed while the monitor still watches it")

        deregisterAndFlush(task)
        XCTAssertNotEqual(identity(number), original, "Not closed after the monitor let go")
    }

    // -[Coprocess terminate] while the monitor services the coprocess leaves its pipes open until
    // the monitor stops using them.
    func testTerminatedCoprocessIsClosedWhenTheMonitorLetsGo() throws {
        let (task, pty) = try makeTask()
        let cat = try makeCatCoprocess()
        let pid = cat.pid
        var readNumber: Int32 = -1
        var writeNumber: Int32 = -1
        cat.ownedReadFileDescriptor.withFileDescriptor { readNumber = $0 }
        cat.ownedWriteFileDescriptor.withFileDescriptor { writeNumber = $0 }
        let readIdentity = identity(readNumber)
        let writeIdentity = identity(writeNumber)
        task.coprocess = cat
        notifier.register(task)
        XCTAssertTrue(flush())

        // Terminate it without removing it from the task, so the monitor keeps its sources.
        objc_sync_enter(task)
        cat.terminate()
        objc_sync_exit(task)
        XCTAssertEqual(identity(readNumber), readIdentity, "Closed while the monitor still watches it")
        XCTAssertEqual(identity(writeNumber), writeIdentity, "Closed while the monitor still watches it")

        task.coprocess = nil
        notifier.unblockTask(task)
        XCTAssertTrue(flush())
        XCTAssertNotEqual(identity(readNumber), readIdentity, "Not closed after the monitor let go")
        XCTAssertNotEqual(identity(writeNumber), writeIdentity, "Not closed after the monitor let go")

        notifier.wait(forPid: pid)
        assertEventuallyReaped(pid)
        deregisterAndFlush(task)
        withExtendedLifetime(pty) {}
    }

    // A session's next task (as after a restart) can wait on a budget its previous task left full
    // while waiting for room.
    func testNewTaskCanWaitOnABudgetLeftFull() throws {
        let budget = TokenBudget(capacity: 1)
        let (old, oldPTY) = try makeTask()
        old.setBudget(budget)
        notifier.register(old)
        oldPTY.writeToSlave(Data("a".utf8))
        XCTAssertTrue(old.waitForReceived(count: 1))
        oldPTY.writeToSlave(Data("b".utf8))
        XCTAssertTrue(flush())
        deregisterAndFlush(old)

        let (new, newPTY) = try makeTask()
        new.setBudget(budget)
        notifier.register(new)
        newPTY.writeToSlave(Data("c".utf8))
        XCTAssertTrue(flush())
        XCTAssertEqual(new.readCalls, 0)

        budget.release()
        XCTAssertTrue(new.waitForReceived(count: 1))
        XCTAssertEqual(new.received, Data("c".utf8))
        deregisterAndFlush(new)
        XCTAssertEqual(old.received, Data("a".utf8))
    }
}

// MARK: - Stress

// A deterministic random number generator, so a failing run can be reproduced from its seed (as
// far as thread scheduling allows).
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func data(count: Int) -> Data {
        var result = Data(count: count)
        result.withUnsafeMutableBytes { buffer in
            for i in 0..<buffer.count {
                buffer[i] = UInt8(truncatingIfNeeded: next())
            }
        }
        return result
    }
}

// Runs a block on a thread of its own. The stress test's helpers block, and blocking GCD's worker
// threads could starve the monitors' queues.
private final class TestThread {
    private let done = DispatchSemaphore(value: 0)

    init(_ name: String, _ block: @escaping () -> Void) {
        let thread = Thread { [done] in
            block()
            done.signal()
        }
        thread.name = name
        thread.start()
    }

    // Waits up to `deadline`, which defaults to the per-wait timeout. Pass .distantFuture for a
    // thread that does many waits, each with its own deadline.
    func join(until deadline: DispatchTime? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(done.wait(timeout: deadline ?? .now() + timeout),
                       .success,
                       "Thread did not finish",
                       file: file,
                       line: line)
    }
}

// Writes to a non-blocking fd until everything is written or stop() is called, whichever is
// first. Unlike RawPTY.writeToSlave, it can be abandoned while nothing is reading.
private final class StoppableWriter {
    private var stopPipe: [Int32] = [-1, -1]

    init() {
        _ = pipe(&stopPipe)
    }

    deinit {
        close(stopPipe[0])
        close(stopPipe[1])
    }

    func stop() {
        var byte: UInt8 = 0
        _ = Darwin.write(stopPipe[1], &byte, 1)
    }

    func write(_ data: Data, to fd: Int32) {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if n > 0 {
                    offset += n
                    continue
                }
                if n < 0 && errno == EINTR {
                    continue
                }
                guard n < 0 && errno == EAGAIN else {
                    XCTFail("write failed: \(errno)")
                    return
                }
                var fds = [pollfd(fd: fd, events: Int16(POLLOUT), revents: 0),
                           pollfd(fd: stopPipe[0], events: Int16(POLLIN), revents: 0)]
                if poll(&fds, 2, -1) < 0 && errno != EINTR {
                    XCTFail("poll failed: \(errno)")
                    return
                }
                if fds[1].revents != 0 {
                    return
                }
            }
        }
    }
}

extension TaskIOMonitorCharacterizationTests {
    private enum StressPhase: CaseIterable {
        case bulkRead
        case trickleRead
        case bulkWrite
        case duplex
        case pausedRead
        case stalledConsumer
        case coprocessEcho
        case coprocessExits
    }

    private enum StressEnding: CaseIterable {
        case deregister
        case endOfFile
        case deregisterDuringTraffic
    }

    // Many tasks at once, each running a random series of phases that read, write, pause, stall
    // the consumer, and add and remove coprocesses, then ending in a random way. Meanwhile another
    // thread registers and deregisters tasks as fast as it can, and idle tasks sit registered
    // throughout. Every byte in each direction is checked.
    //
    // Raise the constants below for a longer soak.
    func testStress() throws {
        let seed: UInt64 = 0x5EED_7A51
        let rounds = 3
        let workersPerRound = 8
        let phasesPerWorker = 6
        print("TaskIOMonitor stress test seed: \(String(seed, radix: 16))")

        // These should never be read from, and their monitors are neighbors of the busy ones.
        var idle = [(FakeTask, RawPTY)]()
        for _ in 0..<16 {
            let (task, pty) = try makeTask()
            notifier.register(task)
            idle.append((task, pty))
        }

        for round in 0..<rounds {
            var threads = [TestThread]()
            for worker in 0..<workersPerRound {
                let workerSeed = seed &+ UInt64(round * 1000 + worker)
                threads.append(TestThread("stress worker \(round).\(worker)") { [self] in
                    var rng = SplitMix64(seed: workerSeed)
                    runStressWorker(phases: phasesPerWorker, rng: &rng)
                })
            }
            let churnSeed = seed &+ UInt64(round * 1000 + 999)
            threads.append(TestThread("stress churn \(round)") { [self] in
                var rng = SplitMix64(seed: churnSeed)
                churnRegistrations(count: 100, rng: &rng)
            })
            // Every blocking step in a worker has its own deadline, so it always finishes.
            threads.forEach { $0.join(until: .distantFuture) }
        }

        for (task, pty) in idle {
            XCTAssertEqual(task.readCalls, 0)
            deregisterAndFlush(task)
            withExtendedLifetime(pty) {}
        }
    }

    private func flush(_ task: FakeTask, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(notifier.flushForTesting(task: task, timeout: timeout),
                      "Monitor did not become idle",
                      file: file,
                      line: line)
    }

    private func runStressWorker(phases: Int, rng: inout SplitMix64) {
        let task: FakeTask
        let pty: RawPTY
        do {
            (task, pty) = try makeTask()
        } catch {
            XCTFail("makeTask failed: \(error)")
            return
        }
        notifier.register(task)
        defer {
            // Harmless if already deregistered. Keeps an early return from leaving a monitor on
            // fds that are about to be closed and reused by other workers.
            notifier.deregister(task)
            flush(task)
            withExtendedLifetime(pty) {}
        }
        // Everything written to the slave, in order. The task must receive exactly this.
        var expected = Data()

        for _ in 0..<phases {
            let phase = StressPhase.allCases.randomElement(using: &rng)!
            switch phase {
            case .bulkRead:
                let data = rng.data(count: Int.random(in: 1...(512 * 1024), using: &rng))
                expected.append(data)
                let writer = TestThread("bulk writer") { pty.writeToSlave(data) }
                XCTAssertTrue(task.waitForReceived(count: expected.count))
                writer.join()

            case .trickleRead:
                for _ in 0..<Int.random(in: 1...200, using: &rng) {
                    let data = rng.data(count: Int.random(in: 1...16, using: &rng))
                    expected.append(data)
                    pty.writeToSlave(data)
                    XCTAssertTrue(task.waitForReceived(count: expected.count))
                }

            case .bulkWrite:
                let data = rng.data(count: Int.random(in: 1...(256 * 1024), using: &rng))
                var echoed = Data()
                let reader = TestThread("bulk reader") { echoed = pty.readFromSlave(count: data.count) }
                writeInRandomChunks(data, to: task, rng: &rng)
                reader.join()
                XCTAssertEqual(echoed, data)

            case .duplex:
                let input = rng.data(count: Int.random(in: 1...(256 * 1024), using: &rng))
                let output = rng.data(count: Int.random(in: 1...(256 * 1024), using: &rng))
                expected.append(input)
                var echoed = Data()
                let reader = TestThread("duplex reader") { echoed = pty.readFromSlave(count: output.count) }
                let writer = TestThread("duplex writer") { pty.writeToSlave(input) }
                writeInRandomChunks(output, to: task, rng: &rng)
                XCTAssertTrue(task.waitForReceived(count: expected.count))
                reader.join()
                writer.join()
                XCTAssertEqual(echoed, output)

            case .pausedRead:
                task.setWantsRead(false)
                notifier.unblockTask(task)
                flush(task)
                let readsBefore = task.readCalls
                // Small enough for the pty to hold without anyone reading, so the flush has
                // something pending to wait for and proves the monitor declined to read it.
                let first = rng.data(count: Int.random(in: 1...512, using: &rng))
                let rest = rng.data(count: Int.random(in: 0...(64 * 1024), using: &rng))
                expected.append(first)
                expected.append(rest)
                pty.writeToSlave(first)
                flush(task)
                let writer = TestThread("paused writer") { pty.writeToSlave(rest) }
                XCTAssertEqual(task.readCalls, readsBefore, "Read while paused")
                task.setWantsRead(true)
                notifier.unblockTask(task)
                XCTAssertTrue(task.waitForReceived(count: expected.count))
                writer.join()

            case .stalledConsumer:
                let capacity = Int.random(in: 1...8, using: &rng)
                let budget = TokenBudget(capacity: capacity)
                let consumer = DispatchQueue(label: "stress consumer")
                consumer.suspend()
                task.setBudget(budget, consumer: consumer)
                // Each read takes at most 4KB, so this can't fit in the budget.
                let data = rng.data(count: capacity * 4096 + Int.random(in: 1...(256 * 1024), using: &rng))
                expected.append(data)
                let slotsBefore = task.slotsTaken
                let writer = TestThread("stalled writer") { pty.writeToSlave(data) }
                XCTAssertTrue(task.waitForSlotsTaken(slotsBefore + capacity))
                flush(task)
                XCTAssertEqual(task.slotsTaken, slotsBefore + capacity, "Read with a full budget")
                XCTAssertLessThan(task.received.count, expected.count)
                consumer.resume()
                XCTAssertTrue(task.waitForReceived(count: expected.count))
                writer.join()
                // Let every slot be released and any capacity callback run before dropping it.
                consumer.sync {}
                flush(task)
                XCTAssertEqual(task.readsWithoutCapacity, 0)
                XCTAssertTrue(budget.hasCapacity)
                task.setBudget(nil)

            case .coprocessEcho:
                let cat: Coprocess
                do {
                    cat = try makeCatCoprocess()
                } catch {
                    XCTFail("makeCatCoprocess failed: \(error)")
                    return
                }
                task.coprocess = cat
                notifier.unblockTask(task)
                // pty slave -> task -> cat -> task's write buffer -> pty slave
                let data = rng.data(count: Int.random(in: 1...(128 * 1024), using: &rng))
                expected.append(data)
                var echoed = Data()
                let reader = TestThread("echo reader") { echoed = pty.readFromSlave(count: data.count) }
                let writer = TestThread("echo writer") { pty.writeToSlave(data) }
                XCTAssertTrue(task.waitForReceived(count: expected.count))
                writer.join()
                reader.join()
                XCTAssertEqual(echoed, data)
                if let pid = task.stopCoprocess() {
                    assertEventuallyReaped(pid)
                }

            case .coprocessExits:
                let cat: Coprocess
                do {
                    cat = try makeCatCoprocess()
                } catch {
                    XCTFail("makeCatCoprocess failed: \(error)")
                    return
                }
                let pid = cat.pid
                task.coprocess = cat
                notifier.unblockTask(task)
                flush(task)
                kill(pid, SIGKILL)
                // The monitor sees EOF, reaps it, and removes it from the task.
                XCTAssertTrue(task.waitForCoprocessRemoved())
                XCTAssertEqual(cat.pid, -1)
                assertEventuallyReaped(pid)
            }
            XCTAssertEqual(task.received, expected)
            XCTAssertEqual(task.brokenPipeCalls, 0)
        }

        switch StressEnding.allCases.randomElement(using: &rng)! {
        case .deregister:
            notifier.deregister(task)
            flush(task)

        case .endOfFile:
            pty.closeSlave()
            XCTAssertTrue(task.waitForBrokenPipe())
            flush(task)
            XCTAssertEqual(task.brokenPipeCalls, 1)

        case .deregisterDuringTraffic:
            let data = rng.data(count: 4 * 1024 * 1024)
            let writer = StoppableWriter()
            let thread = TestThread("abandoned writer") { writer.write(data, to: pty.slave) }
            XCTAssertTrue(task.waitForReceived(count: expected.count + Int.random(in: 1...(64 * 1024), using: &rng)))
            notifier.deregister(task)
            flush(task)
            let readsAfterCancel = task.readCalls
            // Whatever was read before the monitor stopped arrived intact and in order.
            let received = task.received
            XCTAssertEqual(received, (expected + data).prefix(received.count))
            writer.stop()
            thread.join()
            XCTAssertEqual(task.readCalls, readsAfterCancel, "Read after cancellation")
            expected = received
        }
        XCTAssertEqual(task.received, expected)
        XCTAssertEqual(task.readsWithoutCapacity, 0)
        XCTAssertNil(task.coprocess)
    }

    private func writeInRandomChunks(_ data: Data, to task: FakeTask, rng: inout SplitMix64) {
        var offset = 0
        while offset < data.count {
            let end = min(data.count, offset + Int.random(in: 1...8192, using: &rng))
            task.write(data.subdata(in: offset..<end), coprocess: false)
            offset = end
        }
    }

    // Registers and deregisters tasks as fast as possible, sometimes twice, sometimes with a byte
    // in flight, so monitors start and cancel while others are busy.
    private func churnRegistrations(count: Int, rng: inout SplitMix64) {
        for _ in 0..<count {
            let task: FakeTask
            let pty: RawPTY
            do {
                (task, pty) = try makeTask()
            } catch {
                XCTFail("makeTask failed: \(error)")
                return
            }
            notifier.register(task)
            if Bool.random(using: &rng) {
                notifier.register(task)
            }
            if Bool.random(using: &rng) {
                pty.writeToSlave(Data("x".utf8))
            }
            if Bool.random(using: &rng) {
                task.write(Data("y".utf8), coprocess: false)
            }
            notifier.deregister(task)
            if Bool.random(using: &rng) {
                notifier.deregister(task)
            }
            // The pty can't be closed until the monitor is done with it.
            flush(task)
            withExtendedLifetime(pty) {}
        }
    }
}
