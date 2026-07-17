//
//  AppModel.swift
//  iTerm2 Companion
//
//  The app-wide coordinator: owns the navigation route, establishes the paired
//  connection (rendezvous then Noise XK handshake), and keeps the UI's
//  chat/session/message state in sync with host events. State is held in the
//  real model types (Chat, Message) shared with the Mac app.
//

import Foundation
import SwiftUI
import Observation
import Network
import os
import UIKit
import UserNotifications
import CryptoKit
import CompanionProtocol
import CompanionNoise
import CompanionTransport

private let logger = Logger(subsystem: "com.googlecode.iterm2.companion", category: "companion")

/// Logs to the unified log AND, in debug builds, to stdout so every step is
/// visible in Xcode's console without fiddling with metadata filters. Output
/// matches iTerm2's DLog shape: timestamp, file:line, function, message.
func companionLog(_ message: String,
                  file: StaticString = #fileID,
                  line: UInt = #line,
                  function: StaticString = #function) {
    let basename = "\(file)".split(separator: "/").last.map(String.init) ?? "\(file)"
    let formatted = String(format: "%0.6f %@:%u (%@): %@",
                           Date().timeIntervalSince1970,
                           basename,
                           UInt32(line),
                           "\(function)",
                           message)
    CompanionFileLog.shared.log(formatted)
    // print only in debug (Xcode console would otherwise show each line twice,
    // once from stdout and once from the unified log).
#if DEBUG
    print(formatted)
#else
    logger.notice("\(formatted, privacy: .public)")
#endif
}

/// Transport-layer messages arrive with their own call-site prefix (the
/// package embeds file:line); only the timestamp is added here.
func companionLogPreformatted(_ message: String) {
    let formatted = String(format: "%0.6f %@", Date().timeIntervalSince1970, message)
    CompanionFileLog.shared.log(formatted)
#if DEBUG
    print(formatted)
#else
    logger.notice("\(formatted, privacy: .public)")
#endif
}

/// Run an async step with a deadline so a wedged network call surfaces as an
/// error (with the step's name) instead of an eternal spinner.
private func withTimeout<T: Sendable>(_ seconds: TimeInterval,
                                      _ label: String,
                                      _ body: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TransportError.connectionFailed("\(label) timed out after \(Int(seconds)) seconds")
        }
        guard let result = try await group.next() else {
            throw TransportError.closed
        }
        group.cancelAll()
        return result
    }
}

// @Observable (not ObservableObject): views re-render only for properties
// they read. That precision matters for navigation: with ObservableObject,
// unrelated mutations (loading a conversation's history) re-rendered the view
// containing the NavigationStack mid-transition, which killed the push
// animation.

/// The geometry the live canvas needs to lay out its scrollable document: history
/// tiles fill [firstAbsLine, firstAbsLine + totalLines - rows); the live video is
/// the bottom `rows` lines.
struct CompanionLiveCanvasLayout: Equatable {
    var imageSize: CGSize
    var columns: Int
    var rows: Int
    var firstAbsLine: Int64
    var totalLines: Int
    /// Bumped on every geometry change (incl. column reflow). A change means all
    /// history tiles were re-rendered, so the canvas must drop its cached ones.
    var generationId: UInt32
    /// Cell/margin metrics in encoded pixels. The rendered frame includes the side
    /// margins (only the vertical margin is dropped), so the canvas must offset by
    /// leftMargin and use cellWidth rather than spreading the full image width over
    /// the columns. nil for a host too old to report geometry (falls back to
    /// margin-free mapping).
    var cellGeometry: CompanionCellGeometry?
}

@MainActor
@Observable
final class AppModel {
    /// Full-screen phases before (and including arrival at) the chat list.
    /// Which app the user must upgrade when the companion apps are
    /// version-incompatible (shown in the full-screen blocking panel).
    enum UpgradeSide: Equatable {
        case phone   // this iPhone app is too old
        case mac     // the Mac's iTerm2 is too old
    }

    enum Phase: Equatable {
        case launch
        case scanning
        case pairing
        case home
        /// Connected and paired, but the app versions are incompatible: a
        /// blocking panel tells the user which app to upgrade. Cleared by a
        /// successful handshake after the upgrade.
        case needsUpgrade(UpgradeSide)
    }

    /// Screens pushed onto the navigation stack once paired. Driving them
    /// through NavigationStack's path gives the standard slide transition and
    /// interactive swipe-back.
    enum Destination: Hashable {
        case create
        case conversation(chatID: String)
        case settings
        // originatingChatID is the chat the user tapped an @-mention in to reach
        // this session, if any; nil when reached from the session list or a
        // workgroup. The session view's compose overlay sends into that chat
        // (rather than a fresh session-bound one) and a reply notification pops
        // back to it.
        case session(guid: String, title: String, originatingChatID: String?)
        case workgroup(id: String, title: String)

        /// The chat id if this is a conversation entry, else nil. One definition
        /// so every "extract the conversation from a Destination" site stays in
        /// lockstep.
        var conversationID: String? {
            if case .conversation(let id) = self { return id }
            return nil
        }
    }

    /// The paired UI's top-level modes (the tab bar).
    enum AppTab: String, Hashable {
        case chats
        case sessions
    }

    var phase: Phase = .launch
    var selectedTab: AppTab = .chats {
        didSet {
            guard oldValue != selectedTab else { return }
            // A TabView keeps both tabs' bars mounted and does NOT fire the hidden
            // tab's onDisappear, so a dictation started on the leaving tab would
            // otherwise keep the mic recording. The controller cancels it if its
            // owner is no longer on the visible tab (covering a start still mid-
            // await, whose post-await re-check then bails).
            dictation.tabChanged(to: selectedTab)
            // A tab switch is NOT a user-initiated open of the now-visible chat, so
            // its cache-backed refresh failures don't count toward the escalate-to-
            // red streak (tab-switch churn on a flaky link shouldn't look permanent).
            syncOpenConversationToActiveTab(userInitiated: false)
        }
    }

    /// Point the single shared open-conversation state at the conversation
    /// VISIBLE on the now-active tab (its stack's last conversation). A
    /// conversation can be mounted on both tabs at once, and openChatID/messages
    /// are shared, so on tab switch we resync to the visible one.
    /// conversationDidAppear is a no-op when it's already open.
    ///
    /// If the active tab holds NO conversation, we DON'T clear openChatID: the
    /// conversation is still mounted (just hidden on the other tab), so leaving
    /// it open keeps its live deliveries flowing into `messages` and avoids
    /// wiping+refetching (an empty flash) every time the user rounds-trips
    /// through a conversation-free tab. A genuine pop clears it via
    /// conversationWasPopped instead.
    private func syncOpenConversationToActiveTab(userInitiated: Bool) {
        let ids = activePath.map(\.conversationID)
        if let active = SessionNavOpen.activeConversationID(in: ids) {
            conversationDidAppear(chatID: active, userInitiated: userInitiated)
        }
    }

    /// Detach the shared open-conversation display state without unsubscribing
    /// (the conversation may still be mounted on the other tab). Subscription
    /// teardown is handled separately by conversationWasPopped/the watch.
    private func clearOpenConversationDisplay() {
        guard openChatID != nil else { return }
        openChatID = nil
        openChatWasDeleted = false
        resetRefreshFailureState()
        messages = []
        isLoadingConversation = false
    }

    /// Reset the BANNER state (soft flag + escalated error) as one unit. Does NOT
    /// touch refreshFailuresByChat: the per-chat failure count must survive an
    /// open/close of the same chat so a persistently-failing load can escalate.
    private func resetRefreshFailureState() {
        conversationRefreshFailed = false
        conversationRefreshError = nil
    }
    /// The Sessions tab's navigation stack (the browser and what it pushes).
    /// A conversation can be pushed here too (from a live session view's reply
    /// notification), so it also tears down the subscription when popped.
    var sessionsPath: [Destination] = [] {
        didSet {
            conversationTeardownIfPopped(old: oldValue, new: sessionsPath, otherStack: navigationPath)
            // Resync the shared open-conversation state after any change to the
            // ACTIVE tab's stack (not just tab switches), so popping a
            // dual-mounted conversation off the visible tab doesn't leave
            // openChatID/messages stale.
            // A stack change (the user pushed/popped a conversation) IS a user open
            // of the now-visible chat, so its load failures may escalate the banner.
            if selectedTab == .sessions { syncOpenConversationToActiveTab(userInitiated: true) }
        }
    }
    /// The Chats tab's navigation stack.
    var navigationPath: [Destination] = [] {
        didSet {
            conversationTeardownIfPopped(old: oldValue, new: navigationPath, otherStack: sessionsPath)
            if selectedTab == .chats { syncOpenConversationToActiveTab(userInitiated: true) }
        }
    }

    /// Swipe-back and the back button mutate a path directly; when a conversation
    /// leaves it, tear down that conversation's shared open state/subscription.
    /// open-conversation state (openChatID/messages) and the Mac-side
    /// subscription are a single shared resource, and a chat can be mounted on
    /// both tabs at once, so a chat is torn down only once its LAST mount is gone
    /// across BOTH stacks (SessionNavTeardown, unit-tested) - never just because
    /// one stack lost it.
    private func conversationTeardownIfPopped(old: [Destination],
                                              new: [Destination],
                                              otherStack: [Destination]) {
        let gone = SessionNavTeardown.fullyRemoved(before: conversationIDs(in: old),
                                                   after: conversationIDs(in: new),
                                                   otherStack: conversationIDs(in: otherStack))
        for chatID in gone {
            conversationWasPopped(chatID)
        }
    }

    private func conversationIDs(in path: [Destination]) -> Set<String> {
        Set(path.compactMap(\.conversationID))
    }

    /// Every conversation mounted somewhere (either tab's stack). One definition
    /// of "mounted anywhere".
    private var mountedConversationIDs: Set<String> {
        conversationIDs(in: navigationPath).union(conversationIDs(in: sessionsPath))
    }

    /// The navigation stack of the currently-selected tab.
    private var activePath: [Destination] {
        selectedTab == .chats ? navigationPath : sessionsPath
    }

    /// Whether a chat is mounted as a conversation on either tab's stack, i.e.
    /// some ConversationView owns its (single, non-refcounted) Mac subscription.
    /// Short-circuiting scan; no Set allocation on these navigation-time paths.
    private func isConversationMounted(_ chatID: String) -> Bool {
        let isChat: (Destination) -> Bool = { $0.conversationID == chatID }
        return navigationPath.contains(where: isChat) || sessionsPath.contains(where: isChat)
    }

    /// Whether a chat still has an owner that needs its (unrefcounted) Mac
    /// subscription: a mounted conversation on either tab, the live session-view
    /// watch, or an in-flight watch intent a concurrent send registered before its
    /// subscribe. SINGLE source of truth so the unsubscribe path and the reconnect
    /// re-subscribe path can't drift on what "still needed" means (drift between
    /// those two definitions was the root of the subscribe/unsubscribe races).
    private func shouldRemainSubscribed(_ chatID: String) -> Bool {
        isConversationMounted(chatID) || watchState.needsSubscription(chatID)
    }
    var chats: [CompanionChatListEntry] = []
    /// One place the "does this chat exist / fetch it" identity rule lives, so the
    /// ~handful of send/notification/existence-guard sites don't each hand-roll the
    /// `chats.contains { $0.chat.id == X }` scan (and a future change like treating
    /// a soft-deleted chat as absent is one edit).
    func chatExists(_ chatID: String) -> Bool { chats.contains { $0.chat.id == chatID } }
    func chat(for chatID: String) -> CompanionChatListEntry? { chats.first { $0.chat.id == chatID } }
    var sessions: [CompanionSessionSummary] = []
    /// The Sessions tab's window/tab/pane/peer hierarchy.
    var sessionTree: CompanionSessionTree?
    /// Why the tree could not be loaded; only meaningful while sessionTree is
    /// nil (a stale tree keeps showing instead of an error).
    var sessionTreeError: String?

    // Conversation state for the open chat.
    var openChatID: String?
    var messages: [Message] = []
    /// Last-seen transcript per chat, so switching between two co-mounted
    /// conversations (one per tab) serves the cached messages instantly instead
    /// of flashing empty while a full history refetch runs. Bounded to mounted
    /// conversations (pruned on each switch).
    private var transcriptCache: [String: [Message]] = [:]
    /// Chats whose agent is currently typing. Tracked for ALL chats (typingStatus
    /// is edge-triggered and only delivered while a chat is watched/subscribed, so
    /// a status that arrived while a chat was hidden would otherwise be lost), so
    /// re-selecting a co-mounted chat mid-turn shows the right indicator.
    private var agentTypingChats: Set<String> = []
    /// Whether the OPEN chat's agent is typing. Derived, so switching tabs to a
    /// co-mounted chat reflects ITS state instead of being blanket-cleared.
    var isAgentTyping: Bool { openChatID.map { agentTypingChats.contains($0) } ?? false }

    // MARK: Live session view compose/notify

    /// userInfo keys on the local notifications the live session view posts when
    /// an agent reply arrives: the chat id to route to, and the tab whose stack
    /// the originating session view lives on (so a tap pushes the chat above it
    /// there, not onto whatever tab happens to be selected). The nav key's
    /// presence also distinguishes these from push-driven NSE alerts, which
    /// carry no routing payload.
    static let sessionChatNavKey = "sessionChatNav"
    static let sessionChatTabKey = "sessionChatTab"

    /// The session-view reply WATCH: a single slot plus its per-send claim
    /// bookkeeping, owned by one value type so the token/tab/chatID/sequence/
    /// departed-token transitions live and are tested in one place (see
    /// SessionWatchState). A SINGLE slot: two session views can be mounted at once
    /// (a TabView keeps both tabs' stacks), so a second view's send replaces the
    /// first's watch - a keyed set of watches would be the next step.
    private var watchState = SessionWatchState()
    /// Live (appeared, not-yet-popped) session-view watch tokens, keyed by session
    /// guid. The watch is token-keyed but the pop-vs-tab-switch decision was
    /// guid-keyed; when the SAME guid is mounted more than once (two nav stacks, or
    /// twice in one), a guid-only "still mounted?" check keeps returning true after
    /// the watch-owning view pops, so its watch would leak. Comparing the count of
    /// mounted destinations for a guid against the number of live tokens tells a
    /// genuine pop (one destination removed) apart from a tab switch (none removed),
    /// per token.
    private var appearedSessionTokens: [String: Set<UUID>] = [:]
    /// Pure decision logic for when to fire the reply notification (unit-tested in
    /// CompanionProtocol). The app feeds it normalized delivery/typing events; the
    /// trigger now also owns the per-id reply-text accumulation (one id->text
    /// surface, so there is no separate accumulator to keep keyed in lockstep).
    private var replyTrigger = SessionReplyTrigger()

    #if DEBUG
    /// The body of the last reply notification the trigger fired, for tests to
    /// observe reply firing without the UNUserNotification side effect.
    private(set) var testLastReplyFireBody: String?
    #endif
    /// De-dupes concurrent session-bound chat resolution by session guid, so two
    /// quick sends before the first resolves don't each create a new chat.
    private var pendingChatResolution: [String: Task<String, Error>] = [:]
    /// A reply-notification tap that arrived before the app finished launching
    /// (cold launch); replayed once phase == .home, since loadHome resets the
    /// nav paths and no NavigationStack is mounted before then.
    private var pendingSessionChatNav: (chatID: String, tab: AppTab)?

    /// On-device speech-to-text for the composer. Lazily prepared (download +
    /// load) on first use, not at launch.
    let whisperManager = WhisperModelManager()
    /// Single owner of dictation (recorder + ownership token + owning tab), so
    /// claim/start/stop are atomic across the two composer bars that can be
    /// mounted at once. Composer bars drive it; nothing else touches the recorder.
    let dictation: DictationController

    /// A user-facing error for the pairing screen. Nil while in progress.
    var pairingError: String?
    /// Step description for the pairing screen ("Searching for your Mac…").
    var pairingStatus = ""
    /// The 6-digit SAS confirmation code to display during a fresh pairing.
    /// Non-nil only while waiting for the user to type it on the Mac.
    var sasCode: String?
    /// When the in-flight pairing attempt began; drives the elapsed counter.
    var pairingStartedAt: Date?
    /// A pairing code received from an external URL (a tapped iterm2://pair link)
    /// that is awaiting user confirmation. QR scans pair directly; a link opened
    /// from elsewhere could point at an attacker's relay, so we confirm and show
    /// the host first.
    var pendingExternalPairing: PairingCode?
    /// True while a freshly pushed conversation is waiting for its history.
    var isLoadingConversation = false
    /// True while transparently re-establishing a dropped connection (shown
    /// as a banner; the user keeps their place in the UI).
    var isReconnecting = false

    /// Non-nil while the relay is refusing us for hitting its daily data limit
    /// (WS 1008 "daily quota exceeded"); holds the time we will next retry.
    /// Reconnecting sooner just trips the same limit, so the reconnect loop waits
    /// this out instead of the routine ~2s retry, and the UI shows a distinct
    /// "daily limit reached" banner (with a Reconnect now override) rather than
    /// the plain reconnecting banner. Cleared once a connection succeeds.
    var quotaBackoffUntil: Date?
    /// Set by the banner's "Reconnect now" button to end the quota backoff early.
    private var manualQuotaRetry = false

    /// True when the open conversation's chat was deleted on the Mac. The
    /// conversation stays on screen (yanking it away would be disruptive)
    /// with composing disabled; it is gone from the list once the user
    /// leaves. Always set together with the explanatory notice, and only from
    /// an authoritative chat list (see checkOpenChatStillExists).
    var openChatWasDeleted = false

    /// The single explanatory notice appended when the open chat is found
    /// deleted (display text only).
    static let deletedChatNoticeText =
        "This chat was deleted on your Mac. You can keep reading it until you leave, but nothing new can be sent."

    /// The message shown when a session-view send resolves to a deleted chat (the
    /// recovery path then creates a fresh chat). Hoisted so the three .chatDeleted
    /// returns and any localization stay in one place.
    static let chatDeletedRecoveryText =
        "This chat was deleted on your Mac. Start a new chat to keep talking to the agent."

    /// Stable, non-localized identity for that synthetic notice, so dedupe and
    /// removal key off the message id - not the user-visible body text, which
    /// would break if the wording is ever edited or localized. Only ever one such
    /// notice exists at a time (messages holds a single open chat's transcript),
    /// and the reserved value never collides with a real (random) message id.
    private static let deletedChatNoticeID =
        UUID(uuidString: "0000DE1E-7ED0-0000-0000-000000000000")!

    /// Stable id for the synthetic "Could not load this chat" notice, so it is
    /// never snapshotted into transcriptCache as if it were real loaded content
    /// (which would then render an error bubble AND a "showing cached" banner).
    private static let loadErrorNoticeID =
        UUID(uuidString: "0000E770-0000-0000-0000-000000000000")!

    /// The synthetic local-notice ids that must NEVER be cached as real content: a
    /// cached "Could not load" or "This chat was deleted" bubble would re-render on
    /// return (behind a contradictory "showing cached" banner) as if it were loaded
    /// transcript. One list so a future notice can't be excluded at one snapshot
    /// site but missed at another.
    private static let uncacheableNoticeIDs: Set<UUID> = [loadErrorNoticeID, deletedChatNoticeID]

    /// Snapshot the currently-open transcript into transcriptCache so returning to
    /// it serves content instead of flashing empty and refetching, UNLESS it holds a
    /// synthetic notice (see uncacheableNoticeIDs). The single definition of the
    /// snapshot policy, shared by the navigate-away and reconnect-re-serve paths.
    private func cacheOpenTranscript() {
        guard let openChatID,
              !messages.contains(where: { Self.uncacheableNoticeIDs.contains($0.uniqueID) }) else {
            return
        }
        transcriptCache[openChatID] = messages
    }

    /// True when the open conversation is showing a cached transcript because a
    /// refresh failed (e.g. a subscribe timeout during a tab switch). The cache
    /// may be missing messages that arrived while disconnected, so the view shows
    /// a non-destructive "couldn't refresh" banner. Cleared on the next
    /// successful load or when the conversation is left.
    var conversationRefreshFailed = false

    /// The real error text for the refresh-failed banner once the failure is no
    /// longer plausibly transient (a non-transport error, or a transport error
    /// that has repeated). nil while the soft "showing cached" banner is enough,
    /// so a permanent failure (auth loss / inaccessible history) is surfaced
    /// rather than hidden behind arbitrarily stale content.
    var conversationRefreshError: String?

    /// Consecutive failed loads PER chat, so escalation survives re-opening the
    /// same chat (the banner flags reset on open, but this does not). Cleared for a
    /// chat on its next successful load. Keyed by chatID rather than a single
    /// counter, which reset on every open and so never reached the escalation
    /// threshold across reconnect/re-open retries.
    private var refreshFailuresByChat: [String: Int] = [:]

    /// Whether the currently open chat's transcript is being served from the cache
    /// (so a failed refresh should keep it behind the soft banner, even when the
    /// cached transcript is legitimately EMPTY - which `messages.isEmpty` alone
    /// can't distinguish from "never loaded").
    private var openChatServedFromCache = false

    /// Interactive bubbles the user already answered, so their buttons render
    /// disabled (mirrors the Mac's one-shot buttons).
    var respondedInteractiveMessageIDs: Set<UUID> = []

    /// Non-nil while the session-picker sheet is up for a selectSessionRequest.
    struct SessionPickerRequest: Identifiable {
        let id = UUID()
        var requestMessageID: UUID
        var originalMessage: Message
        var terminal: Bool
    }
    var sessionPicker: SessionPickerRequest?

    /// Mention identifier (the text after the "@") to how the Mac resolved it.
    /// Message bubbles read this to draw live names in place of raw UUIDs;
    /// misses are requested in batches as messages arrive.
    var mentionResolutions: [String: CompanionMentionResolution] = [:]
    private var mentionResolutionsInFlight: Set<String> = []
    /// Identifiers we asked about and got no live name for (the Mac was
    /// unreachable, or the guid did not resolve at that instant). This gate
    /// stops a failed lookup from being re-requested on every incremental
    /// message delivery; it is cleared on reconnect and on chat open (see
    /// retryUnresolvedMentions) so a transient miss recovers instead of leaving
    /// the bubble showing a raw @UUID forever.
    private var unresolvedMentions: Set<String> = []

    private var pairingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    /// The code the current/last pairing attempt used, so Try Again can retry
    /// it instead of dumping the user at the scanner.
    private var activePairingCode: PairingCode?
    /// Whether the in-flight attempt is a reconnect to an existing pairing
    /// (vs a first pairing); the screen titles itself accordingly.
    private(set) var activeIsReconnect = false

    private var client: CompanionClient?

    /// Whether the connected Mac supports live session streaming (advertised
    /// protocol revision >= streamingRevision). The session view shows live video
    /// when true and falls back to PNG tiles otherwise. Set on each handshake.
    private(set) var macSupportsStreaming = false

