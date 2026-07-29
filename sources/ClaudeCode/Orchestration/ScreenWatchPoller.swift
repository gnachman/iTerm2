//
//  ScreenWatchPoller.swift
//  iTerm2SharedARC
//
//  Drives a headless AIConversation to decide when a session has reached
//  its watch goal by reading its rendered screen. Used in two cases:
//  state watchers on sessions that report no machine-readable status (no
//  OSC 21337 / cc-status, so the exact tab-status-transition path can't
//  fire), and plain-English condition watchers, which are always judged
//  from the screen regardless of status reporting. See
//  OrchestratorDispatcher's startScreenPoll / screenPollFinished and
//  WorkgroupIntrospection.reportsSessionStatus.
//
//  Why a model instead of a screen-stability heuristic: a coding agent (or
//  any program) churns silently while working — `sleep 10` leaves the screen
//  byte-for-byte static yet the task isn't done — so "the screen stopped
//  changing" is NOT "the work finished". What distinguishes working from done
//  is screen *content*: an animated spinner, an increasing elapsed-time
//  counter, a "Working…/esc to interrupt" line, vs. a ready input prompt.
//  Judging that generalizes across unknown TUIs, which is what the model is
//  for. We hand it the first capture plus the two most recent ones so it can
//  see change over time (is the indicator still animating?) without the
//  conversation growing without bound.

import Foundation

@MainActor
final class ScreenWatchPoller {
    // One rendered-screen reading at a point in time.
    private struct Capture {
        var elapsed: Int   // seconds since monitoring began
        var text: String
    }

    private let watcher: WorkgroupWatcher
    private let sessionProvider: () -> PTYSession?
    private let onReached: () -> Void
    private let onTimedOut: () -> Void

    private var task: Task<Void, Never>?
    // Held only for its lifetime so cancel() can abort an in-flight model
    // request. AIConversation is a struct but shares its controller (a
    // class) across copies, so cancelling this copy cancels the request
    // the run loop is awaiting.
    private var inflight: AIConversation?

    // Give up and hand back to the orchestrator after this much wall-clock
    // time without reaching the target. The old 5-minute cap woke the
    // orchestrator (a full, user-visible model turn) for every watch that
    // outran it, and a code review routinely runs longer, so that produced a
    // stream of "watch timed out, re-registering" chatter for no user
    // benefit. The poller now keeps watching on its own for hours, polling
    // less and less often (see backoff), and only surfaces watchTimedOut as a
    // rare backstop for a condition that may simply never come true.
    static let deadline: TimeInterval = 6 * 3600  // 6 hours

