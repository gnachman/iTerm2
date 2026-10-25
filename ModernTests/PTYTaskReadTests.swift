//
//  PTYTaskReadTests.swift
//  iTerm2
//
//  Drives -[PTYTask processRead] directly on a task that is not registered with any
//  TaskNotifier.
//

import XCTest
@testable import iTerm2SharedARC

private final class RecordingTaskDelegate: NSObject, PTYTaskDelegate {
    enum Event: Equatable {
        case read(Data)
        case brokenPipe
    }
    private(set) var events = [Event]()

    func threadedReadTask(_ buffer: UnsafeMutablePointer<CChar>!, length: Int32) {
        events.append(.read(Data(bytes: buffer, count: Int(length))))
    }

    func threadedTaskBrokenPipe() {
        events.append(.brokenPipe)
    }

    func brokenPipe() {}
    func tmuxClientWrite(_ data: Data!) {}
    func taskDiedImmediately() {}
    func taskDiedWithError(_ error: String!) {}
    func taskDidChangeTTY(_ task: PTYTask!) {}
    func taskDidRegister(_ task: PTYTask!) {}
    func taskDidChangePaused(_ task: PTYTask!, paused: Bool) {}
    func taskMuteCoprocessDidChange(_ task: PTYTask!, hasMuteCoprocess: Bool) {}
    func taskDidResize(to gridSize: VT100GridSize, pixelSize: NSSize) {}
    func taskDidReadFromCoprocessWhileSSHIntegration(inUse data: Data!) {}
    func taskHasReadCapacity() -> Bool { true }
    func taskNotifyWhenReadCapacityAvailable(on queue: DispatchQueue!, block: (() -> Void)!) {}
}

final class PTYTaskReadTests: XCTestCase {
    private var delegate: RecordingTaskDelegate!

    override func setUp() {
        super.setUp()
        delegate = RecordingTaskDelegate()
    }

    // The task closes `fd` when it is deallocated.
    private func makeTask(fd: OwnedFileDescriptor) -> PTYTask {
        fd.nonblocking = true
        let task = PTYTask(forTestingWith: fd)!
        task.delegate = delegate
        return task
    }

    // TaskNotifier hands each of a task's pids to the reaper once, however many times the task is
    // deregistered.
    func testEachPidIsHandedToTheReaperOnce() throws {
        let (read, write) = try makePipe()
        defer { write.close() }
        let task = try XCTUnwrap(makeTask(fd: read) as? iTermTask)
        XCTAssertTrue(task.markPidHanded(toReaper: 123))
        XCTAssertFalse(task.markPidHanded(toReaper: 123))
        XCTAssertTrue(task.markPidHanded(toReaper: 456))
    }

    private func makePipe() throws -> (read: OwnedFileDescriptor, write: OwnedFileDescriptor) {
        guard let pipe = OwnedFileDescriptor.makePipe(),
              let read = pipe.firstObject,
              let write = pipe.secondObject else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return (read, write)
    }

