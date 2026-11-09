//
//  iTermSessionDirectoryTracker.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/24/26.
//

import Foundation

/// Protocol for objects that can provide an SSH identity.
/// Conductor conforms to this protocol.
@objc(iTermSSHIdentityProvider)
@MainActor
protocol SSHIdentityProvider: AnyObject {
    var sshIdentity: SSHIdentity { get }
}

/// Protocol for the directory tracker's delegate.
@objc(iTermSessionDirectoryTrackerDelegate)
protocol iTermSessionDirectoryTrackerDelegate: AnyObject {
    // MARK: - Notifications

    /// Called when the directory changes (update proxy icon, etc).
    func directoryTrackerDidChangeDirectory(_ tracker: iTermSessionDirectoryTracker)

    /// Called when shell integration updates the current directory.
    func directoryTrackerDidUpdateCurrentDirectory(_ tracker: iTermSessionDirectoryTracker, path: String?)

    /// Records path usage in shell history.
    func directoryTracker(_ tracker: iTermSessionDirectoryTracker,
                          recordUsageOfPath path: String,
                          onHost host: (any VT100RemoteHostReading)?,
                          isChange: Bool)

    /// Called when the poller finds a valid working directory that should create a mark.
    func directoryTracker(_ tracker: iTermSessionDirectoryTracker,
                          createMarkForPolledDirectory directory: String)

    /// Called when the local directory changes (for updating local file checker).
    func directoryTracker(_ tracker: iTermSessionDirectoryTracker,
                          didChangeLocalDirectory directory: String?)

    // MARK: - Data Source

    /// Returns the process ID for the working directory poller.
    func directoryTrackerProcessID(_ tracker: iTermSessionDirectoryTracker) -> pid_t

    /// The terminal's foreground process group, or -1 if unknown. Polls read the shell the user
    /// is in, found from it.
    func directoryTrackerForegroundProcessGroup(_ tracker: iTermSessionDirectoryTracker) -> pid_t

    /// Returns the environment PWD variable.
    func directoryTrackerEnvironmentPWD(_ tracker: iTermSessionDirectoryTracker) -> String?

    /// Returns whether we're in soft alternate screen mode.
    func directoryTrackerIsInSoftAlternateScreenMode(_ tracker: iTermSessionDirectoryTracker) -> Bool

    /// Returns whether escape sequences are disabled.
    func directoryTrackerEscapeSequencesDisabled(_ tracker: iTermSessionDirectoryTracker) -> Bool

    /// Returns the working directory provider (PTYTask) for sync/async directory fetching.
    func directoryTrackerWorkingDirectoryProvider(_ tracker: iTermSessionDirectoryTracker) -> (any iTermWorkingDirectoryProvider)?

    /// Returns the SSH identity provider (e.g., Conductor) for SSH directory tracking.
    func directoryTrackerSSHIdentityProvider(_ tracker: iTermSessionDirectoryTracker) -> (any SSHIdentityProvider)?

    /// Resolves symlinks in a local directory without blocking the main thread, giving the path
    /// in the form a poll of a process's working directory would. The completion runs exactly
    /// once on the main queue, with nil if the directory couldn't be resolved for any reason.
    /// It may take a long time (e.g., on a network volume).
    func directoryTracker(_ tracker: iTermSessionDirectoryTracker,
                          resolveSymlinksInDirectory directory: String,
                          completion: @escaping (String?) -> Void)
}

/// Arrangement keys for serialization (must match existing PTYSession keys for compatibility).
private enum ArrangementKeys {
    static let lastDirectory = "Last Directory"
    static let lastLocalDirectory = "Last Local Directory"
    static let lastLocalDirectoryWasPushed = "Last Local Directory Was Pushed"
    static let lastDirectoryIsRemote = "Last Directory Is Remote"  // Deprecated key for backward compat
    static let directories = "Directories"
    static let hosts = "Hosts"
    static let workingDirectoryPollerDisabled = "Working Directory Poller Disabled"
    static let shouldExpectCurrentDirUpdates = "Should Expect Current Dir Updates"
    static let lastDirectorySSHIdentity = "Last Directory SSH Identity"  // Phase 2
}

/// Maximum number of directories and hosts to keep in history.
private let kMaxDirectories: Int = 100
private let kMaxHosts: Int = 100

