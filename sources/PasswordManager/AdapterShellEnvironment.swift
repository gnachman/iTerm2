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
/// The AI Usage workgroup toolbar item also takes its PATH from here, without calling
/// `prefetch()`. The same shell run also reports CLAUDE_CONFIG_DIR, which only that item uses
/// (through `shellValues(_:)`); adapters never get it.
///
/// Main thread only, like the adapter data sources that use it.
final class AdapterShellEnvironment {
    /// Asks the shell for PATH and CLAUDE_CONFIG_DIR. Must call its completion exactly once, on
    /// the main thread, with the output of `fetchCommand` (see `parse(shellOutput:)`), or nil
    /// when the shell could not be run.
    typealias PathFetcher = (_ completion: @escaping (String?) -> Void) -> Void

    /// What the shell reported, or the fallback when it could not be read.
    struct ShellValues: Equatable {
        /// The merged PATH (see `mergedPath(shellPath:)`).
        var path: String
        /// The shell's exported CLAUDE_CONFIG_DIR. nil when unset, empty, or not reported.
        var claudeConfigDir: String?
        /// False when these are the fallback because the shell could not be read, so an unset
        /// `claudeConfigDir` means “unknown” rather than “unset”.
        var reportedByShell: Bool
    }

    /// Prints PATH, a newline, then CLAUDE_CONFIG_DIR (nothing when unset). One command, as
    /// the gateway requires, and it exits 0 even when CLAUDE_CONFIG_DIR is unset (a nonzero
    /// status would lose PATH too). It is /bin/sh that expands the variables, from the
    /// exported environment the user's startup files produced, so the result doesn't depend on
    /// the user's shell syntax (fish's own `echo $PATH` would separate entries with spaces).
    static let fetchCommand = #"/bin/sh -c 'printf "%s\n%s" "$PATH" "$CLAUDE_CONFIG_DIR"'"#

    static let shared = AdapterShellEnvironment(
        fetchPath: { completion in
            // The gateway guarantees delivery: it calls back with nil if the service dies.
            iTermSlowOperationGateway.sharedInstance().runCommand(inUserShell: fetchCommand,
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
    /// The CLAUDE_CONFIG_DIR that came with `cachedPath`; nil when unset or `cacheIsFallback`.
    private var cachedClaudeConfigDir: String?
    /// True while `cachedPath` holds the fallback rather than a value the shell reported, so a
    /// late reply may still replace it.
    private var cacheIsFallback = false
    private var pending: [(ShellValues) -> Void] = []
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
        shellValues { values in
            completion(Self.environment(path: values.path))
        }
    }

    /// Like `environment(_:)`, with the same waiting and caching, but delivers what the shell
    /// reported, including CLAUDE_CONFIG_DIR, rather than an adapter environment.
    func shellValues(_ completion: @escaping (ShellValues) -> Void) {
        it_assert(Thread.isMainThread, "AdapterShellEnvironment is main thread only")
        if let cachedPath {
            completion(ShellValues(path: cachedPath,
                                   claudeConfigDir: cachedClaudeConfigDir,
                                   reportedByShell: !cacheIsFallback))
            return
        }
        if fetching && fetchTimedOut {
            completion(Self.fallbackValues)
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
        DLog("Reading PATH from the user’s shell for password manager adapters and AI Usage")

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.fetching, self.generation == fetchGeneration else {
                return
            }
            // Stop making callers wait, but keep the fetch: its reply still lands in the cache.
            self.fetchTimedOut = true
            if self.cachedPath == nil {
                DLog("Still waiting for the shell’s PATH; giving waiters \(Self.fallbackValues.path)")
                self.flushPending(Self.fallbackValues)
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
                self.cacheFallback()
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
            let parsed = value.map { Self.parse(shellOutput: $0) }
            guard let parsed, let shellPath = parsed.path else {
                if self.cachedPath == nil {
                    // Nothing better is coming; cache the fallback so callers stop waiting.
                    DLog("Shell did not report PATH; using \(Self.fallbackValues.path)")
                    self.cacheFallback()
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
            DLog("Shell PATH=\(shellPath); adapter PATH=\(merged); CLAUDE_CONFIG_DIR=\(parsed.claudeConfigDir ?? "(unset)")")
            self.cachedPath = merged
            self.cachedClaudeConfigDir = parsed.claudeConfigDir
            self.cacheIsFallback = false
            self.flushPending(ShellValues(path: merged,
                                          claudeConfigDir: parsed.claudeConfigDir,
                                          reportedByShell: true))
        }
    }

    private func cacheFallback() {
        cachedPath = Self.fallbackValues.path
        cachedClaudeConfigDir = nil
        cacheIsFallback = true
        flushPending(Self.fallbackValues)
    }

    private func flushPending(_ values: ShellValues) {
        let completions = pending
        pending = []
        for completion in completions {
            completion(values)
        }
    }

    private static var fallbackValues: ShellValues {
        return ShellValues(path: mergedPath(shellPath: nil), claudeConfigDir: nil, reportedByShell: false)
    }

    /// Splits `fetchCommand`'s output at the first newline into PATH and CLAUDE_CONFIG_DIR.
    /// The gateway trims trailing newlines, so an unset CLAUDE_CONFIG_DIR leaves no newline at
    /// all. Empty values are nil.
    static func parse(shellOutput: String) -> (path: String?, claudeConfigDir: String?) {
        let parts = shellOutput.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let path = parts.first.map(String.init).flatMap { $0.isEmpty ? nil : $0 }
        let claudeConfigDir = parts.count > 1 ? String(parts[1]) : nil
        return (path, claudeConfigDir.flatMap { $0.isEmpty ? nil : $0 })
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