    /// The live stream the session view is currently watching, and the handlers
    /// it registered. Only one session is streamed at a time.
    private var activeStreamID: UInt32?
    /// Whether a live stream is currently running (the canvas uses this to decide
    /// whether an unchanged-geometry layout pass should still re-drive tiles).
    var hasActiveStream: Bool { activeStreamID != nil }
    private var onStreamConfig: ((CompanionStreamConfig) -> Void)?
    private var onStreamMedia: ((CompanionMediaFrame) -> Void)?
    private var onStreamEnded: ((CompanionStreamEndReason) -> Void)?
    /// Geometry of the active stream (from the latest config) and the live top
    /// line (from the latest media frame), used to map a touch to a terminal cell
    /// for phone-driven selection. Whether selection is offered depends on the
    /// mac advertising selectionGeometryRevision and the config carrying geometry.
    private(set) var activeStreamGeometry: CompanionCellGeometry?
    private(set) var activeStreamImageSize: CGSize = .zero
    private(set) var activeStreamColumns = 0
    private(set) var activeStreamRows = 0
    private(set) var activeStreamLiveTop: Int64 = 0
    /// History extent from the latest config, for laying out the scrollback canvas.
    private(set) var activeStreamFirstAbsLine: Int64 = 0
    private(set) var activeStreamTotalLines = 0
    /// Whether the mac reports the session's window can currently be resized, from
    /// the latest config; the resize control is disabled otherwise.
    private(set) var activeStreamCanResize = true
    private var activeStreamGeneration: UInt32 = 0
    /// Rendered scrollback tiles keyed by the tile's first absolute line, with the
    /// fetches in flight so scroll events do not duplicate them.
    // Internal plumbing, not UI state: mutating it must not re-render SwiftUI views
    // (a tile load would otherwise trigger updateUIView and re-run selection logic).
    // Bounded so a long history browse cannot accumulate tile images without limit;
    // the LRU evicts the least-recently-used tile past the cap and supports the
    // key-range pruning below (unlike NSCache).
    @ObservationIgnored private let historyTileCache = CompanionLRUCache<Int64, UIImage>(capacity: 256)

    // History-tile request throttle. A fast fling scroll can walk through dozens of
    // viewports in under a second, and each viewport wants ~17 tiles; issuing them
    // all at once floods the relay and trips its per-connection frame-rate limit,
    // which closes the bridge (closeCode 1008 "frame rate exceeded"). Cap the number
    // of tile requests in flight and queue the rest. This bounds the burst; it reduces
    // (does not eliminate) the risk of tripping the relay's sustained rate limit,
    // which is why the relay also tears down both legs on a frame-rate close.
    @ObservationIgnored private var historyTilePending: [(firstAbsLine: Int64, lineCount: Int, epoch: Int, completion: (HistoryTileOutcome) -> Void)] = []
    // In-flight fetch Tasks, keyed by a monotonic id so each can remove itself on
    // completion and flushHistoryTileThrottle can cancel the prior stream's fetches.
    // This set IS the in-flight count: the throttle gate is its size, so there is no
    // separate counter to keep in sync (and no way to drive one negative). Without
    // cancellation, a transition that cleared the count while old fetches kept running
    // would let rapid session switches over one connection push real concurrency past
    // maxHistoryTilesInFlight and trip the relay's frame-rate limit.
    @ObservationIgnored private var historyTileTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var historyTileTaskCounter = 0
    // Per-stream epoch for the throttle. Generations restart at 1 for every stream
    // (see restartLiveStreamAfterReconnect), and a session switch reuses the same live
    // connection, so generation alone cannot tell one stream's tiles from another's.
    // The epoch bumps on every stream transition (watch/stop/pause/reconnect/ended/lost);
    // an in-flight request or a queued entry from a prior epoch is stale and must not
    // decrement the (reset) in-flight count, be cached, or be re-sent against the new
    // stream. See flushHistoryTileThrottle.
    @ObservationIgnored private var historyTileEpoch = 0
    // Set to true when a request is rejected because the backlog is full, and cleared
    // when the pipeline next drains to spare capacity. It gates the slot-available
    // signal so the canvas re-drives paced by network replies (when a slot actually
    // frees) instead of busy-looping a self-scheduled refresh while still saturated.
    @ObservationIgnored private var historyTileOverflowed = false
    /// Called on the main actor when the throttle drains to spare capacity after having
    /// rejected requests (and once per flush), so the canvas can re-request whatever it
    /// still wants. Two LiveCanvas coordinators can share this one AppModel (the Sessions
    /// tab and the session-mention preview), so the live coordinator claims ownership via
    /// historyTileSlotOwner and only the owner clears it; otherwise a dismissed preview
    /// would nil out the still-live tab's callback. See SessionView.
    ///
    /// This is a latency optimization, not a correctness dependency: the canvas also
    /// recovers rejected/spinner tiles from its 4 Hz growthTick pass (which runs on every
    /// live coordinator regardless of zoom), so a briefly-stranded or clobbered callback
    /// self-heals within ~250 ms and is reclaimed on the owner's next updateUIView.
    @ObservationIgnored var onHistoryTileSlotAvailable: (() -> Void)?
    @ObservationIgnored var historyTileSlotOwner: ObjectIdentifier?
    /// Most tile requests in flight at once.
    private let maxHistoryTilesInFlight = 6
    /// Deadline for a single tile fetch. CompanionSession.request has no timeout of its
    /// own: a lost or never-produced reply that does not close the socket would await
    /// forever and pin an in-flight slot, wedging the whole pipeline once all slots are
    /// stuck. Bounding the fetch frees the slot as .failed so the throttle recovers.
    private let historyTileTimeout: TimeInterval = 20
    /// Most tile requests waiting behind the in-flight window. A fling scroll enqueues
    /// far more than can matter by the time they run; cap the backlog and drop the
    /// oldest (furthest from where the user has since scrolled) so it cannot grow
    /// without bound. A dropped request reports .throttled so the caller keeps any
    /// current image and re-requests from its current position if still visible.
    private let maxHistoryTilesPending = 24

    /// The current selection span reported by the mac, for drawing handles.
    private(set) var activeSelectionRange: CompanionSelectionRange?
    /// The mac's advertised protocol revision (0 until the handshake).
    private(set) var macRevision = 0

    #if DEBUG
    /// Test override for this phone build's own revision, so a test can simulate a
    /// future (turnLifecycleRevision) build while `current` is still below it.
    var testLocalRevisionOverride: Int?
    #endif
    /// This phone build's own protocol revision.
    private var localRevision: Int {
        #if DEBUG
        return testLocalRevisionOverride ?? CompanionProtocolVersion.current
        #else
        return CompanionProtocolVersion.current
        #endif
    }
    /// Whether the reply trigger's turn boundaries come from the explicit
    /// turnLifecycle event rather than typing edges. Requires BOTH ends at
    /// turnLifecycleRevision: this phone stops driving the trigger from typing only
    /// when the mac ALSO sends turnLifecycle (and the mac gates that send on OUR
    /// revision), so the two gates are exact complements and the trigger is fed by
    /// exactly one source in every version pairing. Keying on macRevision alone
    /// would, against a future rev-8 mac, drop typing edges here while the mac
    /// (seeing our revision < 8) never sends turnLifecycle - silencing replies.
    private func usesTurnLifecycleBoundaries() -> Bool {
        min(macRevision, localRevision) >= CompanionProtocolVersion.turnLifecycleRevision
    }
    var sessionSelectionSupported: Bool {
        macRevision >= CompanionProtocolVersion.selectionGeometryRevision && activeStreamGeometry != nil
    }
    /// The session the live view wants to watch. Held across reconnects so the
    /// stream restarts automatically once the connection is back, instead of
    /// surfacing a transient "unavailable" error. nil when no live view is open.
    private var liveWatchGuid: String?
    /// True while the app is backgrounded: intent is kept but no stream runs.
    private var liveStreamPaused = false
    /// True while a start request is in flight, so a reconnect and a foreground
    /// resume firing together don't open two streams.
    private var liveStreamStarting = false

    // How the phone reaches the mac, built per pairing code: the relay connector
    // when the code carries a relay origin (off-LAN reach), else a connector that
    // fails fast. Injectable for tests; production uses
    // CompanionTransports.connector(for:).
    private let connectorForCode: (PairingCode, _ pairingTicket: String?, _ established: Bool) -> TransportConnector

    /// App Attest primitives for the relay attestation client. Off-device these
    /// are inert (isSupported == false), so attestation degrades to open mode.
    private let appAttestService: AppAttestService
    private let attestKeyStore: AttestKeyStore

    init(appAttestService: AppAttestService = DeviceCheckAppAttestService(),
         attestKeyStore: AttestKeyStore = UserDefaultsAttestKeyStore(),
         connectorForCode: @escaping (PairingCode, String?, Bool) -> TransportConnector = { code, ticket, established in
        // Sign the relay join only once THIS room is established (its verifier
        // is registered). Before that a fresh pairing must present the App
        // Attest ticket (or an empty proof in open mode), not a signature from
        // the device's global room secret, since the room has no verifier yet
        // and the relay would reject a signature under attestation.
        CompanionTransports.connector(
            for: code,
            roomSecret: { established ? PhoneIdentity.existingRoomSecret() : nil },
            pairingTicket: ticket)
    }) {
        self.appAttestService = appAttestService
        self.attestKeyStore = attestKeyStore
        self.connectorForCode = connectorForCode
        self.dictation = DictationController(whisper: whisperManager)
        // Route the transport/crypto layers' diagnostics into the unified log
        // (visible in Console.app and `log stream`).
        CompanionLog.handler = { message in
            companionLogPreformatted(message)
        }
        // Build stamp: settles "is the device running current code" instantly.
        if let url = Bundle.main.executableURL,
           let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date {
            companionLog("Launched; binary built \(mtime)")
        }
    }

    // MARK: Stored pairing

    // Shared with the NSE (single source of truth in CompanionProtocol).
    private static let storedKeyDefault = CompanionSharedIdentifiers.pairedResponderKeyDefault
    private static let storedPIDDefault = CompanionSharedIdentifiers.pairedPairingIDDefault
    private static let storedRelayOriginDefault = CompanionSharedIdentifiers.pairedRelayOriginDefault
    /// The canonical relay host. A pairing whose relay host differs from this is
    /// shown in punycode at confirmation time so a homograph host cannot
    /// masquerade as the real one.
    static let defaultRelayHost = "relay.iterm2.com"
    // The relay room name whose verifier this device has registered. Per ROOM,
    // not a global flag: pairing to a different Mac (a new pid, e.g. after the
    // user re-scans a QR) is a different room and must register (and, under
    // attestation, attest) its own verifier instead of inheriting a stale
    // "done" from the previous pairing. NoSync: local device state, not config.
    private static let registeredRoomDefault = "NoSyncRelayRegisteredRoom"

    private func roomName(for code: PairingCode) -> String {
        RelayRoom.name(responderStaticPublicKey: code.responderStaticPublicKey,
                       pairingID: code.pairingID)
    }

    /// Whether this pairing's verifier is registered with the relay (the room is
    /// established). Gates the one-time /register POST and the pairing-time
    /// attestation; false until a registration actually succeeds, so a failed
    /// attempt is retried on the next connect (self-healing).
    private func verifierRegistered(for code: PairingCode) -> Bool {
        let target = roomName(for: code)
        if PhoneIdentity.registeredRoomName() == target {
            return true
        }
        // Promote a marker left by an older build in UserDefaults (which a reinstall
        // wipes) into the keychain, so it survives future reinstalls like the
        // pairing code and room secret. Without this, a reinstall would forget the
        // room was established and wrongly attest on reconnect.
        if UserDefaults.standard.string(forKey: Self.registeredRoomDefault) == target {
            try? PhoneIdentity.storeRegisteredRoomName(target)
            return true
        }
        return false
    }

    private func markVerifierRegistered(for code: PairingCode) {
        try? PhoneIdentity.storeRegisteredRoomName(roomName(for: code))
    }

    /// The pairing from the last successful handshake. The responder key is
    /// public and the pid is not a secret, so UserDefaults is fine. The relay
    /// origin is persisted too so an off-LAN reconnect after relaunch can still
    /// reach the mac through the relay (not just the local network).
    /// The pairing code lives in the App Group KEYCHAIN (PhoneIdentity), so it
    /// survives an app reinstall - which wipes UserDefaults but not the keychain -
    /// and the NSE can read it. (It used to be in UserDefaults, so reinstalling
    /// the app forced a re-pair even though the keychain identity survived.)
    var storedPairingCode: PairingCode? {
        if let code = PhoneIdentity.pairingCode() {
            return code
        }
        // Fallback: a pairing stored by an older build (UserDefaults). Read it so
        // the user is not forced to re-pair; migratePairingCodeToKeychain copies
        // it into the keychain at launch.
        return legacyUserDefaultsPairingCode()
    }

    private func storePairing(_ code: PairingCode) {
        do {
            try PhoneIdentity.storePairingCode(code)
        } catch {
            companionLog("Failed to store pairing code in keychain: \(error)")
        }
    }

    /// One-time migration of a pairing code stored by an older build in
    /// UserDefaults into the keychain. Idempotent; runs at launch. Leaves the old
    /// UserDefaults values in place (forgetStoredPairing clears them on unpair).
    private func migratePairingCodeToKeychain() {
        guard PhoneIdentity.pairingCode() == nil,
              let legacy = legacyUserDefaultsPairingCode() else {
            return
        }
        try? PhoneIdentity.storePairingCode(legacy)
    }

    /// Read a pairing code left by an older build in UserDefaults (App Group
    /// suite, then app-only defaults).
    private func legacyUserDefaultsPairingCode() -> PairingCode? {
        let shared = UserDefaults(suiteName: PhoneIdentity.appGroup) ?? .standard
        let std = UserDefaults.standard
        guard let key = shared.data(forKey: Self.storedKeyDefault) ?? std.data(forKey: Self.storedKeyDefault),
              key.count == 32,
              let pid = shared.string(forKey: Self.storedPIDDefault) ?? std.string(forKey: Self.storedPIDDefault) else {
            return nil
        }
        let relayOrigin = shared.string(forKey: Self.storedRelayOriginDefault)
            ?? std.string(forKey: Self.storedRelayOriginDefault)
        return PairingCode(responderStaticPublicKey: key, pairingID: pid, relayOrigin: relayOrigin)
    }

    private func resetForFreshPairing() {
        companionLog("Fresh pairing: clearing all previous key material")
        wipeAllKeyMaterial()
    }

    /// Erase EVERY piece of key material on this device, for a clean fresh start
    /// (the user may be unpairing because of a compromise): the Noise identity,
    /// the room secret, the push-relay secret, and all attest key ids, plus - via
    /// forgetStoredPairing - the pairing code, the verifier-registration marker,
    /// and the per-chat push watermarks. Every unpair / re-pair path calls this
    /// so none leaves anything behind. The keychain deletes use a nil access
    /// group, so they span all the app's access groups (the App Group copy AND
    /// any leftover pre-migration default-group copy).
    private func wipeAllKeyMaterial() {
        attestKeyStore.removeAll()
        PhoneIdentity.deleteKeyPair()
        PhoneIdentity.deleteRoomSecret()
        PhoneIdentity.deletePushRelaySecret()
        forgetStoredPairing()
    }

    func forgetStoredPairing() {
        // Clear the pairing code from the keychain (current location) and from
        // both UserDefaults suites (legacy location).
        PhoneIdentity.deletePairingCode()
        for defaults in [UserDefaults(suiteName: PhoneIdentity.appGroup), UserDefaults.standard].compactMap({ $0 }) {
            defaults.removeObject(forKey: Self.storedKeyDefault)
            defaults.removeObject(forKey: Self.storedPIDDefault)
            defaults.removeObject(forKey: Self.storedRelayOriginDefault)
        }
        // Clear the verifier-registered marker from the keychain (current location)
        // and UserDefaults (legacy location).
        PhoneIdentity.deleteRegisteredRoomName()
        UserDefaults.standard.removeObject(forKey: Self.registeredRoomDefault)
        // Drop the per-chat push watermarks (shared with the NSE): they are keyed
        // by the old room secret and meaningless once unpaired. reset() clears by
        // prefix, so it does not need the (possibly already-deleted) room secret.
        if let backing = UserDefaultsWatermarkBacking(appGroup: PhoneIdentity.appGroup) {
            WatermarkStore(backing: backing).reset()
        }
    }

    /// Build the best-effort relay delete-room call for the current pairing, or
    /// nil if there is nothing to delete (no relay, no stored room secret). The
    /// returned closure captures the room secret now, so callers can wipe local
    /// key material immediately after without racing the network call. Best
    /// effort: a failure just leaves the relay's idle TTL to reclaim the room.
    private func relayDeleteWork() -> (@Sendable () async -> Void)? {
        guard let code = storedPairingCode,
              let origin = code.relayOrigin,
              let secret = PhoneIdentity.existingRoomSecret() else { return nil }
        let room = roomName(for: code)
        return {
            do {
                try await RelayRoomDeleter(origin: origin).deleteRoom(roomName: room, roomSecret: secret)
                companionLog("Relay room deleted at unpair")
            } catch {
                companionLog("Relay delete-room failed (best-effort): \(String(describing: error))")
            }
        }
    }

    /// Called once at launch: if a pairing is stored, reconnect to it instead
    /// of demanding a fresh QR scan.
    func handleLaunch() {
        // Move the NSE-shared keychain items into the App Group group and the
        // pairing code into the keychain, once, at launch (idempotent +
        // crash-safe), before any reconnect reads them.
        PhoneIdentity.migrateSharedItemsToAppGroup()
        migratePairingCodeToKeychain()
        guard phase == .launch, pairingTask == nil else { return }
        guard let code = storedPairingCode else { return }
        companionLog("Reconnecting to stored pairing (pid \(code.pairingID))")
        pair(with: code, isReconnect: true)
    }

    // MARK: Navigation

    func beginScanning() {
        pairingError = nil
        phase = .scanning
    }

    func cancelToLaunch() {
        phase = .launch
    }

    func beginCreateChat() {
        navigationPath.append(.create)
    }

    func beginSettings() {
        navigationPath.append(.settings)
    }

    /// The navigation stack of whichever tab the user is looking at; mention
    /// taps and the session browser both push onto the visible stack.
    private func appendToActivePath(_ destination: Destination) {
        switch selectedTab {
        case .chats:
            navigationPath.append(destination)
        case .sessions:
            sessionsPath.append(destination)
        }
    }

    /// Tapping an @-mention in a bubble pushes the read-only session view.
    /// fromChatID is the chat the mention lived in, so the session view's
    /// compose overlay can send back into it (nil from the session list).
    func openSession(guid: String, title: String, fromChatID: String? = nil) {
        appendToActivePath(.session(guid: guid, title: title, originatingChatID: fromChatID))
    }

    /// Tapping a workgroup @-mention pushes the member list.
    func openWorkgroup(id: String, title: String) {
        appendToActivePath(.workgroup(id: id, title: title))
    }

    /// Sessions tab: appearance and pull-to-refresh both re-fetch the tree.
    func refreshSessionBrowser() async {
        do {
            let client = try await currentClient(label: "Session tree")
            sessionTree = try await withTimeout(15, "Loading sessions") {
                try await client.sessionTree()
            }
            sessionTreeError = nil
        } catch {
            companionLog("Session tree refresh failed: \(String(describing: error))")
            if sessionTree == nil {
                sessionTreeError = userMessage(for: error)
            }
        }
    }

    /// Settings: sever the pairing entirely. Notifies the mac (so it destroys
    /// its key material too), deletes this device's identity and stored
    /// pairing, clears all state, and returns to the scanner.
    func disconnectFromMac() {
        companionLog("Disconnecting and forgetting this Mac")
        pairingTask?.cancel()
        pairingTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        let oldClient = client
        client = nil
        // Capture what the relay delete-room call needs BEFORE the secret is
        // wiped below; the phone initiates this unpair, so it owns the delete.
        let relayDelete = relayDeleteWork()
        Task {
            if let oldClient {
                try? await oldClient.sendUnpairing()
                await oldClient.close()
            }
            await relayDelete?()
        }
        // Wipe ALL key material (the relay delete-room call above already
        // captured the room secret it needs). The next pairing mints a fresh
        // Noise identity, room secret, push secret, and verifier registration.
        wipeAllKeyMaterial()
        activePairingCode = nil
        isReconnecting = false
        quotaBackoffUntil = nil
        pairingStartedAt = nil
        clearPairedMacData()
    }

    /// Shared privacy teardown for the two unpair paths (user-initiated
    /// disconnectFromMac and Mac-initiated handleRemoteUnpair): drop EVERYTHING
    /// in memory that belonged to the just-unpaired Mac so nothing lingers until
    /// a future pairing. Path-specific bits (pairing code / reconnect flags) stay
    /// in the callers. Keep this the single source of truth so the two paths
    /// can't drift (transcriptCache and the reply buffers were previously missed
    /// here, leaving full transcripts and buffered reply text in memory).
    private func clearPairedMacData() {
        chats = []
        sessions = []
        sessionTree = nil
        sessionTreeError = nil
        messages = []
        transcriptCache = [:]
        mentionResolutions = [:]
        mentionResolutionsInFlight = []
        unresolvedMentions = []
        openChatID = nil
        openChatWasDeleted = false
        resetRefreshFailureState()
        refreshFailuresByChat = [:]
        openChatServedFromCache = false
        agentTypingChats = []
        isLoadingConversation = false
        // The live session view's watch and its buffered agent-reply text also
        // reference the unpaired Mac's chats.
        watchState.reset()
        appearedSessionTokens = [:]
        resetWatchedReplyState()
        // A deferred reply-tap replay would otherwise navigate the NEXT paired Mac
        // to a chat id that never existed there.
        pendingSessionChatNav = nil
        // Cancel any in-flight session-bound chat resolution so it stops calling
        // createChat against the just-unpaired Mac.
        pendingChatResolution.values.forEach { $0.cancel() }
        pendingChatResolution = [:]
        // Cancel dictation directly: setting selectedTab = .chats below is a no-op
        // (and skips its tab-change side effect) when already on .chats, which
        // would leave the mic recording through the teardown transition.
        dictation.cancelActive()
        navigationPath = []
        sessionsPath = []
        selectedTab = .chats
        pairingError = nil
        phase = .scanning
    }

    // MARK: Pairing

    /// True when this code was already consumed by a successful pairing.
    /// Scanning it again should fail immediately rather than time out.
    func isUsedPairingCode(_ code: PairingCode) -> Bool {
        storedPairingCode?.pairingID == code.pairingID
    }

    /// Called by the scanning screen once it has a valid pairing code (or at
    /// launch with the stored one). Moves to the pairing screen and runs the
    /// rendezvous + handshake.
    /// Stash a pairing code that arrived from an external URL so the UI can
    /// confirm it (showing the relay host) before connecting.
    func requestExternalPairing(_ code: PairingCode) {
        pendingExternalPairing = code
    }

    /// The relay host to show in the confirmation: as-is when it is the known
    /// default, otherwise in punycode so a Unicode lookalike is visible.
    var pendingPairingRelayDisplay: String {
        Self.relayHostDisplay(for: pendingExternalPairing?.relayOrigin)
    }

