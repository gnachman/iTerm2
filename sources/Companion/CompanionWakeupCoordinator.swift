//
//  CompanionWakeupCoordinator.swift
//  iTerm2
//
//  The single, GLOBAL gate for contentless-wakeup pushes (protocol revision >= 2).
//  A wakeup is content-free and level-triggered: it tells the phone's NSE to
//  reconnect and fetch EVERYTHING new across all chats and alerts in one syncSince
//  round trip. So more than one wakeup "in flight" is waste, and a wakeup for
//  content the NSE would NOT render produces the empty "Your agent has an update."
//  placeholder.
//
//  Structure (deliberately stateless about DB content):
//    - "Is there anything to show" is answered on demand by the injected
//      `hasRenderableContent`, which runs the SAME render predicate the syncSince
//      responder uses (Message.isCompanionRenderable) against the current store and
//      the phone's floor. There is no mac-side high-water mirror of the DB tip to
//      drift, so deletes / rewinds / a cleared store need no reconciliation - the
//      next check simply reads the truth.
//    - The only long-lived state is the phone's acked FLOOR (message + alert), which
//      the phone itself reports via syncSince (authoritative), plus rate-limit state.
//
//  A wakeup is sent when there is renderable content above the phone's floor AND the
//  rate-limit interval allows. Everything worth notifying - replies, alerts, and
//  .classic permission / session-pick prompts - is renderable content (the prompts
//  render from their request text), so there is ONE outstanding condition and no
//  special nudge path. The interval is a hard invariant: the first wakeup fires
//  immediately (leading edge), later ones coalesce into a single trailing wakeup at
//  interval's end. There is NO "fetched since last push" override (it defeated the
//  interval, since the NSE fetches within ~1s of every push).
//
//  Deliberately I/O-free and unit-testable: the clock, the interval, the renderable
//  check, the send, and the timer are all injected. Legacy per-chat pushes (revision
//  1) do NOT route through here.
//
//  Logs (RLog) carry the full decision - renderable, floors, action, reason - so a
//  field log explains every push without a DB query. Never message content.
//

import Foundation

@MainActor
final class CompanionWakeupCoordinator {
    /// What prompted a decision, for logging only.
    private enum Trigger: CustomStringConvertible {
        case content(String)
        case fetch
        case deferred
        var description: String {
            switch self {
            case .content(let chatID): return "content(chat \(chatID))"
            case .fetch: return "nseFetch"
            case .deferred: return "deferredRetry"
            }
        }
    }

    private let interval: () -> TimeInterval
    private let clock: () -> Date
    /// "Would the next syncSince return anything the NSE renders, above these
    /// floors?" - the responder's own predicate, evaluated fresh each time.
    private let hasRenderableContent: (_ messageFloor: Int64, _ alertFloor: Int64) -> Bool
    private let send: () -> Void
    private let scheduleAfter: (TimeInterval, @escaping () -> Void) -> Void

    // The phone's last-acked floors (from syncSince). Phone-authoritative; advance
    // only when the phone fetches, so they never drift with DB mutations.
    private var phoneMessageFloor: Int64 = 0
    private var phoneAlertFloor: Int64 = 0
    private var lastPushAt: Date?
    // Monotonic generation stamps the armed deferred re-check; any change (a send,
    // a new arming, or an explicit cancel) invalidates a still-pending closure so
    // at most one re-check is ever live.
    private var deferredGeneration = 0

    init(interval: @escaping () -> TimeInterval,
         clock: @escaping () -> Date = { Date() },
         hasRenderableContent: @escaping (Int64, Int64) -> Bool,
         send: @escaping () -> Void,
         scheduleAfter: @escaping (TimeInterval, @escaping () -> Void) -> Void) {
        self.interval = interval
        self.clock = clock
        self.hasRenderableContent = hasRenderableContent
        self.send = send
        self.scheduleAfter = scheduleAfter
    }

    // MARK: Inputs

    /// A renderable agent reply (or alert) may now exist. Re-runs the decision, which
    /// pushes only if the responder would actually show something above the floor.
    func noteContentActivity(chatID: String) {
        evaluate(.content(chatID))
    }

