//
//  BrowserExtensionAPIRequestMessageHandler.swift
//  WebExtensionsFramework
//
//  Created by George Nachman on 7/6/25.
//

import Foundation
import WebKit

/// Message handler for chrome.runtime.xxx native requests
class BrowserExtensionAPIRequestMessageHandler: NSObject, WKScriptMessageHandler {
    private let callbackHandler: BrowserExtensionSecureCallbackHandler
    private let logger: BrowserExtensionLogger
    private let dispatcher: BrowserExtensionDispatcher

    init(callbackHandler: BrowserExtensionSecureCallbackHandler,
         dispatcher: BrowserExtensionDispatcher,
         logger: BrowserExtensionLogger) {
        self.callbackHandler = callbackHandler
        self.dispatcher = dispatcher
        self.logger = logger
    }

    /// This is the entry point for API calls that call into native code.
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        logger.debug("Received API request from JavaScript: \(message.body)")

        // Extract requestId from message body
        guard let messageBody = message.body as? [String: Any],
              let requestId = messageBody["requestId"] as? String,
              let api = messageBody["api"] as? String else {
                  logger.error("Invalid message: \(message.body))")
            return
        }
        Task { @MainActor in
            do {
                // Invoke the correct native function
                let obj = try await dispatcher.dispatch(
                    api: api,
                    requestId: requestId,
                    body: messageBody)

                // Send a response to the callback.
                callbackHandler.invokeCallback(requestId: requestId, result: obj, in: message.webView)
            } catch {
                callbackHandler.invokeCallback(requestId: requestId, error: error, in: message.webView)
            }
        }
    }
}