    /// The relay host to surface on the pairing confirmation (SAS) screen when
    /// the active pairing uses a NON-default relay, in punycode; nil for the
    /// official default (nothing to disclose). This covers both entry points: a
    /// tapped iterm2:// link (which also discloses up front) and a scanned QR
    /// (which otherwise went straight into pairing without showing the host).
    var activePairingRelayHostToShow: String? {
        RelayHost.hostToDisclose(relayOrigin: activePairingCode?.relayOrigin,
                                 default: Self.defaultRelayHost)
    }

    static func relayHostDisplay(for relayOrigin: String?) -> String {
        guard let relayOrigin,
              let host = URLComponents(string: relayOrigin)?.host, !host.isEmpty else {
            return "an unspecified relay"
        }
        return host == defaultRelayHost ? host : Punycode.encodedHost(host)
    }

    func confirmExternalPairing() {
        guard let code = pendingExternalPairing else { return }
        pendingExternalPairing = nil
        pair(with: code)
    }

    func cancelExternalPairing() {
        pendingExternalPairing = nil
    }

    func pair(with code: PairingCode, isReconnect: Bool = false) {
        // Ignore a duplicate trigger for a fresh pairing already in flight for
        // this exact code. Both entry points reach here, the in-app scanner and
        // the system-camera link's confirm dialog, and they can BOTH fire for one
        // QR (scanning while the dialog is up). Cancelling and restarting would
        // open a second relay connection that displaces the first (newest-wins)
        // and breaks the Mac's in-progress handshake. A different code, or a
        // reconnect, still proceeds.
        if !isReconnect, pairingTask != nil, activePairingCode?.pairingID == code.pairingID {
            companionLog("Pairing already in progress for pid \(code.pairingID); ignoring duplicate trigger")
            return
        }
        companionLog("Pairing started (pid \(code.pairingID), reconnect: \(isReconnect))")
        if !isReconnect {
            // A fresh pairing (a scanned code, not a reconnect) supersedes any
            // previous one. Wipe carryover key material up front so the new
            // pairing starts from a clean slate and never inherits the old
            // room's secret, verifier registration, or attest key. The phone
            // cannot depend on the Mac's unpair farewell for this: that message
            // is delivered only if the phone is connected at unpair time, so an
            // offline phone would otherwise keep stale state forever.
            resetForFreshPairing()
        }
        activePairingCode = code
        activeIsReconnect = isReconnect
        phase = .pairing
        pairingError = nil
        pairingStartedAt = Date()
        pairingStatus = isReconnect ? "Reconnecting to your Mac" : "Searching for your Mac"
        pairingTask?.cancel()
        pairingTask = Task {
            var attempt = 0
            while true {
                attempt += 1
                do {
                    try await establish(code: code,
                                        handshakeTimeout: isReconnect
                                            ? Self.reconnectHandshakeTimeout
                                            : Self.firstPairHandshakeTimeout,
                                        requireConfirmation: !isReconnect)
                    pairingStatus = "Loading chats"
                    companionLog("Pairing succeeded; loading home")
                    try await loadHome()
                    companionLog("Home loaded")
                    storePairing(code)
                    reportPushStatus()
                } catch is CancellationError {
                    companionLog("Pairing cancelled")
                } catch {
                    companionLog("Pairing attempt \(attempt) failed: \(String(describing: error))")
                    if isReconnect {
                        // Transient network trouble must never dead-end into
                        // re-pairing; keep trying until the user cancels. Retry
                        // quickly: the mac may still be relaunching, and each
                        // attempt re-sends a fresh handshake until it lands.
                        pairingStatus = "Mac not found yet; retrying (attempt \(attempt + 1))"
                        do {
                            try await Task.sleep(nanoseconds: Self.reconnectRetryDelayNanos)
                            continue
                        } catch {
                            companionLog("Pairing retry loop cancelled")
                        }
                    } else {
                        pairingError = userMessage(for: error)
                    }
                }
                break
            }
            pairingStartedAt = nil
            pairingTask = nil
        }
    }

    /// Retry the same pairing the failed attempt used. The scanner is only for
    /// pairing a different Mac.
    func retryPairing() {
        guard let code = activePairingCode else {
            beginScanning()
            return
        }
        pair(with: code, isReconnect: activeIsReconnect)
    }

    /// The Cancel button on the pairing screen.
    func cancelPairing() {
        pairingTask?.cancel()
        pairingTask = nil
        pairingStartedAt = nil
        pairingError = nil
        phase = .launch
    }

    /// Seconds to wait for the Noise handshake before giving up an attempt.
    /// First pairing is generous (the user is watching, the network may be
    /// settling). Reconnect is short: over the relay the handshake is ~1s when
    /// the mac is ready, and when it is NOT (mac still relaunching, or a stale
    /// mac socket that swallows the first message), a fast failure lets us retry
    /// promptly instead of stalling ~15s on a message that will never be answered.
    // nonisolated: used as a default argument of establish(), which is
    // evaluated in a nonisolated context. An immutable Sendable constant.
    nonisolated private static let firstPairHandshakeTimeout: TimeInterval = 15
    private static let reconnectHandshakeTimeout: TimeInterval = 6
    /// Delay between reconnect attempts. The relay does not notify the phone
    /// when the mac (re)appears and drops a handshake sent before the mac is
    /// parked, so reconnect is a poll: keep re-sending a fresh handshake on this
    /// cadence until one lands on a ready mac. Kept short so a mac that just
    /// finished relaunching is picked up quickly.
    private static let reconnectRetryDelayNanos: UInt64 = 2_000_000_000
    /// How long to back off after the relay reports its daily data limit is
    /// exhausted. Fixed (the relay reports no reset time), long enough not to
    /// hammer the limit, short enough to recover within a day once the relay's
    /// 24h window rolls over. The user can override it with "Reconnect now".
    private static let quotaBackoffSeconds: TimeInterval = 30 * 60

    /// How long the phone waits for the user to type the SAS code on the Mac.
    /// Generous: a human is walking to a keyboard.
    private static let sasConfirmationTimeout: TimeInterval = 180

    /// True when admission failed because the relay required a signed join (the room
    /// is established and the verifier is registered). Used to self-heal a lost
    /// "established" marker by retrying with a signature.
    private static func admissionNeedsSignature(_ error: Error) -> Bool {
        guard case let TransportError.connectionFailed(message) = error else { return false }
        return message.range(of: "signature required", options: .caseInsensitive) != nil
    }

    private func establish(code: PairingCode,
                           handshakeTimeout: TimeInterval = firstPairHandshakeTimeout,
                           requireConfirmation: Bool = false) async throws {
        // A retry (PairingView "Try Again") can re-enter establish after a prior
        // attempt already built a client. Tear the old one down so its
        // connection and receive loop do not linger.
        if let existing = client {
            client = nil
            await existing.close()
        }

        let identity = try PhoneIdentity.keyPair()
        let established = verifierRegistered(for: code)
        companionLog("Connecting (discovery + TCP\(code.relayOrigin != nil ? " + relay" : ""))… "
            + "room \(established ? "established (will sign join)" : "fresh (will attest/empty proof)")")
        let pairingTicket = await pairingTicketIfNeeded(code)
        let connector = connectorForCode(code, pairingTicket, established)
        companionLog("Admission proof: "
            + (pairingTicket != nil ? "App Attest ticket"
               : established ? "join signature" : "empty (open mode)"))
        let rendezvous = PairingRendezvous(pairingID: code.pairingID)
        let transport: MessageTransport
        do {
            transport = try await connector.connect(to: rendezvous, timeout: 30)
        } catch let error where !established
                && Self.admissionNeedsSignature(error)
                && PhoneIdentity.existingRoomSecret() != nil {
            // Self-heal a lost/stale "established" marker: the relay still holds our
            // verifier and demands a SIGNED join, but we attested because the marker
            // was gone (e.g. a reinstall wiped the legacy UserDefaults copy before
            // it was moved to the keychain). We DO have the room secret, so persist
            // the marker and retry by signing - recovering without a re-pair, and
            // signing first-try on every later connect. (Couples to the relay's
            // "signature required" reason; if that drifts, the keychain marker plus a
            // manual re-pair still recover.)
            companionLog("Admission rejected (signature required) after attesting; retrying signed")
            markVerifierRegistered(for: code)
            let signingConnector = connectorForCode(code, nil, true)
            transport = try await signingConnector.connect(to: rendezvous, timeout: 30)
        }
        // The relay mints this for the phone at admission; present it to
        // /register. Captured before the handshake wraps the transport.
        let registrationToken = (transport as? RelayTransport)?.registrationToken
        companionLog("Transport connected; starting Noise handshake…")
        pairingStatus = "Securing the connection"
        let channel = try await withTimeout(handshakeTimeout, "Noise handshake") {
            try await NoiseHandshake.perform(
                role: .initiator,
                transport: transport,
                localKeyPair: identity,
                remoteStaticPublicKey: code.responderStaticPublicKey,
                prologue: code.handshakePrologue())
        }
        companionLog("Handshake complete; channel established")
        if requireConfirmation {
            // Fresh pairing: show the SAS code (derived from the handshake
            // hash, so both ends agree iff there is no man in the middle) and
            // wait for the Mac's verdict, the first frame on the channel. A
            // photographed-QR attacker pairs with their own phone, shows a
            // code the victim never sees, and the victim has nothing to type.
            sasCode = PairingSAS.code(handshakeHash: channel.handshakeHash)
            pairingStatus = "Waiting for the code to be entered on your Mac"
            defer { sasCode = nil }
            companionLog("Awaiting SAS confirmation from the mac")
            let verdictData: Data
            do {
                verdictData = try await withTimeout(Self.sasConfirmationTimeout, "Pairing confirmation") {
                    try await channel.receive()
                }
            } catch {
                await channel.close()
                throw error
            }
            guard PairingConfirmation.decode(verdictData) == .accepted else {
                companionLog("Pairing was not accepted on the mac")
                await channel.close()
                throw TransportError.connectionFailed(
                    "The pairing was declined on your Mac. Make sure the code matches and try again.")
            }
            companionLog("SAS confirmation accepted")
        }
        let client = CompanionClient(session: CompanionSession(transport: channel))
        await client.start(onEvent: { [weak self] event in
            Task { @MainActor in
                self?.handle(event: event)
            }
        }, onClose: { [weak self] error in
            Task { @MainActor in
                self?.connectionLost(dueTo: error)
            }
        }, onMedia: { [weak self] frame in
            Task { @MainActor in
                self?.handleStreamMedia(frame)
            }
        })
        self.client = client

        await lockRelayRoom(client: client, code: code, registrationToken: registrationToken)
    }

    /// For a fresh pairing, earn the single-use App Attest admission ticket the
    /// relay requires of a genuine app. Returns nil (an empty proof, the
    /// open-mode path) when the pairing is already established (reconnects sign
    /// with the room secret), there is no relay, or the device cannot attest /
    /// the relay is not enforcing attestation. Best-effort: a failure logs and
    /// returns nil, surfacing as an ordinary admission failure iff the relay
    /// actually required the ticket.
    private func pairingTicketIfNeeded(_ code: PairingCode) async -> String? {
        guard let relayOrigin = code.relayOrigin else {
            companionLog("Attestation: no relay origin in code; skipping ticket")
            return nil
        }
        guard !verifierRegistered(for: code) else {
            companionLog("Attestation: room already established; no ticket needed (reconnect signs)")
            return nil
        }
        companionLog("Attestation: fresh pairing, attempting App Attest ticket "
            + "(device supports App Attest: \(appAttestService.isSupported))")
        let roomName = roomName(for: code)
        let client = RelayAttestationClient(origin: relayOrigin,
                                            service: appAttestService,
                                            store: attestKeyStore)
        do {
            if let ticket = try await client.obtainTicket(roomName: roomName) {
                companionLog("Attestation: App Attest ticket obtained for pairing admission")
                return ticket
            }
            companionLog("Attestation: no ticket (open-mode relay or unsupported device); "
                + "joining with an empty proof")
            return nil
        } catch {
            companionLog("Attestation: ticket request FAILED: \(String(describing: error))")
            return nil
        }
    }

    /// Courier the room secret to the mac (every connect, idempotent) and, on a
    /// fresh pairing, register the verifier so the relay room is locked to this
    /// pairing. Best-effort: failures leave the room open-mode and are retried
    /// on the next connect (the design's self-healing re-key). Only meaningful
    /// for the relay transport.
    private func lockRelayRoom(client: CompanionClient,
                               code: PairingCode,
                               registrationToken: String?) async {
        guard let relayOrigin = code.relayOrigin else { return }
        do {
            let secret = try PhoneIdentity.roomSecret()
            // Ack-before-register: wait until the mac has stored the secret (and
            // can sign its parks) before establishing the room. The reverse
            // would let the room go established with the mac unable to park.
            companionLog("Relay room: couriering room secret to the mac…")
            try await client.registerRoomSecret(secret)
            companionLog("Relay room: mac acked the room secret")
            // Register once, the first connect after pairing. Reconnects
            // re-courier the secret but skip /register. The relay mints a token
            // on every admit, so the per-room flag, not the token, decides.
            if verifierRegistered(for: code) {
                companionLog("Relay room: verifier already registered for this room; done")
            } else if let registrationToken {
                companionLog("Relay room: registering verifier (token present)…")
                let registered = await registerRelayVerifier(
                    roomSecret: secret,
                    registrationToken: registrationToken,
                    relayOrigin: relayOrigin,
                    roomName: roomName(for: code))
                if registered {
                    markVerifierRegistered(for: code)
                }
            } else {
                companionLog("Relay room: no registration token (not a relay admission); "
                    + "verifier registration deferred")
            }
        } catch {
            companionLog("Relay room lock deferred: \(String(describing: error))")
        }
    }

