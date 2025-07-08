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
    func injectRuntimeAPIs(into webView: WKWebView,
                           dispatcher: BrowserExtensionDispatcher,
                           router: BrowserExtensionRouter,
                           network: BrowserExtensionNetwork) {
        logger.info("Injecting chrome.runtime APIs into webview")
        
        // Register webview with the network so it can receive messages
        network.add(webView: webView, browserExtension: browserExtension)
        
        // Create shared callback handler for secure callback dispatch
        let callbackHandler = BrowserExtensionSecureCallbackHandler(
            logger: logger,
            function: .invokeCallback)

        // Add message handler for chrome.runtime.* native calls (id is now synchronous)
        webView.configuration.userContentController.add(
            BrowserExtensionAPIRequestMessageHandler(
                callbackHandler: callbackHandler,
                dispatcher: dispatcher,
                logger: logger
            ),
            name: "requestBrowserExtension"
        )

        // Add message handler for onMessage listeners
        webView.configuration.userContentController.add(
            BrowserExtensionListenerResponseHandler(
                router: router,
                logger: logger
            ),
            name: "listenerResponseBrowserExtension"
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