    /// A human-readable form of `deadline`, so the dispatcher's watchTimedOut
    /// message can name the wait without a separate literal that drifts when
    /// `deadline` changes.
    static var deadlineDescription: String {
        // Below an hour, name it in minutes: rounding hours would emit
        // "0 hours" for any sub-30-minute deadline (e.g. the former 5-minute
        // value), which reads as broken in the model-visible timeout message.
        guard deadline >= 3600 else {
            let minutes = max(1, Int((deadline / 60).rounded()))
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        let hours = Int((deadline / 3600).rounded())
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    // Poll cadence widens the longer a watch runs, to bound token cost on a
    // long wait (each poll is an economy-model round-trip):
    //   * first 5 minutes: quadratic backoff 3 + n*n (responsive on short
    //     tasks: 3, 4, 7, 12, 19, 28…), unchanged.
    //   * after 5 minutes: no tighter than every 2 minutes.
    //   * after 1 hour: no tighter than every 10 minutes.
    // A 10-minute ceiling also caps how stale the reading can get once a
    // watch is old, so a late completion is still noticed within ten minutes.
    private static let slowAfter: TimeInterval = 300      // 5 minutes
    private static let slowerAfter: TimeInterval = 3600   // 1 hour
    private static let slowInterval: TimeInterval = 120   // >= 2 min after slowAfter
    private static let slowerInterval: TimeInterval = 600 // >= 10 min after slowerAfter
    private static let maxInterval: TimeInterval = 600    // never slower than 10 min

    // Delay before the next poll, given how many polls have run (n) and how
    // long the watch has been active. The quadratic keeps early detection
    // tight; the elapsed-based floors slow it down in tiers so a multi-hour
    // watch is not billed a model round-trip every minute or two.
    private static func backoff(pollIndex n: Int, elapsed: TimeInterval) -> TimeInterval {
        let quadratic = TimeInterval(3 + n * n)
        let floor: TimeInterval
        if elapsed >= slowerAfter {
            floor = slowerInterval
        } else if elapsed >= slowAfter {
            floor = slowInterval
        } else {
            floor = 0
        }
        return min(max(quadratic, floor), maxInterval)
    }

    init(watcher: WorkgroupWatcher,
         sessionProvider: @escaping () -> PTYSession?,
         onReached: @escaping () -> Void = {},
         onTimedOut: @escaping () -> Void = {}) {
        self.watcher = watcher
        self.sessionProvider = sessionProvider
        self.onReached = onReached
        self.onTimedOut = onTimedOut
    }

    // One screen read + model judgement, with no run loop, deadline, or
    // backoff. Returns true only when the model positively confirms the
    // watcher's target. Used by the tab-status escalation backstop, which
    // owns its own re-check cadence (a single check every few minutes)
    // rather than running a continuous poll. The instance must be retained
    // for the duration of the call so cancel() can abort the in-flight
    // model request if the watch is resolved or dropped mid-check; an
    // unreadable or cancelled judgement returns false (treated as not-yet,
    // same as the run loop treats `unknown`).
    func checkOnce() async -> Bool {
        guard let session = sessionProvider() else { return false }
        let contents = WorkgroupIntrospection.screenContents(
            forSession: session, requestedLines: 150)
        let capture = Capture(elapsed: 0, text: contents.text)
        let verdict = await evaluate(window: [capture], kind: contents.kind)
        return verdict == .reached
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.run()
        }
    }

    // Idempotent. Stops the loop and aborts any in-flight model request.
    // The run loop also re-checks Task.isCancelled after each await, so a
    // cancel that lands mid-request takes effect as soon as that request
    // resolves (or immediately, since cancelOutstandingOperation fails it).
    func cancel() {
        task?.cancel()
        task = nil
        inflight?.cancelOutstandingOperation()
        inflight = nil
    }

    // Trace the poll lifecycle to the debug log. The poller's model traffic
    // runs on a headless AIConversation that bypasses ChatAgent's console
    // logger, so this is the only window into what a statusless watch is
    // doing; replies are snippeted so a screen-derived answer stays short.
    private func log(_ message: String) {
        RLog("[ScreenWatchPoller \(watcher.roleName)] \(message)")
    }

    private static func snippet(_ text: String, limit: Int = 200) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if oneLine.count <= limit {
            return oneLine
        }
        return String(oneLine.prefix(limit)) + "…"
    }

