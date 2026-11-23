//
//  ClaudeCodeBrowserNavigation.swift
//  iTerm2
//
//  Sets up the Claude Code workgroup so Claude can show the page it is
//  working on (an issue, a pull request) in a browser peer, and offers that
//  once to people who installed the integration before it existed.
//
//  iTerm2 never reads the user's skills or CLAUDE.md. It shows the
//  instructions to add and, if asked, appends them to CLAUDE.md.
//
//  Claude may run on this Mac or on a host reached through SSH Integration
//  (directly or in a tmux pane whose gateway is). Its settings are changed
//  where it runs, through the connection as the remote hook install does.
//

import Foundation

enum ClaudeCodeBrowserNavigation {
    enum SetupError: LocalizedError {
        case noWorkgroup
        case noBrowserProfile
        /// Not valid JSON.
        case settingsUnreadable(path: String)
        /// There, but couldn't be read.
        case read(path: String, underlying: Error)
        /// Its permissions or permissions.allow isn't what Claude Code
        /// expects, so adding to it would lose what's there.
        case permissionsMalformed(path: String)
        case write(path: String, underlying: Error)
        /// How many running workgroups couldn't be restarted.
        case restartFailed(count: Int)
        /// Something on a remote host, described in full.
        case remote(String)

        var errorDescription: String? {
            switch self {
            case .noWorkgroup:
                return String(localized: "ClaudeCodeBrowserNavigation.NoWorkgroup",
                              defaultValue: "The Claude Code workgroup isn’t installed.",
                              comment: "Error when adding a browser to the Claude Code workgroup but that workgroup does not exist")
            case .noBrowserProfile:
                return String(localized: "ClaudeCodeBrowserNavigation.NoBrowserProfile",
                              defaultValue: "iTerm2 couldn’t create a browser profile.",
                              comment: "Error when a browser profile could not be found or created")
            case .settingsUnreadable(let path):
                return String.localizedStringWithFormat(
                    String(localized: "ClaudeCodeBrowserNavigation.SettingsUnreadable",
                           defaultValue: "%@ couldn’t be parsed as JSON. Fix it in a text editor and try again.",
                           comment: "Error when Claude Code’s settings file is not valid JSON. %@ is the file’s path."),
                    path)
            case .read(let path, let underlying):
                return String.localizedStringWithFormat(
                    String(localized: "ClaudeCodeBrowserNavigation.ReadFailed",
                           defaultValue: "Couldn’t read %1$@: %2$@",
                           comment: "Error when reading a file fails. %1$@ is the file’s path; %2$@ describes the failure."),
                    path,
                    underlying.localizedDescription)
            case .permissionsMalformed(let path):
                return String.localizedStringWithFormat(
                    String(localized: "ClaudeCodeBrowserNavigation.PermissionsMalformed",
                           defaultValue: "In %@, “permissions” isn’t an object or its “allow” isn’t a list, so iTerm2 left the file unchanged. Fix it in a text editor and try again.",
                           comment: "Error when Claude Code’s settings file has a permissions value of the wrong type. %@ is the file’s path. “permissions” and “allow” are JSON keys and must not be translated."),
                    path)
            case .restartFailed(let count):
                return String(localized: "ClaudeCodeBrowserNavigation.RestartFailed",
                              defaultValue: "\(count) running Claude Code workgroups couldn’t be restarted. Enter them again from Shell > Workgroups.",
                              comment: "Error when running Claude Code workgroups could not be restarted to get a new browser session. The value is how many; plural.")
            case .write(let path, let underlying):
                return String.localizedStringWithFormat(
                    String(localized: "ClaudeCodeBrowserNavigation.WriteFailed",
                           defaultValue: "Couldn’t write %1$@: %2$@",
                           comment: "Error when writing a file fails. %1$@ is the file’s path; %2$@ describes the failure."),
                    path,
                    underlying.localizedDescription)
            case .remote(let message):
                return message
            }
        }
    }

    // MARK: - Browser peer

    static var workgroup: iTermWorkgroup? {
        return iTermWorkgroupModel.instance.workgroup(uniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.workgroup)
    }

    /// The Claude Code workgroup's browser member, if it has one.
    static var target: WorkgroupBrowserNavigation.Target? {
        return workgroup.flatMap { WorkgroupBrowserNavigation.targets(in: $0).first }
    }

