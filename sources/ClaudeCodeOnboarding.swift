//
//  ClaudeCodeOnboarding.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/7/26.
//

import AppKit

@objc(iTermClaudeCodeOnboarding)
class ClaudeCodeOnboarding: NSObject {
    private static var instance: ClaudeCodeOnboarding?

    private enum Step: Int, CaseIterable {
        case installTriggers = 0
        case showToolbelt = 1
        case explainStatus = 2

        var title: String {
            switch self {
            case .installTriggers: return "Install Triggers"
            case .showToolbelt: return "Show Toolbelt"
            case .explainStatus: return "Using Session Status"
            }
        }

        var buttonTitle: String {
            switch self {
            case .installTriggers: return "Install"
            case .showToolbelt: return "Show"
            case .explainStatus: return "Show Settings"
            }
        }

        var description: String {
            switch self {
            case .installTriggers:
                return "Add Claude Code\u{2013}specific triggers to the profiles you use with Claude Code. These triggers let iTerm2 detect Claude\u{2019}s state (working, waiting, idle) and display it in the Session Status tool."
            case .showToolbelt:
                return "Show the toolbelt and enable the Session Status tool. The toolbelt appears on the right side of your terminal window.\n\nYou can toggle the toolbelt from View \u{2192} Toolbelt \u{2192} Show Toolbelt, or with the shortcut \u{2318}\u{21E7}B."
            case .explainStatus:
                return "The Session Status tool shows all your Claude Code sessions sorted by status.\n\nSessions waiting for input appear at the top, followed by those actively working, with idle sessions at the bottom.\n\nClick a session to jump to it. Use the gear icon (\u{2699}\u{FE0F}) to configure which statuses are visible and how sessions are sorted."
            }
        }
    }

    private var panel: iTermFocusablePanel!
    private var currentStep: Step = .installTriggers
    private var completedSteps = Set<Step>()

    // UI elements
    private var stepLabels = [NSTextField]()
    private var contentLabel: NSTextField!
    private var backButton: NSButton!
    private var doItButton: NSButton!
    private var nextButton: NSButton!
    private var scrims = [OnboardingScrim]()

    // MARK: - Public API

