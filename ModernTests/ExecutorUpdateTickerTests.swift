//
//  ExecutorUpdateTickerTests.swift
//  iTerm2
//
//  One ticker sends every session's executor updates to the main thread, so the number of timer
//  fires and main-thread dispatches doesn't grow with the number of busy sessions.
//

import XCTest
@testable import iTerm2SharedARC

final class ExecutorUpdateTickerTests: XCTestCase {
    // Ticks only when the test says so.
    private final class FakeTickSource: ExecutorUpdateTickSource {
        private let mutex = Mutex()
        private var _handler: (() -> Void)?

        var isRunning: Bool {
            return mutex.sync { _handler != nil }
        }

        func start(_ handler: @escaping () -> Void) {
            mutex.sync {
                XCTAssertNil(_handler, "Started twice")
                _handler = handler
            }
        }

        func stop() {
            mutex.sync {
                XCTAssertNotNil(_handler, "Stopped while not running")
                _handler = nil
            }
        }

        func tick() {
            mutex.sync { _handler }?()
        }
    }

    // Holds blocks sent to "main" until the test runs them.
    private final class FakeMain {
        private let mutex = Mutex()
        private var blocks = [() -> Void]()

        var dispatchCount: Int {
            return mutex.sync { blocks.count }
        }

        func deliver(_ block: @escaping () -> Void) {
            mutex.sync { blocks.append(block) }
        }

        func runAll() {
            let pending = mutex.sync {
                let pending = blocks
                blocks.removeAll()
                return pending
            }
            for block in pending {
                block()
            }
        }
    }

    private final class Counter {
        var value = 0
    }

    // Only moves when the test moves it.
    private final class FakeClock {
        private let mutex = Mutex()
        private var _now = UInt64(1_000_000_000)

        var now: UInt64 {
            return mutex.sync { _now }
        }

        func advance(by seconds: TimeInterval) {
            mutex.sync { _now += UInt64(seconds * 1e9) }
        }
    }

    private let period = 1.0 / 120.0
    private var tickSource: FakeTickSource!
    private var main: FakeMain!
    private var clock: FakeClock!
    private var ticker: ExecutorUpdateTicker!

    override func setUp() {
        super.setUp()
        tickSource = FakeTickSource()
        main = FakeMain()
        clock = FakeClock()
        let main = self.main!
        let clock = self.clock!
        ticker = ExecutorUpdateTicker(tickSource: tickSource,
                                      period: period,
                                      now: { clock.now },
                                      deliver: { main.deliver($0) })
    }

    private func makeClient(_ counter: Counter) -> ExecutorUpdateTickerClient {
        return ticker.makeClient {
            counter.value += 1
        }
    }

    // The first update after output was idle goes out right away, so new output isn't delayed.
    func testFirstUpdateIsDeliveredRightAway() {
        let fired = Counter()
        let client = makeClient(fired)
        client.markNeedsUpdate()
        XCTAssertEqual(main.dispatchCount, 1)
        main.runAll()
        XCTAssertEqual(fired.value, 1)
        XCTAssertTrue(tickSource.isRunning)
    }

    // While ticking, updates wait for the next tick and coalesce into one.
    func testUpdatesWhileTickingWaitForTheNextTickAndCoalesce() {
        let fired = Counter()
        let client = makeClient(fired)
        client.markNeedsUpdate()
        main.runAll()
        client.markNeedsUpdate()
        client.markNeedsUpdate()
        client.markNeedsUpdate()
        XCTAssertEqual(main.dispatchCount, 0)

        tickSource.tick()
        XCTAssertEqual(main.dispatchCount, 1)
        main.runAll()
        XCTAssertEqual(fired.value, 2)
    }

    // Every session with an update goes out in one dispatch per tick.
    func testOneDispatchPerTickForAllSessions() {
        let counters = (0..<10).map { _ in Counter() }
        let clients = counters.map { makeClient($0) }
        // Each session's first update goes out right away.
        for client in clients {
            client.markNeedsUpdate()
        }
        main.runAll()
        for client in clients {
            client.markNeedsUpdate()
        }
        XCTAssertEqual(main.dispatchCount, 0)

        tickSource.tick()
        XCTAssertEqual(main.dispatchCount, 1)
        main.runAll()
        XCTAssertEqual(counters.map(\.value), Array(repeating: 2, count: 10))
    }

    // A quiet session's first update goes out right away even while another session keeps the
    // ticker running, so typing in one tab isn't delayed by output in another.
    func testQuietSessionsUpdateIsImmediateWhileAnotherSessionTicks() {
        let busy = Counter()
        let quiet = Counter()
        let busyClient = makeClient(busy)
        let quietClient = makeClient(quiet)
        busyClient.markNeedsUpdate()
        main.runAll()
        busyClient.markNeedsUpdate()
        XCTAssertTrue(tickSource.isRunning)

        quietClient.markNeedsUpdate()
        XCTAssertEqual(main.dispatchCount, 1)
        main.runAll()
        XCTAssertEqual(quiet.value, 1)
        XCTAssertEqual(busy.value, 1)
    }