    /// POST the verifier (public, derived from the room secret) to the relay's
    /// /register, authenticated by the one-time registration token.
    /// Returns true if the verifier is registered (a fresh 200, or a 403 that
    /// reports it is already registered), so the caller stops retrying. Any
    /// other outcome returns false to retry on the next connect.
    private func registerRelayVerifier(roomSecret: Data,
                                       registrationToken: String,
                                       relayOrigin: String,
                                       roomName: String) async -> Bool {
        struct Body: Encodable {
            var registrationToken: String
            var verifier: String
            // Present only under attestation; a nil optional is omitted, so an
            // open-mode register sends just the token and verifier.
            var challenge: String?
            var assertion: String?
        }
        guard let url = URL(string: relayOrigin + "/register") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(roomName, forHTTPHeaderField: "x-relay-room")
        request.setValue(CompanionUserAgent.value, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let verifier = RelayJoin.verifier(roomSecret: roomSecret).base64EncodedString()
        // Prove current possession of the attested key (the relay requires this
        // under attestation; nil in open mode). Best-effort: a failure leaves
        // an open-mode register, which the relay rejects iff it requires it.
        let attestation = try? await RelayAttestationClient(
            origin: relayOrigin, service: appAttestService, store: attestKeyStore)
            .registerAssertion(roomName: roomName)
        companionLog("Relay /register: verifier \(verifier.prefix(12))…, "
            + "assertion \(attestation != nil ? "present" : "absent (open mode)")")
        do {
            request.httpBody = try JSONEncoder().encode(
                Body(registrationToken: registrationToken, verifier: verifier,
                     challenge: attestation?.challenge, assertion: attestation?.assertion))
            let (data, response) = try await CompanionURLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            if (200..<300).contains(status) {
                companionLog("Relay verifier registered; room locked to this pairing")
                return true
            }
            // The room is already established (e.g. a prior attempt's POST
            // landed but its reply was lost): also done, stop retrying.
            if status == 403, body.contains("already registered") {
                companionLog("Relay verifier already registered")
                return true
            }
            companionLog("Relay verifier registration rejected (\(status)): \(body)")
            return false
        } catch {
            companionLog("Relay verifier registration failed: \(String(describing: error))")
            return false
        }
    }

    // MARK: Home

    /// From the upgrade panel, after the user has updated an app.
    ///
    /// If the upgrade wall came from a FRESH pairing (a scanned QR), return to the
    /// scanner rather than reconnecting: retrying a fresh pairing means re-scanning
    /// the (now-updated) Mac's NEW QR - the one just scanned is invalidated, so a
    /// silent reconnect with that stale code is wrong. A reconnect of an
    /// already-paired device just reconnects and re-runs the handshake; a
    /// compatible one proceeds to home, an incompatible one returns to the panel.
    func retryAfterUpgrade() {
        guard activeIsReconnect, let code = storedPairingCode else {
            phase = .scanning
            return
        }
        pair(with: code, isReconnect: true)
    }

    /// Thrown by the timeout leg of the post-establish `.hello` race, so a genuine
    /// timeout is distinguishable from a transport drop or a teardown (see loadHome).
    private struct HelloHandshakeTimedOut: Error {}

    func loadHome() async throws {
        // Version handshake FIRST: if the apps are incompatible, show the blocking
        // upgrade panel instead of the home screen. Pairing itself succeeded, so
        // storePairing still runs (caller) - after the user upgrades, a reconnect
        // gets a compatible handshake and proceeds to home.
        let client = try await currentClient(label: "Version handshake")
        // We reach here only AFTER establish() completed the Noise handshake, so
        // the channel is up and the Mac is authenticated. Race .hello against a
        // timeout and keep the outcomes distinct:
        //   - TIMED OUT: the Mac is present but never answers .hello at all - an
        //     older Mac that predates the handshake. (A network drop in the very
        //     next operation after a clean establish is far less likely; the Retry
        //     button recovers that rare false positive.) Treat it as "the Mac must
        //     upgrade" so a phone-first updater gets a clear panel, not a silent
        //     reconnect loop.
        //   - FAILED with a CompanionError: the Mac RESPONDED but with a rejection
        //     or a reply we can't make sense of (an older Mac that forward-compat-
        //     decodes .hello as .unsupported and replies .error, or any unexpected
        //     reply) - also "the Mac must upgrade".
        //   - FAILED with anything else: a real transport drop (TransportError) or
        //     a deliberate teardown (CancellationError) propagates to the normal
        //     pairing retry path. We do NOT claim "upgrade the Mac" just because
        //     the connection broke.
        let handshake: CompanionClient.HandshakeResult
        do {
            handshake = try await withThrowingTaskGroup(of: CompanionClient.HandshakeResult.self) { group in
                group.addTask { try await client.handshakeVersion() }
                group.addTask {
                    // A genuine elapse throws the sentinel; a cancelled sleep
                    // (teardown, or cancelAll after the handshake already won)
                    // throws CancellationError instead, so a teardown is never
                    // mistaken for a timeout.
                    try await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                    throw HelloHandshakeTimedOut()
                }
                defer { group.cancelAll() }
                // First child to finish wins: a verdict, or a thrown error (the
                // handshake's own, or our timeout sentinel).
                guard let result = try await group.next() else {
                    throw CancellationError()
                }
                return result
            }
        } catch is HelloHandshakeTimedOut {
            companionLog("Version handshake timed out after a successful establish; assuming the Mac app must upgrade")
            phase = .needsUpgrade(.mac)
            return
        } catch let error as CompanionError {
            companionLog("Version handshake rejected by Mac (\(error)); Mac app must upgrade")
            phase = .needsUpgrade(.mac)
            return
        }
        // Any OTHER error - a real transport drop (TransportError) or a deliberate
        // teardown (CancellationError) - is not an upgrade signal and propagates
        // out of loadHome to the normal pairing retry path.
        switch handshake.compatibility {
        case .compatible:
            break
        case .selfMustUpgrade:
            companionLog("Version handshake: this phone app must upgrade")
            phase = .needsUpgrade(.phone)
            return
        case .peerMustUpgrade:
            companionLog("Version handshake: the Mac app must upgrade")
            phase = .needsUpgrade(.mac)
            return
        }
        macSupportsStreaming = handshake.supportsStreaming
        macRevision = handshake.peerRevision
        companionLog("Version handshake: macRevision=\(macRevision) supportsStreaming=\(macSupportsStreaming) sessionResizeSupported=\(sessionResizeSupported) (resize needs mac revision >= \(CompanionProtocolVersion.sessionResizeRevision))")
        // The mac says the user opted into phone alerts: ask iOS for notification
        // permission if we haven't yet (deferring to foreground if backgrounded).
        if handshake.wantsNotificationPermission {
            ensureNotificationPermission(replyTo: nil)
        }
        try await refreshLists()
        navigationPath = []
        if phase != .home {
            // Arriving from pairing (not a pull-to-refresh): start clean.
            sessionsPath = []
            selectedTab = .chats
        }
        phase = .home
        // A reply-notification tap during launch was deferred (the nav paths
        // were just reset and no stack was mounted before now); replay it.
        applyPendingSessionChatNav()
    }

    private func refreshLists() async throws {
        let client = try await currentClient(label: "Refresh lists")
        companionLog("Requesting chat and session lists…")
        let (chats, sessions) = try await withTimeout(15, "Chat list request") {
            try await client.listChatsAndSessions()
        }
        companionLog("Received \(chats.count) chat(s), \(sessions.count) session(s)")
        self.chats = chats
        self.sessions = sessions
        // This is a wholesale list replacement (reconnect/foreground), so prune
        // state for chats deleted while offline - same as chatListChanged.
        pruneStateForLiveChats(Set(chats.map { $0.chat.id }))
        // Snippets can contain @-mentions; resolve them so the chat list
        // shows names instead of raw UUIDs.
        noteMentions(inTexts: chats.compactMap { $0.snippet })
        checkOpenChatStillExists()
    }

    /// Prune per-chat derived state (and the live watch) for chats that no longer
    /// exist after a wholesale chat-list replacement. Shared by chatListChanged and
    /// refreshLists so an offline deletion can't leave a stale cache / typing entry
    /// / failure counter / watch+subscription behind on either path.
    private func pruneStateForLiveChats(_ liveChatIDs: Set<String>) {
        transcriptCache = transcriptCache.filter { liveChatIDs.contains($0.key) }
        agentTypingChats.formIntersection(liveChatIDs)
        refreshFailuresByChat = refreshFailuresByChat.filter { liveChatIDs.contains($0.key) }
        if let watchedID = watchState.watchedChatID, !liveChatIDs.contains(watchedID) {
            tearDownCurrentWatch()
        }
    }

    // MARK: Connection lifecycle

    /// Returns the live client, waiting (bounded) for an in-flight reconnect
    /// to produce one. Throws with a readable message if none arrives, so
    /// callers surface a real error instead of spinning forever.
    private func currentClient(label: String, timeout: TimeInterval = 20) async throws -> CompanionClient {
        if let client {
            return client
        }
        companionLog("\(label): not connected; waiting up to \(Int(timeout))s for reconnect")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 250_000_000)
            if let client {
                companionLog("\(label): connection is back; proceeding")
                return client
            }
        }
        companionLog("\(label): gave up waiting for a connection")
        throw TransportError.connectionFailed("Not connected to your Mac")
    }

    /// The session's receive loop died: the mac quit, restarted, or the
    /// network dropped. Reconnect with the stored pairing, keeping the user's
    /// place in the UI. `error` is the terminating transport error when known, so
    /// a relay daily-quota teardown enters the long backoff immediately rather
    /// than after a first doomed attempt.
    private func connectionLost(dueTo error: Error? = nil) {
        guard !isReconnecting else { return }
        if let error {
            companionLog("Connection lost dueTo: \(String(describing: error))")
        } else {
            companionLog("Connection lost (no transport error; e.g. the foreground connection-check ping failed)")
        }
        client = nil
        // The stream id belongs to the dead connection; drop it (neutralizing the tile
        // throttle first) but keep the live-watch intent so it restarts after reconnect.
        neutralizeDeadStream()
        guard phase == .home else { return }
        guard let code = storedPairingCode else {
            phase = .scanning
            return
        }
        // A relay quota teardown is not transient: show the "daily limit reached"
        // banner up front and make the loop wait out the backoff before its first
        // attempt, instead of hammering the exhausted quota.
        if (error as? TransportError) == .quotaExceeded {
            companionLog("Connection lost: relay daily data limit reached")
            quotaBackoffUntil = Date().addingTimeInterval(Self.quotaBackoffSeconds)
            manualQuotaRetry = false
        }
        isReconnecting = true
        reconnectTask = Task {
            var attempt = 0
            while true {
                // Wait out a relay quota backoff (or a manual "Reconnect now")
                // before attempting, so we don't re-trip an exhausted daily limit.
                // quotaBackoffUntil stays set through the attempt (banner stays up);
                // it is cleared only on success or a non-quota exit below.
                if quotaBackoffUntil != nil {
                    await waitOutQuotaBackoff()
                    if Task.isCancelled { break }
                }
                attempt += 1
                do {
                    try await establish(code: code,
                                        handshakeTimeout: Self.reconnectHandshakeTimeout)
                    companionLog("Reconnected (attempt \(attempt))")
                    // Reachable again: leave any quota state so the banner clears.
                    quotaBackoffUntil = nil
                    // The Mac is reachable again: reopen the retry gate so the
                    // list-snippet and conversation re-scans below re-resolve any
                    // mention that failed while we were disconnected.
                    retryUnresolvedMentions()
                    // Re-run the version handshake on every reconnect so the mac's
                    // "user wants alerts" signal (carried in the .hello reply) is
                    // honored on each connect, not just the initial pairing. A
                    // failure here must not abort the reconnect, so it's best-effort.
                    if let client {
                        do {
                            let handshake = try await client.handshakeVersion()
                            macSupportsStreaming = handshake.supportsStreaming
                            macRevision = handshake.peerRevision
                            companionLog("Version handshake (reconnect): macRevision=\(macRevision) supportsStreaming=\(macSupportsStreaming) sessionResizeSupported=\(sessionResizeSupported) (resize needs mac revision >= \(CompanionProtocolVersion.sessionResizeRevision))")
                            if handshake.wantsNotificationPermission {
                                ensureNotificationPermission(replyTo: nil)
                            }
                        } catch {
                            companionLog("Reconnect version handshake failed: \(String(describing: error))")
                        }
                    }
                    reportPushStatus()
                    try await refreshLists()
                    if sessionTree != nil || selectedTab == .sessions {
                        // The Sessions tab loads its tree on appearance; if
                        // that load gave up while we were down (or its data
                        // is now stale), this is the retry.
                        await refreshSessionBrowser()
                    }
                    if let chatID = openChatID, !isLoadingConversation {
                        // Re-subscribe the open conversation on the new
                        // session. Skipped when a load is already parked in
                        // currentClient(); it resumes by itself.
                        //
                        // Snapshot the CURRENT live transcript into the cache
                        // first: forcing conversationDidAppear to re-run (by
                        // nil-ing openChatID) makes it serve transcriptCache[chatID],
                        // which is otherwise the stale snapshot from the last
                        // navigate-away (the open chat's cache entry is never
                        // refreshed by live deliveries). Without this, the reconnect
                        // clobbers messages received since - and if the reconnect-time
                        // reload then fails, strands the user on that stale transcript
                        // behind the soft "showing cached" banner. cacheOpenTranscript
                        // excludes the synthetic notices (never cache those as content).
                        cacheOpenTranscript()
                        openChatID = nil
                        conversationDidAppear(chatID: chatID)
                    }
                    // Subscriptions are per-connection. Re-subscribe EVERY mounted
                    // conversation across both tabs' stacks (not just openChatID +
                    // the watch): a conversation on the inactive tab (e.g. pushed
                    // there by a reply-notification tap, then handed off from the
                    // watch) is neither, and would otherwise silently drop live
                    // deliveries until the user switched to its tab.
                    if let client {
                        // Include openChatID: the conversationDidAppear above is
                        // skipped while a load is parked, and if that load already
                        // failed on the dead client (isLoadingConversation flipped
                        // false), nothing else re-subscribes the open chat.
                        // Every id here is mounted by construction, so no filter is
                        // needed (shouldRemainSubscribed would always be true);
                        // resubscribeVerifyingOwnership re-checks ownership after its
                        // await regardless.
                        for chatID in mountedConversationIDs {
                            await resubscribeVerifyingOwnership(chatID, client: client)
                        }
                        // The watch's chat may not be mounted as a conversation; make
                        // sure it too is re-subscribed (same ownership-verified idiom).
                        if let watched = watchState.watch, watched.chatID != openChatID,
                           !isConversationMounted(watched.chatID) {
                            await resubscribeVerifyingOwnership(watched.chatID, client: client)
                        }
                    }
                    // Reset the reply trigger for a live watch: a typingStatus that
                    // arrived during the drop is not replayed, so stale turn state
                    // must not carry across. NOTE this is broader than "completed
                    // while disconnected": a turn that STARTED before the drop and
                    // finishes just after (a brief mobile blip) also loses its
                    // notification, because turnStarted was cleared. Preferred over
                    // false fires from replayed-but-incomplete state; a full fix
                    // would re-query the chat's current typing status on reconnect.
                    if watchState.watch != nil {
                        resetWatchedReplyState()
                    }
                    // typingStatus is edge-triggered and NOT re-asserted on
                    // reconnect, so a turn's completing false may have been lost
                    // during the drop; clear typing state to avoid a stuck
                    // indicator (a still-typing chat re-asserts on its next turn).
                    agentTypingChats = []
                    // Resume a live session view that was open across the drop.
                    restartLiveStreamAfterReconnect()
                } catch is CancellationError {
                    // App-driven teardown; nothing to report.
                } catch {
                    // The relay hit its daily data limit: back off long (the loop
                    // top waits it out) and show the limit banner instead of the
                    // ~2s poll, which would only keep tripping the same limit.
                    if (error as? TransportError) == .quotaExceeded {
                        companionLog("Reconnect attempt \(attempt): relay daily data limit reached; backing off")
                        quotaBackoffUntil = Date().addingTimeInterval(Self.quotaBackoffSeconds)
                        manualQuotaRetry = false
                        continue
                    }
                    // A non-quota failure means the relay is no longer quota-blocking
                    // us (we reached admission, or it is a plain network error): drop
                    // any lingering backoff so the banner reverts from the limit
                    // message to the ordinary "reconnecting" pill.
                    quotaBackoffUntil = nil
                    // Keep the user's place and keep trying; transient network
                    // trouble must not dump them on the pairing screen.
                    companionLog("Reconnect attempt \(attempt) failed: \(String(describing: error))")
                    do {
                        try await Task.sleep(nanoseconds: Self.reconnectRetryDelayNanos)
                        continue
                    } catch {
                        companionLog("Reconnect loop cancelled")
                    }
                }
                break
            }
            isReconnecting = false
            quotaBackoffUntil = nil
            manualQuotaRetry = false
        }
    }

    /// Poll-wait out the relay quota backoff, returning when the deadline passes,
    /// the user taps "Reconnect now", or the reconnect task is torn down. The 1s
    /// tick keeps the banner countdown live and lets a manual retry engage
    /// promptly; quotaBackoffUntil is left set so the banner stays up through the
    /// following attempt (cleared only on success or a non-quota exit).
    private func waitOutQuotaBackoff() async {
        while let until = quotaBackoffUntil, until > Date(), !manualQuotaRetry, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    /// The quota banner's "Reconnect now" button: end the backoff early so the
    /// reconnect loop attempts immediately (e.g. after the user freed up quota or
    /// just wants to check).
    func reconnectNowAfterQuota() {
        guard quotaBackoffUntil != nil else { return }
        companionLog("Quota backoff: manual reconnect requested")
        manualQuotaRetry = true
    }

    /// Called when the app returns to the foreground: sockets often die
    /// silently in the background, so probe before the user hits an error.
    func checkConnectionOnForeground() {
        guard phase == .home, let client, !isReconnecting else { return }
        Task {
            do {
                try await withTimeout(5, "Connection check") {
                    try await client.ping()
                }
                companionLog("Foreground connection check: ping ok")
            } catch {
                companionLog("Foreground connection check: ping FAILED (\(String(describing: error))) -> treating connection as lost and reconnecting")
                connectionLost()
            }
        }
    }

    func refreshHome() {
        Task {
            do {
                try await loadHome()
            } catch {
                pairingError = userMessage(for: error)
            }
        }
    }

    // MARK: Create

    func createChat(mode: CompanionNewChatMode) {
        Task {
            do {
                let client = try await currentClient(label: "Create chat")
                let title = (mode == .orchestrator) ? "Orchestrator" : "New Chat"
                let entry = try await client.createChat(title: title, mode: mode)
                if !chatExists(entry.chat.id) {
                    chats.insert(entry, at: 0)
                }
                openConversation(chatID: entry.chat.id, replacingPath: true)
            } catch {
                pairingError = userMessage(for: error)
            }
        }
    }

    /// Swipe-to-delete: remove the row optimistically and tell the Mac. The
    /// list snapshot pushed after the Mac-side delete confirms it (or
    /// restores the row if the Mac refused).
    func deleteChat(chatID: String) {
        chats.removeAll { $0.chat.id == chatID }
        transcriptCache[chatID] = nil
        // Uphold the same per-chat cleanup invariant as pruneStateForLiveChats (the
        // chatListChanged / refreshLists paths): a deletion must not leave a stale
        // typing entry or failure counter behind. Otherwise a swipe-delete mid-turn
        // leaves agentTypingChats[chatID] lingering until the Mac's delete echo
        // pushes a fresh list.
        agentTypingChats.remove(chatID)
        refreshFailuresByChat[chatID] = nil
        // Stop watching a chat we just deleted, or its trailing typing(false) /
        // delivery would still fire a reply notification for a chat that no longer
        // exists (and can't be opened when tapped).
        if watchState.isWatching(chatID) {
            tearDownCurrentWatch()
        }
        Task {
            do {
                let client = try await currentClient(label: "Delete chat")
                try await client.deleteChat(chatID: chatID)
            } catch {
                companionLog("Delete chat failed: \(String(describing: error))")
            }
        }
    }

    /// Whether the connected Mac persists per-chat mute state; the mute UI is
    /// offered only then (an older mac would silently ignore the toggle).
    var macSupportsChatMuting: Bool {
        macRevision >= CompanionProtocolVersion.chatMuteRevision
    }

    /// Whether the connected Mac can resize a session on the phone's behalf; the
    /// resize control is offered only then (an older mac would silently ignore the
    /// resizeSession message).
    var sessionResizeSupported: Bool {
        macRevision >= CompanionProtocolVersion.sessionResizeRevision
    }

    /// Whether the mac supports the auto-provide consent flow (asking to include a
    /// session's terminal state + visible screen with AI messages).
    var autoProvideConsentSupported: Bool {
        macRevision >= CompanionProtocolVersion.autoProvideConsentRevision
    }

    /// Sessions the user chose "Not Now" for this app run, so a decline isn't re-asked
    /// on every message (a grant persists on the mac and reads back as satisfied).
    @ObservationIgnored private var declinedAutoProvideSessions = Set<String>()

    /// Whether to block a send with the auto-provide consent modal: the mac supports
    /// it, the user hasn't declined this session, and consent is not already in effect
    /// for the chat the send would target. Fails closed (no prompt) on any error.
    func shouldPromptAutoProvideConsent(sessionGuid: String) async -> Bool {
        guard autoProvideConsentSupported,
              !declinedAutoProvideSessions.contains(sessionGuid),
              let client else {
            return false
        }
        let satisfied = (try? await client.fetchAutoProvideConsent(sessionGuid: sessionGuid)) ?? true
        return !satisfied
    }

    /// Remember a "Not Now" so the modal isn't shown again for this session this run.
    func declineAutoProvideConsent(sessionGuid: String) {
        declinedAutoProvideSessions.insert(sessionGuid)
    }

    /// Whether the chat is muted, as of the last list refresh (or an optimistic
    /// local toggle awaiting the next refresh).
    func isChatMuted(chatID: String) -> Bool {
        chats.first { $0.chat.id == chatID }?.muted == true
    }

    /// Mute/unmute: flip the row optimistically and tell the Mac, which owns
    /// the muted set (it decides whether to push, possibly while this phone is
    /// unreachable). The next chat-list refresh carries the persisted state.
    func setChatMuted(chatID: String, muted: Bool) {
        companionLog("Setting chat \(chatID) muted=\(muted) (mac revision \(macRevision))")
        if let index = chats.firstIndex(where: { $0.chat.id == chatID }) {
            chats[index].muted = muted
        }
        Task {
            do {
                let client = try await currentClient(label: "Mute chat")
                try await client.setChatMuted(chatID: chatID, muted: muted)
                companionLog("setChatMuted(\(muted)) for chat \(chatID) sent to the mac")
            } catch {
                companionLog("Set chat muted failed: \(String(describing: error))")
            }
        }
    }

    /// The Session view's chat button: continue the session's most recently
    /// active chat if it was touched in the last 24 hours, otherwise start a
    /// fresh one. Conversations live on the Chats tab, so either way this
    /// switches there.
    func openOrCreateChat(forSessionGuid guid: String) {
        if let attached = recentAttachedChat(forSessionGuid: guid) {
            companionLog("Continuing chat \(attached.chat.id) for session \(guid)")
            openConversation(chatID: attached.chat.id, replacingPath: true)
        } else {
            companionLog("Creating a new chat for session \(guid)")
            createChat(mode: .session(guid: guid))
        }
    }

    /// The session's most recently active chat if it was touched within the last
    /// 24 hours, else nil. One definition shared by the session-list "chat about
    /// this session" button and the session-view compose overlay so their reuse
    /// rule can't silently diverge.
    private func recentAttachedChat(forSessionGuid guid: String) -> CompanionChatListEntry? {
        guard let attached = chats
            .filter({ $0.chat.terminalSessionGuid == guid })
            .max(by: { $0.chat.lastModifiedDate < $1.chat.lastModifiedDate }),
              Date().timeIntervalSince(attached.chat.lastModifiedDate) < 24 * 60 * 60 else {
            return nil
        }
        return attached
    }

    // MARK: Conversation

    /// Called from ConversationView.onAppear. Chat rows are NavigationLinks,
    /// so the system performs the (animated) push itself; this just starts the
    /// history load for the chat that appeared.
    /// `userInitiated` is true only for a real navigation to the chat
    /// (ConversationView.onAppear); the tab-sync and reconnect callers pass false,
    /// so their background cache-backed refresh failures show the soft banner but
    /// don't count toward the escalate-to-red streak (tab-switch churn on a flaky
    /// link shouldn't look like a permanent error).
    func conversationDidAppear(chatID: String, userInitiated: Bool = false) {
        guard openChatID != chatID else {
            return
        }
        // Snapshot the outgoing chat so returning to it (a tab switch back) serves
        // its transcript instead of flashing empty + refetching. Excludes the
        // synthetic notices (see cacheOpenTranscript), which must not be cached as
        // real content.
        cacheOpenTranscript()
        openChatID = chatID
        // Presumed live on open. Deletion is inferred ONLY from an authoritative
        // list (checkOpenChatStillExists), never from the possibly-not-yet-synced
        // local list here: a cold-launch notification tap mounts this before
        // `chats` has synced, and latching true from that would strand the
        // composer disabled with no notice and no recovery.
        openChatWasDeleted = false
        resetRefreshFailureState()
        // isAgentTyping is derived from agentTypingChats + openChatID, so switching
        // to a co-mounted chat mid-turn reflects ITS typing state (no blanket reset,
        // which used to drop the indicator for a turn in flight).
        if let cached = transcriptCache[chatID] {
            // Serve the cache immediately; loadConversation still refreshes below.
            messages = cached
            isLoadingConversation = false
            openChatServedFromCache = true
            // A cache entry only exists mid-session, where `chats` is kept live by
            // chatListChanged, so it IS authoritative here: a chat missing from it
            // was deleted while backgrounded. Disable + explain now (deduped)
            // rather than waiting for the next list push. The notice is re-asserted
            // after loadConversation, which replaces `messages`.
            checkOpenChatStillExists()
        } else {
            messages = []
            isLoadingConversation = true
            openChatServedFromCache = false
        }
        // Bound the cache to conversations still mounted somewhere.
        let mounted = mountedConversationIDs
        transcriptCache = transcriptCache.filter { mounted.contains($0.key) }
        Task {
            await loadConversation(chatID: chatID, userInitiated: userInitiated)
        }
    }

    private func isDeletedChatNotice(_ message: Message) -> Bool {
        message.uniqueID == Self.deletedChatNoticeID
    }

    /// Append the deleted-chat notice to the open transcript, once. Safe to call
    /// after the transcript is (re)loaded, since loadConversation replaces
    /// `messages` and would otherwise drop a notice appended earlier.
    private func appendDeletedChatNoticeIfNeeded() {
        guard openChatWasDeleted, let openChatID else { return }
        guard !messages.contains(where: { isDeletedChatNotice($0) }) else { return }
        messages.append(Message(chatID: openChatID,
                                author: .agent,
                                content: .clientLocal(ClientLocal(action: .notice(
                                    Self.deletedChatNoticeText))),
                                sentDate: Date(),
                                uniqueID: Self.deletedChatNoticeID))
    }

    /// Reconcile the open chat against an AUTHORITATIVE list snapshot
    /// (refreshLists / chatListChanged, or the mid-session cache path where the
    /// local list is kept live). Latches deletion WITH its notice, or recovers a
    /// false positive if the chat is present again. This is the single place that
    /// flips `openChatWasDeleted`, so the flag and the notice never diverge and a
    /// fresh list can clear a stale positive. Not called from the cold-launch /
    /// fresh-open path, where `chats` may not have synced yet.
    private func checkOpenChatStillExists() {
        guard let openChatID else { return }
        if !chatExists(openChatID) {
            if !openChatWasDeleted {
                companionLog("Open chat \(openChatID) was deleted on the Mac")
                openChatWasDeleted = true
            }
            appendDeletedChatNoticeIfNeeded()
        } else if openChatWasDeleted {
            companionLog("Open chat \(openChatID) is present again; re-enabling composer")
            clearDeletedChatState()
        }
    }

    /// The open chat is present again after a (possibly transient) deletion latch:
    /// re-enable the composer and drop the "deleted" notice, together. One
    /// definition so the flag and its notice never diverge; callers confirm presence
    /// (an authoritative list, or a successful subscribe+load) first.
    private func clearDeletedChatState() {
        openChatWasDeleted = false
        messages.removeAll { isDeletedChatNotice($0) }
    }

    /// Programmatic open used by the Create flow: replaces the stack so back
    /// returns to Home, then lets conversationDidAppear load the history.
    func openConversation(chatID: String, replacingPath: Bool) {
        handOffWatchedChatIfOpening(chatID)
        withAnimation {
            // Conversations live on the Chats tab (callers can be on the
            // Sessions tab, e.g. the session view's chat button).
            selectedTab = .chats
            if replacingPath {
                navigationPath = [.conversation(chatID: chatID)]
            } else {
                navigationPath.append(.conversation(chatID: chatID))
            }
        }
    }

    /// The user is opening a conversation the live session view was watching for
    /// replies. Stop watching (the user is about to read it, and leaving the
    /// session view must not unsubscribe the chat the conversation is taking
    /// over) but keep the subscription: opening the conversation re-subscribes
    /// idempotently, and its own teardown handles the unsubscribe. Runs
    /// synchronously before the navigation, so a subsequent session-view
    /// onDisappear finds nothing to tear down and can't race the re-subscribe.
    private func handOffWatchedChatIfOpening(_ chatID: String) {
        // Cancel the watch INTENT (installed or in-flight) only when the chat being
        // opened is the one it's for: a send suspended in beginWatchingSessionChat
        // would otherwise re-install a watch for the chat the user is now reading.
        // The watch KEEPS its subscription (the conversation re-subscribes
        // idempotently and owns teardown), so no unsubscribe here.
        if watchState.handOffIfOpening(chatID) {
            resetWatchedReplyState()
        }
    }

    private func loadConversation(chatID: String, userInitiated: Bool) async {
        companionLog("Loading conversation \(chatID)")
        do {
            let client = try await currentClient(label: "Load conversation")
            let history = try await withTimeout(15, "Loading the conversation") {
                try await client.subscribe(chatID: chatID)
            }
            // The user may have popped back (or opened another chat) while the
            // history was in flight.
            guard openChatID == chatID else {
                companionLog("Conversation \(chatID) no longer open; discarding history")
                return
            }
            messages = history.filter { !$0.hiddenFromClient }
            // Opening (or re-subscribing) a chat is a fresh chance to resolve
            // any mention that failed before, so reopen the retry gate first.
            retryUnresolvedMentions()
            noteMentions(in: messages)
            // A successful subscribe+history load is authoritative that the chat
            // EXISTS (a genuinely-deleted chat errors -> the catch keeps the flag).
            // So clear any stale deletion flag the cache path may have latched from
            // a transiently-incomplete `chats`, re-enabling the composer; a real
            // deletion re-latches on the next authoritative chatListChanged.
            if openChatWasDeleted {
                clearDeletedChatState()
            }
            resetRefreshFailureState()
            refreshFailuresByChat[chatID] = nil   // recovered; forget the streak
            // The refetch replaced the cache with authoritative history.
            openChatServedFromCache = false
            companionLog("Conversation loaded (\(messages.count) messages)")
        } catch {
            companionLog("Conversation load failed: \(String(describing: error))")
            guard openChatID == chatID else { return }
            // Discriminate on whether a CACHED transcript is on screen (which may
            // be legitimately empty), NOT on messages.isEmpty - a momentary blip on
            // an empty/new chat must still degrade to the soft banner, not a scary
            // "Could not load" notice.
            if openChatServedFromCache {
                // A cached transcript is still on screen; keep it, but don't
                // silently pretend it's current: show the soft "showing cached"
                // banner. Escalation to the red permanent-error banner is gated on
                // userInitiated - a background tab-sync/reconnect refresh must not
                // count toward the failure streak, or tab-switch churn on a flaky
                // link would look like a permanent error. For a user-initiated
                // open, a non-transport failure escalates at once, and a repeating
                // transient one (streak >= 2) escalates too.
                conversationRefreshFailed = true
                if userInitiated {
                    let failures = (refreshFailuresByChat[chatID] ?? 0) + 1
                    refreshFailuresByChat[chatID] = failures
                    if !(error is TransportError) || failures >= 2 {
                        conversationRefreshError = userMessage(for: error)
                    }
                }
            } else {
                // Never had content to preserve: the error notice IS the content.
                if userInitiated {
                    refreshFailuresByChat[chatID] = (refreshFailuresByChat[chatID] ?? 0) + 1
                }
                messages = [Message(chatID: chatID,
                                    author: .agent,
                                    content: .clientLocal(ClientLocal(action: .notice(
                                        "Could not load this chat: \(userMessage(for: error))"))),
                                    sentDate: Date(),
                                    uniqueID: Self.loadErrorNoticeID)]
            }
        }
        if openChatID == chatID {
            isLoadingConversation = false
        }
    }

    /// Called from the path observer once a specific conversation has been
    /// popped (back button or swipe); the pop animation is already underway.
    /// Unsubscribes that chat, and clears the open-conversation state only when
    /// the popped chat is the one currently open (it may belong to the other
    /// tab's stack).
    private func conversationWasPopped(_ chatID: String) {
        // If the live session view's watch still needs this chat, hand the
        // subscription to the watch so exactly one path unsubscribes later
        // (tearDownCurrentWatch), regardless of pop ordering. Otherwise this pop is
        // the sole owner of the (unrefcounted) subscription: release it.
        //
        // Only the unsubscribe branch drops chatID from agentTypingChats (once
        // unsubscribed, its typing(false) will never arrive). On the ADOPT branch we
        // deliberately do NOT: the subscription is kept, so a live turn's
        // typing(false) still arrives and self-heals the indicator - dropping it
        // here would wrongly hide "typing…" for an in-progress turn. Only a
        // genuinely HUNG turn (never emits typing(false)) leaves a stale indicator,
        // which reconnect/unpair clears.
        if !watchState.adoptSubscription(for: chatID) {
            unsubscribeIfUnused(chatID)
        }
        // Clear the shared display state if this was the open chat (single source
        // of truth, so the isLoadingConversation reset can't drift out of sync).
        if openChatID == chatID {
            clearOpenConversationDisplay()
        }
    }

    /// Unsubscribe a chat, but re-check just before sending that nothing owns it
    /// now: the deferred send runs later than the (synchronous) decision to
    /// unsubscribe, and the Mac sub isn't refcounted, so a re-navigation/re-watch
    /// in between would otherwise have its fresh subscription cut by this stale
    /// unsubscribe.
    private func unsubscribeIfUnused(_ chatID: String) {
        guard let client else { return }
        Task {
            // shouldRemainSubscribed also covers an IN-FLIGHT watch intent
            // (watchState.activeChatID), which a concurrent send sets synchronously
            // at the start of beginWatchingSessionChat, BEFORE its subscribe await
            // and before it installs the watch. Without that, the window lets us
            // unsubscribe a chat the concurrent send is about to (or just did)
            // subscribe. The guard + the unsubscribe send run without a suspension
            // between them, so once any owner is visible we never send.
            guard !shouldRemainSubscribed(chatID) else { return }
            // Once unsubscribed we won't receive this chat's typingStatus(false), so
            // a turn that finishes while we're away would leave a STUCK "typing…"
            // indicator on re-open. Drop its (now unverifiable) typing state.
            agentTypingChats.remove(chatID)
            try? await client.unsubscribe(chatID: chatID)
        }
    }

    /// Re-subscribe a chat on reconnect, then re-check ownership AFTER the await
    /// (each await is a @MainActor reentrancy point where a Back tap could pop the
    /// chat and run its unsubscribe) and undo a resurrect nothing owns, so the
    /// unrefcounted Mac subscription can't leak. One copy of this delicate idiom,
    /// used for both mounted conversations and the watch chat.
    private func resubscribeVerifyingOwnership(_ chatID: String, client: CompanionClient) async {
        _ = try? await client.subscribe(chatID: chatID)
        if !shouldRemainSubscribed(chatID) {
            _ = try? await client.unsubscribe(chatID: chatID)
        }
    }

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let chatID = openChatID, !openChatWasDeleted else { return }
        publishUserMessage(trimmed, toChatID: chatID, echo: true)
    }

    /// Build a user message, optionally echo it into the open transcript, note
    /// its mentions, and publish it. Shared by the chat composer (send) and the
    /// live session view (sendFromSessionView) so message construction and the
    /// publish path stay in one place. The text is assumed already trimmed.
    /// Build the user message, guard a deleted chat, optimistically echo it, and
    /// note its mentions. Returns nil when the chat was deleted (nothing to
    /// publish). Shared prep for both the fire-and-forget and awaitable paths.
    private func prepareUserMessage(_ text: String, toChatID chatID: String, echo: Bool) -> Message? {
        // Never publish into a chat the Mac deleted (belt-and-suspenders: send()
        // and sendFromSessionView both pre-check, but this is the single choke
        // point for constructing a user message).
        if chatID == openChatID, openChatWasDeleted { return nil }
        let message = Message(chatID: chatID,
                              author: .user,
                              content: .plainText(text, context: nil),
                              sentDate: Date(),
                              uniqueID: UUID())
        // Optimistic local echo so the bubble appears immediately.
        if echo {
            messages.append(message)
        }
        noteMentions(in: [message])
        return message
    }

    /// Fire-and-forget publish for the chat composer (send()), which echoes the
    /// bubble so a swallowed failure is at least visible as an un-answered message.
    private func publishUserMessage(_ text: String, toChatID chatID: String, echo: Bool) {
        guard let message = prepareUserMessage(text, toChatID: chatID, echo: echo) else { return }
        Task {
            do {
                let client = try await currentClient(label: "Send message")
                try await client.publish(message, toChatID: chatID)
            } catch {
                companionLog("Send failed: \(String(describing: error))")
            }
        }
    }

    /// Awaitable publish for the session-view send, which AWAITS the delivery and
    /// rethrows: a session-bound send has no echo, so a swallowed failure would
    /// make the message vanish silently (dismissed overlay, cleared draft, no
    /// bubble, no error). Surfacing the throw lets sendFromSessionView return
    /// .failed and restore the draft.
    private func publishUserMessageAwaitingDelivery(_ text: String,
                                                    toChatID chatID: String,
                                                    echo: Bool) async throws {
        // prepareUserMessage returns nil ONLY for a chat the Mac deleted (which
        // openChatWasDeleted can flip to true across the awaits sendFromSessionView
        // makes before this). Throw so the caller reports .chatDeleted rather than a
        // .sent for a message that was never published.
        guard let message = prepareUserMessage(text, toChatID: chatID, echo: echo) else {
            throw SessionSendChatDeleted()
        }
        do {
            let client = try await currentClient(label: "Send message")
            try await client.publish(message, toChatID: chatID)
        } catch {
            // Roll back the optimistic echo before rethrowing. On the @-mention path
            // the originating chat sits open below the session view, so echo == true
            // appended a bubble; the caller (sendComposed) then RESTORES the draft
            // into the composer on .failed. Without this rollback the failed message
            // shows BOTH as an undelivered phantom bubble AND back in the composer,
            // and each retry echoes another never-delivered bubble. The fire-and-
            // forget send() path keeps its bubble on purpose (no draft restore) and
            // uses publishUserMessage, so it is unaffected.
            if echo {
                rollBackEcho(id: message.uniqueID, chatID: chatID)
            }
            throw error
        }
    }

    /// Undo an optimistic echo for `chatID` after its publish failed, keyed by the
    /// TARGET chat rather than the live `messages`. During the publish await the user
    /// may have navigated away, which snapshots the echo into transcriptCache[chatID]
    /// and repoints `messages` to another chat; removing only from `messages` would
    /// then no-op and leave the phantom bubble in the cache (re-served on return).
    /// Purge both the live transcript (if that chat is still open) and its cache.
    private func rollBackEcho(id: UUID, chatID: String) {
        if openChatID == chatID {
            messages.removeAll { $0.uniqueID == id }
        }
        transcriptCache[chatID]?.removeAll { $0.uniqueID == id }
    }

    /// Thrown when a session-view send resolves to a chat the Mac deleted, so the
    /// caller surfaces the same .chatDeleted recovery as its up-front precheck.
    private struct SessionSendChatDeleted: Error {}

    // MARK: Live session view compose + reply notifications

    /// Outcome of a session-view send, scoped to the caller so its error alert
    /// doesn't leak onto a different SessionView via shared state.
    enum SessionSendOutcome {
        case sent(chatID: String)
        case failed(message: String)
        /// The resolved target chat was deleted on the Mac. Distinct from a
        /// transient .failed so the caller can drop its cached composeChatID and
        /// let the next send resolve/create a fresh session-bound chat, instead of
        /// re-targeting the dead id forever.
        case chatDeleted(message: String)
    }

    /// Claim the watch slot for this session view synchronously, BEFORE the async
    /// send Task runs (so a dismiss during startup clears it via
    /// endWatchingSessionChat). The caller must only claim for a non-empty send.
    /// Returns the prior claim so a failed send can restore it.
    /// The claim a send holds, used to restore it on failure without cutting a
    /// newer same-view send (which shares watchToken but has a higher sequence).
    typealias SessionWatchClaim = SessionWatchState.Claim

    func claimSessionWatch(token: UUID) -> SessionWatchClaim {
        // Capture the session view's tab NOW (synchronously). beginWatching runs
        // after an await, by which point the user may have switched tabs; reading
        // selectedTab there would stamp the watch with the wrong tab and a reply
        // tap would push the chat onto the wrong stack.
        watchState.claim(token: token, tab: selectedTab)
    }

    /// Undo a claim when the send it was made for didn't install a watch (failed),
    /// but only if this exact send is still the active claim (a newer same-view
    /// send bumps the sequence) - so it doesn't cut a concurrent valid watch, and
    /// not if the prior view has departed.
    func restoreSessionWatchClaim(_ claim: SessionWatchClaim) {
        watchState.restore(claim)
    }

    /// Send a message from the live session view's compose overlay. Resolves
    /// which chat it belongs to (the chat already resolved this visit, else the
    /// originating @-mention chat, else the session's recent chat or a fresh
    /// session-bound one), publishes it, and starts watching that chat so the
    /// agent's reply raises a local notification. `watchToken` identifies the
    /// calling session view (already claimed via claimSessionWatch) so a stale
    /// send or a different view leaving can't steal/cancel this view's watch.
    func sendFromSessionView(text: String,
                             sessionGuid: String,
                             resolvedChatID: String?,
                             originatingChatID: String?,
                             grantAutoProvideConsent: Bool = false,
                             watchToken: UUID,
                             claimSequence: Int) async -> SessionSendOutcome {
        // The caller (sendComposed) is the single point that rejects empty input,
        // BEFORE it claims the watch; by here the text is guaranteed non-empty.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Whether THIS send installed a fresh watch, so the unwind paths tear down
        // only their own (not a prior successful send's, which shares watchToken).
        var installedWatch = false
        do {
            // Precheck a live connection so a send while disconnected fails fast
            // (the resolvedChatID/originatingChatID branches below don't otherwise
            // touch the client). The resolve/watch/publish steps each fetch the
            // live client themselves so they self-heal across a reconnect.
            _ = try await currentClient(label: "Message from session")
            let chatID: String
            if let resolvedChatID {
                chatID = resolvedChatID
            } else if let originatingChatID {
                chatID = originatingChatID
            } else {
                chatID = try await resolveSessionBoundChat(forSessionGuid: sessionGuid)
            }
            // The user approved the consent modal: grant "provided automatically" on
            // the now-resolved chat BEFORE publishing, so this first message already
            // carries the terminal state + visible screen. Best-effort: a grant
            // failure must not block the send.
            if grantAutoProvideConsent {
                try? await currentClient(label: "Grant auto-provide").grantAutoProvideConsent(chatID: chatID)
            }
            // Don't publish into a chat the Mac deleted. Check the RESOLVED target
            // against the chat list, not `chatID == openChatID && openChatWasDeleted`:
            // an @-mention target (originatingChatID) can differ from openChatID
            // once syncOpenConversationToActiveTab repoints it, so the single
            // openChatWasDeleted flag wouldn't cover it. (A freshly created/reused
            // chat is inserted into `chats` before we get here, so it's present.)
            if !chatExists(chatID) {
                return .chatDeleted(message: Self.chatDeletedRecoveryText)
            }
            // Subscribe (start watching) BEFORE publishing, so the phone is
            // subscribed before the Mac starts the turn: otherwise its
            // typing(true) could land before the subscription and the reply
            // trigger (which requires a turn start) would never fire.
            installedWatch = await beginWatchingSessionChat(chatID: chatID, token: watchToken)
            // Re-check deletion AFTER the awaits above: a chatListChanged during the
            // resolve/subscribe could have deleted chatID, and prepareUserMessage's
            // guard only covers the OPEN chat, so a session-bound chat would still be
            // published into (silently lost - no echo). Unwind our own watch and
            // route to the same .chatDeleted recovery.
            if !chatExists(chatID) {
                unwindWatchForFailedSend(installedWatch: installedWatch, token: watchToken, claimSequence: claimSequence)
                return .chatDeleted(message: Self.chatDeletedRecoveryText)
            }
            // Echo into the transcript only when this is the open chat (the
            // @-mention case, whose conversation sits below the session view). Await
            // the delivery so a publish failure surfaces as .failed rather than a
            // silently-vanished message.
            try await publishUserMessageAwaitingDelivery(trimmed, toChatID: chatID,
                                                         echo: chatID == openChatID)
            return .sent(chatID: chatID)
        } catch {
            // The compose overlay already cleared the draft optimistically and
            // (session-bound case) echoes nowhere the user can see, so a swallowed
            // failure looks like a sent message that vanished. Report it to the
            // caller (which scopes the alert to its own view).
            companionLog("Send from session failed: \(String(describing: error))")
            // Tear down ONLY a watch THIS send installed (installedWatch): a failed
            // follow-up send must not destroy a prior successful send's still-valid
            // watch (they share the per-view watchToken).
            unwindWatchForFailedSend(installedWatch: installedWatch, token: watchToken, claimSequence: claimSequence)
            // A chat deleted between the precheck and the publish gets the same
            // recovery (drop the dead id, create a fresh chat) as the precheck.
            if error is SessionSendChatDeleted {
                return .chatDeleted(message: Self.chatDeletedRecoveryText)
            }
            return .failed(message: userMessage(for: error))
        }
    }

    /// Unwind a watch a FAILED send installed. Only tears down when this send
    /// actually installed a fresh watch AND that watch is still ours (same token),
    /// so it never cuts a prior successful send's watch or a newer view's. Does NOT
    /// mark the token departed - the view is still up (unlike endWatchingSessionChat).
    private func unwindWatchForFailedSend(installedWatch: Bool, token: UUID, claimSequence: Int) {
        guard let removed = watchState.unwindFailedSend(installedWatch: installedWatch,
                                                        token: token,
                                                        claimSequence: claimSequence) else {
            return
        }
        resetWatchedReplyState()
        if removed.subscribedHere { unsubscribeIfUnused(removed.chatID) }
    }

    /// Reuse the session's most recently active chat if it was touched in the
    /// last 24 hours (same rule as openOrCreateChat), otherwise create a new
    /// session-bound chat. De-dupes concurrent resolutions for the same session
    /// (a second send arriving before the first's createChat returns would
    /// otherwise create a duplicate chat, since the new chat isn't in `chats`
    /// yet). Does not navigate; just yields the chat id for a background send.
    private func resolveSessionBoundChat(forSessionGuid guid: String) async throws -> String {
        if let inFlight = pendingChatResolution[guid] {
            return try await inFlight.value
        }
        var thisTask: Task<String, Error>!
        thisTask = Task<String, Error> {
            // Clear the slot when the TASK finishes (not when an awaiting caller
            // returns): if a caller's outer Task is cancelled mid-send, a
            // caller-scoped defer would free the slot while this unstructured Task
            // keeps running createChat, and a second send would then create a
            // duplicate chat. Guard on TASK IDENTITY (Task is Hashable): a
            // cancelled old task unwinding later must not evict a NEWER task's slot
            // (e.g. after unpair+repair reused this guid).
            defer { if self.pendingChatResolution[guid] == thisTask { self.pendingChatResolution[guid] = nil } }
            // Fetch the LIVE client at await time (mirrors beginWatchingSessionChat)
            // so a reconnect during a long createChat self-heals, instead of every
            // coalesced waiter failing against a captured, now-dead connection.
            let client = try await self.currentClient(label: "Resolve session chat")
            return try await self.resolveSessionBoundChatUncoalesced(forSessionGuid: guid, client: client)
        }
        pendingChatResolution[guid] = thisTask
        return try await thisTask.value
    }

    private func resolveSessionBoundChatUncoalesced(forSessionGuid guid: String,
                                                    client: CompanionClient) async throws -> String {
        if let attached = recentAttachedChat(forSessionGuid: guid) {
            return attached.chat.id
        }
        // Time-bound the createChat like the other client calls: a hung Mac must
        // not park this (coalesced) resolution forever, which would stick the
        // pendingChatResolution slot and block all future sends for this session.
        let entry = try await withTimeout(15, "Creating a chat") {
            try await client.createChat(title: "New Chat", mode: .session(guid: guid))
        }
        if !chatExists(entry.chat.id) {
            chats.insert(entry, at: 0)
        }
        return entry.chat.id
    }

    /// Begin watching a chat for the agent's reply while the session view is up.
    /// If the chat is not already open, subscribe so its deliveries stream in.
    /// Runs async (after publish/subscribe); if this send is no longer the active
    /// watch intent (its view left, or a newer send superseded it) we install
    /// nothing and undo any subscription made just now, so a departed/superseded
    /// send can't leak a watcher or clobber a newer valid watch.
    /// Returns whether THIS call installed a fresh watch (vs reused an existing
    /// one, or no-op'd because superseded). A caller unwinding a failed send must
    /// only tear the watch down when it installed one - otherwise a failed
    /// follow-up send would destroy a PRIOR successful send's still-valid watch
    /// (both sends from a view share one per-view token, so token identity can't
    /// tell them apart).
    @discardableResult
    private func beginWatchingSessionChat(chatID: String, token: UUID) async -> Bool {
        // Record the intent (and no-op if a stale/superseded send lost ownership
        // BEFORE any destructive work).
        guard watchState.recordIntent(chatID: chatID, token: token) else { return false }
        // Already watching this chat: transfer ownership (token + tab) to the newer
        // view but keep the existing subscription. Reused, not freshly installed.
        if watchState.reuseIfSameChat(chatID, token: token) {
            return false
        }
        // Switching to a different watched chat: drop the previous one first.
        tearDownCurrentWatch()
        // Subscribe only if no mounted conversation already owns this chat's
        // subscription (checking BOTH stacks, not just openChatID - the chat may
        // be mounted on the other tab).
        var subscribedHere = false
        if !isConversationMounted(chatID) {
            // Fetch the LIVE client (self-heals across a reconnect that happened
            // since the send began) rather than a captured instance that may be
            // dead; otherwise the subscribe hits a defunct connection.
            if let client = try? await currentClient(label: "Watch subscribe") {
                do {
                    _ = try await client.subscribe(chatID: chatID)
                    subscribedHere = true
                } catch {
                    companionLog("Watch-subscribe failed for \(chatID): \(String(describing: error))")
                }
            }
        }
        // The view may have left (or a newer send superseded us) during the
        // awaited subscribe; honor the token so we don't watch/leak for it.
        guard watchState.isActiveOwner(token) else {
            companionLog("Session view left/superseded before watch could start; unwinding \(chatID)")
            // Don't unsubscribe if a newer watch already adopted this chat (Mac
            // subscribe/unsubscribe isn't refcounted, so we'd cut its stream) or
            // a conversation now mounts it (re-checked in unsubscribeIfUnused).
            if subscribedHere {
                unsubscribeIfUnused(chatID)
            }
            return false
        }
        resetWatchedReplyState()
        // install() uses the tab captured synchronously at claim time (NOT
        // selectedTab here, post-await): a reply tap must push the chat onto the
        // stack the session view actually lives on.
        watchState.install(chatID: chatID, subscribedHere: subscribedHere, token: token)
        companionLog("Watching chat \(chatID) for replies (subscribedHere=\(subscribedHere), openChat=\(openChatID ?? "nil"))")
        return true
    }

    /// A session view (re)appeared: its token is alive again, so un-mark it as
    /// departed. onDisappear fires while a view stays in the stack (a tab switch, a
    /// cover), and its @State watchToken outlives that, so without this a live
    /// view's token would linger and wrongly block a restore.
    func watchViewDidAppear(guid: String, token: UUID) {
        appearedSessionTokens[guid, default: []].insert(token)
        watchState.viewDidAppear(token: token)
    }

    /// How many session-view destinations for `guid` are mounted across both tabs'
    /// stacks. A count (not a bool) because the same guid can be mounted more than
    /// once, and a genuine pop is detected as the count dropping below the number of
    /// live views for that guid.
    private func mountedSessionCount(_ guid: String) -> Int {
        let matches: (Destination) -> Bool = {
            if case .session(let g, _, _) = $0 { return g == guid }
            return false
        }
        return navigationPath.filter(matches).count + sessionsPath.filter(matches).count
    }

    /// A session view's onDisappear. onDisappear ALSO fires on a tab switch / cover
    /// while the view stays in the nav stack, and tearing the watch down then would
    /// kill the reply notification for a message the user just sent before
    /// switching to the Chats tab to wait. Only a genuine pop ends the watch.
    ///
    /// The pop test is token-aware: a genuine pop removes THIS view's destination
    /// from the nav stack, so the count of mounted `.session(guid)` destinations
    /// drops below the number of live tokens for that guid; a tab switch / cover
    /// leaves them equal. A guid-only "still mounted?" bool would wrongly see a
    /// co-mounted duplicate of the same guid and skip the teardown, leaking this
    /// token's watch (and its Mac subscription) permanently.
    func sessionViewDidDisappear(guid: String, token: UUID) {
        let live = appearedSessionTokens[guid]?.count ?? 0
        guard mountedSessionCount(guid) < live else { return }   // tab switch / cover
        appearedSessionTokens[guid]?.remove(token)
        if appearedSessionTokens[guid]?.isEmpty == true { appearedSessionTokens[guid] = nil }
        endWatchingSessionChat(token: token)
    }

    /// A genuine departure (view popped): mark the token departed (blocks a later
    /// restore from reviving it) and tear down the watch if it owned it.
    func endWatchingSessionChat(token: UUID) {
        if let removed = watchState.depart(token: token) {
            resetWatchedReplyState()
            if removed.subscribedHere { unsubscribeIfUnused(removed.chatID) }
        }
    }

    /// Drop the current watch (if any) and its watch-only subscription.
    private func tearDownCurrentWatch() {
        guard let removed = watchState.removeWatch() else { return }
        resetWatchedReplyState()
        // Unsubscribe only if this watch owns the subscription and no mounted
        // conversation still needs it (one may have mounted the chat since the
        // watch began; its own teardown then handles the unsubscribe). The
        // re-check runs again just before the send.
        if removed.subscribedHere {
            unsubscribeIfUnused(removed.chatID)
        }
    }

    private func resetWatchedReplyState() {
        // The trigger owns the reply-text accumulation, so a fresh trigger clears it.
        replyTrigger = SessionReplyTrigger()
    }

    /// A delivery arrived for the chat the session view is watching. A reply may
    /// arrive as streaming append deltas, as growing whole-message snapshots, or
    /// (for a non-streaming model) as a single final message published AFTER the
    /// turn's typingStatus false, so no single delivery is "the reply is done".
    /// Deliveries are normalized to SessionReplyTrigger events (unit-tested),
    /// which decides when to fire. (The .commit that ends a streamed turn is
    /// hiddenFromClient and never forwarded, so it isn't a signal here.)
    /// Note: this watches the whole CHAT, not a specific turn, so while the
    /// session view is up ANY agent turn on the watched chat (an
    /// orchestration/watcher-triggered turn, a queued follow-up, or activity from
    /// another paired device) fires a notification. That breadth is intentional:
    /// any agent reply on the chat the user is engaged with is worth surfacing.
    private func noteWatchedSessionDelivery(_ message: Message, chatID: String) {
        guard let watched = watchState.watch, chatID == watched.chatID else { return }
        guard message.author == .agent, !message.hiddenFromClient else { return }
        // Resolve any @-mentions in the reply so the notification body (and the
        // transcript when the user opens the chat) shows names, not raw @<guid>.
        // For the OPEN chat apply() already parsed it this delivery, so only do it
        // here for a watched-but-covered chat (avoids a second O(text) regex scan
        // per streamed token when the chat is both open and watched).
        if chatID != openChatID {
            noteMentions(in: [message])
        }
        // Normalize the delivery to a raw accumulation chunk (or a request/no-op).
        // The trigger owns the single id->text surface now, so the chunk carries its
        // own id: a streamed delta reuses the delta's uuid (which reuses the .begin
        // id); a whole message uses the uniqueID.
        let id = message.uniqueID.uuidString
        let event: SessionReplyTrigger.Event
        switch message.content {
        case .append(let string, let uuid):
            // A streamed text delta; concatenates onto the .begin snapshot's text.
            event = .reply(chunk: .appendText(id: uuid.uuidString, delta: string))
        case .appendAttachment(let attachment, let uuid):
            // A streamed attachment delta; keeps the .begin preview if any, else the
            // attachment's preview + label-ness (a "📄 name" label REPLACES on the
            // next text delta; .code text EXTENDS, like the whole-message path).
            let preview = Self.attachmentPreview(attachment)
            event = .reply(chunk: .appendAttachment(id: uuid.uuidString,
                                                    previewIfEmpty: preview.text,
                                                    isLabel: preview.isLabel))
        case .plainText(let text, _), .markdown(let text):
            // A whole message, OR the .begin first chunk of a streamed reply
            // (later chunks arrive as .append reusing this uniqueID). Seed with the
            // RAW text (isLabel: false) so those chunks concatenate onto it instead
            // of dropping the first chunk.
            event = .reply(chunk: .begin(id: id, preview: text, isLabel: false))
        case .multipart, .explanationResponse:
            // isLabel comes from what the preview actually is (an attachment label
            // vs real text), computed inside replyPreview from the last substantive
            // subpart - not from subpart-type presence, which mis-flags a trailing
            // attachment label as text when an empty .markdown("") is present.
            let preview = Self.replyPreview(for: message)
            event = .reply(chunk: .begin(id: id, preview: preview.text, isLabel: preview.isLabel))
        case .remoteCommandRequest(.classic, _), .selectSessionRequest:
            // A block-on-user request the phone received. The mac's broker processor
            // (ChatClient.processRemoteCommandRequest) SQUELCHES auto-run (.always +
            // safe) and auto-deny (.never) classic requests before fan-out, so a
            // .classic remoteCommandRequest that reaches us here has ALWAYS parked on
            // the user's approval - regardless of the content-safety `safe` flag (a
            // .ask command judged safe still parks). Surface any of them (and a
            // select-session) as a userActionRequest, which fires without a preceding
            // turnStarted - so the pending approval is notified even on a
            // turnLifecycleRevision mac (where a park emits no turnEnded) and isn't
            // mis-framed as a finished reply on a legacy mac. External (orchestration)
            // requests are auto-dispatched and not squelched, so they fall to default.
            event = .userActionRequest(id: id, fallback: Self.requestDescription(for: message.content))
        case .clientLocal(let clientLocal):
            // The orchestration-enable request parks the turn on the user's
            // Enable/Not-Now; like an approval park it emits no turnEnded on a
            // turnLifecycleRevision mac, so surface it as a userActionRequest too.
            // Other client-local notices/bookkeeping don't park.
            guard case .enableOrchestrationRequest = clientLocal.action else { return }
            event = .userActionRequest(id: id, fallback: "Enable orchestration for this chat?")
        default:
            // Tool calls, local notices, commits, bookkeeping: not the preview.
            return
        }
        applyReplyTrigger(event, watched: watched)
    }

    /// Max length of a reply-notification body preview (one source of truth).
    private static let notificationBodyMaxLength = 200

    /// The preview walks below feed the reply NOTIFICATION, whose body is
    /// @-mention-rendered and then truncated ONCE at the end (postReplyNotification,
    /// matching "render mentions BEFORE truncating"). Truncating inside a preview
    /// first would cut a @<guid> token (37 chars) that straddles the 200-char
    /// boundary before it is resolved, leaving a raw fragment on the lock screen. So
    /// the previews pass an effectively-unbounded length; the streamed plainText/
    /// markdown path already seeds the accumulator with the raw untruncated text, and
    /// this keeps the multipart / attachment / request paths consistent with it.
    private static let untruncatedPreviewLength = Int.max

    /// A user-facing one-line preview of a streamed attachment, plus its label-ness
    /// (a "📄 name" file label vs real .code text), from one walk. Ephemeral
    /// reasoning/status is excluded (returns "") so a reasoning-only streamed turn's
    /// notification isn't the "Thinking…" text - matching the whole-message path.
    private static func attachmentPreview(_ attachment: LLM.Message.Attachment) -> (text: String, isLabel: Bool) {
        // Map the single attachment subpart directly (no throwaway multipart Content
        // allocated per streamed delta), applying the same substance policy the
        // whole-message path uses: Subpart.hasDisplayableSubstance already encodes
        // "a statusUpdate / empty .code is not a preview", so a non-substantive
        // subpart yields ("", false) and the trigger's empty guard suppresses the
        // fire - without re-implementing the statusUpdate rule here.
        let sub = Message.Subpart.attachment(attachment)
        guard sub.hasDisplayableSubstance else { return ("", false) }
        return sub.previewAndLabel(maxLength: untruncatedPreviewLength) ?? ("", false)
    }

    /// The user-facing preview for an agent REPLY, matching the bubble the user
    /// will see, plus whether that preview is a rendered ATTACHMENT LABEL ("📄
    /// name") rather than real text - both from ONE walk (previewAndLabel) so the
    /// preview and its flag can't drift. isLabel drives whether a following streamed
    /// text delta REPLACES the preview (a label) or extends it (real text).
    ///
    /// Strips ephemeral reasoning/status subparts first, then returns ("", false)
    /// for substance-free content so the trigger's empty guard suppresses the fire
    /// (rather than showing a placeholder).
    private static func replyPreview(for message: Message) -> (text: String, isLabel: Bool) {
        var cleaned = message
        cleaned.removeReasoningStatusSubparts()
        guard cleaned.content.hasDisplayableSubstance else { return ("", false) }
        return cleaned.content.previewAndLabel(maxLength: untruncatedPreviewLength)
            ?? (cleaned.content.shortDescription, false)
    }

    /// Description of a block-on-user request (remote command / select session)
    /// for its notification body. Unlike replyPreview this is NOT gated on
    /// hasDisplayableSubstance (which is false for requests) - the request
    /// description IS the substance here.
    private static func requestDescription(for content: Message.Content) -> String {
        content.snippetText(maxLength: untruncatedPreviewLength) ?? content.shortDescription
    }

    /// Agent typing changed for the watched chat. On a mac BELOW
    /// turnLifecycleRevision (which sends no explicit turn-lifecycle event) the
    /// typing edge IS the turn boundary, so translate it: turnStarted resets the
    /// accumulation, turnEnded may fire. On a turnLifecycleRevision mac, boundaries
    /// come from the turnLifecycle message (noteWatchedTurnLifecycle) and typing is
    /// only the spinner - so it must NOT drive the trigger here, or a mid-turn park
    /// (which toggles typing for the spinner) would be misread as a turn boundary.
    /// The trigger is fed turn boundaries from exactly ONE source, keyed on
    /// macRevision.
    private func noteWatchedTypingStatus(isTyping: Bool, chatID: String) {
        guard !usesTurnLifecycleBoundaries() else { return }
        guard let watched = watchState.watch, chatID == watched.chatID else { return }
        applyReplyTrigger(isTyping ? .turnStarted : .turnEnded, watched: watched)
    }

    /// Accept an explicit turn-lifecycle boundary from the wire. Gated so it drives
    /// the trigger ONLY when both ends use turnLifecycle - the exact complement of
    /// the typing gate in noteWatchedTypingStatus, so the trigger is fed by one
    /// source, never both. Shared by the wire handler (handle(.turnLifecycle)) and
    /// the test hook so tests exercise THIS production gate, not a copy of it.
    private func acceptTurnLifecycle(_ event: TurnEvent, chatID: String) {
        guard usesTurnLifecycleBoundaries() else { return }
        noteWatchedTurnLifecycle(event, chatID: chatID)
    }

    /// An explicit agent-turn boundary arrived (a turnLifecycleRevision mac). This
    /// is the authoritative turn-start/-end signal that replaces typing-edge
    /// inference; feed it straight to the trigger.
    private func noteWatchedTurnLifecycle(_ event: TurnEvent, chatID: String) {
        guard let watched = watchState.watch, chatID == watched.chatID else { return }
        switch event {
        case .started: applyReplyTrigger(.turnStarted, watched: watched)
        case .ended: applyReplyTrigger(.turnEnded, watched: watched)
        case .unknownFuture: break
        }
    }

    private func applyReplyTrigger(_ event: SessionReplyTrigger.Event, watched: SessionWatchState.Watch) {
        // Suppression is passed INTO the trigger so a fire suppressed for visibility
        // does not latch (burn the turn's one-fire opportunity / mark text
        // notified): if the user later navigates away, a subsequent off-screen
        // message in the same turn can still fire. If the watched chat is the
        // visible top view, the user sees the reply land live via apply(), so a
        // notification would be redundant. (The @-mention case, where the session
        // view covers the conversation, is NOT the visible top, so it still fires.)
        let shouldFire: (String) -> Bool = { _ in
            // Suppress ONLY when the reply is actually being seen live: the chat is
            // the visible-top conversation AND the app is foreground+active. When
            // backgrounded/locked the nav position is unchanged but nothing is on
            // screen, so a reply that lands in the still-connected window must still
            // notify (don't rely on the APNs/NSE path covering it).
            let active = UIApplication.shared.applicationState == .active
            let suppress = active && self.isWatchedChatVisibleTop(watched)
            if suppress {
                companionLog("Reply for visible chat \(watched.chatID); shown live, not notifying")
            }
            return !suppress
        }
        if case .fire(let body) = replyTrigger.handle(event, shouldFire: shouldFire) {
            #if DEBUG
            testLastReplyFireBody = body
            #endif
            postReplyNotification(watched: watched, body: body)
        }
    }

    private func isWatchedChatVisibleTop(_ watched: SessionWatchState.Watch) -> Bool {
        // Whether the watched chat is the conversation on top of the CURRENTLY
        // selected tab (independent of watched.tab - the chat can be mounted on
        // both, and the user may be reading it on the other tab where apply()
        // already renders the reply live).
        activePath.last?.conversationID == watched.chatID
    }

    /// Replace raw @<guid> mention tokens with the resolved entity name (with the
    /// terminal glyph) for a PLAIN-TEXT context (the notification body). Delegates
    /// to the SAME shared renderer the push/NSE preview path uses, so the two
    /// lock-screen notification paths agree for a given mention (both show
    /// "🖥 name", not one bare and one prefixed) and there's a single copy of the
    /// parse-and-replace loop.
    private func renderMentionsPlainText(_ text: String) -> String {
        MentionPlainTextRenderer.render(text) { mentionResolutions[$0]?.displayName }
    }

    private func postReplyNotification(watched: SessionWatchState.Watch, body: String) {
        // Belt-and-suspenders: never post for a chat that no longer exists (the tap
        // handler would refuse to navigate to it). The watch is torn down on
        // deletion, but a delivery could race that teardown. One lookup for both the
        // existence check and the title (no double scan / divergence).
        guard let entry = chat(for: watched.chatID) else {
            companionLog("Skipping reply notification for missing chat \(watched.chatID)")
            return
        }
        let chatTitle = entry.chat.title
        let content = UNMutableNotificationContent()
        content.title = chatTitle
        // Render @-mentions to names BEFORE truncating (matching the push path),
        // so the lock screen shows a readable name, not a raw @<guid>.
        content.body = renderMentionsPlainText(body)
            .truncatedWithTrailingEllipsis(to: Self.notificationBodyMaxLength)
        content.sound = .default
        content.threadIdentifier = "sessionchat-\(watched.chatID)"
        content.userInfo = [
            Self.sessionChatNavKey: watched.chatID,
            Self.sessionChatTabKey: watched.tab.rawValue,
        ]
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        companionLog("Posting reply notification for chat \(watched.chatID) tab=\(watched.tab.rawValue) (\(body.count) chars)")
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                companionLog("Failed to post session reply notification: \(String(describing: error))")
            }
        }
    }

    /// A tap on a session-view reply notification: push the chat onto the tab the
    /// originating session view lives on (above the session), so Back returns the
    /// user to that session view rather than the home screen. On a cold launch
    /// the home screen isn't up yet (and loadHome clears the nav paths), so defer
    /// the tap until phase == .home.
    func handleSessionChatNotificationTap(chatID: String, tab: AppTab) {
        guard phase == .home else {
            companionLog("Reply-notification tap before home; deferring nav to \(chatID)")
            pendingSessionChatNav = (chatID, tab)
            return
        }
        // The chat may have been deleted on the Mac since the notification was
        // posted (a stale tap, or a cold-launch replay of an old one). `chats` is
        // authoritative here - refreshLists runs before any deferred replay, and
        // live taps keep it fresh - so silently ignore the tap rather than
        // navigating to a broken/empty "Could not load this chat".
        guard chatExists(chatID) else {
            companionLog("Ignoring reply-notification tap for missing chat \(chatID)")
            return
        }
        handOffWatchedChatIfOpening(chatID)
        // Bind the target stack once so the read and the write can't drift to
        // different stacks.
        let stack: ReferenceWritableKeyPath<AppModel, [Destination]> =
            (tab == .chats) ? \.navigationPath : \.sessionsPath
        // Put the chat on top exactly once, keeping any session view below it so
        // Back returns to the session view. If it's already mounted (the
        // @-mention case, sitting below the session), remove that copy first so
        // there's no duplicate.
        switch SessionNavOpen.action(forOpening: chatID, in: self[keyPath: stack].map(\.conversationID)) {
        case .noChange:
            break
        case .moveToTop(let removeIndices):
            var newStack = self[keyPath: stack]
            for index in removeIndices.sorted(by: >) {
                newStack.remove(at: index)
            }
            newStack.append(.conversation(chatID: chatID))
            self[keyPath: stack] = newStack
        }
        // Switch to the target tab AFTER mutating its stack, so the single
        // resulting selectedTab.didSet sync runs against the final stack (not the
        // pre-push one, which would load the wrong conversation first).
        selectedTab = tab
    }

    /// Replay a reply-notification tap that arrived during launch, once home is
    /// up. Called at the end of loadHome.
    private func applyPendingSessionChatNav() {
        guard phase == .home, let pending = pendingSessionChatNav else { return }
        pendingSessionChatNav = nil
        companionLog("Applying deferred reply-notification nav to \(pending.chatID)")
        handleSessionChatNotificationTap(chatID: pending.chatID, tab: pending.tab)
    }

    // MARK: Interactive message responses

    /// "Select a Session" on a selectSessionRequest bubble: refresh the list
    /// and put up the picker sheet.
    func beginSelectSession(requestMessage: Message, original: Message, terminal: Bool) {
        sessionPicker = SessionPickerRequest(requestMessageID: requestMessage.uniqueID,
                                             originalMessage: original,
                                             terminal: terminal)
        Task {
            try? await refreshLists()
        }
    }

    /// Completes a selectSessionRequest, from the sheet (guid set) or the
    /// bubble's Cancel button (guid nil).
    func respondSelectSession(requestMessageID: UUID,
                              original: Message,
                              terminal: Bool,
                              guid: String?) {
        sessionPicker = nil
        guard let chatID = openChatID else { return }
        respondedInteractiveMessageIDs.insert(requestMessageID)
        companionLog("Select-session response: \(guid ?? "declined")")
        Task {
            do {
                let client = try await currentClient(label: "Select session")
                try await client.sendSelectSessionResponse(chatID: chatID,
                                                           originalMessage: original,
                                                           sessionGuid: guid,
                                                           terminal: terminal)
            } catch {
                companionLog("Select-session response failed: \(String(describing: error))")
            }
        }
    }

    func respondRemoteCommand(requestMessage: Message, decision: CompanionRemoteCommandDecision) {
        guard let chatID = openChatID else { return }
        respondedInteractiveMessageIDs.insert(requestMessage.uniqueID)
        companionLog("Remote command decision: \(decision.rawValue)")
        Task {
            do {
                let client = try await currentClient(label: "Command decision")
                try await client.sendRemoteCommandDecision(chatID: chatID,
                                                           messageUniqueID: requestMessage.uniqueID,
                                                           decision: decision)
            } catch {
                companionLog("Command decision failed: \(String(describing: error))")
            }
        }
    }

    /// Approve/Deny on a workgroup permission request, and Enable/Not Now on
    /// an orchestration request: both are plain user-authored publishes, the
    /// same thing the Mac UI sends.
    func respondUserCommand(requestMessage: Message, command: UserCommand) {
        guard let chatID = openChatID else { return }
        respondedInteractiveMessageIDs.insert(requestMessage.uniqueID)
        companionLog("User command response: \(command)")
        let response = Message(chatID: chatID,
                               author: .user,
                               content: .userCommand(command),
                               sentDate: Date(),
                               uniqueID: UUID())
        Task {
            do {
                let client = try await currentClient(label: "Interactive response")
                try await client.publish(response, toChatID: chatID)
            } catch {
                companionLog("User command response failed: \(String(describing: error))")
            }
        }
    }

    /// The Link button on an offerLink bubble.
    func linkSession(requestMessage: Message, guid: String, terminal: Bool) {
        guard let chatID = openChatID else { return }
        respondedInteractiveMessageIDs.insert(requestMessage.uniqueID)
        Task {
            do {
                let client = try await currentClient(label: "Link session")
                try await client.sendLinkSession(chatID: chatID, sessionGuid: guid, terminal: terminal)
            } catch {
                companionLog("Link session failed: \(String(describing: error))")
            }
        }
    }

    // MARK: Push notifications

    // The permission prompt is never shown spontaneously: it appears just in
    // time, when the orchestrator calls its request_notification_permission
    // tool because the user asked to be alerted about something. Connects
    // only REPORT the current state (the user can revoke in Settings between
    // connections).

    private static let pushTokenDefault = "NoSyncPushDeviceToken"

    /// A debug build's APNs token belongs to the sandbox environment; the
    /// relay must use the matching endpoint.