    @objc static func show() {
        if let existing = instance {
            existing.panel.makeKeyAndOrderFront(nil)
            return
        }
        let onboarding = ClaudeCodeOnboarding()
        instance = onboarding
        onboarding.setupPanel()
        onboarding.updateUI()
        onboarding.panel.center()
        onboarding.panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Panel Setup

    private func setupPanel() {
        panel = iTermFocusablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 380),
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

    private func makeStepIndicators() -> NSView {
        let container = NSView()
        stepLabels.removeAll()

        for _ in Step.allCases {
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
        for step in Step.allCases {
            let prefix: String
            if completedSteps.contains(step) {
                prefix = "\u{2705} "
            } else if step == currentStep {
                prefix = "\u{25B6}\u{FE0F} "
            } else {
                prefix = "\u{25CB} "
            }
            let label = stepLabels[step.rawValue]
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
        backButton.isEnabled = currentStep.rawValue > 0
        doItButton.title = currentStep.buttonTitle
        let oldY = doItButton.frame.origin.y
        let oldHeight = doItButton.frame.height
        doItButton.sizeToFit()
        doItButton.frame.origin.x = nextButton.frame.minX - doItButton.frame.width - 10
        doItButton.frame.origin.y = oldY
        doItButton.frame.size.height = oldHeight
        doItButton.isHidden = false

        if currentStep == .explainStatus {
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
        guard currentStep.rawValue > 0,
              let prev = Step(rawValue: currentStep.rawValue - 1) else {
            return
        }
        currentStep = prev
        updateUI()
    }

    @objc private func nextPressed(_ sender: Any?) {
        if currentStep == .explainStatus {
            panel.close()
            Self.instance = nil
            return
        }
        guard let next = Step(rawValue: currentStep.rawValue + 1) else {
            return
        }
        currentStep = next
        updateUI()
    }

    @objc private func doItPressed(_ sender: Any?) {
        switch currentStep {
        case .installTriggers:
            doInstallTriggers()
        case .showToolbelt:
            doShowToolbelt()
        case .explainStatus:
            showSettingsPopover()
        }
        completedSteps.insert(currentStep)
        updateUI()
    }

    // MARK: - Step 1: Install Triggers

    private func claudeSessionGUIDs() -> Set<String> {
        // Prefer ClaudeWatcher if running, otherwise query GlobalJobMonitor directly.
        if let watcher = ClaudeWatcher.instance, !watcher.sessionIDs.isEmpty {
            return watcher.sessionIDs
        }
        return GlobalJobMonitor.instance.sessionGUIDs(runningJob: "claude")
    }

    private func claudeSessions() -> [PTYSession] {
        return claudeSessionGUIDs().compactMap { guid in
            iTermController.sharedInstance()?.session(withGUID: guid)
        }
    }

    private func doInstallTriggers() {
        guard let bundlePath = Bundle.main.path(forResource: "claude-code-status-triggers",
                                                ofType: "json") else {
            DLog("Onboarding: claude-code-status-triggers.json not found in bundle")
            return
        }
        DLog("Onboarding: loading triggers from \(bundlePath)")

        guard let triggers = TriggerController.triggers(fromFile: bundlePath,
                                                        window: panel),
              triggers.count > 0 else {
            DLog("Onboarding: no triggers loaded from file")
            return
        }
        DLog("Onboarding: loaded \(triggers.count) triggers")

        let sessions = claudeSessions()
        DLog("Onboarding: found \(sessions.count) Claude sessions")

        // Collect unique profile GUIDs that are running Claude.
        var claudeProfileGUIDs = Set<String>()
        for session in sessions {
            if let guid = profileGUID(for: session) {
                claudeProfileGUIDs.insert(guid)
                DLog("Onboarding: Claude session \(session.guid ?? "nil") uses profile GUID \(guid) (isDivorced=\(session.isDivorced))")
            } else {
                DLog("Onboarding: Claude session \(session.guid ?? "nil") has no profile GUID")
            }
        }
        DLog("Onboarding: unique Claude profile GUIDs: \(claudeProfileGUIDs)")

        // Show profile selection alert with pre-selection.
        guard let selectedGUIDs = showProfileSelectionAlert(triggers: triggers,
                                                            preselectedGUIDs: claudeProfileGUIDs) else {
            DLog("Onboarding: user cancelled profile selection")
            return
        }
        DLog("Onboarding: user selected \(selectedGUIDs.count) profile(s): \(selectedGUIDs)")

        // Add triggers to each selected profile.
        for guid in selectedGUIDs {
            let profileBefore = ProfileModel.sharedInstance()?.bookmark(withGuid: guid)
            let countBefore = (profileBefore?[KEY_TRIGGERS] as? [Any])?.count ?? 0
            DLog("Onboarding: adding triggers to profile \(guid), existing trigger count: \(countBefore)")

            TriggerController.add(triggers, toProfileWithGUID: guid)

            let profileAfter = ProfileModel.sharedInstance()?.bookmark(withGuid: guid)
            let countAfter = (profileAfter?[KEY_TRIGGERS] as? [Any])?.count ?? 0
            DLog("Onboarding: profile \(guid) now has \(countAfter) triggers (was \(countBefore))")
        }

        // Update divorced sessions that have overridden triggers.
        for session in sessions {
            guard session.isDivorced else {
                DLog("Onboarding: session \(session.guid ?? "nil") is not divorced, skipping session-specific update")
                continue
            }
            guard let originalGUID = session.profile?[KEY_ORIGINAL_GUID] as? String,
                  selectedGUIDs.contains(originalGUID) else {
                DLog("Onboarding: divorced session \(session.guid ?? "nil") originalGUID \(session.profile?[KEY_ORIGINAL_GUID] ?? "nil") not in selected set, skipping")
                continue
            }
            // Copy the updated trigger list from the shared profile to the session.
            if let sharedProfile = ProfileModel.sharedInstance()?.bookmark(withGuid: originalGUID),
               let updatedTriggers = sharedProfile[KEY_TRIGGERS] {
                let count = (updatedTriggers as? [Any])?.count ?? -1
                DLog("Onboarding: copying \(count) triggers to divorced session \(session.guid ?? "nil")")
                session.setSessionSpecificProfileValues([KEY_TRIGGERS: updatedTriggers])
            } else {
                DLog("Onboarding: failed to get shared profile for \(originalGUID)")
            }
        }

        DLog("Onboarding: posting kReloadAllProfiles")
        NotificationCenter.default.post(name: NSNotification.Name(kReloadAllProfiles), object: nil)

        // Jiggle all Claude sessions so triggers have a chance to fire on a redraw.
        for session in sessions {
            DLog("Onboarding: jiggling session \(session.guid ?? "nil")")
            session.setNeedsJiggle(true)
        }
        DLog("Onboarding: doInstallTriggers complete")
    }

    private func profileGUID(for session: PTYSession) -> String? {
        if session.isDivorced,
           let originalGUID = session.profile?[KEY_ORIGINAL_GUID] as? String {
            return originalGUID
        }
        return session.profile?[KEY_GUID] as? String
    }

    private func showProfileSelectionAlert(triggers: [Trigger],
                                           preselectedGUIDs: Set<String>) -> Set<String>? {
        let alert = NSAlert()
        alert.messageText = "Select profiles to add Claude Code triggers to:"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let profiles = ProfileListView(frame: NSMakeRect(0, 0, 300, 300))
        profiles.disableArrowHandler()
        profiles.allowMultipleSelections()
        alert.accessoryView = profiles

        // Ensure data is loaded before trying to select.
        profiles.reloadData()

        // Pre-select profiles running Claude.
        if !preselectedGUIDs.isEmpty {
            var indicesToSelect = IndexSet()
            guard let wrapper = profiles.dataSource() else { return nil }
            for guid in preselectedGUIDs {
                let row = Int(wrapper.indexOfProfile(withGuid: guid))
                if row >= 0 {
                    indicesToSelect.insert(row)
                }
            }
            if !indicesToSelect.isEmpty {
                profiles.tableView().selectRowIndexes(indicesToSelect, byExtendingSelection: false)
            }
        }

        // Disable OK when nothing is selected.
        let okButton = alert.buttons[0]
        okButton.isEnabled = profiles.hasSelection
        let observer = ProfileSelectionObserver(profiles: profiles, okButton: okButton)
        profiles.delegate = observer

        guard alert.runModal() == .alertFirstButtonReturn else {
            _ = observer  // prevent dealloc
            return nil
        }
        _ = observer
        return profiles.selectedGuids
    }

    // MARK: - Step 2: Show Toolbelt

    private func doShowToolbelt() {
        // Enable Session Status tool if needed.
        if !iTermToolbeltView.shouldShowTool(kStatusToolName, profileType: .terminal) {
            iTermToolbeltView.toggleShouldShowTool(kStatusToolName)
        }

        // Show toolbelt in all windows with Claude sessions.
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

// MARK: - ProfileSelectionObserver

/// Observes profile list selection to enable/disable the OK button.
private class ProfileSelectionObserver: NSObject, ProfileListViewDelegate {
    private weak var okButton: NSButton?

    init(profiles: ProfileListView, okButton: NSButton) {
        self.okButton = okButton
        super.init()
    }

    func profileTableSelectionDidChange(_ profileTable: Any!) {
        guard let list = profileTable as? ProfileListView else { return }
        okButton?.isEnabled = list.hasSelection
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