    /// Adds a browser peer to the Claude Code workgroup unless it has one.
    @discardableResult
    static func addBrowserPeer() throws -> WorkgroupBrowserNavigation.Target {
        if let target {
            return target
        }
        guard let workgroup else {
            throw SetupError.noWorkgroup
        }
        guard let profileGUID = WorkgroupBrowserNavigation.browserProfileGUID() else {
            throw SetupError.noBrowserProfile
        }
        guard let updated = WorkgroupBrowserNavigation.addingBrowserPeer(to: workgroup,
                                                                         profileGUID: profileGUID),
              let target = WorkgroupBrowserNavigation.targets(in: updated).first else {
            throw SetupError.noWorkgroup
        }
        iTermWorkgroupModel.instance.replace(uniqueIdentifier: workgroup.uniqueIdentifier, with: updated)
        RLog("ClaudeCodeBrowserNavigation: added browser peer \(target.peerName) to the Claude Code workgroup")
        return target
    }

    /// Running Claude Code workgroups without the browser: entered before it
    /// was added, or every one if it hasn't been added yet. Not ones in tmux
    /// Integration, which a restart leaves alone.
    static var runningWorkgroupsMissingBrowser: [iTermWorkgroupInstance] {
        let peerName = target?.peerName
        return iTermWorkgroupController.instance
            .runningInstances(ofWorkgroup: ClaudeCodeWorkgroupTemplate.ID.workgroup)
            .filter { instance in
                // The configuration the instance was entered with, not its live
                // sessions: a member that is still starting counts as present.
                guard instance.tmuxBinding == nil else {
                    return false
                }
                guard let peerName else {
                    return true
                }
                return !instance.workgroup.sessions.contains { $0.displayName.caseInsensitiveCompare(peerName) == .orderedSame }
            }
    }

    /// Restarts the running workgroups that don't have the browser. Others,
    /// such as one entered after it was added, keep their members.
    /// `completion` gets how many of them couldn't be restarted.
    static func restartRunningWorkgroupsMissingBrowser(completion: @escaping (Int) -> Void) {
        iTermWorkgroupController.instance.restart(instances: runningWorkgroupsMissingBrowser,
                                                  completion: completion)
    }

    // MARK: - Where Claude Code keeps its settings

    /// Where the Claude that will follow the instructions keeps its settings,
    /// found as the hook install finds it. For a session reached through SSH
    /// Integration, the host's CLAUDE_CONFIG_DIR, looked up there, unless the
    /// host is this Mac. On this Mac, the agent's own CLAUDE_CONFIG_DIR when it
    /// runs in the session, else the directory recorded when the hook was
    /// installed (see ClaudeCodeOnboarding.localConfigDirectory). With neither
    /// a session nor a conductor, this Mac. `conductor` is the session's, if
    /// the caller has no session but knows that. Completion is on the main
    /// thread.
    @MainActor
    static func resolveLocation(session: PTYSession?,
                                conductor: Conductor? = nil,
                                completion: @escaping (Result<ClaudeCodeConfigLocation, SetupError>) -> Void) {
        func local() {
            ClaudeCodeOnboarding.localConfigDirectory(for: session) { directory in
                DLog("ClaudeCodeBrowserNavigation: using \(directory.path) on this Mac")
                completion(.success(.local(directory)))
            }
        }
        // As in the installer: the innermost conductor, and for a tmux pane its gateway's.
        guard let conductor = conductor ?? session?.hostConductor.flatMap({ $0.framing ? $0 : nil }) else {
            local()
            return
        }
        let host = conductor.sshIdentity.stringIdentifier
        guard conductor.framing, let home = conductor.homeDirectory, !home.isEmpty else {
            completion(.failure(.remote(disconnectedMessage(host: host))))
            return
        }
        Task { @MainActor in
            switch await ClaudeCodeRemoteHooks.hostIdentity(files: ConductorClaudeCodeRemoteFiles(conductor: conductor)) {
            case .thisMac:
                // ssh back to this Mac: Claude reads this Mac's settings.
                local()
            case .unknown, .noAnswer:
                completion(.failure(.remote(remoteFailureMessage(.identityUnknown, host: host, directory: "") ?? "")))
            case .elsewhere:
                ClaudeCodeOnboarding.remoteConfigDirectory(conductor: conductor) { directory in
                    guard let directory else {
                        completion(.failure(.remote(String(
                            localized: "ClaudeCodeBrowserNavigation.RemoteConfigUnknown",
                            defaultValue: "iTerm2 couldn’t read CLAUDE_CONFIG_DIR from your login shell on \(host), so it doesn’t know where Claude Code keeps its settings there.",
                            comment: "Error when browser setup could not find Claude Code’s settings directory on a remote host. The value is the host."))))
                        return
                    }
                    DLog("ClaudeCodeBrowserNavigation: using \(directory) on \(host)")
                    completion(.success(.remote(.init(conductor: conductor,
                                                      host: host,
                                                      home: home,
                                                      directory: directory))))
                }
            }
        }
    }