/// Tracks working directory state for a PTYSession.
/// Extracts directory tracking logic from PTYSession for better organization and testability.
@objc(iTermSessionDirectoryTracker)
@MainActor
class iTermSessionDirectoryTracker: NSObject {
    // MARK: - Properties

    /// The variable scope for updating path and reading tmux pane.
    private let variablesScope: iTermVariableScope

    /// The last directory reported (may be local or remote).
    @objc private(set) var lastDirectory: String?

    /// The last local directory (for new tab initial directory).
    /// This must not update the path variable: it is also set from the local
    /// process's cwd while the session is ssh'ed somewhere, and the path must keep
    /// showing the remote directory. setLastDirectory(_:remote:pushed:) owns it.
    @objc private(set) var lastLocalDirectory: String? {
        didSet {
            delegate?.directoryTracker(self, didChangeLocalDirectory: lastLocalDirectory)
        }
    }

    /// Whether lastLocalDirectory came from shell integration (pushed) or polling (not pushed).
    @objc private(set) var lastLocalDirectoryWasPushed: Bool = false

    /// The local shell's directory, taken only from sources proven to be local: the pwd poller,
    /// or a push whose OSC 7 machineID token matched ours. Used when creating new local sessions
    /// to avoid using a remote path that was pushed via OSC 7 without a hostname (which looks
    /// local but isn't). Unlike lastLocalDirectory, an unverified push never sets it.
    @objc private(set) var verifiedLocalDirectory: String?

    /// Whether verifiedLocalDirectory came from a push verified as local. Such a push names the
    /// directory the way the user does, keeping their symlinks, while a poll gives the resolved
    /// path. A poll replaces it only once it's known to name a different directory.
    private var verifiedLocalDirectoryWasPushed = false

    /// verifiedLocalDirectory with symlinks resolved, once known, while it was pushed. Symlinks
    /// can change, so this is discarded whenever verifiedLocalDirectory changes.
    private var resolvedPushedDirectory: String?

    /// Incremented whenever resolvedPushedDirectory is discarded, so a resolution that finishes
    /// after its directory was replaced is ignored.
    private var resolutionGeneration = 0

    /// Whether a resolution of the pushed directory is outstanding. When none is and there's no
    /// result (it failed, or the service wasn't ready), the next push of the same directory
    /// tries again.
    private var isResolvingPushedDirectory = false

    /// Whether the latest strong push was a verified push of verifiedLocalDirectory. A strong push
    /// of unknown locality since then (an unverified report, or one with no directory) means the
    /// shell may have moved, so a poll may then replace the pushed directory before its
    /// resolution is known, unless it names the pushed directory.
    private var pushedDirectoryIsLatestPush = false

    /// Incremented on every strong push. Every poll records it when it begins. A poll that began
    /// before the latest strong push may report where the shell was before it, so its result
    /// must not override what the push established: the pushed directory, or the result of the
    /// poll the push started.
    private var pushGeneration = 0

    /// The last remote host at the time of setting the current directory.
    @objc private(set) var lastRemoteHost: (any VT100RemoteHostReading)?

    /// The SSH identity associated with lastDirectory (Phase 2 - bug fix).
    /// This tracks which SSH host the lastDirectory belongs to, so we only reuse
    /// directories appropriately when creating new sessions.
    @objc private(set) var lastDirectorySSHIdentity: SSHIdentity?

    /// Historical list of directories (max kMaxDirectories entries).
    @objc private(set) var directories: [String] = []

    /// Historical list of remote hosts (max kMaxHosts entries).
    @objc private(set) var hosts: [any VT100RemoteHostReading] = []

    /// Whether the working directory poller is disabled (shell integration is providing updates).
    @objc var workingDirectoryPollerDisabled: Bool = false

    /// Whether we should expect current directory updates from shell integration.
    @objc var shouldExpectCurrentDirUpdates: Bool = false

    /// The working directory poller for shells without integration.
    private var pwdPoller: iTermWorkingDirectoryPoller

    /// Delegate for notifications and data.
    @objc weak var delegate: (any iTermSessionDirectoryTrackerDelegate)?

    // MARK: - Initialization

    @objc
    init(variablesScope: iTermVariableScope) {
        self.variablesScope = variablesScope
        pwdPoller = iTermWorkingDirectoryPoller()
        super.init()
        pwdPoller.delegate = self
    }

