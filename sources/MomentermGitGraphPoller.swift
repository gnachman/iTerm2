//
//  MomentermGitGraphPoller.swift
//  iTerm2
//
//  Async wrapper around `git log --all` for the bottom Git Graph panel.
//  Caches results per cwd, debounces concurrent requests, and posts
//  notifications when a refresh completes so the graph view can redraw
//  without polling itself.
//

import Foundation

@objc final class MomentermGitGraphPoller: NSObject {

    @objc static let shared = MomentermGitGraphPoller()

    /// userInfo["cwd"] = String, userInfo["isGitRepo"] = Bool
    @objc static let didUpdateNotification = Notification.Name("MomentermGitGraphDidUpdate")

    private let queue = DispatchQueue(label: "com.momenterm.gitgraph-poller")
    private var commitsByCwd: [String: [MomentermGitCommit]] = [:]
    private var isGitRepoByCwd: [String: Bool] = [:]
    private var inFlight: Set<String> = []
    private let cacheLock = NSLock()

    private override init() { super.init() }

    // MARK: - Public

    @objc func commitsCount(forCwd cwd: String) -> Int {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return commitsByCwd[cwd]?.count ?? 0
    }

    func commits(forCwd cwd: String) -> [MomentermGitCommit] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return commitsByCwd[cwd] ?? []
    }

    @objc func isGitRepo(cwd: String) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return isGitRepoByCwd[cwd] ?? false
    }

    /// Kick off an async refresh for the given cwd. Skips if the same cwd
    /// is already being refreshed (de-dupe).
    @objc func refresh(cwd: String) {
        guard !cwd.isEmpty else { return }
        cacheLock.lock()
        if inFlight.contains(cwd) {
            cacheLock.unlock()
            return
        }
        inFlight.insert(cwd)
        cacheLock.unlock()

        queue.async { [weak self] in
            guard let self = self else { return }
            let (isRepo, commits) = Self.runGitLog(cwd: cwd)
            self.cacheLock.lock()
            self.isGitRepoByCwd[cwd] = isRepo
            self.commitsByCwd[cwd] = commits
            self.inFlight.remove(cwd)
            self.cacheLock.unlock()

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: MomentermGitGraphPoller.didUpdateNotification,
                    object: nil,
                    userInfo: ["cwd": cwd, "isGitRepo": isRepo])
            }
        }
    }

    // MARK: - Implementation

    private static let format = "%H|%P|%D|%an|%at|%s"
    private static let maxCommits = 200

    private static func runGitLog(cwd: String) -> (Bool, [MomentermGitCommit]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.arguments = [
            "log", "--all", "--topo-order",
            "--format=\(format)",
            "-\(maxCommits)"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return (false, [])
        }
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            // Not a git repo, no commits, or git not on PATH.
            return (false, [])
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        let commits = MomentermGitLogParser.parse(text)
        return (true, commits)
    }
}
