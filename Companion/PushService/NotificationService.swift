//
//  NotificationService.swift
//  iTerm2 Companion Push Service (Notification Service Extension)
//
//  Memory-spike harness (docs/push.txt Verification gate 0). On a push, it
//  reconnects to the Mac over the relay + Noise channel and logs the extension's
//  remaining memory headroom (os_proc_available_memory). It does NOT yet fetch
//  or rewrite content; it always delivers the unchanged (fallback) notification.
//  The real NSE grows from this shell.
//

import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var content: UNNotificationContent?
    private var probeTask: Task<Void, Never>?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        lock.lock()
        self.contentHandler = contentHandler
        // Prefer a mutable copy (so a real impl can rewrite it), but fall back to
        // the original content if the copy is unavailable, so we ALWAYS have
        // something to deliver and never drop the notification.
        self.content = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? request.content
        lock.unlock()

        probeTask = Task { [weak self] in
            // NOTE (spike limitation): this deadline delivers the fallback on time
            // via serviceExtensionTimeWillExpire, but it does NOT forcibly unblock a
            // stalled Noise handshake. URLSessionWebSocketTask.receive() ignores
            // cooperative cancellation and NoiseHandshake.perform has no internal
            // timeout, so a Mac that stalls mid-handshake can pin this extension
            // until URLSession's own (long) timeout. The production NSE must hard-
            // cancel the transport on deadline (docs/push.txt section 6). Acceptable
            // here only because this is throwaway measurement code.
            await ReconnectProbe.run(deadline: .seconds(12))
            self?.deliver()
        }
    }

    override func serviceExtensionTimeWillExpire() {
        deliver()
    }

    /// Deliver exactly once. A present handler is ALWAYS called with something
    /// (the mutable copy, the original content, or an empty content as a last
    /// resort) - the "have a handler" check is decoupled from "have content" so a
    /// missing mutable copy can never drop the notification.
    private func deliver() {
        lock.lock()
        let handler = contentHandler
        let toDeliver = content
        contentHandler = nil
        lock.unlock()

        probeTask?.cancel()
        guard let handler else { return }
        handler(toDeliver ?? UNNotificationContent())
    }
}