    deinit {
        pwdPoller.delegate = nil
    }

    /// Restore state from a saved arrangement. Called after init when restoring a session.
    @objc
    func restoreFromArrangement(_ arrangement: [String: Any]) {
        lastDirectory = arrangement[ArrangementKeys.lastDirectory] as? String

        // Handle backward compatibility with deprecated "Last Directory Is Remote" key
        let isRemote = arrangement[ArrangementKeys.lastDirectoryIsRemote] as? Bool ?? false
        if !isRemote, let dir = lastDirectory {
            lastLocalDirectory = dir
        }

        if let localDir = arrangement[ArrangementKeys.lastLocalDirectory] as? String {
            lastLocalDirectory = localDir
            lastLocalDirectoryWasPushed = arrangement[ArrangementKeys.lastLocalDirectoryWasPushed] as? Bool ?? false
        }

        shouldExpectCurrentDirUpdates = arrangement[ArrangementKeys.shouldExpectCurrentDirUpdates] as? Bool ?? false
        workingDirectoryPollerDisabled = (arrangement[ArrangementKeys.workingDirectoryPollerDisabled] as? Bool ?? false) || shouldExpectCurrentDirUpdates

        if let savedDirectories = arrangement[ArrangementKeys.directories] as? [String] {
            directories.append(contentsOf: savedDirectories)
            trimDirectoriesIfNeeded()
        }

        if let savedHosts = arrangement[ArrangementKeys.hosts] as? [[String: Any]] {
            for hostDict in savedHosts {
                if let remoteHost = VT100RemoteHost(dictionary: hostDict) {
                    hosts.append(remoteHost)
                }
            }
            trimHostsIfNeeded()
        }

        // Restore SSH identity (Phase 2)
        if let sshIdentityDict = arrangement[ArrangementKeys.lastDirectorySSHIdentity] as? [String: Any] {
            lastDirectorySSHIdentity = SSHIdentity(userDefaultsObject: sshIdentityDict)
        }
    }

    // MARK: - Arrangement Serialization

    /// Encode arrangement to the encoder.
    @objc
    func encodeArrangement(with encoder: any iTermEncoderAdapter) {
        RLog("\(d(delegate)): Saving arrangement with lastDirectory of \(d(lastDirectory))");
        if let dir = lastDirectory {
            encoder.setObject(dir, forKey: ArrangementKeys.lastDirectory)
        }

        if let localDir = lastLocalDirectory {
            encoder.setObject(localDir, forKey: ArrangementKeys.lastLocalDirectory)
            encoder.setObject(NSNumber(value: lastLocalDirectoryWasPushed), forKey: ArrangementKeys.lastLocalDirectoryWasPushed)
        }

        encoder.setObject(NSNumber(value: shouldExpectCurrentDirUpdates), forKey: ArrangementKeys.shouldExpectCurrentDirUpdates)
        encoder.setObject(NSNumber(value: workingDirectoryPollerDisabled), forKey: ArrangementKeys.workingDirectoryPollerDisabled)
        encoder.setObject(directories as NSArray, forKey: ArrangementKeys.directories)

        // Serialize hosts as dictionaries
        let hostDicts = hosts.compactMap { $0.dictionaryValue() }
        encoder.setObject(hostDicts as NSArray, forKey: ArrangementKeys.hosts)

        // Serialize SSH identity (Phase 2)
        if let sshIdentity = lastDirectorySSHIdentity {
            encoder.setObject(sshIdentity.toUserDefaultsObject() as NSDictionary, forKey: ArrangementKeys.lastDirectorySSHIdentity)
        }
    }

    // MARK: - Directory Setting

