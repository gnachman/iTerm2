//
//  OrchestratorDispatcher.swift
//  iTerm2SharedARC
//

import Foundation

// Bridges the LLM tool-use loop to the orchestrator's actual
// behavior. One instance per chat; owned by CockpitChatAgent and
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

    // Observer on iTermSessionTabStatusDidChange — the source of
    // truth for "a session's state changed". When a notification
    // fires we walk watchers, fire any matches, and remove them
    // from the list.
    private var tabStatusObserver: NSObjectProtocol?
    private var sessionWillTerminateObserver: NSObjectProtocol?

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

    deinit {
        // Beta/Nightly tripwire: deinit on a @MainActor class is not
        // itself main-actor-isolated. If a future code path captures
        // the dispatcher in a non-main Task and that Task holds the
        // last strong ref, this body runs off-main. The assertion
        // surfaces the violation on testing channels so we can fix
        // the call site. Capturing into locals first because
        // it_assert's autoclosure can't close over @MainActor state
        // directly.
        let isBetaChannel = Bundle.it_isEarlyAdopter() || Bundle.it_isNightlyBuild()
        let promptsRemaining = pendingPermissionPrompts.count
        let subscriptionRemaining = brokerSubscription != nil
        if isBetaChannel {
            it_assert(promptsRemaining == 0,
                      "OrchestratorDispatcher.deinit: pending prompts not drained before deinit")
            it_assert(!subscriptionRemaining,
                      "OrchestratorDispatcher.deinit: brokerSubscription not torn down before deinit")
        }
        // Belt-and-suspenders: do the actual cleanup on main, even if
        // we're already there. The mutations touch @MainActor state
        // (ChatBroker.subs via Subscription.unsubscribe) and resuming
        // continuations is thread-safe on its own but downstream
        // awaiters expect to wake on main. Capture all references
        // explicitly into the dispatch closure so they outlive self
        // and run safely after the deinit returns. If the work turns
        // out to be no-op by the time it runs (observers already gone,
        // broker already cleaned up its subs), the cost is one
        // runloop hop.
        let sub = brokerSubscription
        let tabObs = tabStatusObserver
        let termObs = sessionWillTerminateObserver
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
        guard case let .delivery(message, _) = update,
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
    // very roles the cockpit cares about and every watcher fire was
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
        guard let status = notification.object as? iTermSessionTabStatus else {
            return
        }
        let newState = WorkgroupIntrospection.state(forTabStatus: status)
        let guid = status.sessionID
        let previousState = sessionStateHistory[guid]
        sessionStateHistory[guid] = newState
        guard previousState != newState else { return }
        let matches = watchers.filter {
            $0.sessionGUID == guid && $0.targetState == newState
        }
        guard !matches.isEmpty else { return }
        let matchedIDs = Set(matches.map { $0.watcherID })
        watchers.removeAll { matchedIDs.contains($0.watcherID) }
        persistWatchers()
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
            publishStatusUpdate(
                watcher: watcher,
                reason: .watcherDropped,
                stateReached: "",
                detail: "Watch dropped: the session for \(watcher.roleName) in \(watcher.workgroupName) terminated before the target state was reached.")
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
        let payload = StatusUpdate(
            watcherID: watcher.watcherID,
            workgroupID: watcher.workgroupID,
            workgroupName: watcher.workgroupName,
            roleID: watcher.roleID,
            roleName: watcher.roleName,
            reason: reason,
            stateReached: stateReached,
            timestamp: Date(),
            detail: detail)
        do {
            try broker?.publishMessageFromUser(
                chatID: chatID,
                content: .watcherEvent(payload))
        } catch {
            DLog("Cockpit dispatcher: failed to publish status_update: \(error)")
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
            DLog("Cockpit dispatcher: failed to persist claimed workgroups: \(error)")
        }
    }

    private func persistWatchers() {
        do {
            try broker?.listModel
                .setWatchers(watchers, forChatID: chatID)
        } catch {
            DLog("Cockpit dispatcher: failed to persist watchers: \(error)")
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

        do {
            let response: String = try await withCheckedThrowingContinuation { continuation in
                do {
                    try session.execute(remoteCommand) { response, _ in
                        // session.execute's completion can fire off-main
                        // (browser commands resolve on WebKit queues, some
                        // command-history paths dispatch async).
                        continuation.resume(returning: response)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            return Data(response.utf8)
        } catch {
            return Data("Error executing command: \(error.localizedDescription)".utf8)
        }
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
            struct A: Decodable { let target: OrchestratorTarget }
            return .getState(target: try decoder.decode(A.self, from: jsonArgs).target)
        case .getScreenContents:
            return .getScreenContents(try decoder.decode(GetScreenContentsArgs.self, from: jsonArgs))
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
            struct A: Decodable { let target: OrchestratorTarget }
            return .interrupt(target: try decoder.decode(A.self, from: jsonArgs).target)
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
        case .notifyUser:
            return .notifyUser(try decoder.decode(NotifyUserArgs.self, from: jsonArgs))
        }
    }

    // MARK: - Gating

    @MainActor
    private func applyGating(for command: OrchestratorCommand) async throws {
        switch command.category {
        case .write:
            guard let workgroupID = command.requiredWorkgroupClaim else { return }
            if !(await ensureClaim(workgroupID: workgroupID)) {
                throw OrchestratorError.permissionDenied
            }
        case .spawn:
            let approved = try await promptForSpawn(command: command)
            if !approved {
                throw OrchestratorError.permissionDenied
            }
        case .readOnly, .watcher, .userFacing:
            return
        }
    }

    // Ensure this chat has user approval to perform write actions on the
    // session identified by `sessionGuid`. The session is wrapped in a
    // synthetic single-session workgroup ("session:<guid>"), so its
    // approval state lives in the same `claimedScopes` set the
    // workgroup-shaped tools use. session_* tools call this before
    // dispatching to PTYSession.execute so a one-time user prompt
    // gates the whole family for the rest of the chat. Returns true
    // when the chat is already claimed for this session or the user
    // just approved; false if the user declines (the caller surfaces
    // an error string to the LLM).
    @MainActor
    public func ensureSessionClaim(sessionGuid: String) async -> Bool {
        let workgroupID = WorkgroupIntrospection.syntheticWorkgroupIDPrefix + sessionGuid
        return await ensureClaim(workgroupID: workgroupID)
    }

    // Shared claim check + prompt + persist. Returns true when the
    // workgroup is already claimed or the user just approved.
    @MainActor
    private func ensureClaim(workgroupID: String) async -> Bool {
        if claimedScopes.contains(workgroupID) {
            return true
        }
        let approved = await promptForClaim(workgroupID: workgroupID)
        if approved {
            claimedScopes.insert(workgroupID)
            persistClaimedScopes()
        }
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
                + "this and future write actions on this session until you "
                + "explicitly approve."
        } else {
            summary = "The agent is asking to send keystrokes, interrupt running "
                + "commands, and post clippings to this workgroup. Approval is sticky "
                + "for the rest of this chat. Deny to refuse this and future write "
                + "actions on this workgroup until you explicitly approve."
        }
        return await awaitPermission(workgroupID: workgroupID,
                                      workgroupName: workgroupName,
                                      summary: summary)
    }

    // The spawn prompt uses a synthetic workgroupID ("new-session")
    // since there's no real workgroup yet. The cell renderer doesn't
    // depend on the ID resolving to anything live — only on the name
    // and summary being human-readable.
    private func promptForSpawn(command: OrchestratorCommand) async throws -> Bool {
        let placement: String
        let cmd: String?
        if case .startSession(let args) = command {
            switch args.window ?? .tab {
            case .new: placement = "a new window"
            case .tab: placement = "a new tab in the current window"
            case .current: placement = "a vertical split of the current pane"
            }
            cmd = (args.command?.isEmpty == false) ? args.command : nil
        } else {
            placement = "a new session"
            cmd = nil
        }
        let detail: String
        if let cmd {
            detail = "The agent is asking to open \(placement) and run \u{201C}\(cmd)\u{201D}."
        } else {
            detail = "The agent is asking to open \(placement)."
        }
        return await awaitPermission(workgroupID: "spawn",
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
                DLog("Cockpit dispatcher: failed to publish permission request: \(error)")
                if let cont = pendingPermissionPrompts.removeValue(forKey: requestID) {
                    cont.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Execute

    private func execute(_ command: OrchestratorCommand) async throws -> OrchestratorResult {
        switch command {
        case .listWorkgroups:
            return try await doListWorkgroups()
        case .getState(let target):
            return try await doGetState(target: target)
        case .getScreenContents(let args):
            return try await doGetScreenContents(args)
        case .listWorkgroupClippings(let workgroupID, let typeFilter):
            return try await doListWorkgroupClippings(
                workgroupID: workgroupID, typeFilter: typeFilter)
        case .sendText(let args):
            return try await doSendText(args)
        case .interrupt(let target):
            return try await doInterrupt(target: target)
        case .addWorkgroupClipping(let args):
            return try await doAddWorkgroupClipping(args)
        case .startSession(let args):
            return try await doStartSession(args)
        case .startCodeReview(let args):
            return try await doStartCodeReview(args)
        case .registerWatch(let args):
            return try await doRegisterWatch(args)
        case .unregisterWatch(let watcherID):
            return await doUnregisterWatch(watcherID: watcherID)
        case .listWatches:
            return await doListWatches()
        case .notifyUser(let args):
            return try await doNotifyUser(args)
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
    private func doGetState(target: OrchestratorTarget) async throws -> OrchestratorResult {
        guard let resolved = WorkgroupIntrospection.resolve(target: target) else {
            throw OrchestratorError.unknownRole(
                workgroupID: target.workgroupID,
                role: target.role,
                available: WorkgroupIntrospection.availableRoleNames(
                    forWorkgroupID: target.workgroupID))
        }
        return .sessionState(WorkgroupIntrospection.stateInfo(for: resolved))
    }

    @MainActor
    private func doGetScreenContents(_ args: GetScreenContentsArgs) async throws -> OrchestratorResult {
        guard let resolved = WorkgroupIntrospection.resolve(target: args.target) else {
            throw OrchestratorError.unknownRole(
                workgroupID: args.target.workgroupID,
                role: args.target.role,
                available: WorkgroupIntrospection.availableRoleNames(
                    forWorkgroupID: args.target.workgroupID))
        }
        let contents = WorkgroupIntrospection.screenContents(
            for: resolved, requestedLines: args.lines)
        return .screenContents(contents)
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

    // Registers an async state watcher. Returns immediately; the
    // chat receives a status_update when the watched state is
    // reached. De-duplicated on (sessionGUID, targetState): if a
    // watcher with the same target/state already exists, return
    // the existing watcher_id instead of creating a duplicate.
    //
    // If the target is already in the desired state at registration
    // time, fire immediately — the agent's caller-side expectation
    // is "I'll get a status_update when this is reached", and
    // already-reached counts.
    @MainActor
    private func doRegisterWatch(_ args: RegisterWatchArgs) async throws -> OrchestratorResult {
        // target_state must be a state we actually transition to. .unknown
        // is part of the enum so we can model "no tabStatus yet" internally
        // and surface it on get_state output, but watchers keyed to it
        // would never fire because state(forTabStatus:) never emits it as
        // a transition. The schema documents this; reject loudly so the
        // LLM gets a structured error.
        if args.targetState == .unknown {
            throw OrchestratorError.malformedArgs(reason:
                "target_state \u{201C}unknown\u{201D} is reported by get_state but is not a watchable "
                + "transition. Pick \u{201C}idle\u{201D}, \u{201C}working\u{201D}, or \u{201C}waiting\u{201D} instead.")
        }
        guard let resolved = WorkgroupIntrospection.resolve(target: args.target) else {
            throw OrchestratorError.unknownRole(
                workgroupID: args.target.workgroupID,
                role: args.target.role,
                available: WorkgroupIntrospection.availableRoleNames(
                    forWorkgroupID: args.target.workgroupID))
        }
        let session = resolved.session
        let guid = session.guid
        if let existing = watchers.first(where: {
            $0.sessionGUID == guid && $0.targetState == args.targetState
        }) {
            return .watcherRegistered(Self.description(of: existing))
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
                registeredAt: Date())
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
            registeredAt: Date())
        watchers.append(watcher)
        persistWatchers()
        return .watcherRegistered(Self.description(of: watcher))
    }

    @MainActor
    private func doUnregisterWatch(watcherID: String) -> OrchestratorResult {
        let before = watchers.count
        watchers.removeAll { $0.watcherID == watcherID }
        if watchers.count != before {
            persistWatchers()
        }
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
        guard let resolved = WorkgroupIntrospection.resolve(target: args.target) else {
            throw OrchestratorError.unknownRole(
                workgroupID: args.target.workgroupID,
                role: args.target.role,
                available: WorkgroupIntrospection.availableRoleNames(
                    forWorkgroupID: args.target.workgroupID))
        }
        if resolved.session.exited {
            throw OrchestratorError.targetNoLongerExists(args.target)
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
        Self.typeIntoPTY(session: resolved.session,
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
    //    the TUI receives the whole thing as one paste event rather than per-
    //    character input. EXCEPTION: if the payload contains any control byte
    //    other than \n (e.g. ESC, Ctrl-C), the caller is sending keystrokes
    //    rather than prose. Paste-wrap would convert those control bytes into
    //    literal pasted data and neutralize them (the bug that left vim stuck
    //    in insert mode when the agent sent ESC :q LF and the ESC got pasted
    //    instead of switching mode). Skip the wrap and write raw in that case.
    //  - Ink (Claude Code's TUI) swallows the trailing \r when it rides in
    //    the SAME write as the body: with the paste body and Enter in a
    //    single kernel PTY event, Ink treats the \r as paste content
    //    rather than a discrete submit gesture. Splitting text and Enter
    //    into two separate writeTaskNoBroadcast calls produces two
    //    separate PTY events on the slave side, which is all Ink needs
    //    to treat the \r as the submit gesture. This also covers
    //    single-line text on Claude Code because empirically the trailing
    //    \r still gets swallowed when it rides in the same write as the
    //    body, even without BP wrappers.
    //  - On a plain shell (or any non-BP-mode terminal), neither concern
    //    applies, and the line-discipline echoes \r as Enter immediately;
    //    one write is fine and cheaper.

    @MainActor
    private static func typeIntoPTY(session: PTYSession,
                                    text: String,
                                    appendNewline: Bool) {
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
            let body: String
            if text.contains("\n") {
                let bpStart = "\u{1B}[200~"
                let bpEnd = "\u{1B}[201~"
                body = bpStart + text + bpEnd
            } else {
                // Single-line text on an Ink TUI doesn't need the BP
                // wrappers for atomicity, but we still split the Enter into
                // a second write so Ink sees it as a separate submit
                // gesture. Tested empirically against Claude Code idle in
                // its chat prompt: text + "\r" in one write types the text
                // but never submits.
                body = text
            }
            session.writeTaskNoBroadcast(body)
            if appendNewline {
                // Second write for the submit gesture. Two separate
                // writeTaskNoBroadcast calls produce two separate PTY
                // events on the slave side, which is all Ink needs to
                // treat the \r as the submit gesture rather than paste
                // content. No async hop, no sleep: a user pasting into
                // Claude Code and pressing Enter immediately submits
                // cleanly, and that's the same shape as two back-to-back
                // synchronous writes here.
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
    private func doInterrupt(target: OrchestratorTarget) async throws -> OrchestratorResult {
        guard let resolved = WorkgroupIntrospection.resolve(target: target) else {
            throw OrchestratorError.unknownRole(
                workgroupID: target.workgroupID,
                role: target.role,
                available: WorkgroupIntrospection.availableRoleNames(
                    forWorkgroupID: target.workgroupID))
        }
        if resolved.session.exited {
            throw OrchestratorError.targetNoLongerExists(target)
        }
        resolved.session.writeTaskNoBroadcast("\u{03}")
        return .ack
    }

    // Append a clipping to the workgroup's leader (or to the
    // standalone session for synthetic workgroups). PTYSession.clippings
    // delegates through peerPort, so writes against the leader fan
    // out automatically to whatever the workgroup considers its
    // clippings store.
    @MainActor
    private func doAddWorkgroupClipping(_ args: AddClippingArgs) async throws -> OrchestratorResult {
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
            throw OrchestratorError.targetNoLongerExists(
                OrchestratorTarget(workgroupID: args.workgroupID, role: ""))
        }
        var current = session.clippings
        current.append(PTYSessionClipping(type: args.type,
                                           title: args.title,
                                           detail: args.detail))
        session.clippings = current
        return .ack
    }

    // Spawn a new session via iTermSessionLauncher, honoring the
    // requested window placement. Approval is already enforced by the
    // .spawn gate (promptForSpawn) before we get here; this method is
    // strictly the "do it" half. Returns the synthetic single-session
    // workgroup_id for the new session so the agent can address it
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

        // Apply optional cwd by mutating a copy of the profile dict.
        // The session launcher reads KEY_CUSTOM_DIRECTORY = "Yes" plus
        // KEY_WORKING_DIRECTORY = <path> to override the profile's
        // configured starting directory for just this launch.
        let bookmark: [AnyHashable: Any]
        if let cwd = args.cwd, !cwd.isEmpty {
            var mutable = baseProfile
            mutable[KEY_CUSTOM_DIRECTORY] = kProfilePreferenceInitialDirectoryCustomValue
            mutable[KEY_WORKING_DIRECTORY] = cwd
            bookmark = mutable
        } else {
            bookmark = baseProfile
        }

        let style: iTermOpenStyle
        switch args.window ?? .tab {
        case .new: style = .window
        case .tab: style = .tab
        case .current: style = .verticalSplit
        }

        // 30s timeout safety net. launchBookmark has multiple code
        // paths (modal alert cancellation, profile validation failure,
        // app teardown mid-launch) where its completion is not invoked.
        // Without this, an LLM start_session call that hits any of
        // those paths parks the turn forever with no recovery.
        let spawned: PTYSession? = await withResolvedOnce(timeoutSeconds: 30) { resume in
            iTermSessionLauncher.launchBookmark(
                bookmark,
                in: nil,
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
            throw OrchestratorError.unsupported(reason: "iTerm2 could not spawn the requested session.")
        }
        let workgroupID = WorkgroupIntrospection.syntheticWorkgroupIDPrefix + session.guid
        return .startedSession(workgroupID: workgroupID)
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
        guard let resolved = WorkgroupIntrospection.resolve(target: args.target) else {
            throw OrchestratorError.unknownRole(
                workgroupID: args.target.workgroupID,
                role: args.target.role,
                available: WorkgroupIntrospection.availableRoleNames(
                    forWorkgroupID: args.target.workgroupID))
        }
        if resolved.session.exited {
            throw OrchestratorError.targetNoLongerExists(args.target)
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
            Self.typeIntoPTY(session: resolved.session,
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

        DLog("[Orchestrator \(chatID)] Code Review started for \(resolved.roleName) "
             + "in \(resolved.workgroupName) using \(promptLabel); watcher \(watcher.watcherID)")

        return .watcherRegistered(Self.description(of: watcher))
    }

    private func doNotifyUser(_ args: NotifyUserArgs) async throws -> OrchestratorResult {
        throw OrchestratorError.notImplemented("notify_user")
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
                    DLog("withResolvedOnce timed out after \(timeoutSeconds)s")
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
