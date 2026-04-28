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
        case explainStatus = 3
        case installWorkgroup = 4
        case installTriggers = 5

        var title: String {
            switch self {
            case .enablePythonAPI: return "Enable Python API"
            case .installHook: return "Install Hook"
            case .showToolbelt: return "Show Toolbelt"
            case .explainStatus: return "Using Session Status"
            case .installWorkgroup: return "Install Workgroup"
            case .installTriggers: return "Auto-Enter Workgroup"
            }
        }

        var buttonTitle: String {
            switch self {
            case .enablePythonAPI: return "Enable"
            case .installHook: return "Install"
            case .showToolbelt: return "Show"
            case .explainStatus: return "Show Settings"
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
            case .explainStatus:
                return "The Session Status tool shows all your Claude Code sessions sorted by status.\n\nSessions waiting for input appear at the top, followed by those actively working, with idle sessions at the bottom.\n\nClick a session to jump to it. Use the gear icon (\u{2699}\u{FE0F}) to configure which statuses are visible and how sessions are sorted."
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
    private var introOverlay: NSView?
    private var introCard: NSView?
    private var introTitleLabel: NSTextField?
    private var introLeadLabel: NSTextField?
    private var introDisclosureButton: NSButton?
    private var introDisclosureLabel: NSTextField?
    private var introDetailsLabel: NSTextField?
    private var introContinueButton: NSButton?

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
            DLog("Onboarding: no settings.json, nothing to uninstall")
            iTermUserDefaults.claudeCodeHooksInstalled = false
            return .success
        }
        let data: Data
        do {
            data = try Data(contentsOf: settingsURL)
        } catch {
            DLog("Onboarding: couldn't read settings.json: \(error)")
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
            DLog("Onboarding: failed to write settings.json during uninstall: \(error)")
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
            let filtered = triggers.filter { dict in
                guard let action = dict[kTriggerActionKey] as? String else { return true }
                if action == "iTermEnterWorkgroupTrigger",
                   let param = dict[kTriggerParameterKey] as? String,
                   param == ClaudeCodeWorkgroupTemplate.ID.workgroup {
                    return false
                }
                if action == "iTermExitWorkgroupTrigger",
                   let params = dict[kTriggerEventParamsKey] as? [String: Any],
                   (params["jobName"] as? String) == "claude" {
                    return false
                }
                return true
            }
            if filtered.count != triggers.count {
                model.setObject(filtered, forKey: KEY_TRIGGERS, inBookmark: profile)
            }
        }
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
                          (params["jobName"] as? String) == "claude" {
                    // Match the installer's scope: an Exit trigger
                    // filtered on "claude". A user-added Exit trigger
                    // for some other job is unrelated and shouldn't
                    // count as "already installed."
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

    // Authoritative scan of ~/.claude/settings.json. Used only at
    // app launch to seed the cache, since the alternative — trusting
    // a stale cache forever — would mis-report state for users who
    // installed hooks before this caching landed, or who edited
    // settings.json by hand.
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
                                  .explainStatus,
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
        if hooksAlreadyInstalled() {
            onboarding.completedSteps.insert(.installHook)
        }
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
        // not knowing what's about to be touched on disk; an
        // overlay (rather than a real installer step) keeps the click
        // count down for repeat users while still surfacing the
        // "you can undo this" promise to first-timers.
        onboarding.showIntroOverlay()
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

    // MARK: - Intro Overlay

    private func showIntroOverlay() {
        guard let contentView = panel.contentView else { return }
        let overlay = NSView(frame: contentView.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor

        let cardWidth: CGFloat = 540
        let cardPadding: CGFloat = 24
        let textWidth = cardWidth - cardPadding * 2

        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        card.layer?.cornerRadius = 10
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.layer?.borderWidth = 1

        let titleLabel = NSTextField(labelWithString: "Before You Start")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.frame.size.width = textWidth
        titleLabel.sizeToFit()
        card.addSubview(titleLabel)
        introTitleLabel = titleLabel

        let lead = NSTextField(wrappingLabelWithString:
            "Don’t panic! All of this can be undone later via "
            + "iTerm2 > Uninstall Claude Code Integration.")
        lead.font = NSFont.systemFont(ofSize: 13)
        lead.textColor = .labelColor
        lead.isSelectable = false
        Self.sizeWrappingLabel(lead, width: textWidth)
        card.addSubview(lead)
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
        card.addSubview(disclosure)
        introDisclosureButton = disclosure

        let disclosureLabel = NSTextField(labelWithString: "What gets changed")
        disclosureLabel.font = NSFont.systemFont(ofSize: 13)
        disclosureLabel.textColor = .labelColor
        disclosureLabel.isSelectable = false
        disclosureLabel.sizeToFit()
        card.addSubview(disclosureLabel)
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
        card.addSubview(details)
        introDetailsLabel = details

        let continueButton = NSButton(title: "Continue",
                                      target: self,
                                      action: #selector(dismissIntroOverlay(_:)))
        continueButton.bezelStyle = .rounded
        continueButton.keyEquivalent = "\r"
        continueButton.frame.size = NSSize(width: 100, height: 32)
        card.addSubview(continueButton)
        introContinueButton = continueButton

        // The installer's own Do It / Next buttons set keyEquivalent
        // "\r" too — clear them while the overlay is up so Enter
        // routes to Continue. updateUI() restores them on dismiss.
        nextButton.keyEquivalent = ""
        doItButton.keyEquivalent = ""

        overlay.addSubview(card)
        contentView.addSubview(overlay)
        introOverlay = overlay
        introCard = card

        layoutIntroCard()
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

    // Lay out the intro card top-down based on the disclosure state.
    // Re-runs whenever the disclosure toggles, so the card grows/shrinks
    // and re-centers in the overlay.
    private func layoutIntroCard() {
        guard let overlay = introOverlay,
              let card = introCard,
              let title = introTitleLabel,
              let lead = introLeadLabel,
              let disclosure = introDisclosureButton,
              let disclosureLabel = introDisclosureLabel,
              let details = introDetailsLabel,
              let continueButton = introContinueButton else { return }

        let cardWidth: CGFloat = 540
        let cardPadding: CGFloat = 24
        let bottomPadding: CGFloat = 16
        let leadGap: CGFloat = 12
        let disclosureGap: CGFloat = 16
        let detailsGap: CGFloat = 8
        let buttonGap: CGFloat = 20
        let disclosureRowHeight = max(disclosure.frame.height,
                                      disclosureLabel.frame.height)

        var height = cardPadding
        height += title.frame.height
        height += leadGap
        height += lead.frame.height
        height += disclosureGap
        height += disclosureRowHeight
        if !details.isHidden {
            height += detailsGap
            height += details.frame.height
        }
        height += buttonGap
        height += continueButton.frame.height
        height += bottomPadding

        card.frame = NSRect(
            x: (overlay.bounds.width - cardWidth) / 2,
            y: (overlay.bounds.height - height) / 2,
            width: cardWidth,
            height: height)

        var y = height - cardPadding - title.frame.height
        title.frame.origin = NSPoint(x: cardPadding, y: y)
        y -= leadGap
        y -= lead.frame.height
        lead.frame.origin = NSPoint(x: cardPadding, y: y)
        y -= disclosureGap
        y -= disclosureRowHeight
        let disclosureY = y + (disclosureRowHeight - disclosure.frame.height) / 2
        disclosure.frame.origin = NSPoint(x: cardPadding, y: disclosureY)
        let labelY = y + (disclosureRowHeight - disclosureLabel.frame.height) / 2
        disclosureLabel.frame.origin = NSPoint(
            x: disclosure.frame.maxX + 4,
            y: labelY)
        if !details.isHidden {
            y -= detailsGap
            y -= details.frame.height
            details.frame.origin = NSPoint(x: cardPadding, y: y)
        }
        continueButton.frame.origin = NSPoint(
            x: cardWidth - cardPadding - continueButton.frame.width,
            y: bottomPadding)
    }

    @objc private func toggleIntroDetails(_ sender: NSButton) {
        introDetailsLabel?.isHidden = (sender.state == .off)
        layoutIntroCard()
    }

    @objc private func dismissIntroOverlay(_ sender: Any?) {
        introOverlay?.removeFromSuperview()
        introOverlay = nil
        introCard = nil
        introTitleLabel = nil
        introLeadLabel = nil
        introDisclosureButton = nil
        introDisclosureLabel = nil
        introDetailsLabel = nil
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

        // Keep scrims visible during steps 2 and 3; remove otherwise.
        if currentStep != .showToolbelt && currentStep != .explainStatus {
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
            nextButton.isEnabled = completedSteps.contains(currentStep)
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
        case .explainStatus:
            showSettingsPopover()
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
        guard let ccStatusPath = Bundle.main.path(forResource: "utilities/cc-status",
                                                  ofType: nil) else {
            DLog("Onboarding: cc-status not found in bundle")
            return false
        }
        DLog("Onboarding: cc-status binary at \(ccStatusPath)")

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

            // Check if cc-status is already installed in any group.
            let alreadyInstalled = eventHookGroups.contains { group in
                guard let groupHooks = group["hooks"] as? [[String: Any]] else {
                    return false
                }
                return groupHooks.contains { entry in
                    guard let command = entry["command"] as? String else {
                        return false
                    }
                    return command.hasSuffix("/cc-status")
                }
            }
            if alreadyInstalled {
                DLog("Onboarding: hook for \(eventName) already installed, skipping")
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
            DLog("Onboarding: failed to write settings.json: \(error)")
            let alert = NSAlert()
            alert.messageText = "Failed to install hook"
            alert.informativeText = "Could not write to \(settingsURL.path): \(error.localizedDescription)"
            alert.runModal()
            return false
        }
        iTermUserDefaults.claudeCodeHooksInstalled = true
        DLog("Onboarding: doInstallHook complete")
        return true
    }

    // MARK: - Step: Install Workgroup

    private func doInstallWorkgroup() -> Bool {
        Self.installWorkgroupIfNeeded()
        return true
    }

    // MARK: - Step: Install Triggers

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
            DLog("Onboarding: failed to construct trigger objects")
            return false
        }
        guard let listView = ProfileListView(
            frame: NSRect(x: 0, y: 0, width: 360, height: 240),
            model: ProfileModel.sharedInstance(),
            font: nil,
            profileTypes: .terminal) else {
            return false
        }
        listView.disableArrowHandler()
        listView.allowMultipleSelections()

        let alert = NSAlert()
        alert.messageText = "Install Auto-Enter Triggers"
        alert.informativeText = "Pick the profiles you\u{2019}ll run claude in. "
            + "We\u{2019}ll add Enter/Exit Workgroup triggers to each one so the "
            + "Claude Code workgroup is entered automatically."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = listView

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

        for guid in guidsToInstall {
            TriggerController.add([enter, exit], toProfileWithGUID: guid)
        }
        // Push the same triggers into divorced session profiles
        // whose canonical parent the user picked. Without this, an
        // already-running divorced session keeps the old (trigger-
        // less) profile snapshot — install would silently fail to
        // affect anyone currently working in that session. Mirrors
        // uninstall, which already walks sessionsInstance.
        // TriggerController.add(_:toProfileWithGUID:) only walks
        // sharedInstance, so use the in-model overload here.
        if let sessions = ProfileModel.sessionsInstance() {
            for divorced in sessions.bookmarks() {
                guard let originalGuid = divorced[KEY_ORIGINAL_GUID] as? String,
                      guidsToInstall.contains(originalGuid),
                      let divorcedGuid = divorced[KEY_GUID] as? String else {
                    continue
                }
                TriggerController.add([enter, exit],
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
            NotificationCenter.default.post(
                name: NSNotification.Name(kReloadAllProfiles),
                object: nil)
        }
        Self.reconcileTriggersCache()
        DLog("Onboarding: installed Enter/Exit workgroup triggers on \(guidsToInstall.count) profile(s)")
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
            kTriggerEventParamsKey: ["jobName": "claude"]
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
            guard let windowController = session.view.window?.windowController as? PseudoTerminal else {
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

    // MARK: - Step 3: Explain Status

    private func showSettingsPopover() {
        for session in claudeSessions() {
            guard let windowController = session.view.window?.windowController as? PseudoTerminal,
                  let toolbeltView = windowController.toolbelt(),
                  let statusTool = toolbeltView.tool(withName: kStatusToolName) as? ToolStatus else {
                continue
            }
            statusTool.showSettings(nil)
            return
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
    }

    required init?(coder: NSCoder) {
        it_fatalError()
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
