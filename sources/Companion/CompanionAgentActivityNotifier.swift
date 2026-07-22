//
//  CompanionAgentActivityNotifier.swift
//  iTerm2
//
//  Mac-side: watches the chat broker and decides when to nudge an away phone
//  with a content-free push (the NSE fetches the real content over Noise). It
//  fires on:
//    - a completed agent turn (streamed: a .commit(streamID) that resolves to a
//      visible, non-empty message; non-streamed: a visible, partial:false,
//      .agent reply), debounced per chat; and
//    - a permission / session-selection request, which blocks the agent waiting
//      on the user and so BYPASSES the debounce (the user must be told).
//
//  See docs/push.txt section 4. The actual push send is section 5; this notifier
//  takes injected dependencies (clock, gate, .commit resolver, send) so its
//  decision logic is unit-testable with no broker, network, or push stack.
//

import Foundation
import CompanionProtocol

@MainActor
final class CompanionAgentActivityNotifier {
    enum Trigger: Equatable {
        case turnComplete        // respects the per-chat debounce
        case userActionRequired  // permission / session pick: bypasses the debounce
    }

    private let gate: () -> Bool
    private let muted: (_ chatID: String) -> Bool
    private let resolve: (_ streamID: UUID, _ chatID: String) -> Message?
    private let send: (_ trigger: Trigger, _ chatID: String) -> Void
    private var subscription: ChatBroker.Subscription?

    private static var shared: CompanionAgentActivityNotifier?

    init(gate: @escaping () -> Bool,
         muted: @escaping (String) -> Bool = { _ in false },
         resolve: @escaping (UUID, String) -> Message?,
         send: @escaping (Trigger, String) -> Void) {
        self.gate = gate
        self.muted = muted
        self.resolve = resolve
        self.send = send
    }

    // MARK: Decision (unit-tested)

    /// Classify a broker delivery into the trigger it should fire, or nil to
    /// ignore it (mid-stream deltas, the streamed turn's opening message, hidden
    /// bookkeeping, user messages, empty turns).
    func trigger(for message: Message, partial: Bool, chatID: String) -> Trigger? {
        switch message.content {
        case .commit(let streamID):
            // Streamed turn end. The .commit is itself hidden/non-persisted;
            // resolve the visible streamed message it finalizes and require real
            // content (a tool-only / empty turn should not notify).
            guard let target = resolve(streamID, chatID),
                  !target.hiddenFromClient,
                  Self.hasDisplayableText(target) else {
                return nil
            }
            return .turnComplete
        case .remoteCommandRequest(let payload, safe: _):
            // A .classic request has Allow/Deny and genuinely BLOCKS on the user, so
            // it is worth a nudge. A .external request is an orchestration tool call,
            // auto-executed with no per-call user decision (its permission gate is the
            // workgroup claim, not the command) - the agent is not blocked, so ignore
            // it. Firing for .external was the source of the push flood + the silent
            // placeholders: those requests never render, so their wakeups drained empty.
            switch payload {
            case .classic: return .userActionRequired
            case .external: return nil
            }
        case .selectSessionRequest:
            // The agent is blocked waiting for the user to pick a session.
            return .userActionRequired
        default:
            // Non-streamed final reply: committed (partial:false), visible,
            // agent-authored, non-empty. partial:true excludes a streamed turn's
            // opening message, which ends with its own .commit above.
            guard !partial,
                  message.author == .agent,
                  !message.hiddenFromClient,
                  Self.hasDisplayableText(message) else {
                return nil
            }
            return .turnComplete
        }
    }

    // MARK: Handle (unit-tested)

