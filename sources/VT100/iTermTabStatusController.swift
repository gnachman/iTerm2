//
//  iTermTabStatusController.swift
//  iTerm2SharedARC
//

import Foundation

/// A session's tab status and everything that governs it: the status object
/// itself, the updates applied to it, and when a status that was scoped to an
/// operation stops being true.
///
/// A program that reports its status out of band cannot announce every way its
/// work can end, so it may instead say up front what should happen when the
/// terminal sees the operation finish (see VT100TabStatusExpirationReason).
/// Deciding that means knowing which operation an armed expiration belongs to,
/// whether that operation has ended, and how long to wait before acting on the
/// end. Keeping the status here too means there is one object to consult, and
/// no way to hold a status whose governing state lives somewhere else.
///
/// Main thread only.
@objc(iTermTabStatusController)
class TabStatusController: NSObject {
    /// How long to wait, after the progress protocol reports that an operation
    /// ended, before expiring a status that was scoped to it. A program that
    /// announces the end of its work usually updates its status at the same
    /// moment over a much slower path, and its own word should win; this is
    /// the head start that gives it.
    ///
    /// The path to beat, measured for Claude Code, is a hook process that
    /// spawns it2, which connects to the API and waits for a reply: 0.14 to
    /// 0.34 seconds warm, and 1.66 seconds on a cold start, which is the
    /// likely state after a long turn on a machine loaded by that turn's own
    /// subagents. Three seconds leaves real margin over the worst measured
    /// case. Being late costs only a few seconds of stale status, and any
    /// update that lands meanwhile corrects it immediately; being early
    /// publishes a state the program never reported, which anything watching
    /// for a transition will act on.
    private static let defaultProgressEndDelay: TimeInterval = 3.0

    private let progressEndDelay: TimeInterval

    private let sessionID: () -> String
    private let didChange: (String?) -> Void

    /// The session's tab status, created on demand. A session that never has
    /// one costs nothing: see `statusIfPresent` for the readers that must not
    /// bring one into being.
    @objc var status: iTermSessionTabStatus {
        if let existing = _status {
            return existing
        }
        let created = iTermSessionTabStatus(sessionID: sessionID())
        _status = created
        return created
    }

    /// The status if the session has one, without creating it. For readers
    /// that are asking whether there is anything to show or save.
    @objc private(set) var statusIfPresent: iTermSessionTabStatus?

    private var _status: iTermSessionTabStatus? {
        get { statusIfPresent }
        set { statusIfPresent = newValue }
    }

    /// What the current status asked to happen when it stops being true, if
    /// anything. This lives here rather than on the status because it is not
    /// part of what the session is showing: a status can be copied for the tab
    /// aggregate or written to an arrangement, and neither copy should be able
    /// to expire.
    private var armedExpiration: (reason: VT100TabStatusExpirationReason,
                                  fallback: VT100TabStatusUpdate)?
    /// Bumped whenever a scheduled expiration stops being valid, so a block
    /// that was already dispatched can tell it has been superseded, and so a
    /// later look can tell whether anything has been asserted since.
    private var generation = 0
    /// Whether the last thing the progress protocol said was that something
    /// was running. A stop only ends an operation if one had started.
    private var progressWasRunning = false
    /// Whether the head start for the operation that just ended has elapsed
    /// without anything superseding it, and the generation as of that
    /// operation's end. Set when the timer fires, not when the operation ends:
    /// until then the pending timer is the thing that will decide, and letting
    /// an update short-circuit it would hand back the head start it exists to
    /// provide.
    private var headStartElapsed = false
    private var operationEndGeneration = 0

    /// - Parameters:
    ///   - sessionID: The owning session's identity, read when a status is
    ///     first needed rather than captured, since a session that restarts
    ///     gets a new one.
    ///   - didChange: Called with the previous status text whenever the status
    ///     visibly changed, so the session can publish it.
    @objc
    convenience init(sessionID: @escaping () -> String,
                     didChange: @escaping (String?) -> Void) {
        self.init(sessionID: sessionID,
                  didChange: didChange,
                  progressEndDelay: Self.defaultProgressEndDelay)
    }

