//
//  WorkgroupUsageToolbarItem.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/26.
//

import AppKit

// One usage bar in the report emitted by the usage command.
struct WorkgroupUsageBar: Decodable {
    let label: String
    // Optional caption for the cramped toolbar row (the full `label`
    // always lives in the tooltip). The data source owns this because
    // only it knows the right abbreviation for an arbitrary window or
    // model name (a fortnightly cap, a vendor-specific model, a
    // non-Latin label) that a generic client-side rule would mangle.
    // When absent, the view derives one from `label`.
    let short: String?
    let fraction: Double
    let detail: String?

    // Renderable fraction, clamped to the drawable range so a bad
    // command can't blow out the bar geometry.
    var clampedFraction: Double {
        return min(1.0, max(0.0, fraction))
    }
}

// The JSON contract the usage command prints on stdout. `error` non-nil
// (or an empty `bars`) means "nothing to show" and the item renders the
// message instead of bars.
struct WorkgroupUsageReport: Decodable {
    let bars: [WorkgroupUsageBar]
    // Short, human-readable summary shown in the toolbar when there are
    // no bars.
    let error: String?
    // Detailed, copyable text for a bug report (e.g. the raw command
    // output we couldn't parse). Optional.
    let diagnostic: String?
    // When true, the failure is one the user should act on / report (the
    // usage format wasn't recognized, or the command emitted junk) — the
    // item shows a clickable "update or report" affordance. When false or
    // absent, the failure is expected (no subscription, tool missing) and
    // we just show the summary. Absent decodes to nil (treated as false).
    let reportable: Bool?
}

// A thin determinate progress bar drawn with CALayers. No VT100
// coupling; just a track with a fractional fill.
private final class WorkgroupUsageBarView: NSView {
    private let track = CALayer()
    private let fill = CALayer()
    var fraction: CGFloat = 0 {
        didSet { needsLayout = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        track.cornerRadius = 1.5
        fill.cornerRadius = 1.5
        layer?.addSublayer(track)
        layer?.addSublayer(fill)
        applyColors()
    }

    required init?(coder: NSCoder) {
        it_fatalError("not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        // Resolve colors in the view's current appearance so the bar
        // tracks light/dark (CALayer colors don't auto-update).
        effectiveAppearance.performAsCurrentDrawingAppearance {
            track.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            fill.backgroundColor = Self.fillColor(for: fraction).cgColor
        }
    }

    // Green-ish accent normally, amber past 75%, red past 90%, so a
    // near-exhausted limit reads at a glance.
    private static func fillColor(for fraction: CGFloat) -> NSColor {
        if fraction >= 0.9 {
            return .systemRed
        }
        if fraction >= 0.75 {
            return .systemOrange
        }
        return .controlAccentColor
    }

    override func layout() {
        super.layout()
        // Disable implicit animation so the bar snaps to the new value
        // on each refresh rather than sliding.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = bounds
        fill.frame = NSRect(x: 0,
                            y: 0,
                            width: bounds.width * min(1.0, max(0.0, fraction)),
                            height: bounds.height)
        applyColors()
        CATransaction.commit()
    }
}

// Container that reports window membership so the item can start its
// refresh timer only while on screen.
private final class WorkgroupUsageContainerView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?
    // Invoked on click. Returns true if the click was handled (used to
    // decide whether to show a click affordance). Nil means not clickable.
    var onClick: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }

    override func mouseDown(with event: NSEvent) {
        if let onClick {
            onClick()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func resetCursorRects() {
        // Point the cursor when there's something to click (an error the
        // user can drill into); otherwise leave the default.
        if onClick != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

// A single row: [short label][bar][percent].
private final class WorkgroupUsageRowViews {
    let label = NSTextField(labelWithString: "")
    let bar = WorkgroupUsageBarView(frame: .zero)
    let percent = NSTextField(labelWithString: "")

    init() {
        for field in [label, percent] {
            field.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            field.textColor = .secondaryLabelColor
            field.lineBreakMode = .byClipping
            field.drawsBackground = false
            field.isBordered = false
            field.isEditable = false
            field.isSelectable = false
        }
        percent.alignment = .right
    }
}

// A workgroup toolbar item that periodically runs a command reporting
// AI usage as JSON and renders it as inline determinate progress bars.
@objc(iTermWorkgroupUsageToolbarItem)
class WorkgroupUsageToolbarItem: SessionToolbarGenericView {
    private let provider: WorkgroupUsageProvider
    private let command: String
    private let intervalSeconds: Double
    private let container: WorkgroupUsageContainerView

    private var rows: [WorkgroupUsageRowViews] = []
    private let messageLabel = NSTextField(labelWithString: "")

    // Retained from the most recent report so the click handler can build
    // a report the user can copy and send in. Non-nil summary + reportable
    // is what makes the item clickable.
    private var lastErrorSummary: String?
    private var lastDiagnostic: String?
    private var lastReportable = false

    private var timer: Timer?
    // Background queue that runs the (blocking) usage command so the
    // main thread never waits on a subprocess.
    private let queue = DispatchQueue(label: "com.googlecode.iterm2.WorkgroupUsage")
    // Guards against launching a second command while the previous one
    // is still running (a slow claude invocation must not pile up).
    private var runInFlight = false

    // iTerm2's convention for flagging an error in the UI.
    private static let errorPrefix = "🐞 "
    // New-issue page for reportable usage errors. GitLab pre-fills the
    // form from issue[title]/issue[description] query params, so the link
    // itself carries the report and the user usually needn't paste.
    private static let bugReportBaseURL =
        "https://gitlab.com/gnachman/iterm2/-/work_items/new"
    // Dedicated issue template (.gitlab/issue_templates/AI Usage.md).
    // Selecting it keeps the project's default template (and its unrelated
    // boilerplate) out of the report.
    private static let bugReportTemplate = "AI Usage"
    // Cap the URL-borne description; the full report always goes to the
    // clipboard as a fallback for anything a long URL would truncate.
    private static let maxURLDescription = 2000

    // Layout metrics.
    private static let labelWidth: CGFloat = 26
    private static let percentWidth: CGFloat = 34
    private static let barHeight: CGFloat = 5
    private static let hInset: CGFloat = 2
    private static let hGap: CGFloat = 4
    private static let rowGap: CGFloat = 2

    init(identifier: String,
         priority: Int,
         provider: WorkgroupUsageProvider,
         command: String,
         intervalSeconds: Double) {
        self.provider = provider
        self.command = command
        self.intervalSeconds = max(5, intervalSeconds)
        self.container = WorkgroupUsageContainerView(frame: .zero)
        super.init(identifier: identifier, priority: priority, view: container)

        // Init runs on the main thread; safe to install the app-quit
        // observer that terminates any in-flight usage commands.
        Self.installTerminationObserverIfNeeded()

        messageLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        messageLabel.textColor = .tertiaryLabelColor
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.drawsBackground = false
        messageLabel.isBordered = false
        messageLabel.isEditable = false
        messageLabel.isSelectable = false
        messageLabel.stringValue = String(localized: "WorkgroupUsage.Loading",
                                           defaultValue: "AI usage…",
                                           comment: "Placeholder shown in the AI usage toolbar item before the first result arrives")
        container.addSubview(messageLabel)

        container.onWindowChange = { [weak self] window in
            guard let self else { return }
            if window == nil {
                self.stopTimer()
            } else {
                self.startTimer()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    override var desiredWidthRange: ClosedRange<CGFloat> {
        // Compact and mostly fixed; a little stretch is allowed so a
        // roomy toolbar can widen the bars.
        return 100...150
    }

    override func layoutSubviews() {
        let width = view.bounds.width
        let height = view.bounds.height
        _view.frame = NSRect(x: 0, y: 0, width: width, height: height)

        guard !rows.isEmpty else {
            let h = messageLabel.fittingSize.height
            messageLabel.frame = NSRect(x: Self.hInset,
                                        y: (height - h) / 2.0,
                                        width: max(0, width - 2 * Self.hInset),
                                        height: h)
            return
        }

        let n = CGFloat(rows.count)
        let totalGap = Self.rowGap * max(0, n - 1)
        let rowHeight = max(0, (height - totalGap) / n)
        // Lay rows top-down.
        var y = height - rowHeight
        let barX = Self.hInset + Self.labelWidth + Self.hGap
        let barW = max(0, width - barX - Self.hGap - Self.percentWidth - Self.hInset)
        for row in rows {
            let labelH = row.label.fittingSize.height
            row.label.frame = NSRect(x: Self.hInset,
                                     y: y + (rowHeight - labelH) / 2.0,
                                     width: Self.labelWidth,
                                     height: labelH)
            row.bar.frame = NSRect(x: barX,
                                   y: y + (rowHeight - Self.barHeight) / 2.0,
                                   width: barW,
                                   height: Self.barHeight)
            let pctH = row.percent.fittingSize.height
            row.percent.frame = NSRect(x: width - Self.percentWidth - Self.hInset,
                                       y: y + (rowHeight - pctH) / 2.0,
                                       width: Self.percentWidth,
                                       height: pctH)
            y -= rowHeight + Self.rowGap
        }
    }

    // MARK: - Timer

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common so it keeps firing during menu tracking / resize.
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard !runInFlight else {
            DLog("WorkgroupUsage: skipping tick, previous run still in flight")
            return
        }
        guard let invocation = resolveInvocation() else {
            // Bundled script missing from the app bundle: a packaging
            // regression, not a transient empty result. Surface it as a
            // reportable error instead of the quiet "No usage data",
            // which would otherwise make the regression invisible.
            apply(report: WorkgroupUsageReport(
                bars: [],
                error: String(localized: "WorkgroupUsage.ScriptMissing",
                              defaultValue: "The AI usage helper is missing from iTerm2. This is a bug.",
                              comment: "AI usage toolbar item message when the bundled helper script is absent from the app bundle"),
                diagnostic: "bundled script \(provider.bundledScriptResourceName).sh not found in app bundle",
                reportable: true))
            return
        }
        runInFlight = true
        queue.async { [weak self] in
            let data = WorkgroupUsageToolbarItem.runCommand(
                launchPath: invocation.launchPath,
                arguments: invocation.arguments,
                timeout: 20)
            let report = WorkgroupUsageToolbarItem.decode(data: data)
            DispatchQueue.main.async {
                guard let self else { return }
                self.runInFlight = false
                self.apply(report: report)
            }
        }
    }

    // MARK: - Command

    // Returns the command to run, or nil when the provider's bundled
    // script is missing from the app bundle (a packaging regression the
    // caller surfaces as a reportable error). A user-supplied custom
    // command never returns nil.
    private func resolveInvocation() -> (launchPath: String, arguments: [String])? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let resource = provider.bundledScriptResourceName
            guard let path = Bundle(for: WorkgroupUsageToolbarItem.self)
                .path(forResource: resource, ofType: "sh") else {
                DLog("WorkgroupUsage: bundled \(resource).sh not found")
                return nil
            }
            return ("/bin/sh", [path])
        }
        return ("/bin/sh", ["-c", trimmed])
    }

    // Runs the command with a hard timeout and returns its stdout, or nil
    // on failure. Uses the shared iTermBufferedCommandRunner so timeout,
    // stderr draining, and SIGKILL escalation live in one place. stderr is
    // discarded (routed to /dev/null), which both avoids an unread pipe
    // filling and deadlocking the read, and keeps a stray warning from
    // corrupting the JSON on stdout; the bundled script already folds
    // claude's stderr into its own diagnostic field.
    private static func runCommand(launchPath: String,
                                   arguments: [String],
                                   timeout: TimeInterval) -> Data? {
        let runner = iTermBufferedCommandRunner(command: launchPath,
                                                withArguments: arguments,
                                                path: "/")
        runner.discardStandardError = true
        // Bound captured output so a runaway custom command can't grow
        // memory unbounded (1 MiB dwarfs any real usage JSON).
        runner.maximumOutputSize = NSNumber(value: 1024 * 1024)

        registerActiveRunner(runner)
        defer { unregisterActiveRunner(runner) }
        _ = runner.blockingRun(withTimeout: timeout)
        return runner.output
    }

    // MARK: - In-flight process registry

    // In-flight runners, so they can be terminated when iTerm2 quits.
    // Without this, a usage command still running at quit is reparented to
    // launchd and lingers (or hangs) after iTerm2 exits; frequent
    // quit/relaunch cycles would leak orphaned claude processes.
    private static let activeRunnersLock = NSLock()
    private static var activeRunners: [iTermBufferedCommandRunner] = []
    private static var didInstallTerminationObserver = false

    // Install once, on the main thread, from init.
    private static func installTerminationObserverIfNeeded() {
        guard !didInstallTerminationObserver else { return }
        didInstallTerminationObserver = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main) { _ in
            activeRunnersLock.lock()
            let runners = activeRunners
            activeRunnersLock.unlock()
            // Terminate outside the lock to avoid reentrancy with the
            // register/unregister calls the runners' teardown may trigger.
            for runner in runners {
                runner.terminate()
            }
        }
    }

    private static func registerActiveRunner(_ runner: iTermBufferedCommandRunner) {
        activeRunnersLock.lock()
        activeRunners.append(runner)
        activeRunnersLock.unlock()
    }

    private static func unregisterActiveRunner(_ runner: iTermBufferedCommandRunner) {
        activeRunnersLock.lock()
        activeRunners.removeAll { $0 === runner }
        activeRunnersLock.unlock()
    }

    private static func decode(data: Data?) -> WorkgroupUsageReport {
        guard let data, !data.isEmpty else {
            // No output at all. Could be transient (command still warming
            // up, a slow claude launch), so don't nag the user to report.
            return WorkgroupUsageReport(bars: [],
                                        error: String(localized: "WorkgroupUsage.NoOutput",
                                                      defaultValue: "No usage data",
                                                      comment: "AI usage toolbar item message when the command produced no output"),
                                        diagnostic: nil,
                                        reportable: false)
        }
        do {
            return try JSONDecoder().decode(WorkgroupUsageReport.self, from: data)
        } catch {
            // The command emitted something that isn't our JSON contract.
            // That's a real defect (our shipped script, or a user's custom
            // command) worth reporting, so surface the raw bytes.
            DLog("WorkgroupUsage: JSON decode failed: \(error)")
            let raw = String(data: data, encoding: .utf8)
            return WorkgroupUsageReport(bars: [],
                                        error: String(localized: "WorkgroupUsage.BadOutput",
                                                      defaultValue: "Unreadable usage data",
                                                      comment: "AI usage toolbar item message when the command output could not be parsed"),
                                        diagnostic: raw,
                                        reportable: true)
        }
    }

    // MARK: - Rendering

    private func apply(report: WorkgroupUsageReport) {
        let bars = report.bars
        if bars.isEmpty {
            for row in rows {
                row.label.removeFromSuperview()
                row.bar.removeFromSuperview()
                row.percent.removeFromSuperview()
            }
            rows = []
            messageLabel.isHidden = false
            let summary = report.error
                ?? String(localized: "WorkgroupUsage.Unavailable",
                          defaultValue: "AI usage unavailable",
                          comment: "AI usage toolbar item message when no usage bars are available")
            lastErrorSummary = summary
            lastDiagnostic = report.diagnostic
            lastReportable = (report.reportable ?? false)

            // The ladybug prefix is iTerm2's convention for an error shown
            // in the UI (see the status-bar components). Only the compact
            // toolbar label gets it; the summary stays clean for the alert
            // and the copyable report.
            let displayed = Self.errorPrefix + summary
            let clickable = lastReportable
            if clickable {
                // Nudge that there's more behind the click, and wire the
                // click to the report sheet.
                messageLabel.stringValue = displayed
                let hint = String(localized: "WorkgroupUsage.ClickForDetails",
                                  defaultValue: "\(summary) (click for details)",
                                  comment: "Tooltip on the AI usage toolbar item when an error can be reported; the placeholder is the short error summary")
                messageLabel.toolTip = hint
                container.toolTip = hint
                container.onClick = { [weak self] in self?.presentReport() }
            } else {
                messageLabel.stringValue = displayed
                messageLabel.toolTip = summary
                container.toolTip = summary
                container.onClick = nil
            }
            container.window?.invalidateCursorRects(for: container)
            delegate?.itemDidChange(sender: self)
            return
        }

        // A good report clears any prior error affordance.
        lastErrorSummary = nil
        lastDiagnostic = nil
        lastReportable = false
        container.onClick = nil
        container.toolTip = nil
        container.window?.invalidateCursorRects(for: container)

        messageLabel.isHidden = true
        rebuildRows(count: bars.count)
        for (i, bar) in bars.enumerated() {
            let row = rows[i]
            row.label.stringValue = Self.shortLabel(for: bar)
            row.bar.fraction = CGFloat(bar.clampedFraction)
            row.percent.stringValue = Self.percentString(bar.clampedFraction)
            let tooltip = Self.tooltip(label: bar.label, detail: bar.detail)
            row.label.toolTip = tooltip
            row.bar.toolTip = tooltip
            row.percent.toolTip = tooltip
        }
        delegate?.itemDidChange(sender: self)
    }

    // MARK: - Error reporting

    // Show the full error plus a copyable report the user can send to the
    // developer. Reached by clicking the item when a report is reportable
    // (e.g. the usage format wasn't recognized).
    private func presentReport() {
        let summary = lastErrorSummary
            ?? String(localized: "WorkgroupUsage.Unavailable",
                      defaultValue: "AI usage unavailable",
                      comment: "AI usage toolbar item message when no usage bars are available")
        let report = reportText(summary: summary)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = summary
        alert.informativeText = String(localized: "WorkgroupUsage.ReportGuidanceIntro",
                                        defaultValue: "iTerm2 couldn’t read the AI usage report. Updating iTerm2 to the latest version may fix this. If you’re already up to date, click “Report a Bug” to open a pre-filled report. The full details below are also copied to your clipboard.",
                                        comment: "Guidance shown when the AI usage format couldn’t be parsed") + "\n\n" + report
        alert.addButton(withTitle: String(localized: "WorkgroupUsage.ReportBug",
                                           defaultValue: "Report a Bug",
                                           comment: "Button that opens a pre-filled bug report and copies the details to the clipboard"))
        alert.addButton(withTitle: String(localized: "General.Cancel",
                                           defaultValue: "Cancel",
                                           comment: "Cancel button"))

        let url = Self.bugReportURL(title: summary, body: report)
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                // Clipboard first as the reliable fallback: URL length
                // limits (and prefill support) can truncate what the link
                // carries, but the clipboard always has the whole report.
                let pboard = NSPasteboard.general
                pboard.clearContents()
                pboard.setString(report, forType: .string)
                if let url {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        if let window = container.window {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    // The clipboard payload: enough context for the developer to act on,
    // built from what we know locally plus the command's diagnostic.
    private func reportText(summary: String) -> String {
        let version = Bundle.main
            .infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let custom = command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "no (bundled script)" : "yes"
        // Markdown mirroring the AI Usage issue template, so the report
        // reads cleanly whether it lands in the template or replaces it.
        var lines = ["## What happened",
                     "",
                     summary,
                     "",
                     "## Environment",
                     "",
                     "- iTerm2 version: \(version)",
                     "- Provider: \(provider.displayName)",
                     "- Custom command: \(custom)"]
        if let diagnostic = lastDiagnostic, !diagnostic.isEmpty {
            lines.append("")
            lines.append("## Diagnostic")
            lines.append("")
            lines.append("```")
            lines.append(diagnostic)
            lines.append("```")
        }
        return lines.joined(separator: "\n")
    }

    // Build the GitLab new-issue URL with the report pre-filled via the
    // issue[title]/issue[description] query params. Returns the bare page
    // URL if composition somehow fails, so the button still does something
    // useful (open the tracker) with the report on the clipboard.
    private static func bugReportURL(title: String, body: String) -> URL? {
        let trimmed = body.count > maxURLDescription
            ? String(body.prefix(maxURLDescription))
                + "\n\n"
                + String(localized: "WorkgroupUsage.ReportTruncated",
                         defaultValue: "…(truncated; full report copied to your clipboard)",
                         comment: "Appended to a pre-filled bug report body when it was shortened to fit the URL")
            : body
        guard var components = URLComponents(string: bugReportBaseURL) else {
            return URL(string: bugReportBaseURL)
        }
        components.queryItems = [
            URLQueryItem(name: "issuable_template", value: bugReportTemplate),
            URLQueryItem(name: "issue[title]", value: title),
            URLQueryItem(name: "issue[description]", value: trimmed),
        ]
        return components.url ?? URL(string: bugReportBaseURL)
    }

    private func rebuildRows(count: Int) {
        guard rows.count != count else { return }
        for row in rows {
            row.label.removeFromSuperview()
            row.bar.removeFromSuperview()
            row.percent.removeFromSuperview()
        }
        rows = (0..<count).map { _ in WorkgroupUsageRowViews() }
        for row in rows {
            container.addSubview(row.label)
            container.addSubview(row.bar)
            container.addSubview(row.percent)
        }
    }

    // Caption for the cramped toolbar row. Prefer the data source's own
    // `short` (only it knows how to abbreviate an arbitrary window or
    // model name); fall back to a derived abbreviation when it omits one.
    // The full label lives in the tooltip either way.
    private static func shortLabel(for bar: WorkgroupUsageBar) -> String {
        if let short = bar.short?.trimmingCharacters(in: .whitespacesAndNewlines),
           !short.isEmpty {
            return short
        }
        return derivedShortLabel(for: bar.label)
    }

    // Fallback abbreviation when the command supplies no `short`:
    // uppercase initials of the first alphanumeric run(s), capped at
    // two characters.
    private static func derivedShortLabel(for label: String) -> String {
        let words = label
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return "?" }
        if words.count == 1 {
            return String(words[0].prefix(1)).uppercased()
        }
        let initials = words.prefix(2).compactMap { $0.first }
        return String(initials).uppercased()
    }

    private static func percentString(_ fraction: Double) -> String {
        return "\(Int((fraction * 100).rounded()))%"
    }

    private static func tooltip(label: String, detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return label }
        // Self-contained values on either side; safe to interpolate.
        return String(localized: "WorkgroupUsage.Tooltip",
                      defaultValue: "\(label): \(detail)",
                      comment: "AI usage toolbar item tooltip: %1$@ is the limit name, %2$@ is the reset detail")
    }
}
