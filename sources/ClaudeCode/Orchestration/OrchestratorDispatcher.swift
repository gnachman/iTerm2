//
//  OrchestratorDispatcher.swift
//  iTerm2SharedARC
//

import Foundation

// Bridges the LLM tool-use loop to the orchestrator's actual
// behavior. One instance per chat; owned by OrchestratorClient and
// torn down when the chat closes.
//
// Holds two pieces of state, both persisted on the chat record so
// they survive iTerm2 restart:
//   - claimedScopes: write targets the user has approved this chat
//     to act on. Each entry is either a real workgroup instance ID
//     OR a synthetic single-session scope ("session:<sessionGuid>",
//     see WorkgroupIntrospection.syntheticWorkgroupIDPrefix). A
//     write call against an unclaimed scope prompts the user inline.
//   - watchers: registered async state watchers. Non-blocking by
//     design — register_watch returns immediately and the
//     tab-status subscription delivers a status_update message to
//     the chat when a watcher's condition fires.
//
// Public entrypoint is handleToolCall(name:jsonArgs:llmMessage:) which
// OrchestratorClient (the app-side broker subscriber that owns this
// dispatcher) calls for each .remoteCommandRequest(.external(...))
// the agent publishes. Returns the JSON the client ships back as the
// tool_result body of the corresponding .remoteCommandResponse.
// @MainActor: OrchestratorDispatcher's init subscribes to the broker
// and registers notification observers, several methods mutate
// claimedScopes / watchers, and per-tool dispatchers call into
// MainActor-bound infrastructure (broker, listModel, PTYSession). The
// class-level annotation pins all of that on main instead of relying
// on per-method @MainActor sprinkles.
@MainActor
final class OrchestratorDispatcher {

    private let chatID: String
    private weak var broker: ChatBroker?

    // Set by tearDown() to short-circuit any handler that's already
    // mid-await when the chat exits orchestration mode (or the chat is
    // deleted). After tearDown the dispatcher's subscription and
    // observers are gone, but in-flight Tasks may still hold strong
    // refs and resume into this object. Each public-ish entrypoint
    // checks this flag so a posthumous handleToolCall doesn't publish
    // a tool_result back into a chat that's no longer listening, and
    // a posthumous broker update doesn't try to resume a continuation
    // that's already been resolved with `false`.
    private var tornDown = false

    // Persisted claim set, cached in memory. The listModel is the
    // source of truth on disk; we write through on every mutation
    // and read once at init.
    private var claimedScopes: Set<String>

    // Persisted watcher list, cached in memory. Mutated by
    // register_watch / unregister_watch and by the tab-status
    // handler when a watcher fires (firing is a one-shot — the
    // watcher is removed after delivering its status_update).
    // Mirrored to the chat record on every change.
    private var watchers: [WorkgroupWatcher]

    // Last SessionState we observed for each watched session GUID.
    // Watchers fire only on a transition to their target state, never on
    // a same-state notification. Without this, transient tabStatus clears
    // (PTYSession.screenPromptDidStartAtLine calls clearTabStatus when a
    // shell prompt starts up; the login-shell that wraps Code Review's
    // claude -p launch fires this on startup) make state(forTabStatus:)
    // fall back to .idle from the empty tabStatus, which would match an
    // idle-targeted watcher and trigger immediately - producing a
    // "review completed" status_update before Claude Code has even
    // printed its first byte. Tracked per session, not per watcher,
    // because every watcher on a given session cares about the same
    // transition history.
    private var sessionStateHistory: [String: SessionState] = [:]

    // Continuations parked by promptForClaim / promptForSpawn,
    // keyed by request UUID. The broker subscription resumes them
    // when a matching .workgroupPermissionResponse arrives. Resumed
    // with `false` from deinit so a chat torn down mid-prompt
    // doesn't leak a task.
    private var pendingPermissionPrompts: [String: CheckedContinuation<Bool, Never>] = [:]
    private var brokerSubscription: ChatBroker.Subscription?

    // De-dup table for in-flight ensureClaim calls. Two concurrent
    // write tool calls against the same unclaimed workgroup would
    // otherwise both pass the claimedScopes.contains check (the
    // membership read is synchronous but the prompt is async), both
    // call promptForClaim, and surface two stacked permission bubbles
    // for the same target. The @MainActor isolation serializes
    // synchronous code but doesn't bridge across the `await` that
    // promptForClaim hangs on, so we need a per-workgroup in-flight
    // map: if a claim is being negotiated, later callers await the
    // same task instead of spawning a new prompt.
    private var pendingClaimTasks: [String: Task<Bool, Never>] = [:]

    // Observer on iTermSessionTabStatusDidChange — the source of
    // truth for "a session's state changed". When a notification
    // fires we walk watchers, fire any matches, and remove them
    // from the list.
    private var tabStatusObserver: NSObjectProtocol?
    private var sessionWillTerminateObserver: NSObjectProtocol?

    // Live screen-observation pollers, keyed by watcherID. Created for
    // watchers whose session reports no machine-readable status (see
    // WorkgroupIntrospection.reportsSessionStatus) and for plain-English
    // condition watchers (always screen-judged); each drives a headless
    // AIConversation that reads the screen and fires the same status_update
    // a tab-status watcher would. Not persisted — a running loop can't be
    // serialized; reconcilePersistedWatchers restarts one for each
    // surviving .screenPoll watcher after a relaunch.
    private var screenPollers: [String: ScreenWatchPoller] = [:]

    // Screen-observation backstop timers for tab-status watchers, keyed by
    // watcherID. A tab-status watcher waits indefinitely on a status
    // transition; if the cc-status hook drops the event that would report
    // the target state, that transition never arrives and the watch hangs
    // (a session reported "working" that has actually gone idle). After
    // tabStatusEscalationDelay without firing, the timer escalates the
    // watcher to screen observation — a poller reads the rendered screen and
    // fires the watch when it can positively confirm the target, while the
    // tab-status subscription stays armed in case the hook recovers. Not
    // persisted; reconcilePersistedWatchers re-arms one per surviving
    // tab-status watcher after a relaunch.
    private var escalationTimers: [String: Task<Void, Never>] = [:]

    // How long a tab-status watcher waits for its status transition before
    // escalating to the screen-observation backstop.
    private static let tabStatusEscalationDelay: TimeInterval = 300  // 5 minutes

    init(chatID: String, broker: ChatBroker) {
        self.chatID = chatID
        self.broker = broker
        let listModel = broker.listModel
        self.claimedScopes = listModel.claimedScopes(forChatID: chatID)
        self.watchers = listModel.watchers(forChatID: chatID)
        // Broker callbacks can fire on whatever thread publish() runs
        // on. Permission-prompt state lives on the main actor; hop
        // there before touching it so we don't race with awaitPermission.
        self.brokerSubscription = broker.subscribe(
            chatID: chatID,
            registrationProvider: nil
        ) { [weak self] update in
            Task { @MainActor in
                self?.handle(brokerUpdate: update)
            }
        }

        // Tab-status is the primary watcher trigger. queue: .main
        // routes the callback through the main runloop so watchers
        // (and the chat broker publish that follows when one fires)
        // are touched only from main — same isolation everything
        // else in the dispatcher relies on.
        self.tabStatusObserver = NotificationCenter.default.addObserver(
            forName: iTermSessionTabStatus.didChangeNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handle(tabStatusNotification: notification)
            }
        }

