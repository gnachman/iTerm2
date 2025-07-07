//
//  BrowserExtensionContext.swift
//  WebExtensionsFramework
//
//  Created by George Nachman on 7/6/25.
//

import Foundation
import WebKit

/// Each message sender has their own context.
class BrowserExtensionContext {
    struct MessageSender: Codable {
        // always present for extension→extension messages
        var id: String  // the extensionId that called sendMessage
        var url: String?  // the URL of the context that called sendMessage
        var tlsChannelId: String?

        struct Tab: Codable {
            var id: Int?
            var url: String?
            // More can go here, not sure what.
        }
        // only present for messages from content scripts
        var tab: Tab?

        var frameId: Int?
        var origin: String?  // origin of the frame that sent the message

        // For port connections only - not implemented yet
        // Note: these only appear on the sender passed to runtime.onConnect/onConnectExternal or
        // runtime.onUserScriptMessage, not on onMessage.
        var documentId: String?
        var documentLifecycle: String?
        var userScriptWorldId: String?

        init(sender: BrowserExtension,
             senderWebview: WKWebView,
             tab: MessageSender.Tab?,
             frameId: Int?) async {
            id = sender.id.uuidString
            url = (try? await senderWebview.evaluateJavaScript(
                "window.location.href") as? String) ?? "about:empty"
            origin = try? await senderWebview.evaluateJavaScript("window.origin") as? String
            tlsChannelId = nil  // not supported
            self.tab = tab
            self.frameId = frameId
        }
    }

    var logger: BrowserExtensionLogger
    var router: BrowserExtensionRouter
    weak var webView: WKWebView?
    var browserExtension: BrowserExtension
    var tab: MessageSender.Tab?
    var frameId: Int?

    init(logger: BrowserExtensionLogger,
         router: BrowserExtensionRouter,
         webView: WKWebView?,
         browserExtension: BrowserExtension,
         tab: MessageSender.Tab?,
         frameId: Int?) {
        self.logger = logger
        self.router = router
        self.webView = webView
        self.browserExtension = browserExtension
        self.tab = tab
        self.frameId = frameId
    }
}