    private static func disconnectedMessage(host: String) -> String {
        return String(localized: "ClaudeCodeBrowserNavigation.RemoteDisconnected",
                      defaultValue: "The connection to \(host) has ended. Reconnect and try again.",
                      comment: "Error when browser setup needs a remote host whose connection has ended. The value is the host.")
    }

    /// What to say when changing settings on a remote host failed, or nil if
    /// it didn't.
    private static func remoteFailureMessage(_ result: ClaudeCodeRemoteHooks.InstallResult,
                                             host: String,
                                             directory: String) -> String? {
        switch result {
        case .thisMac:
            return String(localized: "ClaudeCodeBrowserNavigation.RemoteIsThisMac",
                          defaultValue: "\(host) turned out to be this Mac. Open this setup again to change Claude Code’s settings here instead.",
                          comment: "Error when browser setup tried to change settings on a remote host that is really this Mac. The value is the host.")
        case .it2Missing:
            return String(localized: "ClaudeCodeBrowserNavigation.RemoteIt2Missing",
                          defaultValue: "SSH Integration couldn’t set up the it2 command on \(host), so Claude would have nothing to run. This happens when the login shell there is not one SSH Integration supports: zsh, bash, fish, or xonsh.",
                          comment: "Error when a remote host lacks the it2 command that SSH Integration uploads. The value is the host.")
        case .editRefused:
            let path = (directory as NSString).appendingPathComponent("settings.json")
            return String(localized: "ClaudeCodeBrowserNavigation.RemotePermissionsMalformed",
                          defaultValue: "In \(path) on \(host), “permissions” isn’t an object or its “allow” isn’t a list, so iTerm2 left the file unchanged. Fix it and try again.",
                          comment: "Error when Claude Code’s settings file on a remote host has a permissions value of the wrong type. The values are the file’s path and the host. “permissions” and “allow” are JSON keys and must not be translated.")
        case .installed, .identityUnknown, .unreadable, .malformed, .writeFailed:
            return ClaudeCodeOnboarding.remoteInstallFailureMessage(result, host: host, configDirectory: directory)
        }
    }

    /// Opens the setup checklist for the Claude that runs in `session`, or on
    /// `conductor`'s host, once it's known where that Claude keeps its
    /// settings. If that can't be found out, says why and reports setup
    /// incomplete.
    @MainActor
    static func showSetup(near parent: NSWindow?,
                          session: PTYSession?,
                          conductor: Conductor? = nil,
                          onClose: ((Bool) -> Void)? = nil) {
        var session = session
        if session == nil && conductor == nil {
            guard let choice = chooseLeader(near: parent) else {
                onClose?(false)
                return
            }
            session = choice.leader
        }
        resolveLocation(session: session, conductor: conductor) { result in
            switch result {
            case .success(let location):
                presentSetup?(parent, location, onClose)
            case .failure(let error):
                showError(error, window: parent)
                onClose?(false)
            }
        }
    }

    private struct LeaderChoice {
        /// Nil when no Claude Code workgroup runs.
        var leader: PTYSession?
    }

    /// The host a leader's Claude runs on, as setup will find it: nil for
    /// this Mac, else the SSH Integration connection's host.
    @MainActor
    private static func place(of leader: PTYSession) -> String? {
        return leader.hostConductor.flatMap { $0.framing ? $0.sshIdentity.stringIdentifier : nil }
    }