    /// Set the last directory with remote and pushed flags.
    /// - Parameters:
    ///   - directory: The new directory path
    ///   - remote: Whether this is a remote directory (not on localhost)
    ///   - pushed: Whether this came from shell integration (true) or polling (false)
    @objc
    func setLastDirectory(_ directory: String?, remote: Bool, pushed: Bool) {
        DLog("\(d(delegate)): setLastDirectory:\(directory ?? "nil") remote:\(remote) pushed:\(pushed)")

        if pushed, let dir = directory {
            directories.append(dir)
            trimDirectoriesIfNeeded()
        }

        lastDirectory = directory

        if !remote {
            if pushed || !lastLocalDirectoryWasPushed {
                lastLocalDirectory = directory
                lastLocalDirectoryWasPushed = pushed
            }
        }

        // Track which SSH host this directory is from (Phase 2)
        if remote {
            lastDirectorySSHIdentity = delegate?.directoryTrackerSSHIdentityProvider(self)?.sshIdentity
        } else {
            lastDirectorySSHIdentity = nil
        }

        if let dir = directory {
            variablesScope.setValue(dir, forVariableNamed: iTermVariableKeySessionPath)
        }

        // Update the proxy icon
        delegate?.directoryTrackerDidChangeDirectory(self)
    }

    /// Update the last remote host. Called when restoring from arrangement.
    @objc(recordLastRemoteHost:)
    func recordLastRemoteHost(_ remoteHost: (any VT100RemoteHostReading)?) {
        if let host = remoteHost {
            hosts.append(host)
            trimHostsIfNeeded()
        }
        lastRemoteHost = remoteHost
    }

    // MARK: - Collection Trimming

    private func trimDirectoriesIfNeeded() {
        if directories.count > kMaxDirectories {
            directories.removeFirst(directories.count - kMaxDirectories)
        }
    }

    private func trimHostsIfNeeded() {
        if hosts.count > kMaxHosts {
            hosts.removeFirst(hosts.count - kMaxHosts)
        }
    }

    // MARK: - Async Directory Methods

    /// Get the initial directory for a new session based on the current directory.
    /// For SSH sessions, only uses lastDirectory if it's from the same SSH host.
    /// - Parameters:
    ///   - sshIdentity: The SSH identity of the new session being created (nil for local sessions)
    ///   - completion: Called with the directory to use, or nil
    @objc
    func asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory(
        sshIdentity: SSHIdentity?,
        completion: @escaping (String?) -> Void
    ) {
        // If the new session is SSH, we need special handling
        if let newSessionSSHIdentity = sshIdentity {
            // New session is SSH - only use lastDirectory if it's from the same SSH host
            if let currentSSHIdentity = lastDirectorySSHIdentity,
               currentSSHIdentity.isEqual(newSessionSSHIdentity),
               let dir = lastDirectory, !dir.isEmpty {
                // Same SSH host and we have a directory - use it
                completion(dir)
                return
            }
            // Either no SSH identity match, or no directory - don't pass anything to SSH session
            completion(nil)
            return
        }

        // New session is local - use local directory logic
        let envPwd = delegate?.directoryTrackerEnvironmentPWD(self)
        asyncCurrentLocalWorkingDirectory { [weak self] pwd in
            guard self != nil else {
                completion(envPwd)
                return
            }
            if let pwd = pwd {
                completion(pwd)
            } else {
                completion(envPwd)
            }
        }
    }

    /// Get the current local working directory asynchronously.
    /// Returns the verified local directory (the true local pwd) for use when creating new local sessions.
    @objc
    func asyncCurrentLocalWorkingDirectory(completion: @escaping (String?) -> Void) {
        DLog("\(d(delegate)): asyncCurrentLocalWorkingDirectory requested")
        if let localDir = verifiedLocalDirectory {
            DLog("\(d(delegate)): Using verified local directory \(localDir)")
            completion(localDir)
            return
        }
        DLog("\(d(delegate)): No verified local directory yet, polling")

        updateLocalDirectoryWithCompletion { [weak self] pwd in
            DLog("\(d(self?.delegate)): updateLocalDirectory finished with \(pwd ?? "nil")")
            // A poll that began before a push isn't recorded, but until the push's own poll
            // finishes it's still the best guess. It's the raw poll, never a pushed path that
            // might be remote.
            completion(self?.verifiedLocalDirectory ?? pwd)
        }
    }

