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
    func injectRuntimeAPIs(into webView: WKWebView, dispatcher: BrowserExtensionDispatcher) {
        logger.info("Injecting chrome.runtime APIs into webview")
        
        // Create shared callback handler for secure callback dispatch
        let callbackHandler = BrowserExtensionSecureCallbackHandler(
            logger: logger,
            function: .invokeCallback)

        // Add message handler for getPlatformInfo (id is now synchronous)
        webView.configuration.userContentController.add(
            BrowserExtensionMessageHandler(
                callbackHandler: callbackHandler,
                dispatcher: dispatcher,
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
        return generatedAPIJavascript(.init(extensionId: browserExtension.id.uuidString))
    }
}


/// Message handler for chrome.runtime.getPlatformInfo requests
class BrowserExtensionMessageHandler: NSObject, WKScriptMessageHandler {
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
        logger.info("Received runtime.getPlatformInfo request from JavaScript")
        
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
