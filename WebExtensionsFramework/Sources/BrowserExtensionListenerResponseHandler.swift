//
//  BrowserExtensionListenerResponseHandler.swift
//  WebExtensionsFramework
//
//  Created by George Nachman on 7/7/25.
//

import Foundation
import WebKit
import BrowserExtensionShared

/// Message handler for chrome.runtime.onMessage.addListener native requests
class BrowserExtensionListenerResponseHandler: NSObject, WKScriptMessageHandler {
    private let logger: BrowserExtensionLogger
    private let router: BrowserExtensionRouter

    init(router: BrowserExtensionRouter,
         logger: BrowserExtensionLogger) {
        self.router = router
        self.logger = logger
    }

    /// This is the entry point for API calls that call into native code.
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        logger.info("Received onMessage reply request from JavaScript")

        // Extract requestId from message body
        guard let messageBody = message.body as? [String: Any],
              let requestId = messageBody["requestId"] as? String else {
                  logger.error("Invalid message: \(message.body))")
            return
        }
        
        // Response is now encoded - decode it back to the original value
        do {
            let encodedResponse = try BrowserExtensionEncodedValue(messageBody["response"])
            let decodedResponse = try encodedResponse.decode()
            logger.debug("Send reply to \(requestId): \(decodedResponse ?? "nil") type: \(type(of: decodedResponse))")
            router.sendReply(message: decodedResponse, requestId: requestId)
        } catch {
            logger.error("Failed to decode response: \(error)")
            return
        }
    }
}
