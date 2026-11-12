import XCTest
@testable import iTerm2SharedARC

final class FileTreeWatcherTests: XCTestCase {
    private final class Record {
        var roots = [String]()
        var streams = [Stream]()
        var callsOnMain = [Bool]()
        var active = 0
        var maximumActive = 0
    }

    private final class Stream: iTermFileTreeWatchStream {
        let root: String
        let record: Record
        let event: ([String]) -> Void
        var startCount = 0
        var closeCount = 0
        var beforeStart: (() -> Void)?
        var succeeds = true
        private var started = false

        init(root: String, record: Record, event: @escaping ([String]) -> Void) {
            self.root = root
            self.record = record
            self.event = event
        }
        func start() -> Bool {
            record.callsOnMain.append(Thread.isMainThread)
            startCount += 1
            beforeStart?()
            if succeeds {
                started = true
                record.active += 1
                record.maximumActive = max(record.maximumActive, record.active)
            }
            return succeeds
        }
        func close() {
            record.callsOnMain.append(Thread.isMainThread)
            closeCount += 1
            if started { record.active -= 1; started = false }
        }
    }

    private func watcher(queue: DispatchQueue, record: Record,
                         configure: @escaping (Stream) -> Void = { _ in },
                         event: @escaping (String, [String]) -> Void = { _, _ in }) -> iTermFileTreeWatcher {
        iTermFileTreeWatcher(queue: queue, makeStream: { root, _, callback in
            record.callsOnMain.append(Thread.isMainThread)
            record.roots.append(root)
            let stream = Stream(root: root, record: record, event: callback)
            configure(stream)
            record.streams.append(stream)
            return stream
        }, onEvents: event)
    }

    func testQueuedStartsKeepOnlyLatestRootAndSameRootDoesNotRegisterAgain() {
        let queue = DispatchQueue(label: "FileTreeWatcherTests.supersession")
        let record = Record()
        let watcher = watcher(queue: queue, record: record)
        queue.suspend()
        watcher.watch(root: "/tmp/a")
        watcher.watch(root: "/tmp/b")
        watcher.watch(root: "/tmp/a")
        watcher.watch(root: "/tmp/a")
        queue.resume()
        queue.sync {}
        XCTAssertEqual(record.roots, ["/tmp/a"])
        XCTAssertEqual(record.streams.map(\.startCount), [1])
        watcher.watch(root: "/tmp/a")
        queue.sync {}
        XCTAssertEqual(record.roots, ["/tmp/a"])
        watcher.stop()
        queue.sync {}
        XCTAssertEqual(record.streams.map(\.closeCount), [1])
        XCTAssertFalse(record.callsOnMain.contains(true))
    }

    func testStopDuringBlockedRegistrationReturnsWithoutWaitingAndSkipsQueuedRoot() {
        let queue = DispatchQueue(label: "FileTreeWatcherTests.blocked")
        let record = Record()
        let entered = expectation(description: "registration entered on worker")
        let gate = DispatchSemaphore(value: 0)
        let watcher = watcher(queue: queue, record: record, configure: { stream in
            guard stream.root == "/tmp/a" else { return }
            stream.beforeStart = {
                entered.fulfill()
                XCTAssertEqual(gate.wait(timeout: .now() + 5), .success)
            }
        })
        watcher.watch(root: "/tmp/a")
        wait(for: [entered], timeout: 5)
        // These calls must complete while the registration worker still waits on its gate.
        watcher.watch(root: "/tmp/b")
        watcher.stop()
        gate.signal()
        queue.sync {}
        XCTAssertEqual(record.roots, ["/tmp/a"])
        XCTAssertEqual(record.streams.map(\.closeCount), [1])
        XCTAssertEqual(record.active, 0)
        XCTAssertFalse(record.callsOnMain.contains(true))
    }