    /// Get the current local working directory synchronously (SLOW - avoid calling).
    @objc
    var currentLocalWorkingDirectory: String? {
        DLog("\(d(delegate)): Warning! Slow currentLocalWorkingDirectory called")
        if let localDir = lastLocalDirectory {
            // If a shell integration-provided working directory is available, prefer to use it because
            // it has unresolved symlinks. The path provided by -getWorkingDirectory has expanded symlinks
            // and isn't what the user expects to see. This was raised in issue 3383. My first fix was
            // to expand symlinks on _lastDirectory and use it if it matches what the kernel reports.
            // That was a bad idea because expanding symlinks is slow on network file systems (Issue 4901).
            // Instead, we'll use _lastDirectory if we believe it's on localhost.
            // Furthermore, getWorkingDirectory is slow and blocking and it would be better never to call
            // it.
            DLog("\(d(delegate)): Using last directory from shell integration: \(localDir)")
            return localDir
        }
        DLog("\(d(delegate)): Last directory is nil, fetching from provider")
        if let provider = delegate?.directoryTrackerWorkingDirectoryProvider(self) {
            lastLocalDirectory = provider.getWorkingDirectory
            lastLocalDirectoryWasPushed = false
        }
        return lastLocalDirectory
    }

    // MARK: - Poller Control

    /// Trigger a working directory poll.
    @objc
    func poll() {
        pwdPoller.poll()
    }

    /// Poll for the local working directory and update lastLocalDirectory only.
    /// Does not affect lastDirectory, shell history, or path variable.
    /// Used when OSC 7/shell integration is providing directory updates but we still
    /// want to track the local directory for session restoration.
    @objc
    func pollLocalDirectoryOnly() {
        DLog("\(d(delegate)): pollLocalDirectoryOnly")
        updateLocalDirectoryWithCompletion { _ in }
    }

    /// Called when a line feed is received.
    @objc
    func didReceiveLineFeed() {
        pwdPoller.didReceiveLineFeed()
    }

    /// Called when the user presses a key.
    @objc
    func userDidPressKey() {
        pwdPoller.userDidPressKey()
    }

    /// Invalidate outstanding poller requests (when shell integration provides better data).
    @objc
    func invalidateOutstandingRequests() {
        pwdPoller.invalidateOutstandingRequests()
    }

    /// Add a one-time completion handler for the next poll result.
    @objc
    func addOneTimeCompletion(_ completion: @escaping @Sendable (String?) -> Void) {
        pwdPoller.addOneTimeCompletion(completion)
    }

    // MARK: - Tmux Support

    /// Replace the working directory poller with a tmux-aware one.
    @objc
    func switchToTmuxPoller(tmuxController: TmuxController) {
        RLog("\(d(delegate)): switchToTmuxPoller")
        guard let gateway = tmuxController.gateway else {
            RLog("\(d(delegate)): Missing gateway")
            return
        }

        let windowPane = (variablesScope.value(forVariableName: iTermVariableKeySessionTmuxWindowPane) as? NSNumber)?.int32Value ?? -1

        pwdPoller.delegate = nil
        pwdPoller = iTermWorkingDirectoryPoller(
            tmuxGateway: gateway,
            scope: variablesScope,
            windowPane: windowPane
        )
        pwdPoller.delegate = self
        pwdPoller.poll()
    }

    // MARK: - Screen Delegate Methods

    /// Called when shell integration logs a working directory on a line.
    /// - Parameter locality: How `directory` is known to be on this machine, if it is.
    @objc
    func screenLogWorkingDirectory(onAbsoluteLine absLine: Int64,
                                   remoteHost: (any VT100RemoteHostReading)?,
                                   withDirectory directory: String?,
                                   pushType: VT100ScreenWorkingDirectoryPushType,
                                   locality: VT100ScreenWorkingDirectoryLocality = .unverified,
                                   accepted: Bool) {
        DLog("\(d(delegate)): screenLogWorkingDirectory: \(directory ?? "nil") pushType:\(pushType.rawValue) locality:\(locality.rawValue) accepted:\(accepted)")

        let pushed = (pushType != .pull)

        if pushed && accepted {
            // If we're currently polling for a working directory, do not create a
            // mark for the result when the poll completes because this mark is
            // from a higher-quality data source.
            invalidateOutstandingRequests()
        }

        // Update shell integration DB.
        if pushed, let dir = directory {
            let isSame = (dir == lastDirectory) && remoteHost?.isEqual(toRemoteHost: lastRemoteHost) == true
            delegate?.directoryTracker(self,
                                       recordUsageOfPath: dir,
                                       onHost: remoteHost,
                                       isChange: !isSame)
        }

        if accepted {
            // This has been a big ugly hairball for a long time. Because of the
            // working directory poller I think it's safe to simplify it now. Before,
            // we'd track whether the update was trustworthy and likely to happen
            // again. These days, it should always be regular so that is not
            // interesting. Instead, we just want to make sure we know if the directory
            // is local or remote because we want to ignore local directories when we
            // know the user is ssh'ed somewhere.
            let directoryIsRemote = (pushType == .strongPush) &&
                                    remoteHost != nil &&
                                    remoteHost?.isLocalhost == false

            // Update lastDirectory, lastLocalDirectory (maybe), proxy icon, "path" variable.
            setLastDirectory(directory, remote: directoryIsRemote, pushed: pushed)
            if pushed {
                recordLastRemoteHost(remoteHost)
            }
            if pushType == .strongPush {
                updateVerifiedLocalDirectoryAfterPush(directory, locality: locality)
            }
        }
    }

