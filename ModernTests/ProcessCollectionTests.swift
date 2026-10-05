//
//  ProcessCollectionTests.swift
//  iTerm2
//
//  Ported from the legacy (disabled) iTermProcessCollectionTest.m against the Swift
//  ProcessCollection and iTermProcessInfo. Foreground status comes from a fake
//  ProcessDataSource so no syscalls are made.
//

import XCTest
@testable import iTerm2SharedARC

final class ProcessCollectionTests: XCTestCase {
    // Answers isForeground from a fixed set of pids; everything else is inert.
    private final class ForegroundSetDataSource: NSObject, ProcessDataSource {
        var foregroundPIDs = Set<pid_t>()

        func nameOfProcess(withPid thePid: pid_t,
                           isForeground: UnsafeMutablePointer<ObjCBool>) -> String? {
            isForeground.pointee = ObjCBool(foregroundPIDs.contains(thePid))
            return "process\(thePid)"
        }

        func commandLineArguments(forProcess pid: pid_t,
                                  execName: AutoreleasingUnsafeMutablePointer<NSString>?) -> [String]? {
            return nil
        }

        func startTime(forProcess pid: pid_t) -> Date? {
            return nil
        }

        func ttyRdev(forFileDescriptor fd: Int32, ofProcess pid: pid_t) -> dev_t {
            return 0
        }
    }

    private var dataSource: ForegroundSetDataSource!
    private var collection: ProcessCollection!

    override func setUp() {
        super.setUp()
        dataSource = ForegroundSetDataSource()
        collection = ProcessCollection(dataSource: dataSource)
    }

    override func tearDown() {
        collection = nil
        dataSource = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func add(_ pid: pid_t, parent: pid_t, foreground: Bool = false) {
        collection.addProcess(withProcessID: pid, parentProcessID: parent)
        if foreground {
            dataSource.foregroundPIDs.insert(pid)
        }
    }

    private func deepestForegroundPID(of pid: pid_t) -> pid_t? {
        return collection.info(forProcessID: pid)?.deepestForegroundJob?.processID
    }

    // ? -> a -> b
    //        -> c -> d+
    //        -> e -> f -> g+
    private let a: pid_t = 1, b: pid_t = 2, c: pid_t = 3, d: pid_t = 4, e: pid_t = 5, f: pid_t = 6, g: pid_t = 8

    private func buildMultipleChildrenTree(rootParent: pid_t = 0,
                                           dForeground: Bool = true,
                                           gForeground: Bool = true) {
        add(a, parent: rootParent)
        add(b, parent: a)
        add(c, parent: a)
        add(d, parent: c, foreground: dForeground)
        add(e, parent: a)
        add(f, parent: e)
        add(g, parent: f, foreground: gForeground)
        collection.commit()
    }

    // MARK: - Basic

    func testDeepestForegroundJobOfAncestorIsTheForegroundDescendant() {
        // ? -> 2 -> 3+
        add(2, parent: 1)
        add(3, parent: 2, foreground: true)
        collection.commit()

        XCTAssertEqual(deepestForegroundPID(of: 2), 3)
    }

    func testDeepestForegroundJobOfForegroundLeafIsItself() {
        // ? -> 10 -> 11+
        add(10, parent: 9)
        add(11, parent: 10, foreground: true)
        collection.commit()

        XCTAssertEqual(deepestForegroundPID(of: 11), 11)
    }

    func testUnknownProcessIDHasNoInfo() {
        add(2, parent: 1)
        collection.commit()

        XCTAssertNil(collection.info(forProcessID: 99))
    }

    // MARK: - Multiple children

    func testDeepestForegroundJobPrefersDeepestBranch() {
        buildMultipleChildrenTree()
        XCTAssertEqual(deepestForegroundPID(of: a), g)
    }

    func testDeepestForegroundJobOfNonForegroundLeafIsNil() {
        buildMultipleChildrenTree()
        XCTAssertNil(deepestForegroundPID(of: b))
    }

    func testDeepestForegroundJobOfShallowBranchIsItsOwnForegroundLeaf() {
        buildMultipleChildrenTree()
        XCTAssertEqual(deepestForegroundPID(of: c), d)
        XCTAssertEqual(deepestForegroundPID(of: d), d)
    }

    func testDeepestForegroundJobAlongDeepBranch() {
        buildMultipleChildrenTree()
        XCTAssertEqual(deepestForegroundPID(of: e), g)
        XCTAssertEqual(deepestForegroundPID(of: f), g)
        XCTAssertEqual(deepestForegroundPID(of: g), g)
    }

    // MARK: - No foreground job

    func testNoForegroundJobAnywhereYieldsNilForEveryProcess() {
        buildMultipleChildrenTree(dForeground: false, gForeground: false)

        for pid in [a, b, c, d, e, f, g] {
            XCTAssertNil(deepestForegroundPID(of: pid), "pid \(pid)")
        }
    }

    // MARK: - Cycle

    //  +-> a -> b
    //  |     -> c -> d+
    //  |     -> e -> f -> g+ -+
    //  |                      |
    //  +----------------------+
    func testProcessesOnACycleHaveNoDeepestForegroundJob() {
        buildMultipleChildrenTree(rootParent: g)

        for pid in [a, e, f, g] {
            XCTAssertNil(deepestForegroundPID(of: pid),
                         "failed to find cycle for pid \(pid) in collection \(collection.treeString)")
        }
    }

    func testNonForegroundLeafOutsideCycleHasNoDeepestForegroundJob() {
        buildMultipleChildrenTree(rootParent: g)
        XCTAssertNil(deepestForegroundPID(of: b))
    }

    func testSubtreeOutsideCycleStillResolves() {
        buildMultipleChildrenTree(rootParent: g)
        XCTAssertEqual(deepestForegroundPID(of: c), d)
        XCTAssertEqual(deepestForegroundPID(of: d), d)
    }

    // MARK: - Multiple foreground jobs

    func testDeepestOfNestedForegroundJobsWins() {
        // a -> b+ -> c+
        add(a, parent: 0)
        add(b, parent: a, foreground: true)
        add(c, parent: b, foreground: true)
        collection.commit()

        XCTAssertEqual(deepestForegroundPID(of: a), c)
    }
}