    // A session that hasn't delivered for a period goes out right away again, while one that
    // delivered recently waits for the tick.
    func testSessionQuietForAPeriodIsImmediateAgain() {
        let other = Counter()
        let fired = Counter()
        let otherClient = makeClient(other)
        let client = makeClient(fired)
        client.markNeedsUpdate()
        main.runAll()
        otherClient.markNeedsUpdate()
        main.runAll()

        clock.advance(by: period / 2)
        client.markNeedsUpdate()
        XCTAssertEqual(main.dispatchCount, 0)
        tickSource.tick()
        main.runAll()
        XCTAssertEqual(fired.value, 2)

        // Keep the ticker running with the other session's output.
        otherClient.markNeedsUpdate()
        clock.advance(by: period * 2)
        client.markNeedsUpdate()
        XCTAssertEqual(main.dispatchCount, 1)
        main.runAll()
        XCTAssertEqual(fired.value, 3)
    }

    // After a keystroke, the session's next update (the echo) goes out right away even if one went
    // out within the last period.
    func testExpeditedUpdateGoesOutRightAwayEvenIfOneWentOutRecently() {
        let fired = Counter()
        let client = makeClient(fired)
        client.markNeedsUpdate()
        main.runAll()
        client.expedite()
        client.markNeedsUpdate()
        XCTAssertEqual(main.dispatchCount, 1)
        main.runAll()
        XCTAssertEqual(fired.value, 2)
    }

    // An update already waiting for the tick goes out right away when the session is expedited, and
    // isn't sent a second time at the tick.
    func testExpeditedUpdateWaitingForTheTickGoesOutRightAway() {
        let fired = Counter()
        let client = makeClient(fired)
        client.markNeedsUpdate()
        main.runAll()
        client.markNeedsUpdate()
        XCTAssertEqual(main.dispatchCount, 0)

        client.expedite()
        client.markNeedsUpdate()
        XCTAssertEqual(main.dispatchCount, 1)
        main.runAll()
        XCTAssertEqual(fired.value, 2)
        tickSource.tick()
        main.runAll()
        XCTAssertEqual(fired.value, 2)
    }

    // Expediting applies to one update: the one after it waits for the tick as usual.
    func testExpediteAppliesToOneUpdate() {
        let fired = Counter()
        let client = makeClient(fired)
        client.markNeedsUpdate()
        main.runAll()
        client.expedite()
        client.markNeedsUpdate()
        main.runAll()
        client.markNeedsUpdate()
        XCTAssertEqual(main.dispatchCount, 0)
        tickSource.tick()
        main.runAll()
        XCTAssertEqual(fired.value, 3)
    }

    // A tick with nothing to send stops the timer, and the next update goes out right away again.
    func testTickerStopsWhenIdleAndTheNextUpdateIsImmediate() {
        let fired = Counter()
        let client = makeClient(fired)
        client.markNeedsUpdate()
        main.runAll()
        tickSource.tick()
        XCTAssertEqual(main.dispatchCount, 0)
        XCTAssertFalse(tickSource.isRunning)

        client.markNeedsUpdate()
        XCTAssertEqual(main.dispatchCount, 1)
        main.runAll()
        XCTAssertEqual(fired.value, 2)
        XCTAssertTrue(tickSource.isRunning)
    }

    // An update marked while the last one is being delivered goes out at the next tick.
    func testUpdateMarkedDuringDeliveryGoesOutAtTheNextTick() {
        let fired = Counter()
        var client: ExecutorUpdateTickerClient!
        client = ticker.makeClient {
            fired.value += 1
            if fired.value == 1 {
                client.markNeedsUpdate()
            }
        }
        client.markNeedsUpdate()
        main.runAll()
        tickSource.tick()
        main.runAll()
        XCTAssertEqual(fired.value, 2)
    }

    // Sessions on many threads mark updates while the ticker ticks. Every update marked is followed
    // by a delivery that started after it, so nothing is lost.
    func testNoUpdateIsLostUnderConcurrency() {
        final class Session {
            let marks = iTermAtomicInt64Create()
            var marksSeenByLastDelivery: Int64 = 0
            var client: ExecutorUpdateTickerClient!
            deinit {
                iTermAtomicInt64Free(marks)
            }
        }
        let serialMain = DispatchQueue(label: "test.main")
        let clock = self.clock!
        let ticker = ExecutorUpdateTicker(tickSource: tickSource,
                                          period: period,
                                          now: { clock.now },
                                          deliver: { serialMain.async(execute: $0) })
        let sessions = (0..<16).map { _ in Session() }
        for session in sessions {
            session.client = ticker.makeClient { [session] in
                // Runs on serialMain only.
                session.marksSeenByLastDelivery = iTermAtomicInt64Get(session.marks)
            }
        }
        let done = MutableAtomicObject(false)
        let tickerFinished = DispatchSemaphore(value: 0)
        let tickerThread = Thread { [tickSource] in
            while !done.value {
                tickSource!.tick()
            }
            tickerFinished.signal()
        }
        tickerThread.start()
        DispatchQueue.concurrentPerform(iterations: sessions.count) { i in
            let session = sessions[i]
            for _ in 0..<2000 {
                iTermAtomicInt64Add(session.marks, 1)
                session.client.markNeedsUpdate()
            }
        }
        done.set(true)
        tickerFinished.wait()
        // Drain: deliver what's pending until the ticker stops.
        while tickSource.isRunning {
            tickSource.tick()
            serialMain.sync {}
        }
        serialMain.sync {}
        for session in sessions {
            XCTAssertEqual(session.marksSeenByLastDelivery, iTermAtomicInt64Get(session.marks))
        }
    }
}
