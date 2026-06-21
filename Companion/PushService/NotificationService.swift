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
            let decision: PushFetchCoordinator<NSEMessagesSince.Preview>.Decision =
                await withTaskGroup(of: PushFetchCoordinator<NSEMessagesSince.Preview>.Decision?.self) { group in
                    group.addTask { await coordinator.run(collapseToken: token) }
                    group.addTask {
                        try? await Task.sleep(for: Self.deadline)
                        // Only hard-cancel if the deadline ACTUALLY elapsed. When
                        // the work finishes first, group.cancelAll() cancels this
                        // task: the sleep throws, try? swallows it, and without
                        // this guard we'd fall through and cancel() a channel that
                        // already delivered - firing a spurious "hard-cancel" on
                        // every successful fetch.
                        if Task.isCancelled { return .fallback }
                        await fetcher.cancel()
                        return .fallback
                    }
                    let first = await group.next() ?? .fallback
                    group.cancelAll()
                    return first ?? .fallback
                }
            await fetcher.close()
            self?.deliver(decision)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        NSELog.log("serviceExtensionTimeWillExpire; cancelling and delivering fallback")
        Task { await fetcher?.cancel() }
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
        // previews arrive newest-first; deliver them CHRONOLOGICALLY (oldest
        // first) so each notification's delivery timestamp matches message order.
        // A local notification (add) is stamped with the time it is added, so the
        // newest must be added LAST to be the most-recent notification (top of the
        // shade). The oldest goes through contentHandler, whose notification keeps
        // the push's ARRIVAL time (earliest) and the collapse id - so it anchors
        // the bottom and carries the "+ more older messages" hint.
        let chronological = Array(previews.reversed())   // oldest -> newest
        guard let oldest = chronological.first else {
            deliverFallback()
            return
        }
        let rest = Array(chronological.dropFirst())      // may be empty
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
        // The oldest of the batch via contentHandler (earliest timestamp -> bottom).
        deliverFinal { content in
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

    private func deliverFallback() {
        deliverFinal { _ in }   // deliver the unchanged fallback content
    }

    /// Deliver exactly once. `customize` mutates the content when it is mutable;
    /// a present handler is always called with something.
    private func deliverFinal(_ customize: (UNMutableNotificationContent) -> Void) {
        lock.lock()
        let handler = contentHandler
        let content = fallbackContent
        contentHandler = nil
        lock.unlock()

        task?.cancel()
        guard let handler else { return }
        if let mutable = content as? UNMutableNotificationContent {
            // Group all of this chat's notifications under one thread (also keeps
            // the generic fallback in the chat's thread).
            if let threadID { mutable.threadIdentifier = threadID }
            customize(mutable)
            handler(mutable)
        } else {
            handler(content ?? UNNotificationContent())
        }
    }
}
