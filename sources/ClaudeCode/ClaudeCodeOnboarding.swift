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

@objc(iTermClaudeCodeOnboarding)
class ClaudeCodeOnboarding: NSObject {
    private static var instance: ClaudeCodeOnboarding?

    private enum Step: Int {
        case enablePythonAPI = 0
        case installHook = 1
        case showToolbelt = 2
        case installWorkgroup = 4
        case installTriggers = 5

        var title: String {
            switch self {
            case .enablePythonAPI: return "Enable Python API"
            case .installHook: return "Install Hook"
            case .showToolbelt: return "Show Toolbelt"
            case .installWorkgroup: return "Install Workgroup"
            case .installTriggers: return "Auto-Enter Workgroup"
            }
        }

        var buttonTitle: String {
            switch self {
            case .enablePythonAPI: return "Enable"
            case .installHook: return "Install"
            case .showToolbelt: return "Show"
            case .installWorkgroup: return "Install"
            case .installTriggers: return "Install"
            }
        }

        var description: String {
            switch self {
            case .enablePythonAPI:
                return "The Claude Code integration relies on iTerm2\u{2019}s Python API to find sessions running Claude and track their status.\n\nThe Python API is currently disabled. Setup can\u{2019}t continue until it is enabled. Click Enable to turn it on."
            case .installHook:
                return "Install a Claude Code hook that lets iTerm2 detect Claude\u{2019}s state (working, waiting, idle) and display it in the Session Status tool.\n\nThis adds a hook to your Claude Code settings that runs automatically as Claude works."
            case .showToolbelt:
                return "Show the toolbelt and enable the Session Status tool. The toolbelt appears on the right side of your terminal window.\n\nYou can toggle the toolbelt from View > Toolbelt > Show Toolbelt, or with the shortcut \u{2318}\u{21E7}B."
            case .installWorkgroup:
                return "Install the Claude Code workgroup, which groups your main Claude session with two peer sessions: a diff viewer and a code-review session. You can switch between them with one click.\n\nYou can customize this layout later in Settings > Shortcuts > Workgroups."
            case .installTriggers:
                return "Pick the terminal profiles where you run claude. iTerm2 will add triggers so the Claude Code workgroup is entered automatically when claude starts and exited when it stops.\n\nWithout this, you can still enter the workgroup manually via Shell > Workgroups > Claude Code."
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
    private var scrims = [OnboardingScrim]()
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

    // Strip every cc-status hook entry from ~/.claude/settings.json.
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
    @objc
    @discardableResult
    static func uninstallHooks() -> ClaudeCodeUninstallHooksResult {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("settings.json")
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            RLog("Onboarding: no settings.json, nothing to uninstall")
            iTermUserDefaults.claudeCodeHooksInstalled = false
            return .success
        }
        let data: Data
        do {
            data = try Data(contentsOf: settingsURL)
        } catch {
            RLog("Onboarding: couldn't read settings.json: \(error)")
            return .unreadable
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
        guard var hooks = settings["hooks"] as? [String: Any] else {
            iTermUserDefaults.claudeCodeHooksInstalled = false
            return .success
        }
        var changed = false
        for eventName in hookEventNames {
            guard var groups = hooks[eventName] as? [[String: Any]] else { continue }
            var groupsChanged = false
            for i in (0..<groups.count).reversed() {
                guard var entries = groups[i]["hooks"] as? [[String: Any]] else { continue }
                let before = entries.count
                entries.removeAll { entry in
                    guard let command = entry["command"] as? String else { return false }
                    return command.hasSuffix("/cc-status")
                }
                if entries.count != before {
                    groupsChanged = true
                    if entries.isEmpty {
                        // Drop a hook group whose only entry was
                        // ours — leaving an empty group behind would
                        // change the shape of the user's settings
                        // unnecessarily.
                        groups.remove(at: i)
                    } else {
                        var group = groups[i]
                        group["hooks"] = entries
                        groups[i] = group
                    }
                }
            }
            if groupsChanged {
                changed = true
                if groups.isEmpty {
                    hooks.removeValue(forKey: eventName)
                } else {
                    hooks[eventName] = groups
                }
            }
        }
        guard changed else {
            // Nothing on disk references cc-status — cache is no
            // longer "installed" regardless of what it was before.
            iTermUserDefaults.claudeCodeHooksInstalled = false
            return .success
        }
        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }
        do {
            let out = try JSONSerialization.data(withJSONObject: settings,
                                                 options: [.prettyPrinted, .sortedKeys])
            try out.write(to: settingsURL, options: .atomic)
            iTermUserDefaults.claudeCodeHooksInstalled = false
            DLog("Onboarding: uninstalled cc-status hooks")
            return .success
        } catch {
            RLog("Onboarding: failed to write settings.json during uninstall: \(error)")
            return .writeFailed
        }
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
            if profileIsDynamic(profile),
               !iTermProfilePreferences.bool(forKey: KEY_DYNAMIC_PROFILE_REWRITABLE,
                                             inProfile: profile) {
                continue
            }
            sawAny = true
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
            if !hasEnter || !hasExit {
                return false
            }
        }
        return sawAny
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
    // hookEventNames must have a cc-status entry, AND the command
    // path must point at an executable file. Catches the cases
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
    // The new-hook-event migration case (a future iTerm2 adds a
    // 10th event) returns false here, which prompts the user to
    // Reinstall — doInstallHook is idempotent and just adds the
    // missing event.
    //
    // Reads disk and follows symlinks; call off the main thread.
    @objc
    static func hooksHealthyOnDiskForHealthCheck() -> Bool {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = parsed["hooks"] as? [String: Any] else {
            return false
        }
        let fm = FileManager.default
        for eventName in hookEventNames {
            guard let groups = hooks[eventName] as? [[String: Any]] else {
                return false
            }
            var ok = false
            for group in groups {
                guard let entries = group["hooks"] as? [[String: Any]] else { continue }
                for entry in entries {
                    guard let command = entry["command"] as? String,
                          command.hasSuffix("/cc-status") else {
                        continue
                    }
                    // Follows symlinks; a dangling symlink fails
                    // both isExecutableFile and fileExists. The
                    // executable bit matters because Claude Code
                    // would refuse to invoke a non-executable hook.
                    if fm.isExecutableFile(atPath: command) {
                        ok = true
                        break
                    }
                }
                if ok { break }
            }
            if !ok { return false }
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
    // hooksHealthyOnDiskForHealthCheck above.
    private static func hooksInstalledOnDisk() -> Bool {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = parsed["hooks"] as? [String: Any] else {
            return false
        }
        for eventName in hookEventNames {
            guard let groups = hooks[eventName] as? [[String: Any]] else { continue }
            for group in groups {
                guard let entries = group["hooks"] as? [[String: Any]] else { continue }
                for entry in entries {
                    if let command = entry["command"] as? String,
                       command.hasSuffix("/cc-status") {
                        return true
                    }
                }
            }
        }
        return false
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

    @objc static func show() {
        if let existing = instance {
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
        steps.append(contentsOf: [.installHook,
                                  .showToolbelt,
                                  .installWorkgroup,
                                  .installTriggers])

        let onboarding = ClaudeCodeOnboarding(activeSteps: steps)
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
        onboarding.setupPanel()
        onboarding.updateUI()
        onboarding.panel.center()
        onboarding.panel.makeKeyAndOrderFront(nil)
        // Cover the installer with the heads-up intro until the user
        // dismisses it. They might've launched this from the menu
        // not knowing what's about to be touched on disk; a sheet
        // (rather than a real installer step) keeps the click count
        // down for repeat users while still surfacing the
        // "you can undo this" promise to first-timers.
        onboarding.showIntroSheet()
        // Background completion of the install-step pre-mark.
        // Identity-checks against the static instance on return so
        // a panel that was closed-and-reopened during the read
        // doesn't get the result of an earlier query.
        DispatchQueue.global(qos: .utility).async { [weak onboarding] in
            let healthy = hooksHealthyOnDiskForHealthCheck()
            DispatchQueue.main.async {
                guard let onboarding,
                      Self.instance === onboarding,
                      healthy else {
                    return
                }
                onboarding.completedSteps.insert(.installHook)
                onboarding.updateUI()
            }
        }
    }

    // MARK: - Panel Setup

    private func setupPanel() {
        panel = iTermFocusablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        panel.title = "Claude Code Integration Setup"
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

        nextButton = NSButton(title: "Next", target: self, action: #selector(nextPressed(_:)))
        nextButton.bezelStyle = .rounded
        nextButton.frame = NSRect(x: contentView.bounds.width - margin - 80,
                                  y: buttonY,
                                  width: 80,
                                  height: 32)
        nextButton.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(nextButton)

        doItButton = NSButton(title: "Do It", target: self, action: #selector(doItPressed(_:)))
        doItButton.bezelStyle = .rounded
        doItButton.keyEquivalent = "\r"
        doItButton.frame = NSRect(x: nextButton.frame.minX - 90,
                                  y: buttonY,
                                  width: 80,
                                  height: 32)
        doItButton.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(doItButton)

        backButton = NSButton(title: "Back", target: self, action: #selector(backPressed(_:)))
        backButton.bezelStyle = .rounded
        backButton.frame = NSRect(x: margin,
                                  y: buttonY,
                                  width: 80,
                                  height: 32)
        backButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        contentView.addSubview(backButton)
    }

    // MARK: - Intro Sheet

    private func showIntroSheet() {
        let sheetWidth: CGFloat = 540
        let sheetPadding: CGFloat = 24
        let textWidth = sheetWidth - sheetPadding * 2

        let titleLabel = NSTextField(labelWithString: "Before You Start")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.frame.size.width = textWidth
        titleLabel.sizeToFit()
        introTitleLabel = titleLabel

        let lead = NSTextField(wrappingLabelWithString:
            "Don’t panic! All of this can be undone later via "
            + "iTerm2 > Uninstall Claude Code Integration.")
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

        let disclosureLabel = NSTextField(labelWithString: "What gets changed")
        disclosureLabel.font = NSFont.systemFont(ofSize: 13)
        disclosureLabel.textColor = .labelColor
        disclosureLabel.isSelectable = false
        disclosureLabel.sizeToFit()
        introDisclosureLabel = disclosureLabel

        let details = NSTextField(wrappingLabelWithString:
            "\u{2022} iTerm2\u{2019}s Python API is enabled\n"
            + "\u{2022} A cc-status hook is added to ~/.claude/settings.json\n"
            + "\u{2022} The toolbelt is shown\n"
            + "\u{2022} A Claude Code workgroup is added to iTerm2\u{2019}s settings\n"
            + "\u{2022} Enter/Exit Workgroup triggers are added to the profiles you pick")
        details.font = NSFont.systemFont(ofSize: 13)
        details.textColor = .secondaryLabelColor
        details.isSelectable = false
        Self.sizeWrappingLabel(details, width: textWidth)
        details.isHidden = true
        introDetailsLabel = details

        // Always-visible link to the full writeup, regardless of the
        // disclosure state. Sits below the "What gets changed" row so
        // users who want the whole story can read it on the web.
        let helpLink = LinkButton(title: "Learn more about the Claude Code integration",
                                  target: self,
                                  action: #selector(openIntegrationHelp(_:)))
        helpLink.font = NSFont.systemFont(ofSize: 13)
        helpLink.configureLinkAppearance()
        helpLink.sizeToFit()
        introHelpLink = helpLink

        let continueButton = NSButton(title: "Continue",
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
        contentLabel.stringValue = currentStep.description

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
            nextButton.title = "Close"
            nextButton.isEnabled = true
        } else {
            nextButton.title = "Next"
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
        let success: Bool
        switch currentStep {
        case .enablePythonAPI:
            success = doEnablePythonAPI()
        case .installHook:
            success = doInstallHook()
        case .showToolbelt:
            doShowToolbelt()
            success = true
        case .installWorkgroup:
            success = doInstallWorkgroup()
        case .installTriggers:
            success = doInstallTriggers()
        }
        if success {
            completedSteps.insert(currentStep)
        }
        updateUI()
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
        guard let bundlePath = Bundle.main.path(forResource: "utilities/cc-status",
                                                ofType: nil) else {
            RLog("Onboarding: cc-status not found in bundle")
            return nil
        }
        let fm = FileManager.default
        guard let dotDir = fm.homeDirectoryDotDir() else {
            DLog("Onboarding: no dot dir available for cc-status symlink")
            return nil
        }
        let symlinkURL = URL(fileURLWithPath: dotDir)
            .appendingPathComponent("cc-status")
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
                DLog("Onboarding: couldn't remove old cc-status symlink: \(error)")
                return nil
            }
        }
        do {
            try fm.createSymbolicLink(atPath: symlinkURL.path,
                                       withDestinationPath: bundlePath)
        } catch {
            RLog("Onboarding: couldn't create cc-status symlink: \(error)")
            return nil
        }
        DLog("Onboarding: cc-status symlink \(symlinkURL.path) -> \(bundlePath)")
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
    private static let hookEventNames = [
        "UserPromptSubmit",
        "Stop",
        "StopFailure",
        "Notification",
        "PermissionRequest",
        "SessionEnd",
        "PreToolUse",
        "PostToolUse",
        "SessionStart",
    ]

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

    private func doInstallHook() -> Bool {
        guard let ccStatusPath = Self.ensureCCStatusSymlink() else {
            RLog("Onboarding: couldn't prepare cc-status symlink")
            return false
        }
        DLog("Onboarding: cc-status hook will point at \(ccStatusPath)")

        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("settings.json")

        // Read existing settings, or start with an empty object.
        var settings: [String: Any]
        if let data = try? Data(contentsOf: settingsURL),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = parsed
            DLog("Onboarding: loaded existing settings.json")
        } else {
            settings = [:]
            DLog("Onboarding: starting with empty settings")
        }

        // Build or update the "hooks" dictionary.
        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]

        let hookEntry: [String: Any] = [
            "type": "command",
            "command": ccStatusPath
        ]

        for eventName in Self.hookEventNames {
            var eventHookGroups = (hooks[eventName] as? [[String: Any]]) ?? []

            // Find any existing cc-status hook and rewrite it to the current
            // path. A previously installed hook may point at a stale dot dir
            // (for example a `-suite` instance wrote ~/.config/iterm2-alt4/
            // cc-status and we're now reinstalling from the default instance
            // that wants ~/.config/iterm2/cc-status). Matching on the
            // "/cc-status" suffix lets us adopt and correct that entry instead
            // of leaving it stale or appending a duplicate.
            var foundCCStatus = false
            for groupIndex in eventHookGroups.indices {
                guard var groupHooks = eventHookGroups[groupIndex]["hooks"] as? [[String: Any]] else {
                    continue
                }
                var groupChanged = false
                for entryIndex in groupHooks.indices {
                    guard let command = groupHooks[entryIndex]["command"] as? String,
                          command.hasSuffix("/cc-status") else {
                        continue
                    }
                    foundCCStatus = true
                    if command != ccStatusPath {
                        groupHooks[entryIndex]["command"] = ccStatusPath
                        groupChanged = true
                        DLog("Onboarding: updated stale cc-status hook for \(eventName) from \(command) to \(ccStatusPath)")
                    }
                }
                if groupChanged {
                    eventHookGroups[groupIndex]["hooks"] = groupHooks
                }
            }
            if foundCCStatus {
                hooks[eventName] = eventHookGroups
                DLog("Onboarding: hook for \(eventName) already present, ensured path is current")
                continue
            }

            // Add a new hook group with cc-status.
            let newGroup: [String: Any] = ["hooks": [hookEntry]]
            eventHookGroups.append(newGroup)
            hooks[eventName] = eventHookGroups
            DLog("Onboarding: added hook for \(eventName)")
        }

        settings["hooks"] = hooks

        // Write settings back.
        do {
            // Ensure ~/.claude directory exists.
            let claudeDir = settingsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: claudeDir,
                                                    withIntermediateDirectories: true)

            let data = try JSONSerialization.data(withJSONObject: settings,
                                                  options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsURL, options: .atomic)
            DLog("Onboarding: wrote settings.json")
        } catch {
            RLog("Onboarding: failed to write settings.json: \(error)")
            let alert = NSAlert()
            alert.messageText = "Failed to install hook"
            alert.informativeText = "Could not write to \(settingsURL.path): \(error.localizedDescription)"
            alert.runModal()
            return false
        }
        iTermUserDefaults.claudeCodeHooksInstalled = true
        // Sticky "user once completed setup" flag — distinct from the
        // disk-reconciled cache above. Drives broken-install detection
        // when something else (Claude Code itself, hand edits) strips
        // our hook out of settings.json after the fact. Only the
        // Uninstall menu flow clears it.
        iTermUserDefaults.claudeCodeIntegrationCompleted = true
        RLog("Onboarding: doInstallHook complete")
        return true
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
            let title = orphanCount == 1
                ? "Also update 1 session whose profile is missing"
                : "Also update \(orphanCount) sessions whose profiles are missing"
            let checkbox = NSButton(
                checkboxWithTitle: title,
                target: nil,
                action: nil)
            checkbox.toolTip = "Includes running sessions that were created from a profile that has since been deleted."
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
        alert.messageText = "Install Auto-Enter Triggers"
        alert.informativeText = "Pick the profiles you\u{2019}ll run claude in. "
            + "We\u{2019}ll add Enter/Exit Workgroup triggers to each one so the "
            + "Claude Code workgroup is entered automatically."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
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
            let name = (profile[KEY_NAME] as? String) ?? "(unknown)"
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
        warning.heading = "Dynamic Profiles Selected"
        warning.title = "These profiles are dynamic and not marked "
            + "\u{201C}rewritable,\u{201D} so iTerm2 normally regenerates them "
            + "from disk and any change here would be lost:\n\n\(listed)\n\n"
            + "iTerm2 can write the triggers back to dynamic profiles when "
            + "they\u{2019}re marked rewritable. Rewriting can change the "
            + "order of values in the underlying file."
        warning.warningType = .kiTermWarningTypePersistent
        warning.actionLabels = [
            "Mark Rewritable & Install",
            "Skip Dynamic Profiles",
            "Cancel"
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
