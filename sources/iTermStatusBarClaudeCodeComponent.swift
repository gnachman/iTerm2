import AppKit

/// Pure logic extracted from iTermStatusBarClaudeCodeComponent so it can be unit-tested
/// without instantiating the heavyweight status-bar component hierarchy.
enum ClaudeCodeSummaryBuilder {
    static let waitingText = "Waiting"
    static let workingText = "Working\u{2026}"
    static let idleText = "Idle"

    static func isClaudeCodeStatus(_ text: String?) -> Bool {
        guard let text else { return false }
        return text == waitingText || text == workingText || text == idleText
    }

    static func buildSummary(from sessions: [iTermSessionTabStatus]) -> String {
        if sessions.isEmpty {
            return "No sessions"
        }
        let waiting = sessions.filter { $0.statusText == waitingText }.count
        let working = sessions.filter { $0.statusText == workingText }.count
        let idle    = sessions.filter { $0.statusText == idleText }.count

        var parts = [String]()
        if waiting > 0 { parts.append(waiting == 1 ? "1 waiting" : "\(waiting) waiting") }
        if working > 0 { parts.append(working == 1 ? "1 working" : "\(working) working") }
        if idle    > 0 { parts.append(idle    == 1 ? "1 idle"    : "\(idle) idle") }
        return parts.joined(separator: ", ")
    }
}

@objc(iTermStatusBarClaudeCodeComponent)
class iTermStatusBarClaudeCodeComponent: iTermStatusBarTextComponent {
    private var observerToken: NotifyingDictionaryObserverToken?
    private var cachedSummary: String = ""
    private var popover: NSPopover?

    override static var compatibleProfileTypes: ProfileType {
        [.terminal]
    }

    required init(configuration: [iTermStatusBarComponentConfigurationKey: Any], scope: iTermVariableScope?) {
        super.init(configuration: configuration, scope: scope)
        observerToken = SessionStatusController.instance.addObserver { [weak self] _, _, _ in
            DispatchQueue.main.async {
                self?.rebuildSummary()
            }
        }
        rebuildSummary()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observerToken = nil
    }

    override func statusBarComponentIcon() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        return NSImage(systemSymbolName: "brain", accessibilityDescription: "Claude Code")?
            .withSymbolConfiguration(config) ?? NSImage()
    }

    override func statusBarComponentShortDescription() -> String {
        return "Claude Code"
    }

    override func statusBarComponentDetailedDescription() -> String {
        return "Shows status of Claude Code sessions across all windows"
    }

    override func statusBarComponentExemplar(withBackgroundColor backgroundColor: NSColor, textColor: NSColor) -> Any {
        return "2 waiting, 1 working"
    }

    override func statusBarComponentCanStretch() -> Bool {
        return false
    }

    override func statusBarComponentHandlesClicks() -> Bool {
        return true
    }

    override var stringVariants: [String]? {
        return [cachedSummary]
    }

    override func stringValueForCurrentWidth() -> String? {
        return cachedSummary
    }

    override func statusBarComponentUpdate() {
        rebuildSummary()
        super.statusBarComponentUpdate()
    }

    override func statusBarComponentDidClick(with view: NSView) {
        let sessions = claudeCodeSessions()
        guard !sessions.isEmpty else { return }
        showPopover(relativeTo: view)
    }

    private func rebuildSummary() {
        cachedSummary = ClaudeCodeSummaryBuilder.buildSummary(from: claudeCodeSessions())
        updateTextFieldIfNeeded()
    }

    private func claudeCodeSessions() -> [iTermSessionTabStatus] {
        let activeGUIDs = GlobalJobMonitor.instance.sessionGUIDs(runningJob: "claude")
        return SessionStatusController.instance.statuses.values.filter {
            activeGUIDs.contains($0.sessionID) && ClaudeCodeSummaryBuilder.isClaudeCodeStatus($0.statusText)
        }
    }

    private func showPopover(relativeTo view: NSView) {
        popover?.close()

        let newPopover = NSPopover()
        newPopover.appearance = view.effectiveAppearance
        newPopover.behavior = .semitransient
        let viewController = ClaudeCodeStatusPopoverViewController()
        newPopover.contentViewController = viewController
        newPopover.contentSize = viewController.preferredContentSize

        let positionRawValue = iTermPreferences.unsignedInteger(forKey: kPreferenceKeyStatusBarPosition)
        let preferredEdge: NSRectEdge = positionRawValue == iTermStatusBarPosition.top.rawValue ? .maxY : .minY

        let relativeView = view.subviews.first ?? view
        var rect = relativeView.bounds
        rect.size.width = statusBarComponentMinimumWidth()
        newPopover.show(relativeTo: rect, of: relativeView, preferredEdge: preferredEdge)
        popover = newPopover
    }
}