    private func write(_ data: Data, to fd: OwnedFileDescriptor) -> Int {
        var written = -1
        fd.withFileDescriptor { fd in
            written = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, $0.count) }
        }
        return written
    }

    private var readData: Data {
        return delegate.events.reduce(into: Data()) { result, event in
            if case .read(let data) = event {
                result.append(data)
            }
        }
    }

    func testNothingToReadIsNotEOF() throws {
        let fds = try makePipe()
        defer { fds.write.close() }
        let task = makeTask(fd: fds.read)

        task.processRead()

        XCTAssertFalse(task.hasBrokenPipe())
        XCTAssertFalse(delegate.events.contains(RecordingTaskDelegate.Event.brokenPipe))
    }

    func testPipeEOFIsBrokenPipe() throws {
        let fds = try makePipe()
        let task = makeTask(fd: fds.read)
        fds.write.close()

        task.processRead()

        XCTAssertTrue(task.hasBrokenPipe())
        XCTAssertEqual(delegate.events.filter { $0 == RecordingTaskDelegate.Event.brokenPipe }.count, 1)
        XCTAssertEqual(readData, Data())
    }

    // On macOS a pty master's read() returns 0 (not EIO) once the slave has no openers.
    func testPtyEOFIsBrokenPipe() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let task = makeTask(fd: OwnedFileDescriptor(master))
        close(slave)

        task.processRead()

        XCTAssertTrue(task.hasBrokenPipe())
        XCTAssertEqual(delegate.events.filter { $0 == RecordingTaskDelegate.Event.brokenPipe }.count, 1)
    }

    // TaskNotifier can call brokenPipe twice in one iteration (once from processRead seeing EOF and
    // again for the select exception on a pty). The delegate must hear about it only once, or a
    // session that restarts on exit would end its new shell.
    func testBrokenPipeIsReportedOnce() throws {
        let fds = try makePipe()
        let task = makeTask(fd: fds.read)
        fds.write.close()

        task.processRead()
        task.brokenPipe()

        XCTAssertEqual(delegate.events.filter { $0 == RecordingTaskDelegate.Event.brokenPipe }.count, 1)
    }

    func testDataBeforeEOFIsDeliveredBeforeBrokenPipe() throws {
        let fds = try makePipe()
        let task = makeTask(fd: fds.read)
        // Exactly one full read, so EOF is seen by the next read() within the same processRead.
        let payload = Data((0..<1024).map { UInt8($0 & 0xff) })
        let written = write(payload, to: fds.write)
        XCTAssertEqual(written, payload.count)
        fds.write.close()

        task.processRead()

        XCTAssertEqual(delegate.events, [RecordingTaskDelegate.Event.read(payload), .brokenPipe])
        XCTAssertTrue(task.hasBrokenPipe())
    }

    func testDataWithoutEOFIsNotBrokenPipe() throws {
        let fds = try makePipe()
        defer { fds.write.close() }
        let task = makeTask(fd: fds.read)
        let payload = Data("hello".utf8)
        let written = write(payload, to: fds.write)
        XCTAssertEqual(written, payload.count)

        task.processRead()

        XCTAssertEqual(delegate.events, [RecordingTaskDelegate.Event.read(payload)])
        XCTAssertFalse(task.hasBrokenPipe())
    }

    // MARK: Input queues

    private func makeTask(inputQueue: TaskInputQueue) -> PTYTask {
        let task = PTYTask(forTestingWith: inputQueue)!
        task.delegate = delegate
        return task
    }

    func testInputQueueBytesAreRead() {
        let queue = TaskInputQueue()
        let task = makeTask(inputQueue: queue)
        queue.append(Data("hello".utf8))

        task.processRead()

        XCTAssertEqual(delegate.events, [RecordingTaskDelegate.Event.read(Data("hello".utf8))])
        XCTAssertFalse(task.hasBrokenPipe())
        XCTAssertFalse(queue.isReadable)
    }

    // At most 4 KB per call, like reading a file descriptor.
    func testInputQueueReadIsLimited() {
        let queue = TaskInputQueue()
        let task = makeTask(inputQueue: queue)
        let payload = Data((0..<5000).map { UInt8($0 & 0xff) })
        queue.append(payload)

        task.processRead()
        task.processRead()

        XCTAssertEqual(delegate.events, [RecordingTaskDelegate.Event.read(payload.prefix(4096)),
                                         .read(payload.suffix(from: 4096))])
    }

    func testClosedInputQueueIsBrokenPipe() {
        let queue = TaskInputQueue()
        let task = makeTask(inputQueue: queue)
        queue.close()

        task.processRead()

        XCTAssertTrue(task.hasBrokenPipe())
        XCTAssertEqual(delegate.events, [RecordingTaskDelegate.Event.brokenPipe])
    }

    // The session closing its pane's queue (as when it is deallocated) ends the task's input, like
    // closing a pipe's write end. The task must still read to find that out.
    func testQueueClosedBySessionIsReadAsEndOfFile() throws {
        let queue = TaskInputQueue()
        let task = makeTask(inputQueue: queue)
        queue.close()

        XCTAssertTrue(try XCTUnwrap(task as AnyObject as? iTermTask).wantsRead)
        task.processRead()

        XCTAssertTrue(task.hasBrokenPipe())
    }

    // Resizing a pane reports its new size to the session even though there is no tty to resize.
    func testInputQueueTaskIsReadyForWindowSizes() throws {
        let queue = TaskInputQueue()
        let task = makeTask(inputQueue: queue)
        let delegate = try XCTUnwrap(task as AnyObject as? WinSizeControllerDelegate)
        XCTAssertTrue(delegate.winSizeControllerIsReady())

        task.stop()

        XCTAssertFalse(delegate.winSizeControllerIsReady())
    }

    // The task reads its queue only while it is open, and closing it closes the queue.
    func testInputQueueTaskIOAllowedUntilClosed() throws {
        let queue = TaskInputQueue()
        let task = try XCTUnwrap(makeTask(inputQueue: queue) as? iTermTask)
        XCTAssertTrue(task.inputQueue === queue)
        XCTAssertTrue(task.wantsRead)
        XCTAssertFalse(task.wantsWrite)

        (task as! PTYTask).stop()

        XCTAssertTrue(queue.isClosed)
        XCTAssertFalse(task.wantsRead)
    }
}
