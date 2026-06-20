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

final class NotificationService: UNNotificationServiceExtension {
    private static let appGroup = CompanionSharedIdentifiers.appGroup
    private static let deadline: Duration = .seconds(12)
    private static let log = Logger(subsystem: "com.googlecode.iterm2.companion.PushService",
                                    category: "nse")

    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var fallbackContent: UNNotificationContent?
    private var fetcher: NSEFetcher?
    private var task: Task<Void, Never>?

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
        let fetcher = NSEFetcher(appGroup: Self.appGroup)
        self.fetcher = fetcher

        guard let backing = UserDefaultsWatermarkBacking(appGroup: Self.appGroup) else {
            Self.log.error("no App Group; delivering fallback")
            deliverFallback()
            return
        }
        let coordinator = PushFetchCoordinator<NSEMessagesSince.Preview>(
            watermarks: WatermarkStore(backing: backing),
            fetch: { try await fetcher.fetch(collapseToken: $0, sinceSeq: $1, limit: $2) })

        task = Task { [weak self] in
            // Race the work against an internal deadline. On timeout we HARD
            // cancel the transport (URLSession's receive ignores cooperative
            // cancellation) so a stalled handshake can't pin the extension.
            let decision: PushFetchCoordinator<NSEMessagesSince.Preview>.Decision =
                await withTaskGroup(of: PushFetchCoordinator<NSEMessagesSince.Preview>.Decision?.self) { group in
                    group.addTask { await coordinator.run(collapseToken: token) }
                    group.addTask {
                        try? await Task.sleep(for: Self.deadline)
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
        Task { await fetcher?.cancel() }
        deliverFallback()
    }

    // MARK: Delivery

    private func deliver(_ decision: PushFetchCoordinator<NSEMessagesSince.Preview>.Decision) {
        switch decision {
        case .fallback:
            deliverFallback()
        case let .content(chatName, previews, truncated):
            deliverContent(chatName: chatName, previews: previews, truncated: truncated)
        }
    }

    private func deliverContent(chatName: String,
                                previews: [NSEMessagesSince.Preview],
                                truncated: Bool) {
        guard let newest = previews.first else {
            deliverFallback()
            return
        }
        // Schedule the older messages (and a "+N more" hint when truncated) as
        // their own notifications with distinct ids, so they don't replace each
        // other or the collapse-id'd one delivered via contentHandler.
        let older = Array(previews.dropFirst())
        for (index, preview) in older.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = chatName
            content.body = body(for: preview, appendMore: truncated && index == older.count - 1)
            content.sound = .default
            let id = "\(newest.uniqueID.uuidString)-\(preview.uniqueID.uuidString)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
        // The newest goes through contentHandler (keeps the push's collapse id).
        deliverFinal { content in
            content.title = chatName
            content.body = self.body(for: newest, appendMore: truncated && older.isEmpty)
            content.sound = .default
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
            customize(mutable)
            handler(mutable)
        } else {
            handler(content ?? UNNotificationContent())
        }
    }
}