#if DEBUG
    private static let pushSandbox = true
#else
    private static let pushSandbox = false
#endif

    /// The last APNs device token iOS issued. Persisted so connect-time
    /// status reports can carry it before re-registration completes.
    private var storedPushToken: Data? {
        get { UserDefaults.standard.data(forKey: Self.pushTokenDefault) }
        set { UserDefaults.standard.set(newValue, forKey: Self.pushTokenDefault) }
    }

    private static func authorization(from status: UNAuthorizationStatus) -> CompanionPushAuthorization {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    /// Report the phone's push capability to the Mac. Called after every
    /// connection; when authorized it also refreshes the APNs token (whose
    /// arrival triggers a follow-up report carrying it).
    private func reportPushStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let authorization = Self.authorization(from: settings.authorizationStatus)
            if authorization == .authorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
            await sendPushStatus(authorization)
        }
    }

    private func sendPushStatus(_ authorization: CompanionPushAuthorization) async {
        guard let client else { return }
        var token: Data?
        var secret: Data?
        if authorization == .authorized, let storedPushToken {
            token = storedPushToken
            secret = try? PhoneIdentity.pushRelaySecret()
        }
        do {
            try await client.sendPushStatus(authorization: authorization,
                                            token: token,
                                            relaySecret: secret,
                                            sandbox: Self.pushSandbox)
            companionLog("Push status sent: \(authorization.rawValue) (token: \(token != nil))")
        } catch {
            companionLog("Push status send failed: \(String(describing: error))")
        }
    }

    /// The app delegate received (or refreshed) the APNs token: register its
    /// secret hash with the push relay, then report to the Mac.
    func pushTokenDidChange(_ token: Data) {
        storedPushToken = token
        Task {
            await registerWithPushRelay(token: token)
            await sendPushStatus(.authorized)
        }
    }

    private func registerWithPushRelay(token: Data) async {
        struct Registration: Encodable {
            var token: String
            var secretHash: String
            var sandbox: Bool
        }
        guard let secret = try? PhoneIdentity.pushRelaySecret() else {
            companionLog("Push relay registration skipped: no secret")
            return
        }
        var request = URLRequest(url: CompanionPushRelay.registerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(CompanionUserAgent.value, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let secretHash = SHA256.hash(data: secret).map { String(format: "%02x", $0) }.joined()
        do {
            request.httpBody = try JSONEncoder().encode(
                Registration(token: token.map { String(format: "%02x", $0) }.joined(),
                             secretHash: secretHash,
                             sandbox: Self.pushSandbox))
            let (data, response) = try await CompanionURLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                companionLog("Registered with push relay")
            } else {
                companionLog("Push relay registration rejected: \(String(data: data, encoding: .utf8) ?? "")")
            }
        } catch {
            companionLog("Push relay registration failed: \(String(describing: error))")
        }
    }

    /// The Mac asked (on the orchestrator's behalf) to show iOS's
    /// notification-permission prompt. Replies with the outcome; a grant is
    /// followed by a pushStatus carrying the token once APNs issues it.
    private func handleNotificationPermissionRequest(requestID: UInt64) {
        companionLog("Received notification-permission request \(requestID)")
        ensureNotificationPermission(replyTo: requestID)
    }

    /// Observer token for a deferred prompt; non-nil means we're waiting for the app
    /// to become active before showing the iOS notification prompt.
    private var becomeActiveObserver: NSObjectProtocol?

    /// Ask iOS for notification permission when it makes sense, robustly:
    ///  - already decided (authorized/denied): just report (and register if granted);
    ///  - undetermined + app ACTIVE: show the prompt now;
    ///  - undetermined + app NOT active (e.g. a background reconnect delivered the
    ///    request): DEFER and show it the next time the app becomes active, so the
    ///    prompt never depends on the request happening to land while foreground.
    /// `replyTo` answers the orchestrator's request-id flow; nil for the hello flow.
    private func ensureNotificationPermission(replyTo requestID: UInt64?) {
        Task { await ensureNotificationPermissionImpl(replyTo: requestID) }
    }

    private func ensureNotificationPermissionImpl(replyTo requestID: UInt64?) async {
        let center = UNUserNotificationCenter.current()
        var authorization = Self.authorization(from: await center.notificationSettings().authorizationStatus)
        companionLog("ensureNotificationPermission: status=\(authorization.rawValue), "
            + "appState=\(UIApplication.shared.applicationState.rawValue)")
        if authorization == .notDetermined {
            guard UIApplication.shared.applicationState == .active else {
                companionLog("App not active; deferring notification prompt to next foreground")
                scheduleNotificationPromptOnNextActive()
                if let requestID, let client {
                    try? await client.sendNotificationPermissionResponse(requestID: requestID,
                                                                         authorization: .notDetermined)
                }
                return
            }
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            authorization = granted ? .authorized : .denied
            companionLog("Notification permission prompt answered: \(authorization.rawValue)")
        }
        if authorization == .authorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
        if let requestID, let client {
            try? await client.sendNotificationPermissionResponse(requestID: requestID,
                                                                 authorization: authorization)
        }
        await sendPushStatus(authorization)
    }

    private func scheduleNotificationPromptOnNextActive() {
        guard becomeActiveObserver == nil else { return }
        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let observer = self.becomeActiveObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.becomeActiveObserver = nil
                }
                await self.ensureNotificationPermissionImpl(replyTo: nil)
            }
        }
    }

    // MARK: Mentions

    /// The visible texts of a message that can contain @-mentions.
    private func mentionableTexts(of message: Message) -> [String] {
        switch message.content {
        case .plainText(let text, _):
            return [text]
        case .markdown(let text):
            return [text]
        case .multipart(let subparts, _):
            return subparts.compactMap {
                switch $0 {
                case .plainText(let text): return text
                case .markdown(let text): return text
                case .attachment, .context: return nil
                }
            }
        case .explanationResponse(let response, _, let markdown):
            return [markdown.isEmpty ? (response.mainResponse ?? "") : markdown]
        case .remoteCommandRequest(let payload, _):
            // MessageBubbleView renders this bubble's description with
            // textWithMentions (both the classic and orchestration branches
            // resolve to payload.markdownDescription), so its mentions must be
            // scanned here too or they never get resolved and stay raw.
            return [payload.markdownDescription]
        default:
            return []
        }
    }

    /// Scan messages for mentions and ask the Mac to resolve any we have not
    /// seen yet. Resolutions land in `mentionResolutions`, which re-renders
    /// the bubbles that reference them.
    private func noteMentions(in messages: [Message]) {
        noteMentions(inTexts: messages.flatMap { mentionableTexts(of: $0) })
    }

    private func noteMentions(inTexts texts: [String]) {
        let identifiers = Set(texts
            .flatMap { MentionParser.mentions(in: $0) }
            .map { $0.identifier })
        // Skip ids we already resolved, have a request in flight for, or tried
        // and failed (the retry gate). Everything else gets requested.
        let toRequest = identifiers.filter {
            mentionResolutions[$0] == nil
                && !mentionResolutionsInFlight.contains($0)
                && !unresolvedMentions.contains($0)
        }
        guard !toRequest.isEmpty else { return }
        mentionResolutionsInFlight.formUnion(toRequest)
        companionLog("Resolving \(toRequest.count) mention(s)")
        Task {
            do {
                let client = try await currentClient(label: "Resolve mentions")
                let resolutions = try await client.resolveMentions(Array(toRequest))
                let byIdentifier = Dictionary(
                    resolutions.map { ($0.identifier, $0) },
                    uniquingKeysWith: { _, last in last })
                for id in toRequest {
                    // Cache only a real hit (a live name). A miss (nil
                    // displayName, or no entry returned at all) goes to the
                    // retry gate so a later trigger can ask again, rather than
                    // caching an unresolved id and rendering a raw @UUID forever.
                    if let resolution = byIdentifier[id], resolution.displayName != nil {
                        mentionResolutions[id] = resolution
                    } else {
                        unresolvedMentions.insert(id)
                    }
                }
            } catch {
                // The whole batch failed (Mac unreachable). Gate them so we
                // don't fire a fresh request on every delivery; a reconnect or
                // chat open clears the gate and retries.
                companionLog("Mention resolution failed: \(String(describing: error))")
                unresolvedMentions.formUnion(toRequest)
            }
            mentionResolutionsInFlight.subtract(toRequest)
        }
    }

    /// Reopen the retry gate so mentions that failed to resolve earlier (Mac was
    /// down, or a session was still launching) get another attempt. The re-scan
    /// itself is done by the caller's own noteMentions pass that follows.
    private func retryUnresolvedMentions() {
        unresolvedMentions.removeAll()
    }

    /// A chat-list snippet, ready to display: inline markdown rendered (so
    /// **bold** is bold) and @-mentions replaced with the live entity name
    /// (plain text, not a link; the row itself is the tap target).
    func renderedSnippet(_ snippet: String) -> AttributedString {
        var attributed = (try? AttributedString(
            markdown: snippet,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(snippet)
        let plain = String(attributed.characters)
        // Replace back to front so earlier ranges stay valid.
        for mention in MentionParser.mentions(in: plain).reversed() {
            guard let resolution = mentionResolutions[mention.identifier],
                  let range = Range(mention.range, in: attributed) else {
                continue
            }
            attributed.replaceSubrange(
                range,
                with: AttributedString(resolution.displayName ?? "[defunct session]"))
        }
        return attributed
    }

    // MARK: Session content

    func sessionScreenInfo(guid: String) async throws -> CompanionSessionScreenInfo {
        let client = try await currentClient(label: "Session info")
        return try await withTimeout(15, "Loading session info") {
            try await client.sessionScreenInfo(guid: guid)
        }
    }

    func sessionContent(guid: String, firstLine: Int, lineCount: Int) async throws -> CompanionSessionContent {
        let client = try await currentClient(label: "Session content")
        return try await withTimeout(20, "Loading session content") {
            try await client.sessionContent(guid: guid, firstLine: firstLine, lineCount: lineCount)
        }
    }

    func workgroupInfo(id: String) async throws -> CompanionWorkgroupInfo {
        let client = try await currentClient(label: "Workgroup info")
        return try await withTimeout(15, "Loading workgroup info") {
            try await client.workgroupInfo(id: id)
        }
    }

    // MARK: Host events

    private func handle(event: CompanionHostMessage) {
        switch event {
        case .delivery(let message, let chatID, _):
            if !message.hiddenFromClient {
                if chatID == openChatID {
                    apply(message)
                } else if transcriptCache[chatID] != nil {
                    // A co-mounted-but-hidden chat that was previously OPEN (so its
                    // cache is a full snapshot): merge the delivery so a switch-back
                    // shows this reply. Only merge into an EXISTING entry - seeding a
                    // fresh 1-message entry for a mounted-but-never-opened chat would
                    // be served by conversationDidAppear as the WHOLE conversation
                    // (missing all history). Such a chat instead refetches full
                    // history on switch-to, and the delivery still fires its watch
                    // notification. removeValue detaches so the in-place append is
                    // amortized O(1) (no COW deep copy per streamed delta).
                    var cached = transcriptCache.removeValue(forKey: chatID) ?? []
                    apply(message, into: &cached, chatID: chatID)
                    transcriptCache[chatID] = cached
                }
            }
            // The live session view may be watching a chat (its own or the one
            // an @-mention came from). Accumulate the agent's reply text; the
            // notification fires when the turn completes - on a turnLifecycleRevision
            // mac from the explicit .turnLifecycle(.ended) boundary, on an older mac
            // from the typing(false) edge (noteWatchedTypingStatus translates it).
            // Typing is spinner-only on a turnLifecycleRevision mac, so do NOT
            // re-route the fire back through typing edges.
            noteWatchedSessionDelivery(message, chatID: chatID)
        case .typingStatus(let isTyping, let participant, let chatID):
            if participant == .agent {
                // Track per-chat so re-selecting a co-mounted chat mid-turn (a tab
                // switch, which doesn't re-deliver this edge-triggered status) still
                // shows the indicator. isAgentTyping is derived from this set. This
                // is the spinner hint; the reply-notification turn boundary comes
                // from typing only on a pre-turnLifecycle mac (noteWatchedTypingStatus
                // gates on macRevision), else from .turnLifecycle below.
                if isTyping { agentTypingChats.insert(chatID) } else { agentTypingChats.remove(chatID) }
                noteWatchedTypingStatus(isTyping: isTyping, chatID: chatID)
            }
        case .turnLifecycle(let event, let chatID):
            acceptTurnLifecycle(event, chatID: chatID)
        case .chatListChanged(let entries):
            // The Mac pushes a fresh list whenever a chat is renamed, gets
            // its icon, or is created/deleted/reordered.
            chats = entries
            // Evict cached transcripts for chats deleted on the Mac, so a later
            // delivery can't merge into a stale snapshot (deleteChat evicts the
            // local-delete path; this covers the remote-delete path).
            pruneStateForLiveChats(Set(entries.map { $0.chat.id }))
            noteMentions(inTexts: entries.compactMap { $0.snippet })
            checkOpenChatStillExists()
        case .requestNotificationPermission(let requestID):
            handleNotificationPermissionRequest(requestID: requestID)
        case .unpaired:
            handleRemoteUnpair()
        case .streamConfig(let config):
            if config.streamID == activeStreamID {
                activeStreamGeometry = config.cellGeometry
                activeStreamImageSize = CGSize(width: config.pixelWidth, height: config.pixelHeight)
                activeStreamColumns = config.columns
                activeStreamRows = config.rows
                activeStreamFirstAbsLine = config.firstAbsLine
                activeStreamTotalLines = config.totalLines
                // Absent (older mac) means unknown; default to allowing resize since
                // the resize control is gated on the mac's revision anyway.
                activeStreamCanResize = config.canResize ?? true
                // A new generation re-renders everything; stale tiles must not show.
                if config.generationId != activeStreamGeneration {
                    // Not the first config for this stream = a mid-stream geometry
                    // change (e.g. column reflow), which renumbers absolute lines and
                    // invalidates the current selection's coordinates. Drop it; the
                    // mac re-pushes the reflowed selection. The first config keeps any
                    // pre-existing selection couriered on subscribe.
                    let isInitialConfig = activeStreamGeneration == 0
                    activeStreamGeneration = config.generationId
                    historyTileCache.removeAll()
                    // A reflow renumbers absolute lines, so every queued/in-flight tile
                    // request is now stale. Neutralize the throttle (drop the queue,
                    // cancel in-flight fetches, nudge a re-drive) so we do not send up to
                    // maxHistoryTilesPending doomed requests to the relay; applyLayout
                    // re-requests fresh tiles for the new generation.
                    flushHistoryTileThrottle()
                    // Snap the live top to the new extent so a stale (pre-reflow)
                    // value does not inflate the canvas until the next media frame.
                    activeStreamLiveTop = config.firstAbsLine + Int64(max(0, config.totalLines - config.rows))
                    if !isInitialConfig {
                        activeSelectionRange = nil
                    }
                }
                onStreamConfig?(config)
            }
        case .streamExtent(let streamID, let firstAbsLine, let totalLines):
            if streamID == activeStreamID,
               firstAbsLine != activeStreamFirstAbsLine || totalLines != activeStreamTotalLines {
                let shrank = totalLines < activeStreamTotalLines
                activeStreamFirstAbsLine = firstAbsLine
                activeStreamTotalLines = totalLines
                if shrank {
                    // Cleared/reset: the content at existing absolute lines changed
                    // and the (pre-clear) live top is now stale, which would inflate
                    // the canvas until the next frame. Snap the live top to the new
                    // extent and drop every cached tile.
                    activeStreamLiveTop = firstAbsLine + Int64(max(0, totalLines - activeStreamRows))
                    historyTileCache.removeAll()
                } else {
                    // Trimmed: only lines below the new origin are gone.
                    historyTileCache.removeAll(where: { $0 < firstAbsLine })
                }
            }
        case .selectionRange(let streamID, let range):
            if streamID == activeStreamID {
                activeSelectionRange = range
            }
        case .streamEnded(let streamID, let reason):
            if streamID == activeStreamID {
                // A host-side end is a stream transition like the others: neutralize the
                // throttle (releasing slots, cancelling fetches) before dropping the id so
                // a late reply cannot be cached against the next stream.
                neutralizeDeadStream()
                activeStreamGeometry = nil
                activeSelectionRange = nil
                // A host-side end is terminal: drop the intent so it does not
                // restart, and tell the view (which shows it only for reasons
                // worth surfacing, e.g. the session closed).
                liveWatchGuid = nil
                onStreamEnded?(reason)
            }
        default:
            break
        }
    }

    // MARK: Live session streaming

    private func handleStreamMedia(_ frame: CompanionMediaFrame) {
        guard frame.streamID == activeStreamID else { return }
        // Track the top visible line so a touch maps to the right absolute line.
        activeStreamLiveTop = frame.liveTop
        onStreamMedia?(frame)
    }

    private func clearStreamHandlers() {
        onStreamConfig = nil
        onStreamMedia = nil
        onStreamEnded = nil
    }

    /// Express intent to watch a session live. The handlers receive the stream
    /// config (parameter sets + geometry), each media frame, and a terminal end
    /// event. The stream starts when the connection is ready and restarts after a
    /// reconnect; a not-yet-connected state is NOT an error (no onEnded fires).
    func watchSessionLive(guid: String,
                          onConfig: @escaping (CompanionStreamConfig) -> Void,
                          onMedia: @escaping (CompanionMediaFrame) -> Void,
                          onEnded: @escaping (CompanionStreamEndReason) -> Void) {
        liveWatchGuid = guid
        liveStreamPaused = false
        // A session switch reuses the same live connection, so any in-flight or queued
        // tile requests belong to the previous session; neutralize the throttle before
        // the new stream starts issuing requests.
        flushHistoryTileThrottle()
        // Drop the previous session's geometry/extent so the canvas waits for the
        // new config before laying out (streamExtent can arrive first); otherwise it
        // would briefly fetch tiles against stale geometry.
        historyTileCache.removeAll()
        activeStreamGeometry = nil
        activeStreamImageSize = .zero
        activeStreamColumns = 0
        activeStreamRows = 0
        activeStreamLiveTop = 0
        activeStreamFirstAbsLine = 0
        activeStreamTotalLines = 0
        activeStreamCanResize = true
        activeStreamGeneration = 0
        activeSelectionRange = nil
        onStreamConfig = onConfig
        onStreamMedia = onMedia
        onStreamEnded = onEnded
        startLiveStreamIfPossible()
    }

    /// Drop the live-watch intent and stop any running stream (on leaving the view).
    func stopWatchingSessionLive() {
        liveWatchGuid = nil
        flushHistoryTileThrottle()
        stopActiveStream()
        clearStreamHandlers()
    }

    /// Backgrounded: keep the intent but stop the running stream so the Mac stops
    /// encoding while the phone can't display anything.
    func pauseLiveStream() {
        liveStreamPaused = true
        flushHistoryTileThrottle()
        stopActiveStream()
    }

    /// Foregrounded: resume if a live view is still open. Safe if not connected
    /// yet (the reconnect path will start it).
    func resumeLiveStream() {
        liveStreamPaused = false
        startLiveStreamIfPossible()
    }

    /// Start the live stream for the watched session if everything is ready;
    /// otherwise a no-op (a later reconnect/resume retries). Never surfaces a
    /// transient failure as a stream end.
    private func startLiveStreamIfPossible() {
        guard let guid = liveWatchGuid, !liveStreamPaused, macSupportsStreaming,
              activeStreamID == nil, !liveStreamStarting, let client else {
            return
        }
        liveStreamStarting = true
        let params = CompanionStreamParams(supportedCodecs: [.hevc], maxFrameRate: 30, maxBitrate: nil,
                                           maxMediaFrameVersion: 2)
        Task { @MainActor in
            do {
                let started = try await client.startSessionStream(guid: guid, params: params)
                // Guard against races: the view may have closed, the app may have
                // paused, or a reconnect may have superseded this attempt.
                if liveWatchGuid == guid, !liveStreamPaused, activeStreamID == nil {
                    activeStreamID = started.streamID
                    companionLog("phone stream STARTED id=\(started.streamID) guid=\(guid)")
                } else {
                    try? await client.stopSessionStream(streamID: started.streamID)
                }
            } catch {
                companionLog("startSessionStream failed (will retry on reconnect/resume): \(String(describing: error))")
            }
            liveStreamStarting = false
            // If the live intent moved to a DIFFERENT session while this attempt was
            // in flight (superseded, or it failed and the user switched sessions),
            // drive the new intent now instead of stranding it until the next
            // reconnect/resume. Comparing against the attempted guid avoids a tight
            // retry loop when the same session persistently fails to start.
            if let current = liveWatchGuid, current != guid, activeStreamID == nil {
                startLiveStreamIfPossible()
            }
        }
    }

    /// Tell the connected Mac to stop the active stream and forget its id. Keeps
    /// the watch intent so it can restart.
    private func stopActiveStream() {
        guard let streamID = activeStreamID else { return }
        activeStreamID = nil
        guard let client else { return }
        Task { try? await client.stopSessionStream(streamID: streamID) }
    }

    /// Called after a (re)connect completes so an open live view resumes.
    private func restartLiveStreamAfterReconnect() {
        // A new connection means the old stream id is dead; neutralize the throttle
        // (its in-flight/queued requests are stale) and drop the id.
        neutralizeDeadStream()
        // The new stream's generations restart at 1; treat its first config as
        // initial (not a mid-stream reflow). Otherwise a stale generation from the
        // old stream could wipe the selection the mac couriers on subscribe, and a
        // coincidentally-equal one would skip the tile-cache clear even though
        // content may have changed while offline.
        activeStreamGeneration = 0
        historyTileCache.removeAll()
        startLiveStreamIfPossible()
    }

    /// Ask the Mac for a fresh keyframe (on resume, or after a decode error).
    func requestActiveStreamKeyframe() {
        guard let client, let streamID = activeStreamID else { return }
        Task { try? await client.requestStreamKeyframe(streamID: streamID) }
    }

    /// Report flow-control feedback for the active stream.
    func sendActiveStreamAck(lastPTSMilliseconds: UInt64, queueDepth: Int) {
        guard let client, let streamID = activeStreamID else { return }
        Task {
            try? await client.sendStreamAck(streamID: streamID,
                                            lastPTSMilliseconds: lastPTSMilliseconds,
                                            queueDepth: queueDepth)
        }
    }

    /// A mapper for the current stream geometry, or nil if selection is not
    /// available yet.
    private var activeTouchMapper: CompanionTouchMapper? {
        guard let geometry = activeStreamGeometry else { return nil }
        return CompanionTouchMapper(imageSize: activeStreamImageSize,
                                    cellGeometry: geometry,
                                    columns: activeStreamColumns,
                                    rows: activeStreamRows,
                                    liveTop: activeStreamLiveTop)
    }

    /// View-space points for the selection's start (top-left) and end
    /// (bottom-right) handles, or nil if there is no selection/geometry.
    func selectionHandlePoints(viewSize: CGSize) -> (start: CGPoint, end: CGPoint)? {
        guard let range = activeSelectionRange, let mapper = activeTouchMapper,
              let start = mapper.viewPoint(column: range.start.column, absLine: range.start.absLine,
                                           rightEdge: false, bottomEdge: false, viewSize: viewSize),
              let end = mapper.viewPoint(column: range.end.column, absLine: range.end.absLine,
                                         rightEdge: true, bottomEdge: true, viewSize: viewSize) else {
            return nil
        }
        return (start, end)
    }

    /// Drive a live-view selection from a touch at `viewPoint` in a view of
    /// `viewSize`, mapping it to an absolute terminal point with the current
    /// stream geometry. No-op if selection is not supported.
    func sendSelectionGesture(phase: CompanionSelectionPhase,
                              mode: CompanionSelectionMode,
                              viewPoint: CGPoint,
                              viewSize: CGSize) {
        guard let mapper = activeTouchMapper else { return }
        sendSelectionGesture(phase: phase, mode: mode,
                             point: mapper.selectionPoint(viewPoint: viewPoint, viewSize: viewSize))
    }

    /// Drive a selection with an explicit absolute point (used to anchor a handle
    /// drag at the opposite, fixed endpoint).
    func sendSelectionGesture(phase: CompanionSelectionPhase,
                              mode: CompanionSelectionMode,
                              point: CompanionSelectionPoint) {
        guard let client, let streamID = activeStreamID else { return }
        // Coalesce: a drag fires a touch event per frame, but the selection only
        // changes when the mapped CELL changes. Sending a move per event (often
        // the same cell) floods the link in both directions (the move, plus the
        // mac's selectionRange reply) and backs it up for seconds. Drop a .move
        // whose cell is unchanged; begin/end always go.
        if phase == .move && point == lastSentSelectionPoint { return }
        lastSentSelectionPoint = (phase == .end) ? nil : point
        sendOrderedSelection {
            try? await client.sendSelectionGesture(streamID: streamID, phase: phase, mode: mode, point: point)
        }
    }
    private var lastSentSelectionPoint: CompanionSelectionPoint?

    /// Serialize selection sends. A drag fires begin/move/move/.../end in quick
    /// succession; wrapping each in its own Task does NOT preserve order, so the
    /// opening .begin (anchor) could reach the mac after the first .move and the
    /// move would be lost (the symptom: the selection only updates after a
    /// "jiggle" produces a later move). Chaining each send after the previous one
    /// guarantees in-order delivery.
    private var lastSelectionSend: Task<Void, Never>?
    private func sendOrderedSelection(_ operation: @escaping () async -> Void) {
        let previous = lastSelectionSend
        lastSelectionSend = Task {
            await previous?.value
            await operation()
        }
    }

    /// The selection's start/end as absolute points (for anchoring handle drags).
    var activeSelectionEndpoints: (start: CompanionSelectionPoint, end: CompanionSelectionPoint)? {
        activeSelectionRange.map { ($0.start, $0.end) }
    }

    /// Where to center the magnifier: the CENTER OF THE CELL the finger maps to,
    /// not the raw finger point. The selection (and its caret in the video) sits
    /// at that cell, so this lines the magnified caret up with the selection
    /// instead of leaving a persistent sub-cell offset. Computed locally, so it is
    /// instant and independent of the round-trip.
    func selectionImagePoint(viewPoint: CGPoint, viewSize: CGSize) -> CGPoint? {
        guard let mapper = activeTouchMapper else { return nil }
        let point = mapper.selectionPoint(viewPoint: viewPoint, viewSize: viewSize)
        return mapper.cellCenterImagePoint(column: point.column, absLine: point.absLine)
    }

    /// Encoded-pixel cell height of the active stream (for sizing the magnifier).
    var activeStreamCellHeight: CGFloat { CGFloat(activeStreamGeometry?.cellHeight ?? 0) }

    /// The layout the live canvas needs to size its scrollable document (history
    /// above, live video at the bottom). Nil until a config with geometry arrives.
    var liveCanvasLayout: CompanionLiveCanvasLayout? {
        guard activeStreamImageSize.width > 0, activeStreamImageSize.height > 0,
              activeStreamRows > 0, activeStreamTotalLines > 0 else {
            return nil
        }
        return CompanionLiveCanvasLayout(imageSize: activeStreamImageSize,
                                         columns: activeStreamColumns,
                                         rows: activeStreamRows,
                                         firstAbsLine: activeStreamFirstAbsLine,
                                         totalLines: activeStreamTotalLines,
                                         generationId: activeStreamGeneration,
                                         cellGeometry: activeStreamGeometry)
    }

    /// A cached scrollback tile, if already fetched.
    func cachedHistoryTile(firstAbsLine: Int64) -> UIImage? { historyTileCache[firstAbsLine] }

    /// Drop a cached tile so it is re-rendered (e.g. a partial tile that has since
    /// grown more lines).
    func invalidateHistoryTile(firstAbsLine: Int64) { historyTileCache[firstAbsLine] = nil }

    /// The result of a scrollback tile fetch. `.throttled` is distinct from `.failed`
    /// so the caller can keep any currently-shown image and re-request, rather than
    /// destroying a valid tile with a "couldn't load" state: a throttle drop, a
    /// stream transition, or a mid-stream reflow superseding a request are all
    /// transient and recoverable, unlike a host-reported miss or a network error.
    enum HistoryTileOutcome {
        case image(UIImage)
        case failed
        case throttled
    }

    /// Fetch a scrollback tile; `completion` ALWAYS runs on the main actor so the
    /// caller can clear its in-flight state. De-duplication and staleness are the
    /// caller's job (the canvas keys requests by tile and ignores out-of-date
    /// completions); doing it here by absolute line silently dropped re-requests after
    /// an invalidation, leaving tiles stuck loading or showing a stale highlight.
    func requestHistoryTile(firstAbsLine: Int64, lineCount: Int, completion: @escaping (HistoryTileOutcome) -> Void) {
        if let image = historyTileCache[firstAbsLine] {
            completion(.image(image))
            return
        }
        guard client != nil, activeStreamID != nil else {
            companionLog("historyTile no stream firstAbs=\(firstAbsLine)")
            if liveWatchGuid != nil {
                // Transient between-stream window (right after stopActiveStream, or during
                // a reconnect): a stream is still intended, so report .throttled and keep
                // any current image; the canvas re-drives (growthTick / slot signal) once
                // it is live. Matches the drain path's no-stream handling.
                reportThrottled(completion)
            } else {
                // No live-watch intent (the host ended the stream): it will not come back,
                // so report a real failure rather than an eternal spinner.
                reportFailed(completion)
            }
            return
        }
        let epoch = historyTileEpoch
        guard historyTileTasks.count < maxHistoryTilesInFlight else {
            guard historyTilePending.count < maxHistoryTilesPending else {
                // Backlog full: reject THIS request rather than evicting a still-valid
                // queued tile. Evicting the oldest churned the whole pending set every
                // pass on a static wide viewport (each pass re-requested the evicted
                // tiles, which re-evicted others). Rejecting the incoming instead lets
                // the pipeline drain in order; onHistoryTileSlotAvailable then nudges the
                // canvas to re-request what it still wants, paced by replies.
                historyTileOverflowed = true
                companionLog("historyTile reject (backlog full) firstAbs=\(firstAbsLine)")
                reportThrottled(completion)
                return
            }
            historyTilePending.append((firstAbsLine, lineCount, epoch, completion))
            return
        }
        sendHistoryTile(firstAbsLine: firstAbsLine, lineCount: lineCount, epoch: epoch, completion: completion)
    }

    /// Drop still-queued tile requests the caller no longer wants (e.g. tiles the user
    /// flung past). Only the pending queue is pruned; an already-issued fetch is left to
    /// complete (it warms the cache). This keeps a fling from spending in-flight slots
    /// and relay frame budget on viewports that have already scrolled away. Takes a set
    /// so the fling hot path prunes the queue in one pass, not one scan per tile.
    func cancelPendingHistoryTiles(firstAbsLines: Set<Int64>) {
        guard !firstAbsLines.isEmpty else { return }
        historyTilePending.removeAll { entry in
            let match = firstAbsLines.contains(entry.firstAbsLine)
            if match {
                reportThrottled(entry.completion)
            }
            return match
        }
    }

    /// Issue one tile request against the current window and, when it settles, pull
    /// the next queued request into the freed slot. Callers gate on the in-flight
    /// window before calling this; see requestHistoryTile. `epoch` ties the request to
    /// the stream it was made for so a transition can neutralize it.
    private func sendHistoryTile(firstAbsLine: Int64, lineCount: Int, epoch: Int, completion: @escaping (HistoryTileOutcome) -> Void) {
        guard let client, let streamID = activeStreamID else {
            // The stream vanished after this request was queued. Report it as throttled
            // (transient) without touching the in-flight count; the drain loop keeps
            // pulling the backlog.
            companionLog("historyTile no stream firstAbs=\(firstAbsLine)")
            reportThrottled(completion)
            return
        }
        let generation = activeStreamGeneration
        let taskID = historyTileTaskCounter
        historyTileTaskCounter += 1
        companionLog("historyTile req firstAbs=\(firstAbsLine) lineCount=\(lineCount) stream=\(streamID) gen=\(generation) epoch=\(epoch)")
        let task = Task { @MainActor in
            defer {
                // historyTileTasks IS the in-flight set (the gate is its count), so
                // removing self frees the slot. A stale task (epoch bumped mid-await, its
                // entry already cleared by flush) removes a no-op key and must not drive
                // the queue for the new stream, so gate the drain on the current epoch.
                historyTileTasks[taskID] = nil
                if epoch == historyTileEpoch {
                    drainHistoryTileQueue()
                }
            }
            do {
                let tile = try await withTimeout(historyTileTimeout, "History tile") {
                    try await client.historyTile(streamID: streamID, firstAbsLine: firstAbsLine,
                                                 lineCount: lineCount, generationId: generation)
                }
                // A stream transition (session switch / reconnect) since the request
                // started makes this reply belong to a dead stream; it must not be
                // cached (its absolute-line key would collide in the new stream).
                guard epoch == historyTileEpoch else {
                    companionLog("historyTile stale epoch firstAbs=\(firstAbsLine) reqEpoch=\(epoch) now=\(historyTileEpoch)")
                    completion(.throttled)
                    return
                }
                // A reflow/resize between request and reply bumps the generation and
                // re-renders every tile, so a reply for the old generation must not be
                // cached or shown as current.
                guard generation == activeStreamGeneration else {
                    companionLog("historyTile stale gen firstAbs=\(firstAbsLine) reqGen=\(generation) now=\(activeStreamGeneration)")
                    completion(.throttled)
                    return
                }
                // The host clamps to the available window and reports the range it
                // actually covered. If that origin differs from what we requested
                // (an eviction race), the image does not belong at this key, so treat
                // it as a miss rather than poisoning the cache with misplaced content.
                guard tile.firstAbsLine == firstAbsLine else {
                    companionLog("historyTile origin drift req=\(firstAbsLine) covered=\(tile.firstAbsLine)+\(tile.lineCount)")
                    completion(.failed)
                    return
                }
                guard tile.lineCount > 0, let image = UIImage(data: tile.pngData) else {
                    companionLog("historyTile reply firstAbs=\(firstAbsLine) lineCount=\(tile.lineCount) bytes=\(tile.pngData.count) -> \(tile.lineCount == 0 ? "evicted" : "undecodable")")
                    completion(.failed)
                    return
                }
                historyTileCache[firstAbsLine] = image
                companionLog("historyTile ok firstAbs=\(firstAbsLine) covered=\(tile.firstAbsLine)+\(tile.lineCount) bytes=\(tile.pngData.count)")
                completion(.image(image))
            } catch is CancellationError {
                // Cancelled by flushHistoryTileThrottle on a stream transition: transient,
                // so keep any current image rather than flashing a failure.
                companionLog("historyTile cancelled firstAbs=\(firstAbsLine)")
                completion(.throttled)
            } catch {
                companionLog("historyTile FAIL firstAbs=\(firstAbsLine): \(error)")
                completion(.failed)
            }
        }
        historyTileTasks[taskID] = task
    }

    /// Pull queued tile requests into freed in-flight slots. A queued request from a
    /// superseded epoch is neutralized (reported .throttled) rather than sent against
    /// the current stream, since its line ranges belong to a different session.
    private func drainHistoryTileQueue() {
        while historyTileTasks.count < maxHistoryTilesInFlight, !historyTilePending.isEmpty {
            let next = historyTilePending.removeFirst()
            guard next.epoch == historyTileEpoch else {
                companionLog("historyTile drop (stale epoch queued) firstAbs=\(next.firstAbsLine) reqEpoch=\(next.epoch) now=\(historyTileEpoch)")
                reportThrottled(next.completion)
                continue
            }
            sendHistoryTile(firstAbsLine: next.firstAbsLine, lineCount: next.lineCount,
                            epoch: next.epoch, completion: next.completion)
        }
        // Spare capacity opened up after we had rejected requests: nudge the canvas to
        // re-request what it still wants. Gated on the overflow flag so ordinary
        // scrolling (which never overflows) does not fire this on every completion.
        if historyTileOverflowed, historyTileTasks.count < maxHistoryTilesInFlight, historyTilePending.isEmpty {
            historyTileOverflowed = false
            onHistoryTileSlotAvailable?()
        }
    }

    /// Neutralize the tile throttle on a stream transition: bump the epoch (so any
    /// straddling request from the old stream becomes a no-op), cancel the prior
    /// stream's in-flight fetches (so they stop occupying the wire and cannot push real
    /// concurrency past the cap across rapid switches; clearing the task set also resets
    /// the in-flight count, which IS that set's size), and report every queued request
    /// as throttled so the canvas keeps its images and re-requests against the new stream.
    /// A dead stream must neutralize the tile throttle before its id is dropped, so
    /// stale in-flight/queued requests do not hit the relay or poison the next stream.
    /// One helper keeps that pairing in a single place across the transition sites.
    private func neutralizeDeadStream() {
        flushHistoryTileThrottle()
        activeStreamID = nil
    }

    private func flushHistoryTileThrottle() {
        historyTileEpoch &+= 1
        // Cancel a snapshot: a cancelled fetch's defer removes itself (a no-op on the
        // cleared set) and, being from the now-stale epoch, will not drive the queue.
        let tasks = historyTileTasks
        historyTileTasks = [:]
        for task in tasks.values {
            task.cancel()
        }
        historyTileOverflowed = false
        let dropped = historyTilePending
        historyTilePending = []
        // Batch into a single deferred turn (rather than one Task per entry) while
        // preserving the non-re-entrant "fresh main-actor turn" contract.
        Task { @MainActor in
            for entry in dropped {
                entry.completion(.throttled)
            }
        }
        // A flush turns some on-screen tiles into spinners (cancelled/queued requests
        // report .throttled, which keeps the loading state). Nudge the canvas to
        // re-request once, so a transition that leaves geometry unchanged (reconnect,
        // resume, streamEnded) still recovers instead of spinning forever. Coalesced and
        // stream-gated on the view side, so it cannot busy-loop; if no stream is live yet
        // (reconnect in progress) the view's applyLayout re-drives once it is.
        onHistoryTileSlotAvailable?()
    }

    /// Deliver a `.throttled` outcome asynchronously. Callers report throttled drops
    /// from inside their own loops (requestHistoryTile/drainHistoryTileQueue); the
    /// SessionView completion mutates tile state and can re-drive refreshTiles, so it
    /// must not run re-entrantly. Deferring to a fresh main-actor turn preserves the
    /// "completions are async except a cache hit" contract.
    private func reportThrottled(_ completion: @escaping (HistoryTileOutcome) -> Void) {
        Task { @MainActor in completion(.throttled) }
    }

    /// Deliver a `.failed` outcome asynchronously, preserving the same non-re-entrant
    /// contract as reportThrottled (the caller may be mid-loop in refreshTiles).
    private func reportFailed(_ completion: @escaping (HistoryTileOutcome) -> Void) {
        Task { @MainActor in completion(.failed) }
    }

    /// The view-space rect the video occupies (excluding letterbox bars), or the
    /// full view if geometry is unknown.
    func contentRect(in viewSize: CGSize) -> CGRect {
        activeTouchMapper?.contentRect(viewSize: viewSize) ?? CGRect(origin: .zero, size: viewSize)
    }

    /// Whether a touch falls on the terminal image rather than the letterbox bars
    /// around it, so a drag in the empty margins does not start a selection.
    func isInsideContent(viewPoint: CGPoint, viewSize: CGSize) -> Bool {
        guard let mapper = activeTouchMapper,
              let p = mapper.imagePoint(viewPoint: viewPoint, viewSize: viewSize) else {
            return false
        }
        return p.x >= 0 && p.x <= activeStreamImageSize.width
            && p.y >= 0 && p.y <= activeStreamImageSize.height
    }

    /// Clear the live-view selection on the mac. Ordered with gestures so a clear
    /// that follows a drag cannot overtake the drag's final messages.
    func clearActiveSelection() {
        guard let client, let streamID = activeStreamID else { return }
        sendOrderedSelection { try? await client.clearSelection(streamID: streamID) }
    }

    /// Copy the active session's selection to the iOS clipboard.
    func copyActiveSelection() {
        guard let client, let guid = liveWatchGuid else { return }
        Task {
            guard let text = try? await client.copySelection(sessionGuid: guid), !text.isEmpty else { return }
            UIPasteboard.general.string = text
        }
    }

    /// Select the entire terminal content (edit-menu Select All). Ordered with
    /// gestures so it cannot overtake a drag's tail.
    func selectAllActiveStream() {
        guard let client, let streamID = activeStreamID else { return }
        sendOrderedSelection { try? await client.selectAll(streamID: streamID) }
    }

    /// Paste the iOS clipboard into the session as input (edit-menu Paste).
    func pasteIntoActiveSession() {
        guard let client, let guid = liveWatchGuid, let text = UIPasteboard.general.string, !text.isEmpty else { return }
        Task { try? await client.pasteText(sessionGuid: guid, text: text) }
    }

    /// Resize the live session's grid so terminal text is legible on this phone:
    /// 40 columns in portrait, 80 in landscape, and however many rows of that font
    /// fill the viewport vertically. `viewSize` is the live canvas area in points.
    /// No-op without an active stream, reported geometry, or a real viewport.
    func resizeActiveSessionForLegibility(viewSize: CGSize) {
        guard let client, let guid = liveWatchGuid, let layout = liveCanvasLayout,
              viewSize.width > 0, viewSize.height > 0 else {
            return
        }
        // Font-independent cell aspect (width/height) in encoded pixels: prefer the
        // reported cell geometry, else derive it from the frame pixels over the grid.
        let cellWidthPx: CGFloat
        let cellHeightPx: CGFloat
        if let geometry = layout.cellGeometry, geometry.cellWidth > 0, geometry.cellHeight > 0 {
            cellWidthPx = geometry.cellWidth
            cellHeightPx = geometry.cellHeight
        } else if layout.columns > 0, layout.rows > 0,
                  layout.imageSize.width > 0, layout.imageSize.height > 0 {
            cellWidthPx = layout.imageSize.width / CGFloat(layout.columns)
            cellHeightPx = layout.imageSize.height / CGFloat(layout.rows)
        } else {
            return
        }
        guard cellWidthPx > 0, cellHeightPx > 0 else { return }

        let columns = viewSize.width > viewSize.height ? 80 : 40
        // Pick a font so `columns` cells span the width, then count how many rows of
        // that same font fill the height.
        let cellPointWidth = viewSize.width / CGFloat(columns)
        let cellPointHeight = cellPointWidth * cellHeightPx / cellWidthPx
        guard cellPointHeight > 0 else { return }
        let rows = Int((viewSize.height / cellPointHeight).rounded(.down))
        guard rows > 0 else { return }

        companionLog("Resize session \(guid) for legibility: \(columns)x\(rows) (viewport \(Int(viewSize.width))x\(Int(viewSize.height)))")
        Task { try? await client.resizeSession(sessionGuid: guid, columns: columns, rows: rows) }
    }

    /// The mac kicked this device: forget the pairing and go back to the scan
    /// screen so the user can pair afresh.
    private func handleRemoteUnpair() {
        companionLog("Unpaired by the Mac")
        reconnectTask?.cancel()
        reconnectTask = nil
        wipeAllKeyMaterial()
        let oldClient = client
        client = nil
        Task { await oldClient?.close() }
        clearPairedMacData()
    }

    /// Apply one delivered message: streaming deltas mutate the targeted bubble
    /// in place (using the same Message.append logic the Mac uses); everything
    /// else upserts by uniqueID.
    private func apply(_ message: Message) {
        apply(message, into: &messages, chatID: openChatID ?? "")
    }

    /// Apply one delivered message into `transcript` (the live open transcript, or
    /// a co-mounted hidden chat's cached snapshot). `chatID` names the target chat
    /// so a stream delta that starts a fresh bubble stamps the right chat.
    private func apply(_ message: Message, into transcript: inout [Message], chatID: String) {
        switch message.content {
        case .append(let string, let uuid):
            applyStreamDelta(to: uuid, in: &transcript, chatID: chatID, fallbackDate: message.sentDate) { target in
                target.append(string, useMarkdownIfAmbiguous: true)
            } orStartWith: {
                .markdown(string)
            }
        case .appendAttachment(let attachment, let uuid):
            applyStreamDelta(to: uuid, in: &transcript, chatID: chatID, fallbackDate: message.sentDate) { target in
                target.append(attachment, vectorStoreID: nil)
            } orStartWith: {
                .multipart([.attachment(attachment)], vectorStoreID: nil)
            }
        case .commit:
            break
        default:
            if let index = transcript.firstIndex(where: { $0.uniqueID == message.uniqueID }) {
                transcript[index] = message
            } else {
                transcript.append(message)
            }
        }
        // Resolve any mentions the change introduced. Streaming deltas target
        // the bubble named by their uuid, not the delta's own uniqueID.
        let affectedID: UUID
        switch message.content {
        case .append(_, let uuid), .appendAttachment(_, let uuid):
            affectedID = uuid
        default:
            affectedID = message.uniqueID
        }
        if let affected = transcript.first(where: { $0.uniqueID == affectedID }) {
            noteMentions(in: [affected])
        }
    }

    /// Mutate the streamed message with `mutate`, or start a fresh agent bubble
    /// with `orStartWith` if no message with that id exists yet. Message.append
    /// traps on non-text content, so only text-bearing targets are mutated.
    private func applyStreamDelta(to messageID: UUID,
                                  in transcript: inout [Message],
                                  chatID: String,
                                  fallbackDate: Date,
                                  mutate: (inout Message) -> Void,
                                  orStartWith makeContent: () -> Message.Content) {
        if let index = transcript.firstIndex(where: { $0.uniqueID == messageID }) {
            switch transcript[index].content {
            case .plainText, .markdown, .multipart:
                mutate(&transcript[index])
            default:
                break
            }
        } else {
            transcript.append(Message(chatID: chatID,
                                      author: .agent,
                                      content: makeContent(),
                                      sentDate: fallbackDate,
                                      uniqueID: messageID))
        }
    }

    func userMessage(for error: Error) -> String {
        if let transport = error as? TransportError {
            return transport.errorDescription ?? "The connection to your Mac was interrupted."
        }
        if let companion = error as? CompanionError {
            return companion.message
        }
        if let parseError = error as? PairingCode.ParseError {
            return parseError.userMessage
        }
        // Surface the real failure ("connection reset by peer"), not Apple's
        // bridged-NSError boilerplate ("The operation couldn't be completed.
        // (Network.NWError error 54.)").
        if let nwError = error as? NWError {
            return "Lost the connection to your Mac (\(Self.describe(nwError)))."
        }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain {
            return "Lost the connection to your Mac (\(Self.posixDescription(Int32(ns.code))))."
        }
        companionLog("Unmapped error shown generically: \(error)")
        return "Something went wrong communicating with your Mac."
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            return posixDescription(code.rawValue)
        case .dns(let code):
            return "DNS error \(code)"
        case .tls(let status):
            return "TLS error \(status)"
        default:
            // Covers cases newer than our deployment target (.wifiAware) as
            // well as truly unknown future ones.
            return String(describing: error)
        }
    }

    private static func posixDescription(_ code: Int32) -> String {
        guard let cString = strerror(code) else {
            return "errno \(code)"
        }
        // Lowercase so it reads naturally inside the sentence's parentheses.
        return String(cString: cString).lowercased()
    }
}

