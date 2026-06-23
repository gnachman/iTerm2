//
//  ProcessInfoProvider.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/19/22.
//

import Foundation

@objc
protocol ProcessCollectionFactory {
    @objc(newProcessCollectionWithDataSource:)
    func newProcessCollection(dataSource: ProcessDataSource) -> ProcessCollectionProvider
}

@objc
protocol ProcessCollectionProvider {
    @objc var processIDs: [pid_t] { get }

    @objc(infoForProcessID:)
    func info(forProcessID pid: pid_t) -> iTermProcessInfo?

    @objc(addProcessWithProcessID:parentProcessID:)
    @discardableResult
    func addProcess(withProcessID: pid_t,
                    parentProcessID: pid_t) -> iTermProcessInfo

    @objc
    func commit()
}

@objc
@MainActor
protocol ProcessInfoProvider {
    @objc(processInfoForPid:)
    func processInfo(for pid: pid_t) -> iTermProcessInfo?

    @objc(setNeedsUpdate:)
    func setNeedsUpdate(_ needsUpdate: Bool)

    @objc(requestImmediateUpdateWithCompletionBlock:)
    func requestImmediateUpdate(completion: @escaping () -> ())

    @objc
    func updateSynchronously()

    @objc(deepestForegroundJobForPid:)
    func deepestForegroundJob(for pid: pid_t) -> iTermProcessInfo?

    // Like deepestForegroundJob(for:) but prefers the deepest foreground job whose
    // stdin or stdout is the session's tty, falling back to the raw deepest
    // foreground job when none qualifies. This hides foreground-process-group
    // members that aren't actually attached to the terminal, e.g. an MCP server
    // piped to its parent or caffeinate writing to /dev/null. The provider derives
    // and caches the session's tty from the tracked root pid's stdio, so callers
    // don't pass it.
    @objc(displayForegroundJobForPid:)
    func displayForegroundJob(for pid: pid_t) -> iTermProcessInfo?

    @objc(registerTrackedPID:)
    func register(trackedPID pid: pid_t)

    @objc(unregisterTrackedPID:)
    func unregister(trackedPID pid: pid_t)

    @objc(processIsDirty:)
    func processIsDirty(_ pid: pid_t) -> Bool

    @objc(sendSignal:toPID:)
    func send(signal: Int32, toPID: Int32)
}

@objc
@MainActor
protocol SessionProcessInfoProvider {
    @objc(cachedProcessInfoIfAvailable)
    func cachedProcessInfoIfAvailable() -> iTermProcessInfo?

    @objc(fetchProcessInfoForCurrentJobWithCompletion:)
    func fetchProcessInfoForCurrentJob(completion: @escaping (iTermProcessInfo?) -> ())
}