    /// The delay is a parameter so tests can drive the timer without waiting
    /// on the real head start.
    @objc
    init(sessionID: @escaping () -> String,
         didChange: @escaping (String?) -> Void,
         progressEndDelay: TimeInterval) {
        self.sessionID = sessionID
        self.didChange = didChange
        self.progressEndDelay = progressEndDelay
        super.init()
    }

    /// Takes over a status rebuilt from a saved arrangement.
    @objc
    func adoptRestoredStatus(_ restored: iTermSessionTabStatus) {
        _status = restored
    }

    /// Clears the status, if there is one to clear. Returns whether anything
    /// was showing, since the caller has its own work to do in that case.
    @objc
    func clearStatus() -> Bool {
        // An expiration can be armed by a status that set no visible field, so
        // hasActiveStatus alone would let one outlive the clear and resurrect
        // a status on a session that was explicitly cleared.
        guard let status = statusIfPresent,
              status.hasActiveStatus || hasArmedExpiration else {
            return false
        }
        armedExpiration = nil
        generation += 1
        status.clear()
        return true
    }

    @objc var hasArmedExpiration: Bool {
        return armedExpiration != nil
    }

    /// Applies one update, and with it any change to what should happen when
    /// the current operation ends.
    @objc
    func apply(_ update: VT100TabStatusUpdate) {
        let status = self.status
        let assertsStatus = update.assertsStatus
        if assertsStatus {
            // Whether the expiration being replaced had already been released
            // by the timer and was only being held back by outstanding
            // background work. Read before the update lands, since the update
            // may carry a new count.
            let previousWasHeld = armedExpiration != nil &&
                                  headStartElapsed &&
                                  generation == operationEndGeneration &&
                                  status.backgroundTasks > 0
            // A new assertion supersedes whatever the last one asked to happen
            // when it went stale, whether or not it changes anything visible.
            // By the time the terminal notices the operation ended, the program
            // may already have said something newer, and its word wins. Bumping
            // the generation drops the timer that would have fired the old one.
            // An update that only parks bookkeeping is not such an assertion:
            // a program updating its task count mid-operation has not changed
            // its mind about what happens when the operation ends.
            armedExpiration = nil
            if update.expiresOn != .never, let fallback = update.expirationFallback {
                armedExpiration = (update.expiresOn, fallback)
            }
            generation += 1
            if previousWasHeld && armedExpiration != nil {
                // The program re-armed while its last expiration was held: it
                // reported that some of the background work finished and
                // restated its status, with the same request for when the
                // operation ends. No operation has started since the one that
                // ended, so the new expiration belongs to that same ended
                // operation. Carrying the end forward keeps the count able to
                // release it; otherwise nothing would, since no stop is coming
                // for an operation that already stopped, and the tab would sit
                // on the stale status until the next turn.
                operationEndGeneration = generation
            }
        }
        let previousStatusText = status.statusText
        if status.apply(update) {
            didChange(previousStatusText)
        } else {
            DLog("No change from \(update)")
        }

        guard !assertsStatus,
              update.backgroundTasksPresence != .notSet,
              headStartElapsed,
              generation == operationEndGeneration else {
            return
        }
        // The head start has already elapsed and left an expiration held back
        // by outstanding background work. This update carries a new count, so
        // it may be the program reporting that the last of it finished, which
        // is the one thing that can change that answer. Releasing a hold is
        // not the same as skipping the wait, so there is nothing to wait for
        // here: the program has just spoken.
        //
        // Each test earns its place. A bookkeeping update cannot have armed
        // anything itself. The count is the only input to the decision that an
        // update can change. The head start having elapsed means the timer has
        // already had its say, so an update arriving inside the window cannot
        // cut it short. And the generation still matching the one current when
        // the operation ended means nothing has been asserted since: an
        // assertion in between may have armed an expiration for an operation
        // that has not started yet, and that one must wait for its own end.
        expireNow()
    }

