import BrowserExtensionShared
import Foundation
import WebKit

/// Injects JavaScript APIs into web extension contexts
/// This class handles injecting the browser.* and chrome.* APIs into webviews
class BrowserExtensionJavaScriptAPIInjector {
    
    // MARK: - Properties
    
    private let browserExtension: BrowserExtension
    private let logger: BrowserExtensionLogger
    
    // MARK: - Initialization
    
    init(browserExtension: BrowserExtension, logger: BrowserExtensionLogger) {
        self.browserExtension = browserExtension
        self.logger = logger
    }
    
    // MARK: - API Injection
    
    /// Injects the chrome.runtime APIs into a webview
    /// - Parameter webView: The webview to inject APIs into
    func injectRuntimeAPIs(into webView: WKWebView) {
        logger.info("Injecting chrome.runtime APIs into webview")
        
        // Create shared callback handler for secure callback dispatch
        let callbackHandler = BrowserExtensionSecureCallbackHandler(logger: logger)
        
        // Add message handler for getPlatformInfo (id is now synchronous)
        webView.configuration.userContentController.add(
            BrowserExtensionMessageHandler(
                callbackHandler: callbackHandler,
                logger: logger
            ),
            name: "requestBrowserExtension"
        )
        
        // Get the JavaScript to inject with the extension data
        let injectionScript = createRuntimeAPIsInjectionScript(browserExtension: browserExtension)
        
        // Create and add the user script
        let userScript = WKUserScript(
            source: injectionScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page)
        
        webView.configuration.userContentController.addUserScript(userScript)
    }
    
    // MARK: - Private Methods
    
    private func createRuntimeAPIsInjectionScript(browserExtension: BrowserExtension) -> String {
        let preamble = """
        ;(function() {
          'use strict';
          const __ext_callbackMap = new Map();

          function __ext_randomString(len = 16) {
            const bytes = crypto.getRandomValues(new Uint8Array(len));
            return Array.from(bytes)
              .map(b => b.toString(36).padStart(2, '0'))
              .join('')
              .substring(0, len);
          }

          const __ext_post = window.webkit.messageHandlers;
        """
        let body = generatedAPIJavascript(.init(extensionId: browserExtension.id.uuidString))
        let postamble = """
          // Expose chrome.runtime
          Object.defineProperty(window, 'chrome', {
            value: Object.freeze({ runtime }),
            writable: false,
            configurable: false,
            enumerable: false
          });

          Object.defineProperty(window, '__EXT_invokeCallback__', {
            value(requestId, result) {
              const cb = __ext_callbackMap.get(requestId);
              if (cb) {
                try { cb(result) }
                finally { __ext_callbackMap.delete(requestId) }
              }
            },
            writable: false,
            configurable: false,
            enumerable: false
          });

          true;
        })();
        """
        return [preamble, body, postamble].joined(separator: "\n")
    }
}


/// Message handler for chrome.runtime.getPlatformInfo requests
class BrowserExtensionMessageHandler: NSObject, WKScriptMessageHandler {

    private let callbackHandler: BrowserExtensionSecureCallbackHandler
    private let logger: BrowserExtensionLogger
    
    init(callbackHandler: BrowserExtensionSecureCallbackHandler, logger: BrowserExtensionLogger) {
        self.callbackHandler = callbackHandler
        self.logger = logger
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        logger.info("Received runtime.getPlatformInfo request from JavaScript")
        
        // Extract requestId from message body
        guard let messageBody = message.body as? [String: Any],
              let requestId = messageBody["requestId"] as? String,
              let api = messageBody["api"] as? String else {
                  logger.error("Invalid message: \(message.body))")
            return
        }
        Task { @MainActor in
            let obj = try await dispatch(api: api, requestId: requestId, body: messageBody)
            callbackHandler.invokeCallback(requestId: requestId, result: obj, in: message.webView)
        }
    }
}
