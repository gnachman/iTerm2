//
//  RelayKeepaliveTests.swift
//  CompanionCore
//
//  The keepalive ping loop, exercised with an injected ping so no socket is
//  needed: it must ping repeatedly, stop when a ping reports the socket gone,
//  and stop promptly when cancelled.
//

import XCTest
@testable import CompanionTransport

private actor PingRecorder {
    private(set) var count = 0
    private let failAfter: Int
    private var stopWaiter: CheckedContinuation<Void, Never>?

    init(failAfter: Int) { self.failAfter = failAfter }

    func ping() -> Bool {
        count += 1
        if count >= failAfter {
            stopWaiter?.resume()
            stopWaiter = nil
            return false
        }
        return true
    }

    func waitForFailure() async {
        if count >= failAfter { return }
        await withCheckedContinuation { stopWaiter = $0 }
    }

    func countReached(_ n: Int) async {
        while count < n { try? await Task.sleep(nanoseconds: 200_000) }
    }
}

final class RelayKeepaliveTests: XCTestCase {
    func test_pingsRepeatedlyThenStopsWhenSocketReportsGone() async {
        let rec = PingRecorder(failAfter: 4)
        let ka = RelayKeepalive(intervalNanos: 200_000) { await rec.ping() } // 0.2ms
        ka.start()
        await rec.waitForFailure()
        let atFailure = await rec.count
        XCTAssertEqual(atFailure, 4, "loop pings until a ping reports the socket gone")
        // The loop has ended; no further pings accrue.
        try? await Task.sleep(nanoseconds: 5_000_000)
        let later = await rec.count
        XCTAssertEqual(later, 4)
    }

    func test_stopHaltsPinging() async {
        let rec = PingRecorder(failAfter: .max)
        let ka = RelayKeepalive(intervalNanos: 500_000) { await rec.ping() } // 0.5ms
        ka.start()
        await rec.countReached(2)
        ka.stop()
        let afterStop = await rec.count
        try? await Task.sleep(nanoseconds: 10_000_000)
        // At most one in-flight ping may land after stop(); no sustained pinging.
        let settled = await rec.count
        XCTAssertLessThanOrEqual(settled - afterStop, 1)
    }

    func test_startAfterStopIsNoOp() async {
        let rec = PingRecorder(failAfter: .max)
        let ka = RelayKeepalive(intervalNanos: 200_000) { await rec.ping() }
        ka.stop()
        ka.start()
        try? await Task.sleep(nanoseconds: 5_000_000)
        let count = await rec.count
        XCTAssertEqual(count, 0, "a keepalive stopped before start never pings")
    }

    // MARK: withPingTimeout

    func test_pingTimeout_passesThroughAFastResult() async {
        let ok = await withPingTimeout(nanos: 1_000_000_000) { true }
        XCTAssertEqual(ok, true, "a ping that returns true within the timeout passes through")
        let bad = await withPingTimeout(nanos: 1_000_000_000) { false }
        XCTAssertEqual(bad, false, "a ping that returns false within the timeout passes through")
    }

    func test_pingTimeout_boundsAHungPingToNil() async {
        // Model the real wedge: a ping that has not returned by the time the
        // timeout elapses (a JS promise that never settles / a URLSession ping
        // completion that never fires). It must be bounded to nil promptly rather
        // than blocking this call on the ping. A long sleep stands in for the hang
        // without leaking a continuation; withPingTimeout abandons rather than
        // cancels the ping task, so the sleep simply outlives the timeout.
        let start = DispatchTime.now().uptimeNanoseconds
        let result = await withPingTimeout(nanos: 20_000_000) {   // 20ms
            try? await Task.sleep(nanoseconds: 5_000_000_000)     // 5s: outlives the timeout
            return true
        }
        let elapsedMs = (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        XCTAssertNil(result, "a ping still outstanding at the deadline must time out to nil")
        XCTAssertLessThan(elapsedMs, 2_000, "the timeout must fire promptly, not wait on the hung ping")
    }
}
