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
            BrowserExtensionRuntimePlatformInfoMessageHandler(
                callbackHandler: callbackHandler,
                logger: logger
            ),
            name: "requestRuntimePlatformInfo"
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
        // Use JSONEncoder to safely encode the extension ID
        let extensionId = browserExtension.id.uuidString
        guard let encodedIdData = try? JSONEncoder().encode(extensionId),
              let encodedIdString = String(data: encodedIdData, encoding: .utf8) else {
            logger.error("Failed to encode extension ID for JavaScript injection")
            return ""
        }
        
        return """
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

          const runtime = {
            getPlatformInfo(callback) {
              const id = __ext_randomString();
              __ext_callbackMap.set(id, callback);
              __ext_post.requestRuntimePlatformInfo.postMessage({ requestId: id });
            }
          };

          // Define id as a non-writable, non-configurable property
          Object.defineProperty(runtime, 'id', {
            value: \(encodedIdString),
            writable: false,
            configurable: false,
            enumerable: true
          });
          
          Object.freeze(runtime);

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
    }
}


/// Message handler for chrome.runtime.getPlatformInfo requests
class BrowserExtensionRuntimePlatformInfoMessageHandler: NSObject, WKScriptMessageHandler {
    
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
              let requestId = messageBody["requestId"] as? String else {
            logger.error("Invalid message format for runtime.getPlatformInfo: missing requestId")
            return
        }
        
        // Determine architecture at runtime
        let arch: String
        #if arch(x86_64)
        arch = "x86-64"
        #elseif arch(arm64)
        arch = "arm64"
        #else
        arch = "x86-64" // Default to x86-64 for unknown architectures
        #endif
        
        // Platform info for macOS
        let platformInfo = [
            "os": "mac",
            "arch": arch,
            "nacl_arch": arch  // Same as arch since NaCl isn't supported
        ]
        
        // Use secure callback handler to invoke the callback
        callbackHandler.invokeCallback(requestId: requestId, result: platformInfo, in: message.webView)
    }
}
