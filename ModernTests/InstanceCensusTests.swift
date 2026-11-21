//
//  InstanceCensusTests.swift
//  ModernTests
//
//  Checks the instance census (InstanceCensus.swift), so that the lifetime
//  witness tests built on it can be trusted.
//

import XCTest
@testable import iTerm2SharedARC

// Each probe class is tracked by one test only, so the tests do not depend on
// each other's order.
private class CensusProbe: NSObject {}
private final class CensusProbeSubclass: CensusProbe {
    var payload = [Int]()

    deinit {
        payload.removeAll()
    }
}
private final class CensusPreexistingProbe: NSObject {}
private final class CensusThreadProbe: NSObject {}
private final class CensusMarkProbe: NSObject {}

final class InstanceCensusTests: XCTestCase {
    private let census = InstanceCensus.shared

    func testCountsSwiftInstancesUntilTheyAreFreed() {
        census.track([CensusProbe.self])
        let mark = census.mark()
        let before = census.count(of: CensusProbe.self)
        var probes: [CensusProbe] = autoreleasepool {
            [CensusProbe(), CensusProbeSubclass(), CensusProbeSubclass()]
        }
        XCTAssertEqual(census.count(of: CensusProbe.self), before + 3)
        XCTAssertEqual(census.count(of: CensusProbe.self, since: mark), 3)
        XCTAssertEqual(census.count(of: CensusProbeSubclass.self, since: mark), 2,
                       "a subclass of a tracked class is counted under its own class too")

        probes.removeLast()
        XCTAssertEqual(census.count(of: CensusProbe.self, since: mark), 2)
        probes.removeAll()
        XCTAssertEqual(census.count(of: CensusProbe.self), before)
        XCTAssertEqual(census.survivors(of: [CensusProbe.self], since: mark), [:])
    }

    // VT100Screen is Objective-C with its own -dealloc, and makes a
    // VT100ScreenMutableState itself, which the census counts although the
    // test never sees it.
    func testCountsObjectiveCInstancesMadeByOtherObjects() {
        census.track([VT100Screen.self, VT100ScreenMutableState.self, TokenExecutor.self])
        let mark = census.mark()
        weak var weakScreen: VT100Screen?
        autoreleasepool {
            let screen = VT100Screen()
            weakScreen = screen
            XCTAssertEqual(census.count(of: VT100Screen.self, since: mark), 1)
            XCTAssertGreaterThanOrEqual(census.count(of: VT100ScreenMutableState.self, since: mark), 1)
            XCTAssertEqual(census.count(of: TokenExecutor.self, since: mark), 1,
                           "the instance a Swift convenience initializer discarded is not counted")
        }
        let deadline = Date(timeIntervalSinceNow: 30)
        while weakScreen != nil || !census.survivors(of: [VT100Screen.self, VT100ScreenMutableState.self, TokenExecutor.self], since: mark).isEmpty,
              Date() < deadline {
            autoreleasepool {
                _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
        }
        XCTAssertNil(weakScreen)
        XCTAssertEqual(census.survivors(of: [VT100Screen.self, VT100ScreenMutableState.self, TokenExecutor.self], since: mark), [:])
    }

    func testInstancesFromBeforeTrackingAreNotCounted() {
        var early: CensusPreexistingProbe? = CensusPreexistingProbe()
        census.track([CensusPreexistingProbe.self])
        XCTAssertEqual(census.count(of: CensusPreexistingProbe.self), 0)
        var late: CensusPreexistingProbe? = CensusPreexistingProbe()
        XCTAssertEqual(census.count(of: CensusPreexistingProbe.self), 1)
        early = nil
        XCTAssertEqual(census.count(of: CensusPreexistingProbe.self), 1,
                       "freeing an instance that was never counted must not change the count")
        late = nil
        XCTAssertEqual(census.count(of: CensusPreexistingProbe.self), 0)
        XCTAssertNil(early)
        XCTAssertNil(late)
    }

    func testRecordsTheThreadOfDeallocation() {
        census.track([CensusThreadProbe.self])
        let mark = census.mark()
        var onMain: CensusThreadProbe? = CensusThreadProbe()
        onMain = nil
        XCTAssertNil(onMain)

        let box = ProbeBox(CensusThreadProbe())
        let done = DispatchSemaphore(value: 0)
        // async, because sync from the main thread may run the block on the main thread.
        DispatchQueue.global().async {
            box.probe = nil
            done.signal()
        }
        done.wait()
        XCTAssertEqual(census.deallocThreads(of: CensusThreadProbe.self, since: mark).main, 1)
        XCTAssertEqual(census.deallocThreads(of: CensusThreadProbe.self, since: mark).other, 1)
    }

    func testMarkExcludesEarlierAllocations() {
        census.track([CensusMarkProbe.self])
        let earlier = CensusMarkProbe()
        let mark = census.mark()
        XCTAssertEqual(census.count(of: CensusMarkProbe.self, since: mark), 0)
        let later = CensusMarkProbe()
        XCTAssertEqual(census.count(of: CensusMarkProbe.self, since: mark), 1)
        XCTAssertEqual(census.count(of: CensusMarkProbe.self), 2)
        withExtendedLifetime((earlier, later)) {}
    }
}

private final class ProbeBox {
    var probe: CensusThreadProbe?

    init(_ probe: CensusThreadProbe) {
        self.probe = probe
    }
}
