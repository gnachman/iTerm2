//
//  ClaudeCodeOnboarding.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/7/26.
//

import AppKit

// Outcome buckets for uninstallHooks. Distinguishes "nothing on disk
// to remove" (success) from real failures, and within failures
// distinguishes filesystem read, JSON parse, and write — each gets a
// different user-facing error message.
@objc(iTermClaudeCodeUninstallHooksResult)
enum ClaudeCodeUninstallHooksResult: Int {
    case success
    case unreadable
    case malformed
    case writeFailed
}

// Outcome of merging our hooks into settings.json during Install. An existing
// file that can't be read or parsed is left alone (.unreadable / .malformed).
enum ClaudeCodeInstallHooksResult: Equatable {
    case success
    case unreadable
    case malformed
    case writeFailed(description: String)
}

@objc(iTermClaudeCodeOnboarding)
class ClaudeCodeOnboarding: NSObject {
    private static var instance: ClaudeCodeOnboarding?

    private enum Step: Int {
        case enablePythonAPI = 0
        case installHook = 1
        case showToolbelt = 2
        case installWorkgroup = 4
        case installTriggers = 5
        /// The hook on the host the session reaches through SSH Integration. Shown only for such a
        /// session.
        case installRemoteHook = 6

        var title: String {
            switch self {
            case .enablePythonAPI: return String(localized: "ClaudeCodeOnboarding.EnablePythonAPITitle", defaultValue: "Enable Python API", comment: "Title of the enable-Python-API onboarding step")
            case .installHook: return String(localized: "ClaudeCodeOnboarding.InstallHookTitle", defaultValue: "Install Hook", comment: "Title of the install-hook onboarding step")
            case .showToolbelt: return String(localized: "ClaudeCodeOnboarding.ShowToolbeltTitle", defaultValue: "Show Toolbelt", comment: "Title of the show-toolbelt onboarding step")
            case .installWorkgroup: return String(localized: "ClaudeCodeOnboarding.InstallWorkgroupTitle", defaultValue: "Install Workgroup", comment: "Title of the install-workgroup onboarding step")
            case .installTriggers: return String(localized: "ClaudeCodeOnboarding.AutoEnterWorkgroupTitle", defaultValue: "Auto-Enter Workgroup", comment: "Title of the auto-enter-workgroup onboarding step")
            case .installRemoteHook: return String(localized: "ClaudeCodeOnboarding.InstallRemoteHookTitle", defaultValue: "Install on Remote Host", comment: "Title of the onboarding step that installs the Claude Code hook on the host the session is connected to through SSH Integration")
            }
        }

        var buttonTitle: String {
            switch self {
            case .enablePythonAPI: return String(localized: "ClaudeCodeOnboarding.Enable", defaultValue: "Enable", comment: "Button that enables the Python API onboarding step")
            case .installHook: return String(localized: "ClaudeCodeOnboarding.Install", defaultValue: "Install", comment: "Button that installs the integration step")
            case .showToolbelt: return String(localized: "ClaudeCodeOnboarding.Show", defaultValue: "Show", comment: "Button that shows the toolbelt onboarding step")
            case .installWorkgroup: return String(localized: "ClaudeCodeOnboarding.Install", defaultValue: "Install", comment: "Button that installs the integration step")
            case .installTriggers: return String(localized: "ClaudeCodeOnboarding.Install", defaultValue: "Install", comment: "Button that installs the integration step")
            case .installRemoteHook: return String(localized: "ClaudeCodeOnboarding.Install", defaultValue: "Install", comment: "Button that installs the integration step")
            }
        }

        /// The remote step's text names its host, so it comes from remoteHookDescription instead.
        var description: String {
            switch self {
            case .enablePythonAPI:
                return String(localized: "ClaudeCodeOnboarding.EnablePythonAPIDescription", defaultValue: "The Claude Code integration relies on iTerm2\u{2019}s Python API to find sessions running Claude and track their status.\n\nThe Python API is currently disabled. Setup can\u{2019}t continue until it is enabled. Click Enable to turn it on.", comment: "Description of the enable-Python-API onboarding step")
            case .installHook:
                return String(localized: "ClaudeCodeOnboarding.InstallHookDescription", defaultValue: "Install a Claude Code hook that lets iTerm2 detect Claude\u{2019}s state (working, waiting, idle) and display it in the Session Status tool.\n\nThis adds a hook to your Claude Code settings that runs automatically as Claude works.", comment: "Description of the install-hook onboarding step")
            case .showToolbelt:
                return String(localized: "ClaudeCodeOnboarding.ShowToolbeltDescription", defaultValue: "Show the toolbelt and enable the Session Status tool. The toolbelt appears on the right side of your terminal window.\n\nYou can toggle the toolbelt from View > Toolbelt > Show Toolbelt, or with the shortcut \u{2318}\u{21E7}B.", comment: "Description of the show-toolbelt onboarding step")
            case .installWorkgroup:
                return String(localized: "ClaudeCodeOnboarding.InstallWorkgroupDescription", defaultValue: "Install the Claude Code workgroup, which groups your main Claude session with two peer sessions: a diff viewer and a code-review session. You can switch between them with one click.\n\nYou can customize this layout later in Settings > Arrangements > Workgroups.", comment: "Description of the install-workgroup onboarding step")
            case .installRemoteHook:
                return ""
            case .installTriggers:
                return String(localized: "ClaudeCodeOnboarding.InstallTriggersDescription", defaultValue: "Pick the terminal profiles where you run claude. iTerm2 will add triggers so the Claude Code workgroup is entered automatically when claude starts and exited when it stops.\n\nWithout this, you can still enter the workgroup manually via Shell > Workgroups > Claude Code.", comment: "Description of the install-triggers onboarding step")
            }
        }
    }

    private var panel: iTermFocusablePanel!
    private let activeSteps: [Step]
    private var currentStep: Step
    private var completedSteps = Set<Step>()

    private init(activeSteps: [Step]) {
        it_assert(!activeSteps.isEmpty)
        self.activeSteps = activeSteps
        self.currentStep = activeSteps[0]
        super.init()
    }

    private func index(of step: Step) -> Int {
        return activeSteps.firstIndex(of: step) ?? 0
    }

    private var isFirstStep: Bool { currentStep == activeSteps.first }
    private var isLastStep: Bool { currentStep == activeSteps.last }

    // UI elements
    private var stepLabels = [NSTextField]()
    private var contentLabel: NSTextField!
    private var backButton: NSButton!
    private var doItButton: NSButton!
    private var nextButton: NSButton!
    private var cancelButton: NSButton!
    private var spinner: NSProgressIndicator!
    private var scrims = [OnboardingScrim]()

    // $CLAUDE_CONFIG_DIR resolution (the one shell spawn) is kicked off when the
    // panel opens so the answer is usually ready by the time the user clicks
    // Install. resolvedConfigDirectory is set when it completes;
    // configResolutionInFlight guards against launching it twice. If the user
    // clicks Install before it finishes, pendingInstallStep records the step to
    // resume and the button bar shows a spinner + Cancel until it lands.
    private var resolvedConfigDirectory: URL?
    private var configResolutionInFlight = false
    private var pendingInstallStep: Step?
    // Where CLAUDE_CONFIG_DIR can be read from for the session that opened the
    // installer (see ClaudeCodeConfigDirResolver). Every source is resolved as
    // soon as the panel opens. When they all agree (or only one answered) the
    // directory goes straight into resolvedConfigDirectory; when they disagree
    // the distinct directories wait in configDirCandidates until the user picks
    // one at Install time.
    private var configDirSources: [ClaudeCodeConfigDirResolver.Source] = []
    private var configDirCandidates: [ClaudeCodeConfigDirResolver.Candidate] = []
    // The remote step. remoteConductor is the session's conductor when it is framing, captured
    // when the panel opens; its host's CLAUDE_CONFIG_DIR lookup also starts then.
    private weak var remoteConductor: Conductor?
    private var remoteHost = ""
    private var remoteResolvedDirectory: String?
    private var remoteResolutionInFlight = false
    private var introSheet: NSWindow?
    private var introTitleLabel: NSTextField?
    private var introLeadLabel: NSTextField?
    private var introDisclosureButton: NSButton?
    private var introDisclosureLabel: NSTextField?
    private var introDetailsLabel: NSTextField?
    private var introHelpLink: LinkButton?
    private var introContinueButton: NSButton?

    private static let integrationHelpURL =
        "https://iterm2.com/claude-code-integration.html"

    // MARK: - Public API

    // Strip every cc-status hook entry from Claude Code's settings.json
    // (resolved from $CLAUDE_CONFIG_DIR, defaulting to ~/.claude).
    // Inverse of doInstallHook. Returns .success for the file-missing
    // and no-cc-status-entries cases; returns a specific failure
    // case (.unreadable / .malformed / .writeFailed) when something
    // actually went wrong, so the caller can show a targeted alert
    // instead of always blaming the write step. Cleans up empty
    // containers as it goes — an event whose only hook was
    // cc-status is removed entirely; an empty `hooks` dict is
    // removed from the top-level settings — so the file shape after
    // uninstall matches what a fresh install would have produced if
    // the user had never installed our hook in the first place.
    // Synchronous: claudeSettingsURL() reads the install-time-recorded directory
    // and never spawns a shell, so there's nothing slow to defer.
    @objc
    @discardableResult
    static func uninstallHooks() -> ClaudeCodeUninstallHooksResult {
        let settingsURL = claudeSettingsURL()
        let result = stripCCStatusHooks(fromSettingsURL: settingsURL)
        if result == .success {
            // Not simply false: the strip leaves a command that runs more
            // than cc-status (see ccStatusCommandsOnDisk), and
            // reconcileHooksCache would set the flag again at the next
            // launch. Agreeing with it now keeps the menu stable.
            iTermUserDefaults.claudeCodeHooksInstalled = hooksInstalled(atSettingsURL: settingsURL)
        }
        return result
    }

    // The distinct cc-status hook commands in settings.json. After
    // uninstallHooks succeeds, these are the ones it left in place because
    // they also run something of the user's.
    static func ccStatusCommandsOnDisk() -> [String] {
        guard let settings = loadSettings(at: claudeSettingsURL()) else {
            return []
        }
        var seen = Set<String>()
        return ccStatusCommands(inSettings: settings).filter { seen.insert($0).inserted }
    }