private extension Message.Content {
    /// The preview text AND whether it is a rendered attachment LABEL ("📄 name")
    /// vs real text, computed in ONE reversed subpart walk (mirroring snippetText's
    /// multipart mapping) so the text and its label flag can never drift - they
    /// previously came from two separate walks that agreed only by coincidence.
    /// isLabel drives replace-vs-append in the streaming accumulator, so a .code
    /// attachment (real text) reports false like the whole-message path. Returns
    /// nil when there is nothing to preview.
    func previewAndLabel(maxLength: Int) -> (text: String, isLabel: Bool)? {
        guard case .multipart(let subparts, _) = self else {
            // Non-multipart reply content renders as text, never an attachment label.
            return snippetText(maxLength: maxLength).map { ($0, false) }
        }
        // The last SUBSTANTIVE subpart, via the shared Subpart.previewAndLabel
        // mapping (so text + label can't drift). Skip substance-free subparts here
        // (the phone's policy: an empty/whitespace subpart is not a notifiable
        // preview) and return nil when there is none - NOT the display placeholder
        // "Empty message", which a caller would otherwise fire as a notification.
        for subpart in subparts.reversed() where subpart.hasDisplayableSubstance {
            if let preview = subpart.previewAndLabel(maxLength: maxLength) {
                return preview
            }
        }
        return nil
    }
}