    /// Which Claude Code leader stands in for a session when setup opens
    /// without one (from Settings or a workgroup's help): the one whose
    /// workgroup has the key window's session, else the only place they run.
    /// When they run on more than one computer, the user picks, since the
    /// allow rule and instructions go to that computer. Nil if the user
    /// cancels.
    @MainActor
    private static func chooseLeader(near window: NSWindow?) -> LeaderChoice? {
        let instances = iTermWorkgroupController.instance
            .runningInstances(ofWorkgroup: ClaudeCodeWorkgroupTemplate.ID.workgroup)
        if let current = iTermController.sharedInstance()?.currentTerminal?.currentSession(),
           let instance = current.workgroupInstance,
           instances.contains(where: { $0 === instance }),
           let leader = instance.mainSession {
            DLog("ClaudeCodeBrowserNavigation: using the key window's workgroup leader \(leader.guid)")
            return LeaderChoice(leader: leader)
        }
        // This Mac first, then hosts by name, so the order doesn't depend on
        // the registry's.
        var leadersByPlace = [String: PTYSession]()
        let thisMac = ""
        for instance in instances {
            guard let leader = instance.mainSession else {
                continue
            }
            let key = place(of: leader) ?? thisMac
            if leadersByPlace[key] == nil {
                leadersByPlace[key] = leader
            }
        }
        let places = leadersByPlace.keys.sorted()
        guard places.count > 1 else {
            return LeaderChoice(leader: places.first.flatMap { leadersByPlace[$0] })
        }
        let shown = Array(places.prefix(5))
        if shown.count < places.count {
            RLog("ClaudeCodeBrowserNavigation: Claude Code workgroups run in \(places.count) places; offering the first \(shown.count)")
        }
        let titles = shown.map { place in
            place == thisMac ? String(localized: "ClaudeCodeBrowserNavigation.ChooseThisMac",
                                      defaultValue: "This Mac",
                                      comment: "Button choosing the Claude Code that runs on this Mac, rather than on a remote host") : place
        }
        let warning = iTermWarning()
        warning.heading = String(localized: "ClaudeCodeBrowserNavigation.ChooseComputerHeading",
                                 defaultValue: "Choose a Computer",
                                 comment: "Heading of a dialog asking which computer’s Claude Code to set up")
        warning.title = String(localized: "ClaudeCodeBrowserNavigation.ChooseComputer",
                               defaultValue: "Claude Code workgroups are running on more than one computer. Set up Claude on which one?",
                               comment: "Asks which computer’s Claude Code to set up for showing pages, when Claude Code workgroups run on this Mac and remote hosts. The buttons are “This Mac” and host names.")
        warning.actionLabels = titles + [iTermLocalizedCancel()]
        warning.warningType = .kiTermWarningTypePersistent
        // Each opens the setup sheet, which is only usable at the Mac.
        warning.notOfferedRemotelyLabels = titles
        warning.window = window
        let selection = warning.runModal()
        let index = selection.rawValue - iTermWarningSelection.kiTermWarningSelection0.rawValue
        guard index >= 0, index < shown.count else {
            return nil
        }
        return LeaderChoice(leader: leadersByPlace[shown[index]])
    }

    static func showError(_ error: Error, window: NSWindow?) {
        iTermWarning.show(withTitle: error.localizedDescription,
                          actions: [iTermLocalizedOK()],
                          accessory: nil,
                          identifier: nil,
                          silenceable: .kiTermWarningTypePersistent,
                          heading: String(localized: "WorkgroupBrowserNavigation.ErrorHeading",
                                          defaultValue: "Setup Failed",
                                          comment: "Heading of an error shown when a browser setup step fails"),
                          window: window)
    }

    // MARK: - it2

    /// How Claude should run it2: the dot-dir symlink the hooks use, which
    /// iTerm2 points at its own bundled it2, written with ~ so the allow rule
    /// matches what Claude types. Not a bare `it2`: iTerm2 appends its
    /// utilities to PATH, but shell startup files often rebuild PATH without
    /// them, and then `it2` finds a fallback that can't reach iTerm2.
    static var it2: String {
        return it2(path: ClaudeCodeOnboarding.it2SymlinkPath)
    }

    /// How Claude on a host reached through SSH Integration runs it2: the
    /// wrapper SSH Integration keeps there, which reaches this iTerm2 over the
    /// connection. Written with ~ so it needs no quoting and the allow rule
    /// matches what Claude types.
    static let remoteIt2 = "~/.iterm2/bin/it2"

    /// Makes the it2 that `location`'s commands name point at this build, as
    /// installing the hook does. On a remote host SSH Integration keeps it.
    static func prepareIt2(for location: ClaudeCodeConfigLocation) {
        if case .local = location {
            ClaudeCodeOnboarding.refreshIt2Symlink()
        }
    }

