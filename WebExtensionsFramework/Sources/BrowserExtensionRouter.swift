//
//  BrowserExtensionRouter.swift
//  WebExtensionsFramework
//
//  Created by George Nachman on 7/6/25.
//

import Foundation
import WebKit

/// Routes messages between different webviews.
/// The initial message is sent:
///     chrome.runtime.sendMessage -> chrome.runtime.onMessage.addListener
///     chrome.runtime.sendMessage -> chrome.runtime.onMessageExternal.addListener
///     chrome.tabs.sendMessage    -> chrome.runtime.onMessage.addListener
/// A listener may choose to send a reply, which goes to the sender's callback.
class BrowserExtensionRouter {
    private let logger: BrowserExtensionLogger

    init(logger: BrowserExtensionLogger) {
        self.logger = logger
    }

    // Deliver a message from sendMessage to all webviews associated with a particular extension,
    // or, if none is given, the sender's extension.
    func publish(message: [String: Any],
                 extensionId directedRecipient: String?,
                 sender: BrowserExtensionContext.MessageSender,
                 sendingWebView: WKWebView,
                 options: [String: Any]) async throws -> [String: Any]? {
        let destinationID = directedRecipient ?? sender.id
        logger.info("publish \(message) to extension \(destinationID) from \(sender)")
        throw BrowserExtensionError.noMessageReceiver
    }
}

extension Encodable {
    var asJSONObject: String {
        String(data: try! JSONSerialization.data(withJSONObject: self, options: []), encoding: .utf8)!
    }
    var asJSONFragment: String {
        String(data: try! JSONSerialization.data(withJSONObject: self, options: [.fragmentsAllowed]), encoding: .utf8)!
    }
    var asJSONObjectMaybe: String? {
        guard let data = try? JSONSerialization.data(withJSONObject: self, options: []) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    func toJSONFragment() throws -> String {
        let data = try JSONSerialization.data(withJSONObject: self, options: [.fragmentsAllowed])
        return String(data: data, encoding: .utf8)!
    }
}

