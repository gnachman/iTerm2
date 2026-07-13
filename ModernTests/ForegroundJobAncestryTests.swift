//
//  ForegroundJobAncestryTests.swift
//  ModernTests
//
//  Reproduces the spurious "job ended" that tears down the claudeCode workgroup:
//  a live intermediate ancestor (e.g. "claude") vanishes from
//  foregroundJobAncestorNames for one process-cache cycle even though the process
//  never exited. GlobalJobMonitor can't tell a missing ancestor from an exited one,
//  so it fires job-ended and the workgroup peers are torn down.
//
//  The hypothesis under test: the drop is caused by a *failed parent link*.
//  iTermProcessInfo.parent is a `weak` reference and the ancestor objects are owned
//  only by the ProcessCollection that built them. So the moment a deepest-job info
//  is used after its collection has been freed (PTYSession retains one across cycles
//  in `_lastProcessInfo`, and the process cache replaces the collection on its work
//  queue), the parent chain dangles to nil and the ancestry collapses to just the
//  deepest job. That is exactly the observed ["clangd","claude"] -> ["clangd"].
//
//  Note this is NOT reproducible by dropping a node from a single consistent
//  collection: dropping an intermediate also orphans everything below it (see
//  testMissingIntermediateInLiveCollectionOrphansEverythingBelow), so the deepest
//  job could not remain selected. Only a live node read after its collection died
//  keeps the deepest job while dropping its ancestors.

import XCTest
@testable import iTerm2SharedARC

final class ForegroundJobAncestryTests: XCTestCase {
    // Minimal ProcessDataSource that answers from a fixed pid -> (name, argv0, fg)
    // table so we can build a deterministic process tree with no syscalls.
    private final class FakeProcessDataSource: NSObject, ProcessDataSource {
        struct Entry {
            let name: String
            let argv0: String?
            let foreground: Bool
        }
        var entries = [pid_t: Entry]()

        func nameOfProcess(withPid thePid: pid_t,
                           isForeground: UnsafeMutablePointer<ObjCBool>) -> String? {
            guard let entry = entries[thePid] else {
                isForeground.pointee = ObjCBool(false)
                return nil
            }
            isForeground.pointee = ObjCBool(entry.foreground)
            return entry.name
        }

        func commandLineArguments(forProcess pid: pid_t,
                                  execName: AutoreleasingUnsafeMutablePointer<NSString>?) -> [String]? {
            guard let entry = entries[pid], let argv0 = entry.argv0 else {
                return nil
            }
            execName?.pointee = argv0 as NSString
            return [argv0]
        }

        func startTime(forProcess pid: pid_t) -> Date? {
            return nil
        }

        func ttyRdev(forFileDescriptor fd: Int32, ofProcess pid: pid_t) -> dev_t {
            return 0
        }
    }

    // Models login(100) -> claude(200) -> clangd(300), where clangd is the deepest
    // foreground job. login's argv0 starts with "-" so the ancestry walk stops there
    // (matching a real login shell), giving ["clangd", "claude"].
    private static let loginPID: pid_t = 100
    private static let claudePID: pid_t = 200
    private static let clangdPID: pid_t = 300

    private func makeDataSource() -> FakeProcessDataSource {
        let ds = FakeProcessDataSource()
        ds.entries = [
            Self.loginPID: .init(name: "login", argv0: "-bash", foreground: false),
            Self.claudePID: .init(name: "claude", argv0: nil, foreground: false),
            Self.clangdPID: .init(name: "clangd", argv0: nil, foreground: true),
        ]
        return ds
    }

    private func makeCollection(dataSource: ProcessDataSource) -> ProcessCollection {
        let collection = ProcessCollection(dataSource: dataSource)
        collection.addProcess(withProcessID: Self.loginPID, parentProcessID: 1)
        collection.addProcess(withProcessID: Self.claudePID, parentProcessID: Self.loginPID)
        collection.addProcess(withProcessID: Self.clangdPID, parentProcessID: Self.claudePID)
        collection.commit()
        return collection
    }

    // Baseline: while the collection is alive, the deepest job is clangd and its
    // ancestry is ["clangd", "claude"]. Passes today; guards the model.
    func testBaselineAncestryWithLiveCollection() {
        let ds = makeDataSource()
        let collection = makeCollection(dataSource: ds)

        let login = collection.info(forProcessID: Self.loginPID)
        XCTAssertEqual(login?.deepestForegroundJob?.processID, Self.clangdPID,
                       "clangd should be the selected deepest foreground job")

        let clangd = collection.info(forProcessID: Self.clangdPID)
        XCTAssertEqual(clangd?.foregroundJobAncestorNames, ["clangd", "claude"])
        withExtendedLifetime(collection) {}
    }

    // The bug. PTYSession keeps the deepest job past the collection's lifetime
    // (_lastProcessInfo). Because iTermProcessInfo.parent is weak and the ancestors
    // are owned only by the collection, once the collection is freed the retained
    // deepest job's parent chain dangles to nil and the ancestry collapses to just
    // the deepest job. This is the spurious "claude ended" the workgroup reacted to.
    //
    // FAILS on current code (yields ["clangd"]); flips to passing once a retained
    // deepest job keeps its ancestor chain alive (e.g. strong parent links, or the
    // process cache snapshots the ancestry eagerly / keeps the collection alive as
    // long as any of its infos is reachable).
    func testDeepestJobOutlivingItsCollectionKeepsAncestry() {
        let ds = makeDataSource()
        var clangd: iTermProcessInfo!

        autoreleasepool {
            let collection = makeCollection(dataSource: ds)
            clangd = collection.info(forProcessID: Self.clangdPID)
            // Sanity while the collection is alive.
            XCTAssertEqual(clangd.foregroundJobAncestorNames, ["clangd", "claude"],
                           "precondition: ancestry is intact while the collection is alive")
        }
        // The collection (and the login/claude infos it owned) is now deallocated,
        // but `clangd` is still retained (as PTYSession retains _lastProcessInfo).

        XCTAssertEqual(clangd.foregroundJobAncestorNames, ["clangd", "claude"],
                       "BUG: after the collection was freed the ancestry collapsed; a live 'claude' was dropped because iTermProcessInfo.parent is weak")
    }

    // Contrast: a missing intermediate in a *single, live* collection (the naive
    // TOCTOU-drop story) does NOT reproduce the observed signature. Dropping claude
    // orphans clangd, so clangd is no longer reachable as the deepest job at all,
    // rather than surviving with a truncated ancestry. This is why the real cause
    // must be the dangling-parent-after-free path above, not a dropped node.
    func testMissingIntermediateInLiveCollectionOrphansEverythingBelow() {
        let ds = makeDataSource()
        let collection = ProcessCollection(dataSource: ds)
        collection.addProcess(withProcessID: Self.loginPID, parentProcessID: 1)
        // claude (200) omitted, as if its ppid read failed mid-build.
        collection.addProcess(withProcessID: Self.clangdPID, parentProcessID: Self.claudePID)
        collection.commit()

        let login = collection.info(forProcessID: Self.loginPID)
        // clangd is orphaned (its parent 200 is absent), so it is unreachable from
        // login and cannot be the selected deepest job -> the whole chain is lost,
        // which would surface as ["clangd","claude"] -> [] (a different signature).
        XCTAssertNil(login?.deepestForegroundJob,
                     "with claude dropped, clangd is orphaned and no deepest fg job is reachable from login")
        withExtendedLifetime(collection) {}
    }
}
