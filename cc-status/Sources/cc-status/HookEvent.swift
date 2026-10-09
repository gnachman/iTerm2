import Foundation

// Reading the hook event off stdin and deciding what it should change.

// The palette. Each status has one pair of colors wherever it is set.
let workingDot = "#ff9500"
let workingText = "#ff9500"
let waitingDot = "#5f87ff"
let waitingText = "#5f87ff"
let idleDot = "#00d75f"
let idleText = "#888888"
let doneDot = "#00d75f"
let doneText = "#00d75f"
let errorDot = "#ff3b30"
let errorText = "#ff3b30"

/// Which program's hooks are driving this run. Codex CLI (0.154+) runs the same hooks as Claude
/// Code with the same payload shape, so one binary serves both, but the two differ in what they
/// report: Codex sends no background_tasks, fires no Stop when a detached sub-agent finishes after
/// the turn that started it, has an Interrupt hook for Esc where Claude Code has none, and does
/// not draw the tab's progress ring for itself. The hook configuration says which one it is,
/// because session-boundary events carry nothing that could tell them apart.
enum Agent: Equatable {
    case claude
    case codex

    /// Reads `--agent codex` off the command line. Anything else is Claude Code.
    init(arguments: [String]) {
        if let index = arguments.firstIndex(of: "--agent"),
           index + 1 < arguments.count,
           arguments[index + 1] == "codex" {
            self = .codex
        } else {
            self = .claude
        }
    }
}

/// What one hook event says about the session. Every field is optional: an event may change only
/// some of them, and an unset field is left alone rather than cleared.
struct StatusUpdate {
    // status/colors are nil for updates that only store the background-task
    // count without changing what's displayed (SubagentStop reaching zero).
    var status: String? = nil
    var dotColor: String? = nil
    var textColor: String? = nil
    // nil = don't touch detail; non-nil (including "") = send --detail through.
    var detail: String? = nil
    // Whether this status is only true while the current turn is in flight, in
    // which case iTerm2 is asked to drop it back to idle when the session's
    // progress protocol reports the turn ended. That edge is the only signal an
    // interrupt produces: pressing Esc runs no hook at all, so without it a turn
    // cancelled mid-flight leaves the tab reading “working” or “waiting” until
    // the next turn.
    //
    // All of this is measured against Claude Code 2.1.274, by driving a session
    // under a pty and recording both the hook events and the escape sequences:
    //   • A turn start emits OSC 9;4;3 about 40ms after the prompt is submitted,
    //     and a turn end emits OSC 9;4;0 within about 120ms, whether it ended by
    //     itself, by an API error, or by Esc.
    //   • Esc emits no hook of any kind. Nothing else reports the interrupt.
    //   • The indicator stays on for the whole turn, including the 15s a
    //     permission prompt sat open waiting for an answer, and it does not stop
    //     when Esc is swallowed by the slash-command menu mid-turn. That is why
    //     the waiting statuses are armed too: the only thing that stops the
    //     indicator under a permission prompt is dismissing it.
    // If a later version stops the indicator while blocked on the user, a waiting
    // status would expire to idle while the prompt is still up, so recheck this
    // before trusting it on a much newer Claude Code.
    //
    // Background work is deliberately not accounted for here: the fallback is
    // always plain idle. iTerm2 holds an expiration back while the background
    // task count it was told about is non-zero and applies it when the count
    // reaches zero, so the simple fallback still converges on the truth.
    //
    // Never set on the Codex path. Codex emits no progress protocol of its own;
    // cc-status writes the ring for it (see It2Runner), and it writes the
    // stopped state for a permission prompt as well as for idle, so an armed
    // expiration would drop a “waiting” to idle while the prompt is still up.
    // Codex reports Esc through its Interrupt hook instead, which closes the
    // turn the way Stop does.
    var expiresOnProgressEnd = false
    // nil = don't touch the stored count; non-nil = send --background-tasks.
    // iTerm2 keeps the count in RAM only (never written to disk); it exists
    // so a later idle_prompt, whose payload carries no task info, can read
    // back what the last Stop/SubagentStop knew.
    var backgroundTasks: Int? = nil
    // Change the count by this instead of assigning it. Only Codex uses it: Claude
    // Code is handed the true count in every payload, so it has nothing to work
    // out and nothing to race over. Never set alongside backgroundTasks; iTerm2
    // refuses a request carrying both.
    var backgroundTasksDelta: Int? = nil
    // nil = leave the turn flag alone; true/false = record it in the same
    // set-status that carries the display. Codex CLI fires no Stop when a
    // detached sub-agent finishes after the parent went idle, so SubagentStop
    // needs to know whether the turn is still open; iTerm2 keeps that flag
    // beside the count, RAM only like the count. One call means one outcome: a
    // hook killed before it (Codex allows Interrupt one second by default)
    // changes nothing, leaving a turn that still looks open, which only costs a
    // spurious “working” until the next event; a hook killed after it has left
    // the display and the flag consistent. There is no state in which the flag
    // reads closed while the display is stale, which is what would let a
    // sub-agent's SubagentStop report a false idle.
    var turnOpen: Bool? = nil
    // Send the update with preconditions that iTerm2 checks as it applies it:
    // the turn must still be closed and no work still counted, or the update is
    // dropped whole. For a done decided from a status read a round trip
    // earlier: a prompt submitted in between has reopened the turn and written
    // “working”, and an unconditional done would cover it until the next tool
    // call, or for the whole turn if it uses none.
    var onlyWhenFinished = false
    // Set on the Codex path whenever the display about to be written says work
    // is still running. The count that justified it was read a moment earlier,
    // and a sub-agent finishing in between either saw the turn as still open and
    // stayed quiet (a turn ending) or wrote its own idle that this write is about
    // to cover (a sibling's SubagentStop). So the write asks for the status as it
    // stood once it landed: if no work is counted and the turn is closed, this
    // is how the turn ended, said in a second write. Reading it again afterwards would
    // cost the same round trip and leave the same gap open. Anything that
    // finishes after this write lands sees “working” and reports done itself
    // (see SubagentStop). The second write carries what it assumed as
    // preconditions (see onlyWhenFinished), so a prompt that lands in between
    // keeps its “working”. The ending is the turn's own (done, error, or idle
    // for a cancel), since it is this turn's end the second write reports.
    var endingIfTasksFinished: (ending: TurnEnding, detail: String)? = nil