    /// The NSE performed a syncSince fetch, acking everything up through these floors.
    /// `messageReset`/`alertReset` are the responder's rewind signal (the store was
    /// lost/recreated and the seq space restarted low). Updates the phone's floors and
    /// re-checks for content above them.
    func noteNSEFetch(messageFloor: Int64,
                      alertFloor: Int64,
                      messageReset: Bool = false,
                      alertReset: Bool = false) {
        // On a reset ASSIGN the floor (which may LOWER it) so post-rewind low-seq
        // content lands above it again and can fire; otherwise ADVANCE via max, which
        // guards against a lower, out-of-order syncSince response dropping the floor.
        phoneMessageFloor = messageReset ? messageFloor : max(phoneMessageFloor, messageFloor)
        phoneAlertFloor = alertReset ? alertFloor : max(phoneAlertFloor, alertFloor)
        evaluate(.fetch)
    }

    // MARK: Decision

    private func evaluate(_ trigger: Trigger) {
        guard hasRenderableContent(phoneMessageFloor, phoneAlertFloor) else {
            cancelDeferred()
            RLog("CompanionWakeupCoordinator: \(trigger) -> no push (nothing renderable above floor msg=\(phoneMessageFloor)/alert=\(phoneAlertFloor))")
            return
        }
        let now = clock()
        // Read the interval ONCE so the elapsed check and the deferred delay agree.
        let intervalValue = interval()
        // Clamp elapsed-since-push to >= 0: the injected clock is wall-clock while the
        // deferred timer runs on the monotonic dispatch clock, so a backward clock
        // step must not strand the wakeup (remaining = interval - negative).
        let sincePush = lastPushAt.map { max(now.timeIntervalSince($0), 0) }
        let intervalElapsed = sincePush.map { $0 >= intervalValue } ?? true
        if intervalElapsed {
            cancelDeferred()
            lastPushAt = now
            RLog("CompanionWakeupCoordinator: \(trigger) -> SEND wakeup (floor msg=\(phoneMessageFloor)/alert=\(phoneAlertFloor), sinceLastPush=\(sincePush.map { String(format: "%.1fs", $0) } ?? "never"))")
            send()
        } else {
            let remaining = max(intervalValue - (sincePush ?? intervalValue), 0)
            RLog("CompanionWakeupCoordinator: \(trigger) -> defer wakeup for \(String(format: "%.1fs", remaining)) (too soon since last push)")
            armDeferred(after: remaining)
        }
    }

    /// Arm a single re-check `after` seconds out. A generation stamp means a later
    /// send / cancel / re-arm makes this pending fire a harmless no-op.
    private func armDeferred(after: TimeInterval) {
        deferredGeneration += 1
        let generation = deferredGeneration
        scheduleAfter(after) { [weak self] in
            guard let self, generation == self.deferredGeneration else { return }
            self.evaluate(.deferred)
        }
    }

    private func cancelDeferred() {
        deferredGeneration += 1
    }
}

extension CompanionWakeupCoordinator {
    private static var _shared: CompanionWakeupCoordinator?

    /// The process-wide wakeup gate, wired to production dependencies: the coalesce
    /// interval from advanced settings, the render check from the chat DB (reusing the
    /// responder's predicate + the current muted-chat set), the wakeup send via
    /// CompanionPushSender, and a main-queue timer. Main-actor; every call site (the
    /// agent-activity notifier, the alert bridge, the host bridge's syncSince
    /// responder) already runs there.
    static var shared: CompanionWakeupCoordinator {
        if let existing = _shared {
            return existing
        }
        let instance = CompanionWakeupCoordinator(
            interval: { TimeInterval(iTermAdvancedSettingsModel.companionWakeupCoalesceInterval()) },
            hasRenderableContent: { messageFloor, alertFloor in
                ChatDatabase.instance?.hasRenderableContentSince(
                    messageSeq: messageFloor,
                    alertSeq: alertFloor,
                    mutedChatIDs: CompanionChatMuteRegistry.mutedChatIDs) ?? false
            },
            send: { CompanionPushSender.dispatchPush(chatID: nil) },
            scheduleAfter: { delay, closure in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay,
                                              execute: DispatchWorkItem(block: closure))
            })
        _shared = instance
        return instance
    }
}