    static func it2(path: String?) -> String {
        guard let path else {
            return "it2"
        }
        let abbreviated = (path as NSString).abbreviatingWithTildeInPath
        if abbreviated.hasPrefix("~/") {
            let components = abbreviated.dropFirst(2).split(separator: "/", omittingEmptySubsequences: false)
            if components.allSatisfy({ WorkgroupBrowserNavigation.shellQuoted(String($0)) == String($0) }) {
                return abbreviated
            }
        }
        return WorkgroupBrowserNavigation.shellQuoted(path)
    }

    // MARK: - Allow rule

    @MainActor
    static func allowRuleInstalled(for target: WorkgroupBrowserNavigation.Target,
                                   in location: ClaudeCodeConfigLocation) async -> Bool {
        let rule = WorkgroupBrowserNavigation.claudeAllowRule(for: target, it2: location.it2)
        let settings: [String: Any]?
        switch location {
        case .local:
            settings = ClaudeCodeOnboarding.loadSettings(at: URL(fileURLWithPath: location.settingsPath))
        case .remote(let remote):
            guard let conductor = remote.conductor,
                  case .contents(let data) = await ConductorClaudeCodeRemoteFiles(conductor: conductor).read(location.settingsPath) else {
                return false
            }
            settings = ClaudeCodeHookSettings.settingsObjectIfValid(from: data)
        }
        return settings.map { allowRules(in: $0).contains(rule) } ?? false
    }

    /// The string entries of permissions.allow. Others are skipped rather than
    /// hiding the rest, as adding(allowRule:to:) keeps them.
    static func allowRules(in settings: [String: Any]) -> [String] {
        let allow = (settings["permissions"] as? [String: Any])?["allow"] as? [Any]
        return allow?.compactMap { $0 as? String } ?? []
    }

    /// `settings` with `rule` added to permissions.allow, keeping everything
    /// else. nil if permissions or permissions.allow is there but of the
    /// wrong type, since replacing it would lose the user's entries.
    static func adding(allowRule rule: String, to settings: [String: Any]) -> [String: Any]? {
        var result = settings
        let existingPermissions = settings["permissions"]
        guard existingPermissions == nil || existingPermissions is [String: Any] else {
            return nil
        }
        var permissions = (existingPermissions as? [String: Any]) ?? [:]
        let existingAllow = permissions["allow"]
        guard existingAllow == nil || existingAllow is [Any] else {
            return nil
        }
        var allow = (existingAllow as? [Any]) ?? []
        if !allow.contains(where: { ($0 as? String) == rule }) {
            allow.append(rule)
        }
        permissions["allow"] = allow
        result["permissions"] = permissions
        return result
    }

    @MainActor
    static func installAllowRule(for target: WorkgroupBrowserNavigation.Target,
                                 in location: ClaudeCodeConfigLocation) async throws {
        prepareIt2(for: location)
        let rule = WorkgroupBrowserNavigation.claudeAllowRule(for: target, it2: location.it2)
        switch location {
        case .local:
            try installLocalAllowRule(rule, settingsURL: URL(fileURLWithPath: location.settingsPath))
        case .remote(let remote):
            guard let conductor = remote.conductor, conductor.framing else {
                throw SetupError.remote(disconnectedMessage(host: remote.host))
            }
            // The same checks and care as the remote hook install: not this
            // Mac, the wrapper the rule names is there, and a file that can't
            // be parsed is left alone.
            let result = await ClaudeCodeRemoteHooks.editSettings(
                files: ConductorClaudeCodeRemoteFiles(conductor: conductor),
                settingsPath: location.settingsPath,
                home: remote.home,
                purpose: "browser allow rule") { adding(allowRule: rule, to: $0) }
            if let message = remoteFailureMessage(result, host: remote.host, directory: remote.directory) {
                throw SetupError.remote(message)
            }
            RLog("ClaudeCodeBrowserNavigation: added allow rule on the remote host")
        }
    }