    /// Whether there is anything to send.
    var isEmpty: Bool {
        return status == nil && dotColor == nil && textColor == nil && detail == nil &&
               !expiresOnProgressEnd && backgroundTasks == nil && backgroundTasksDelta == nil &&
               turnOpen == nil
    }

    mutating func showWorking(detail: String?) {
        status = "working"
        dotColor = workingDot
        textColor = workingText
        self.detail = detail
    }

    mutating func showWaiting(detail: String?) {
        status = "waiting"
        dotColor = waitingDot
        textColor = waitingText
        self.detail = detail
    }

    mutating func showIdle(detail: String?) {
        status = "idle"
        dotColor = idleDot
        textColor = idleText
        self.detail = detail
    }

    /// The turn finished and its result is waiting for the user. iTerm2 ranks
    /// this above work in progress and turns it idle once the user types in
    /// the session.
    mutating func showDone(detail: String?) {
        status = "done"
        dotColor = doneDot
        textColor = doneText
        self.detail = detail
    }

    /// The turn ended in an error. Dismissed like done.
    mutating func showError(detail: String?) {
        status = "error"
        dotColor = errorDot
        textColor = errorText
        self.detail = detail
    }

    /// How a turn that ended with no work left reads.
    enum TurnEnding {
        /// Finished, with a result the user has not seen.
        case done
        /// Failed.
        case error
        /// Cancelled: nothing new to look at.
        case idle
    }

    mutating func showEnded(_ ending: TurnEnding, detail: String?) {
        switch ending {
        case .done:
            showDone(detail: detail)
        case .error:
            showError(detail: detail)
        case .idle:
            showIdle(detail: detail)
        }
    }
}

/// The event on stdin, or nil when there is nothing usable to act on.
func readHookEvent() -> (name: String, json: [String: Any])? {
    let inputData = FileHandle.standardInput.readDataToEndOfFile()
    guard !inputData.isEmpty,
          let json = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
          let eventName = json["hook_event_name"] as? String else {
        return nil
    }
    return (eventName, json)
}