    // Strip every cc-status hook entry from the given settings.json. Returns
    // .success for the file-missing and no-cc-status-entries cases; returns a
    // specific failure (.unreadable / .malformed / .writeFailed) when something
    // actually went wrong, so a caller can show a targeted alert instead of
    // always blaming the write step. Cleans up empty containers as it goes — an
    // event whose only hook was cc-status is removed entirely; an empty `hooks`
    // dict is removed from the top-level settings — so the file shape afterward
    // matches what a fresh install would have produced if the user had never
    // installed our hook. Pure: touches only the given file, no user-defaults
    // side effects (uninstallHooks and the reinstall-orphan cleanup layer those
    // on top).
    // internal (not private) for unit testing via @testable import.
    @discardableResult
    static func stripCCStatusHooks(fromSettingsURL settingsURL: URL) -> ClaudeCodeUninstallHooksResult {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            RLog("Onboarding: no settings.json at \(settingsURL.path), nothing to strip")
            return .success
        }
        let data: Data
        do {
            data = try Data(contentsOf: settingsURL)
        } catch {
            RLog("Onboarding: couldn't read settings.json: \(error)")
            return .unreadable
        }
        // An empty or whitespace-only file has no hooks to remove (and Install
        // accepts it), but JSONSerialization rejects it.
        let blank = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ?? false
        if blank {
            return .success
        }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            DLog("Onboarding: settings.json isn't valid JSON: \(error)")
            return .malformed
        }
        guard var settings = parsed as? [String: Any] else {
            DLog("Onboarding: settings.json root isn't a JSON object")
            return .malformed
        }
        guard let stripped = ClaudeCodeHookSettings.stripped(settings,
                                                             descriptor: .claudeCode,
                                                             isOurs: { Self.isOurHookCommand($0) }) else {
            return .success
        }
        settings = stripped
        do {
            let out = try JSONSerialization.data(withJSONObject: settings,
                                                 options: [.prettyPrinted, .sortedKeys])
            try writeSettings(out, to: settingsURL)
            DLog("Onboarding: stripped cc-status hooks from \(settingsURL.path)")
            return .success
        } catch {
            RLog("Onboarding: failed to write settings.json during strip: \(error)")
            return .writeFailed
        }
    }

    // Write settings.json atomically without breaking a symlink. People who
    // keep their Claude Code settings in a dotfiles repo (GNU Stow, chezmoi)
    // have a settings.json that is a symlink into that repo. An atomic write
    // renames a temp file over the path it's given, so writing to the link's
    // own path replaces the link with a regular file: the real file silently
    // stops getting changes, and the new copy doesn't inherit the real file's
    // permissions (a 0600 file can end up world-readable). Resolving every
    // symlink in the path first puts the rename next to the real file, so the
    // link survives, and the atomic write carries the real file's mode over
    // to its replacement (the symlink tests check both).
    // resolvingSymlinksInPath() returns a dangling link's path unchanged, so
    // writing through one replaces the link, as before. An atomic write over
    // the link would carry the link's own mode (0755) to the new file, so
    // that case writes a new file beside it and renames it over the link,
    // giving it the mode any new file gets.
    private static func writeSettings(_ data: Data, to settingsURL: URL) throws {
        let writeURL = settingsURL.resolvingSymlinksInPath()
        if writeURL.path != settingsURL.path {
            DLog("Onboarding: \(settingsURL.path) resolves to \(writeURL.path); writing there")
        }
        let type = (try? FileManager.default.attributesOfItem(atPath: writeURL.path))?[.type] as? FileAttributeType
        guard type == .typeSymbolicLink else {
            try data.write(to: writeURL, options: .atomic)
            return
        }
        DLog("Onboarding: \(writeURL.path) is a dangling symlink; replacing it with a new file")
        let tempURL = writeURL.deletingLastPathComponent()
            .appendingPathComponent(".\(writeURL.lastPathComponent).\(UUID().uuidString)")
        do {
            try data.write(to: tempURL, options: .withoutOverwriting)
            if rename(tempURL.path, writeURL.path) != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw errorNamingSettingsFile(error, writeURL: writeURL)
        }
    }

    // The temporary file's name is an implementation detail the user never
    // sees, so a failure to write it is reported against settings.json, as an
    // atomic write would report it.
    private static func errorNamingSettingsFile(_ error: Error, writeURL: URL) -> Error {
        let nsError = error as NSError
        let code: Int
        if nsError.domain == NSCocoaErrorDomain {
            code = nsError.code
        } else if nsError.domain == NSPOSIXErrorDomain,
                  nsError.code == Int(EACCES) || nsError.code == Int(EPERM) {
            code = CocoaError.fileWriteNoPermission.rawValue
        } else {
            code = CocoaError.fileWriteUnknown.rawValue
        }
        var userInfo = nsError.domain == NSCocoaErrorDomain ? nsError.userInfo : [:]
        userInfo[NSFilePathErrorKey] = writeURL.path
        userInfo[NSURLErrorKey] = writeURL
        if nsError.domain != NSCocoaErrorDomain {
            userInfo[NSUnderlyingErrorKey] = nsError
        }
        return NSError(domain: NSCocoaErrorDomain, code: code, userInfo: userInfo)
    }

    // True iff the Claude Code workgroup (identified by the stable
    // template ID) is already in the user's workgroup model.
    @objc static func workgroupAlreadyInstalled() -> Bool {
        return iTermWorkgroupModel.instance.workgroup(
            uniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.workgroup) != nil
    }

    // Add the Claude Code workgroup to the user's workgroup model if
    // it isn't already there. Idempotent. Used both by the installer's
    // explicit install step and by ClaudeCodeModeController's
    // "Try It Now" path so the trial workgroup exists at entry time.
    @objc static func installWorkgroupIfNeeded() {
        guard !workgroupAlreadyInstalled() else { return }
        iTermWorkgroupModel.instance.add(ClaudeCodeWorkgroupTemplate.config)
    }

    // Remove the Claude Code workgroup from the user's model. Inverse
    // of installWorkgroupIfNeeded; no-op if the user has already
    // deleted it. Returns true so the caller treats it as a success
    // even when nothing changed.
    @objc
    @discardableResult
    static func uninstallWorkgroup() -> Bool {
        guard workgroupAlreadyInstalled() else { return true }
        iTermWorkgroupModel.instance.remove(
            uniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.workgroup)
        return true
    }

    // Strip Enter/Exit Workgroup triggers we installed from every
    // profile in both the canonical bookmarks and the divorced session
    // overrides — covers the "user opened the installer, then divorced
    // their session and ran installer again" case too. Match what the
    // installer installs: Enter triggers must reference our workgroup ID;
    // Exit triggers must filter on the "claude" job (so a hand-rolled
    // Exit trigger on a different job survives uninstall).
    @objc
    @discardableResult
    static func uninstallTriggers() -> Bool {
        if let shared = ProfileModel.sharedInstance() {
            removeOurWorkgroupTriggers(from: shared)
            // Persist the removal. Like install, removeOurWorkgroupTriggers
            // only mutates the in-memory model via setObject:forKey:inBookmark:;
            // without flush the triggers reappear on the next launch.
            shared.flush()
        }
        if let sessions = ProfileModel.sessionsInstance() {
            removeOurWorkgroupTriggers(from: sessions)
        }
        reconcileTriggersCache()
        return true
    }

    private static func removeOurWorkgroupTriggers(from model: ProfileModel) {
        for profile in model.bookmarks() {
            // Skip dynamic profiles that aren't rewritable — the
            // dynamic profile manager regenerates them from disk so
            // our edit would be clobbered. Rewritable dynamic profiles
            // are fair game (the install path could have written
            // there with the user's permission, so uninstall should
            // be able to undo it).
            if profileIsDynamic(profile),
               !iTermProfilePreferences.bool(forKey: KEY_DYNAMIC_PROFILE_REWRITABLE,
                                             inProfile: profile) {
                continue
            }
            guard let triggers = profile[KEY_TRIGGERS] as? [[String: Any]] else {
                continue
            }
            let filtered = removingClaudeWorkgroupTriggers(triggers)
            if filtered.count != triggers.count {
                model.setObject(filtered, forKey: KEY_TRIGGERS, inBookmark: profile)
            }
        }
    }

    // True iff the trigger dict is one of the Claude Code workgroup triggers
    // this installer manages (our Enter trigger pointing at the Claude Code
    // workgroup, or an Exit trigger filtered on "claude"). Matches regardless
    // of the leaderOnly flag so an older, pre-leaderOnly Exit trigger is still
    // recognized (and thus removed/replaced on reinstall and uninstall).
    private static func isClaudeWorkgroupTrigger(_ dict: [String: Any]) -> Bool {
        guard let action = dict[kTriggerActionKey] as? String else { return false }
        if action == "iTermEnterWorkgroupTrigger",
           (dict[kTriggerParameterKey] as? String) == ClaudeCodeWorkgroupTemplate.ID.workgroup {
            return true
        }
        if action == "iTermExitWorkgroupTrigger",
           let params = dict[kTriggerEventParamsKey] as? [String: Any],
           (params["jobName"] as? String) == "claude" {
            return true
        }
        return false
    }

    private static func removingClaudeWorkgroupTriggers(_ triggers: [[String: Any]]) -> [[String: Any]] {
        return triggers.filter { !isClaudeWorkgroupTrigger($0) }
    }

    // Add our Enter/Exit triggers to a profile, first removing any older copies
    // (e.g. an Exit trigger from before leaderOnly existed) so a reinstall
    // upgrades in place. TriggerController.add dedupes by exact dictionary, so
    // without this strip a flagless Exit trigger would survive *alongside* the
    // new leaderOnly one and keep firing on peers.
    private static func addClaudeWorkgroupTriggers(_ triggers: [Trigger],
                                                   toProfileWithGUID guid: String,
                                                   in model: ProfileModel) {
        if let profile = model.bookmark(withGuid: guid),
           let existing = profile[KEY_TRIGGERS] as? [[String: Any]] {
            let stripped = removingClaudeWorkgroupTriggers(existing)
            if stripped.count != existing.count {
                model.setObject(stripped, forKey: KEY_TRIGGERS, inBookmark: profile)
            }
        }
        TriggerController.add(triggers, toProfileWithGUID: guid, in: model)
    }

    // True iff every install-eligible profile has both our Enter
    // trigger (pointing at the Claude Code workgroup) and an Exit
    // trigger filtered on "claude". Backed by an iTermUserDefaults
    // cache so it's hot-path safe — validateMenuItem hits this on
    // every menu update and we don't want to walk every profile's
    // trigger list each time. The install/uninstall paths recompute
    // and write the cache; reconcileTriggersCache reseeds it at app
    // launch and before show().
    @objc static func triggersAlreadyInstalled() -> Bool {
        return iTermUserDefaults.claudeCodeTriggersInstalled
    }

    // Authoritative scan of the profile model. Used by the cache
    // reconciliation paths and by the install/uninstall paths after
    // they finish mutating profiles. Eligibility rule mirrors
    // install: skip non-rewritable dynamic profiles (regenerated
    // from disk, can't hold a merge).
    private static func triggersInstalledOnDisk() -> Bool {
        guard let model = ProfileModel.sharedInstance() else { return false }
        var sawAny = false
        for profile in model.bookmarks() {
            if !profileIsEligibleForClaudeTriggers(profile) {
                continue
            }
            sawAny = true
            if !profileHasClaudeWorkgroupTriggers(profile) {
                return false
            }
        }
        return sawAny
    }

    // Eligibility rule mirrors install: skip non-rewritable dynamic
    // profiles (regenerated from disk, can't hold a merge).
    private static func profileIsEligibleForClaudeTriggers(_ profile: [AnyHashable: Any]) -> Bool {
        return !profileIsDynamic(profile) ||
            iTermProfilePreferences.bool(forKey: KEY_DYNAMIC_PROFILE_REWRITABLE, inProfile: profile)
    }

    // Both our Enter trigger (pointing at the Claude Code workgroup) and
    // an Exit trigger filtered on "claude".
    static func profileHasClaudeWorkgroupTriggers(_ profile: [AnyHashable: Any]) -> Bool {
        let triggers = (profile[KEY_TRIGGERS] as? [[String: Any]]) ?? []
        var hasEnter = false
        var hasExit = false
        for dict in triggers {
            guard let action = dict[kTriggerActionKey] as? String else { continue }
            if action == "iTermEnterWorkgroupTrigger",
               let param = dict[kTriggerParameterKey] as? String,
               param == ClaudeCodeWorkgroupTemplate.ID.workgroup {
                hasEnter = true
            } else if action == "iTermExitWorkgroupTrigger",
                      let params = dict[kTriggerEventParamsKey] as? [String: Any],
                      (params["jobName"] as? String) == "claude",
                      (params[ExitWorkgroupTrigger.leaderOnlyParamKey] as? NSNumber)?.boolValue == true {
                // Match the installer's scope: an Exit trigger
                // filtered on "claude". A user-added Exit trigger
                // for some other job is unrelated and shouldn't
                // count as "already installed." The leaderOnly
                // requirement also makes a pre-leaderOnly install
                // read as not-installed, so reinstalling upgrades it.
                hasExit = true
            }
        }
        return hasEnter && hasExit
    }

    // MARK: - The tmux profile

    // tmux Integration creates its "tmux" profile the first time it needs it,
    // by copying the default profile. Someone who installed the triggers on
    // other profiles but not the default one would get a tmux profile
    // without them, and claude in a tmux tab would never enter the workgroup.
    // So a tmux profile created after the triggers were installed anywhere
    // gets them too. Creating the profile up front instead would add a
    // "tmux" profile for everyone, tmux user or not.
    static func newTmuxProfileNeedsClaudeTriggers(_ tmuxProfile: [AnyHashable: Any],
                                                  otherProfiles: [[AnyHashable: Any]]) -> Bool {
        guard profileIsEligibleForClaudeTriggers(tmuxProfile),
              !profileHasClaudeWorkgroupTriggers(tmuxProfile) else {
            return false
        }
        return otherProfiles.contains {
            profileIsEligibleForClaudeTriggers($0) && profileHasClaudeWorkgroupTriggers($0)
        }
    }

    // The dictionaries the installer writes.
    static func claudeWorkgroupTriggerDictionaries() -> [[String: Any]] {
        return [makeEnterWorkgroupTrigger(), makeExitWorkgroupTrigger()].compactMap {
            $0?.dictionaryValue() as? [String: Any]
        }
    }

    private static var tmuxProfileObserver: NSObjectProtocol?

    @objc static func observeTmuxProfileCreation() {
        guard tmuxProfileObserver == nil else {
            return
        }
        tmuxProfileObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.iTermProfileModelDidCreateTmuxProfile,
            object: nil,
            queue: nil) { notification in
                guard let guid = notification.object as? String else {
                    return
                }
                MainActor.assumeIsolated {
                    tmuxProfileWasCreated(guid: guid)
                }
            }
    }

    private static func tmuxProfileWasCreated(guid: String) {
        guard let model = ProfileModel.sharedInstance(),
              let tmuxProfile = model.bookmark(withGuid: guid) else {
            return
        }
        let others = model.bookmarks().filter { ($0[KEY_GUID] as? String) != guid }
        guard newTmuxProfileNeedsClaudeTriggers(tmuxProfile, otherProfiles: others),
              let enter = makeEnterWorkgroupTrigger(),
              let exit = makeExitWorkgroupTrigger() else {
            DLog("New tmux profile \(guid) needs no Claude Code triggers")
            return
        }
        RLog("Adding Claude Code workgroup triggers to the new tmux profile \(guid)")
        addClaudeWorkgroupTriggers([enter, exit], toProfileWithGUID: guid, in: model)
        reconcileTriggersCache()
    }

    // Recompute the trigger cache from the profile model. Cheap to
    // call on demand (one walk vs. one walk per validateMenuItem
    // call). Used at app launch, before opening the installer
    // panel, and after install/uninstall mutations.
    @objc static func reconcileTriggersCache() {
        let onDisk = triggersInstalledOnDisk()
        if iTermUserDefaults.claudeCodeTriggersInstalled != onDisk {
            iTermUserDefaults.claudeCodeTriggersInstalled = onDisk
        }
    }

    private static func profileIsDynamic(_ profile: [AnyHashable: Any]) -> Bool {
        return (profile[KEY_DYNAMIC_PROFILE] as? NSNumber)?.boolValue == true
    }

    // True iff our cc-status hook entries are present. Backed by an
    // iTermUserDefaults cache (claudeCodeHooksInstalled) that the
    // install/uninstall paths keep in sync — so this is hot-path safe
    // (called repeatedly by validateMenuItem for the install /
    // uninstall menu items, no disk IO). The disk-walking scan lives
    // in hooksInstalledOnDisk for the rare cases that need
    // authoritative truth.
    @objc static func hooksAlreadyInstalled() -> Bool {
        return iTermUserDefaults.claudeCodeHooksInstalled
    }

    // Strict health check used by the broken-install detector.
    // Stronger than hooksInstalledOnDisk: every event in
    // hookEventNames must have a cc-status entry, AND that entry's
    // command must plausibly run. Catches the cases
    // hooksInstalledOnDisk doesn't:
    //   • partial removal (Claude Code rewrote settings.json and
    //     dropped some events but not others)
    //   • stale path (a hook command from an iTerm2 location that
    //     no longer exists, e.g. the user replaced the app and the
    //     symlink target is gone)
    //   • broken symlink (cc-status was removed from the bundle)
    // hooksInstalledOnDisk stays loose because reconcileHooksCache
    // wants "is it set up at all" semantics — flipping the cache to
    // false on a partial install would incorrectly hide the menu's
    // Uninstall item.
    //
    // Claude Code runs a hook's command with /bin/sh -c and never
    // checks it beforehand, so the command may use $HOME, ~, or a
    // wrapper (issue 13099). Variables in the command are expanded
    // from the environment withHookEnvironment provides (see
    // CCStatusHookCommand). An entry is healthy if any of its
    // references to cc-status resolves to an executable, or can't be
    // resolved without running the shell: like Claude Code, we can't
    // know whether such a command works, and a false alarm on every
    // launch is worse than missing a rare real breakage.
    //
    // The new-hook-event migration case (a future iTerm2 adds a
    // 10th event) returns false here, which prompts the user to
    // Reinstall — doInstallHook is idempotent and just adds the
    // missing event.
    //
    // Reads settings.json and follows symlinks on `queue`, which must not be
    // the main queue: a wedged network mount could block forever. Launches
    // the user's shell only if some cc-status command needs its environment
    // (see withHookEnvironment). Calls completion on the main thread.
    // `settingsURL` is the recorded directory's by default; the installer
    // pre-marks its hook step from the directory the lookups resolved for the
    // session, which need not be the recorded one.
    static func checkHooksHealth(settingsURL: URL = claudeSettingsURL(),
                                 on queue: DispatchQueue,
                                 completion: @escaping (Bool) -> Void) {
        queue.async {
            guard let settings = loadSettings(at: settingsURL) else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            withHookEnvironment(for: settings, queue: queue) { environment in
                let healthy = hooksHealthy(inSettings: settings, environment: environment) {
                    // Follows symlinks; a dangling symlink fails. The
                    // executable bit matters because sh can't run a
                    // non-executable file.
                    FileManager.default.isExecutableFile(atPath: $0)
                }
                DispatchQueue.main.async {
                    completion(healthy)
                }
            }
        }
    }

    // checkHooksHealth without a shell: iTerm2's own environment, which has
    // HOME, stands in for the user's shell's. For a background question that
    // must not cost a shell startup (hooksHealthyForSession). Reads disk and
    // follows symlinks; call off the main thread.
    static func hooksHealthyOnDisk(settingsURL: URL) -> Bool {
        guard let settings = loadSettings(at: settingsURL) else {
            return false
        }
        return hooksHealthy(inSettings: settings, environment: ProcessInfo.processInfo.environment) {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private static func loadSettings(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // This instance's hook commands in settings.json (isOurHookCommand), across
    // all our events.
    // internal (not private) for unit testing via @testable import.
    static func ccStatusCommands(inSettings settings: [String: Any]) -> [String] {
        guard let hooks = settings["hooks"] as? [String: Any] else {
            return []
        }
        return hookEventNames.flatMap { eventName -> [String] in
            let groups = hooks[eventName] as? [[String: Any]] ?? []
            return groups.flatMap { group -> [String] in
                let entries = group["hooks"] as? [[String: Any]] ?? []
                return entries.compactMap { entry in
                    guard let command = entry["command"] as? String,
                          isOurHookCommand(command) else {
                        return nil
                    }
                    return command
                }
            }
        }
    }

    // The environment for judging the cc-status commands in `settings`. The
    // health check and the installer both get it here, so they agree on
    // whether a command works: if they didn't, the health check could call
    // a command broken that Reinstall then keeps, and the warning would
    // return on every launch.
    //
    // When no command needs an environment (the usual case: the installer
    // writes a plain absolute path) this is empty and no shell is launched.
    // Otherwise it is /usr/bin/env from a login, interactive shell, which is
    // what a terminal session, and so a claude started in one, sees. If the
    // shell can't be run, iTerm2's own environment stands in; it has HOME,
    // and a variable it lacks or a bare cc-status missing from its PATH only
    // makes a command unresolvable, which counts as working.
    //
    // Called on `queue`; calls completion on `queue`.
    private static func withHookEnvironment(for settings: [String: Any],
                                            queue: DispatchQueue,
                                            completion: @escaping ([String: String]) -> Void) {
        guard ccStatusCommands(inSettings: settings).contains(where: CCStatusHookCommand.needsEnvironment) else {
            completion([:])
            return
        }
        DLog("Onboarding: reading the shell environment to resolve hook commands")
        DispatchQueue.main.async {
            iTermSlowOperationGateway.sharedInstance().runCommand(inUserShell: "/usr/bin/env",
                                                                  mode: .loginInteractive) { output in
                let environment: [String: String]
                if let output {
                    environment = CCStatusHookCommand.parseEnvironment(output)
                } else {
                    DLog("Onboarding: couldn't read the shell environment; using iTerm2's")
                    environment = ProcessInfo.processInfo.environment
                }
                queue.async {
                    completion(environment)
                }
            }
        }
    }

    // The settings.json half of checkHooksHealth.
    // internal (not private) for unit testing via @testable import.
    // Only this instance's hooks count (CCStatusHookCommand.isOwned); `dotDir`
    // names the instance, the running one by default.
    static func hooksHealthy(inSettings settings: [String: Any],
                             environment: [String: String],
                             dotDir: String? = FileManager.default.homeDirectoryDotDir(),
                             isExecutable: (String) -> Bool) -> Bool {
        guard let dotDir else {
            // With no dot dir there is no hook of ours to be healthy.
            return false
        }
        guard let hooks = settings["hooks"] as? [String: Any] else {
            return false
        }
        for eventName in hookEventNames {
            guard let groups = hooks[eventName] as? [[String: Any]] else {
                return false
            }
            let ok = groups.contains { group in
                let entries = group["hooks"] as? [[String: Any]] ?? []
                return entries.contains { entry in
                    guard let command = entry["command"] as? String,
                          CCStatusHookCommand.isOwned(command, byDotDir: dotDir, environment: environment) else {
                        return false
                    }
                    let resolutions = CCStatusHookCommand.resolutions(of: command,
                                                                      environment: environment,
                                                                      isExecutable: isExecutable)
                    return resolutions.contains { resolution in
                        if case .notExecutable = resolution {
                            return false
                        }
                        return true
                    }
                }
            }
            if !ok {
                DLog("Health: no working cc-status hook for \(eventName)")
                return false
            }
        }
        return true
    }

    // Loose "is the hook set up at all" scan, used by
    // reconcileHooksCache to seed the menu-validation cache at
    // launch. Returns true if any one event has a cc-status entry.
    // Stays loose because flipping the cache to false on a partial
    // install would incorrectly hide the menu's Uninstall item
    // when there's still real state on disk. The strict variant
    // for the broken-install detector is
    // checkHooksHealth above.
    private static func hooksInstalledOnDisk() -> Bool {
        return hooksInstalled(atSettingsURL: claudeSettingsURL())
    }

    // The settings.json half of hooksInstalledOnDisk, shared with
    // uninstallHooks so the two agree.
    // internal (not private) for unit testing via @testable import.
    static func hooksInstalled(atSettingsURL settingsURL: URL) -> Bool {
        guard let settings = loadSettings(at: settingsURL) else {
            return false
        }
        return !ccStatusCommands(inSettings: settings).isEmpty
    }

    // Call once at app launch. Reconciles the on-disk truth with the
    // cached UD value so the cache survives the cold-start case
    // where the user has hooks installed from a pre-cache build (or
    // edited settings.json by hand). Subsequent reads of
    // hooksAlreadyInstalled use the cache only.
    @objc static func reconcileHooksCache() {
        let onDisk = hooksInstalledOnDisk()
        if iTermUserDefaults.claudeCodeHooksInstalled != onDisk {
            iTermUserDefaults.claudeCodeHooksInstalled = onDisk
        }
    }

    // Migration for the claudeCodeIntegrationCompleted sticky flag.
    // The flag was added after 3.7.0beta1/beta2 shipped, so users
    // who installed the integration in those releases never got it
    // set on their successful install — and they're exactly the
    // population that most needs the broken-install prompt
    // (settings.json may have been rewritten in the meantime).
    //
    // Detect them by intersecting "we have hooks on disk now" (per
    // claudeCodeHooksInstalled, which reconcileHooksCache has just
    // refreshed) with "user has run a pre-flag beta on this
    // machine" (per iTermPreferences's recorded version history).
    // Idempotent: subsequent launches see the flag set and bail.
    // Must run after reconcileHooksCache so the cache is current.
    @objc static func migrateIntegrationCompletedFlagIfNeeded() {
        if iTermUserDefaults.claudeCodeIntegrationCompleted {
            return
        }
        // Only fire on the upgrade transition: the version that
        // ran on the previous launch was a pre-flag build.
        // Looking at the full all-versions-ever-used set would
        // also catch this, but it would re-evaluate forever — a
        // user who briefly tried a pre-flag build years ago and
        // has been on post-flag versions since would have the
        // pre-flag string in their history indefinitely, so any
        // future event that cleared the flag (manual defaults
        // edit, a future bug) would re-trigger this migration on
        // every launch. The migration is a one-time bridge across
        // the version that introduced the flag, so make it
        // observe exactly that transition.
        guard let previousVersion = iTermPreferences.appVersionBeforeThisLaunch(),
              versionStringIsPreFlag(previousVersion) else {
            return
        }
        // Mirror doInstallHook, the only path that sets the flag
        // for live installs: condition strictly on the hook being
        // present. ORing in triggers/workgroup would cover more
        // wholesale-strip cases — but it would also turn on the
        // flag for users who installed only triggers or only the
        // workgroup in a pre-flag build without ever installing
        // the hook, leaving them subject to the broken-install
        // prompt whose copy talks about reinstalling a hook they
        // never had. Wholesale-strip users (settings.json wiped,
        // cache reconciled to false) miss the auto-prompt; they
        // recover via the Install Claude Code Integration menu,
        // which is visible when no artifacts are detected.
        guard iTermUserDefaults.claudeCodeHooksInstalled else {
            return
        }
        RLog("Onboarding: migrating claudeCodeIntegrationCompleted=true (hook on disk, previous launch was pre-flag build \(previousVersion))")
        iTermUserDefaults.claudeCodeIntegrationCompleted = true
    }

    // True for versions that shipped doInstallHook but predate the
    // claudeCodeIntegrationCompleted setter inside it. The integration
    // code first landed on 2026-04-07 (commit 5ad76ad9c), and the
    // setter is being added in 3.7.0beta3, so the affected window
    // is: 3.7.0beta1, 3.7.0beta2, and any 3.7 nightly built between
    // 2026-04-07 and beta3 cut. We don't bother filtering nightlies
    // by date — a user whose only 3.7 nightly is post-flag will
    // have had the flag set natively by doInstallHook on install
    // and will already have bailed out of migration above.
    private static func versionStringIsPreFlag(_ version: String) -> Bool {
        if version == "3.7.0beta1" || version == "3.7.0beta2" {
            return true
        }
        // Format: "3.7.YYYYMMDD-nightly" (per version.txt's
        // %(extra)s expansion in the nightly build script).
        return version.range(of: #"^3\.7\.\d{8}-nightly$"#,
                             options: .regularExpression) != nil
    }

    // True for versions that predate the Exit Workgroup leaderOnly flag, which
    // shipped after 3.7.0beta3 and the 2026-06-08 nightly. Used to backfill the
    // flag exactly once, on the upgrade transition.
    private static func versionStringIsPreLeaderOnly(_ version: String) -> Bool {
        if version == "3.7.0beta1" || version == "3.7.0beta2" || version == "3.7.0beta3" {
            return true
        }
        // Format: "3.7.YYYYMMDD-nightly".
        let prefix = "3.7."
        let suffix = "-nightly"
        if version.hasPrefix(prefix), version.hasSuffix(suffix) {
            let dateString = String(version.dropFirst(prefix.count).dropLast(suffix.count))
            if dateString.count == 8, let date = Int(dateString) {
                return date <= 20260608
            }
        }
        return false
    }

    // One-time backfill: set leaderOnly on existing Claude Code Exit Workgroup
    // triggers for users upgrading from a build that predates the flag. The
    // pre-leaderOnly installer wrote an Exit trigger that fires on any session
    // (including peers); without this, upgraders would keep the buggy behavior
    // until they manually reinstalled. Mirrors migrateIntegrationCompletedFlag-
    // IfNeeded: gated on the previous-launch version so it runs exactly on the
    // upgrade transition and never re-flips a flag the user later cleared. It
    // writes profiles (KEY_TRIGGERS), so it touches only install-eligible
    // profiles and only when the flag is actually missing.
    @objc static func migrateExitTriggersToLeaderOnlyIfNeeded() {
        guard let previousVersion = iTermPreferences.appVersionBeforeThisLaunch(),
              versionStringIsPreLeaderOnly(previousVersion) else {
            return
        }
        var changed = false
        if let shared = ProfileModel.sharedInstance() {
            changed = upgradeExitTriggersToLeaderOnly(in: shared) || changed
        }
        if let sessions = ProfileModel.sessionsInstance() {
            changed = upgradeExitTriggersToLeaderOnly(in: sessions) || changed
        }
        guard changed else {
            return
        }
        RLog("Onboarding: migrated Exit Workgroup triggers to leaderOnly (previous launch was pre-leaderOnly build \(previousVersion))")
        ProfileModel.sharedInstance()?.flush()
        NotificationCenter.default.post(name: NSNotification.Name(kReloadAllProfiles),
                                        object: nil)
    }

    // Set leaderOnly on every Claude Code Exit Workgroup trigger in `model`
    // that lacks it. Returns whether any profile changed. Skips non-rewritable
    // dynamic profiles (regenerated from disk), matching install/uninstall.
    private static func upgradeExitTriggersToLeaderOnly(in model: ProfileModel) -> Bool {
        var any = false
        for profile in model.bookmarks() {
            if profileIsDynamic(profile),
               !iTermProfilePreferences.bool(forKey: KEY_DYNAMIC_PROFILE_REWRITABLE,
                                             inProfile: profile) {
                continue
            }
            guard let triggers = profile[KEY_TRIGGERS] as? [[String: Any]] else {
                continue
            }
            var changed = false
            let updated: [[String: Any]] = triggers.map { dict in
                // Only the installer's Exit trigger (Job Ended: claude). A
                // regex/user-added Exit trigger has no claude jobName and is
                // left alone, so we never force the flag onto a hand-made one.
                guard (dict[kTriggerActionKey] as? String) == "iTermExitWorkgroupTrigger",
                      var params = dict[kTriggerEventParamsKey] as? [String: Any],
                      (params["jobName"] as? String) == "claude" else {
                    return dict
                }
                if (params[ExitWorkgroupTrigger.leaderOnlyParamKey] as? NSNumber)?.boolValue == true {
                    return dict
                }
                params[ExitWorkgroupTrigger.leaderOnlyParamKey] = NSNumber(value: true)
                var newDict = dict
                newDict[kTriggerEventParamsKey] = params
                changed = true
                return newDict
            }
            if changed {
                model.setObject(updated, forKey: KEY_TRIGGERS, inBookmark: profile)
                any = true
            }
        }
        return any
    }

    // The installer for whichever session is current: the menu items and the
    // welcome window have no better candidate, and a session's profile is what
    // decides where CLAUDE_CONFIG_DIR is read from.
    @objc static func show() {
        show(session: iTermController.sharedInstance()?.currentTerminal?.currentSession())
    }

    // `session` is the one whose claude the install is for: the one that showed
    // the offer, the one the health monitor found broken, or the current one.
    // Its profile decides which shells could have exported CLAUDE_CONFIG_DIR.
    @objc static func show(session: PTYSession?) {
        show(session: session, startAtRemoteStep: false)
    }

    /// The installer opened at the step that installs the hook on the host `session` reaches
    /// through SSH Integration, for something that is specifically about that host, such as the
    /// health monitor finding its hook broken.
    @objc static func showRemoteInstall(session: PTYSession?) {
        show(session: session, startAtRemoteStep: true)
    }

    private static func show(session: PTYSession?, startAtRemoteStep: Bool) {
        if let existing = instance {
            if startAtRemoteStep, existing.activeSteps.contains(.installRemoteHook) {
                existing.currentStep = .installRemoteHook
                existing.updateUI()
            }
            existing.panel.makeKeyAndOrderFront(nil)
            return
        }

        // Omit the Python API step if the API is already enabled when the
        // installer opens — it's a precondition gate, not a checklist
        // item, so it has nothing to surface once on. Every other step
        // is always shown so the user can see what's already done
        // (pre-marked complete) versus what isn't. Silent skipping of
        // install steps confused users who closed the installer early
        // expecting "nothing was installed" while a previously-run
        // step was still active and auto-entering the workgroup.
        var steps: [Step] = []
        if !iTermAPIHelper.isEnabled() {
            steps.append(.enablePythonAPI)
        }
        steps.append(.installHook)
        // The agent in a session reached through SSH Integration reads the remote host's settings,
        // not this Mac's. hostConductor is the innermost conductor, where the shell runs, and for
        // a tmux pane its gateway's, since a pane has none of its own.
        // Menu actions and the health monitor call this on the main thread.
        let remoteConductor = MainActor.assumeIsolated {
            session?.hostConductor.flatMap { $0.framing ? $0 : nil }
        }
        if remoteConductor != nil {
            steps.append(.installRemoteHook)
        }
        steps.append(contentsOf: [.showToolbelt,
                                  .installWorkgroup,
                                  .installTriggers])

        let onboarding = ClaudeCodeOnboarding(activeSteps: steps)
        if let remoteConductor {
            onboarding.remoteConductor = remoteConductor
            onboarding.remoteHost = MainActor.assumeIsolated { remoteConductor.sshIdentity.stringIdentifier }
            // A session on a remote host is about that host, so start at its step, unless the
            // Python API still has to be enabled: nothing works until it is.
            if startAtRemoteStep || !steps.contains(.enablePythonAPI) {
                onboarding.currentStep = .installRemoteHook
            }
        }
        // Pre-mark install steps that are already done so the installer
        // shows them with the green checkmark and Next-as-default
        // affordance from the get-go. Re-clicking Install is a no-op
        // (the doInstall* methods are idempotent), so this is purely
        // about visibility. Reseed the cached flags from disk first
        // — the user may have added/removed profiles or edited
        // settings.json since this app launch.
        reconcileHooksCache()
        reconcileTriggersCache()
        // installHook's pre-marked state needs the strict check —
        // show() is also the repair prompt's destination, and
        // marking it complete via the loose cache would
        // contradict the warning text ("reinstall the hook…")
        // that just brought the user here. But the strict check
        // does file IO, including stat-following symlinks, and a
        // wedged network mount on $HOME would hang the panel
        // open. Defer to a background read and update the row
        // when it returns; the panel opens immediately with the
        // step shown as not-complete (default), then flips to ✅
        // if the install is actually healthy.
        if workgroupAlreadyInstalled() {
            onboarding.completedSteps.insert(.installWorkgroup)
        }
        if triggersAlreadyInstalled() {
            onboarding.completedSteps.insert(.installTriggers)
        }
        instance = onboarding
        onboarding.configDirSources = configDirSources(for: session)
        DLog("Onboarding: CLAUDE_CONFIG_DIR sources for session \(session?.guid ?? "none"): \(onboarding.configDirSources)")
        onboarding.setupPanel()
        onboarding.updateUI()
        onboarding.panel.center()
        onboarding.panel.makeKeyAndOrderFront(nil)
        // Start the CLAUDE_CONFIG_DIR lookups now, while the user reads the intro
        // and steps through the panel, so Install rarely has to wait on them.
        onboarding.startResolvingConfigDirectory()
        MainActor.assumeIsolated {
            onboarding.startResolvingRemoteConfigDirectory()
            onboarding.premarkRemoteHookStepIfHealthy()
        }
        // Cover the installer with the heads-up intro until the user
        // dismisses it. They might've launched this from the menu
        // not knowing what's about to be touched on disk; a sheet
        // (rather than a real installer step) keeps the click count
        // down for repeat users while still surfacing the
        // "you can undo this" promise to first-timers.
        onboarding.showIntroSheet()
        // The hook step's pre-mark waits for the CLAUDE_CONFIG_DIR lookups
        // (configResolutionDidFinish): it is judged against the directory this
        // session's shells report, not the one an earlier install recorded, and
        // when the shells disagree nothing is pre-marked, so the Install button
        // that asks which directory to use stays the default action.
    }

    // Background completion of the install-step pre-mark against the resolved
    // directory. Identity-checks against the static instance on return so a
    // panel that was closed-and-reopened during the read doesn't get the result
    // of an earlier query.
    private func premarkHookStepIfHealthy(in configDirectory: URL) {
        let settingsURL = configDirectory.appendingPathComponent("settings.json")
        Self.checkHooksHealth(settingsURL: settingsURL, on: DispatchQueue.global(qos: .utility)) { [weak self] healthy in
            guard let self, Self.instance === self, healthy else {
                return
            }
            DLog("Onboarding: hook already healthy in \(configDirectory.path); pre-marking the step")
            self.completedSteps.insert(.installHook)
            self.updateUI()
        }
    }

    // MARK: - Panel Setup

    private func setupPanel() {
        panel = iTermFocusablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        panel.title = String(localized: "ClaudeCodeOnboarding.PanelTitle", defaultValue: "Claude Code Integration Setup", comment: "Title of the Claude Code onboarding panel window")
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.delegate = self

        let contentView = NSView(frame: panel.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        panel.contentView = contentView

        let margin: CGFloat = 20

        // Step indicators at the top
        let stepsContainer = makeStepIndicators()
        stepsContainer.frame = NSRect(x: margin,
                                      y: contentView.bounds.height - 50,
                                      width: contentView.bounds.width - margin * 2,
                                      height: 30)
        stepsContainer.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(stepsContainer)

        // Separator line
        let separator = NSBox()
        separator.boxType = .separator
        separator.frame = NSRect(x: margin,
                                 y: contentView.bounds.height - 60,
                                 width: contentView.bounds.width - margin * 2,
                                 height: 1)
        separator.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(separator)

        // Content label
        contentLabel = NSTextField(wrappingLabelWithString: "")
        contentLabel.frame = NSRect(x: margin,
                                    y: 60,
                                    width: contentView.bounds.width - margin * 2,
                                    height: contentView.bounds.height - 130)
        contentLabel.autoresizingMask = [.width, .height]
        contentLabel.font = NSFont.systemFont(ofSize: 13)
        contentLabel.textColor = .labelColor
        contentLabel.isSelectable = false
        contentView.addSubview(contentLabel)

        // Button bar at the bottom
        let buttonY: CGFloat = 15

        nextButton = NSButton(title: String(localized: "ClaudeCodeOnboarding.Next", defaultValue: "Next", comment: "Button to advance to the next onboarding step"), target: self, action: #selector(nextPressed(_:)))
        nextButton.bezelStyle = .rounded
        nextButton.frame = NSRect(x: contentView.bounds.width - margin - 80,
                                  y: buttonY,
                                  width: 80,
                                  height: 32)
        nextButton.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(nextButton)

        doItButton = NSButton(title: String(localized: "ClaudeCodeOnboarding.DoIt", defaultValue: "Do It", comment: "Button that performs the current onboarding step action"), target: self, action: #selector(doItPressed(_:)))
        doItButton.bezelStyle = .rounded
        doItButton.keyEquivalent = "\r"
        doItButton.frame = NSRect(x: nextButton.frame.minX - 90,
                                  y: buttonY,
                                  width: 80,
                                  height: 32)
        doItButton.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(doItButton)

        backButton = NSButton(title: String(localized: "ClaudeCodeOnboarding.Back", defaultValue: "Back", comment: "Button to return to the previous onboarding step"), target: self, action: #selector(backPressed(_:)))
        backButton.bezelStyle = .rounded
        backButton.frame = NSRect(x: margin,
                                  y: buttonY,
                                  width: 80,
                                  height: 32)
        backButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        contentView.addSubview(backButton)

        // Cancel button, shown in the Do It button's place only while the hook
        // install is waiting on the (early-started) CLAUDE_CONFIG_DIR resolution.
        cancelButton = NSButton(title: iTermLocalizedCancel(), target: self, action: #selector(cancelPressed(_:)))
        cancelButton.bezelStyle = .rounded
        cancelButton.frame = doItButton.frame
        cancelButton.autoresizingMask = [.minXMargin, .maxYMargin]
        cancelButton.isHidden = true
        contentView.addSubview(cancelButton)

        // Indeterminate spinner shown next to Cancel during that same wait.
        spinner = NSProgressIndicator(frame: NSRect(x: doItButton.frame.minX - 28,
                                                    y: buttonY + 6,
                                                    width: 20,
                                                    height: 20))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(spinner)
    }

    // MARK: - Intro Sheet

    private func showIntroSheet() {
        let sheetWidth: CGFloat = 540
        let sheetPadding: CGFloat = 24
        let textWidth = sheetWidth - sheetPadding * 2

        let titleLabel = NSTextField(labelWithString: String(localized: "ClaudeCodeOnboarding.BeforeYouStart", defaultValue: "Before You Start", comment: "Title of the intro sheet shown before onboarding"))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.frame.size.width = textWidth
        titleLabel.sizeToFit()
        introTitleLabel = titleLabel

        let lead = NSTextField(wrappingLabelWithString:
            String(localized: "ClaudeCodeOnboarding.IntroLead", defaultValue: "Don’t panic! All of this can be undone later via iTerm2 > Uninstall Claude Code Integration.", comment: "Reassuring lead text on the intro sheet"))
        lead.font = NSFont.systemFont(ofSize: 13)
        lead.textColor = .labelColor
        lead.isSelectable = false
        Self.sizeWrappingLabel(lead, width: textWidth)
        introLeadLabel = lead

        // Image-only disclosure triangle plus a sibling label, mirroring
        // iTermDisclosableView. NSButton's .disclosure bezel doesn't
        // render a title alongside the triangle, so the label stands
        // separately.
        let disclosure = NSButton(title: "",
                                  target: self,
                                  action: #selector(toggleIntroDetails(_:)))
        disclosure.setButtonType(.onOff)
        disclosure.bezelStyle = .disclosure
        disclosure.imagePosition = .imageOnly
        disclosure.state = .off
        disclosure.sizeToFit()
        introDisclosureButton = disclosure

        let disclosureLabel = NSTextField(labelWithString: String(localized: "ClaudeCodeOnboarding.WhatGetsChanged", defaultValue: "What gets changed", comment: "Disclosure triangle label revealing the list of changes"))
        disclosureLabel.font = NSFont.systemFont(ofSize: 13)
        disclosureLabel.textColor = .labelColor
        disclosureLabel.isSelectable = false
        disclosureLabel.sizeToFit()
        introDisclosureLabel = disclosureLabel

        let details = NSTextField(wrappingLabelWithString:
            String(localized: "ClaudeCodeOnboarding.WhatGetsChangedDetails", defaultValue: "\u{2022} iTerm2\u{2019}s Python API is enabled\n\u{2022} A cc-status hook is added to ~/.claude/settings.json\n\u{2022} The toolbelt is shown\n\u{2022} A Claude Code workgroup is added to iTerm2\u{2019}s settings\n\u{2022} Enter/Exit Workgroup triggers are added to the profiles you pick", comment: "Bulleted list detailing what the Claude Code integration changes"))
        details.font = NSFont.systemFont(ofSize: 13)
        details.textColor = .secondaryLabelColor
        details.isSelectable = false
        Self.sizeWrappingLabel(details, width: textWidth)
        details.isHidden = true
        introDetailsLabel = details

        // Always-visible link to the full writeup, regardless of the
        // disclosure state. Sits below the "What gets changed" row so
        // users who want the whole story can read it on the web.
        let helpLink = LinkButton(title: String(localized: "ClaudeCodeOnboarding.LearnMore", defaultValue: "Learn more about the Claude Code integration", comment: "Link to documentation about the Claude Code integration"),
                                  target: self,
                                  action: #selector(openIntegrationHelp(_:)))
        helpLink.font = NSFont.systemFont(ofSize: 13)
        helpLink.configureLinkAppearance()
        helpLink.sizeToFit()
        introHelpLink = helpLink

        let continueButton = NSButton(title: String(localized: "General.Continue", defaultValue: "Continue", comment: "Continue button"),
                                      target: self,
                                      action: #selector(dismissIntroSheet(_:)))
        continueButton.bezelStyle = .rounded
        continueButton.keyEquivalent = "\r"
        continueButton.frame.size = NSSize(width: 100, height: 32)
        introContinueButton = continueButton

        let sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: sheetWidth, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        sheetWindow.isReleasedWhenClosed = false

        let contentView = NSView()
        contentView.addSubview(titleLabel)
        contentView.addSubview(lead)
        contentView.addSubview(disclosure)
        contentView.addSubview(disclosureLabel)
        contentView.addSubview(details)
        contentView.addSubview(helpLink)
        contentView.addSubview(continueButton)
        sheetWindow.contentView = contentView

        introSheet = sheetWindow
        layoutIntroSheet()
        panel.beginSheet(sheetWindow)
    }

    // sizeToFit on a wrapping NSTextField sometimes returns a single-
    // line height even after preferredMaxLayoutWidth — sizeThatFits
    // with an explicit width is the reliable path for the wrapped
    // height we actually need.
    private static func sizeWrappingLabel(_ label: NSTextField, width: CGFloat) {
        label.preferredMaxLayoutWidth = width
        label.frame.size.width = width
        let fitted = label.sizeThatFits(NSSize(width: width,
                                                height: .greatestFiniteMagnitude))
        label.frame.size = NSSize(width: width, height: fitted.height)
    }

    // Lay out the intro sheet top-down based on the disclosure state.
    // Re-runs whenever the disclosure toggles, so the sheet's content
    // size grows or shrinks to match.
    private func layoutIntroSheet() {
        guard let sheet = introSheet,
              let title = introTitleLabel,
              let lead = introLeadLabel,
              let disclosure = introDisclosureButton,
              let disclosureLabel = introDisclosureLabel,
              let details = introDetailsLabel,
              let helpLink = introHelpLink,
              let continueButton = introContinueButton else { return }

        let sheetWidth: CGFloat = 540
        let sheetPadding: CGFloat = 24
        let bottomPadding: CGFloat = 16
        let leadGap: CGFloat = 12
        let disclosureGap: CGFloat = 16
        let detailsGap: CGFloat = 8
        let linkGap: CGFloat = 12
        let buttonGap: CGFloat = 20
        let disclosureRowHeight = max(disclosure.frame.height,
                                      disclosureLabel.frame.height)

        var height = sheetPadding
        height += title.frame.height
        height += leadGap
        height += lead.frame.height
        height += disclosureGap
        height += disclosureRowHeight
        if !details.isHidden {
            height += detailsGap
            height += details.frame.height
        }
        height += linkGap
        height += helpLink.frame.height
        height += buttonGap
        height += continueButton.frame.height
        height += bottomPadding

        sheet.setContentSize(NSSize(width: sheetWidth, height: height))

        var y = height - sheetPadding - title.frame.height
        title.frame.origin = NSPoint(x: sheetPadding, y: y)
        y -= leadGap
        y -= lead.frame.height
        lead.frame.origin = NSPoint(x: sheetPadding, y: y)
        y -= disclosureGap
        y -= disclosureRowHeight
        let disclosureY = y + (disclosureRowHeight - disclosure.frame.height) / 2
        disclosure.frame.origin = NSPoint(x: sheetPadding, y: disclosureY)
        let labelY = y + (disclosureRowHeight - disclosureLabel.frame.height) / 2
        disclosureLabel.frame.origin = NSPoint(
            x: disclosure.frame.maxX + 4,
            y: labelY)
        if !details.isHidden {
            y -= detailsGap
            y -= details.frame.height
            details.frame.origin = NSPoint(x: sheetPadding, y: y)
        }
        y -= linkGap
        y -= helpLink.frame.height
        helpLink.frame.origin = NSPoint(x: sheetPadding, y: y)
        continueButton.frame.origin = NSPoint(
            x: sheetWidth - sheetPadding - continueButton.frame.width,
            y: bottomPadding)
    }

    @objc private func toggleIntroDetails(_ sender: NSButton) {
        introDetailsLabel?.isHidden = (sender.state == .off)
        layoutIntroSheet()
    }

    @objc private func openIntegrationHelp(_ sender: Any?) {
        if let url = URL(string: Self.integrationHelpURL) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func dismissIntroSheet(_ sender: Any?) {
        guard let sheet = introSheet else { return }
        panel.endSheet(sheet)
        introSheet = nil
        introTitleLabel = nil
        introLeadLabel = nil
        introDisclosureButton = nil
        introDisclosureLabel = nil
        introDetailsLabel = nil
        introHelpLink = nil
        introContinueButton = nil
        updateUI()
    }

    private func makeStepIndicators() -> NSView {
        let container = NSView()
        stepLabels.removeAll()

        for _ in activeSteps {
            let label = NSTextField(labelWithString: "")
            label.font = NSFont.systemFont(ofSize: 12)
            label.lineBreakMode = .byTruncatingTail
            container.addSubview(label)
            stepLabels.append(label)
        }

        return container
    }

    private func layoutStepLabels() {
        guard let container = stepLabels.first?.superview else { return }
        let containerWidth = container.bounds.width
        // Space labels evenly so the last label's right edge aligns with the container's right edge.
        var x: CGFloat = 0
        for (i, label) in stepLabels.enumerated() {
            label.frame.origin = NSPoint(x: x, y: 0)
            if i < stepLabels.count - 1 {
                let spacing = (containerWidth - stepLabels.reduce(0) { $0 + $1.frame.width }) / CGFloat(stepLabels.count - 1)
                x += label.frame.width + max(spacing, 4)
            }
        }
    }

    // MARK: - UI Update

    private func updateUI() {
        // Update step labels
        for (i, step) in activeSteps.enumerated() {
            let prefix: String
            if completedSteps.contains(step) {
                prefix = "\u{2705} "
            } else if step == currentStep {
                prefix = "\u{25B6}\u{FE0F} "
            } else {
                prefix = "\u{25CB} "
            }
            let label = stepLabels[i]
            label.stringValue = prefix + step.title
            label.font = step == currentStep ? NSFont.boldSystemFont(ofSize: 12) : NSFont.systemFont(ofSize: 12)
            label.sizeToFit()
        }
        layoutStepLabels()

        // Keep scrims visible during the Show Toolbelt step; remove otherwise.
        if currentStep != .showToolbelt {
            removeScrims()
        }

        // Update content
        if currentStep == .installRemoteHook {
            contentLabel.stringValue = MainActor.assumeIsolated { remoteHookDescription }
        } else {
            contentLabel.stringValue = currentStep.description
        }

        // The step labels and content above always update. The button bar,
        // however, is owned by the config-resolution wait while it's up
        // (beginWaitingForConfigResolution): Do It is hidden behind the spinner
        // + Cancel and Back/Next are disabled. updateUI can be re-entered during
        // that wait (e.g. the panel-open disk health check's main-queue
        // continuation), so bail out before touching the buttons rather than
        // un-hiding Do It on top of Cancel. endWaitingForConfigResolution clears
        // pendingInstallStep and calls updateUI again to restore this section.
        guard pendingInstallStep == nil else {
            return
        }

        // Update buttons
        backButton.isEnabled = !isFirstStep
        doItButton.title = currentStep.buttonTitle
        let oldY = doItButton.frame.origin.y
        let oldHeight = doItButton.frame.height
        doItButton.sizeToFit()
        doItButton.frame.origin.x = nextButton.frame.minX - doItButton.frame.width - 10
        doItButton.frame.origin.y = oldY
        doItButton.frame.size.height = oldHeight
        doItButton.isHidden = false

        if isLastStep {
            nextButton.title = String(localized: "General.Close", defaultValue: "Close", comment: "Close: used on buttons and menu items")
            nextButton.isEnabled = true
        } else {
            nextButton.title = String(localized: "ClaudeCodeOnboarding.Next", defaultValue: "Next", comment: "Button to advance to the next onboarding step")
            // Show Toolbelt is optional: Next is always enabled so the
            // user can skip it. The default-button logic below keeps
            // Show as the default until the toolbelt has actually been
            // shown, then promotes Next to the default.
            nextButton.isEnabled =
                completedSteps.contains(currentStep) || currentStep == .showToolbelt
        }

        if completedSteps.contains(currentStep) {
            nextButton.keyEquivalent = "\r"
            doItButton.keyEquivalent = ""
        } else {
            doItButton.keyEquivalent = "\r"
            nextButton.keyEquivalent = ""
        }
    }

    // MARK: - Navigation

    @objc private func backPressed(_ sender: Any?) {
        let i = index(of: currentStep)
        guard i > 0 else {
            return
        }
        currentStep = activeSteps[i - 1]
        updateUI()
    }

    @objc private func nextPressed(_ sender: Any?) {
        if isLastStep {
            panel.close()
            Self.instance = nil
            return
        }
        let i = index(of: currentStep)
        guard i + 1 < activeSteps.count else {
            return
        }
        currentStep = activeSteps[i + 1]
        updateUI()
    }

    @objc private func doItPressed(_ sender: Any?) {
        // Capture the step now rather than reading currentStep back in any async
        // continuation. The config-dir wait itself is modal (Back/Next are
        // disabled), but the file-I/O phase after it is not: performHookInstall
        // runs with Back/Next re-enabled (endWaitingForConfigResolution calls
        // updateUI before it starts), so the user can move to another step
        // before installHookFiles completes. Re-reading currentStep there would
        // mark whatever step they moved to as complete instead of installHook.
        let step = currentStep
        switch step {
        case .enablePythonAPI:
            finishDoIt(doEnablePythonAPI(), step: step)
        case .installHook:
            if let configDirectory = resolvedConfigDirectory {
                // CLAUDE_CONFIG_DIR already resolved (started when the panel
                // opened) — go straight to the fast file-write install.
                performHookInstall(configDirectory: configDirectory, step: step)
            } else if !configDirCandidates.isEmpty {
                // The shells that could have exported CLAUDE_CONFIG_DIR for this
                // session disagree. Ask which directory to install into.
                guard let configDirectory = askWhichConfigDirectory() else {
                    return
                }
                resolvedConfigDirectory = configDirectory
                performHookInstall(configDirectory: configDirectory, step: step)
            } else {
                // Still resolving: show a spinner + Cancel and resume when it
                // lands (or the user cancels).
                beginWaitingForConfigResolution(step: step)
            }
        case .showToolbelt:
            doShowToolbelt()
            finishDoIt(true, step: step)
        case .installWorkgroup:
            finishDoIt(doInstallWorkgroup(), step: step)
        case .installTriggers:
            finishDoIt(doInstallTriggers(), step: step)
        case .installRemoteHook:
            if let directory = remoteResolvedDirectory {
                MainActor.assumeIsolated {
                    performRemoteHookInstall(configDirectory: directory, step: step)
                }
            } else {
                beginWaitingForConfigResolution(step: step)
            }
        }
    }

    private func finishDoIt(_ success: Bool, step: Step) {
        if success {
            completedSteps.insert(step)
        }
        updateUI()
    }

    // MARK: - CLAUDE_CONFIG_DIR resolution

    private func startResolvingConfigDirectory() {
        guard resolvedConfigDirectory == nil, configDirCandidates.isEmpty, !configResolutionInFlight else {
            return
        }
        configResolutionInFlight = true
        let sources = configDirSources
        var results: [(source: ClaudeCodeConfigDirResolver.Source, directory: URL?)] = []
        // Sequential rather than concurrent: two interactive shells starting at
        // once would double the rc-file cost on the same core, and the pidinfo
        // service runs them one at a time anyway.
        func resolveNext() {
            guard results.count < sources.count else {
                configResolutionDidFinish(results: results)
                return
            }
            let source = sources[results.count]
            Self.resolveConfigDirectory(from: source) { [weak self] url in
                guard let self, Self.instance === self else {
                    return
                }
                results.append((source, url))
                resolveNext()
            }
        }
        resolveNext()
    }

    private func configResolutionDidFinish(results: [(source: ClaudeCodeConfigDirResolver.Source, directory: URL?)]) {
        configResolutionInFlight = false
        let candidates = ClaudeCodeConfigDirResolver.candidates(from: results)
        DLog("Onboarding: CLAUDE_CONFIG_DIR candidates: \(candidates)")
        switch candidates.count {
        case 0:
            // Every lookup failed (see resolveConfigDirectory). Do NOT record a
            // guessed directory; a retry can still succeed.
            configResolutionFailed()
        case 1:
            resolvedConfigDirectory = candidates[0].directory
            // If Install is waiting on this, resume it now.
            if let step = pendingInstallStep, step == .installHook {
                pendingInstallStep = nil
                endWaitingForConfigResolution()
                performHookInstall(configDirectory: candidates[0].directory, step: step)
            } else {
                premarkHookStepIfHealthy(in: candidates[0].directory)
            }
        default:
            configDirCandidates = candidates
            // If Install is waiting on this, ask now and resume.
            if let step = pendingInstallStep, step == .installHook {
                pendingInstallStep = nil
                endWaitingForConfigResolution()
                guard let configDirectory = askWhichConfigDirectory() else {
                    return
                }
                resolvedConfigDirectory = configDirectory
                performHookInstall(configDirectory: configDirectory, step: step)
            }
        }
    }

    private func configResolutionFailed() {
        guard pendingInstallStep == .installHook else {
            // The early background kick-off failed and nobody is waiting. Leave
            // resolvedConfigDirectory nil so the next Install click re-resolves
            // (showing the spinner) rather than silently proceeding.
            return
        }
        // The user is waiting on the spinner. Offer to retry rather than install
        // into a guessed location.
        let warning = iTermWarning()
        warning.heading = String(localized: "ClaudeCodeOnboarding.ConfigResolutionFailedTitle", defaultValue: "Couldn\u{2019}t Determine Settings Location", comment: "Title of the alert shown when iTerm2 could not read CLAUDE_CONFIG_DIR from the user\u{2019}s shell")
        warning.title = String(localized: "ClaudeCodeOnboarding.ConfigResolutionFailedBody", defaultValue: "iTerm2 couldn\u{2019}t read CLAUDE_CONFIG_DIR from your shell, so it doesn\u{2019}t know where Claude Code keeps its settings. Try again?", comment: "Body of the alert shown when iTerm2 could not read CLAUDE_CONFIG_DIR from the user\u{2019}s shell")
        warning.actionLabels = [String(localized: "ClaudeCodeOnboarding.Retry", defaultValue: "Retry", comment: "Button to retry resolving the Claude Code settings location"),
                                iTermLocalizedCancel()]
        warning.cancelLabel = iTermLocalizedCancel()
        warning.warningType = .kiTermWarningTypePersistent
        if warning.runModal() == .kiTermWarningSelection0 {
            // Keep the spinner up and pendingInstallStep set; re-run the lookups.
            startResolvingConfigDirectory()
        } else {
            pendingInstallStep = nil
            endWaitingForConfigResolution()
        }
    }

    private func beginWaitingForConfigResolution(step: Step) {
        pendingInstallStep = step
        // In case the early kick-off never ran or failed, start it now. Each lookup resumes only
        // an install waiting on its own step.
        if step == .installRemoteHook {
            MainActor.assumeIsolated {
                startResolvingRemoteConfigDirectory()
            }
        } else {
            startResolvingConfigDirectory()
        }
        // Right-align Cancel where Do It sat, and drop the spinner to its left.
        cancelButton.sizeToFit()
        var cancelFrame = cancelButton.frame
        cancelFrame.size.height = doItButton.frame.height
        cancelFrame.origin.y = doItButton.frame.origin.y
        cancelFrame.origin.x = doItButton.frame.maxX - cancelFrame.size.width
        cancelButton.frame = cancelFrame
        spinner.frame.origin.x = cancelFrame.minX - 28
        spinner.frame.origin.y = doItButton.frame.origin.y + 6
        cancelButton.isHidden = false
        doItButton.isHidden = true
        backButton.isEnabled = false
        nextButton.isEnabled = false
        // Move the keyboard affordances to Cancel: a hidden Do It button can't
        // respond to Return, so clear its key equivalent and let Escape trigger
        // Cancel. endWaitingForConfigResolution's updateUI() restores Do It's.
        doItButton.keyEquivalent = ""
        cancelButton.keyEquivalent = "\u{1b}"  // Escape
        spinner.startAnimation(nil)
    }

    private func endWaitingForConfigResolution() {
        spinner.stopAnimation(nil)
        cancelButton.isHidden = true
        cancelButton.keyEquivalent = ""
        doItButton.isHidden = false
        // updateUI restores the correct Back/Next/Do It enabled + default state,
        // including Do It's Return key equivalent.
        updateUI()
    }

    @objc private func cancelPressed(_ sender: Any?) {
        // Abandon the wait; the lookups may still land later and set
        // resolvedConfigDirectory or configDirCandidates (harmless — no install
        // proceeds because pendingInstallStep is cleared).
        pendingInstallStep = nil
        endWaitingForConfigResolution()
    }

    private func performHookInstall(configDirectory: URL, step: Step) {
        doItButton.isEnabled = false
        Self.installHookFiles(configDirectory: configDirectory) { [weak self] success in
            guard let self else { return }
            self.doItButton.isEnabled = true
            self.finishDoIt(success, step: step)
        }
    }

    // MARK: - Step: Install on Remote Host

    @MainActor
    private var remoteHostIsAlwaysAllowed: Bool {
        return !remoteHost.isEmpty && Conductor.hostGrantStore.grant(forHost: remoteHost) != nil
    }

    @MainActor
    private var remoteHookDescription: String {
        let host = remoteHost
        var text = String(localized: "ClaudeCodeOnboarding.InstallRemoteHookDescription", defaultValue: "Install the Claude Code hook on \(host), so Claude Code running there shows its state (working, waiting, idle) in the Session Status tool too.\n\nThis adds a hook to Claude Code\u{2019}s settings on \(host). It runs the it2 command that SSH Integration keeps up to date on that host.", comment: "Description of the onboarding step that installs the Claude Code hook on a remote host; the value is the host, such as user@example.com")
        if remoteHostIsAlwaysAllowed {
            text += "\n\n" + String(localized: "ClaudeCodeOnboarding.RemoteHostAlreadyAllowed", defaultValue: "\(host) is already always allowed to use the iTerm2 API. You can change that in Settings > General > Magic > API access over ssh.", comment: "Shown in the remote install step when the host already has an always-allow grant; the value is the host")
        }
        return text
    }

    @MainActor
    private func startResolvingRemoteConfigDirectory() {
        guard remoteResolvedDirectory == nil, !remoteResolutionInFlight, let conductor = remoteConductor else {
            return
        }
        remoteResolutionInFlight = true
        Self.resolveRemoteConfigDirectory(conductor: conductor) { [weak self] directory in
            guard let self, Self.instance === self else {
                return
            }
            self.remoteResolutionInFlight = false
            if let directory {
                self.remoteResolvedDirectory = directory
                if self.pendingInstallStep == .installRemoteHook {
                    self.pendingInstallStep = nil
                    self.endWaitingForConfigResolution()
                    self.performRemoteHookInstall(configDirectory: directory, step: .installRemoteHook)
                }
            } else if self.pendingInstallStep == .installRemoteHook {
                self.remoteConfigResolutionFailed()
            }
        }
    }

    @MainActor
    private func remoteConfigResolutionFailed() {
        let alert = NSAlert()
        alert.messageText = String(localized: "ClaudeCodeOnboarding.ConfigResolutionFailedTitle", defaultValue: "Couldn\u{2019}t Determine Settings Location", comment: "Title of the alert shown when iTerm2 could not read CLAUDE_CONFIG_DIR from the user\u{2019}s shell")
        let host = remoteHost
        alert.informativeText = String(localized: "ClaudeCodeOnboarding.RemoteConfigResolutionFailedBody", defaultValue: "iTerm2 couldn\u{2019}t read CLAUDE_CONFIG_DIR from your login shell on \(host), so it doesn\u{2019}t know where Claude Code keeps its settings there. Try again?", comment: "Body of the alert shown when iTerm2 could not read CLAUDE_CONFIG_DIR on a remote host; the value is the host")
        alert.addButton(withTitle: String(localized: "ClaudeCodeOnboarding.Retry", defaultValue: "Retry", comment: "Button to retry resolving the Claude Code settings location"))
        alert.addButton(withTitle: iTermLocalizedCancel())
        if alert.runModal() == .alertFirstButtonReturn {
            startResolvingRemoteConfigDirectory()
        } else {
            pendingInstallStep = nil
            endWaitingForConfigResolution()
        }
    }

    /// Marks the remote step done when the host already has a healthy hook, as the local step is.
    @MainActor
    private func premarkRemoteHookStepIfHealthy() {
        guard let conductor = remoteConductor else {
            return
        }
        Self.remoteHooksHealthy(conductor: conductor) { [weak self] healthy in
            guard let self, Self.instance === self, healthy else {
                return
            }
            DLog("Onboarding: remote hook already healthy; pre-marking the step")
            self.completedSteps.insert(.installRemoteHook)
            self.updateUI()
        }
    }

    private enum AlwaysAllowAnswer {
        case alwaysAllow
        case askEachConnection
        case cancel
    }

    /// Installing the hook does not by itself let the host in: each connection's first hook would
    /// raise the authorization prompt. Always allowing the host avoids that, but means anything on
    /// it can see and control the user's terminal without asking, which nobody would guess from
    /// "install an integration". So it is asked plainly, and nothing grants by default.
    @MainActor
    private func askAboutAlwaysAllow() -> AlwaysAllowAnswer {
        let host = remoteHost
        let alert = NSAlert()
        alert.messageText = String(localized: "ClaudeCodeOnboarding.AlwaysAllowHostTitle", defaultValue: "Always Allow \(host) to Use the iTerm2 API?", comment: "Title of the question asked before installing the Claude Code hook on a remote host; the value is the host")
        alert.informativeText = String(localized: "ClaudeCodeOnboarding.AlwaysAllowHostBody", defaultValue: "Claude Code on \(host) reports its status to iTerm2 through the iTerm2 API.\n\nIf you always allow \(host), any program running as you on that host can see and control your terminal sessions, reading their contents and typing into them, without asking, on this and every future connection.\n\nIf you choose Ask Each Connection, iTerm2 asks the first time Claude Code reports on each new connection.\n\nYou can stop always allowing a host in Settings > General > Magic > API access over ssh.", comment: "Body of the question asked before installing the Claude Code hook on a remote host; the value is the host")
        alert.addButton(withTitle: String(localized: "ClaudeCodeOnboarding.AlwaysAllow", defaultValue: "Always Allow", comment: "Button that installs the remote Claude Code hook and always allows the host to use the iTerm2 API"))
        alert.addButton(withTitle: String(localized: "ClaudeCodeOnboarding.AskEachConnection", defaultValue: "Ask Each Connection", comment: "Button that installs the remote Claude Code hook without always allowing the host; iTerm2 asks on each connection"))
        alert.addButton(withTitle: iTermLocalizedCancel())
        // No default: Return must not grant access, or install without the user reading this.
        alert.buttons[0].keyEquivalent = ""
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .alwaysAllow
        case .alertSecondButtonReturn:
            return .askEachConnection
        default:
            return .cancel
        }
    }

    @MainActor
    private func performRemoteHookInstall(configDirectory: String, step: Step) {
        guard let conductor = remoteConductor, conductor.framing else {
            showRemoteInstallFailure(String(localized: "ClaudeCodeOnboarding.RemoteDisconnected", defaultValue: "The connection to \(remoteHost) has ended. Reconnect and try again.", comment: "Shown when the remote host disconnected before the Claude Code hook could be installed; the value is the host"))
            return
        }
        let grant: Bool
        if remoteHostIsAlwaysAllowed {
            // Already allowed, and the step's text says so. Minting again would only replace it.
            grant = false
        } else {
            switch askAboutAlwaysAllow() {
            case .alwaysAllow:
                grant = true
            case .askEachConnection:
                grant = false
            case .cancel:
                return
            }
        }
        doItButton.isEnabled = false
        Self.installHooksRemotely(conductor: conductor,
                                  configDirectory: configDirectory,
                                  grantAlwaysAllow: grant) { [weak self] result in
            guard let self else {
                return
            }
            self.doItButton.isEnabled = true
            if let message = self.remoteInstallFailureMessage(result, configDirectory: configDirectory) {
                self.showRemoteInstallFailure(message)
                self.finishDoIt(false, step: step)
            } else {
                self.finishDoIt(true, step: step)
            }
        }
    }

    private func remoteInstallFailureMessage(_ result: ClaudeCodeRemoteHooks.InstallResult,
                                             configDirectory: String) -> String? {
        let host = remoteHost
        let path = (configDirectory as NSString).appendingPathComponent("settings.json")
        switch result {
        case .installed:
            return nil
        case .thisMac:
            return String(localized: "ClaudeCodeOnboarding.RemoteIsThisMac", defaultValue: "\(host) is this Mac. Claude Code here is set up by the Install Hook step instead.", comment: "Shown when the remote install was attempted on an ssh connection back to this Mac; the value is the host")
        case .it2Missing:
            return String(localized: "ClaudeCodeOnboarding.RemoteIt2Missing", defaultValue: "SSH Integration couldn\u{2019}t set up the it2 command on \(host), so the hook would have nothing to run. This happens when the login shell there is not one SSH Integration supports: zsh, bash, fish, or xonsh.", comment: "Shown when the remote host lacks the uploaded it2 wrapper; the value is the host")
        case .unreadable:
            return String(localized: "ClaudeCodeOnboarding.RemoteSettingsUnreadable", defaultValue: "iTerm2 couldn\u{2019}t read \(path) on \(host).", comment: "Shown when Claude Code settings on a remote host could not be read; the values are a file path and the host")
        case .malformed:
            return String(localized: "ClaudeCodeOnboarding.RemoteSettingsMalformed", defaultValue: "\(path) on \(host) isn\u{2019}t valid JSON. iTerm2 left it unchanged. Fix or remove it and try again.", comment: "Shown when Claude Code settings on a remote host could not be parsed; the values are a file path and the host")
        case .writeFailed:
            return String(localized: "ClaudeCodeOnboarding.RemoteSettingsWriteFailed", defaultValue: "iTerm2 couldn\u{2019}t write \(path) on \(host).", comment: "Shown when Claude Code settings on a remote host could not be written; the values are a file path and the host")
        }
    }

    private func showRemoteInstallFailure(_ message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "ClaudeCodeOnboarding.FailedToInstallHook", defaultValue: "Failed to install hook", comment: "Title of the alert shown when the Claude Code hook could not be installed")
        alert.informativeText = message
        alert.runModal()
    }

    // MARK: - Step: Enable Python API

    private func doEnablePythonAPI() -> Bool {
        if iTermAPIHelper.isEnabled() {
            return true
        }
        // Prompt the user. If they agree, update the preference and start the server.
        guard iTermAPIHelper.confirmShouldStartServerAndUpdateUserDefaultsForced(true) else {
            return false
        }
        _ = iTermAPIHelper.sharedInstance()
        return iTermAPIHelper.isEnabled()
    }

    // MARK: - Step 1: Install Hook

    // Point a stable cc-status symlink in iTerm2's dot dir
    // (homeDirectoryDotDir — typically ~/.config/iterm2 or ~/.iterm2,
    // honoring preferredBaseDir and the --suite= per-instance suite
    // name) at the cc-status binary inside the currently-running
    // iTerm2.app bundle. Hooks reference the symlink path instead of
    // the bundle path so moving, renaming, or replacing iTerm2.app
    // doesn't break them — the next launch refreshes the target.
    // Idempotent: skips the filesystem update when the symlink already
    // resolves to the right target. Returns the symlink path on
    // success.
    @objc
    @discardableResult
    static func ensureCCStatusSymlink() -> String? {
        // it2 first: the cc-status shim execs the it2 beside it in the bundle, and a new install
        // names it2 directly. Both symlinks are refreshed together so an old hook entry keeps
        // working through the shim while a new one calls it2.
        guard ensureDotDirSymlink(named: "it2") != nil else {
            return nil
        }
        return ensureDotDirSymlink(named: "cc-status")
    }

    /// The hook command a fresh install writes: the dot-dir it2 symlink, quoted, running the
    /// hook subcommand. The symlinks are refreshed on the way.
    static func hookCommandForNewInstalls() -> String? {
        guard ensureCCStatusSymlink() != nil, let it2 = ensureDotDirSymlink(named: "it2") else {
            return nil
        }
        return hookCommand(it2Path: it2)
    }

    /// `"<it2Path>" handle-agent-hook`. Quoted because the dot dir can contain spaces, and the
    /// hook runs through a shell.
    static func hookCommand(it2Path: String) -> String {
        return "\"\(it2Path)\" handle-agent-hook"
    }

    /// Whether a hook entry's command is this instance's hook (see
    /// CCStatusHookCommand.isOwned). `environment` expands `~` and variables in it;
    /// iTerm2's own, which has HOME, unless a caller has the user's shell's.
    static func isOurHookCommand(_ command: String,
                                 environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard let dotDir = FileManager.default.homeDirectoryDotDir() else {
            // With no dot dir there is no such thing as "our" hook, and claiming one would let
            // an uninstall or a directory change delete another instance's entries.
            return false
        }
        return hookCommand(command, belongsToDotDir: dotDir, environment: environment)
    }

    /// Whether a hook entry's command belongs to the instance whose dot dir is `dotDir`.
    ///
    /// Shape alone is not enough. Every iTerm2 writes the same two shapes, differing only in the
    /// dot dir the executable sits in, which is per-suite. Matching on shape made every instance
    /// consider every other instance's hooks its own, so installing from a second instance
    /// stripped the main install's entries out of its settings.json (2026-09-27).
    ///
    /// Pure, so the rule can be tested without a dot dir on disk.
    static func hookCommand(_ command: String,
                            belongsToDotDir dotDir: String,
                            environment: [String: String] = [:]) -> Bool {
        return CCStatusHookCommand.isOwned(command, byDotDir: dotDir, environment: environment)
    }

    /// The directory a just-finished install should strip its own stale hooks from, or nil when
    /// there is nothing to strip.
    ///
    /// Only ever a directory THIS instance recorded. "Nothing recorded" used to mean "assume
    /// ~/.claude", which is how a second instance's first install deleted the main install's
    /// hooks from a directory it had never written to.
    ///
    /// Compares normalized path STRINGS, not URLs: URL equality includes the trailing slash, and
    /// URL(fileURLWithPath:) decides that slash by stat-ing the filesystem, so a first-ever
    /// install would compare "changed" and strip the settings.json it just wrote.
    static func directoryToStrip(afterInstallingInto configDirectory: URL,
                                 recorded: String?) -> URL? {
        guard let recorded, !recorded.isEmpty else {
            return nil
        }
        let previous = URL(fileURLWithPath: recorded)
        guard previous.standardizedFileURL.path != configDirectory.standardizedFileURL.path else {
            return nil
        }
        return previous
    }

    /// Points `<dotdir>/<name>` at the bundled utility of the same name, replacing whatever was
    /// there. Returns the symlink path.
    private static func ensureDotDirSymlink(named name: String) -> String? {
        guard let bundlePath = Bundle.main.path(forResource: "utilities/\(name)",
                                                ofType: nil) else {
            RLog("Onboarding: \(name) not found in bundle")
            return nil
        }
        let fm = FileManager.default
        guard let dotDir = fm.homeDirectoryDotDir() else {
            DLog("Onboarding: no dot dir available for \(name) symlink")
            return nil
        }
        let symlinkURL = URL(fileURLWithPath: dotDir)
            .appendingPathComponent(name)
        let existing = try? fm.destinationOfSymbolicLink(atPath: symlinkURL.path)
        if existing == bundlePath {
            return symlinkURL.path
        }
        // The path may be a regular file or a stale symlink. Either
        // way, remove before recreating.
        if (try? symlinkURL.checkResourceIsReachable()) == true || existing != nil {
            do {
                try fm.removeItem(at: symlinkURL)
            } catch {
                DLog("Onboarding: couldn't remove old \(name) symlink: \(error)")
                return nil
            }
        }
        do {
            try fm.createSymbolicLink(atPath: symlinkURL.path,
                                       withDestinationPath: bundlePath)
        } catch {
            RLog("Onboarding: couldn't create \(name) symlink: \(error)")
            return nil
        }
        DLog("Onboarding: \(name) symlink \(symlinkURL.path) -> \(bundlePath)")
        return symlinkURL.path
    }

    // True iff the cc-status symlink exists and resolves to a file that is
    // still present. The launch-time refresh only re-points the symlink when
    // this launch is a newer version than the last (so an older build never
    // downgrades the deployed cc-status); this lets it also repair a symlink
    // that broke for a version-independent reason — the bundle it pointed at
    // was moved, renamed, or deleted — regardless of version.
    @objc
    static func ccStatusSymlinkIsHealthy() -> Bool {
        let fm = FileManager.default
        guard let dotDir = fm.homeDirectoryDotDir() else {
            return false
        }
        let symlinkPath = (dotDir as NSString).appendingPathComponent("cc-status")
        guard let target = try? fm.destinationOfSymbolicLink(atPath: symlinkPath) else {
            return false
        }
        return fm.fileExists(atPath: target)
    }

    /// Hook event names that cc-status handles.
    // Not private: ClaudeCodeHookOwnershipTests builds a settings.json covering every event
    // the health check requires, and a hand-copied list there would silently rot.
    static let hookEventNames = [
        "UserPromptSubmit",
        "Stop",
        "StopFailure",
        "Notification",
        "PermissionRequest",
        "SessionEnd",
        "PreToolUse",
        "PostToolUse",
        "SessionStart",
        // Keeps the background-task count current between turns: it is
        // the only event that fires when a background subagent finishes
        // while the main loop sits at the prompt.
        "SubagentStop",
    ]

    private static var defaultClaudeConfigDirectory: URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
    }

    // The directory Claude Code's settings.json lives in, as recorded at the
    // last install/reinstall. Claude Code resolves its own settings from
    // $CLAUDE_CONFIG_DIR (defaulting to ~/.claude — the supported way to run
    // separate accounts, e.g. personal vs. work, on one machine). That variable
    // lives in the user's interactive rc files, so reading it requires spawning
    // their shell — expensive and only ever needed to decide WHERE to install.
    // So we resolve it once, at install time (resolveConfigDirectory +
    // recordConfigDirectory below), persist the result, and read it back here
    // synchronously everywhere else. nil until a first install has run, in which
    // case we assume the default; that matches Claude Code's own default and is
    // where a from-scratch install would go.
    private static var claudeConfigDirectory: URL {
        if let path = iTermUserDefaults.claudeCodeConfigDirPath, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return defaultClaudeConfigDirectory
    }

    // Settings.json location for reads (uninstall, health check, menu
    // visibility). Synchronous and main-thread-safe: it never spawns a shell,
    // just reads the directory recorded at the last install.
    static func claudeSettingsURL() -> URL {
        return claudeConfigDirectory.appendingPathComponent("settings.json")
    }

    // Resolve the real $CLAUDE_CONFIG_DIR from the source chosen for the session
    // that opened the installer (ClaudeCodeConfigDirResolver decides which are
    // on offer). Used ONLY at install/reinstall, never for reads. A shell source
    // runs /usr/bin/env by absolute path (so a PATH override/alias/function can't
    // shadow it) in an interactive login shell via iTermSlowOperationGateway, so
    // the user's .zshrc/.bashrc/.profile/etc., where CLAUDE_CONFIG_DIR usually
    // lives, are sourced the way they are for a shell iTerm2 starts in a tab; a
    // bare -c shell would miss it. A running-job source reads the environment
    // the program in the session actually started with and runs nothing.
    //
    // Fully async (completion on the main thread). The install UI shows a spinner
    // with a Cancel button so the user isn't blocked and can give up early. There
    // is no UI-level cutoff, but the XPC service does bound the work: reallyRun
    // ShellScript enforces a 15s wall-clock deadline (SIGTERM/SIGKILL) and the
    // runShellScript watchdog is 20s; both surface here as completion(nil). With a
    // single source the onboarding panel kicks this off as soon as it opens, so by
    // the time the user reaches and clicks Install the answer is usually in hand.
    //
    // completion(nil) means the lookup FAILED (the shell could not be run to
    // completion: the 15s deadline, the 20s watchdog, a crash, or a setup error —
    // all surfaced as nil output). That is distinct from a successful run where
    // CLAUDE_CONFIG_DIR is simply unset, which yields the default directory:
    // `/usr/bin/env` always prints output, so a non-nil result with no
    // CLAUDE_CONFIG_DIR line genuinely means "unset". The caller must NOT persist
    // a guessed directory on failure, or it would install into the wrong place
    // and record it as ground truth.
    //
    // Local sessions only; a host reached through SSH Integration uses
    // resolveRemoteConfigDirectory below.
    private static func resolveConfigDirectory(from source: ClaudeCodeConfigDirResolver.Source,
                                               completion: @escaping (URL?) -> Void) {
        let dependencies = ClaudeCodeConfigDirResolver.Dependencies(
            runInteractiveShell: { shellPath, login, done in
                iTermSlowOperationGateway.sharedInstance().runCommand("/usr/bin/env",
                                                                      inShell: shellPath,
                                                                      mode: login ? .loginInteractive : .interactive,
                                                                      completion: done)
            },
            processEnvironment: { pid in
                iTermLSOF.environment(forProcess: pid)
            },
            homeDirectory: NSHomeDirectory(),
            defaultDirectory: defaultClaudeConfigDirectory)
        ClaudeCodeConfigDirResolver.resolve(source, dependencies: dependencies, completion: completion)
    }

    /// The remote counterpart of resolveConfigDirectory: CLAUDE_CONFIG_DIR as the host's login
    /// shell reports it. Delivers nil, on the main thread, when the lookup failed, in which case
    /// the caller must not guess. Only the login shell from getshell is run; see
    /// ClaudeCodeRemoteConfigDirResolver.
    @MainActor
    static func resolveRemoteConfigDirectory(conductor: Conductor,
                                             completion: @escaping (String?) -> Void) {
        guard conductor.framing else {
            RLog("Remote CLAUDE_CONFIG_DIR lookup failed: the connection is not framing")
            completion(nil)
            return
        }
        let dependencies = ClaudeCodeRemoteConfigDirResolver.Dependencies(
            run: { [weak conductor] commandLine, done in
                // resolve() calls this synchronously, and it is called from here, on main.
                MainActor.assumeIsolated {
                    guard let conductor else {
                        done(Data(), -1)
                        return
                    }
                    conductor.runRemoteCommand(commandLine) { data, status in
                        DispatchQueue.main.async {
                            done(data, status)
                        }
                    }
                }
            },
            after: { seconds, block in
                let box = MainQueueBlock(block)
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                    box.block()
                }
            },
            makeSentinel: {
                String.makeSecureHexString(byteCount: 16) ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
            })
        ClaudeCodeRemoteConfigDirResolver.resolve(shell: conductor.shell,
                                                  home: conductor.homeDirectory,
                                                  dependencies: dependencies,
                                                  completion: completion)
    }

    /// Whether THIS instance's hooks are healthy in the directory the given session's agent will
    /// actually read. Answers on the main thread.
    ///
    /// Replaces consulting `hooksAlreadyInstalled()`, a flag reconciled at launch from whatever
    /// settings.json sat at the recorded-or-default directory. On 2026-09-27 that was ~/.claude,
    /// holding another iTerm2's entries, so the flag read true, the installer never opened, the
    /// API server stayed off and no hook ever ran. Two things fix that: the entries there are no
    /// longer counted as ours (see hookCommand(_:belongsToDotDir:)), and the answer now comes
    /// from disk rather than a cache.
    ///
    /// Deliberately the cheap resolution only. When the session's foreground job is the agent,
    /// its own environment is read from the kernel, which spawns nothing; otherwise the recorded
    /// directory is used. No shell is ever run: this answers a background question raised by an
    /// announcement, not an install, so it must not cost a shell startup or ask the user anything.
    ///
    /// For a session on a host reached through SSH Integration the answer is about that host's
    /// hook, read over the connection.
    static func hooksHealthyForSession(_ session: PTYSession?,
                                       completion: @escaping (Bool) -> Void) {
        // A session on a host reached through SSH Integration runs claude there, so it is that
        // host's hook that matters. A connection back to this Mac is answered by the local check.
        // Callers are on the main thread.
        if let conductor = MainActor.assumeIsolated({ session?.hostConductor.flatMap { $0.framing ? $0 : nil } }) {
            MainActor.assumeIsolated {
                remoteHostIsThisMac(conductor: conductor) { isThisMac in
                    if isThisMac {
                        localHooksHealthyForSession(session, completion: completion)
                    } else {
                        remoteHooksHealthy(conductor: conductor, completion: completion)
                    }
                }
            }
            return
        }
        localHooksHealthyForSession(session, completion: completion)
    }

    private static func localHooksHealthyForSession(_ session: PTYSession?,
                                                    completion: @escaping (Bool) -> Void) {
        let checkDisk = { (settingsURL: URL) in
            // Reads disk and follows symlinks, so keep it off the main thread.
            DispatchQueue.global(qos: .userInitiated).async {
                let healthy = hooksHealthyOnDisk(settingsURL: settingsURL)
                DispatchQueue.main.async {
                    completion(healthy)
                }
            }
        }
        guard let job = agentJob(for: session) else {
            checkDisk(claudeSettingsURL())
            return
        }
        resolveConfigDirectory(from: .runningJob(job)) { directory in
            guard let directory else {
                // The kernel hides a platform binary's environment from other processes, and an
                // agent that simply has no CLAUDE_CONFIG_DIR also answers empty. Either way this
                // is "cannot tell from the process", so fall back rather than guess.
                checkDisk(claudeSettingsURL())
                return
            }
            checkDisk(directory.appendingPathComponent("settings.json"))
        }
    }

    /// The session's foreground job when it is the agent whose environment the hook install is
    /// for, or nil. Only the agent qualifies: a shell's exec-time environment predates its rc
    /// files, so it would answer for a state the user never saw.
    private static func agentJob(for session: PTYSession?) -> ClaudeCodeConfigDirResolver.RunningJob? {
        guard let session,
              let pid = session.genericScope.value(forVariableName: iTermVariableKeySessionJobPid) as? NSNumber,
              pid.int32Value > 0,
              let name = session.genericScope.value(forVariableName: iTermVariableKeySessionJob) as? String,
              ClaudeCodeConfigDirResolver.agentJobNames.contains(name) else {
            return nil
        }
        return ClaudeCodeConfigDirResolver.RunningJob(pid: pid.int32Value, name: name)
    }

    // The shells (or the already-running program) that could have exported
    // CLAUDE_CONFIG_DIR for this session. No session, or a profile that runs the
    // login shell, means just the login shell, as always.
    private static func configDirSources(for session: PTYSession?) -> [ClaudeCodeConfigDirResolver.Source] {
        let loginShell = iTermOpenDirectory.userShell() ?? "/bin/bash"
        guard let session, let profile = session.profile else {
            return ClaudeCodeConfigDirResolver.sources(loginShell: loginShell, profile: [:], runningJob: nil)
        }
        var runningJob: ClaudeCodeConfigDirResolver.RunningJob?
        if let pid = session.genericScope.value(forVariableName: iTermVariableKeySessionJobPid) as? NSNumber,
           pid.int32Value > 0 {
            let name = session.genericScope.value(forVariableName: iTermVariableKeySessionJob) as? String ?? ""
            runningJob = ClaudeCodeConfigDirResolver.RunningJob(pid: pid.int32Value, name: name)
        }
        return ClaudeCodeConfigDirResolver.sources(loginShell: loginShell,
                                                   profile: profile,
                                                   runningJob: runningJob)
    }

    // Modal question for a session whose shells disagree about CLAUDE_CONFIG_DIR:
    // which directory should the hook be installed into? The buttons are the
    // directories; the body says which shell (or program) reported each. A
    // remote source, when one exists, must name its host in its sentence. nil
    // on Cancel.
    private func askWhichConfigDirectory() -> URL? {
        guard configDirCandidates.count > 1 else {
            return configDirCandidates.first?.directory
        }
        let warning = iTermWarning()
        warning.heading = String(localized: "ClaudeCodeOnboarding.WhichConfigDirTitle", defaultValue: "Which Settings Location Should the Claude Code Hook Be Installed In?", comment: "Title of the question asked when the shells that could start claude in this session report different CLAUDE_CONFIG_DIR values")
        var lines: [String] = []
        for candidate in configDirCandidates {
            let directory = (candidate.directory.path as NSString).abbreviatingWithTildeInPath
            for source in candidate.sources {
                switch source {
                case .loginShell(let path):
                    lines.append(String(localized: "ClaudeCodeOnboarding.ConfigDirFromLoginShell", defaultValue: "\(directory) is what your login shell, \(path), reports.", comment: "One line of the settings-location question; the first value is a directory, the second the path of the login shell that reported it"))
                case .profileShell(let path):
                    lines.append(String(localized: "ClaudeCodeOnboarding.ConfigDirFromProfileShell", defaultValue: "\(directory) is what this session\u{2019}s shell, \(path), reports.", comment: "One line of the settings-location question; the first value is a directory, the second the path of the shell the session\u{2019}s profile runs"))
                case .runningJob(let job):
                    lines.append(String(localized: "ClaudeCodeOnboarding.ConfigDirFromRunningJob", defaultValue: "\(directory) is what \(job.name), running in this session now, was started with.", comment: "One line of the settings-location question; the first value is a directory, the second the name of the program running in the session"))
                }
            }
        }
        warning.title = lines.joined(separator: "\n")
        // At most one directory per source (login shell, profile shell, running program), so
        // these and Cancel fit in iTermWarning's seven actions.
        warning.actionLabels = configDirCandidates.map {
            ($0.directory.path as NSString).abbreviatingWithTildeInPath
        } + [iTermLocalizedCancel()]
        warning.cancelLabel = iTermLocalizedCancel()
        warning.warningType = .kiTermWarningTypePersistent
        let index = warning.runModal().rawValue
        guard index >= 0, index < configDirCandidates.count else {
            DLog("Onboarding: config dir question cancelled")
            return nil
        }
        DLog("Onboarding: config dir chosen: \(configDirCandidates[index].directory.path)")
        return configDirCandidates[index].directory
    }

    // Persist the directory we installed into so every later read
    // (claudeConfigDirectory) returns it without spawning a shell.
    private static func recordConfigDirectory(_ url: URL) {
        iTermUserDefaults.claudeCodeConfigDirPath = url.path
    }

    // Extract CLAUDE_CONFIG_DIR from `/usr/bin/env` output (newline-separated
    // KEY=VALUE lines). A value containing an embedded newline would split
    // incorrectly — an accepted limitation shared with it2ssh's own env-report
    // parsing (terminalUpdateEnv).
    // internal (not private) for unit testing via @testable import.
    static func parseCLAUDE_CONFIG_DIR(from output: String) -> String? {
        return parseVariable("CLAUDE_CONFIG_DIR", from: output)
    }

    static func parseVariable(_ name: String, from output: String) -> String? {
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<equals])
            guard key == name else { continue }
            return String(line[line.index(after: equals)...])
        }
        return nil
    }

    private func claudeSessionGUIDs() -> Set<String> {
        // Prefer ClaudeWatcher if running, otherwise query GlobalJobMonitor directly.
        if let watcher = ClaudeWatcher.instance, !watcher.sessionIDs.isEmpty {
            return watcher.sessionIDs
        }
        return GlobalJobMonitor.instance.sessionGUIDs(runningJob: "claude")
    }

    private func claudeSessions() -> [PTYSession] {
        let actual = claudeSessionGUIDs().compactMap { guid in
            iTermController.sharedInstance()?.session(withGUID: guid)
        }
        if actual.isEmpty,
           let currentSession = iTermController.sharedInstance()?.currentTerminal?.currentSession() {
            return [currentSession]
        }
        return actual
    }

    // Writes the cc-status symlink and merges our hooks into
    // configDirectory/settings.json on a background queue (local file I/O, which
    // can block on a network-mounted home), then persists configDirectory and
    // reports back on the main thread. configDirectory has already been resolved
    // (resolveConfigDirectory) before this is called, so there is no shell spawn
    // here.
    //
    // Existing cc-status hook commands are judged in the same environment the
    // health check uses (withHookEnvironment), so a command the health check
    // calls broken is one Reinstall replaces.
    private static func installHookFiles(configDirectory: URL, completion: @escaping (Bool) -> Void) {
        let queue = DispatchQueue.global(qos: .userInitiated)
        queue.async {
            let settingsURL = configDirectory.appendingPathComponent("settings.json")
            let settings = loadSettings(at: settingsURL) ?? [:]
            withHookEnvironment(for: settings, queue: queue) { environment in
                installHookFilesOnBackgroundQueue(configDirectory: configDirectory,
                                                  environment: environment,
                                                  completion: completion)
            }
        }
    }

    // The alert body for a failed merge, or nil on success.
    private static func installFailureDetail(_ result: ClaudeCodeInstallHooksResult,
                                             settingsPath: String) -> String? {
        switch result {
        case .success:
            return nil
        case .unreadable:
            return String(localized: "ClaudeCodeOnboarding.SettingsUnreadable", defaultValue: "iTerm2 couldn\u{2019}t read \(settingsPath), so it left the file unchanged. Check the file\u{2019}s permissions and try again.", comment: "Body of the alert shown when installing the Claude Code hook fails because settings.json exists but could not be read; the interpolated value is the absolute path to settings.json")
        case .malformed:
            return String(localized: "ClaudeCodeOnboarding.SettingsMalformed", defaultValue: "\(settingsPath) has a syntax error or isn\u{2019}t a JSON object, so iTerm2 left it unchanged to avoid losing your other Claude Code settings. Fix the file in a text editor, or remove it, and then try again.", comment: "Body of the alert shown when installing the Claude Code hook fails because settings.json is not valid JSON or is not a JSON object; the interpolated value is the absolute path to settings.json")
        case .writeFailed(let description):
            return String(localized: "ClaudeCodeOnboarding.FailedToWriteSettings", defaultValue: "Could not write to \(settingsPath): \(description)", comment: "Body of the alert shown when settings.json could not be written; first interpolation is a file path, second is an error description")
        }
    }

    // The hooks dictionary with the hook running once for every event in
    // hookEventNames. The first existing entry of ours for an event is kept,
    // rewritten to `command`, or left beside a new entry, as
    // existingHookAction decides: a previously installed hook may point at a
    // stale dot dir (a `-suite` instance wrote ~/.config/iterm2-alt4/cc-status
    // and we're now reinstalling from the default instance), while one the user
    // wrote is kept if it can run. Further entries that only run the hook are
    // removed, since two instances installing into one file could each have
    // added one and Claude Code would run the hook once per entry; one that
    // also runs something of the user's is left. A group emptied by that
    // cleanup is dropped. Foreign entries are left alone.
    // internal (not private) for unit testing via @testable import.
    static func mergedHooks(_ existing: [String: Any],
                            command: String,
                            environment: [String: String] = [:],
                            isExecutable: @escaping (String) -> Bool = {
                                FileManager.default.isExecutableFile(atPath: $0)
                            }) -> [String: Any] {
        // Another instance's entries are foreign: left alone, and not duplicates of ours.
        let ownership = environment.isEmpty ? ProcessInfo.processInfo.environment : environment
        return ClaudeCodeHookSettings.merged(existing,
                                             command: command,
                                             descriptor: .claudeCode,
                                             isOurs: { Self.isOurHookCommand($0, environment: ownership) },
                                             action: { existingCommand in
            switch existingHookAction(existingCommand,
                                      ccStatusPath: command,
                                      environment: environment,
                                      isExecutable: isExecutable) {
            case .keep:
                return .keep
            case .rewrite:
                return .rewrite
            case .addAlongside:
                return .addAlongside
            }
        })
    }

    // Merge our hook for every event in hookEventNames into the
    // settings.json at settingsURL, creating the file (and its directory) when
    // it doesn't exist. An existing file that can't be read, or doesn't parse
    // as a JSON object, is never written: replacing it would throw away every
    // other setting the user has in it.
    // internal (not private) for unit testing via @testable import.
    static func mergeCCStatusHooks(intoSettingsURL settingsURL: URL,
                                   ccStatusPath: String,
                                   environment: [String: String]) -> ClaudeCodeInstallHooksResult {
        // Read existing settings, or start with an empty object when there is
        // no file. A dangling symlink counts as no file, as in
        // stripCCStatusHooks.
        var settings: [String: Any]
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let data: Data
            do {
                data = try Data(contentsOf: settingsURL)
            } catch {
                RLog("Onboarding: couldn't read settings.json, leaving it alone: \(error)")
                return .unreadable
            }
            let parsed: Any
            do {
                // An empty or whitespace-only file holds nothing to lose, but
                // JSONSerialization rejects it, so treat it as an empty object.
                let blank = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty ?? false
                parsed = blank ? [String: Any]() : try JSONSerialization.jsonObject(with: data)
            } catch {
                RLog("Onboarding: settings.json isn't valid JSON, leaving it alone: \(error)")
                return .malformed
            }
            guard let object = parsed as? [String: Any] else {
                RLog("Onboarding: settings.json root isn't a JSON object, leaving it alone")
                return .malformed
            }
            settings = object
            DLog("Onboarding: loaded existing settings.json")
        } else {
            settings = [:]
            DLog("Onboarding: no settings.json; starting with empty settings")
        }

        settings["hooks"] = Self.mergedHooks((settings["hooks"] as? [String: Any]) ?? [:],
                                             command: ccStatusPath,
                                             environment: environment)

        // Write settings back.
        do {
            // Ensure ~/.claude directory exists.
            let claudeDir = settingsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: claudeDir,
                                                    withIntermediateDirectories: true)

            let data = try JSONSerialization.data(withJSONObject: settings,
                                                  options: [.prettyPrinted, .sortedKeys])
            try writeSettings(data, to: settingsURL)
            DLog("Onboarding: wrote settings.json")
            return .success
        } catch {
            RLog("Onboarding: failed to write settings.json: \(error)")
            return .writeFailed(description: error.localizedDescription)
        }
    }

    private static func installHookFilesOnBackgroundQueue(configDirectory: URL,
                                                          environment: [String: String],
                                                          completion: @escaping (Bool) -> Void) {
        guard let ccStatusPath = Self.hookCommandForNewInstalls() else {
            RLog("Onboarding: couldn't prepare the hook symlinks")
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        DLog("Onboarding: hook command will be \(ccStatusPath)")

        let settingsURL = configDirectory.appendingPathComponent("settings.json")
        let mergeResult = mergeCCStatusHooks(intoSettingsURL: settingsURL,
                                             ccStatusPath: ccStatusPath,
                                             environment: environment)
        if let detail = installFailureDetail(mergeResult, settingsPath: settingsURL.path) {
            DispatchQueue.main.async {
                let warning = iTermWarning()
                warning.heading = String(localized: "ClaudeCodeOnboarding.FailedToInstallHook", defaultValue: "Failed to install hook", comment: "Title of the alert shown when the Claude Code hook could not be installed")
                warning.title = detail
                warning.actionLabels = [iTermLocalizedOK()]
                warning.warningType = .kiTermWarningTypePersistent
                warning.runModal()
                completion(false)
            }
            return
        }

        // Only now that the new settings.json is safely written do we strip our
        // hook from a DIFFERENT directory we installed into last time, so it
        // stops firing from a file no read path will look at again. Doing this
        // after the write (not before) means a failed write above can't leave
        // the user with the hook removed from the old location and not installed
        // in the new one. Only a directory this instance recorded counts (see
        // directoryToStrip), and one that is the same directory or settings file
        // under another name is left alone (see stripStaleCCStatusHooks). Best
        // effort: a missing file is fine and we don't fail the install if the
        // strip fails.
        if let previousDirectory = Self.directoryToStrip(afterInstallingInto: configDirectory,
                                                         recorded: iTermUserDefaults.claudeCodeConfigDirPath) {
            stripStaleCCStatusHooks(previousDirectory: previousDirectory,
                                    newConfigDirectory: configDirectory)
        }

        DispatchQueue.main.async {
            // Record where we installed so all later reads (uninstall, health
            // check, menu visibility) find settings.json without spawning a shell.
            recordConfigDirectory(configDirectory)
            iTermUserDefaults.claudeCodeHooksInstalled = true
            // Sticky "user once completed setup" flag, distinct from the
            // disk-reconciled cache above. Drives broken-install detection
            // when something else (Claude Code itself, hand edits) strips
            // our hook out of settings.json after the fact. Only the
            // Uninstall menu flow clears it.
            iTermUserDefaults.claudeCodeIntegrationCompleted = true
            RLog("Onboarding: hook install complete")
            completion(true)
        }
    }

    // Strip our hook from previousDirectory's settings.json, unless that is
    // the settings.json Install just wrote into newConfigDirectory. Returns
    // whether it stripped.
    //
    // "Same" is decided by file identity, not by path: ~/.claude and a
    // $CLAUDE_CONFIG_DIR of ~/dotfiles/claude are one directory when ~/.claude
    // is a link to it, as are ~/.claude and ~/.Claude on a case-insensitive
    // volume. Stripping the "old" file in those cases removes the hook Install
    // just wrote (QA F-274). The settings.json files are compared too, since
    // two distinct directories can hold links to one settings file.
    // internal (not private) for unit testing via @testable import.
    @discardableResult
    static func stripStaleCCStatusHooks(previousDirectory: URL,
                                        newConfigDirectory: URL) -> Bool {
        if pathsNameSameItem(previousDirectory, newConfigDirectory) {
            return false
        }
        let oldSettingsURL = previousDirectory.appendingPathComponent("settings.json")
        let newSettingsURL = newConfigDirectory.appendingPathComponent("settings.json")
        if pathsNameSameItem(oldSettingsURL, newSettingsURL) {
            DLog("Onboarding: \(oldSettingsURL.path) is the settings.json just written; not stripping")
            return false
        }
        DLog("Onboarding: install dir changed; stripping stale hook from \(oldSettingsURL.path)")
        stripCCStatusHooks(fromSettingsURL: oldSettingsURL)
        return true
    }

    // Whether two paths name the same file or directory. When both exist this
    // compares device and inode (stat follows links), which handles symlinks,
    // case variants, and spelling differences such as a trailing slash. When
    // either can't be stat-ed, fall back to comparing the paths with links
    // resolved, ignoring case only if the volume is case-insensitive.
    private static func pathsNameSameItem(_ a: URL, _ b: URL) -> Bool {
        if let idA = fileIdentity(a), let idB = fileIdentity(b) {
            return idA == idB
        }
        let pathA = a.standardizedFileURL.resolvingSymlinksInPath().path
        let pathB = b.standardizedFileURL.resolvingSymlinksInPath().path
        if pathA == pathB {
            return true
        }
        guard pathA.caseInsensitiveCompare(pathB) == .orderedSame else {
            return false
        }
        return !volumeIsCaseSensitive(containing: URL(fileURLWithPath: pathA))
    }

    private struct FileIdentity: Equatable {
        var device: dev_t
        var inode: ino_t
    }

    private static func fileIdentity(_ url: URL) -> FileIdentity? {
        var info = stat()
        guard stat(url.path, &info) == 0 else {
            return nil
        }
        return FileIdentity(device: info.st_dev, inode: info.st_ino)
    }

    // Case sensitivity of the volume holding url, judged from its nearest
    // existing ancestor. Assumes case-sensitive when unknown, so an unknown
    // volume never makes two differently cased paths look the same.
    private static func volumeIsCaseSensitive(containing url: URL) -> Bool {
        var candidate = url
        while true {
            if let values = try? candidate.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]),
               let caseSensitive = values.volumeSupportsCaseSensitiveNames {
                return caseSensitive
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return true
            }
            candidate = parent
        }
    }

    enum ExistingHookAction: Equatable {
        /// The command runs cc-status, or might. It counts as our hook.
        case keep
        /// Replace the command with ccStatusPath.
        case rewrite
        /// The command can't run cc-status, but it runs something of the
        /// user's too. Leave it and add an entry for ccStatusPath beside it.
        case addAlongside
    }

    // What reinstalling does with an existing hook command that refers to
    // cc-status. A plain absolute path is the form the installer writes, so it
    // is updated whenever it differs; this corrects a hook left pointing at
    // another dot dir (for example a `-suite` instance wrote
    // ~/.config/iterm2-alt4/cc-status and we're now reinstalling from the
    // default instance that wants ~/.config/iterm2/cc-status). Anything else
    // was written by the user, such as $HOME/.config/iterm2/cc-status for a
    // settings.json shared between Macs, or a wrapper that tolerates a
    // missing cc-status (issue 13099). Those are kept unless every reference
    // to cc-status resolves to a path that isn't executable, which means the
    // hook can't work. Even then, a command that also runs something else
    // (`~/gone/cc-status; notify`) isn't replaced, since that would drop the
    // rest of it.
    // internal (not private) for unit testing via @testable import.
    static func existingHookAction(_ command: String,
                                   ccStatusPath: String,
                                   environment: [String: String],
                                   isExecutable: (String) -> Bool = {
                                       FileManager.default.isExecutableFile(atPath: $0)
                                   }) -> ExistingHookAction {
        guard command != ccStatusPath else {
            return .keep
        }
        if CCStatusHookCommand.isInstallerForm(command) {
            return .rewrite
        }
        let resolutions = CCStatusHookCommand.resolutions(of: command,
                                                          environment: environment,
                                                          isExecutable: isExecutable)
        let broken = !resolutions.isEmpty && resolutions.allSatisfy { resolution in
            if case .notExecutable = resolution {
                return true
            }
            return false
        }
        guard broken else {
            return .keep
        }
        return CCStatusHookCommand.runsOnlyCCStatus(command) ? .rewrite : .addAlongside
    }

    // MARK: - Step: Install Workgroup

    private func doInstallWorkgroup() -> Bool {
        Self.installWorkgroupIfNeeded()
        return true
    }

    // MARK: - Step: Install Triggers

    // Two flavors of "orphan": sessions whose authoritative profile
    // is gone and so cannot be reached by the normal sharedInstance
    // -> reloadProfile path.
    //
    //   Divorced orphan: session.isDivorced is true and the divorced
    //     profile's KEY_ORIGINAL_GUID is missing from sharedInstance.
    //     A bookmark already exists in sessionsInstance, so we can
    //     write triggers to it directly.
    //
    //   Non-divorced orphan: session.isDivorced is false and
    //     session.profile's KEY_GUID is missing from sharedInstance
    //     (the user deleted the source profile after the session was
    //     created). There is no sessionsInstance bookmark yet, so to
    //     write triggers we must first call
    //     divorceAddressBookEntryFromPreferences to create one.
    private struct OrphanScan {
        // Divorced GUIDs (KEY_GUID of the divorced profile) for
        // already-divorced orphans. These come from
        // sessionsInstance.bookmarks() and from live/buried divorced
        // sessions; the two sources usually overlap so we dedupe.
        var divorcedOrphanGuids = Set<String>()
        // Non-divorced sessions whose profile GUID is missing from
        // sharedInstance. Need to be divorced before triggers can be
        // written.
        var nonDivorcedOrphanSessions: [PTYSession] = []
        // Total count of unique sessions affected, for the checkbox
        // label.
        var sessionCount: Int {
            divorcedOrphanGuids.count + nonDivorcedOrphanSessions.count
        }
    }

    private static func scanOrphans() -> OrphanScan {
        var result = OrphanScan()
        guard let sharedModel = ProfileModel.sharedInstance() else {
            DLog("Onboarding: orphan scan: sharedInstance is nil")
            return result
        }
        let sharedGuids = Set(sharedModel.bookmarks().compactMap { $0[KEY_GUID] as? String })
        DLog("Onboarding: orphan scan: sharedInstance has \(sharedGuids.count) GUIDs")
        // Only count live and buried sessions. sessionsInstance can
        // hold stale divorced bookmarks for sessions that have since
        // been closed, and those would inflate the count without
        // actually corresponding to anything the user can see.
        let liveSessions =
            iTermController.sharedInstance()?.allSessions() ?? []
        let buriedSessions =
            iTermBuriedSessions.sharedInstance()?.buriedSessions() ?? []
        DLog("Onboarding: orphan scan: \(liveSessions.count) live + \(buriedSessions.count) buried sessions")
        for session in liveSessions + buriedSessions {
            let profileGuidStr = (session.profile?[KEY_GUID] as? String) ?? "<nil>"
            let originalGuidStr = (session.originalProfile?[KEY_GUID] as? String) ?? "<nil>"
            let name = (session.profile?[KEY_NAME] as? String) ?? "?"
            if session.isDivorced {
                guard let originalGuid = session.originalProfile?[KEY_GUID] as? String,
                      let divorcedGuid = session.profile?[KEY_GUID] as? String else {
                    DLog("Onboarding: orphan scan: skip divorced session=\(session) name=\(name) (missing key) profileGUID=\(profileGuidStr) originalGUID=\(originalGuidStr)")
                    continue
                }
                if sharedGuids.contains(originalGuid) {
                    DLog("Onboarding: orphan scan: not-orphan divorced session=\(session) name=\(name) divorcedGUID=\(divorcedGuid) originalGUID=\(originalGuid)")
                    continue
                }
                DLog("Onboarding: orphan scan: ORPHAN(divorced-live) session=\(session) name=\(name) divorcedGUID=\(divorcedGuid) originalGUID=\(originalGuid)")
                result.divorcedOrphanGuids.insert(divorcedGuid)
            } else {
                guard let profileGuid = session.profile?[KEY_GUID] as? String else {
                    DLog("Onboarding: orphan scan: skip non-divorced session=\(session) name=\(name) (missing profile GUID)")
                    continue
                }
                if sharedGuids.contains(profileGuid) {
                    DLog("Onboarding: orphan scan: not-orphan non-divorced session=\(session) name=\(name) profileGUID=\(profileGuid)")
                    continue
                }
                DLog("Onboarding: orphan scan: ORPHAN(non-divorced) session=\(session) name=\(name) profileGUID=\(profileGuid)")
                result.nonDivorcedOrphanSessions.append(session)
            }
        }
        DLog("Onboarding: orphan scan complete: divorcedOrphanGuids=\(result.divorcedOrphanGuids.count) nonDivorcedOrphanSessions=\(result.nonDivorcedOrphanSessions.count)")
        return result
    }

    // Show a modal asking which profiles should receive the Enter/Exit
    // workgroup triggers, all selected by default. Returns false if
    // the user cancels (so the installer step doesn't tick over to
    // ✅). Dynamic profiles in the selection prompt a second warning:
    // we *can* write to them, but only if they're marked rewritable —
    // otherwise the dynamic profile manager regenerates them from
    // disk and our triggers vanish. Same pattern as
    // ProfilePreferencesViewController.showDynamicProfileWarning.
    private func doInstallTriggers() -> Bool {
        guard let enter = Self.makeEnterWorkgroupTrigger(),
              let exit = Self.makeExitWorkgroupTrigger() else {
            RLog("Onboarding: failed to construct trigger objects")
            return false
        }
        let listWidth: CGFloat = 360
        let listHeight: CGFloat = 240
        guard let listView = ProfileListView(
            frame: NSRect(x: 0, y: 0, width: listWidth, height: listHeight),
            model: ProfileModel.sharedInstance(),
            font: nil,
            profileTypes: .terminal) else {
            return false
        }
        listView.disableArrowHandler()
        listView.allowMultipleSelections()

        // Offer to also update orphan sessions: running sessions
        // whose source profile is missing from sharedInstance (the
        // user deleted the profile after spawning the session, or an
        // arrangement was restored without the original). They can't
        // appear in the picker above, so without this checkbox the
        // user has no way to opt them in. Default on so the obvious
        // behavior happens without the user thinking about it.
        let orphanCheckbox: NSButton?
        let accessoryView: NSView
        let orphanScan = Self.scanOrphans()
        let orphanCount = orphanScan.sessionCount
        if orphanCount > 0 {
            let title = String(localized: "ClaudeOnboarding.AlsoUpdateOrphanSessions", defaultValue: "Also update \(orphanCount) sessions whose profiles are missing", comment: "Checkbox to also update sessions whose profiles are missing; %lld is the count")
            let checkbox = NSButton(
                checkboxWithTitle: title,
                target: nil,
                action: nil)
            checkbox.toolTip = String(localized: "ClaudeCodeOnboarding.OrphanSessionsTooltip", defaultValue: "Includes running sessions that were created from a profile that has since been deleted.", comment: "Tooltip explaining the checkbox that also updates orphaned sessions")
            checkbox.state = .on
            checkbox.translatesAutoresizingMaskIntoConstraints = true
            checkbox.sizeToFit()
            let checkboxHeight = checkbox.frame.height
            let spacing: CGFloat = 8
            let container = NSView(frame: NSRect(
                x: 0,
                y: 0,
                width: listWidth,
                height: listHeight + spacing + checkboxHeight))
            listView.frame = NSRect(
                x: 0,
                y: checkboxHeight + spacing,
                width: listWidth,
                height: listHeight)
            checkbox.frame = NSRect(
                x: 0,
                y: 0,
                width: max(listWidth, checkbox.frame.width),
                height: checkboxHeight)
            container.addSubview(listView)
            container.addSubview(checkbox)
            orphanCheckbox = checkbox
            accessoryView = container
        } else {
            orphanCheckbox = nil
            accessoryView = listView
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "ClaudeCodeOnboarding.InstallTriggersTitle", defaultValue: "Install Auto-Enter Triggers", comment: "Title of the alert asking which profiles to add auto-enter triggers to")
        alert.informativeText = String(localized: "ClaudeCodeOnboarding.InstallTriggersBody", defaultValue: "Pick the profiles you\u{2019}ll run claude in. We\u{2019}ll add Enter/Exit Workgroup triggers to each one so the Claude Code workgroup is entered automatically.", comment: "Body of the alert asking which profiles to add auto-enter triggers to")
        alert.addButton(withTitle: String(localized: "ClaudeCodeOnboarding.Install", defaultValue: "Install", comment: "Button that installs the integration step"))
        alert.addButton(withTitle: iTermLocalizedCancel())
        alert.accessoryView = accessoryView

        // Pre-select every visible row so the default action is "all
        // profiles" and the user just deselects anything they don't
        // want to touch. reloadData first because the table view is
        // lazy: numberOfRows reads 0 until the table has been asked
        // to draw, which only happens after the alert is on screen —
        // by then it's too late to seed the selection.
        listView.reloadData()
        if let table = listView.tableView(), table.numberOfRows > 0 {
            table.selectRowIndexes(
                IndexSet(integersIn: 0..<table.numberOfRows),
                byExtendingSelection: false)
        }

        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }
        let selectedGuids = listView.selectedGuids ?? []
        DLog("Onboarding: trigger picker selected \(selectedGuids.count) profile(s)")
        guard let model = ProfileModel.sharedInstance() else {
            return false
        }

        // Bucket the selection. Non-dynamic profiles install with no
        // warning; dynamic-rewritable profiles install (the user
        // already opted into editing those); dynamic-non-rewritable
        // profiles need confirmation.
        var guidsToInstall = Set<String>()
        var nonRewritableDynamic: [(guid: String, name: String)] = []
        for profile in model.bookmarks() {
            guard let guid = profile[KEY_GUID] as? String,
                  selectedGuids.contains(guid) else { continue }
            if !Self.profileIsDynamic(profile) {
                guidsToInstall.insert(guid)
                continue
            }
            if iTermProfilePreferences.bool(forKey: KEY_DYNAMIC_PROFILE_REWRITABLE,
                                            inProfile: profile) {
                guidsToInstall.insert(guid)
                continue
            }
            let name = (profile[KEY_NAME] as? String) ?? String(localized: "ClaudeCodeOnboarding.UnknownProfileName", defaultValue: "(unknown)", comment: "Fallback name for a profile with no name")
            nonRewritableDynamic.append((guid, name))
        }

        if !nonRewritableDynamic.isEmpty {
            switch promptForDynamicProfileAction(profiles: nonRewritableDynamic) {
            case .markRewritableAndInstall:
                if let manager = iTermDynamicProfileManager.sharedInstance() {
                    for (guid, _) in nonRewritableDynamic {
                        manager.markProfileRewritable(withGuid: guid)
                        guidsToInstall.insert(guid)
                    }
                }
            case .skipDynamic:
                break
            case .cancel:
                return false
            }
        }

        DLog("Onboarding: guidsToInstall = \(guidsToInstall)")
        if let shared = ProfileModel.sharedInstance() {
            for guid in guidsToInstall {
                Self.addClaudeWorkgroupTriggers([enter, exit], toProfileWithGUID: guid, in: shared)
            }
        }
        // Push the same triggers into divorced session profiles
        // whose canonical parent the user picked. Without this, an
        // already-running divorced session keeps the old (trigger-
        // less) profile snapshot — install would silently fail to
        // affect anyone currently working in that session. Mirrors
        // uninstall, which already walks sessionsInstance.
        // TriggerController.add(_:toProfileWithGUID:) only walks
        // sharedInstance, so use the in-model overload here.
        //
        // Use two sources for the match: the dict in
        // ProfileModel.sessionsInstance() (KEY_ORIGINAL_GUID) AND
        // the live session's originalProfile reference. The latter
        // is the runtime authority set at divorce time and survives
        // arrangement reloads that would otherwise leave the dict's
        // KEY_ORIGINAL_GUID stale relative to what the session
        // actually merges from. Dedupe by divorced GUID so a
        // session present in both sources only gets written once;
        // TriggerController.add also dedupes the trigger payload,
        // so a repeated write would be a no-op anyway.
        if let sessions = ProfileModel.sessionsInstance() {
            // A divorced session whose original GUID still exists in
            // sharedInstance is "adopted" by that shared profile. We
            // only push triggers into it if the user picked its parent.
            //
            // A divorced session whose original GUID is no longer in
            // sharedInstance is "orphaned" (the shared profile was
            // deleted, or the session was restored from an arrangement
            // whose original profile is gone). The picker can't list a
            // profile that doesn't exist, and reloadProfile can't
            // propagate changes from a missing shared profile, so the
            // only way to update those sessions is to write directly
            // to their divorced profile here. We expose this as an
            // opt-in checkbox (default on) so users with stale orphans
            // they have no intention of using can skip them.
            let sharedModel = ProfileModel.sharedInstance()
            let includeOrphans = orphanCheckbox?.state != .off
            let isOrphan: (String) -> Bool = { originalGuid in
                includeOrphans && sharedModel?.bookmark(withGuid: originalGuid) == nil
            }

            var divorcedGuidsToUpdate = Set<String>()
            // Stale divorced bookmarks (no live session) are skipped
            // for the orphan case because writing triggers there is
            // dead weight. The live/buried iteration below picks up
            // orphan sessions that actually exist.
            for divorced in sessions.bookmarks() {
                guard let originalGuid = divorced[KEY_ORIGINAL_GUID] as? String,
                      let divorcedGuid = divorced[KEY_GUID] as? String,
                      guidsToInstall.contains(originalGuid) else {
                    continue
                }
                divorcedGuidsToUpdate.insert(divorcedGuid)
            }
            let liveSessions =
                iTermController.sharedInstance()?.allSessions() ?? []
            let buriedSessions =
                iTermBuriedSessions.sharedInstance()?.buriedSessions() ?? []
            for session in liveSessions + buriedSessions {
                let profileGuid = session.profile?[KEY_GUID] as? String ?? "<nil>"
                let originalGuid = session.originalProfile?[KEY_GUID] as? String ?? "<nil>"
                DLog("Onboarding: live session \(session) divorced=\(session.isDivorced) profileGUID=\(profileGuid) originalGUID=\(originalGuid)")
                guard session.isDivorced,
                      let originalGuid = session.originalProfile?[KEY_GUID] as? String,
                      let divorcedGuid = session.profile?[KEY_GUID] as? String else {
                    continue
                }
                if guidsToInstall.contains(originalGuid) || isOrphan(originalGuid) {
                    divorcedGuidsToUpdate.insert(divorcedGuid)
                }
            }
            // Non-divorced orphans don't have a sessionsInstance
            // bookmark we can target, so divorce each one first. The
            // divorce assigns a fresh KEY_GUID and inserts the
            // bookmark into sessionsInstance. We add that fresh GUID
            // to the trigger-write set; the kReloadAllProfiles post
            // below will then drive reloadProfile on the live
            // session, which picks the new triggers up via the
            // divorced branch (the shared branch is a no-op because
            // the original profile is gone).
            if includeOrphans {
                for session in orphanScan.nonDivorcedOrphanSessions {
                    let beforeGuid = session.profile?[KEY_GUID] as? String ?? "<nil>"
                    let newGuid = session.divorceAddressBookEntryFromPreferences()
                    DLog("Onboarding: divorced non-divorced orphan session=\(session) beforeGUID=\(beforeGuid) newDivorcedGUID=\(newGuid)")
                    divorcedGuidsToUpdate.insert(newGuid)
                }
            }
            DLog("Onboarding: divorcedGuidsToUpdate = \(divorcedGuidsToUpdate)")
            for divorcedGuid in divorcedGuidsToUpdate {
                Self.addClaudeWorkgroupTriggers([enter, exit],
                                                toProfileWithGUID: divorcedGuid,
                                                in: sessions)
            }
        }
        // setObject:forKey:inBookmark: posts iTermProfileDidChange and
        // kReloadAddressBookNotification but not kReloadAllProfiles —
        // and only the latter drives PseudoTerminal.reloadBookmarks,
        // which is what walks live sessions and calls reloadProfile on
        // each. Without this, an already-running session keeps its
        // stale _profile (and cached _config.triggerProfileDicts), so
        // claude launched in that session won't fire our triggers
        // until the session is closed and reopened. Mirrors what
        // TriggerController's import paths do after a batch add.
        if !guidsToInstall.isEmpty {
            ProfileModel.sharedInstance()?.flush()
            NotificationCenter.default.post(
                name: NSNotification.Name(kReloadAllProfiles),
                object: nil)
        }
        Self.reconcileTriggersCache()
        RLog("Onboarding: installed Enter/Exit workgroup triggers on \(guidsToInstall.count) profile(s)")
        return true
    }

    private enum DynamicProfileChoice {
        case markRewritableAndInstall
        case skipDynamic
        case cancel
    }

    // Mirrors ProfilePreferencesViewController.showDynamicProfileWarning,
    // but generalized for "the user picked these N dynamic profiles in
    // the picker" instead of "the user is editing the currently-selected
    // dynamic profile."
    private func promptForDynamicProfileAction(
            profiles: [(guid: String, name: String)]) -> DynamicProfileChoice {
        let listed = profiles.map { "\u{2022} \($0.name)" }.joined(separator: "\n")
        let warning = iTermWarning()
        warning.heading = String(localized: "ClaudeCodeOnboarding.DynamicProfilesWarningHeading", defaultValue: "Dynamic Profiles Selected", comment: "Heading of the warning shown when selected profiles are dynamic")
        warning.title = String(localized: "ClaudeCodeOnboarding.DynamicProfilesWarningBody", defaultValue: "These profiles are dynamic and not marked \u{201C}rewritable,\u{201D} so iTerm2 normally regenerates them from disk and any change here would be lost:\n\n\(listed)\n\niTerm2 can write the triggers back to dynamic profiles when they\u{2019}re marked rewritable. Rewriting can change the order of values in the underlying file.", comment: "Body of the warning shown when selected profiles are dynamic and not rewritable; the interpolation is a bulleted list of profile names")
        warning.warningType = .kiTermWarningTypePersistent
        warning.actionLabels = [
            String(localized: "ClaudeCodeOnboarding.MarkRewritableAndInstall", defaultValue: "Mark Rewritable & Install", comment: "Button that marks dynamic profiles rewritable and installs triggers"),
            String(localized: "ClaudeCodeOnboarding.SkipDynamicProfiles", defaultValue: "Skip Dynamic Profiles", comment: "Button that skips dynamic profiles when installing triggers"),
            iTermLocalizedCancel()
        ]
        switch warning.runModal() {
        case .kiTermWarningSelection0:
            return .markRewritableAndInstall
        case .kiTermWarningSelection1:
            return .skipDynamic
        default:
            return .cancel
        }
    }

    private static func makeEnterWorkgroupTrigger() -> Trigger? {
        return Trigger(fromUntrustedDict: [
            kTriggerActionKey: "iTermEnterWorkgroupTrigger",
            kTriggerRegexKey: "",
            kTriggerMatchTypeKey: NSNumber(value: iTermTriggerMatchType.eventJobStarted.rawValue),
            kTriggerParameterKey: ClaudeCodeWorkgroupTemplate.ID.workgroup,
            kTriggerPartialLineKey: NSNumber(value: false),
            kTriggerDisabledKey: NSNumber(value: false),
            kTriggerEventParamsKey: ["jobName": "claude"]
        ])
    }

    private static func makeExitWorkgroupTrigger() -> Trigger? {
        return Trigger(fromUntrustedDict: [
            kTriggerActionKey: "iTermExitWorkgroupTrigger",
            kTriggerRegexKey: "",
            kTriggerMatchTypeKey: NSNumber(value: iTermTriggerMatchType.eventJobEnded.rawValue),
            kTriggerParameterKey: "",
            kTriggerPartialLineKey: NSNumber(value: false),
            kTriggerDisabledKey: NSNumber(value: false),
            // leaderOnly: only the workgroup leader's claude ending tears the
            // workgroup down. Peers (Code Review, Diff) inherit this trigger
            // via the profile, and their own claude ending or reloading must
            // not exit the whole workgroup.
            kTriggerEventParamsKey: ["jobName": "claude", "leaderOnly": NSNumber(value: true)]
        ])
    }

    // MARK: - Step 2: Show Toolbelt

    private func doShowToolbelt() {
        // Enable Session Status tool if needed.
        if !iTermToolbeltView.shouldShowTool(kStatusToolName, profileType: .terminal) {
            iTermToolbeltView.toggleShouldShowTool(kStatusToolName)
        }

        let noTerminals = (iTermController.sharedInstance()?.terminals() ?? []).isEmpty
        if noTerminals {
            // Nothing to put the toolbelt in — launch a default window first, then
            // apply the toolbelt setup once the session is ready.
            iTermSessionLauncher.launchBookmark(nil,
                                                in: nil,
                                                respectTabbingMode: true) { [weak self] _ in
                self?.applyToolbeltToClaudeWindows()
            }
        } else {
            applyToolbeltToClaudeWindows()
        }
    }

    private func applyToolbeltToClaudeWindows() {
        // Show toolbelt in all windows with Claude sessions (falling back to the
        // current session's window if we don't know of any Claude sessions yet).
        let sessions = claudeSessions()
        var processedWindows = Set<ObjectIdentifier>()
        for session in sessions {
            guard let windowController = session.view?.window?.windowController as? PseudoTerminal else {
                continue
            }
            let windowID = ObjectIdentifier(windowController)
            guard !processedWindows.contains(windowID) else { continue }
            processedWindows.insert(windowID)

            if !windowController.shouldShowToolbelt {
                windowController.toggleToolbeltVisibility(self)
            }

            // Add a scrim highlighting the Session Status tool.
            if let toolbeltView = windowController.toolbelt(),
               let statusTool = toolbeltView.tool(withName: kStatusToolName) as? NSView,
               let toolWrapper = statusTool.superview?.superview,
               toolWrapper.isKind(of: iTermToolWrapper.self),
               let contentView = windowController.window?.contentView {
                let scrim = OnboardingScrim(cutoutView: toolWrapper)
                scrim.frame = contentView.bounds
                scrim.autoresizingMask = [.width, .height]
                contentView.addSubview(scrim)
                scrims.append(scrim)
            }
        }
    }

    // MARK: - Scrim

    private func removeScrims() {
        for scrim in scrims {
            scrim.removeFromSuperview()
        }
        scrims.removeAll()
    }

    // MARK: - Cleanup

    deinit {
        removeScrims()
        panel?.delegate = nil
    }
}

