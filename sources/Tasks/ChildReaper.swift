//
//  ChildReaper.swift
//  iTerm2
//
//  Reaps child processes as they exit. Each pid gets a kqueue process-exit source, so neither a
//  SIGCHLD handler nor polling is needed. Only pids passed to reap(_:) are ever waited on, so
//  children that other code waits for (such as Process) are left alone.
//
//  Nothing else may wait for a pid handed to the reaper. If something else reaped it, the pid
//  could be reused by a new child, and the reaper would then reap that child instead.
//

import Foundation

@objc(iTermChildReaper)
final class ChildReaper: NSObject {
    @objc(sharedInstance) static let shared = ChildReaper(didReap: nil)

    private let queue: DispatchQueue
    // Called on the reaper's queue when it stops watching a pid. The Bool is true if the pid was
    // reaped and false if it can't be (for example, it is not a child of this process).
    private let didReap: ((pid_t, Bool) -> Void)?
    // Has waitpid's signature. Tests replace it to simulate a child that can't be reaped yet.
    private let waitForChild: (pid_t, UnsafeMutablePointer<Int32>, Int32) -> pid_t

    private final class Watch {
        let source: DispatchSourceProcess
        // Delay before the next retry once the process has exited.
        var retryDelay = ChildReaper.initialRetryDelay

        init(source: DispatchSourceProcess) {
            self.source = source
        }
    }
    private static let initialRetryDelay: TimeInterval = 0.01
    private static let maximumRetryDelay: TimeInterval = 1

    // Access only on `queue`.
    private var watches = [pid_t: Watch]()
    // Pids requested and not yet reaped or given up on. Checked when a request is made, so requests
    // made while a pid is watched count as one even if the queue handles them after the reap. A
    // request for a new process that got the pid in the moment between waitpid reaping it and its
    // removal from here would be dropped; that needs the pid to be reused within microseconds.
    private let requested = MutableAtomicObject(Set<pid_t>())

    // Tests pass `queue` to control when requests are handled.
    init(didReap: ((pid_t, Bool) -> Void)?,
         waitpid: @escaping (pid_t, UnsafeMutablePointer<Int32>, Int32) -> pid_t = Darwin.waitpid,
         queue: DispatchQueue = DispatchQueue(label: "com.iterm2.child-reaper")) {
        self.didReap = didReap
        self.waitForChild = waitpid
        self.queue = queue
        super.init()
    }

    // Only test instances are ever freed.
    deinit {
        for watch in watches.values {
            watch.source.cancel()
        }
    }

    // Safe to call from any thread and before or after the process exits. A second request for a
    // pid that is still being watched is ignored. A request after the pid was reaped refers to
    // whatever process has that pid now.
    @objc(reapProcessWithID:)
    func reap(_ pid: pid_t) {
        // waitpid treats 0 and negative pids as process groups, which could reap other code's
        // children.
        guard pid > 0 else {
            DLog("Ignore request to reap pid \(pid)")
            return
        }
        guard requested.mutableAccess({ $0.insert(pid).inserted }) else {
            DLog("Already waiting for pid \(pid)")
            return
        }
        queue.async { [self] in
            watch(pid)
        }
    }

    private func watch(_ pid: pid_t) {
        dispatchPrecondition(condition: .onQueue(queue))
        // reap(_:) lets each pid through once until its watch ends.
        it_assert(watches[pid] == nil, "Already watching pid \(pid)")
        RLog("Wait for pid \(pid)")
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        let watch = Watch(source: source)
        source.setEventHandler { [weak self, weak watch] in
            guard let self, let watch, watches[pid] === watch else {
                return
            }
            if tryToReap(pid) == .notYet {
                scheduleRetry(pid, watch: watch)
            }
        }
        watches[pid] = watch
        source.activate()
        // It may already have exited. If this reaps it, any event the source delivers later is
        // ignored because the watch is removed.
        _ = tryToReap(pid)
    }

    // The process has exited but can't be reaped yet. That's normal for a moment until it becomes
    // a zombie, but macOS has also been seen to make waitpid hang on an exited child. Never block
    // (that would stop all reaping); keep retrying with backoff instead, as the old polled dead
    // pool did.
    private func scheduleRetry(_ pid: pid_t, watch: Watch) {
        dispatchPrecondition(condition: .onQueue(queue))
        let delay = watch.retryDelay
        watch.retryDelay = min(delay * 2, Self.maximumRetryDelay)
        if delay < Self.maximumRetryDelay && watch.retryDelay == Self.maximumRetryDelay {
            RLog("pid \(pid) exited but is still not reapable. Retry every \(Self.maximumRetryDelay)s")
        } else {
            DLog("pid \(pid) exited but is not reapable yet. Retry in \(delay)s")
        }
        queue.asyncAfter(deadline: .now() + delay) { [weak self, weak watch] in
            guard let self, let watch, watches[pid] === watch else {
                return
            }
            if tryToReap(pid) == .notYet {
                scheduleRetry(pid, watch: watch)
            }
        }
    }

    private enum ReapResult {
        case reaped
        // It has not exited, or has exited but is not reapable yet. Still watching it.
        case notYet
        // waitpid failed (for example, it is not a child). Stopped watching it.
        case failed
    }

    private func tryToReap(_ pid: pid_t) -> ReapResult {
        dispatchPrecondition(condition: .onQueue(queue))
        var status: Int32 = 0
        var result: pid_t
        repeat {
            result = waitForChild(pid, &status, WNOHANG)
        } while result < 0 && errno == EINTR
        if result == 0 {
            return .notYet
        }
        // A failure is permanent (such as ECHILD), so retrying would never succeed.
        let outcome: ReapResult
        if result == pid {
            RLog("Reaped pid \(pid)")
            outcome = .reaped
        } else {
            let error = errno
            // Our status pointer and options are always valid, so these mean something is badly
            // wrong.
            it_assert(result != -1 || (error != EFAULT && error != EINVAL),
                      "waitpid(\(pid)) failed with errno \(error)")
            // ECHILD is expected when a pid is requested again after it was reaped.
            RLog("waitpid(\(pid)) returned \(result) with errno \(error). Stop waiting for it.")
            outcome = .failed
        }
        watches.removeValue(forKey: pid)?.source.cancel()
        requested.mutableAccess { _ = $0.remove(pid) }
        didReap?(pid, outcome == .reaped)
        return outcome
    }
}