    /// Apply gating and fire send(trigger, chatID) when warranted. Coalescing /
    /// rate-limiting is the global coordinator's job, so there is no per-chat debounce
    /// here (the old one was stamped by the userActionRequired stream and starved real
    /// replies).
    func handle(message: Message, chatID: String, partial: Bool) {
        // Flow logging only; never the message content.
        guard let trigger = trigger(for: message, partial: partial, chatID: chatID) else {
            // Make the noisy "why didn't this notify" case field-visible without a DB
            // query: an ignored orchestration tool call. Other ignorable deltas
            // (streaming, user messages, hidden bookkeeping) stay at DLog.
            if case .remoteCommandRequest(.external, _) = message.content {
                RLog("CompanionAgentActivityNotifier: ignoring .external command in \(chatID) (orchestration, auto-executed; not a nudge)")
            } else {
                DLog("CompanionAgentActivityNotifier: no trigger for delivery in \(chatID) "
                     + "(partial=\(partial), author=\(message.author), kind=\(Self.kind(of: message.content)))")
            }
            return
        }
        guard gate() else {
            DLog("CompanionAgentActivityNotifier: \(trigger) in \(chatID) gated off (not paired, phone connected, or notifications off)")
            return
        }
        // A muted chat gets no push at all, not even a nudge. RLog (not DLog): rare and
        // exactly what a field log needs when muting misbehaves.
        guard !muted(chatID) else {
            RLog("CompanionAgentActivityNotifier: \(trigger) in \(chatID) suppressed (chat is muted)")
            return
        }
        RLog("CompanionAgentActivityNotifier: firing \(trigger) for \(chatID) (kind=\(Self.kind(of: message.content)))")
        send(trigger, chatID)
    }

    /// A coarse, content-free label for the delivery kind, for field logging.
    private static func kind(of content: Message.Content) -> String {
        switch content {
        case .remoteCommandRequest(.classic, _): return "remoteCommandRequest(.classic)"
        case .remoteCommandRequest(.external, _): return "remoteCommandRequest(.external)"
        case .selectSessionRequest: return "selectSessionRequest"
        case .markdown: return "markdown"
        case .multipart: return "multipart"
        case .commit: return "commit"
        default: return "other"
        }
    }

    /// Whether a message has real content worth a notification. Uses the SAME
    /// predicate as the preview builder (MessagesSinceResponder), so a turn that
    /// doesn't warrant a push also never gets fetched onto the lock screen. See
    /// Message.Content.hasDisplayableSubstance.
    private static func hasDisplayableText(_ message: Message) -> Bool {
        return message.content.hasDisplayableSubstance
    }

    // MARK: Production wiring

    /// Install the global notifier at launch (idempotent). Subscribes to all
    /// chats and, on a qualifying event, sends a content-free push (section 5).
    static func start() {
        guard shared == nil else { return }
        RLog("CompanionAgentActivityNotifier: starting; subscribing to all chats")
        let notifier = CompanionAgentActivityNotifier(
            gate: {
                // Suppress only for an INTERACTIVE connection (a foreground app
                // session) - NOT for the mac's own solicited NSE fetch, which also
                // holds a live bridge. Gating on the binary phoneIsConnected
                // dropped a legit push whenever an agent turn completed while an
                // NSE fetch happened to be connected.
                CompanionPushRegistry.devicePaired
                    && !CompanionPushRegistry.interactivePhoneConnected
                    && CompanionPushRegistry.canNotify
            },
            muted: { chatID in
                CompanionChatMuteRegistry.isMuted(chatID: chatID)
            },
            resolve: { streamID, chatID in
                guard let model = ChatListModel.instance,
                      let index = model.index(ofMessageID: streamID, inChat: chatID),
                      let messages = model.messages(forChat: chatID, createIfNeeded: false) else {
                    return nil
                }
                return messages[index]
            },
            send: { _, chatID in
                // Wakeup-capable phones (revision >= 2) route through the global
                // coordinator; legacy revision-1 phones keep the immediate per-chat
                // collapse push. Both a completed turn and a .classic permission /
                // session request are renderable content now, so both are content
                // activity - the coordinator pushes only if the responder would render
                // something above the phone's floor.
                if CompanionPushRegistry.supportsContentlessWakeup {
                    CompanionWakeupCoordinator.shared.noteContentActivity(chatID: chatID)
                } else {
                    CompanionPushSender.dispatchPush(chatID: chatID)
                }
            })
        shared = notifier
        notifier.subscription = ChatClient.instance?.subscribe(chatID: nil,
                                                               registrationProvider: nil) { [weak notifier] update in
            guard case let .delivery(message, chatID, partial) = update else { return }
            notifier?.handle(message: message, chatID: chatID, partial: partial)
        }
    }
}
