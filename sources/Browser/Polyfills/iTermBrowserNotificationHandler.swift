//
//  iTermBrowserNotificationHandler.swift
//  iTerm2
//
//  Created by George Nachman on 6/22/25.
//

import Foundation
import UserNotifications
import Security
import WebKit

@available(macOS 11.0, *)
class iTermBrowserNotificationHandler {
    static let messageHandlerName = "iTermNotification"
    private let secret: String
    private let user: iTermBrowserUser

    init?(user: iTermBrowserUser) {
        guard let secret = String.makeSecureHexString() else {
            return nil
        }
        self.user = user
        self.secret = secret
    }

    var javascript: String {
        return iTermBrowserTemplateLoader.loadTemplate(named: "notification-bridge",
                                                       type: "js",
                                                       substitutions: [ "SECRET": secret ])

    }

    func handleMessage(webView: WKWebView,
                       message: WKScriptMessage) {
        guard let messageDict = message.body as? [String: Any],
              let type = messageDict["type"] as? String,
              let sessionSecret = messageDict["sessionSecret"] as? String,
              sessionSecret == secret else {
            DLog("Invalid notification message format")
            return
        }
        let origin = message.frameInfo.securityOrigin
        Task {
            let originString = iTermBrowserPermissionManager.normalizeOrigin(from: origin)
            switch type {
            case "requestPermission":
                await handlePermissionRequest(webView: webView,
                                              messageDict: messageDict,
                                              originString: originString,
                                              sessionSecret: sessionSecret)
            case "show":
                if await !originIsPermitted(originString) {
                    DLog("Permission denied for \(originString)")
                    return
                }
                await handleShowNotification(messageDict, originString: originString)
            case "close":
                if await !originIsPermitted(originString) {
                    DLog("Permission denied for \(originString)")
                    return
                }
                await handleCloseNotification(messageDict)
            default:
                DLog("Unknown notification message type: \(type)")
            }
        }
    }

    private func originIsPermitted(_ originString: String) async -> Bool {
        let disposition = await iTermBrowserPermissionManager(user: user).getPermissionDecision(for: .notification, origin: originString)
        return disposition == .granted
    }

    private func handlePermissionRequest(webView: WKWebView,
                                         messageDict: [String: Any],
                                         originString: String,
                                         sessionSecret: String) async {
        guard let requestId = messageDict["requestId"] as? Int else {
            DLog("Missing requestId in permission request")
            return
        }
        
        let decision = await iTermBrowserPermissionManager(user: user).requestPermission(
            for: .notification,
            origin: originString
        )
        
        let permissionString = decision == .granted ? "granted" : "denied"
        
        // Send response back to JavaScript with session secret
        let jsCode = "window.iTermNotificationHandler.handlePermissionResponse('\(sessionSecret)', \(requestId), '\(permissionString)');"
        
        await MainActor.run {
            webView.evaluateJavaScript(jsCode) { _, error in
                if let error = error {
                    DLog("Error sending permission response: \(error)")
                }
            }
        }
    }
    
    private func handleShowNotification(_ messageDict: [String: Any], originString: String) async {
        guard let notificationId = messageDict["id"] as? String,
              let title = messageDict["title"] as? String else {
            DLog("Missing required fields in show notification message")
            return
        }

        let body = messageDict["body"] as? String ?? ""
        let icon = messageDict["icon"] as? String

        await showNotification(
            id: notificationId,
            title: title,
            body: body,
            icon: icon,
            origin: originString)
    }
    
    private func handleCloseNotification(_ messageDict: [String: Any]) async {
        guard let notificationId = messageDict["id"] as? String else {
            DLog("Missing notification ID in close message")
            return
        }
        
        DLog("Notification close requested for ID: \(notificationId)")
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationId])
    }

    // MARK: - Notification Display

    private func showNotification(id: String,
                                  title: String,
                                  body: String,
                                  icon: String?,
                                  origin: String) async {
        guard let decision = await iTermBrowserPermissionManager(user: user).getPermissionDecision(for: .notification, origin: origin),
              decision == .granted else {
            DLog("Notifications not allowed for origin: \(origin)")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // Add origin info to userInfo to distinguish from iTerm2's own notifications
        content.userInfo = [
            "origin": origin,
            "webNotification": true
        ]
        
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil // Show immediately
        )
        
        let center = UNUserNotificationCenter.current()
        do {
            try await center.add(request)
            DLog("Showed notification for \(origin): \(title)")
        } catch {
            DLog("Failed to show notification: \(error)")
        }
    }
    
    // MARK: - Permission State Updates
    
    func updatePermissionState(for origin: String, webView: WKWebView) async {
        let decision = await iTermBrowserPermissionManager(user: user).getPermissionDecision(
            for: .notification,
            origin: origin
        )
        
        let permissionString = decision == .granted ? "granted" : (decision == .denied ? "denied" : "default")
        let jsCode = "window.iTermNotificationHandler.setPermission('\(permissionString)');"
        
        await MainActor.run {
            webView.evaluateJavaScript(jsCode) { _, error in
                if let error = error {
                    DLog("Error updating permission state: \(error)")
                }
            }
        }
    }
}
