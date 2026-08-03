//
//  NotificationService.swift
//  iTerm2 Companion Push Service (Notification Service Extension)
//
//  The real NSE (docs/push.txt section 6): on a content-free mutable push, read
//  the per-chat collapse token (the APNs collapse id, surfaced as the request
//  identifier), reconnect to the Mac NON-displacing over the relay + Noise
//  channel, fetch the new messages with the slim messagesSince mirror, and
//  rewrite the notification with the real (already-trimmed) content - one
//  notification per message. Every fault delivers the generic fallback, fast.
//
//  The decision logic lives in PushFetchCoordinator (package, unit-tested); this
//  shell wires CryptoKit/URLSession/UserNotifications reality to it. It needs no
//  chat-model types: the wire is the slim NSEMessagesSince mirror, so the whole
//  extension links only the CompanionCore package.
//

import UserNotifications
import os
import Foundation
import Security
import CompanionProtocol
import CompanionNoise
import CompanionTransport

/// NSE logging: mirrors to the unified log (live debugging) and to a file in the
/// shared App Group Logs directory (email-able later from the app's Settings).
/// Plain strings only - never message content.
enum NSELog {
    private static let osLog = Logger(subsystem: "com.googlecode.iterm2.companion.PushService",
                                      category: "nse")
    private static let writer: CompanionFileLogWriter? = {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CompanionSharedIdentifiers.appGroup) else {
            return nil
        }
        return CompanionFileLogWriter(
            directory: container.appendingPathComponent("Logs", isDirectory: true),
            label: "nse",
            isEnabled: {
                UserDefaults(suiteName: CompanionSharedIdentifiers.appGroup)?
                    .object(forKey: CompanionFileLogWriter.enabledKey) as? Bool ?? true
            })
    }()

    static func log(_ message: String) {
        osLog.log("\(message, privacy: .public)")
        writer?.log("[nse] " + message)
    }
}

final class NotificationService: UNNotificationServiceExtension {
    private static let appGroup = CompanionSharedIdentifiers.appGroup
    private static let deadline: Duration = .seconds(12)

    /// A build stamp so a device log confirms exactly which build is running.
    /// The app and this extension are separate binaries that install
    /// independently, so a stale extension is easy to miss. The bundle's
    /// Info.plist is rewritten on every build, so its modification date changes
    /// each build even when the version/build numbers are not bumped.
    static let buildStamp: String = {
        let bundle = Bundle(for: NotificationService.self)
        let info = bundle.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var built = "unknown"
        if let plist = bundle.url(forResource: "Info", withExtension: "plist"),
           let date = (try? FileManager.default.attributesOfItem(atPath: plist.path))?[.modificationDate] as? Date {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            built = f.string(from: date)
        }
        return "v\(version) (\(build)) built \(built)"
    }()

    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var fallbackContent: UNNotificationContent?
    private var fetcher: NSEFetcher?
    private var task: Task<Void, Never>?
    /// Per-chat collapse token (the push identifier). Used as the notification
    /// threadIdentifier so iOS groups all of a chat's notifications together.
    private var threadID: String?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        NSELog.log("NSE \(Self.buildStamp)")
        lock.lock()
        self.contentHandler = contentHandler
        // Always have something to deliver: a mutable copy if available, else
        // the original content unchanged.
        self.fallbackContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
            ?? request.content
        lock.unlock()

        // iOS sets the request identifier to the apns-collapse-id. The fixed
        // sentinel marks a CONTENTLESS WAKEUP (revision >= 2): fetch everything new
        // across all chats + alerts. Any other value is a real per-chat collapse
        // token from a LEGACY push (revision 1, or an older mac): fetch that chat.
        let token = request.identifier
        // Sealed one-time nonce the mac placed in the push (ciphertext under the
        // room secret); the fetcher opens it and echoes the plaintext so the mac
        // recognizes this fetch as its own (no presence warning).
        let sealedNonce = request.content.userInfo["n"] as? String
        let isWakeup = (token == CompanionPushWakeup.collapseSentinel)
        // Log the KIND only, never the token. On the legacy path the token is the
        // per-chat HMAC(roomSecret, chatID); NSELog mirrors to an emailable file in
        // the App Group, and even an 8-char prefix would let anyone with the log
        // (or a device backup) count/correlate pushes per opaque chat bucket - the
        // very metadata this change set removes from the wire.
        NSELog.log("didReceive push; \(isWakeup ? "wakeup" : "legacy") nonce=\(sealedNonce == nil ? "no" : "yes")")
        let fetcher = NSEFetcher(appGroup: Self.appGroup)
        self.fetcher = fetcher