    /// A strong push means the shell just reported its directory, typically from its prompt hook
    /// right after a `cd`, so verifiedLocalDirectory is now stale. New local sessions read it, so
    /// refresh it here rather than waiting for the poller.
    ///
    /// The pushed directory itself is used only when the report proved it came from this
    /// machine. Otherwise it may be a remote path that looks local (e.g., fish over plain ssh
    /// sends OSC 7 without a hostname; issue 12616), so poll the local shell instead. A poll
    /// reads the shell the user is in, even when it's nested or running ssh, so its result goes
    /// through the same rules as any other: a verified pushed directory is kept while the poll
    /// names it or what it resolves to.
    ///
    /// A push whose directory came from a poll (an empty CurrentDir report) changes nothing here:
    /// directoryChangeReportedWithoutDirectory acted on the report when the poll was requested,
    /// and the poll was recorded when it finished, subject to the staleness check.
    private func updateVerifiedLocalDirectoryAfterPush(_ directory: String?,
                                                       locality: VT100ScreenWorkingDirectoryLocality) {
        if locality == .localPoll {
            DLog("\(d(delegate)): Push of polled \(directory ?? "nil") was recorded when the poll finished")
            return
        }
        if locality == .verifiedReport, let directory, !directory.isEmpty {
            pushGeneration += 1
            if verifiedLocalDirectoryWasPushed && verifiedLocalDirectory == directory {
                pushedDirectoryIsLatestPush = true
                DLog("\(d(delegate)): Verified-local push of unchanged directory \(directory)")
                if resolvedPushedDirectory == nil && !isResolvingPushedDirectory {
                    DLog("\(d(delegate)): No resolution of \(directory) yet; trying again")
                    resolvePushedDirectory(directory)
                }
                return
            }
            DLog("\(d(delegate)): Verified-local push; verified local directory is now \(directory)")
            setVerifiedLocalDirectory(directory, pushed: true)
            pushedDirectoryIsLatestPush = true
            resolvePushedDirectory(directory)
            return
        }
        DLog("\(d(delegate)): Unverified push; polling local directory")
        noteStrongPushOfUnknownLocality()
        pollLocalDirectoryOnly()
    }

    /// The shell reported a directory change without saying where (e.g., an empty CurrentDir), and
    /// the caller is about to poll for it. That's a strong push whose locality is unknown, so act
    /// as for an unverified one. Call this before requesting the poll.
    @objc
    func directoryChangeReportedWithoutDirectory() {
        DLog("\(d(delegate)): Directory change reported without a directory")
        noteStrongPushOfUnknownLocality()
    }

    /// Polls that began earlier are stale, and the poll that follows may replace a pushed value
    /// whose resolution isn't known yet.
    private func noteStrongPushOfUnknownLocality() {
        pushGeneration += 1
        pushedDirectoryIsLatestPush = false
    }

    private func setVerifiedLocalDirectory(_ directory: String?, pushed: Bool) {
        if directory != verifiedLocalDirectory || pushed != verifiedLocalDirectoryWasPushed {
            resolvedPushedDirectory = nil
            resolutionGeneration += 1
            isResolvingPushedDirectory = false
        }
        verifiedLocalDirectory = directory
        verifiedLocalDirectoryWasPushed = pushed
    }

