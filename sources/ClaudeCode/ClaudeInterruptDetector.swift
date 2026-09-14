//
//  ClaudeInterruptDetector.swift
//  iTerm2SharedARC
//
//  Closes the one gap the cc-status hook cannot: Claude Code fires no hook
//  when the user interrupts a turn with Esc, so a session whose
//  tab status says “working” (or “waiting”, for a permission prompt that
//  was dismissed) stays that way until the next prompt is submitted.
//
//  The detector is keystroke-gated rather than polling. It does nothing
//  until Esc is typed into a session that is running claude and
//  whose tab status is working or waiting. Only then does it read the
//  visible screen a few times over the next couple of seconds, looking for
//  Claude Code’s own “Interrupted · What should Claude do instead?” line as
//  the positive idle signal. A live spinner (elapsed-time counter) on
//  screen means the turn is still running, so the status is left alone.
//  When neither signal appears the detector gives up without changing
//  anything: the failure mode under UI drift is “same as today”, never a
//  false idle in the middle of a running turn.
//

import Foundation

@objc(iTermClaudeInterruptDetector)
@MainActor
final class ClaudeInterruptDetector: NSObject {
    @objc static let instance = ClaudeInterruptDetector()

    enum Verdict: Equatable {
        // The interrupt line is on screen and no spinner is live.
        case interrupted
        // A live spinner is on screen: the turn is still running.
        case working
        // Neither signal is present (still rendering, or the UI changed).
        case unknown
    }

    // Claude Code renders the interrupt as the dim text “Interrupted” followed
    // by “· What should Claude do instead?” (verified against 2.1.270). Older
    // and tool-result forms show “⎿ Interrupted” alone. Either form is
    // accepted; both only appear after an actual interrupt.
    nonisolated private static let interruptedRegex = try! NSRegularExpression(
        pattern: "Interrupted\\s*·\\s*What should Claude do instead|⎿\\s*Interrupted\\b")

    // The parenthesized elapsed timer, e.g. “(49s · ↓ 3.4k tokens)” or
    // “(1m 13s · still thinking…)”, renders only while a turn is live; the
    // finished line reads “Cooked for 1m 12s” without the open paren and
    // middot, so it does not match. The token counter and “esc to interrupt”
    // hint are kept as fallbacks for spinner variants without a timer.
    nonisolated private static let workingRegex = try! NSRegularExpression(
        pattern: "\\((?:\\d+h )?(?:\\d+m )?\\d+s ·|[↓↑]\\s*[\\d.,]+k?\\s+tokens|esc to interrupt")

    // First read waits for Claude Code to repaint after the keypress; later
    // reads cover a slow render. Six reads over three seconds bounds the
    // work per keypress.
    static let pollInterval: TimeInterval = 0.5
    static let maxPolls = 6

    // One in-flight check per session; a second Esc restarts it.
    private var pending = [String: Task<Void, Never>]()

    private override init() {
        super.init()
    }

