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

    // The task takes ownership of `fd` and closes it when it is deallocated.
    private func makeTask(fd: Int32) -> PTYTask {
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let task = PTYTask(forTestingWithFileDescriptor: fd)!
        task.delegate = delegate
        return task
    }

    private func makePipe() throws -> (read: Int32, write: Int32) {
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return (fds[0], fds[1])
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
        defer { close(fds.write) }
        let task = makeTask(fd: fds.read)

        task.processRead()

        XCTAssertFalse(task.hasBrokenPipe())
        XCTAssertFalse(delegate.events.contains(RecordingTaskDelegate.Event.brokenPipe))
    }

    func testPipeEOFIsBrokenPipe() throws {
        let fds = try makePipe()
        let task = makeTask(fd: fds.read)
        close(fds.write)

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
        let task = makeTask(fd: master)
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
        close(fds.write)

        task.processRead()
        task.brokenPipe()

        XCTAssertEqual(delegate.events.filter { $0 == RecordingTaskDelegate.Event.brokenPipe }.count, 1)
    }

    func testDataBeforeEOFIsDeliveredBeforeBrokenPipe() throws {
        let fds = try makePipe()
        let task = makeTask(fd: fds.read)
        // Exactly one full read, so EOF is seen by the next read() within the same processRead.
        let payload = Data((0..<1024).map { UInt8($0 & 0xff) })
        let written = payload.withUnsafeBytes { Darwin.write(fds.write, $0.baseAddress!, $0.count) }
        XCTAssertEqual(written, payload.count)
        close(fds.write)

        task.processRead()

        XCTAssertEqual(delegate.events, [RecordingTaskDelegate.Event.read(payload), .brokenPipe])
        XCTAssertTrue(task.hasBrokenPipe())
    }

    func testDataWithoutEOFIsNotBrokenPipe() throws {
        let fds = try makePipe()
        defer { close(fds.write) }
        let task = makeTask(fd: fds.read)
        let payload = Data("hello".utf8)
        let written = payload.withUnsafeBytes { Darwin.write(fds.write, $0.baseAddress!, $0.count) }
        XCTAssertEqual(written, payload.count)

        task.processRead()

        XCTAssertEqual(delegate.events, [RecordingTaskDelegate.Event.read(payload)])
        XCTAssertFalse(task.hasBrokenPipe())
    }
}