    /// The program reported a progress state. Only what the program itself
    /// said belongs here: the screen's progress also changes on reset, which
    /// says nothing about whether the program's work is still running.
    @objc
    func progressProtocolDidReport(_ progress: VT100ScreenProgress) {
        guard Self.endsOperation(progress) else {
            progressWasRunning = true
            headStartElapsed = false
            // Whatever ended a moment ago evidently did not stay ended.
            generation += 1
            return
        }
        guard progressWasRunning else {
            return
        }
        progressWasRunning = false
        generation += 1
        operationEndGeneration = generation
        guard armedExpiration != nil else {
            // Nothing is waiting on this operation, and nothing can start:
            // anything armed from here on comes from an assertion, which moves
            // the generation on and so invalidates a timer scheduled now. A
            // session whose program reports progress but never sets a status
            // therefore schedules nothing at all.
            DLog("Progress protocol reported the operation ended with nothing armed")
            return
        }
        let scheduled = generation
        DLog("Progress protocol reported the operation ended; expiration \(scheduled) armed for \(progressEndDelay)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + progressEndDelay) { [weak self] in
            self?.expire(ifGenerationIs: scheduled)
        }
    }

    /// The program died. A restarted one starts from having reported nothing,
    /// so its first stop cannot end an operation that was never seen to start.
    @objc
    func programDidExit() {
        // Drop the status along with everything the dead program said about
        // it: a restarted session gets a new identity, and a stale instance
        // keyed by the old one would outlive the program that set it.
        _status = nil
        armedExpiration = nil
        generation += 1
        progressWasRunning = false
        headStartElapsed = false
        operationEndGeneration = 0
    }

    // MARK: - Private

    /// Which reported states mean the operation is over. Stopped is the
    /// explicit end. An error state counts too: a program that reports a
    /// failure has finished narrating that operation, and one that exits on
    /// the error may never send a stopped at all, which would pin a status
    /// scoped to it forever. A paused state, and a plain percentage, are not
    /// an end: the operation is still running.
    private static func endsOperation(_ progress: VT100ScreenProgress) -> Bool {
        switch progress {
        case .stopped, .error:
            return true
        default:
            return progress.rawValue >= VT100ScreenProgress.errorBase.rawValue &&
                   progress.rawValue <= VT100ScreenProgress.errorBase.rawValue + 100
        }
    }

    private func expire(ifGenerationIs scheduled: Int) {
        guard scheduled == generation else {
            DLog("Expiration \(scheduled) superseded")
            return
        }
        // From here a held expiration can be released the moment the count
        // that is holding it changes, without waiting all over again.
        headStartElapsed = true
        expireNow()
    }

    /// Expires if an expiration is armed and nothing is holding it back. Safe
    /// to call whenever the inputs to that decision change: it does nothing
    /// unless the status is still waiting for the operation that just ended.
    private func expireNow() {
        guard let armed = armedExpiration, armed.reason == .progressEnd else {
            return
        }
        guard let status = statusIfPresent else {
            return
        }
        // The background-task gate is what keeps an expiration from
        // contradicting the program it serves. A program that reports work it
        // started but is no longer waiting on has not finished; whether its
        // foreground operation ended normally or was interrupted, the truthful
        // status is still the one it last asserted. So this stays armed until
        // the count reaches zero, which is the moment the session really is
        // idle. Expiring anyway would put a transient wrong state on the tab,
        // and anything watching for a state transition would see it.
        guard status.backgroundTasks == 0 else {
            return
        }
        armedExpiration = nil
        let previousStatusText = status.statusText
        guard status.apply(armed.fallback) else {
            return
        }
        RLog("Tab status expired at progress end: \(previousStatusText ?? "none") -> \(status.statusText ?? "none")")
        didChange(previousStatusText)
    }
}