    private func run() async {
        let start = Date()
        log("Started: watching by screen observation for "
            + watcher.goalDescription + ".")
        var pollIndex = 0
        var first: Capture?
        var previous: Capture?
        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= Self.deadline {
                log("Timed out after \(Int(elapsed))s without reaching "
                    + watcher.goalDescription + ".")
                onTimedOut()
                return
            }
            guard let session = sessionProvider() else {
                // Session vanished. The dispatcher's session-terminate
                // handler owns the watcherDropped status_update and cancels
                // us; nothing to publish from here, just stop.
                log("Session no longer resolvable; stopping.")
                return
            }
            let contents = WorkgroupIntrospection.screenContents(
                forSession: session, requestedLines: 150)
            let capture = Capture(elapsed: Int(elapsed.rounded()),
                                  text: contents.text)
            if first == nil { first = capture }
            let window = Self.window(first: first,
                                     previous: previous,
                                     current: capture)
            let verdict = await evaluate(window: window, kind: contents.kind)
            if Task.isCancelled { return }
            log("Poll \(pollIndex) at t=\(capture.elapsed)s: \(verdict).")
            if verdict == .reached {
                log("Target reached; firing status_update.")
                onReached()
                return
            }
            // notYet or unknown: keep polling until the target shows up or
            // the time cap fires.
            previous = capture
            let delay = Self.backoff(pollIndex: pollIndex, elapsed: elapsed)
            pollIndex += 1
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    // First capture plus the two most recent, oldest first, de-duplicated
    // by timestamp (early on first == previous == current).
    private static func window(first: Capture?,
                               previous: Capture?,
                               current: Capture) -> [Capture] {
        var result: [Capture] = []
        for capture in [first, previous, current].compactMap({ $0 }) {
            if !result.contains(where: { $0.elapsed == capture.elapsed }) {
                result.append(capture)
            }
        }
        return result
    }

    // The model's read of a single poll. `unknown` means the reply couldn't
    // be parsed even after asking the model to rephrase, OR the request
    // failed (no API key, network error, cancellation). The run loop treats
    // unknown like notYet — keep watching — so an unreadable answer never
    // fires a false positive and the watch still resolves via a later poll
    // or the time cap.
    private enum Verdict { case reached, notYet, unknown }

    // Judge one poll. If the first reply doesn't parse, ask once for a clean
    // REACHED/NOT_YET in the same conversation before giving up as unknown.
    // Prefer a cheaper same-vendor model for these frequent, low-stakes
    // judgements (e.g. Opus -> Haiku), where the primary chat model would be
    // overkill and too expensive to run every few seconds. nil (no economy
    // alternative, or an unconfigured/unknown model) leaves the conversation on
    // the user's configured chat model. The returned model preserves the
    // configured model's url/api, so a user's custom base URL (proxy/gateway) is
    // honored and the API key is not leaked to the public vendor host.
    private static func economyModel() -> AIMetadata.Model? {
        // A user-designated economy model (toggled in Manual AI Models) wins. It
        // is a full manual model with its own url/api/auth, so it is used
        // verbatim, honoring a custom base URL and its own vendor's API key.
        if let designated = userDesignatedEconomyModel() {
            return designated
        }
        guard let configured = LLMMetadata.model() else {
            return nil
        }
        return AIMetadata.economyModel(for: configured)
    }

    // The manual model the user marked as the economy model, if any, resolved to
    // a full model. nil if unset or no longer present among the manual models.
    private static func userDesignatedEconomyModel() -> AIMetadata.Model? {
        guard let name = iTermPreferences.string(forKey: kPreferenceKeyAIEconomyModelName),
              !name.isEmpty else {
            return nil
        }
        return LLMMetadata.manualModels().first { $0.name == name }
    }

    private func evaluate(window: [Capture], kind: SessionKind) async -> Verdict {
        let economyModel = Self.economyModel()
        var conversation = AIConversation(registrationProvider: nil)
        conversation.systemMessage = Self.systemPrompt(for: watcher)
        conversation.shouldThink = false
        // Set via modelOverride (a full model), not `model` (a name that
        // AIConversation re-resolves to the catalog's public endpoint), so the
        // configured transport/auth is preserved.
        conversation.modelOverride = economyModel
        conversation.add(text: Self.userPrompt(window: window, kind: kind),
                         role: .user)
        guard let (reply, amended) = await complete(conversation) else {
            log("Model request failed or was cancelled.")
            return .unknown
        }
        log("Model: \(Self.snippet(reply))")
        let verdict = Self.parseVerdict(reply)
        if verdict != .unknown {
            return verdict
        }
        if Task.isCancelled { return .unknown }
        // Unparseable: ask once for a clean answer in the same context, then
        // accept whatever we can parse (still unknown if it flubs it again).
        log("Unparseable reply; asking the model to rephrase.")
        // AIConversation's copy initializer carries neither modelOverride nor
        // shouldThink onto the amended conversation, so re-set both to keep the
        // rephrase turn on the economy model with thinking off.
        var retry = amended
        retry.modelOverride = economyModel
        retry.shouldThink = false
        retry.add(text: "Reply with exactly one word and nothing else: "
                      + "REACHED or NOT_YET.",
                  role: .user)
        guard let (secondReply, _) = await complete(retry) else {
            return .unknown
        }
        log("Model (rephrase): \(Self.snippet(secondReply))")
        return Self.parseVerdict(secondReply)
    }

    // Run one completion. Returns the assistant's text plus the conversation
    // amended with that reply (so a follow-up turn can be appended), or nil
    // if the request failed or the poller was cancelled. Tracks `inflight`
    // so cancel() can abort whichever request is outstanding.
    private func complete(
        _ conversation: AIConversation
    ) async -> (reply: String, conversation: AIConversation)? {
        if Task.isCancelled { return nil }
        inflight = conversation
        defer { inflight = nil }
        let amended: AIConversation? = await withCheckedContinuation { continuation in
            var resumed = false
            // Capture the conversation in its own completion closure so the
            // struct (and the controller it owns) outlives this synchronous
            // scope until the model replies.
            var held: AIConversation? = conversation
            held?.complete { result in
                held = nil
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result.successValue)
            }
        }
        guard let amended else { return nil }
        let body = amended.messages.last?.body.content ?? ""
        return (body, amended)
    }