// MARK: - NSWindowDelegate
extension ClaudeCodeOnboarding: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        removeScrims()
        Self.instance = nil
    }
}

// MARK: - OnboardingScrim

/// A semi-transparent overlay with a soft hole punch around a target view,
/// modeled after iTermPrefsScrim.
private class OnboardingScrim: NSView {
    private weak var cutoutView: NSView?

    init(cutoutView: NSView) {
        self.cutoutView = cutoutView
        super.init(frame: .zero)
        // The cutout is computed in draw() from the cutout view's live
        // geometry. When the toolbelt is freshly shown its Session
        // Status tool gets its real frame on a layout pass that can
        // land after our first draw, leaving the highlight punched out
        // of a zero-sized rect. Watch the cutout view (and its toolbelt
        // ancestor) for frame changes and redraw, mirroring how
        // iTermPrefsScrim invalidates itself when its target moves.
        cutoutView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cutoutGeometryDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: cutoutView)
        if let toolbelt = cutoutView.superview {
            toolbelt.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(cutoutGeometryDidChange(_:)),
                name: NSView.frameDidChangeNotification,
                object: toolbelt)
        }
    }

    required init?(coder: NSCoder) {
        it_fatalError()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func cutoutGeometryDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let clippedRect = NSIntersectionRect(dirtyRect, bounds)
        let darkMode = window?.effectiveAppearance.it_isDark ?? false
        let baselineAlpha: CGFloat = darkMode ? 0.8 : 0.7

        // Fill background with semi-transparent black.
        NSColor.black.withAlphaComponent(baselineAlpha).set()
        clippedRect.fill()

        guard let cutoutView else { return }
        // Convert cutout view's bounds to our coordinate space.
        let rect = convert(cutoutView.bounds, from: cutoutView)

        let steps = darkMode ? 30 : 60
        let stepSize: CGFloat = 1.0
        let highlightAlpha: CGFloat = darkMode ? 0.0 : 0.2
        let alphaStride = (baselineAlpha - highlightAlpha) / CGFloat(steps)
        var a = baselineAlpha - alphaStride

        NSGraphicsContext.current?.compositingOperation = .copy
        for i in 0..<steps {
            let r = steps - i - 1
            let inset = stepSize * CGFloat(r)
            NSColor.black.withAlphaComponent(a).set()
            let insetRect = rect.insetBy(dx: -inset, dy: -inset)
            let radius = (inset + 1) * 2
            NSBezierPath(roundedRect: insetRect, xRadius: radius, yRadius: radius).fill()
            a -= alphaStride
        }
    }
}

/// Carries a block created on the main queue to a later main-queue call. Unchecked because the
/// block is never run anywhere else, which the compiler cannot see through asyncAfter.
private final class MainQueueBlock: @unchecked Sendable {
    let block: () -> Void

    init(_ block: @escaping () -> Void) {
        self.block = block
    }
}