    private static func installLocalAllowRule(_ rule: String, settingsURL url: URL) throws {
        let settings: [String: Any]
        let data: Data?
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            data = nil
        } catch {
            throw SetupError.read(path: url.path, underlying: error)
        }
        if let data {
            // A blank file is empty, as for the hook install.
            guard let existing = ClaudeCodeHookSettings.settingsObjectIfValid(from: data) else {
                throw SetupError.settingsUnreadable(path: url.path)
            }
            settings = existing
        } else {
            settings = [:]
        }
        guard let updated = adding(allowRule: rule, to: settings) else {
            throw SetupError.permissionsMalformed(path: url.path)
        }
        do {
            let data = try ClaudeCodeHookSettings.serialized(updated)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try ClaudeCodeOnboarding.writeSettings(data, to: url)
        } catch {
            throw SetupError.write(path: url.path, underlying: error)
        }
        RLog("ClaudeCodeBrowserNavigation: added allow rule to \(url.path)")
    }

    // MARK: - Instructions

    // CLAUDE.md path on this Mac to the generated instructions last appended
    // to it. iTerm2 doesn't read CLAUDE.md, so this is how it knows not to
    // append them twice. Holds paths, so tools/sanitize_iterm2_plist.py
    // removes it. For a remote host it's kept in memory until iTerm2 quits,
    // keyed by host so reconnecting doesn't forget it, since iTerm2 writes
    // nothing about remote hosts to disk.
    static let appendedInstructionsKey = "NoSyncClaudeCodeBrowserInstructionsAppended"
    private static var remoteAppendedInstructions = [RemoteFile: String]()

    private struct RemoteFile: Hashable {
        var host: String
        var path: String
    }

    /// Whether `generated` instructions were appended to CLAUDE.md in
    /// `location`.
    static func instructionsAppended(_ generated: String,
                                     in location: ClaudeCodeConfigLocation,
                                     defaults: UserDefaults = iTermUserDefaults.userDefaults()) -> Bool {
        switch location {
        case .local:
            let appended = defaults.dictionary(forKey: appendedInstructionsKey) as? [String: String]
            return appended?[location.claudeMDPath] == generated
        case .remote(let remote):
            return remoteAppendedInstructions[RemoteFile(host: remote.host, path: location.claudeMDPath)] == generated
        }
    }

    static func noteInstructionsAppended(_ generated: String,
                                         in location: ClaudeCodeConfigLocation,
                                         defaults: UserDefaults = iTermUserDefaults.userDefaults()) {
        switch location {
        case .local:
            var appended = (defaults.dictionary(forKey: appendedInstructionsKey) as? [String: String]) ?? [:]
            appended[location.claudeMDPath] = generated
            defaults.set(appended, forKey: appendedInstructionsKey)
        case .remote(let remote):
            remoteAppendedInstructions[RemoteFile(host: remote.host, path: location.claudeMDPath)] = generated
        }
    }

    /// Appends `text` to CLAUDE.md, creating it if needed. On a remote host, not
    /// again if the file already ends with it (see ClaudeCodeRemotePython.append).
    @MainActor
    static func appendToClaudeMD(_ text: String, in location: ClaudeCodeConfigLocation) async throws {
        let block = Data(("\n\n" + text + "\n").utf8)
        switch location {
        case .local:
            try appendLocally(block, to: URL(fileURLWithPath: location.claudeMDPath))
        case .remote(let remote):
            guard let conductor = remote.conductor, conductor.framing else {
                throw SetupError.remote(disconnectedMessage(host: remote.host))
            }
            let path = location.claudeMDPath
            guard await ConductorClaudeCodeRemoteFiles(conductor: conductor).append(path, block) else {
                let host = remote.host
                throw SetupError.remote(String(
                    localized: "ClaudeCodeBrowserNavigation.RemoteAppendFailed",
                    defaultValue: "iTerm2 couldn’t add to \(path) on \(host).",
                    comment: "Error when appending instructions to a file on a remote host failed. The values are a file path and the host."))
            }
            RLog("ClaudeCodeBrowserNavigation: appended instructions on the remote host")
        }
    }

    private static func appendLocally(_ block: Data, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: block)
        } catch {
            throw SetupError.write(path: url.path, underlying: error)
        }
        RLog("ClaudeCodeBrowserNavigation: appended instructions to \(url.path)")
    }

    // MARK: - Setup UI

    /// Opens the setup checklist near a window, for Claude Code's settings in
    /// a location, and reports when it closes whether setup is complete.
    /// Installed by the checklist
    /// (WorkgroupBrowserNavigationSheetController.installClaudeCodePresenter),
    /// so this code doesn't depend on it. See also showSetup, which finds the
    /// location first.
    static var presentSetup: ((NSWindow?, ClaudeCodeConfigLocation, ((Bool) -> Void)?) -> Void)?

    // MARK: - Offer for existing users

    private static var offeredThisLaunch = false
    private static var observer: NSObjectProtocol?

    /// Offers setup, once, the next time someone who installed the integration
    /// before browser navigation existed enters the Claude Code workgroup.
    static func observeWorkgroupEntryForOffer() {
        guard observer == nil, !iTermUserDefaults.claudeCodeBrowserNavigationOffered else {
            return
        }
        observer = NotificationCenter.default.addObserver(
            forName: iTermWorkgroupController.didEnterNotification,
            object: nil,
            queue: .main) { notification in
                guard let session = notification.object as? PTYSession,
                      notification.userInfo?[iTermWorkgroupController.workgroupIDKey] as? String == ClaudeCodeWorkgroupTemplate.ID.workgroup else {
                    return
                }
                offerIfNeeded(in: session)
            }
    }

    private static func offerIfNeeded(in session: PTYSession) {
        guard !offeredThisLaunch,
              !iTermUserDefaults.claudeCodeBrowserNavigationOffered else {
            return
        }
        guard target == nil else {
            // Already set up some other way; nothing to offer, ever.
            iTermUserDefaults.claudeCodeBrowserNavigationOffered = true
            return
        }
        offeredThisLaunch = true
        let title = String(localized: "ClaudeCodeBrowserNavigation.OfferTitle",
                           defaultValue: "The Claude Code workgroup can now show the issue or pull request Claude is working on in a browser, so you can read along without copying links.",
                           comment: "Announcement shown once to existing Claude Code integration users about a new feature")
        let actions = [
            String(localized: "ClaudeCodeBrowserNavigation.OfferSetUp",
                   defaultValue: "Set Up…",
                   comment: "Announcement button that opens browser navigation setup"),
            String(localized: "ClaudeCodeBrowserNavigation.OfferDontAsk",
                   defaultValue: "Don’t Ask Again",
                   comment: "Announcement button that dismisses an offer permanently"),
        ]
        guard let announcement = iTermAnnouncementViewController.announcement(
            withTitle: title,
            style: .kiTermAnnouncementViewStyleQuestion,
            withActions: actions,
            completion: { [weak session] choice in
                switch choice {
                case 0:
                    iTermUserDefaults.claudeCodeBrowserNavigationOffered = true
                    MainActor.assumeIsolated {
                        showSetup(near: session?.view?.window, session: session)
                    }
                case 1:
                    iTermUserDefaults.claudeCodeBrowserNavigationOffered = true
                default:
                    // Closed without choosing: offer again next launch.
                    break
                }
            }) else {
            return
        }
        session.queueAnnouncement(announcement, identifier: "ClaudeCodeBrowserNavigationOffer")
    }
}