    /// Normally quick, but it touches the filesystem, so it may take a long time or never finish.
    /// Until it does, polls keep the pushed directory.
    private func resolvePushedDirectory(_ directory: String) {
        guard let delegate else {
            return
        }
        let generation = resolutionGeneration
        isResolvingPushedDirectory = true
        delegate.directoryTracker(self, resolveSymlinksInDirectory: directory) { [weak self] resolved in
            guard let self, generation == self.resolutionGeneration else {
                return
            }
            DLog("\(d(self.delegate)): Pushed directory \(directory) resolves to \(resolved ?? "nil")")
            self.isResolvingPushedDirectory = false
            self.resolvedPushedDirectory = resolved
        }
    }

    /// Called before the current directory changes via shell integration.
    /// PTYSession should call this, then do auto profile switching, then call screenDidChangeCurrentDirectory.
    @objc
    func screenWillChangeCurrentDirectory(to newPath: String?,
                                          remoteHost: (any VT100RemoteHostReading)?) {
        DLog("\(d(delegate)): screenWillChangeCurrentDirectory: \(newPath ?? "nil")")
        didUpdateCurrentDirectory(newPath)
    }

    /// Called after the current directory has changed via shell integration.
    /// This invalidates the poller and disables it.
    @objc
    func screenDidChangeCurrentDirectory() {
        DLog("\(d(delegate)): screenDidChangeCurrentDirectory")
        invalidateOutstandingRequests()
        workingDirectoryPollerDisabled = true
    }

    // MARK: - Private Helpers

    /// The completion gets what the poll found, whether or not it was recorded.
    private func updateLocalDirectoryWithCompletion(completion: @escaping (String?) -> Void) {
        DLog("\(d(delegate)): updateLocalDirectory")
        guard let provider = delegate?.directoryTrackerWorkingDirectoryProvider(self) else {
            completion(nil)
            return
        }

        let generation = pushGeneration
        provider.getWorkingDirectory { [weak self] pwd in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                self.didGetWorkingDirectory(pwd, stale: generation != self.pushGeneration)
                completion(pwd)
            }
        }
    }

    /// `stale` means the poll began before the latest strong push, so it may describe where the
    /// shell was before it. It never overrides what that push established, whether the pushed
    /// directory or the result of the poll an unverified push started.
    ///
    /// A current poll gives the resolved path. It replaces a verified push only if the shell has
    /// moved since: the poll names neither the pushed directory nor what it resolves to. Until
    /// the resolution is known, keep the push.
    private func recordPolledLocalDirectory(_ pwd: String?, stale: Bool) {
        guard let pwd else {
            return
        }
        if stale {
            DLog("\(d(delegate)): Ignoring poll from before the latest push: \(pwd)")
            return
        }
        if verifiedLocalDirectoryWasPushed, let pushed = verifiedLocalDirectory {
            if pwd == pushed {
                return
            }
            guard let resolved = resolvedPushedDirectory else {
                if pushedDirectoryIsLatestPush {
                    DLog("\(d(delegate)): Keeping pushed \(pushed) over polled \(pwd) while resolving it")
                    return
                }
                DLog("\(d(delegate)): Polled \(pwd) after a push of unknown locality, with \(pushed) unresolved; the shell may have moved")
                setVerifiedLocalDirectory(pwd, pushed: false)
                return
            }
            if pwd == resolved {
                DLog("\(d(delegate)): Keeping pushed \(pushed), which resolves to polled \(pwd)")
                return
            }
            DLog("\(d(delegate)): Polled \(pwd) is not pushed \(pushed) (\(resolved)); the shell moved")
        }
        setVerifiedLocalDirectory(pwd, pushed: false)
    }

    private func didGetWorkingDirectory(_ pwd: String?, stale: Bool) {
        // Don't call setLastDirectory(_:remote:pushed:) because we don't want to update the
        // path variable if the session is ssh'ed somewhere.
        DLog("\(d(delegate)): didGetWorkingDirectory finished with \(pwd ?? "nil") stale:\(stale)")

        recordPolledLocalDirectory(pwd, stale: stale)

        if lastLocalDirectoryWasPushed, lastLocalDirectory != nil {
            RLog("\(d(delegate)): Looks like there was a race because there is now a last local directory of \(d(lastLocalDirectory)). Keep it")
            return
        }

        lastLocalDirectory = pwd
        lastLocalDirectoryWasPushed = false
    }

    private func didUpdateCurrentDirectory(_ newPath: String?) {
        shouldExpectCurrentDirUpdates = true
        delegate?.directoryTrackerDidUpdateCurrentDirectory(self, path: newPath)
    }

    private func useLocalDirectoryPollerResult() -> Bool {
        if workingDirectoryPollerDisabled {
            DLog("\(d(delegate)): Working directory poller disabled")
            return false
        }

        let escapeSequencesDisabled = delegate?.directoryTrackerEscapeSequencesDisabled(self) ?? false
        if shouldExpectCurrentDirUpdates && !escapeSequencesDisabled {
            DLog("\(d(delegate)): Should not poll for working directory: shell integration used")
            return false
        }

        if delegate?.directoryTrackerIsInSoftAlternateScreenMode(self) == true {
            DLog("\(d(delegate)): Should not poll for working directory: soft alternate screen mode")
            return false
        }

        DLog("\(d(delegate)): Should poll for working directory.")
        return true
    }
}