// MARK: - Event to status

/// Decide what one hook event should change, or nil for an event with nothing to say.
///
/// Detail lifecycle:
///   • SET on events that carry rich, at-a-glance info (PermissionRequest, Stop,
///     Notification for unusual subtypes).
///   • CLEARED (set to "") on events that make prior detail stale: the start of a
///     new turn (UserPromptSubmit), ongoing tool activity (Pre/PostToolUse), and
///     session boundaries (SessionStart/End). This is what stops "Allow Edit: …"
///     from sticking around after the user grants permission.
///   • LEFT ALONE (nil) for duplicate signals: Notification(permission_prompt)
///     would overwrite PermissionRequest's richer detail; Notification(idle_prompt)
///     would overwrite Stop's last_assistant_message.
///
/// Reading the count iTerm2 holds costs an it2 round trip (~200 ms), so only Codex pays for it
/// outside the idle nudge; the increment and the turn flag ride on set-status calls the hook was
/// already making.
func statusUpdate(forEvent eventName: String,
                  json: [String: Any],
                  address: Address,
                  agent: Agent) -> StatusUpdate? {
    var update = StatusUpdate()
    let isCodex = agent == .codex
    let lastMessage = lastMessageDetail(json)

    /// The one rule for an event that ends a turn: stay working while background work remains,
    /// report how the turn ended otherwise. Stop, StopFailure, Interrupt and the idle nudge all
    /// answer it the same way, so they all come through here and cannot drift apart as events are
    /// added. On the Codex path it also closes the turn and, with work still counted, asks for the
    /// status as it stood once the write landed (see StatusUpdate.endingIfTasksFinished).
    func endTurn(running: Int, ending: StatusUpdate.TurnEnding, detail: String) {
        if running > 0 {
            update.showWorking(detail: backgroundDetail(count: running))
        } else {
            update.showEnded(ending, detail: detail)
        }
        if isCodex {
            update.turnOpen = false
            if running > 0 {
                update.endingIfTasksFinished = (ending, detail)
            }
        }
    }

    switch eventName {
    case "UserPromptSubmit", "PreToolUse", "PostToolUse":
        update.showWorking(detail: "")  // new turn / tool activity, so previous detail is stale
        update.expiresOnProgressEnd = true
        if eventName == "UserPromptSubmit", isCodex {
            update.turnOpen = true
        }
    case "PermissionRequest":
        update.showWaiting(detail: permissionDetail(json))
        update.expiresOnProgressEnd = true
    case "Notification":
        let notificationType = json["notification_type"] as? String
        if notificationType == "idle_prompt" {
            // Verified against Claude Code 2.1.201: idle_prompt payloads do
            // NOT carry background_tasks, so read back the count the
            // Stop/SubagentStop handlers stored in iTerm2. Without the
            // fallback, the idle nudge (~60s after Stop) would flip a
            // working-because-background session to idle, resurrecting the
            // false-idle bug.
            let current = storedStatus(addressArgs: address.args)
            let running = backgroundTaskCount(json) ?? current?.backgroundTasks ?? 0
            // The nudge repeats a turn ending that Stop already reported. When
            // the tab still shows that ending, leave it: the nudge carries no
            // message, and re-sending done would replace Stop's with nothing,
            // or, after the user typed in the session and iTerm2 turned it
            // idle, put a result they have seen back at the top of the list.
            if running == 0, let shown = current?.status, ["done", "error", "idle"].contains(shown) {
                return nil
            }
            // Re-assert the last message when the payload has one. It also
            // replaces a stale "N background tasks running" line from an earlier
            // Stop. Without a message, clear the detail instead:
            // an earlier Stop may have set "N background tasks running" and the
            // tasks have since finished without another Stop (background shell
            // commands end silently); leaving that line next to an idle dot would
            // be false. The cost is that Stop's last_assistant_message no longer
            // survives the nudge (2.1.201 idle_prompt payloads lack the message);
            // truthful-but-empty beats sticky-but-possibly-false.
            endTurn(running: running, ending: .done, detail: lastMessage)
        } else {
            // Skip detail for permission_prompt (PermissionRequest carries it better).
            // Other subtypes (auth_success, elicitation_dialog, ...) get the message.
            var message: String? = nil
            if notificationType != "permission_prompt", let raw = json["message"] as? String {
                message = condense(raw)
            }
            update.showWaiting(detail: message)
            update.expiresOnProgressEnd = true
        }
    case "Stop":
        // Stop fires whenever the main loop finishes a turn, including while
        // background subagents (Agent tool with run_in_background) and
        // background Bash tasks keep working. In that case the session is not
        // meaningfully done: a completion watcher that trusts "done" here
        // fires on every between-subagents lull. background_tasks (Claude
        // Code 2.1.198+; shape verified against 2.1.201) lists the
        // still-running work; stay "working" until a Stop arrives with none.
        // Store the count in iTerm2 only when the payload actually carried
        // the field: on older Claude Code it never exists, and the stored
        // count correctly stays at its initial zero. Codex never sends the
        // field; its count is the one SubagentStart/SubagentStop keep in iTerm2.
        let running: Int
        if let counted = backgroundTaskCount(json) {
            running = counted
            update.backgroundTasks = counted
        } else if isCodex {
            running = storedBackgroundTaskCount(addressArgs: address.args)
        } else {
            running = 0
        }
        endTurn(running: running, ending: .done, detail: lastMessage)
    case "Interrupt":
        // Codex CLI only: Esc cancelled the turn and no Stop follows.
        guard isCodex else {
            return nil
        }
        // Codex gives Interrupt and SessionEnd one second by default, three at
        // most, while other events get 600. At roughly 200 ms per it2 call the
        // two calls below fit (three when a sub-agent finished during the write),
        // and tests/codex-hooks.json asks for "timeout": 3 anyway. A hook killed
        // partway through is survivable: the display and the turn flag travel in
        // one call (see StatusUpdate.turnOpen), so what survives is either
        // nothing, a turn that still looks open until the next prompt reopens it
        // and its Stop closes it, or a consistent close.
        // The count is kept: Esc interrupts only the root thread, a spawned
        // agent keeps running and its SubagentStop still arrives. One that dies
        // fires nothing, like a failed root turn, so the count stays high until
        // the next SessionStart zeroes it. Left alone deliberately: with the
        // increments and decrements atomic, that is the only way the count can
        // drift, it costs one per dead agent, and any guard against it would
        // have to decide that long-running background work has stopped without
        // being told, which is the mistake this count exists to avoid.
        endTurn(running: storedBackgroundTaskCount(addressArgs: address.args), ending: .idle, detail: "")
    case "SubagentStart":
        // Codex CLI only; Claude Code reports the count in Stop/SubagentStop.
        guard isCodex else {
            return nil
        }
        // Store the count but leave the display alone, for the same reason
        // SubagentStop does not re-assert "working": sub-agent events also fire for
        // internal utility agents while the session sits at the prompt, and a turn
        // that really did spawn one already showed "working" at PreToolUse.
        //
        // The increment rides on the one set-status this hook makes, so starting
        // a sub-agent costs a single it2 call and cannot lose a count against a
        // sibling starting at the same moment.
        update.backgroundTasksDelta = 1
    case "SubagentStop":
        // Fires when any subagent finishes, including background agents
        // completing while the main loop sits at the prompt, so it is the
        // only signal that updates the count between turns. The payload
        // still lists the agent that just stopped as "running" (verified on
        // 2.1.201), so exclude it by agent_id. Only re-assert "working"
        // while work remains: SubagentStop also fires for internal utility
        // agents while the session is genuinely idle, and flashing those as
        // "working" would create the inverse of the false-idle bug.
        let payloadCount = backgroundTaskCount(json, excludingID: json["agent_id"] as? String)
        let remaining: Int
        if let payloadCount {
            remaining = payloadCount
            update.backgroundTasks = payloadCount
        } else if isCodex {
            // Decrementing has to happen before the display is decided, because
            // what the display should say depends on how many are left. Doing it
            // as its own call keeps the subtraction atomic; reading the count and
            // writing count-1 back would drop decrements whenever two sub-agents
            // finish together, and a dropped decrement pins the tab at "working"
            // for the rest of the session. The same call brings back the rest of
            // the status, so deciding the display costs no second round trip.
            guard let after = changeBackgroundTaskCount(by: -1, addressArgs: address.args) else {
                // The count is now unknown. Saying done here is the one thing that
                // would be actively wrong, so change nothing.
                return nil
            }
            remaining = after.backgroundTasks
            // The decrement already stored the new count, so nothing else goes
            // to iTerm2 unless the display has to change. That takes an explicit
            // closed turn: a flag iTerm2 has never been told (the hooks were
            // installed mid-session, or the session was resumed) reads as
            // unknown, and calling it closed would report done straight through
            // a running turn. It also takes a display that shows something other
            // than a turn that already ended (done, error, or the idle iTerm2
            // turns those into once the user types): the last one to finish
            // after the parent stopped is what left it at "working", or at
            // "waiting" if it asked permission on the way and was refused, and
            // nothing else will clear it. A utility agent Codex ran at an idle
            // prompt finds the turn's ending already shown, or finds nothing
            // displayed at all, and re-sending done would only replace the root
            // turn's last message with the utility agent's, or bring back a
            // result the user has already seen.
            // It says done whatever ended the parent turn (a failure, or Esc):
            // what finished here is background work whose result the user has
            // not seen yet, which is what done means. Carrying the parent's
            // ending this far would mean keeping it in iTerm2 like the count.
            // What was read is a round trip old by the time done lands, so the
            // write carries it as preconditions rather than trusting it.
            if remaining == 0, after.turnOpen == false, let shown = after.status,
               !["done", "error", "idle"].contains(shown) {
                update.showDone(detail: lastMessage)
                update.onlyWhenFinished = true
            }
        } else {
            return nil  // No field: nothing to learn from this event.
        }
        if remaining > 0 {
            update.showWorking(detail: backgroundDetail(count: remaining))
            if isCodex {
                // A sibling that reached zero in the meantime already wrote done,
                // and this "working" would cover it with nothing left to clear it.
                update.endingIfTasksFinished = (.done, lastMessage)
            } else {
                // This can land mid-turn, and re-asserting the status disowns
                // whatever the turn's last event asked to happen when the turn
                // ends. Without re-arming, an Esc between here and the next tool
                // event would go unnoticed and leave the tab reading "working."
                update.expiresOnProgressEnd = true
            }
        }
        // remaining == 0: last one done. Store the zero but change nothing
        // visible; the main loop wakes to process the results and its own
        // events (PostToolUse/Stop) report from here.
        //
        // Deliberately no expiry here either, and not merely because there is
        // no status to scope: sending one would make this an assertion rather
        // than bookkeeping, and iTerm2 treats a bookkeeping update as the one
        // thing that can release an expiration being held back by outstanding
        // background work. Asserting instead would cancel that expiration and
        // re-arm it for an operation that has already ended, so the tab would
        // sit on a stale status until the next turn.
    case "StopFailure":
        // The turn ended in an API error, but background tasks keep running
        // independently; apply the same gate as Stop so a failed turn does
        // not fake idleness during background work.
        let running: Int
        if let counted = backgroundTaskCount(json) {
            running = counted
            update.backgroundTasks = counted
        } else {
            running = storedBackgroundTaskCount(addressArgs: address.args)
        }
        endTurn(running: running, ending: .error, detail: "")
    case "SessionStart", "SessionEnd":
        update.showIdle(detail: "")  // session boundary, wipe stale detail
        update.backgroundTasks = 0  // and the stored count with it
        if isCodex {
            update.turnOpen = false
        }
    default:
        return nil
    }

    if isCodex {
        // See StatusUpdate.expiresOnProgressEnd: the ring cc-status draws for
        // Codex would trip the expiration itself.
        update.expiresOnProgressEnd = false
    }
    return update
}

/// The turn's final message, condensed for the detail line, or "" when the
/// payload has none: the detail is cleared rather than left stale.
func lastMessageDetail(_ json: [String: Any]) -> String {
    return (json["last_assistant_message"] as? String).map { condense($0) } ?? ""
}