    @objc func start() {
        DLog("ClaudeInterruptDetector.start()")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWillTerminate(_:)),
            name: .iTermSessionWillTerminate,
            object: nil)
    }

    // MARK: - Entry point from PTYSession

    // Called on the main thread for every keystroke written to the pty. It
    // must stay cheap: everything past the byte check happens only for a
    // bare Esc in a claude session with an active status. (Ctrl-C is not
    // handled: it does not dismiss permission prompts, so it is not the
    // interrupt key Claude Code documents.)
    @objc func session(_ session: PTYSession, didSendKeyData data: Data) {
        guard Self.isEscapeKey(data) else {
            return
        }
        guard Self.isInterruptible(status: session.tabStatus?.statusText) else {
            return
        }
        guard GlobalJobMonitor.instance.sessionGUIDs(runningJob: "claude").contains(session.guid) else {
            DLog("ClaudeInterruptDetector: \(session.guid) is not running claude")
            return
        }
        RLog("ClaudeInterruptDetector: interrupt key in \(session.guid) while \(session.tabStatus?.statusText ?? "")")
        scheduleCheck(for: session)
    }

    // MARK: - Classification

    // Esc as written to the pty. Claude Code currently runs without kitty
    // key reporting, so Esc is the bare byte; if it ever enables the
    // disambiguate flag, iTerm2’s modern key mapper sends CSI 27 u instead
    // (optionally with a “;1” modifier field). Other keys never take these
    // shapes: legacy Alt+key is ESC plus a character, and cursor keys end in
    // a different final byte.
    nonisolated private static let escapeEncodings: [Data] = [
        Data([0x1b]),
        Data("\u{1b}[27u".utf8),
        Data("\u{1b}[27;1u".utf8),
    ]

    nonisolated static func isEscapeKey(_ data: Data) -> Bool {
        return escapeEncodings.contains(data)
    }

    nonisolated static func isInterruptible(status: String?) -> Bool {
        guard let status = status?.lowercased() else {
            return false
        }
        return status == "working" || status == "waiting"
    }

    // Pure so it can be unit-tested against captured screens. A live spinner
    // wins over a stale interrupt line: the user may have already started a
    // new turn while the previous “Interrupted” line is still visible.
    nonisolated static func classify(screenText: String) -> Verdict {
        let range = NSRange(screenText.startIndex..., in: screenText)
        if workingRegex.firstMatch(in: screenText, range: range) != nil {
            return .working
        }
        if interruptedRegex.firstMatch(in: screenText, range: range) != nil {
            return .interrupted
        }
        return .unknown
    }

    // MARK: - Private

    private func scheduleCheck(for session: PTYSession) {
        let guid = session.guid
        pending[guid]?.cancel()
        pending[guid] = Task { [weak self, weak session] in
            // A cancelled task was replaced by a newer one (or the session
            // ended); only the live task may clear the slot.
            defer {
                if !Task.isCancelled {
                    self?.pending[guid] = nil
                }
            }
            for poll in 0..<Self.maxPolls {
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
                guard !Task.isCancelled, let self, let session else {
                    return
                }
                // A hook may have landed in the meantime (Stop after a
                // natural turn end, PreToolUse from a new turn). Its
                // verdict is authoritative; ours is only for the gap.
                guard Self.isInterruptible(status: session.tabStatus?.statusText) else {
                    DLog("ClaudeInterruptDetector: status changed under us, done")
                    return
                }
                let text = WorkgroupIntrospection.screenContents(forSession: session,
                                                                 requestedLines: 100).text
                let verdict = Self.classify(screenText: text)
                DLog("ClaudeInterruptDetector: poll \(poll) verdict=\(verdict) screen=\(text)")
                switch verdict {
                case .working:
                    RLog("ClaudeInterruptDetector: spinner still live in \(guid), leaving status")
                    return
                case .interrupted:
                    RLog("ClaudeInterruptDetector: interrupt confirmed in \(guid), setting idle")
                    self.setIdle(session)
                    return
                case .unknown:
                    continue
                }
            }
            // Neither signal after every poll. Either the UI changed shape
            // (see the regexes above) or the key did something else, such
            // as closing a dialog. Leave the hook’s state in place.
            RLog("ClaudeInterruptDetector: no signal in \(guid) after \(Self.maxPolls) polls, leaving status")
        }
    }

    // Mirrors what cc-status sends for Stop with no background tasks, so
    // the tab looks exactly as it would after a hook-reported idle.
    private func setIdle(_ session: PTYSession) {
        let update = VT100TabStatusUpdate()
        update.statusPresence = .set
        update.status = "idle"
        var dot = iTermSRGBColor(r: 0, g: 0, b: 0)
        if iTermSRGBColorFromHexString("#00d75f", &dot) {
            update.indicatorPresence = .set
            update.indicator = dot
        }
        var text = iTermSRGBColor(r: 0, g: 0, b: 0)
        if iTermSRGBColorFromHexString("#888888", &text) {
            update.statusColorPresence = .set
            update.statusColor = text
        }
        update.detailPresence = .cleared
        session.screenSetTabStatus(update)
    }

    @objc private func sessionWillTerminate(_ notification: Notification) {
        guard let session = notification.object as? PTYSession else {
            return
        }
        pending.removeValue(forKey: session.guid)?.cancel()
    }
}
