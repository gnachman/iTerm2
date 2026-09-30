//
//  AdapterShellEnvironment.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/29/26.
//

import Foundation

/// Builds the environment that password manager adapter processes run with.
///
/// Adapters get an explicit environment rather than inheriting iTerm2’s. It used to be empty,
/// which broke CLIs that are scripts rather than native binaries: Homebrew’s `bw` is a Node
/// script whose `#!/usr/bin/env node` shebang needs `node` on PATH (issue 13046). This reads
/// PATH from the user’s login, interactive shell, the same environment a terminal session
/// sees, so Homebrew in .zprofile and version managers in .zshrc (nvm, volta, fnm) are both
/// found, and caches it in memory. Only the first adapter command waits on the shell; later
/// ones use the cached value at once. The cache is refreshed only from `prefetch()`, which the
/// password manager calls when it opens, and at most once per `refreshInterval`, so a PATH
/// change in the shell’s startup files is picked up eventually without a shell launch per
/// command. The usual CLI install directories are appended as a safety net for shells that
/// don’t honor the login flag, or when the shell can’t be run at all.
///
/// Main thread only, like the adapter data sources that use it.
final class AdapterShellEnvironment {
    /// Asks the shell for PATH. Must call its completion exactly once, on the main thread, with
    /// nil when the shell could not be run.
    typealias PathFetcher = (_ completion: @escaping (String?) -> Void) -> Void

    static let shared = AdapterShellEnvironment(
        fetchPath: { completion in
            // printenv rather than `echo $PATH` because fish prints its PATH list separated by
            // spaces. The gateway guarantees delivery: it calls back with nil if the service dies.
            iTermSlowOperationGateway.sharedInstance().runCommand(inUserShell: "/usr/bin/printenv PATH",
                                                                  mode: .loginInteractive,
                                                                  completion: completion)
        },
        timeout: 5,
        dropDeadline: 60,
        refreshInterval: 600)

    /// Appended to the shell’s PATH when missing: Homebrew on Apple silicon and Intel, MacPorts,
    /// then the system directories.
    static let fallbackDirectories = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin",
                                      "/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    private let fetchPath: PathFetcher
    /// How long a waiter is kept waiting for the shell. After this the waiter gets the fallback
    /// for its own command, but the fetch stays in flight so the real PATH replaces the cache
    /// as soon as it arrives. Shell startups with nvm, conda or oh-my-zsh can take longer than
    /// this, and the XPC service allows 15 seconds.
    private let timeout: TimeInterval
    /// After this long with no reply the fetch is treated as lost: the fallback is cached if
    /// nothing else is, and a later `prefetch()` may try again. Well past the service’s own
    /// deadlines, so this only matters if delivery fails entirely.
    private let dropDeadline: TimeInterval
    /// Minimum time between refreshes started by `prefetch()` once a value is cached.
    private let refreshInterval: TimeInterval

    private var cachedPath: String?
    /// True while `cachedPath` holds the fallback rather than a value the shell reported, so a
    /// late reply may still replace it.
    private var cacheIsFallback = false
    private var pending: [([String: String]) -> Void] = []
    private var fetching = false
    /// The in-flight fetch passed `timeout`; new callers get the fallback rather than waiting.
    private var fetchTimedOut = false
    private var lastFetchStart: TimeInterval?
    /// Identifies the current fetch so timers and replies from an earlier one are told apart.
    private var generation = 0

    init(fetchPath: @escaping PathFetcher,
         timeout: TimeInterval,
         dropDeadline: TimeInterval,
         refreshInterval: TimeInterval) {
        self.fetchPath = fetchPath
        self.timeout = timeout
        self.dropDeadline = dropDeadline
        self.refreshInterval = refreshInterval
    }

