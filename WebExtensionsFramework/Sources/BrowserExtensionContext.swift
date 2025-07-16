//
//  BrowserExtensionContext.swift
//  WebExtensionsFramework
//
//  Created by George Nachman on 7/6/25.
//

import Foundation
import WebKit

/// Each message sender has their own context.
@MainActor
class BrowserExtensionContext {
    struct MessageSender: Codable {
        // always present for extension→extension messages
        var id: String  // the extensionId that called sendMessage
        var url: String?  // the URL of the context that called sendMessage
        var tlsChannelId: String?
        
        // Role of the sender webview for MV3 messaging restrictions
        var role: WebViewRole

        struct Tab: Codable {
            var id: Int?
            var url: String?
            // More can go here, not sure what.
        }
        // only present for messages from content scripts
        // TODO: This has to be updated when the webview moves tabs.
        var tab: Tab?

        // TODO: This has to be updated when the webview moves frames.
        var frameId: Int?
        // TODO: This has to be updated when the webview moves origins.
        var origin: String?  // origin of the frame that sent the message

        // For port connections only - not implemented yet
        // Note: these only appear on the sender passed to runtime.onConnect/onConnectExternal or
        // runtime.onUserScriptMessage, not on onMessage.
        var documentId: String?
        var documentLifecycle: String?
        var userScriptWorldId: String?

        init(sender: BrowserExtension,
             senderWebview: BrowserExtensionWKWebView,
             tab: MessageSender.Tab?,
             frameId: Int?,
             role: WebViewRole) async {
            id = sender.id.stringValue
            url = (try? await senderWebview.be_evaluateJavaScript(
                "window.location.href", in: nil, in: WKContentWorld.page) as? String) ?? "about:empty"
            origin = try? await senderWebview.be_evaluateJavaScript("window.origin", in: nil, in: WKContentWorld.page) as? String
            tlsChannelId = nil  // not supported
            self.tab = tab
            self.frameId = frameId
            self.role = role
        }
    }

    var logger: BrowserExtensionLogger
    var router: BrowserExtensionRouter
    weak var webView: BrowserExtensionWKWebView?
    var browserExtension: BrowserExtension
    var tab: MessageSender.Tab?
    var frameId: Int?
    var contextType: BrowserExtensionStorageContextType
    var role: WebViewRole

    init(logger: BrowserExtensionLogger,
         router: BrowserExtensionRouter,
         webView: BrowserExtensionWKWebView?,
         browserExtension: BrowserExtension,
         tab: MessageSender.Tab?,
         frameId: Int?,
         contextType: BrowserExtensionStorageContextType,
         role: WebViewRole) {
        self.logger = logger
        self.router = router
        self.webView = webView
        self.browserExtension = browserExtension
        self.tab = tab
        self.frameId = frameId
        self.contextType = contextType
        self.role = role
    }
    
    // MARK: - Permission Checking
    
    /// Check if the extension has the required permissions
    /// - Parameter requiredPermissions: Array of required API permissions
    /// - Throws: BrowserExtensionError.insufficientPermissions if permissions are missing
    func requirePermissions(_ requiredPermissions: [BrowserExtensionAPIPermission]) throws {
        let manifest = browserExtension.manifest
        
        for permission in requiredPermissions {
            if !manifest.hasPermission(permission) {
                logger.error("Extension \(browserExtension.id) missing required permission: \(permission.rawValue)")
                throw BrowserExtensionError.insufficientPermissions(permission.rawValue)
            }
        }
        
        if !requiredPermissions.isEmpty {
            logger.debug("Extension \(browserExtension.id) has all required permissions: \(requiredPermissions.map { $0.rawValue })")
        }
    }
    
    /// Check if the extension has a specific permission
    /// - Parameter permission: The API permission to check
    /// - Returns: true if the extension has the permission
    func hasPermission(_ permission: BrowserExtensionAPIPermission) -> Bool {
        return browserExtension.manifest.hasPermission(permission)
    }
}
