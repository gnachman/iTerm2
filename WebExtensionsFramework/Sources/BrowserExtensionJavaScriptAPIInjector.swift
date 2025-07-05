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
    
    /// Injects the chrome.runtime.getId API into a webview
    /// - Parameter webView: The webview to inject APIs into
    func injectRuntimeIdAPI(into webView: WKWebView) {
        logger.info("Injecting chrome.runtime.getId API into webview")
        
        // Add message handler for runtime.id requests
        let messageHandlerName = "requestRuntimeId"
        webView.configuration.userContentController.add(
            BrowserExtensionRuntimeIdMessageHandler(
                browserExtension: browserExtension,
                logger: logger
            ),
            name: messageHandlerName
        )
        
        // Get the JavaScript to inject
        let injectionScript = createRuntimeIdInjectionScript()
        
        // Create and add the user script
        let userScript = WKUserScript(
            source: injectionScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page)
        
        webView.configuration.userContentController.addUserScript(userScript)
    }
    
    // MARK: - Private Methods
    
    private func createRuntimeIdInjectionScript() -> String {
        return """
        // Injected at document start
        ;(function() {
          // 1. Ensure the callback-style host API namespace exists
          window.chrome = window.chrome || {};
          chrome.runtime = chrome.runtime || {};

          // 2. Define a callback-style getId method
          chrome.runtime.getId = function(callback) {
            // Store the callback so the native side can invoke it later
            window.__runtimeIdCallback = callback;
            // Ask the native host for the ID
            window.webkit.messageHandlers.requestRuntimeId.postMessage(null);
          };
        })();
        """
    }
}

/// Message handler for chrome.runtime.getId requests
class BrowserExtensionRuntimeIdMessageHandler: NSObject, WKScriptMessageHandler {
    
    private let browserExtension: BrowserExtension
    private let logger: BrowserExtensionLogger
    
    init(browserExtension: BrowserExtension, logger: BrowserExtensionLogger) {
        self.browserExtension = browserExtension
        self.logger = logger
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        logger.info("Received runtime.getId request from JavaScript")
        
        // Get the extension ID
        let extensionId = browserExtension.id.uuidString
        
        // Invoke the callback in JavaScript
        let callbackScript = """
        if (window.__runtimeIdCallback) {
            window.__runtimeIdCallback('\(extensionId)');
            delete window.__runtimeIdCallback;
        }
        """
        
        message.webView?.evaluateJavaScript(callbackScript) { [weak self] result, error in
            if let error = error {
                self?.logger.error("Error invoking runtime.getId callback: \(error)")
            } else {
                self?.logger.info("Successfully invoked runtime.getId callback with: \(extensionId)")
            }
        }
    }
}