    /// Starts reading PATH from the user’s shell so it is cached before the first adapter
    /// command needs it, or refreshes a cached value that is older than `refreshInterval`.
    /// This is the only way a refresh starts. Safe to call repeatedly.
    func prefetch() {
        it_assert(Thread.isMainThread, "AdapterShellEnvironment is main thread only")
        guard !fetching else {
            return
        }
        if cachedPath != nil,
           let lastFetchStart,
           ProcessInfo.processInfo.systemUptime - lastFetchStart < refreshInterval {
            return
        }
        fetch()
    }

    /// Calls `completion` on the main thread with the environment to give an adapter. Once PATH
    /// is cached this is immediate and never starts a shell launch; before that it waits for the
    /// shell or the timeout, whichever comes first.
    func environment(_ completion: @escaping ([String: String]) -> Void) {
        it_assert(Thread.isMainThread, "AdapterShellEnvironment is main thread only")
        if let cachedPath {
            completion(Self.environment(path: cachedPath))
            return
        }
        if fetching && fetchTimedOut {
            completion(Self.environment(path: Self.mergedPath(shellPath: nil)))
            return
        }
        pending.append(completion)
        if !fetching {
            fetch()
        }
    }

    private func fetch() {
        fetching = true
        fetchTimedOut = false
        lastFetchStart = ProcessInfo.processInfo.systemUptime
        generation += 1
        let fetchGeneration = generation
        DLog("Reading PATH from the user’s shell for password manager adapters")

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.fetching, self.generation == fetchGeneration else {
                return
            }
            // Stop making callers wait, but keep the fetch: its reply still lands in the cache.
            self.fetchTimedOut = true
            if self.cachedPath == nil {
                let fallback = Self.mergedPath(shellPath: nil)
                DLog("Still waiting for the shell’s PATH; giving waiters \(fallback)")
                self.flushPending(path: fallback)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + dropDeadline) { [weak self] in
            guard let self, self.fetching, self.generation == fetchGeneration else {
                return
            }
            DLog("Gave up waiting for the shell’s PATH")
            self.fetching = false
            self.fetchTimedOut = false
            if self.cachedPath == nil {
                let fallback = Self.mergedPath(shellPath: nil)
                self.cachedPath = fallback
                self.cacheIsFallback = true
                self.flushPending(path: fallback)
            }
        }

        fetchPath { [weak self] value in
            guard let self else {
                return
            }
            let current = self.generation == fetchGeneration
            if current {
                self.fetching = false
                self.fetchTimedOut = false
            }
            let shellPath = value.flatMap { $0.isEmpty ? nil : $0 }
            guard let shellPath else {
                if self.cachedPath == nil {
                    // Nothing better is coming; cache the fallback so callers stop waiting.
                    let fallback = Self.mergedPath(shellPath: nil)
                    DLog("Shell did not report PATH; using \(fallback)")
                    self.cachedPath = fallback
                    self.cacheIsFallback = true
                    self.flushPending(path: fallback)
                } else {
                    // A failed refresh must not replace a good value.
                    DLog("Shell did not report PATH; keeping \(self.cachedPath!)")
                }
                return
            }
            guard current || self.cacheIsFallback else {
                // A reply from a fetch that was given up on, after a newer one succeeded.
                return
            }
            let merged = Self.mergedPath(shellPath: shellPath)
            DLog("Shell PATH=\(shellPath); adapter PATH=\(merged)")
            self.cachedPath = merged
            self.cacheIsFallback = false
            self.flushPending(path: merged)
        }
    }

    private func flushPending(path: String) {
        let completions = pending
        pending = []
        let environment = Self.environment(path: path)
        for completion in completions {
            completion(environment)
        }
    }

    /// The shell’s PATH entries in order, followed by any fallback directories it lacks.
    static func mergedPath(shellPath: String?) -> String {
        var directories = (shellPath ?? "").components(separatedBy: ":").filter { !$0.isEmpty }
        for directory in fallbackDirectories where !directories.contains(directory) {
            directories.append(directory)
        }
        return directories.joined(separator: ":")
    }

    static func environment(path: String) -> [String: String] {
        return ["HOME": NSHomeDirectory(), "PATH": path]
    }
}