        guard let backing = UserDefaultsWatermarkBacking(appGroup: Self.appGroup) else {
            NSELog.log("no App Group container; delivering fallback")
            deliverFallback()
            return
        }
        if isWakeup {
            // iOS reuses one NSE instance across pushes; clear any threadID left by
            // a previous LEGACY push so a wakeup fallback is never grouped under a
            // stale per-chat thread. The wakeup path sets per-item threads itself.
            threadID = nil
            runSync(fetcher: fetcher, backing: backing, sealedNonce: sealedNonce)
        } else {
            threadID = token
            runLegacy(token: token, fetcher: fetcher, backing: backing, sealedNonce: sealedNonce)
        }
    }

    /// The legacy per-chat path (revision 1, or an older mac): fetch one chat by
    /// its collapse token and render its previews.
    private func runLegacy(token: String,
                           fetcher: NSEFetcher,
                           backing: UserDefaultsWatermarkBacking,
                           sealedNonce: String?) {
        let coordinator = PushFetchCoordinator<NSEMessagesSince.Preview>(
            watermarks: WatermarkStore(backing: backing),
            fetch: { try await fetcher.fetch(collapseToken: $0, sinceSeq: $1, limit: $2, sealedNonce: sealedNonce) })

        task = Task { [weak self] in
            // Race the work against an internal deadline. On timeout we HARD
            // cancel the transport (URLSession's receive ignores cooperative
            // cancellation) so a stalled handshake can't pin the extension.
            typealias Outcome = PushFetchCoordinator<NSEMessagesSince.Preview>.Outcome
            let outcome: Outcome =
                await withTaskGroup(of: Outcome?.self) { group in
                    group.addTask { await coordinator.run(collapseToken: token) }
                    group.addTask {
                        try? await Task.sleep(for: Self.deadline)
                        // Only hard-cancel if the deadline ACTUALLY elapsed. When
                        // the work finishes first, group.cancelAll() cancels this
                        // task: the sleep throws, try? swallows it, and without
                        // this guard we'd fall through and cancel() a channel that
                        // already delivered - firing a spurious "hard-cancel" on
                        // every successful fetch.
                        if Task.isCancelled { return nil }
                        await fetcher.cancel()
                        return coordinator.deadlineOutcome(collapseToken: token)
                    }
                    let first = await group.next() ?? nil
                    group.cancelAll()
                    return first ?? coordinator.deadlineOutcome(collapseToken: token)
                }
            await fetcher.close()
            // Deliver, THEN commit the watermark - and only for the outcome we
            // actually used. The deadline outcome carries no watermark move, so a
            // fetch discarded by the deadline can never skip its content. Order
            // (deliver before commit) means a crash between the two re-notifies
            // rather than loses content.
            self?.deliver(outcome.decision)
            coordinator.commitWatermark(outcome)
            // Drop the worker Task and the fetcher (whose open Noise transport we
            // just closed). iOS reuses ONE NSE process across many pushes; without
            // this the chain self.task -> Task -> fetcher -> live transport would
            // accumulate a retained transport per push for the process lifetime.
            self?.clearWork()
        }
    }

    /// The contentless-wakeup path (revision >= 2): one unified syncSince fetch for
    /// everything new across all chats + alerts, each rendered with a
    /// threadIdentifier computed ON-DEVICE (no per-chat id ever crossed the push).
    private func runSync(fetcher: NSEFetcher,
                         backing: UserDefaultsWatermarkBacking,
                         sealedNonce: String?) {
        guard let roomSecret = NSEFetcher.roomSecret(appGroup: Self.appGroup) else {
            NSELog.log("sync: no room secret; delivering fallback")
            deliverFallback()
            return
        }
        let coordinator = SyncFetchCoordinator(
            watermarks: WatermarkStore(backing: backing),
            tokenForChat: { CompanionThreadKey.make(roomSecret: roomSecret, input: $0) },
            fetch: { try await fetcher.fetchSync(messageSeq: $0, alertSeq: $1, limit: $2, sealedNonce: sealedNonce) })

        task = Task { [weak self] in
            typealias Outcome = SyncFetchCoordinator.Outcome
            let outcome: Outcome =
                await withTaskGroup(of: Outcome?.self) { group in
                    group.addTask { await coordinator.run() }
                    group.addTask {
                        try? await Task.sleep(for: Self.deadline)
                        if Task.isCancelled { return nil }
                        await fetcher.cancel()
                        return coordinator.deadlineOutcome()
                    }
                    let first = await group.next() ?? nil
                    group.cancelAll()
                    return first ?? coordinator.deadlineOutcome()
                }
            await fetcher.close()
            // Await delivery (which waits for every queued add() to be accepted by
            // the notification daemon) BEFORE committing the cursors, AND commit
            // ONLY when delivery actually happened. Otherwise the global floor could
            // advance past items that were never shown - e.g. serviceExtensionTime-
            // WillExpire already delivered the fallback and consumed the handler, so
            // deliverSync presents nothing - suppressing those items forever. A nil
            // self (NSE deallocated) likewise commits nothing.
            let committable = await self?.deliverSync(outcome.decision, roomSecret: roomSecret) ?? false
            if committable {
                coordinator.commit(outcome)
            }
            self?.clearWork()
        }
    }

    /// Release the worker Task and fetcher so a reused NSE process doesn't
    /// accumulate retained (open or closed) transports across pushes.
    private func clearWork() {
        lock.lock()
        defer { lock.unlock() }
        task = nil
        fetcher = nil
    }

    override func serviceExtensionTimeWillExpire() {
        NSELog.log("serviceExtensionTimeWillExpire; cancelling and delivering fallback")
        // Cancel the worker Task for symmetry with every other delivery path, so
        // network work stops promptly instead of running on after expiry.
        lock.lock()
        let runningTask = task
        let runningFetcher = fetcher
        lock.unlock()
        runningTask?.cancel()
        Task { await runningFetcher?.cancel() }
        deliverFallback()
    }

    // MARK: Delivery

    private func deliver(_ decision: PushFetchCoordinator<NSEMessagesSince.Preview>.Decision) {
        switch decision {
        case .fallback:
            NSELog.log("decision=fallback; delivering generic notification")
            deliverFallback()
        case let .content(chatName, previews, truncated):
            // Counts only; never the chat name or message bodies.
            NSELog.log("decision=content; \(previews.count) preview(s), truncated=\(truncated)")
            deliverContent(chatName: chatName, previews: previews, truncated: truncated)
        }
    }

    private func deliverContent(chatName: String,
                                previews: [NSEMessagesSince.Preview],
                                truncated: Bool) {
        // previews arrive CHRONOLOGICALLY (oldest first) per the messagesSince
        // wire contract, which is the order we deliver them in. A local
        // notification (add) is stamped with the time it is added, so the newest
        // (last) is added LAST and becomes the most-recent notification (top of
        // the shade). The oldest goes through contentHandler, whose notification
        // keeps the push's ARRIVAL time (earliest) and the collapse id - so it
        // anchors the bottom and carries the "+ more older messages" hint.
        guard let oldest = previews.first else {
            deliverFallback()
            return
        }
        // CLAIM the one-shot handler ONCE, atomically, BEFORE emitting any add().
        // The per-message add() notifications and the generic fallback must be
        // mutually exclusive: claiming first means that if
        // serviceExtensionTimeWillExpire already won (delivered the fallback and
        // niled the handler), claimHandler() returns nil and we skip the whole
        // batch - so the user never sees the fallback AND these content
        // notifications for one push. (The previous peek-then-deliverFinal left a
        // window where the expiry could interleave between the two.)
        guard let claimed = claimHandler() else {
            NSELog.log("deliverContent: handler already consumed (deadline expiry); skipping")
            return
        }
        task?.cancel()
        let rest = Array(previews.dropFirst())           // may be empty
        for (index, preview) in rest.enumerated() {
            let isNewest = index == rest.count - 1
            let content = UNMutableNotificationContent()
            content.title = chatName
            content.body = preview.body
            // One sound per batch, on the newest message, so a 5-message fetch
            // does not play five sounds at once.
            content.sound = isNewest ? .default : nil
            if let threadID { content.threadIdentifier = threadID }
            // Keyed by the message's own uniqueID so a re-fetched message
            // replaces rather than duplicates.
            let request = UNNotificationRequest(identifier: preview.uniqueID.uuidString,
                                                content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
        // The oldest of the batch via the claimed handler (earliest timestamp -> bottom).
        finish(claimed) { content in
            content.title = chatName
            content.body = self.body(for: oldest, appendMore: truncated)
            // Sound only if this is the single message in the batch (otherwise the
            // newest, added above, carries the sound).
            content.sound = rest.isEmpty ? .default : nil
        }
    }

    private func body(for preview: NSEMessagesSince.Preview, appendMore: Bool) -> String {
        appendMore ? preview.body + " (+ more)" : preview.body
    }

    // MARK: Sync (contentless wakeup) delivery

    /// Returns whether the caller may COMMIT the cursors: true when delivery
    /// actually happened (or the items were legitimately nothing-to-show), false
    /// when the handler was already consumed (expiry) so the floor must not advance.
    private func deliverSync(_ decision: SyncFetchCoordinator.Decision, roomSecret: Data) async -> Bool {
        switch decision {
        case .fallback:
            // Fetch failed: show the generic (with its sound). The coordinator left
            // the cursors nil, so "don't commit" is also the safe choice.
            NSELog.log("sync decision=fallback; delivering generic notification")
            deliverFallback()
            return false
        case .silent:
            // Fetched OK but nothing to show (all already-read, or a reset resync).
            // The push notification is unavoidable, so deliver it SILENTLY (no
            // sound, no stale thread). The cursors are correct to advance, so commit.
            NSELog.log("sync decision=silent; delivering silent placeholder")
            deliverFinal { content in content.sound = nil }
            return true
        case let .content(items, truncated):
            NSELog.log("sync decision=content; \(items.count) item(s), truncated=\(truncated)")
            return await deliverSyncContent(items: items, truncated: truncated, roomSecret: roomSecret)
        }
    }

    /// EVERY fetched item is delivered via add() with its OWN identifier
    /// (uniqueID/alertID), so no item is ever collapsed by the shared all-zeros
    /// sentinel: a later wakeup cannot replace an earlier still-unread one. The
    /// threadIdentifier is computed ON-DEVICE from each item's chatID / alert key.
    /// We AWAIT every add() completion (add() is async XPC with no barrier; once the
    /// contentHandler returns iOS may freeze the NSE) and only then satisfy the push
    /// with a SILENT generic via the one-shot handler - that sentinel-id
    /// notification carries no unique unread content, so its cross-wakeup collapse
    /// is harmless. Returns false (don't commit) if the handler was already consumed
    /// or any add() failed, so the floor only advances once the batch is durable.
    private func deliverSyncContent(items: [SyncFetchCoordinator.RenderItem],
                                    truncated: Bool,
                                    roomSecret: Data) async -> Bool {
        struct Spec {
            let id: String
            let title: String
            let body: String
            let threadID: String
            let isPlaceholder: Bool
        }
        // Stable, constant identity for the forward-compat placeholder: a duplicate
        // push and the host's repeated resends of an unknown-kind item all reuse it,
        // so they coalesce onto ONE standing notification rather than stacking.
        let placeholderID = "companion.placeholder"
        // One compact line naming each item's chat/alert source, so a
        // notification that should have been muted can be traced to what the
        // mac actually returned (the chatID stays on-device; only the log).
        NSELog.log("deliverSyncContent: items = ["
                   + items.map { item in
                       switch item {
                       case let .message(chatID, _, _, _, _): return "message(chat \(chatID))"
                       case let .alert(_, threadKey, _, _): return "alert(thread \(threadKey))"
                       case .placeholder: return "placeholder"
                       }
                   }.joined(separator: ", ")
                   + "]")
        let specs: [Spec] = items.map { item in
            switch item {
            case let .message(chatID, chatName, uniqueID, _, body):
                return Spec(id: uniqueID.uuidString, title: chatName, body: body,
                            threadID: CompanionThreadKey.make(roomSecret: roomSecret, input: chatID),
                            isPlaceholder: false)
            case let .alert(alertID, threadKey, title, body):
                return Spec(id: alertID.uuidString, title: title, body: body,
                            threadID: CompanionThreadKey.make(roomSecret: roomSecret, input: "alert:" + threadKey),
                            isPlaceholder: false)
            case .placeholder:
                return Spec(id: placeholderID, title: "iTerm2 Buddy",
                            body: "You have a new notification. Update iTerm2 Buddy to view it.",
                            threadID: placeholderID, isPlaceholder: true)
            }
        }
        guard !specs.isEmpty else {
            // Shouldn't happen (.content implies items), but never advance the floor
            // on a phantom empty batch.
            deliverFinal { content in content.sound = nil }
            return true
        }
        // CLAIM the one-shot handler FIRST so the per-item add()s and any expiry
        // fallback are mutually exclusive. If it's already consumed (expiry won),
        // deliver nothing and DON'T commit - the next wakeup re-fetches.
        guard let claimed = claimHandler() else {
            NSELog.log("deliverSyncContent: handler already consumed (deadline expiry); not committing")
            return false
        }
        task?.cancel()
        // The wakeup push must produce ONE notification of its own (the
        // contentHandler). Rather than waste it on the generic
        // "Your agent has an update." fallback even when we fetched real
        // messages, route the NEWEST real (non-placeholder) item through it and
        // add() the rest as their own notifications. Only when there is nothing
        // real to show does the generic stand (silent). A content-bearing wakeup
        // used to leave a redundant standing "Your agent has an update." banner
        // beside the real messages; this removes it.
        //
        // The push's own notification carries the fixed wakeup collapse-id, so
        // this "newest message" slot collapses across wakeups (it always shows
        // the latest). Older messages keep their own unique-id notifications, so
        // no message loses its place in the shade; only the newest banner is
        // transient. The sound + "+ more" hint ride the newest item.
        let handlerIndex = specs.lastIndex { !$0.isPlaceholder }
        let added = specs.enumerated().filter { $0.offset != handlerIndex }.map { $0.element }
        let allAccepted: Bool = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let group = DispatchGroup()
            let lock = NSLock()
            var ok = true
            for spec in added {
                let content = UNMutableNotificationContent()
                content.title = spec.title
                content.body = spec.body
                content.sound = nil   // the handler item below carries the sound
                content.threadIdentifier = spec.threadID
                let request = UNNotificationRequest(identifier: spec.id, content: content, trigger: nil)
                group.enter()
                UNUserNotificationCenter.current().add(request) { error in
                    if error != nil { lock.lock(); ok = false; lock.unlock() }
                    group.leave()
                }
            }
            group.notify(queue: .main) { continuation.resume(returning: ok) }
        }
        if let i = handlerIndex {
            // Satisfy the push with the newest real message, not the generic.
            let spec = specs[i]
            NSELog.log("deliverSyncContent: added \(added.count) item(s); satisfied the push with the newest message (no generic placeholder)")
            finish(claimed) { content in
                content.title = spec.title
                content.body = truncated ? spec.body + " (+ more)" : spec.body
                content.sound = .default
                content.threadIdentifier = spec.threadID
            }
        } else {
            // Nothing real to show (all placeholders): the generic stands, silent.
            NSELog.log("deliverSyncContent: no real item to show; satisfied the push with the silent generic placeholder")
            finish(claimed) { content in content.sound = nil }
        }
        return allAccepted
    }

    /// The one-shot handler plus the fallback content to feed it, captured under
    /// the lock so only ONE caller can ever win it.
    private struct ClaimedDelivery {
        let handler: (UNNotificationContent) -> Void
        let content: UNNotificationContent?
    }

    /// Atomically take the one-shot handler. Returns nil if delivery already
    /// happened (the fallback/expiry path won). The caller MUST then `finish` it.
    private func claimHandler() -> ClaimedDelivery? {
        lock.lock()
        defer { lock.unlock() }
        guard let handler = contentHandler else { return nil }
        let content = fallbackContent
        contentHandler = nil
        return ClaimedDelivery(handler: handler, content: content)
    }

    /// Customize (when mutable) and call a claimed handler exactly once.
    private func finish(_ claimed: ClaimedDelivery,
                        customize: (UNMutableNotificationContent) -> Void) {
        if let mutable = claimed.content as? UNMutableNotificationContent {
            // Group all of this chat's notifications under one thread (also keeps
            // the generic fallback in the chat's thread).
            if let threadID { mutable.threadIdentifier = threadID }
            customize(mutable)
            claimed.handler(mutable)
        } else {
            claimed.handler(claimed.content ?? UNNotificationContent())
        }
    }

    private func deliverFallback() {
        deliverFinal { _ in }   // deliver the unchanged fallback content
    }

    /// Deliver exactly once. `customize` mutates the content when it is mutable;
    /// a present handler is always called with something.
    private func deliverFinal(_ customize: (UNMutableNotificationContent) -> Void) {
        guard let claimed = claimHandler() else { return }
        task?.cancel()
        finish(claimed, customize: customize)
    }
}
