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

@MainActor
final class CompanionAgentActivityNotifier {
    enum Trigger: Equatable {
        case turnComplete        // respects the per-chat debounce
        case userActionRequired  // permission / session pick: bypasses the debounce
    }

    private let debounceInterval: TimeInterval
    private let clock: () -> Date
    private let gate: () -> Bool
    private let resolve: (_ streamID: UUID, _ chatID: String) -> Message?
    private let send: (_ chatID: String) -> Void
    private var lastFire: [String: Date] = [:]
    private var subscription: ChatBroker.Subscription?

    private static var shared: CompanionAgentActivityNotifier?

    init(debounceInterval: TimeInterval = 30,
         clock: @escaping () -> Date = { Date() },
         gate: @escaping () -> Bool,
         resolve: @escaping (UUID, String) -> Message?,
         send: @escaping (String) -> Void) {
        self.debounceInterval = debounceInterval
        self.clock = clock
        self.gate = gate
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
        case .remoteCommandRequest, .selectSessionRequest:
            // The agent is blocked waiting on the user; always worth a nudge,
            // turn boundary or not.
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

    /// Apply gating + per-chat debounce and fire send(chatID) when warranted.
    func handle(message: Message, chatID: String, partial: Bool) {
        guard let trigger = trigger(for: message, partial: partial, chatID: chatID) else {
            return
        }
        // Gate last: don't even consult the debounce when we wouldn't send.
        guard gate() else { return }
        let now = clock()
        if trigger == .turnComplete,
           let last = lastFire[chatID],
           now.timeIntervalSince(last) < debounceInterval {
            return
        }
        // userActionRequired bypasses the debounce but still updates it, so an
        // immediately-following turn-complete in the same chat doesn't double-fire.
        lastFire[chatID] = now
        send(chatID)
    }

    private static func hasDisplayableText(_ message: Message) -> Bool {
        guard let snippet = message.content.snippetText(maxLength: 8) else {
            return false
        }
        return !snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Production wiring

    /// Install the global notifier at launch (idempotent). Subscribes to all
    /// chats and, on a qualifying event, sends a content-free push (section 5).
    static func start() {
        guard shared == nil else { return }
        let notifier = CompanionAgentActivityNotifier(
            gate: {
                CompanionPushRegistry.devicePaired
                    && !CompanionPushRegistry.phoneIsConnected
                    && CompanionPushRegistry.canNotify
            },
            resolve: { streamID, chatID in
                guard let model = ChatListModel.instance,
                      let index = model.index(ofMessageID: streamID, inChat: chatID),
                      let messages = model.messages(forChat: chatID, createIfNeeded: false) else {
                    return nil
                }
                return messages[index]
            },
            send: { chatID in
                // TODO(section 5): send the content-free mutable push with
                // apns-collapse-id = CompanionCollapseToken.make(roomSecret,
                // chatID) via CompanionPushSender's /push/mutable path. Until
                // that lands, log the decision so the wiring is observable.
                DLog("CompanionAgentActivityNotifier: would push away phone for chat \(chatID)")
            })
        shared = notifier
        notifier.subscription = ChatClient.instance?.subscribe(chatID: nil,
                                                               registrationProvider: nil) { [weak notifier] update in
            guard case let .delivery(message, chatID, partial) = update else { return }
            notifier?.handle(message: message, chatID: chatID, partial: partial)
        }
    }
}