/// Where the Claude that will follow the browser instructions keeps its
/// settings and CLAUDE.md: a directory on this Mac, or one on a host reached
/// through SSH Integration.
enum ClaudeCodeConfigLocation {
    case local(URL)
    case remote(Remote)

    struct Remote {
        weak var conductor: Conductor?
        /// For messages, such as user@example.com.
        var host: String
        var home: String
        /// CLAUDE_CONFIG_DIR there, as its login shell reports it.
        var directory: String
    }

    var isRemote: Bool {
        if case .remote = self {
            return true
        }
        return false
    }

    /// How Claude here runs it2.
    var it2: String {
        switch self {
        case .local:
            return ClaudeCodeBrowserNavigation.it2
        case .remote:
            return ClaudeCodeBrowserNavigation.remoteIt2
        }
    }

    var settingsPath: String {
        return path(of: "settings.json")
    }

    var claudeMDPath: String {
        return path(of: "CLAUDE.md")
    }

    /// The skills folder, which only a folder on this Mac can show.
    var localSkillsURL: URL? {
        if case .local(let directory) = self {
            return directory.appendingPathComponent("skills")
        }
        return nil
    }

    private func path(of name: String) -> String {
        switch self {
        case .local(let directory):
            return directory.appendingPathComponent(name).path
        case .remote(let remote):
            return ClaudeCodeRemoteConnectionFacts.joined(remote.directory, name)
        }
    }

    /// `path` as the user would write it, with ~ for the home directory where
    /// the file is.
    func displayPath(_ path: String) -> String {
        switch self {
        case .local:
            return (path as NSString).abbreviatingWithTildeInPath
        case .remote(let remote):
            var home = remote.home
            while home.count > 1 && home.hasSuffix("/") {
                home.removeLast()
            }
            if path.hasPrefix(home + "/") {
                return "~" + path.dropFirst(home.count)
            }
            return path
        }
    }
}
