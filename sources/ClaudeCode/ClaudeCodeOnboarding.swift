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
        case installHook = 0
        case showToolbelt = 1
        case explainStatus = 2

        var title: String {
            switch self {
            case .installHook: return "Install Hook"
            case .showToolbelt: return "Show Toolbelt"
            case .explainStatus: return "Using Session Status"
            }
        }

        var buttonTitle: String {
            switch self {
            case .installHook: return "Install"
            case .showToolbelt: return "Show"
            case .explainStatus: return "Show Settings"
            }
        }

        var description: String {
            switch self {
            case .installHook:
                return "Install a Claude Code hook that lets iTerm2 detect Claude\u{2019}s state (working, waiting, idle) and display it in the Session Status tool.\n\nThis adds a hook to your Claude Code settings that runs automatically as Claude works."
            case .showToolbelt:
                return "Show the toolbelt and enable the Session Status tool. The toolbelt appears on the right side of your terminal window.\n\nYou can toggle the toolbelt from View \u{2192} Toolbelt \u{2192} Show Toolbelt, or with the shortcut \u{2318}\u{21E7}B."
            case .explainStatus:
                return "The Session Status tool shows all your Claude Code sessions sorted by status.\n\nSessions waiting for input appear at the top, followed by those actively working, with idle sessions at the bottom.\n\nClick a session to jump to it. Use the gear icon (\u{2699}\u{FE0F}) to configure which statuses are visible and how sessions are sorted."
            }
        }
    }

    private var panel: iTermFocusablePanel!
    private var currentStep: Step = .installHook
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
        case .installHook:
            doInstallHook()
        case .showToolbelt:
            doShowToolbelt()
        case .explainStatus:
            showSettingsPopover()
        }
        completedSteps.insert(currentStep)
        updateUI()
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

    private func doInstallHook() {
        guard let ccStatusPath = Bundle.main.path(forResource: "utilities/cc-status",
                                                  ofType: nil) else {
            DLog("Onboarding: cc-status not found in bundle")
            return
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
            return
        }
        DLog("Onboarding: doInstallHook complete")
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
