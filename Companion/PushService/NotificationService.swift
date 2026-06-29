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
        lock.lock()
        self.contentHandler = contentHandler
        // Always have something to deliver: a mutable copy if available, else
        // the original content unchanged.
        self.fallbackContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
            ?? request.content
        lock.unlock()

        // The per-chat collapse token: for a remote notification iOS sets the
        // request identifier to the apns-collapse-id.
        let token = request.identifier
        threadID = token
        // Sealed one-time nonce the mac placed in the push (ciphertext under the
        // room secret); the fetcher opens it and echoes the plaintext so the mac
        // recognizes this fetch as its own (no presence warning).
        let sealedNonce = request.content.userInfo["n"] as? String
        NSELog.log("didReceive push; token=\(token.prefix(8)) nonce=\(sealedNonce == nil ? "no" : "yes")")
        let fetcher = NSEFetcher(appGroup: Self.appGroup)
        self.fetcher = fetcher

        guard let backing = UserDefaultsWatermarkBacking(appGroup: Self.appGroup) else {
            NSELog.log("no App Group container; delivering fallback")
            deliverFallback()
            return
        }
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
