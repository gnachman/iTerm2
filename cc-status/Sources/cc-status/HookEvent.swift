import Foundation

// Reading the hook event off stdin and deciding what it should change.

// The palette. Each status has one pair of colors wherever it is set.
let workingDot = "#ff9500"
let workingText = "#ff9500"
let waitingDot = "#5f87ff"
let waitingText = "#5f87ff"
let idleDot = "#00d75f"
let idleText = "#888888"

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
    var expiresOnProgressEnd = false
    // nil = don't touch the stored count; non-nil = send --background-tasks.
    // iTerm2 keeps the count in RAM only (never written to disk); it exists
    // so a later idle_prompt, whose payload carries no task info, can read
    // back what the last Stop/SubagentStop knew.
    var backgroundTasks: Int? = nil
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
func statusUpdate(forEvent eventName: String,
                  json: [String: Any],
                  address: Address) -> StatusUpdate? {
    var update = StatusUpdate()

    switch eventName {
    case "UserPromptSubmit", "PreToolUse", "PostToolUse":
        update.status = "working"
        update.dotColor = workingDot
        update.textColor = workingText
        update.detail = ""  // new turn / tool activity, so previous detail is stale
        update.expiresOnProgressEnd = true
    case "PermissionRequest":
        update.status = "waiting"
        update.dotColor = waitingDot
        update.textColor = waitingText
        update.detail = permissionDetail(json)
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
            let running = backgroundTaskCount(json) ?? storedBackgroundTaskCount(addressArgs: address.args)
            if running > 0 {
                update.status = "working"
                update.dotColor = workingDot
                update.textColor = workingText
                update.detail = backgroundDetail(count: running)
            } else {
                update.status = "idle"
                update.dotColor = idleDot
                update.textColor = idleText
                if let message = json["last_assistant_message"] as? String {
                    // Re-assert the last message. Also replaces a stale
                    // "N background tasks running" line from an earlier
                    // Stop, if this payload happens to carry the message.
                    update.detail = condense(message)
                } else {
                    // Clear the detail. An earlier Stop may have set
                    // "N background tasks running" and the tasks have
                    // since finished without another Stop (background
                    // shell commands end silently); leaving that line
                    // next to an idle dot would be false. The cost is
                    // that Stop's last_assistant_message no longer
                    // survives the nudge (2.1.201 idle_prompt payloads
                    // lack the message); truthful-but-empty beats
                    // sticky-but-possibly-false.
                    update.detail = ""
                }
            }
        } else {
            update.status = "waiting"
            update.dotColor = waitingDot
            update.textColor = waitingText
            // Skip detail for permission_prompt (PermissionRequest carries it better).
            // Other subtypes (auth_success, elicitation_dialog, ...) get the message.
            if notificationType != "permission_prompt", let message = json["message"] as? String {
                update.detail = condense(message)
            }
            update.expiresOnProgressEnd = true
        }
    case "Stop":
        // Stop fires whenever the main loop finishes a turn, including while
        // background subagents (Agent tool with run_in_background) and
        // background Bash tasks keep working. In that case the session is not
        // meaningfully idle: a completion watcher that trusts "idle" here
        // fires on every between-subagents lull. background_tasks (Claude
        // Code 2.1.198+; shape verified against 2.1.201) lists the
        // still-running work; stay "working" until a Stop arrives with none.
        // Store the count in iTerm2 only when the payload actually carried
        // the field: on older Claude Code it never exists, and the stored
        // count correctly stays at its initial zero.
        let running: Int
        if let counted = backgroundTaskCount(json) {
            running = counted
            update.backgroundTasks = counted
        } else {
            running = 0
        }
        if running > 0 {
            update.status = "working"
            update.dotColor = workingDot
            update.textColor = workingText
            update.detail = backgroundDetail(count: running)
        } else {
            update.status = "idle"
            update.dotColor = idleDot
            update.textColor = idleText
            if let message = json["last_assistant_message"] as? String {
                update.detail = condense(message)
            } else {
                update.detail = ""
            }
        }
    case "SubagentStop":
        // Fires when any subagent finishes, including background agents
        // completing while the main loop sits at the prompt, so it is the
        // only signal that updates the count between turns. The payload
        // still lists the agent that just stopped as "running" (verified on
        // 2.1.201), so exclude it by agent_id. Only re-assert "working"
        // while work remains: SubagentStop also fires for internal utility
        // agents while the session is genuinely idle, and flashing those as
        // "working" would create the inverse of the false-idle bug.
        guard let remaining = backgroundTaskCount(json, excludingID: json["agent_id"] as? String) else {
            return nil  // No field: nothing to learn from this event.
        }
        update.backgroundTasks = remaining
        if remaining > 0 {
            update.status = "working"
            update.dotColor = workingDot
            update.textColor = workingText
            update.detail = backgroundDetail(count: remaining)
            // This can land mid-turn, and re-asserting the status disowns
            // whatever the turn's last event asked to happen when the turn
            // ends. Without re-arming, an Esc between here and the next tool
            // event would go unnoticed and leave the tab reading "working."
            update.expiresOnProgressEnd = true
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
        if running > 0 {
            update.status = "working"
            update.dotColor = workingDot
            update.textColor = workingText
            update.detail = backgroundDetail(count: running)
        } else {
            update.status = "idle"
            update.dotColor = idleDot
            update.textColor = idleText
            update.detail = ""
        }
    case "SessionStart", "SessionEnd":
        update.status = "idle"
        update.dotColor = idleDot
        update.textColor = idleText
        update.detail = ""  // session boundary, wipe stale detail
        update.backgroundTasks = 0  // and the stored count with it
    default:
        return nil
    }

    return update
}