    func testSwitchingClosesPreviousStreamBeforeStartingNextAndStopIsIdempotent() {
        let queue = DispatchQueue(label: "FileTreeWatcherTests.serial")
        let record = Record()
        let watcher = watcher(queue: queue, record: record)
        for root in ["/tmp/a", "/tmp/b", "/tmp/a"] {
            watcher.watch(root: root)
            queue.sync {}
        }
        watcher.stop()
        watcher.stop()
        queue.sync {}
        XCTAssertEqual(record.roots, ["/tmp/a", "/tmp/b", "/tmp/a"])
        XCTAssertEqual(record.maximumActive, 1)
        XCTAssertEqual(record.active, 0)
        XCTAssertEqual(record.streams.map(\.closeCount), [1, 1, 1])
        XCTAssertFalse(record.callsOnMain.contains(true))
    }

    func testAlreadyQueuedCallbacksFromOldAAndBDoNotReachReturnedA() {
        let queue = DispatchQueue(label: "FileTreeWatcherTests.events")
        let record = Record()
        var received = [String]()
        let current = expectation(description: "current A event delivered")
        let watcher = watcher(queue: queue, record: record, event: { root, paths in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(root, "/tmp/a")
            received.append(contentsOf: paths)
            if paths == ["/tmp/a/current"] { current.fulfill() }
        })
        watcher.watch(root: "/tmp/a")
        queue.sync {}
        record.streams[0].event(["/tmp/a/queued-old"])
        watcher.watch(root: "/tmp/b")
        queue.sync {}
        let oldB = record.streams[1]
        watcher.watch(root: "/tmp/a")
        queue.sync {}
        // The native context may still have a pending callback when its stream is retired.
        oldB.event(["/tmp/b/old"])
        record.streams[0].event(["/tmp/a/old-after-return"])
        record.streams[2].event(["/tmp/a/current"])
        wait(for: [current], timeout: 5)
        XCTAssertEqual(received, ["/tmp/a/current"])
        watcher.stop()
        queue.sync {}
    }

    func testHideRejectsEventAlreadyQueuedToMain() {
        let queue = DispatchQueue(label: "FileTreeWatcherTests.hidden")
        let record = Record()
        var received = [String]()
        let watcher = watcher(queue: queue, record: record, event: { _, paths in received += paths })
        watcher.watch(root: "/tmp/a")
        queue.sync {}
        record.streams[0].event(["/tmp/a/old"])
        watcher.stop()
        queue.sync {}
        let drained = expectation(description: "main callbacks drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
        XCTAssertTrue(received.isEmpty)
    }

    func testDeinitializationWhileStartBlockedCancelsAndClosesWithoutRetainingWatcher() {
        let queue = DispatchQueue(label: "FileTreeWatcherTests.deinit")
        let record = Record()
        let entered = expectation(description: "registration entered")
        let gate = DispatchSemaphore(value: 0)
        var watcher: iTermFileTreeWatcher? = self.watcher(queue: queue, record: record, configure: { stream in
            stream.beforeStart = {
                entered.fulfill()
                XCTAssertEqual(gate.wait(timeout: .now() + 5), .success)
            }
        })
        weak var weakWatcher = watcher
        watcher?.watch(root: "/tmp/a")
        wait(for: [entered], timeout: 5)
        watcher = nil
        XCTAssertNil(weakWatcher)
        weakWatcher = nil
        gate.signal()
        queue.sync {}
        XCTAssertEqual(record.active, 0)
        XCTAssertEqual(record.streams.map(\.closeCount), [1])
    }

    func testFailedStartClosesStreamAndSameRootCanRetry() {
        let queue = DispatchQueue(label: "FileTreeWatcherTests.failure")
        let record = Record()
        let watcher = watcher(queue: queue, record: record, configure: { stream in
            stream.succeeds = record.roots.count > 1
        })
        watcher.watch(root: "/tmp/a")
        queue.sync {}
        XCTAssertEqual(record.active, 0)
        XCTAssertEqual(record.streams.map(\.closeCount), [1])
        watcher.watch(root: "/tmp/a")
        queue.sync {}
        XCTAssertEqual(record.active, 1)
        watcher.stop()
        queue.sync {}
        XCTAssertEqual(record.streams.map(\.closeCount), [1, 1])
    }
}
