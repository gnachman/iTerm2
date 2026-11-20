//
//  PTYTaskProcessInfoPIDTests.swift
//  ModernTests
//
//  Which pid a task looks up process info under. A tmux pane session's task never forks anything
//  itself; the only pid it has is the pane pid tmux reported. The async fetch has always used
//  that one, but the cached fast path used the task's own pid, which for a pane is nothing, so
//  the inactive-pane poll got nil back and cleared the pane's job ancestry on every tick: a
//  spurious "claude ended" that tore down the workgroup.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class PTYTaskProcessInfoPIDTests: XCTestCase {
    func testTmuxPanePIDWinsForProcessInfoLookups() {
        let task = PTYTask()!
        XCTAssertEqual(task.processInfoPID, task.pid, "without a pane pid, the task's own pid")

        task.tmuxClientProcessID = 4242
        XCTAssertEqual(task.processInfoPID, 4242, "a pane pid replaces the task's own pid")

        task.tmuxClientProcessID = nil
        XCTAssertEqual(task.processInfoPID, task.pid, "clearing the pane pid goes back to the task's own")
    }

    // jobManager is declared in PTYTask+Private.h, which Swift cannot see.
    private func installFixedPIDJobManager(in task: PTYTask) {
        let jobManager = FixedPIDJobManager(queue: DispatchQueue(label: "PTYTaskProcessInfoPIDTests"))
        task.perform(NSSelectorFromString("setJobManager:"), with: jobManager)
    }

    // PTYTask had two -processInfoPID methods: the one in the ProcessInfo category and one the
    // compiler synthesized in the main implementation, returning an ivar nothing assigned. These
    // pin what callers observe through the property, with a job manager whose pid is not 0, so
    // that a getter returning the unassigned ivar fails both of them.
    func testProcessInfoPIDIsTheTaskPIDWithoutATmuxClient() {
        let task = PTYTask()!
        installFixedPIDJobManager(in: task)
        XCTAssertEqual(task.pid, FixedPIDJobManager.fixedPID)
        XCTAssertNil(task.tmuxClientProcessID)
        XCTAssertEqual(task.processInfoPID, FixedPIDJobManager.fixedPID)
    }

    func testProcessInfoPIDIsTheTmuxClientPIDWhenSet() {
        let task = PTYTask()!
        installFixedPIDJobManager(in: task)
        task.tmuxClientProcessID = 4243
        defer { task.tmuxClientProcessID = nil }
        XCTAssertEqual(task.processInfoPID, 4243)
    }

    // The cached lookup and the async fetch must agree on the pid, or the poll path and the event
    // path describe two different processes for the same session.
    func testCachedLookupUsesTheSamePIDAsTheFetch() {
        let task = PTYTask()!
        task.tmuxClientProcessID = NSNumber(value: getpid())
        defer { task.tmuxClientProcessID = nil }
        // The lookups are the SessionProcessInfoProvider conformance, declared in a category
        // header Swift cannot see, so go through the protocol. The fetch asks the process cache
        // for an immediate update when it has nothing yet, so by the time it completes the cache
        // holds this pid.
        let provider = (task as AnyObject) as! SessionProcessInfoProvider
        let fetched = expectation(description: "fetched")
        var fetchedInfo: iTermProcessInfo?
        provider.fetchProcessInfoForCurrentJob { info in
            fetchedInfo = info
            fetched.fulfill()
        }
        wait(for: [fetched], timeout: 10)
        let cached = provider.cachedProcessInfoIfAvailable()
        XCTAssertEqual(cached?.processID, fetchedInfo?.processID,
                       "cached: \(String(describing: cached)) fetched: \(String(describing: fetchedInfo))")
    }
}

// A job manager that has no process and reports a fixed, nonzero pid. It never forks, attaches,
// or signals anything.
private final class FixedPIDJobManager: NSObject, iTermJobManager {
    static let fixedPID: pid_t = 31337

    let queue: DispatchQueue!
    var tty: String!

    init!(queue: DispatchQueue!) {
        self.queue = queue
        super.init()
    }

    static func available() -> Bool { true }

    var ownedFileDescriptor: OwnedFileDescriptor? { nil }
    var externallyVisiblePid: pid_t { Self.fixedPID }
    var hasJob: Bool { false }
    var sessionRestorationIdentifier: Any! { nil }
    var pidToWaitOn: pid_t { 0 }
    var isSessionRestorationPossible: Bool { false }
    var ioAllowed: Bool { false }
    var isReadOnly: Bool { true }

    func forkAndExec(with ttyState: iTermTTYState,
                     argpath: String!,
                     argv: [String]!,
                     initialPwd: String!,
                     newEnviron: [String]!,
                     task: (any iTermTask)!,
                     completion: ((iTermJobManagerForkAndExecStatus, NSNumber?) -> Void)!) {
        it_fatalError("FixedPIDJobManager does not fork")
    }

    func attach(toServer serverConnection: iTermGeneralServerConnection,
                withProcessID thePid: NSNumber!,
                task: (any iTermTask)!,
                completion: ((iTermJobManagerAttachResults) -> Void)!) {
        it_fatalError("FixedPIDJobManager does not attach")
    }

    func attach(toServer serverConnection: iTermGeneralServerConnection,
                withProcessID thePid: NSNumber!,
                task: (any iTermTask)!) -> iTermJobManagerAttachResults {
        it_fatalError("FixedPIDJobManager does not attach")
    }

    func kill(with mode: iTermJobManagerKillingMode) {
    }

    func closeFileDescriptor() -> Bool {
        false
    }
}
