//
//  SessionWatchState.swift
//  iTerm2 Companion
//
//  Single owner of the session-view reply-WATCH ownership state: which view
//  (token) owns the one watch slot, the tab/chat it targets, the per-send claim
//  sequence, and which view tokens have departed. This used to live as six fields
//  mutated inline across ~10 AppModel methods, each patching one race in isolation
//  with no coordinating invariant - the same shape DictationController was
//  extracted to fix. Concentrating the transitions here (all synchronous and
//  unit-tested) is that fix for the watch.
//
//  The async subscribe/unsubscribe side effects stay in AppModel: the mutating
//  methods return the Watch they removed so the caller can unsubscribe, and
//  AppModel re-checks ownership through this type after each await.
//

import Foundation

struct SessionWatchState {
    /// The one installed watch: the chat being watched and the view that owns it.
    struct Watch: Equatable {
        let chatID: String
        /// The owning view's tab, so a reply-notification tap pushes the chat onto
        /// the right stack. Mutable: ownership can transfer to a newer same-chat view.
        var tab: AppModel.AppTab
        /// Whether this state subscribed to the chat itself (vs it already being an
        /// open conversation), so teardown knows whether to unsubscribe.
        var subscribedHere: Bool
        /// The owning session view (visit). Mutable: see `tab`.
        var token: UUID
    }

    /// A per-send claim, returned so a failed send can restore the prior owner
    /// without cutting a newer same-view send (higher sequence).
    struct Claim: Equatable {
        let priorToken: UUID?
        let priorTab: AppModel.AppTab
        let sequence: Int
    }

    private(set) var watch: Watch?
    /// The token of the send that currently owns the watch INTENT (set at claim,
    /// before the async subscribe installs the watch).
    private(set) var activeToken: UUID?
    private var activeTab: AppModel.AppTab = .chats
    /// The chat the in-flight intent resolved to, so opening that same chat can
    /// cancel the intent (not an unrelated one).
    private(set) var activeChatID: String?
    /// Monotonic per-SEND id. watchToken is per-VIEW, so two overlapping same-view
    /// sends share it; the sequence lets restore fire only for the latest claim.
    private var sequence = 0
    /// Tokens of departed views, so restore can't revive one (its onDisappear won't
    /// fire again to tear down a watch it would install).
    private var departed: Set<UUID> = []

    // MARK: - Reads (delivery / typing / notification / subscription paths)

    var watchedChatID: String? { watch?.chatID }
    func isWatching(_ chatID: String) -> Bool { watch?.chatID == chatID }
    func owns(_ token: UUID) -> Bool { watch?.token == token }
    func isActiveOwner(_ token: UUID) -> Bool { activeToken == token }
    /// Whether a chat still needs its subscription kept: it's watched, or an
    /// in-flight send intends to watch it.
    func needsSubscription(_ chatID: String) -> Bool {
        watch?.chatID == chatID || activeChatID == chatID
    }

    // MARK: - Claim / restore

    mutating func claim(token: UUID, tab: AppModel.AppTab) -> Claim {
        let prior = activeToken
        let priorTab = activeTab
        // A send Task can outlive a genuine pop (sendComposed defers the claim past
        // an async consent check), so this claim may run AFTER the view departed. If
        // so, do NOT make the gone view the active owner: leaving activeToken unset
        // makes beginWatchingSessionChat's recordIntent guard bail, so no watch or
        // Mac subscription (and no reply notification) installs for a departed view.
        // The message itself still publishes; only the reply-watch is skipped. Read
        // this BEFORE the removeAll below erases the departure.
        let claimingTokenDeparted = departed.contains(token)
        activeToken = claimingTokenDeparted ? nil : token
        activeTab = tab
        activeChatID = nil
        sequence += 1
        // Only the LATEST claim can restore (restore checks sequence), so any
        // departure recorded for an earlier claim is now unreachable. Dropping them
        // here bounds `departed` - a genuinely-popped view's token no longer lingers
        // for the life of the pairing.
        departed.removeAll()
        return Claim(priorToken: prior, priorTab: priorTab, sequence: sequence)
    }

    /// Restore the prior claim's INTENT token (so a still-in-flight prior send can
    /// complete and install its watch), but ONLY if this is the latest claim and
    /// the prior view hasn't departed. It does NOT rebuild a watch that was already
    /// torn down when this (failing) send superseded a prior view - with a single
    /// watch slot, that prior watch is genuinely gone; reinstating it per-view is
    /// what a keyed set of watches (the remaining structural step) would provide.
    mutating func restore(_ claim: Claim) {
        guard sequence == claim.sequence else { return }
        // Don't revive a DEPARTED view's token (its suspended send would install a
        // watch/subscription for a gone view); leave the slot cleared instead.
        if let prior = claim.priorToken, departed.contains(prior) {
            activeToken = nil
            activeChatID = nil
            return
        }
        activeToken = claim.priorToken
        activeTab = claim.priorTab
        activeChatID = nil
    }