#if DEBUG
// Test accessors: an extension in the SAME file can read `private` state, and
// @testable import exposes these internal members to the app unit-test target.
// Used to unit-test the recurring session-watch claim/restore/depart logic and
// the derived typing indicator.
extension AppModel {
    var testActiveWatchToken: UUID? { watchState.activeToken }
    var testWatchedChatID: String? { watchState.watchedChatID }
    var testAgentTypingChats: Set<String> { agentTypingChats }
    func testSetAgentTyping(_ chatID: String, _ typing: Bool) {
        if typing { agentTypingChats.insert(chatID) } else { agentTypingChats.remove(chatID) }
    }
    var testRefreshFailureChats: Set<String> { Set(refreshFailuresByChat.keys) }
    func testSetRefreshFailure(_ chatID: String, _ count: Int) {
        refreshFailuresByChat[chatID] = count
    }
    /// Install a watch directly (bypassing the async subscribe) so the synchronous
    /// deletion-teardown logic can be tested without a live connection.
    func testInstallWatch(chatID: String, token: UUID) {
        watchState.install(chatID: chatID, subscribedHere: false, token: token)
    }
    func testSetMacRevision(_ revision: Int) { macRevision = revision }
    func testNoteTyping(isTyping: Bool, chatID: String) {
        noteWatchedTypingStatus(isTyping: isTyping, chatID: chatID)
    }
    func testNoteTurnLifecycle(_ event: TurnEvent, chatID: String) {
        // Route through the SAME helper the wire handler uses, so tests exercise the
        // production acceptance gate rather than a re-implemented copy.
        acceptTurnLifecycle(event, chatID: chatID)
    }
    func testResetLastReplyFireBody() { testLastReplyFireBody = nil }
    func testNoteDelivery(_ message: Message, chatID: String) {
        noteWatchedSessionDelivery(message, chatID: chatID)
    }
}
#endif