    // First non-empty line carries the verdict. Lenient but unambiguous: an
    // explicit NOT_YET / "not yet" wins (checked first so "not reached"
    // doesn't read as REACHED), REACHED anywhere on the line counts, and
    // anything else is unknown so the caller can ask for a rephrase.
    private static func parseVerdict(_ reply: String) -> Verdict {
        let firstLine = reply
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .uppercased() ?? ""
        if firstLine.contains("NOT_YET") || firstLine.contains("NOT YET") {
            return .notYet
        }
        if firstLine.contains("REACHED") {
            return .reached
        }
        return .unknown
    }

    // Goal-specific instruction. For state watchers the detection logic
    // INVERTS by target: an activity indicator means "reached" for working
    // but "not yet" for idle, so each target spells out its own positive
    // evidence rather than sharing one finished-centric description.
    // Condition watchers get the caller's plain-English condition verbatim.
    private static func detectionInstruction(for watcher: WorkgroupWatcher) -> String {
        if let condition = watcher.condition {
            return "Your target is this plain-English condition, judged from "
                + "the rendered screen:\n\n"
                + condition + "\n\n"
                + "Conclude REACHED only when the screen positively shows the "
                + "condition is satisfied. If the screen is ambiguous, or the "
                + "condition describes something that has not visibly happened "
                + "yet, answer NOT_YET. Do not reinterpret the condition as a "
                + "generic idle/busy check; judge exactly what it says."
        }
        switch watcher.targetState ?? .idle {
        case .waiting:
            return "Your target: the program is BLOCKED waiting for the user "
                + "to answer a prompt or make a choice — a question, "
                + "confirmation, or menu is on screen expecting input before it "
                + "can continue. Conclude REACHED only when such a prompt is "
                + "visibly present. An activity indicator means it is still "
                + "working, not waiting; a plain idle prompt with no question "
                + "is also not waiting."
        case .working:
            return "Your target: the program is ACTIVELY working right now — an "
                + "animated spinner, an increasing elapsed-time counter, a "
                + "progress bar, a \"Working…/Thinking…\" line, or streaming "
                + "output that changes between captures is present. Conclude "
                + "REACHED as soon as the screen shows such active work. A "
                + "static idle ready prompt with no activity indicator is "
                + "NOT_YET."
        case .idle, .unknown:
            return "Your target: the program has FINISHED its current work and "
                + "is now idle at a ready input prompt, with no active progress "
                + "bar, spinner, elapsed-time counter, or other activity "
                + "indicator. While any activity indicator is present, or the "
                + "screen is changing in a way that shows ongoing work, it is "
                + "NOT_YET. Conclude REACHED only when the screen positively "
                + "shows an idle ready prompt."
        }
    }

    private static func systemPrompt(for watcher: WorkgroupWatcher) -> String {
        return """
        You are a silent monitor inside iTerm2. You are watching one terminal \
        session that an automated orchestrator is driving. The program in it \
        (often a coding agent or another interactive TUI) is being judged by \
        reading its rendered screen.

        Background on reading these screens: a program that is actively working \
        almost always shows an activity indicator that changes between \
        captures — an animated spinner, an increasing elapsed-time counter, a \
        progress bar, a "Working…/Thinking…/esc to interrupt" line, or \
        streaming output. A program that is idle shows a ready input prompt and \
        no such indicator. An unchanged or blank screen does NOT by itself \
        prove the program is idle — it may be computing silently (for example, \
        sleeping or waiting on a subprocess). Judge from positive evidence on \
        screen, not from the mere absence of change.

        \(detectionInstruction(for: watcher))

        Respond with EXACTLY one word on the first line: REACHED if the target \
        condition is satisfied, or NOT_YET if it is not. You may add a brief \
        reason (12 words or fewer) on a second line. Output nothing else.
        """
    }

    private static func userPrompt(window: [Capture], kind: SessionKind) -> String {
        var sections: [String] = []
        for (index, capture) in window.enumerated() {
            let label: String
            if index == 0 {
                label = "earliest capture, t=\(capture.elapsed)s"
            } else if index == window.count - 1 {
                label = "most recent capture, t=\(capture.elapsed)s"
            } else {
                label = "capture at t=\(capture.elapsed)s"
            }
            let body = capture.text.isEmpty ? "(blank screen)" : capture.text
            sections.append("----- \(label) -----\n\(body)")
        }
        let kindHint: String
        switch kind {
        case .tui:
            kindHint = "The captures are point-in-time snapshots of a "
                + "full-screen TUI."
        case .claudeCode, .shell, .other:
            kindHint = "The captures are the trailing lines of the session "
                + "transcript, oldest content first within each capture."
        }
        return kindHint + "\n\n" + sections.joined(separator: "\n\n")
            + "\n\nHas the target condition been reached?"
    }
}