// MARK: - iTermWorkingDirectoryPollerDelegate

extension iTermSessionDirectoryTracker: iTermWorkingDirectoryPollerDelegate {
    @objc nonisolated
    func workingDirectoryPollerShouldPoll() -> Bool {
        return true
    }

    @objc nonisolated
    func workingDirectoryPollerProcessID() -> pid_t {
        return MainActor.assumeIsolated {
            delegate?.directoryTrackerProcessID(self) ?? -1
        }
    }

    @objc nonisolated
    func workingDirectoryPollerForegroundProcessGroup() -> pid_t {
        return MainActor.assumeIsolated {
            delegate?.directoryTrackerForegroundProcessGroup(self) ?? -1
        }
    }

    @objc nonisolated
    func workingDirectoryPollerRequestStamp() -> Int {
        return MainActor.assumeIsolated {
            pushGeneration
        }
    }

    @objc nonisolated
    func workingDirectoryPollerDidFindWorkingDirectory(_ pwd: String?,
                                                       invalidated: Bool,
                                                       requestStamp: Int) {
        MainActor.assumeIsolated {
            handlePollerResult(pwd, invalidated: invalidated, requestStamp: requestStamp)
        }
    }

    private func handlePollerResult(_ pwd: String?, invalidated: Bool, requestStamp: Int) {
        DLog("\(d(delegate)): workingDirectoryPollerDidFindWorkingDirectory:\(pwd ?? "nil") invalidated:\(invalidated) requestStamp:\(requestStamp)")

        // Track the verified local directory regardless of pushed state or invalidation. It is
        // used when creating new local sessions to ensure we use the true local directory, not a
        // remote path that was pushed via OSC 7 without a hostname.
        // Not `invalidated`: weak pushes invalidate too, but establish nothing to protect.
        recordPolledLocalDirectory(pwd, stale: requestStamp != pushGeneration)

        if invalidated && lastLocalDirectoryWasPushed && lastLocalDirectory != nil {
            DLog("\(d(delegate)): Ignore local directory poller's invalidated result when we have a pushed last local directory")
            return
        }

        if invalidated || !useLocalDirectoryPollerResult() {
            DLog("\(d(delegate)): Not creating a mark. invalidated=\(invalidated)")
            if lastLocalDirectory != nil && lastLocalDirectoryWasPushed {
                DLog("\(d(delegate)): Last local directory was pushed, not changing it.")
                return
            }
            DLog("\(d(delegate)): Since last local directory was not pushed, update it.")
            // This is definitely a local directory. It may have been invalidated because we got a push
            // for a remote directory, but it's still useful to know the local directory for the purposes
            // of session restoration.
            lastLocalDirectory = pwd
            lastLocalDirectoryWasPushed = false
            // Do not call setLastDirectory:remote:pushed: because there's no sense updating the path
            // variable for an invalidated update when we might have a better remote working directory.
            //
            // Update the proxy icon since it only cares about the local directory.
            delegate?.directoryTrackerDidChangeDirectory(self)
            return
        }

        guard let pwd = pwd else {
            DLog("\(d(delegate)): nil result. Don't create a mark")
            return
        }

        // Notify delegate to create a mark on the screen.
        // PTYSession handles the actual screen mutation.
        DLog("\(d(delegate)): Valid polled directory: \(pwd) - notifying delegate to create mark")
        delegate?.directoryTracker(self, createMarkForPolledDirectory: pwd)
    }
}