        // Session-terminating: any watchers on that session are
        // dropped with a watcherDropped status_update so the agent
        // learns the watch ended without firing.
        self.sessionWillTerminateObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.iTermSessionWillTerminate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleSessionWillTerminate(notification)
            }
        }

        // Restart reconciliation: if any persisted watchers target
        // a session GUID that no longer exists (restoration off,
        // partial restore, etc.), surface that to the agent and
        // drop the watcher.
        MainActor.assumeIsolated {
            self.reconcilePersistedWatchers()
        }
    }

    // Synchronously detach from the broker, notification center, and
    // any parked permission prompts. Called from
    // OrchestratorClient.dropDispatcher when the chat exits
    // orchestration mode or is deleted, before the dispatcher is
    // removed from the dict. The dict drop alone wouldn't be enough:
    // an in-flight handleToolCall Task still has a strong ref to this
    // dispatcher, and without explicit detach it would keep delivering
    // status updates (tab-status observer), keep publishing tool
    // responses into a chat that's no longer in orchestration mode,
    // and leave any user permission bubble parked on a continuation
    // that's never going to resume.
    @MainActor
    func tearDown() {
        if tornDown { return }
        tornDown = true
        brokerSubscription?.unsubscribe()
        brokerSubscription = nil
        if let tabObs = tabStatusObserver {
            NotificationCenter.default.removeObserver(tabObs)
            tabStatusObserver = nil
        }
        if let termObs = sessionWillTerminateObserver {
            NotificationCenter.default.removeObserver(termObs)
            sessionWillTerminateObserver = nil
        }
        for (_, task) in pendingClaimTasks {
            task.cancel()
        }
        pendingClaimTasks.removeAll()
        for (_, cont) in pendingPermissionPrompts {
            cont.resume(returning: false)
        }
        pendingPermissionPrompts.removeAll()
        for (_, poller) in screenPollers {
            poller.cancel()
        }
        screenPollers.removeAll()
        for (_, timer) in escalationTimers {
            timer.cancel()
        }
        escalationTimers.removeAll()
    }

    deinit {
        // Beta/Nightly tripwire: deinit on a @MainActor class is not
        // itself main-actor-isolated. If a future code path captures
        // the dispatcher in a non-main Task and that Task holds the
        // last strong ref, this body runs off-main; the cleanup hops
        // back to main on its own, but anything that reads dispatcher
        // state directly here would race.
        let isBetaChannel = Bundle.it_isEarlyAdopter() || Bundle.it_isNightlyBuild()
        if isBetaChannel {
            it_assert(Thread.isMainThread,
                      "OrchestratorDispatcher.deinit: ran off the main thread")
        }
        // Do the actual cleanup on main, even if we're already there.
        // The mutations touch @MainActor state (ChatBroker.subs via
        // Subscription.unsubscribe) and resuming continuations is
        // thread-safe on its own but downstream awaiters expect to wake
        // on main. Capture all references explicitly into the dispatch
        // closure so they outlive self and run safely after the deinit
        // returns. If the work turns out to be no-op by the time it
        // runs (observers already gone, broker already cleaned up its
        // subs), the cost is one runloop hop.
        // These are only touched on main; hand them across the @Sendable
        // boundary explicitly since their types aren't Sendable.
        nonisolated(unsafe) let sub = brokerSubscription
        nonisolated(unsafe) let tabObs = tabStatusObserver
        nonisolated(unsafe) let termObs = sessionWillTerminateObserver
        let prompts = pendingPermissionPrompts
        DispatchQueue.main.async {
            sub?.unsubscribe()
            if let tabObs {
                NotificationCenter.default.removeObserver(tabObs)
            }
            if let termObs {
                NotificationCenter.default.removeObserver(termObs)
            }
            for (_, cont) in prompts {
                cont.resume(returning: false)
            }
        }
    }

    // MARK: - Broker handler

    // Listens for user-side .workgroupPermissionResponse messages and
    // resumes the parked continuation. Anything else flows through
    // untouched — the dispatcher doesn't care about typing status or
    // agent-author messages here. @MainActor-isolated so the parking
    // and resuming sides both run on main, no locks needed.
    @MainActor
    private func handle(brokerUpdate update: ChatBroker.Update) {
        if tornDown { return }
        guard case let .delivery(message, _, _) = update,
              message.author == .user,
              case let .userCommand(command) = message.content,
              case let .workgroupPermissionResponse(requestID, approved) = command else {
            return
        }
        // Normalize case at the lookup boundary. UUID().uuidString returns
        // uppercase, and pendingPermissionPrompts is keyed by that exact
        // string. If anything in the message round-trip ever lower-cases
        // the requestID (e.g. a future JSON round-trip, a UI bridge that
        // canonicalizes IDs), the lookup would miss and the continuation
        // would park forever with no diagnostic.
        let key = requestID.uppercased()
        if let continuation = pendingPermissionPrompts.removeValue(forKey: key) {
            continuation.resume(returning: approved)
        }
    }

    // MARK: - Tab status / watcher firing

    // When a session's tab status changes (the cc-status hook or any
    // trigger-driven status update), walk the watcher list and fire
    // any matches. A firing watcher is removed from the list and
    // published as a Message.Content.watcherEvent so the chat
    // service kicks off an agent turn.
    // Match watchers directly off the notification's tabStatus. Earlier
    // revisions of this handler routed status.sessionID through
    // iTermController.sharedInstance().allSessions() to recover a PTYSession,
    // but workgroup peer-port sessions (Code Review, Diff, any side-pane
    // peer) aren't enumerated through that path — the controller only knows
    // about top-level windowed sessions — so the lookup returned nil for the
    // very roles the orchestrator cares about and every watcher fire was
    // silently dropped. status.sessionID is itself the session's GUID
    // (PTYSession.tabStatus is created with sessionID: self.guid), so we
    // can match watchers directly and read the new state from the tabStatus
    // we already have without ever touching a PTYSession reference.
    //
    // Fire only on TRANSITIONS to target. Empty/cleared tabStatus computes
    // to .idle by fallback in state(forTabStatus:), so a clearTabStatus
    // call mid-program-launch would otherwise match a target=idle watcher
    // and fire spuriously. sessionStateHistory captures the last
    // SessionState we computed for each session; if the new state equals
    // the previous one (notification fired because some other tabStatus
    // field like detailText changed, but our SessionState didn't), we
    // skip. Always update history regardless of whether anything fired.
    @MainActor
    private func handle(tabStatusNotification notification: Notification) {
        if tornDown { return }
        guard let status = notification.object as? iTermSessionTabStatus else {
            return
        }
        let guid = status.sessionID
        // The notification fires for every session in the app (object: nil),
        // not just sessions we have watchers on. Without this gate,
        // sessionStateHistory would grow once per (chat, every session ever
        // observed) and stay there until the session terminated. Only sessions
        // we have a watcher for need their history tracked. doRegisterWatch
        // and doStartCodeReview seed history themselves before appending a
        // watcher, so a watcher's first matching notification always finds a
        // non-nil previousState.
        guard watchers.contains(where: { $0.sessionGUID == guid }) else {
            return
        }
        let newState = WorkgroupIntrospection.state(forTabStatus: status)
        let previousState = sessionStateHistory[guid]
        sessionStateHistory[guid] = newState
        guard previousState != newState else { return }
        let matches = watchers.filter {
            $0.sessionGUID == guid && $0.targetState == newState
                && $0.effectiveMode == .tabStatus
        }
        guard !matches.isEmpty else { return }
        let matchedIDs = Set(matches.map { $0.watcherID })
        watchers.removeAll { matchedIDs.contains($0.watcherID) }
        persistWatchers()
        // The status transition arrived (the hook is healthy): tear down any
        // screen-observation backstop that escalation may have started, and
        // the pending escalation timer, so neither fires after the watch is
        // already resolved.
        for id in matchedIDs {
            removeWatcherAuxiliaries(watcherID: id)
        }
        for fired in matches {
            publishStatusUpdate(
                watcher: fired,
                reason: .stateReached,
                stateReached: newState.rawValue,
                detail: "\(fired.roleName) in \(fired.workgroupName) reached state '\(newState.rawValue)'.")
        }
    }

    // Drop any watchers targeting a session that just exited. The
    // agent gets a watcherDropped status_update so it knows the
    // watch ended without firing — better than silently leaking.
    @MainActor
    private func handleSessionWillTerminate(_ notification: Notification) {
        if tornDown { return }
        guard let session = notification.object as? PTYSession else { return }
        let guid = session.guid
        // Drop the per-session history entry alongside the watchers.
        // Without this, history grows unbounded over the app's lifetime
        // and a future session that happens to reuse this GUID would
        // see a stale "previous state" from the prior session's last
        // tabStatus event.
        sessionStateHistory.removeValue(forKey: guid)
        let dropped = watchers.filter { $0.sessionGUID == guid }
        guard !dropped.isEmpty else { return }
        let droppedIDs = Set(dropped.map { $0.watcherID })
        watchers.removeAll { droppedIDs.contains($0.watcherID) }
        persistWatchers()
        for watcher in dropped {
            removeWatcherAuxiliaries(watcherID: watcher.watcherID)
            publishStatusUpdate(
                watcher: watcher,
                reason: .watcherDropped,
                stateReached: "",
                detail: "Watch dropped: the session for \(watcher.roleName) in \(watcher.workgroupName) terminated before \(watcher.goalDescription) was reached.")
        }
    }

    // Re-check every persisted watcher at init: if the session GUID
    // still resolves, leave it in place (the live tab-status
    // subscription will fire it normally). If not, the session is
    // gone (restoration off, partial restore, terminated mid-quit)
    // — surface that to the agent and remove the watcher.
    //
    // Surviving watchers also need their sessionStateHistory entry
    // seeded here: persistence covers only the watcher list itself,
    // not the in-memory "last observed state" map, so after a restart
    // history[guid] is nil. The notification handler reads previous
    // state from history and fires when previous != new — a nil
    // previous always counts as a transition, which would fire every
    // surviving watcher on the first tabStatus event after launch.
    @MainActor
    private func reconcilePersistedWatchers() {
        let dropped = watchers.filter { sessionByGUID($0.sessionGUID) == nil }
        let droppedIDs = Set(dropped.map { $0.watcherID })
        if !droppedIDs.isEmpty {
            watchers.removeAll { droppedIDs.contains($0.watcherID) }
            persistWatchers()
            for watcher in dropped {
                publishStatusUpdate(
                    watcher: watcher,
                    reason: .watcherDropped,
                    stateReached: "",
                    detail: "Watch dropped after iTerm2 restart: the session for \(watcher.roleName) in \(watcher.workgroupName) could not be restored.")
            }
        }
        // Seed history for every surviving watcher's session. Use the
        // same normalization the notification handler uses (nil tabStatus
        // would compute .unknown, but the handler's fallback is .idle —
        // matching that prevents a spurious .unknown → .idle transition).
        let survivingGUIDs = Set(watchers.map { $0.sessionGUID })
        for guid in survivingGUIDs where sessionStateHistory[guid] == nil {
            guard let session = sessionByGUID(guid) else { continue }
            sessionStateHistory[guid] = Self.seedState(for: session)
        }
        // Screen-poll watchers have no persisted running loop; restart one
        // per surviving watcher. Its 5-minute cap restarts from now, which
        // is the intended behavior after a relaunch.
        for watcher in watchers where watcher.effectiveMode == .screenPoll {
            startScreenPoll(for: watcher)
        }
        // Tab-status watchers get a fresh escalation timer, also counted
        // from now (the running timer can't be serialized any more than the
        // poll loop can). A watcher that already escalated to a live poller
        // before the relaunch starts over: the timer re-arms, and if the
        // status transition still hasn't come 5 minutes later it escalates
        // again.
        for watcher in watchers where watcher.effectiveMode == .tabStatus {
            armScreenEscalation(for: watcher)
        }
    }

    // Compute the seed value for sessionStateHistory. state(for:) returns
    // .unknown when session.tabStatus is nil; the notification handler
    // always computes via state(forTabStatus:), which falls back to .idle
    // when statusText is empty. Without this normalization, seeding
    // .unknown and then receiving the first tabStatus event (computed as
    // .idle by the handler) would register as a real transition and fire
    // every idle-targeted watcher on that session.
    @MainActor
    private static func seedState(for session: PTYSession) -> SessionState {
        let state = WorkgroupIntrospection.state(for: session)
        return state == .unknown ? .idle : state
    }

    @MainActor
    private func publishStatusUpdate(watcher: WorkgroupWatcher,
                                     reason: StatusUpdate.Reason,
                                     stateReached: String,
                                     detail: String) {
        // A watcher registered with notify_user delivers its own push when
        // its goal is reached: the model proved unreliable at deciding to
        // notify after the fact, so the user's registration-time intent is
        // honored mechanically. Drops/timeouts are not the asked-for event
        // and stay chat-only.
        var pushed: Bool?
        if watcher.notifyUser == true,
           reason == .stateReached || reason == .conditionMet {
            if CompanionChatMuteRegistry.isMuted(chatID: chatID) {
                RLog("[Orchestrator \(chatID)] watcher push suppressed: chat is muted")
                pushed = false
            } else if CompanionPushRegistry.canNotify {
                let title = watcher.workgroupName == watcher.roleName
                    ? watcher.workgroupName
                    : "\(watcher.workgroupName): \(watcher.roleName)"
                let body = detail
                Task {
                    do {
                        try await CompanionPushSender.send(title: title, body: body)
                    } catch {
                        RLog("Orchestrator dispatcher: watcher push failed: \(error)")
                    }
                }
                pushed = true
            } else {
                pushed = false
            }
        }
        // Screen age at fire time: lets the agent distinguish a fresh
        // transition (screen changed seconds ago, likely mid-workflow)
        // from a long-quiet session, without a get_screen_contents
        // round trip.
        let screenLastChanged = sessionByGUID(watcher.sessionGUID).flatMap {
            WorkgroupIntrospection.screenAgeDescription(for: $0)
        }
        let payload = StatusUpdate(
            watcherID: watcher.watcherID,
            workgroupID: watcher.workgroupID,
            workgroupName: watcher.workgroupName,
            roleID: watcher.roleID,
            roleName: watcher.roleName,
            reason: reason,
            stateReached: stateReached,
            timestamp: Date(),
            detail: detail,
            pushed: pushed,
            screenLastChanged: screenLastChanged)
        do {
            try broker?.publishMessageFromUser(
                chatID: chatID,
                content: .watcherEvent(payload))
        } catch {
            RLog("Orchestrator dispatcher: failed to publish status_update: \(error)")
        }
    }

    // MARK: - Screen-observation watchers

    // Spin up a headless AI poller for a statusless session and track it
    // by watcherID. The closures hold the dispatcher weakly so a running
    // poller never keeps a torn-down dispatcher alive.
    @MainActor
    private func startScreenPoll(for watcher: WorkgroupWatcher) {
        let id = watcher.watcherID
        let guid = watcher.sessionGUID
        let poller = ScreenWatchPoller(
            watcher: watcher,
            sessionProvider: { [weak self] in self?.sessionByGUID(guid) },
            onReached: { [weak self] in
                self?.screenPollFinished(watcherID: id, timedOut: false)
            },
            onTimedOut: { [weak self] in
                self?.screenPollFinished(watcherID: id, timedOut: true)
            })
        screenPollers[id] = poller
        poller.start()
    }

    // Arm the screen-observation backstop for a tab-status watcher.
    // Idempotent per watcherID. The timer Task waits for the session's
    // screen to go quiet (no textViewDidFindDirtyRects) for
    // tabStatusEscalationDelay, then takes ONE screenshot and asks the model
    // whether the target state has been reached:
    //   - reached: fire the watch (via the shared screen-poll completion).
    //   - not yet: the reported status may be legitimately "working" (a
    //     silent computation can leave the screen static); wait another
    //     interval and check once more. This is a slow single-check cadence,
    //     not a continuous poll, so a long-running task isn't billed a model
    //     round-trip every few seconds.
    // Fresh output keeps resetting the quiet clock, so an actively-updating
    // session never triggers a screenshot. The tab-status subscription stays
    // armed throughout: if the status transition does arrive,
    // handle(tabStatusNotification:) removes the watcher and cancels this
    // timer (and any in-flight check) via removeWatcherAuxiliaries, so the
    // backstop never fires after the watch is already resolved.
    //
    // No-op for two kinds of watcher, so callers don't have to pre-filter:
    //   - Non-tab-status (.screenPoll) watchers already run their own
    //     continuous poller in screenPollers[id]; arming here would let
    //     runSingleScreenCheck overwrite that slot and orphan the running
    //     poller. doStartCodeReview can reach this with a .screenPoll watcher
    //     it dedup-matched (a register_watch made before the session emitted
    //     its first cc-status), so the guard is load-bearing, not cosmetic.
    //   - .working targets: the backstop only fires after the screen has been
    //     QUIET for a while, which is evidence the session is idle, not
    //     working. A quiet-screen screenshot could never confirm activity, so
    //     there is nothing to escalate; the tab-status transition stays the
    //     only trigger.
    @MainActor
    private func armScreenEscalation(for watcher: WorkgroupWatcher) {
        guard watcher.effectiveMode == .tabStatus else { return }
        guard watcher.targetState != .working else { return }
        let id = watcher.watcherID
        guard escalationTimers[id] == nil else { return }
        escalationTimers[id] = Task { @MainActor [weak self] in
            await self?.runScreenEscalation(watcherID: id)
        }
    }

    @MainActor
    private func runScreenEscalation(watcherID id: String) async {
        let delay = Self.tabStatusEscalationDelay
        let interval = UInt64(delay * 1_000_000_000)
        // The screen-change stamp at our most recent screenshot check. While
        // the screen stays on this stamp a re-check would read byte-for-byte
        // identical contents and return the same verdict, so we skip it until
        // a fresh dirty-rect advances the stamp.
        var lastCheckedStamp: TimeInterval?
        while !Task.isCancelled {
            // Still an active, unfired tab-status watcher on a live session?
            guard let watcher = watchers.first(where: { $0.watcherID == id }) else {
                return
            }
            guard let session = sessionByGUID(watcher.sessionGUID) else {
                // Session gone; the terminate handler owns watcher cleanup.
                return
            }
            // Active output resets the quiet clock (textViewDidFindDirtyRects),
            // so a working session keeps us here and never bills a check. This
            // is the "restart the timer on input" behavior: every screen
            // change pushes the screenshot back to last-change + delay.
            let quiet = session.timeSinceScreenContentsLastChanged
            if quiet < delay {
                let remaining = max(1, delay - quiet)
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                continue
            }
            // Screen has been quiet long enough. If it hasn't changed since
            // our last check, the verdict is unchanged too: wait (cheaply,
            // no model call) for the next change instead of re-asking.
            let stamp = session.screenContentsLastChangedAt
            if lastCheckedStamp == stamp {
                try? await Task.sleep(nanoseconds: interval)
                continue
            }
            DLog("Orchestrator dispatcher: tab-status watcher \(id) "
                 + "(\(watcher.roleName) in \(watcher.workgroupName)) has had a "
                 + "quiet screen for \(Int(quiet))s without a status transition; "
                 + "confirming state from a screenshot.")
            let reached = await runSingleScreenCheck(for: watcher)
            if Task.isCancelled { return }
            if reached {
                // Resolve through the shared completion path (removal,
                // persistence, aux teardown, status_update with the
                // escalation-flavored detail).
                screenPollFinished(watcherID: id, timedOut: false)
                return
            }
            // Not yet. Remember the screen we just judged so we don't re-judge
            // the same contents, and wait a full interval before looking
            // again. Capturing the pre-check stamp is conservative: any change
            // during the check advances the stamp and forces a fresh judgement
            // next time rather than risking a missed transition.
            lastCheckedStamp = stamp
            DLog("Orchestrator dispatcher: screenshot for watcher \(id) shows "
                 + "the target is not reached yet; will re-check when its "
                 + "screen next changes.")
            try? await Task.sleep(nanoseconds: interval)
        }
    }

    // Take a single screenshot judgement for an escalated watcher. The
    // poller is parked in screenPollers for the call's duration so
    // removeWatcherAuxiliaries can abort the in-flight model request if the
    // watch fires or is dropped mid-check.
    @MainActor
    private func runSingleScreenCheck(for watcher: WorkgroupWatcher) async -> Bool {
        let id = watcher.watcherID
        let guid = watcher.sessionGUID
        let poller = ScreenWatchPoller(
            watcher: watcher,
            sessionProvider: { [weak self] in self?.sessionByGUID(guid) })
        screenPollers[id] = poller
        let reached = await poller.checkOnce()
        // Only clear our own entry; a concurrent teardown may have already
        // removed (and cancelled) it.
        if screenPollers[id] === poller {
            screenPollers.removeValue(forKey: id)
        }
        return reached
    }

    // Tear down every piece of auxiliary machinery attached to a watcher:
    // its escalation timer and any screen poller. Called from each path that
    // removes a watcher from the list (tab-status fire, screen-poll fire,
    // session terminate, unregister). An escalated tab-status watcher has
    // both, and whichever firing path wins must stop the other so it can't
    // fire again or keep polling/billing.
    @MainActor
    private func removeWatcherAuxiliaries(watcherID: String) {
        if let timer = escalationTimers.removeValue(forKey: watcherID) {
            timer.cancel()
        }
        cancelScreenPoller(watcherID: watcherID)
    }

    // Terminal callback from a poller: it either decided the target was
    // reached or gave up at the time cap. Drop the watcher and poller and
    // publish the matching status_update. Routing through the dispatcher
    // (rather than letting the poller touch the broker) keeps the watcher
    // list the single owner of watcher lifecycle.
    @MainActor
    private func screenPollFinished(watcherID: String, timedOut: Bool) {
        screenPollers.removeValue(forKey: watcherID)
        guard let watcher = watchers.first(where: { $0.watcherID == watcherID }) else {
            return
        }
        watchers.removeAll { $0.watcherID == watcherID }
        persistWatchers()
        // The escalation timer (if this was an escalated tab-status watcher)
        // already fired to start this poller; clear its slot defensively.
        removeWatcherAuxiliaries(watcherID: watcherID)
        if timedOut {
            publishStatusUpdate(
                watcher: watcher,
                reason: .watchTimedOut,
                stateReached: "",
                detail: "Watch timed out: \(watcher.roleName) in \(watcher.workgroupName) "
                    + "did not reach \(watcher.goalDescription) within 5 minutes. It was "
                    + "watched by reading its screen. Check it with get_screen_contents, "
                    + "or register_watch again to keep waiting.")
        } else if let condition = watcher.condition {
            publishStatusUpdate(
                watcher: watcher,
                reason: .conditionMet,
                stateReached: "",
                detail: "\(watcher.roleName) in \(watcher.workgroupName) met the watched "
                    + "condition '\(condition)' (detected by screen observation).")
        } else {
            let target = watcher.targetState?.rawValue ?? "unknown"
            // A screen poller on a .tabStatus watcher is the escalation
            // backstop: the session does report status, it was just stale
            // for long enough that we confirmed the state from the screen
            // instead. A .screenPoll watcher's session reports no status at
            // all. The detail spells out which so the agent isn't misled.
            let how = watcher.effectiveMode == .tabStatus
                ? "confirmed by reading the screen; its reported status had "
                    + "stopped updating for several minutes, so the status may "
                    + "have been stale"
                : "detected by screen observation; this session reports no "
                    + "machine-readable status"
            publishStatusUpdate(
                watcher: watcher,
                reason: .stateReached,
                stateReached: target,
                detail: "\(watcher.roleName) in \(watcher.workgroupName) reached state "
                    + "'\(target)' (\(how)).")
        }
    }

    @MainActor
    private func cancelScreenPoller(watcherID: String) {
        if let poller = screenPollers.removeValue(forKey: watcherID) {
            poller.cancel()
        }
    }

    private func sessionByGUID(_ guid: String) -> PTYSession? {
        // anySession(withGUID:) enumerates ALL sessions including peer-port
        // sessions (Code Review, Diff, any side-pane peer). allSessions()
        // only returns tab/split sessions and silently drops peers, which
        // would mark every Code Review watcher as "dropped after restart"
        // in reconcilePersistedWatchers and would silently skip peer roles
        // in seedState (firing every idle watcher on first tabStatus).
        return iTermController.sharedInstance()?.anySession(withGUID: guid)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Persisted-set write-through

    private func persistClaimedScopes() {
        do {
            try broker?.listModel
                .setClaimedScopes(claimedScopes, forChatID: chatID)
        } catch {
            RLog("Orchestrator dispatcher: failed to persist claimed workgroups: \(error)")
        }
    }

    private func persistWatchers() {
        do {
            try broker?.listModel
                .setWatchers(watchers, forChatID: chatID)
        } catch {
            RLog("Orchestrator dispatcher: failed to persist watchers: \(error)")
        }
    }

    // MARK: - Public entrypoint

    // Called by OrchestratorClient for each tool_use block the agent
    // published as .remoteCommandRequest(.external(...)). Always
    // returns Data; errors are encoded as OrchestratorResult.error
    // rather than thrown so the LLM gets a structured result on every
    // path.
    //
    // Routes by tool-name prefix:
    //   - "session_*": the per-session RemoteCommand surface (mirrors
    //     AITerm's session-bound tools but targeted by raw session
    //     GUID). Decodes per RemoteCommand.Content, gates via the
    //     per-session claim, dispatches on the PTYSession.
    //   - everything else: the workgroup-shaped tools defined in
    //     OrchestratorCommand. Decodes, gates via workgroup claim or
    //     spawn prompt, executes.
    //
    // @MainActor: claimedScopes (read by applyGating /
    // ensureClaim / ensureSessionClaim) and watchers (mutated by
    // command execution paths) are not synchronized. Pinning the
    // entrypoint to the main actor serializes concurrent
    // session_* / workgroup tool calls so two of them can't race on
    // the same Set / Array.
    @MainActor
    func handleToolCall(name: String,
                        jsonArgs: Data,
                        llmMessage: LLM.Message) async -> Data {
        if tornDown {
            return safeEncode(OrchestratorError
                .unsupported(reason:
                    "This chat is no longer in orchestration mode.").asResult)
        }
        if name.hasPrefix("session_") {
            return await handleSessionToolCall(name: name,
                                               jsonArgs: jsonArgs,
                                               llmMessage: llmMessage)
        }
        do {
            let command = try decodeCommand(name: name, jsonArgs: jsonArgs)
            try await applyGating(for: command)
            let result = try await execute(command)
            return try encode(result)
        } catch let error as OrchestratorError {
            return safeEncode(error.asResult)
        } catch {
            return safeEncode(OrchestratorError
                .malformedArgs(reason: error.localizedDescription).asResult)
        }
    }

    // Session-shaped tool dispatch. The wire `name` is
    // "session_<functionName>" matching a RemoteCommand.Content case;
    // we look up the case by functionName, decode the prototype from
    // jsonArgs (with `session_guid` extracted as the target session),
    // gate write-shaped categories on a per-session claim, and call
    // PTYSession.execute. Result string is returned as plain text in
    // a Data buffer (matching how the previous agent-side path
    // returned the response to the LLM).
    @MainActor
    private func handleSessionToolCall(name: String,
                                       jsonArgs: Data,
                                       llmMessage: LLM.Message) async -> Data {
        let rawName = String(name.dropFirst("session_".count))
        guard let content = RemoteCommand.Content.allCases.first(
            where: { $0.functionName == rawName }) else {
            return Data("Error: unknown session tool \(name)".utf8)
        }
        let argsObject: [String: Any]
        do {
            guard let dict = try JSONSerialization.jsonObject(
                with: jsonArgs) as? [String: Any] else {
                return Data("Error: arguments not a JSON object".utf8)
            }
            argsObject = dict
        } catch {
            return Data("Error decoding arguments: \(error.localizedDescription)".utf8)
        }
        guard let sessionGuid = argsObject["session_guid"] as? String else {
            return Data("Error: missing session_guid".utf8)
        }
        var prototypeDict = argsObject
        prototypeDict.removeValue(forKey: "session_guid")

        let remoteCommand: RemoteCommand
        do {
            remoteCommand = try Self.buildRemoteCommand(
                content: content,
                prototypeDict: prototypeDict,
                llmMessage: llmMessage)
        } catch {
            return Data("Error decoding arguments: \(error.localizedDescription)".utf8)
        }

        guard let session = iTermController.sharedInstance()?.anySession(withGUID: sessionGuid) else {
            return Data("Error: no session with GUID \(sessionGuid)".utf8)
        }

        if Self.requiresSessionClaim(content) {
            if !(await ensureSessionClaim(sessionGuid: sessionGuid)) {
                return Data("The user declined to allow this chat to control session \(sessionGuid).".utf8)
            }
        }

        // session.execute's completion isn't guaranteed to fire on every
        // code path: a browser command whose WebView is gone, a remote-host
        // lookup that the SSH daemon never responds to, or a command-history
        // query whose database call hangs would all park this Task forever.
        // ResolveOnce wraps the continuation so the timeout can race the
        // real completion; whichever fires first wins, and any later
        // callback (or a second call from a misbehaving execute path) is
        // dropped. Timeout matches doStartSession's 30s.
        let response = await withResolvedOnce(
            timeoutSeconds: 30
        ) { (resume: @escaping (String?) -> Void) in
            do {
                try session.execute(remoteCommand) { response, _ in
                    // session.execute's completion can fire off-main
                    // (browser commands resolve on WebKit queues, some
                    // command-history paths dispatch async).
                    resume(response)
                }
            } catch {
                resume("Error executing command: \(error.localizedDescription)")
            }
        }
        guard let response else {
            return Data("Error: session command timed out after 30s.".utf8)
        }
        return Data(response.utf8)
    }

    // Per-content decode helper. The runtime case carries the prototype
    // type erased; switch over the case to pick the concrete Decodable
    // and bind it back to a new RemoteCommand.Content with the decoded
    // value. Internal (not private) so OrchestratorSessionToolDecodeTests
    // can pin the 24-arm switch — a typo here would silently mis-decode
    // one tool's args.
    @MainActor
    static func buildRemoteCommand(
        content: RemoteCommand.Content,
        prototypeDict: [String: Any],
        llmMessage: LLM.Message
    ) throws -> RemoteCommand {
        let prototypeJSON = try JSONSerialization.data(withJSONObject: prototypeDict)
        let decoder = JSONDecoder()
        let updated: RemoteCommand.Content
        switch content {
        case .isAtPrompt:
            updated = .isAtPrompt(try decoder.decode(RemoteCommand.IsAtPrompt.self, from: prototypeJSON))
        case .executeCommand:
            updated = .executeCommand(try decoder.decode(RemoteCommand.ExecuteCommand.self, from: prototypeJSON))
        case .getLastExitStatus:
            updated = .getLastExitStatus(try decoder.decode(RemoteCommand.GetLastExitStatus.self, from: prototypeJSON))
        case .getCommandHistory:
            updated = .getCommandHistory(try decoder.decode(RemoteCommand.GetCommandHistory.self, from: prototypeJSON))
        case .getLastCommand:
            updated = .getLastCommand(try decoder.decode(RemoteCommand.GetLastCommand.self, from: prototypeJSON))
        case .getCommandBeforeCursor:
            updated = .getCommandBeforeCursor(try decoder.decode(RemoteCommand.GetCommandBeforeCursor.self, from: prototypeJSON))
        case .searchCommandHistory:
            updated = .searchCommandHistory(try decoder.decode(RemoteCommand.SearchCommandHistory.self, from: prototypeJSON))
        case .getCommandOutput:
            updated = .getCommandOutput(try decoder.decode(RemoteCommand.GetCommandOutput.self, from: prototypeJSON))
        case .getTerminalSize:
            updated = .getTerminalSize(try decoder.decode(RemoteCommand.GetTerminalSize.self, from: prototypeJSON))
        case .getShellType:
            updated = .getShellType(try decoder.decode(RemoteCommand.GetShellType.self, from: prototypeJSON))
        case .detectSSHSession:
            updated = .detectSSHSession(try decoder.decode(RemoteCommand.DetectSSHSession.self, from: prototypeJSON))
        case .getRemoteHostname:
            updated = .getRemoteHostname(try decoder.decode(RemoteCommand.GetRemoteHostname.self, from: prototypeJSON))
        case .getUserIdentity:
            updated = .getUserIdentity(try decoder.decode(RemoteCommand.GetUserIdentity.self, from: prototypeJSON))
        case .getCurrentDirectory:
            updated = .getCurrentDirectory(try decoder.decode(RemoteCommand.GetCurrentDirectory.self, from: prototypeJSON))
        case .setClipboard:
            updated = .setClipboard(try decoder.decode(RemoteCommand.SetClipboard.self, from: prototypeJSON))
        case .insertTextAtCursor:
            updated = .insertTextAtCursor(try decoder.decode(RemoteCommand.InsertTextAtCursor.self, from: prototypeJSON))
        case .deleteCurrentLine:
            updated = .deleteCurrentLine(try decoder.decode(RemoteCommand.DeleteCurrentLine.self, from: prototypeJSON))
        case .getManPage:
            updated = .getManPage(try decoder.decode(RemoteCommand.GetManPage.self, from: prototypeJSON))
        case .createFile:
            updated = .createFile(try decoder.decode(RemoteCommand.CreateFile.self, from: prototypeJSON))
        case .searchBrowser:
            updated = .searchBrowser(try decoder.decode(RemoteCommand.SearchBrowser.self, from: prototypeJSON))
        case .loadURL:
            updated = .loadURL(try decoder.decode(RemoteCommand.LoadURL.self, from: prototypeJSON))
        case .webSearch:
            updated = .webSearch(try decoder.decode(RemoteCommand.WebSearch.self, from: prototypeJSON))
        case .getURL:
            updated = .getURL(try decoder.decode(RemoteCommand.GetURL.self, from: prototypeJSON))
        case .readWebPage:
            updated = .readWebPage(try decoder.decode(RemoteCommand.ReadWebPage.self, from: prototypeJSON))
        }
        return RemoteCommand(llmMessage: llmMessage, content: updated)
    }

    // Whether dispatching the given RemoteCommand on a session
    // requires the chat to have a per-session claim. True for write-
    // shaped categories (executing commands, typing, writing to
    // clipboard / filesystem, browser actions); false for read-only
    // categories (terminal state, command history, manpages). The
    // split matches the workgroup-shaped tools' read/write category
    // distinction so the user sees consistent gating across both
    // families: reads are free, writes prompt once per session.
    //
    // Internal (not private) so tests can pin the classification —
    // a future RemoteCommand category addition without updating both
    // arms here would otherwise silently drop into one of them.
    static func requiresSessionClaim(_ content: RemoteCommand.Content) -> Bool {
        switch content.permissionCategory {
        case .runCommands, .writeToClipboard, .typeForYou,
                .writeToFilesystem, .actInWebBrowser:
            return true
        case .checkTerminalState, .viewHistory, .viewManpages:
            return false
        }
    }

    static var toolDefinitions: [ToolDefinition] {
        return OrchestratorCommand.allToolDefinitions
    }

    // MARK: - Decode

    private func decodeCommand(name: String, jsonArgs: Data) throws -> OrchestratorCommand {
        guard let tool = ToolName(rawValue: name) else {
            throw OrchestratorError.unknownTool(name)
        }
        let decoder = JSONDecoder()
        switch tool {
        case .listWorkgroups:
            return .listWorkgroups
        case .getState:
            struct A: Decodable {
                let session_guid: String
            }
            return .getState(sessionGuid: try decoder.decode(A.self, from: jsonArgs).session_guid)
        case .getScreenContents:
            return .getScreenContents(try decoder.decode(GetScreenContentsArgs.self, from: jsonArgs))
        case .scrollWheel:
            return .scrollWheel(try decoder.decode(ScrollWheelArgs.self, from: jsonArgs))
        case .listWorkgroupClippings:
            struct A: Decodable {
                let workgroup_id: String
                let type_filter: String?
            }
            let a = try decoder.decode(A.self, from: jsonArgs)
            return .listWorkgroupClippings(workgroupID: a.workgroup_id, typeFilter: a.type_filter)
        case .sendText:
            return .sendText(try decoder.decode(SendTextArgs.self, from: jsonArgs))
        case .interrupt:
            struct A: Decodable {
                let session_guid: String
            }
            return .interrupt(sessionGuid: try decoder.decode(A.self, from: jsonArgs).session_guid)
        case .addWorkgroupClipping:
            return .addWorkgroupClipping(try decoder.decode(AddClippingArgs.self, from: jsonArgs))
        case .startSession:
            return .startSession(try decoder.decode(StartSessionArgs.self, from: jsonArgs))
        case .startCodeReview:
            return .startCodeReview(try decoder.decode(StartCodeReviewArgs.self, from: jsonArgs))
        case .registerWatch:
            return .registerWatch(try decoder.decode(RegisterWatchArgs.self, from: jsonArgs))
        case .unregisterWatch:
            struct A: Decodable { let watcher_id: String }
            return .unregisterWatch(watcherID: try decoder.decode(A.self, from: jsonArgs).watcher_id)
        case .listWatches:
            return .listWatches
        case .notify:
            return .notify(try decoder.decode(NotifyArgs.self, from: jsonArgs))
        case .requestNotificationPermission:
            return .requestNotificationPermission
        }
    }

    // MARK: - Gating

    @MainActor
    private func applyGating(for command: OrchestratorCommand) async throws {
        switch command.category {
        case .write:
            let scope: String
            switch command.claimRequirement {
            case .none:
                return
            case .workgroup(let workgroupID):
                scope = workgroupID
            case .session(let sessionGuid):
                // Resolve the session to the workgroup scope its claim
                // lives under (a real instance ID, or "session:<guid>"
                // for a standalone session). A missing session surfaces
                // as unknown_session rather than silently skipping the
                // claim and letting the write fall through.
                guard let resolved = WorkgroupIntrospection.claimScope(
                    forSessionGuid: sessionGuid) else {
                    throw OrchestratorError.unknownSession(guid: sessionGuid)
                }
                scope = resolved
            }
            if !(await ensureClaim(workgroupID: scope)) {
                throw OrchestratorError.permissionDenied
            }
        case .spawn:
            let approved = try await gateSpawn(command: command)
            if !approved {
                throw OrchestratorError.permissionDenied
            }
        case .readOnly, .watcher:
            return
        }
    }

    // Ensure this chat has user approval to control the session
    // identified by `sessionGuid` (send keystrokes, interrupt running
    // commands, etc.). The session is wrapped in a synthetic single-
    // session workgroup ("session:<guid>"), so its approval state
    // lives in the same `claimedScopes` set the workgroup-shaped
    // tools use. session_* tools call this before dispatching to
    // PTYSession.execute so a one-time user prompt gates the whole
    // family for the rest of the chat. Returns true when the chat is
    // already claimed for this session or the user just approved;
    // false if the user declines (the caller surfaces an error string
    // to the LLM).
    @MainActor
    public func ensureSessionClaim(sessionGuid: String) async -> Bool {
        let workgroupID = WorkgroupIntrospection.syntheticWorkgroupIDPrefix + sessionGuid
        return await ensureClaim(workgroupID: workgroupID)
    }

    // Shared claim check + prompt + persist. Returns true when the
    // workgroup is already claimed or the user just approved.
    //
    // Concurrent callers asking about the same workgroupID share one
    // prompt: the first caller spawns a Task that owns the prompt and
    // persists the result, later callers await the same Task. Without
    // this, two writes against the same unclaimed workgroup arriving in
    // the same turn would both pass the contains check (a synchronous
    // read can't see another in-flight prompt) and each call
    // promptForClaim, stacking two bubbles.
    @MainActor
    private func ensureClaim(workgroupID: String) async -> Bool {
        if claimedScopes.contains(workgroupID) {
            return true
        }
        if let existing = pendingClaimTasks[workgroupID] {
            return await existing.value
        }
        let task = Task<Bool, Never> { @MainActor [weak self] in
            guard let self else { return false }
            // Another caller may have raced ahead and approved while we
            // were spawning, so re-check before prompting.
            if self.claimedScopes.contains(workgroupID) {
                return true
            }
            let approved = await self.promptForClaim(workgroupID: workgroupID)
            if approved {
                self.claimedScopes.insert(workgroupID)
                self.persistClaimedScopes()
            }
            return approved
        }
        pendingClaimTasks[workgroupID] = task
        let approved = await task.value
        pendingClaimTasks.removeValue(forKey: workgroupID)
        return approved
    }

    // Confirm with the user that this chat may control the named
    // workgroup (or standalone session, when workgroupID has the
    // synthetic "session:" prefix). Publishes an inline-bubble
    // request through the broker, parks on a continuation, and waits
    // for the matching user-side workgroupPermissionResponse to
    // resume it. The bubble carries the resolved name so it still
    // reads correctly if the workgroup is torn down before the user
    // answers.
    @MainActor
    private func promptForClaim(workgroupID: String) async -> Bool {
        let workgroupName = WorkgroupIntrospection.displayName(forWorkgroupID: workgroupID)
        let summary: String
        if workgroupID.hasPrefix(WorkgroupIntrospection.syntheticWorkgroupIDPrefix) {
            summary = "The agent is asking to send keystrokes and interrupt "
                + "running commands in session \u{201C}\(workgroupName)\u{201D}. "
                + "Approval is sticky for the rest of this chat. Deny to refuse "
                + "this and future control of this session until you "
                + "explicitly approve."
        } else {
            summary = "The agent is asking to send keystrokes, interrupt running "
                + "commands, and post clippings to this workgroup. Approval is sticky "
                + "for the rest of this chat. Deny to refuse this and future control "
                + "of this workgroup until you explicitly approve."
        }
        return await awaitPermission(workgroupID: workgroupID,
                                      workgroupName: workgroupName,
                                      summary: summary)
    }

    // The spawn prompt uses the sentinel workgroupID
    // WorkgroupIntrospection.spawnWorkgroupID since there's no real
    // workgroup yet (it's literally the request to create one). The
    // cell renderer matches the same constant to pick the "Open a
    // new session?" bubble copy instead of the "Allow agent to
    // control workgroup …" copy used for real workgroup claims; see
    // ChatViewController.swift's workgroupPermissionRequest branch.
    // The renderer doesn't depend on the ID resolving to anything live
    // — only on the name and summary being human-readable.
    // Spawn gating for orchestration mode. Opening a session with no
    // command to run is always allowed: nothing executes that could
    // surprise the user, so there's nothing to vet. When the agent
    // supplies a command, run it through the auto-mode classifier the
    // same way session-bound writes are checked — an unambiguous "safe"
    // verdict auto-approves the spawn, and anything else (block,
    // needs-manual-approval, unparseable, or a classifier error, all of
    // which fail closed) falls back to the inline user prompt.
    private func gateSpawn(command: OrchestratorCommand) async throws -> Bool {
        guard let cmd = Self.spawnCommand(from: command) else {
            return true
        }
        if await CommandSafetyChecker.check(cmd) {
            return true
        }
        return try await promptForSpawn(command: command)
    }

    // The shell command a start_session request will run, or nil when it
    // just opens the profile's default shell.
    private static func spawnCommand(from command: OrchestratorCommand) -> String? {
        guard case .startSession(let args) = command else {
            return nil
        }
        return (args.command?.isEmpty == false) ? args.command : nil
    }

    private func promptForSpawn(command: OrchestratorCommand) async throws -> Bool {
        let placement: String
        if case .startSession(let args) = command {
            switch args.window ?? .tab {
            case .new: placement = "a new window"
            case .tab: placement = "a new tab in the current window"
            case .current: placement = "a vertical split of the current pane"
            }
        } else {
            placement = "a new session"
        }
        let cmd = Self.spawnCommand(from: command)
        let detail: String
        if let cmd {
            detail = "The agent is asking to open \(placement) and run \u{201C}\(cmd)\u{201D}."
        } else {
            detail = "The agent is asking to open \(placement)."
        }
        return await awaitPermission(workgroupID: WorkgroupIntrospection.spawnWorkgroupID,
                                      workgroupName: "New session",
                                      summary: detail)
    }

    // Common path: publish the request, park, wait, return. On publish
    // failure we resume with `false` so the agent always gets an
    // answer rather than hanging forever. @MainActor-isolated because
    // broker.publish fans out synchronously to subscribers (including
    // the chat view), and those subscribers touch AppKit — running
    // this off-main triggers an autolayout-from-background crash.
    @MainActor
    private func awaitPermission(workgroupID: String,
                                 workgroupName: String,
                                 summary: String) async -> Bool {
        let requestID = UUID().uuidString
        return await withCheckedContinuation { continuation in
            pendingPermissionPrompts[requestID] = continuation
            do {
                try broker?.publishMessageFromAgent(
                    chatID: chatID,
                    content: .clientLocal(.init(action:
                        .workgroupPermissionRequest(requestID: requestID,
                                                  workgroupID: workgroupID,
                                                  workgroupName: workgroupName,
                                                  summary: summary))))
            } catch {
                RLog("Orchestrator dispatcher: failed to publish permission request: \(error)")
                if let cont = pendingPermissionPrompts.removeValue(forKey: requestID) {
                    cont.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Mention-driven claims

    // The user @-mentioned one or more sessions/workgroups in a chat
    // message. Treat each named target as standing permission for this
    // chat to control it: pre-insert its claim scope so the first write
    // there skips the inline approval prompt. For every scope that
    // wasn't already claimed we publish an orchestrationPermissionGranted
    // bubble so the grant is visible and the user can revoke it.
    //
    // Resolving the scope mirrors applyGating's .session path: a bare
    // session guid resolves through WorkgroupIntrospection.claimScope to
    // the workgroup/synthetic scope its claim actually lives under, so a
    // later write against that session finds the scope already claimed.
    // The "session:" / "wg-" mention forms are themselves claim scopes.
    @MainActor
    func grantClaimsFromMentions(in text: String) {
        if tornDown { return }
        for mention in MentionParser.mentions(in: text) {
            guard let scope = claimScope(forMention: mention) else { continue }
            // contains() also de-dups repeated mentions of the same
            // target within one message: only the first inserts and
            // publishes, the rest short-circuit here.
            if claimedScopes.contains(scope) { continue }
            claimedScopes.insert(scope)
            persistClaimedScopes()
            publishPermissionGranted(scope: scope)
        }
    }

    private func claimScope(forMention mention: MentionParser.Mention) -> String? {
        guard mention.prefix == nil else {
            // "session:<uuid>" / "wg-<uuid>" are already claim scopes.
            return mention.identifier
        }
        // Bare session guid: resolve to the scope its claim lives under.
        return WorkgroupIntrospection.claimScope(forSessionGuid: mention.uuid)
    }

    @MainActor
    private func publishPermissionGranted(scope: String) {
        let name = WorkgroupIntrospection.displayName(forWorkgroupID: scope)
        do {
            try broker?.publishMessageFromAgent(
                chatID: chatID,
                content: .clientLocal(.init(action:
                    .orchestrationPermissionGranted(scope: scope, name: name))))
        } catch {
            RLog("Orchestrator dispatcher: failed to publish permission-granted notice: \(error)")
        }
    }

    // Drop a claim the user previously granted (via @-mention or an
    // approved prompt). Removing the scope means the next write there
    // re-prompts. No-op when the scope isn't claimed so a double-tap on
    // the Revoke button doesn't post a second confirmation notice.
    @MainActor
    func revokeClaim(scope: String) {
        if tornDown { return }
        guard claimedScopes.remove(scope) != nil else { return }
        persistClaimedScopes()
        let name = WorkgroupIntrospection.displayName(forWorkgroupID: scope)
        let notice = "Revoked this chat’s permission to control "
            + "\u{201C}\(name)\u{201D}. The agent will ask before its "
            + "next action there."
        do {
            try broker?.publishNotice(chatID: chatID, notice: notice)
        } catch {
            RLog("Orchestrator dispatcher: failed to publish revoke notice: \(error)")
        }
    }

    // MARK: - Execute

    private func execute(_ command: OrchestratorCommand) async throws -> OrchestratorResult {
        switch command {
        case .listWorkgroups:
            return try await doListWorkgroups()
        case .getState(let sessionGuid):
            return try await doGetState(sessionGuid: sessionGuid)
        case .getScreenContents(let args):
            return try await doGetScreenContents(args)
        case .scrollWheel(let args):
            return try await doScrollWheel(args)
        case .listWorkgroupClippings(let workgroupID, let typeFilter):
            return try await doListWorkgroupClippings(
                workgroupID: workgroupID, typeFilter: typeFilter)
        case .sendText(let args):
            return try await doSendText(args)
        case .interrupt(let sessionGuid):
            return try await doInterrupt(sessionGuid: sessionGuid)
        case .addWorkgroupClipping(let args):
            return try await doAddWorkgroupClipping(args)
        case .startSession(let args):
            return try await doStartSession(args)
        case .startCodeReview(let args):
            return try await doStartCodeReview(args)
        case .registerWatch(let args):
            return try await doRegisterWatch(args)
        case .unregisterWatch(let watcherID):
            return doUnregisterWatch(watcherID: watcherID)
        case .listWatches:
            return doListWatches()
        case .notify(let args):
            return try await doNotify(args)
        case .requestNotificationPermission:
            return try await doRequestNotificationPermission()
        }
    }

    // Push a notification to the paired companion phone through the relay.
    @MainActor
    private func doNotify(_ args: NotifyArgs) async throws -> OrchestratorResult {
        guard CompanionPushRegistry.canNotify else {
            switch (CompanionPairingController.shared.isPhoneConnected, CompanionPushRegistry.authorization) {
            case (true, .notDetermined):
                throw OrchestratorError.unsupported(
                    reason: "Notifications are not enabled on the paired phone yet. Call request_notification_permission first.")
            case (_, .denied):
                throw OrchestratorError.unsupported(
                    reason: "The user has notifications turned off for iTerm2 Buddy. Do not push them about it; they can enable it in iOS Settings if they want alerts.")
            default:
                throw OrchestratorError.unsupported(
                    reason: "No paired companion phone is registered for notifications.")
            }
        }
        if CompanionChatMuteRegistry.isMuted(chatID: chatID) {
            RLog("[Orchestrator \(chatID)] notify tool suppressed: chat is muted")
            throw OrchestratorError.unsupported(
                reason: "The user has muted this chat's notifications on their phone, so the notification was not sent. Do not try to work around it.")
        }
        do {
            try await CompanionPushSender.send(title: args.title, body: args.body)
        } catch {
            throw OrchestratorError.unsupported(
                reason: "Notification delivery failed: \(error.localizedDescription)")
        }
        return .ack
    }

    // Have the connected phone show iOS's notification-permission prompt.
    // Blocks (with a deadline) on the user's answer.
    @MainActor
    private func doRequestNotificationPermission() async throws -> OrchestratorResult {
        if CompanionPushRegistry.canNotify {
            // Already good to go; don't bother the user.
            return .ack
        }
        guard CompanionPairingController.shared.isPhoneConnected else {
            throw OrchestratorError.unsupported(
                reason: "No companion phone is connected right now, so permission cannot be requested.")
        }
        let authorization = await CompanionPairingController.shared.requestNotificationPermission()
        switch authorization {
        case .authorized:
            return .ack
        case .denied:
            throw OrchestratorError.unsupported(
                reason: "The user declined notification permission. Do not ask again; iOS only shows the prompt once. If they change their mind they can enable notifications for iTerm2 Buddy in iOS Settings.")
        case .notDetermined:
            throw OrchestratorError.unsupported(
                reason: "The phone could not show the permission prompt.")
        case nil:
            throw OrchestratorError.timeout
        }
    }

    // MARK: - Implementations

    // Walks iTermWorkgroupController active instances and wraps each
    // standalone session in a synthetic single-session workgroup.
    @MainActor
    private func doListWorkgroups() async throws -> OrchestratorResult {
        return .workgroups(WorkgroupIntrospection.allWorkgroups())
    }

    @MainActor
    private func doGetState(sessionGuid: String) async throws -> OrchestratorResult {
        let resolved = try resolveSessionOrThrow(sessionGuid)
        return .sessionState(WorkgroupIntrospection.stateInfo(for: resolved))
    }

    // Centralized resolve so every session-targeted tool reports a
    // missing session the same way. A session_guid is globally unique,
    // so resolution either finds exactly one live session or fails;
    // there's no role-mismatch case to disambiguate.
    private func resolveSessionOrThrow(_ sessionGuid: String) throws -> WorkgroupIntrospection.ResolvedTarget {
        if let resolved = WorkgroupIntrospection.resolve(sessionGuid: sessionGuid) {
            return resolved
        }
        throw OrchestratorError.unknownSession(guid: sessionGuid)
    }

    @MainActor
    private func doGetScreenContents(_ args: GetScreenContentsArgs) async throws -> OrchestratorResult {
        let resolved = try resolveSessionOrThrow(args.sessionGuid)
        let contents = WorkgroupIntrospection.screenContents(
            for: resolved, requestedLines: args.lines)
        return .screenContents(contents)
    }

    // Inject scroll-wheel events so the agent can page through a
    // full-screen app's own history (the alternate screen keeps no
    // scrollback we can read). Errors when the program hasn't enabled
    // mouse reporting, since there's no scroll sequence it would honor;
    // the agent is told to fall back to get_screen_contents lines on the
    // primary screen. Despite injecting bytes, this is gated as read-only
    // (see OrchestratorCommand.category): it only moves the viewport.
    @MainActor
    private func doScrollWheel(_ args: ScrollWheelArgs) async throws -> OrchestratorResult {
        let resolved = try resolveSessionOrThrow(args.sessionGuid)
        if resolved.session.exited {
            throw OrchestratorError.targetNoLongerExists(sessionGuid: args.sessionGuid)
        }
        guard WorkgroupIntrospection.scrollReportingSupported(for: resolved.session) else {
            throw OrchestratorError.unsupported(reason:
                "Mouse reporting is not enabled in \(resolved.roleName) "
                + "(\(resolved.workgroupName)), so the scroll wheel can't be used. "
                + "If this is the primary screen, just ask get_screen_contents for "
                + "more lines instead.")
        }
        let up = (args.direction ?? .up) == .up
        let didScroll = resolved.session.reportScrollWheelForOrchestrator(
            up: up, lines: args.lines)
        guard didScroll else {
            // mouseReportingEnabled said yes a moment ago, so this is a
            // narrow race (the app turned reporting off between the check
            // and the write); report it the same way.
            throw OrchestratorError.unsupported(reason:
                "The scroll wheel could not be sent to \(resolved.roleName) "
                + "(\(resolved.workgroupName)); mouse reporting appears to be off.")
        }
        return .ack
    }

    @MainActor
    private func doListWorkgroupClippings(workgroupID: String,
                                           typeFilter: String?) async throws -> OrchestratorResult {
        guard let clippings = WorkgroupIntrospection.clippings(
            forWorkgroupID: workgroupID, typeFilter: typeFilter) else {
            throw OrchestratorError.unknownWorkgroup(workgroupID)
        }
        return .clippings(clippings)
    }

    // Registers an async watcher. Returns immediately; the chat
    // receives a status_update when the watch fires. Two forms,
    // selected by which argument is supplied (exactly one required):
    //   - target_state: watch for the session reaching idle/working/
    //     waiting. Exact tab-status transitions when the session
    //     reports machine-readable status; screen observation otherwise.
    //   - condition: a plain-English condition judged by screen
    //     observation, regardless of whether the session reports status.
    // De-duplicated on (sessionGUID, targetState, condition): if a
    // watcher with the same goal already exists, return the existing
    // watcher_id instead of creating a duplicate.
    //
    // If the target is already in the desired state at registration
    // time, fire immediately — the agent's caller-side expectation
    // is "I'll get a status_update when this is reached", and
    // already-reached counts.
    @MainActor
    private func doRegisterWatch(_ args: RegisterWatchArgs) async throws -> OrchestratorResult {
        let trimmedCondition = args.condition?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let condition = (trimmedCondition?.isEmpty == false) ? trimmedCondition : nil
        if (condition == nil) == (args.targetState == nil) {
            throw OrchestratorError.malformedArgs(reason:
                "Supply exactly one of target_state (watch for idle/working/waiting) "
                + "or condition (a plain-English condition judged by reading the screen).")
        }
        // target_state must be a state we actually transition to. .unknown
        // is part of the enum so we can model "no tabStatus yet" internally
        // and surface it on get_state output, but watchers keyed to it
        // would never fire because state(forTabStatus:) never emits it as
        // a transition. The schema documents this; reject loudly so the
        // LLM gets a structured error.
        if args.targetState == .unknown {
            throw OrchestratorError.malformedArgs(reason:
                "target_state \u{201C}unknown\u{201D} is reported by get_state but is not a watchable "
                + "transition. Pick \u{201C}idle\u{201D}, \u{201C}working\u{201D}, or \u{201C}waiting\u{201D} instead, "
                + "or use condition for anything else.")
        }
        let resolved = try resolveSessionOrThrow(args.sessionGuid)
        let session = resolved.session
        let guid = session.guid
        if let existing = watchers.first(where: {
            $0.sessionGUID == guid && $0.targetState == args.targetState
                && $0.condition == condition
        }) {
            return .watcherRegistered(Self.description(of: existing))
        }
        // Screen-observation path, taken when either:
        //   - a condition was supplied (conditions are always judged by
        //     reading the screen, even on status-reporting sessions), or
        //   - the session has no machine-readable status source, so there
        //     are no tab-status transitions to fire a state watcher on.
        // The AI poller fires the same status_update via
        // screenPollFinished. No seedState / already-reached fast path
        // here — the poller's first read detects an already-true goal.
        if condition != nil || !WorkgroupIntrospection.reportsSessionStatus(session) {
            let watcher = WorkgroupWatcher(
                watcherID: UUID().uuidString,
                sessionGUID: guid,
                workgroupID: resolved.workgroupID,
                workgroupName: resolved.workgroupName,
                roleID: resolved.roleID,
                roleName: resolved.roleName,
                targetState: args.targetState,
                registeredAt: Date(),
                mode: .screenPoll,
                condition: condition,
                notifyUser: args.notifyUser)
            watchers.append(watcher)
            persistWatchers()
            startScreenPoll(for: watcher)
            return .watcherRegistered(Self.description(of: watcher))
        }
        // Seed the per-session state history BEFORE appending the watcher.
        // If we appended first and a tabStatus notification slipped in
        // between, the handler would see a nil previous state, treat the
        // event as a transition, and fire the watcher we just registered.
        // Using seedState normalizes .unknown (nil tabStatus) to .idle so a
        // subsequent empty-tabStatus event from state(forTabStatus:) doesn't
        // register as a spurious .unknown to .idle transition.
        let currentState = Self.seedState(for: session)
        sessionStateHistory[guid] = currentState

        // Fast path: already in the desired state. Skip persistence
        // entirely and publish the synthetic match, deferred to the next
        // runloop turn so the tool_use / tool_result pair stays adjacent
        // in the persisted transcript.
        if currentState == args.targetState {
            let synthetic = WorkgroupWatcher(
                watcherID: UUID().uuidString,
                sessionGUID: guid,
                workgroupID: resolved.workgroupID,
                workgroupName: resolved.workgroupName,
                roleID: resolved.roleID,
                roleName: resolved.roleName,
                targetState: args.targetState,
                registeredAt: Date(),
                notifyUser: args.notifyUser)
            let reachedState = currentState.rawValue
            DispatchQueue.main.async { [weak self] in
                self?.publishStatusUpdate(
                    watcher: synthetic,
                    reason: .stateReached,
                    stateReached: reachedState,
                    detail: "\(synthetic.roleName) in \(synthetic.workgroupName) was already in state '\(reachedState)' at watch registration.")
            }
            return .watcherRegistered(Self.description(of: synthetic))
        }

        let watcher = WorkgroupWatcher(
            watcherID: UUID().uuidString,
            sessionGUID: guid,
            workgroupID: resolved.workgroupID,
            workgroupName: resolved.workgroupName,
            roleID: resolved.roleID,
            roleName: resolved.roleName,
            targetState: args.targetState,
            registeredAt: Date(),
            notifyUser: args.notifyUser)
        watchers.append(watcher)
        persistWatchers()
        // Tab-status watcher: arm the screen-observation backstop so a
        // dropped status event can't hang the watch indefinitely.
        armScreenEscalation(for: watcher)
        return .watcherRegistered(Self.description(of: watcher))
    }

    @MainActor
    private func doUnregisterWatch(watcherID: String) -> OrchestratorResult {
        let before = watchers.count
        watchers.removeAll { $0.watcherID == watcherID }
        if watchers.count != before {
            persistWatchers()
        }
        removeWatcherAuxiliaries(watcherID: watcherID)
        return .ack
    }

    @MainActor
    private func doListWatches() -> OrchestratorResult {
        return .watcherList(watchers.map { Self.description(of: $0) })
    }

    private static func description(of watcher: WorkgroupWatcher) -> WatcherDescription {
        return WatcherDescription(
            watcherID: watcher.watcherID,
            workgroupID: watcher.workgroupID,
            workgroupName: watcher.workgroupName,
            roleID: watcher.roleID,
            roleName: watcher.roleName,
            targetState: watcher.targetState,
            condition: watcher.condition,
            registeredAt: iso8601.string(from: watcher.registeredAt))
    }

    // Writes `text` to the target session's PTY as if the user typed
    // it. Defaults to appending a newline (the common case: "run this
    // command"). Per-session, never broadcast — even when broadcast
    // input is configured for the user, the agent's keystrokes stay
    // scoped to the addressed role.
    //
    // Special case: code-review-mode sessions present an in-session
    // prompt overlay before the program runs. While the overlay is
    // up, anything written to the PTY is invisible (the session
    // hasn't launched yet) and the user can't see what the agent
    // typed. Detecting the overlay routes send_text into it instead:
    // we populate the overlay's text, then fire its Start handler,
    // which both kicks off the actual launch and removes the overlay.
    @MainActor
    private func doSendText(_ args: SendTextArgs) async throws -> OrchestratorResult {
        let resolved = try resolveSessionOrThrow(args.sessionGuid)
        if resolved.session.exited {
            throw OrchestratorError.targetNoLongerExists(sessionGuid: args.sessionGuid)
        }
        let decoded: String
        do {
            decoded = try decodeAIBackslashEscapes(args.text)
        } catch {
            throw OrchestratorError.malformedArgs(reason: "text: \(error)")
        }
        if let overlay = resolved.session.view?.codeReviewPromptOverlay {
            overlay.text = decoded
            overlay.onStart?(decoded)
            return .ack
        }
        await Self.typeIntoPTY(session: resolved.session,
                               text: decoded,
                               appendNewline: args.appendNewline ?? true)
        return .ack
    }

    // Centralized rule for writing prompt-style text into a session as if
    // the user typed it. Two callers today: doSendText, and the no-overlay
    // fallback path in doStartCodeReview when the Code Review role is idle.
    //
    // Why this is more than `writeTaskNoBroadcast(text + "\r")`:
    //
    //  - On a bracketed-paste TUI (Claude Code, which uses Ink, and vim),
    //    raw multi-line prompt-style text would surface embedded \n bytes as
    //    Enter keystrokes mid-content. Wrap in ESC[200~ / ESC[201~ markers so
    //    the TUI receives the whole thing as one paste event rather than
    //    per-character input. We wrap regardless of whether the text
    //    contains a newline. Early revisions skipped the wrap for
    //    single-line text on the theory that the two-write split below
    //    was enough to keep the \r distinct; that turned out to be
    //    fragile for long single-line payloads (~500 chars), where the
    //    kernel chunks the master-side write across multiple slave
    //    reads and Ink heuristically treats the whole burst as paste,
    //    absorbing the trailing \r as a literal CR inside the buffer
    //    instead of as the submit gesture. Always-wrapping gives Ink an
    //    unambiguous end-of-paste marker (ESC[201~).
    //  - EXCEPTION to the wrap: if the payload carries any control byte
    //    other than LF (ESC, Ctrl-C, etc.), the caller is sending
    //    keystrokes rather than prose. A paste wrap would neutralize
    //    those control bytes by turning them into literal pasted data
    //    (the bug that left vim stuck in insert mode when the agent
    //    sent ESC :q LF and the ESC got pasted instead of switching
    //    mode). Skip the wrap and write raw in that case.
    //  - After the body, we wait briefly before sending the \r submit
    //    gesture. Two back-to-back writeTaskNoBroadcast calls produce
    //    two PTY events on the slave side which is USUALLY enough to
    //    keep the \r distinct, but for long payloads (~500 chars) Ink
    //    can ingest the body in chunks and still be busy when our
    //    immediate \r arrives, treating the \r as paste content. The
    //    short delay lets the TUI finish ingesting the BPM-terminated
    //    paste before it sees the submit. Async-await: doSendText
    //    awaits typeIntoPTY, so the tool_result is held back until the
    //    \r has actually been sent. Combined with Anthropic's
    //    disable_parallel_tool_use, no other tool call can race ahead
    //    of the \r — the agent only emits one tool call per turn, and
    //    the next turn doesn't start until this tool_result lands.
    //  - On a plain shell (or any non-BP-mode terminal), none of this
    //    applies; the line-discipline echoes \r as Enter immediately
    //    and one write is fine.

    /// Delay between the bracketed-paste body and the \r submit
    /// gesture. ~75ms is well above Ink's input-burst window
    /// (empirically ~25ms) and well below the threshold where the
    /// agent's tool round-trip starts to feel sluggish. Synchronous
    /// from doSendText's perspective via await.
    private static let bracketedPasteSubmitDelayNanos: UInt64 = 75_000_000

    @MainActor
    private static func typeIntoPTY(session: PTYSession,
                                    text: String,
                                    appendNewline: Bool) async {
        let inBracketedPasteMode = session.screen.terminalBracketedPasteMode
        // If the payload carries any control byte other than LF, the caller is
        // sending keystrokes (e.g. ESC :q LF to quit vim), not prompt-style
        // content. A paste wrap would neutralize those control bytes by
        // turning them into literal pasted data, so route them through the
        // raw write path even on a BP-mode terminal.
        let hasControlOtherThanLF = text.unicodeScalars.contains {
            $0.value < 0x20 && $0.value != 0x0A
        }
        if inBracketedPasteMode && !hasControlOtherThanLF {
            let bpStart = "\u{1B}[200~"
            let bpEnd = "\u{1B}[201~"
            session.writeTaskNoBroadcast(bpStart + text + bpEnd)
            if appendNewline {
                try? await Task.sleep(nanoseconds: bracketedPasteSubmitDelayNanos)
                session.writeTaskNoBroadcast("\r")
            }
        } else {
            // \r, not \n: TTYs accept carriage-return as the Enter key.
            // Sending \n leaves the line in the input buffer without
            // submitting (the user has to press Return themselves).
            session.writeTaskNoBroadcast(text + (appendNewline ? "\r" : ""))
        }
    }

    // Send SIGINT to the target's foreground process. The kernel
    // delivers it from the controlling TTY when we write the line-
    // discipline interrupt character, which is Ctrl-C (0x03) by
    // default. writeTaskNoBroadcast routes through the session's
    // task; the shell's line discipline does the signal delivery.
    @MainActor
    private func doInterrupt(sessionGuid: String) async throws -> OrchestratorResult {
        let resolved = try resolveSessionOrThrow(sessionGuid)
        if resolved.session.exited {
            throw OrchestratorError.targetNoLongerExists(sessionGuid: sessionGuid)
        }
        resolved.session.writeTaskNoBroadcast("\u{03}")
        return .ack
    }

    // Append a clipping to the workgroup's leader (or to the
    // standalone session for synthetic workgroups). PTYSession.clippings
    // delegates through peerPort, so writes against the leader fan
    // out automatically to whatever the workgroup considers its
    // clippings store. Routes through PTYSession.addClipping so the
    // append + clippingsViewIndex snap-back live in one place; that
    // also encapsulates the read-modify-write so callers don't have
    // to think about whether another @MainActor body could slip in
    // between the read and the write.
    @MainActor
    private func doAddWorkgroupClipping(_ args: AddClippingArgs) async throws -> OrchestratorResult {
        let trimmedType = args.type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedType.isEmpty else {
            throw OrchestratorError.malformedArgs(reason:
                "type must be a non-empty short tag describing the clipping kind.")
        }
        // 80 chars matches the schema's \u{201C}short tag\u{201D} description.
        // The ClippingsView cell renders the type as a chip; very long
        // values blow out the layout and don't add information that
        // wouldn't fit in the title.
        guard trimmedType.count <= 80 else {
            throw OrchestratorError.malformedArgs(reason:
                "type must be 80 characters or fewer (got \(trimmedType.count)).")
        }
        let session: PTYSession?
        let syntheticPrefix = WorkgroupIntrospection.syntheticWorkgroupIDPrefix
        if args.workgroupID.hasPrefix(syntheticPrefix) {
            let guid = String(args.workgroupID.dropFirst(syntheticPrefix.count))
            session = sessionByGUID(guid)
        } else {
            let instance = iTermWorkgroupController.instance.allInstances
                .first { $0.instanceUniqueIdentifier == args.workgroupID }
            session = instance?.mainSession
        }
        guard let session else {
            throw OrchestratorError.unknownWorkgroup(args.workgroupID)
        }
        if session.exited {
            throw OrchestratorError.targetNoLongerExists(sessionGuid: session.guid)
        }
        session.addClipping(type: trimmedType,
                            title: args.title,
                            detail: args.detail)
        return .ack
    }

    // Spawn a new session via iTermSessionLauncher, honoring the
    // requested window placement. Approval is already enforced by the
    // .spawn gate (gateSpawn) before we get here, whether it was granted
    // automatically (no command, or a command the safety check cleared)
    // or via a user prompt; this method is strictly the "do it" half.
    // Returns the new session's session_guid so the agent can address it
    // immediately with the other tools.
    @MainActor
    private func doStartSession(_ args: StartSessionArgs) async throws -> OrchestratorResult {
        // Profile is a C #define for NSDictionary, so the bridged
        // ProfileModel methods return [AnyHashable: Any] in Swift,
        // which is what iTermSessionLauncher.launchBookmark also
        // accepts.
        let baseProfile: [AnyHashable: Any]
        if let name = args.profile, !name.isEmpty {
            guard let p = ProfileModel.sharedInstance().bookmark(withName: name) else {
                throw OrchestratorError.malformedArgs(reason:
                    "No profile named \u{201C}\(name)\u{201D}.")
            }
            baseProfile = p
        } else {
            guard let p = ProfileModel.sharedInstance().defaultProfile() else {
                throw OrchestratorError.unsupported(reason: "No default profile is configured.")
            }
            baseProfile = p
        }

        // Build the launch-time bookmark by overlaying the user-supplied
        // cwd and (when a command is supplied) the login-shell wrap on
        // the base profile.
        //
        // Login-shell wrap: when args.command is set, the launch path
        // bypasses the profile's own command and runs the agent-supplied
        // string instead. Without KEY_RUN_COMMAND_IN_LOGIN_SHELL, iTerm2
        // forks the command directly with the .app bundle's inherited
        // PATH, which from Finder/launchd typically omits Homebrew,
        // ~/.local/bin, ~/.npm-global/bin, etc. The user's interactive
        // tools (`claude`, `pnpm`, `uv`, anything installed by npm/pip/
        // brew into a user-local prefix) aren't found. The shell exits
        // immediately, the only session in the new window terminates,
        // the window auto-closes, and the LLM is left with a workgroup_id
        // pointing at nothing. Setting the key tells the existing
        // bookmarkCommandSwiftyString path to wrap the command in
        // /usr/bin/login + ShellLauncher so dotfiles run and the user's
        // interactive PATH is in effect.
        var mutable = baseProfile
        if let cwd = args.cwd, !cwd.isEmpty {
            mutable[KEY_CUSTOM_DIRECTORY] = kProfilePreferenceInitialDirectoryCustomValue
            mutable[KEY_WORKING_DIRECTORY] = cwd
        }
        if let cmd = args.command, !cmd.isEmpty {
            mutable[KEY_RUN_COMMAND_IN_LOGIN_SHELL] = true
        }
        let bookmark: [AnyHashable: Any] = mutable

        let style: iTermOpenStyle
        switch args.window ?? .tab {
        case .new: style = .window
        case .tab: style = .tab
        case .current: style = .verticalSplit
        }

        // For the split case (window=current), launchBookmark needs the
        // window controller it should split *into*. With inTerminal:nil
        // the launcher fabricates a fresh, zero-tab PseudoTerminal; the
        // split path inside makeSessionByDefaultWithProfile is gated by
        // `numberOfTabs > 0`, so that gate fails and the launcher
        // silently falls through to a new-window/new-tab path. From the
        // user's POV the requested split silently became a new window,
        // which contradicts both this tool's description and the
        // approval prompt the user just clicked through. Resolve the
        // target window here so the split actually happens, and error
        // out cleanly if there's nothing to split.
        //
        // Window placement for the new-tab case is left to the
        // launcher's normal "current tabbing target" logic by passing
        // nil (it'll pick the user's currently-focused terminal or
        // create a new one).
        let targetTerminal: PseudoTerminal?
        switch args.window ?? .tab {
        case .current:
            let controller = iTermController.sharedInstance()
            targetTerminal = controller?.keyTerminalWindow() ?? controller?.currentTerminal
            guard let t = targetTerminal, t.numberOfTabs() > 0 else {
                throw OrchestratorError.unsupported(reason:
                    "window=\u{201C}current\u{201D} splits the currently-focused terminal, "
                    + "but no terminal window is open. Use window=\u{201C}new\u{201D} or "
                    + "window=\u{201C}tab\u{201D} instead.")
            }
        case .new, .tab:
            targetTerminal = nil
        }

        // 30s timeout safety net. launchBookmark has multiple code
        // paths (modal alert cancellation, profile validation failure,
        // app teardown mid-launch) where its completion is not invoked.
        // Without this, an LLM start_session call that hits any of
        // those paths parks the turn forever with no recovery.
        let spawned: PTYSession? = await withResolvedOnce(timeoutSeconds: 30) { resume in
            iTermSessionLauncher.launchBookmark(
                bookmark,
                in: targetTerminal,
                style: style,
                withURL: nil,
                hotkeyWindowType: .none,
                makeKey: true,
                canActivate: true,
                respectTabbingMode: false,
                index: nil,
                command: args.command,
                makeSession: nil,
                didMakeSession: nil,
                completion: { session, ok in
                    resume(ok ? session : nil)
                })
        }

        guard let session = spawned else {
            throw OrchestratorError.unsupported(reason:
                "iTerm2 could not open a new session. The launch failed before the window was shown.")
        }
        // Synchronous post-launch sanity. launchBookmark's `ok=true`
        // means the fork/exec succeeded (a shell was started), not that
        // the program is still alive or that the window made it to the
        // screen. If the shell exited synchronously within the launch
        // (a missing custom command, a startup-script abort) and the
        // user's profile auto-closes the window when the last session
        // ends, the controller has already torn the window down by the
        // time we get here. Returning a session_guid for a vanished
        // session strands the agent in a polling loop.
        //
        // No sleep: if the program needs grace time to fail, the agent
        // will surface that itself via get_screen_contents on the next
        // turn. This check only catches the same-runloop-turn collapse.
        let reachable = iTermController.sharedInstance()?.anySession(withGUID: session.guid) != nil
        if session.exited || !reachable {
            throw OrchestratorError.unsupported(reason:
                "The new session was created but is no longer reachable. "
                + "The command likely exited immediately (e.g. binary not on PATH "
                + "or a non-zero startup script) and the window auto-closed.")
        }
        // Record who conjured this session so other chats seeing it in
        // their <workgroups> snapshot (directly, or chained through a
        // workgroup provenance like "a trigger in session X entered
        // this workgroup") can tell it belongs to another agent's work
        // rather than something the user set up for them.
        await MainActor.run {
            // Re-check liveness: the hop here is a suspension point, so
            // the session can terminate between the reachability check
            // above and this block. Its terminate notification has
            // already fired by then (removing nothing), and an entry
            // set now would never be cleaned up.
            guard iTermController.sharedInstance()?.anySession(withGUID: session.guid) != nil,
                  !session.exited else {
                return
            }
            let title = ChatListModel.instance?.chat(id: chatID)?.title
            let chatDescription: String
            if let title, !title.isEmpty {
                chatDescription = "chat \u{201C}\(title)\u{201D} (\(chatID))"
            } else {
                chatDescription = "chat \(chatID)"
            }
            SessionProvenanceRegistry.instance.set(
                "Created by the agent in \(chatDescription).",
                forSessionGUID: session.guid)
        }
        return .startedSession(sessionGuid: session.guid)
    }

    // Bundles the Code Review entry sequence into one call so the
    // agent doesn't have to choreograph send_text → register_watch:
    //   1. Resolve the target. Must be a role whose session has the
    //      Code Review prompt overlay up (else the workflow doesn't
    //      apply — return an error that tells the agent why).
    //   2. Pick the prompt text from (in order):
    //        - args.promptName (look up in CodeReviewPromptStore)
    //        - args.customPrompt (use as literal)
    //        - default (CodeReviewPromptStore.defaultPromptText)
    //   3. Populate the overlay, fire onStart — the program launches.
    //   4. Auto-register a watcher for target → .idle. The agent
    //      receives a status_update when the review completes.
    @MainActor
    private func doStartCodeReview(_ args: StartCodeReviewArgs) async throws -> OrchestratorResult {
        let resolved = try resolveSessionOrThrow(args.sessionGuid)
        if resolved.session.exited {
            throw OrchestratorError.targetNoLongerExists(sessionGuid: args.sessionGuid)
        }
        // Three accepted launch states for the Code Review role:
        //   1. Pre-launch overlay is up — populate the overlay's text and
        //      fire its Start handler (this is what spawns the Claude Code
        //      process).
        //   2. No overlay, but the Code Review role's Claude Code TUI is
        //      already idle at its chat prompt — type the review prompt in
        //      and let it run as a new review on the existing session.
        //   3. Anything else (wrong role, or the role's program is busy or
        //      in an unknown state) — error.
        //
        // The role-id check guards against driving a non-review role: this
        // tool is for Code Review specifically, not a generic "send a long
        // prompt and watch for idle" shortcut.
        let overlay = resolved.session.view?.codeReviewPromptOverlay
        let isReviewRole = (resolved.roleID == ClaudeCodeWorkgroupTemplate.ID.review)
        let sessionState = WorkgroupIntrospection.state(for: resolved.session)
        if overlay == nil {
            guard isReviewRole && sessionState == .idle else {
                let reason: String
                if !isReviewRole {
                    reason = "Target \(resolved.roleName) in \(resolved.workgroupName) is not the Code Review role. start_code_review only targets the Code Review role; use send_text if you want to type text into another role."
                } else {
                    reason = "Target \(resolved.roleName) in \(resolved.workgroupName) is busy (status: \(sessionState.rawValue)). Wait until it returns to idle before starting a review."
                }
                throw OrchestratorError.unsupported(reason: reason)
            }
        }

        let promptText: String
        let promptLabel: String
        let store = CodeReviewPromptStore.shared
        let hasName = !(args.promptName ?? "").isEmpty
        let hasCustom = !(args.customPrompt ?? "").isEmpty
        if hasName && hasCustom {
            throw OrchestratorError.malformedArgs(reason:
                "prompt_name and custom_prompt are mutually exclusive; supply at most one.")
        }
        if hasName, let name = args.promptName {
            guard let match = store.prompts.first(where: { $0.name == name }) else {
                let available = store.prompts.map { $0.name }.joined(separator: ", ")
                throw OrchestratorError.malformedArgs(reason:
                    "No saved Code Review prompt named \u{201C}\(name)\u{201D}. "
                    + "Available: \(available.isEmpty ? "(none)" : available).")
            }
            promptText = match.text
            promptLabel = "saved prompt \u{201C}\(match.name)\u{201D}"
        } else if hasCustom, let custom = args.customPrompt {
            promptText = custom
            promptLabel = "custom prompt"
        } else {
            promptText = store.defaultPromptText
            promptLabel = "default prompt"
        }

        // Seed sessionStateHistory BEFORE kicking off the launch. The
        // transient clearTabStatus call that PTYSession fires when the
        // wrapping login shell hits its prompt during Claude Code launch
        // computes as .idle (empty-tabStatus fallback in
        // state(forTabStatus:)); if that notification arrives before we
        // seeded history, the handler would see a nil previous state,
        // treat the event as a transition, and fire the .idle watcher
        // before the review has actually started. Using seedState
        // normalizes .unknown (nil tabStatus, e.g. a session whose program
        // hasn't launched yet) to .idle so the first tabStatus event
        // doesn't register as a spurious .unknown → .idle transition.
        let guid = resolved.session.guid
        sessionStateHistory[guid] = Self.seedState(for: resolved.session)

        if let overlay {
            overlay.text = promptText
            overlay.onStart?(promptText)
        } else {
            // Idle Claude Code TUI fallback. typeIntoPTY handles bracketed
            // paste and the deferred-Enter dance so multi-line prompts (the
            // default review prompt is multi-line) submit reliably.
            await Self.typeIntoPTY(session: resolved.session,
                                   text: promptText,
                                   appendNewline: true)
        }

        // Auto-register the completion watcher unless one already
        // exists for this (session, .idle). Mirrors doRegisterWatch's
        // de-dup behavior so calling start_code_review twice in a row
        // doesn't leak duplicate watchers.
        let watcher: WorkgroupWatcher
        if let existing = watchers.first(where: {
            $0.sessionGUID == guid && $0.targetState == .idle
        }) {
            watcher = existing
        } else {
            watcher = WorkgroupWatcher(
                watcherID: UUID().uuidString,
                sessionGUID: guid,
                workgroupID: resolved.workgroupID,
                workgroupName: resolved.workgroupName,
                roleID: resolved.roleID,
                roleName: resolved.roleName,
                targetState: .idle,
                registeredAt: Date())
            watchers.append(watcher)
            persistWatchers()
        }
        // Code Review runs on a status-reporting Claude Code session, so this
        // is a tab-status watcher: arm the screen-observation backstop (no-op
        // if it already exists from a prior start_code_review on this role).
        armScreenEscalation(for: watcher)

        RLog("[Orchestrator \(chatID)] Code Review started for \(resolved.roleName) "
             + "in \(resolved.workgroupName) using \(promptLabel); watcher \(watcher.watcherID)")

        return .watcherRegistered(Self.description(of: watcher))
    }

    // MARK: - Helpers

    private func encode(_ result: OrchestratorResult) throws -> Data {
        return try JSONEncoder().encode(result)
    }

    // Last-ditch encoding for error paths. If even the error itself
    // can't be encoded, fall back to a hand-built JSON blob so the
    // agent always has *something* to ship as a tool_result.
    private func safeEncode(_ result: OrchestratorResult) -> Data {
        if let data = try? JSONEncoder().encode(result) {
            return data
        }
        let fallback = "{\"error\":{\"code\":\"encode_failed\",\"message\":\"could not encode result\"}}"
        return Data(fallback.utf8)
    }

    // withCheckedContinuation wrapper with a wall-clock timeout. The
    // resume closure can be called at most once: subsequent invocations
    // (including the timeout firing after a real completion) are no-ops.
    // Use for callback-style APIs whose completion isn't guaranteed to
    // fire on every code path (e.g. iTermSessionLauncher.launchBookmark).
    private func withResolvedOnce<T>(
        timeoutSeconds: TimeInterval,
        body: @escaping (@escaping (T?) -> Void) -> Void
    ) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let resolved = ResolveOnce<T>()
            let resume: (T?) -> Void = { value in
                if resolved.tryResolve() {
                    continuation.resume(returning: value)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) {
                if resolved.tryResolve() {
                    RLog("withResolvedOnce timed out after \(timeoutSeconds)s")
                    continuation.resume(returning: nil)
                }
            }
            body(resume)
        }
    }
}

// Helper for withResolvedOnce. A reference type lets the resume closure
// and the timeout closure share atomic "has this been resolved" state.
private final class ResolveOnce<T> {
    private var done = false
    private let lock = NSLock()
    func tryResolve() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
