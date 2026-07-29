//
//  ProcessAncestorNameCacheTests.swift
//  ModernTests
//
//  Covers the last-known-name reuse that keeps a transient failure to read a live
//  process's name from erasing it from foregroundJobAncestorNames (which would look
//  like the job exiting to GlobalJobMonitor).
//

import XCTest
@testable import iTerm2SharedARC

// Names are looked up per pid; a nil value models a read that came back empty for a
// process that is nonetheless alive and in the tree. argv0 is always nil so the
// resolved "title" is just the name, keeping the tree deterministic.
private final class FakeProcessDataSource: NSObject, ProcessDataSource {
    var names: [pid_t: String?] = [:]

    func nameOfProcess(withPid thePid: pid_t,
                       isForeground: UnsafeMutablePointer<ObjCBool>) -> String? {
        isForeground.pointee = ObjCBool(false)
        // names[thePid] is String??; collapse absent-key and present-nil both to nil.
        return names[thePid] ?? nil
    }

    func commandLineArguments(forProcess pid: pid_t,
                              execName: AutoreleasingUnsafeMutablePointer<NSString>?) -> [String]? {
        return nil
    }

    func startTime(forProcess pid: pid_t) -> Date? {
        return Date(timeIntervalSince1970: 1000)
    }

    func ttyRdev(forFileDescriptor fd: Int32, ofProcess pid: pid_t) -> dev_t {
        return 0
    }
}

final class ProcessAncestorNameCacheTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ProcessNameCache.shared.removeAll()
    }

    // Builds login(-zsh) <- claude <- caffeinate. Returns the collection because
    // iTermProcessInfo.parent/collection are weak: the info objects are strongly
    // held only by the collection, so callers must keep it alive while walking the
    // tree (production does this via the process cache's retained collection).
    private func makeTree(_ dataSource: FakeProcessDataSource,
                          claudePpid: pid_t = 1) -> ProcessCollection {
        let collection = ProcessCollection(dataSource: dataSource)
        collection.addProcess(withProcessID: 1, parentProcessID: 0)
        collection.addProcess(withProcessID: 2, parentProcessID: claudePpid)
        collection.addProcess(withProcessID: 3, parentProcessID: 2)
        collection.commit()
        return collection
    }

    private func ancestry(of pid: pid_t, in collection: ProcessCollection) -> [String] {
        return collection.info(forProcessID: pid)!.foregroundJobAncestorNames
    }

    // MARK: - foregroundJobAncestorNames

    func testBaselineAncestryStopsAtLoginShell() {
        let ds = FakeProcessDataSource()
        ds.names = [1: "-zsh", 2: "claude", 3: "caffeinate"]
        let collection = makeTree(ds)
        XCTAssertEqual(ancestry(of: 3, in: collection), ["caffeinate", "claude"])
    }

    // The core regression: a live intermediate ancestor whose name read comes back
    // empty must be recovered from the cache, not dropped.
    func testEmptyNameForLiveAncestorIsReusedFromCache() {
        ProcessNameCache.shared.record(pid: 2, ppid: 1, title: "claude")
        let ds = FakeProcessDataSource()
        ds.names = [1: "-zsh", 2: nil, 3: "caffeinate"]  // claude reads empty this cycle
        let collection = makeTree(ds)
        XCTAssertEqual(ancestry(of: 3, in: collection), ["caffeinate", "claude"])
    }

    // A prior successful walk should warm the cache so the next cycle recovers.
    func testSuccessfulWalkWarmsCacheForNextCycle() {
        let good = FakeProcessDataSource()
        good.names = [1: "-zsh", 2: "claude", 3: "caffeinate"]
        _ = ancestry(of: 3, in: makeTree(good))  // records claude

        let flaky = FakeProcessDataSource()
        flaky.names = [1: "-zsh", 2: nil, 3: "caffeinate"]
        XCTAssertEqual(ancestry(of: 3, in: makeTree(flaky)), ["caffeinate", "claude"])
    }

    // If the pid was reused (different ppid), the stale name must NOT be resurrected.
    func testEmptyNameWithMismatchedPpidIsNotReused() {
        ProcessNameCache.shared.record(pid: 2, ppid: 1, title: "claude")
        let ds = FakeProcessDataSource()
        ds.names = [1: "-zsh", 2: nil, 3: "caffeinate"]
        let collection = makeTree(ds, claudePpid: 99)  // pid 2 now has a different parent
        XCTAssertEqual(ancestry(of: 3, in: collection), ["caffeinate"])
    }

    // MARK: - ProcessNameCache

    func testCacheRecordAndLookup() {
        let cache = ProcessNameCache.shared
        cache.record(pid: 42, ppid: 7, title: "claude")
        XCTAssertEqual(cache.lastKnownTitle(pid: 42, ppid: 7), "claude")
        XCTAssertNil(cache.lastKnownTitle(pid: 42, ppid: 8), "ppid mismatch must miss")
        XCTAssertNil(cache.lastKnownTitle(pid: 43, ppid: 7), "unknown pid must miss")
    }

    func testAnomalyIsLoggedOncePerEpisode() {
        let cache = ProcessNameCache.shared
        cache.record(pid: 42, ppid: 7, title: "claude")
        XCTAssertTrue(cache.shouldLogAnomaly(pid: 42), "first anomaly should log")
        XCTAssertFalse(cache.shouldLogAnomaly(pid: 42), "repeat within an episode is silent")
        // A normal read ends the episode, so the next failure logs again.
        cache.record(pid: 42, ppid: 7, title: "claude")
        XCTAssertTrue(cache.shouldLogAnomaly(pid: 42), "new episode after recovery should log")
        // A dead pid's episode state is dropped by pruning.
        cache.prune(toLivePids: [])
        XCTAssertTrue(cache.shouldLogAnomaly(pid: 42), "pruned pid should start a fresh episode")
    }

    func testCachePruneDropsDeadPids() {
        let cache = ProcessNameCache.shared
        cache.record(pid: 42, ppid: 7, title: "claude")
        cache.record(pid: 43, ppid: 7, title: "caffeinate")
        cache.prune(toLivePids: [NSNumber(value: 42)])
        XCTAssertEqual(cache.lastKnownTitle(pid: 42, ppid: 7), "claude")
        XCTAssertNil(cache.lastKnownTitle(pid: 43, ppid: 7), "pruned pid must be gone")
    }
}