    // MARK: - Begin (around AppModel's async subscribe)

    /// Record the in-flight intent's target chat; returns whether this token is
    /// still the owner (a newer send / a departure clears it).
    mutating func recordIntent(chatID: String, token: UUID) -> Bool {
        guard activeToken == token else { return false }
        activeChatID = chatID
        return true
    }

    /// Already watching this chat: transfer ownership (token + current claim tab)
    /// to the newer view and report a REUSE (no fresh subscribe/install).
    mutating func reuseIfSameChat(_ chatID: String, token: UUID) -> Bool {
        guard watch?.chatID == chatID else { return false }
        watch?.token = token
        watch?.tab = activeTab
        return true
    }

    /// Install a freshly-subscribed watch. Uses the tab captured at claim time.
    mutating func install(chatID: String, subscribedHere: Bool, token: UUID) {
        watch = Watch(chatID: chatID, tab: activeTab, subscribedHere: subscribedHere, token: token)
    }

    // MARK: - Teardown (caller resets reply state + unsubscribes if subscribedHere)

    /// Drop the current watch and return it (nil if none).
    mutating func removeWatch() -> Watch? {
        let removed = watch
        watch = nil
        // Clear the in-flight intent too when it belongs to this watch's token
        // (mirror depart): in steady state recordIntent left activeChatID == the
        // watched chat and install stamped the same token, so without this the intent
        // lingers after teardown and needsSubscription keeps reporting true - so the
        // caller's unsubscribeIfUnused skips the just-removed (e.g. deleted) chat and
        // leaks its Mac subscription. A newer send's intent (different token, e.g. the
        // switch-to-another-chat path) is left intact.
        if let removed, activeToken == removed.token {
            activeToken = nil
            activeChatID = nil
        }
        return removed
    }

    /// A view departed: mark its token (blocks restore-revival), clear the active
    /// intent if it owned it, and remove + return the watch if it owned it.
    mutating func depart(token: UUID) -> Watch? {
        departed.insert(token)
        if activeToken == token {
            activeToken = nil
            activeChatID = nil
        }
        guard watch?.token == token else { return nil }
        defer { watch = nil }
        return watch
    }

    /// A view reappeared (a tab switch fired onDisappear while it stayed mounted);
    /// un-mark its token so a restore can revive it.
    mutating func viewDidAppear(token: UUID) { departed.remove(token) }

    /// Undo a watch a FAILED send installed - only if THIS send installed it, is
    /// still the LATEST claim, and still owns the watch. The sequence check is what
    /// distinguishes install-then-reuse: a newer same-view send (higher sequence)
    /// may have REUSED this watch and then SUCCEEDED, so a stale send's failure must
    /// not tear down the watch that newer send relies on (they share the per-view
    /// token, so token identity alone can't tell them apart). Returns the removed
    /// watch.
    mutating func unwindFailedSend(installedWatch: Bool, token: UUID, claimSequence: Int) -> Watch? {
        guard installedWatch, sequence == claimSequence, watch?.token == token else { return nil }
        defer { watch = nil }
        return watch
    }

    /// The user is opening the watched chat as a conversation: cancel the intent
    /// (installed or in-flight) for THAT chat and drop the watch, but KEEP its
    /// subscription (the conversation re-subscribes idempotently and owns teardown).
    /// Returns whether a watch was dropped (caller resets reply state; no unsubscribe).
    mutating func handOffIfOpening(_ chatID: String) -> Bool {
        // Cancel the in-flight INTENT only if it actually targets THIS chat - NOT
        // because the installed watch happens to be for this chat, which would clear
        // an UNRELATED concurrent send's intent (a different view sending to another
        // chat), silently losing that send's reply notification.
        if activeChatID == chatID {
            activeToken = nil
            activeChatID = nil
        }
        // Dropping the installed watch is the separate case.
        guard watch?.chatID == chatID else { return false }
        watch = nil
        return true
    }

    /// A conversation for the watched chat was popped: the watch adopts its
    /// subscription so exactly one path unsubscribes later. Returns whether adopted.
    mutating func adoptSubscription(for chatID: String) -> Bool {
        guard watch?.chatID == chatID else { return false }
        watch?.subscribedHere = true
        return true
    }

    mutating func reset() {
        watch = nil
        activeToken = nil
        activeTab = .chats
        activeChatID = nil
        sequence = 0
        departed = []
    }

    #if DEBUG
    /// Test-only: how many departed tokens are retained (asserts the bounding).
    var departedCount: Int { departed.count }
    #endif
}
