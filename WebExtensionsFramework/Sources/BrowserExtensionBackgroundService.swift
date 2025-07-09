// BrowserExtensionBackgroundService.swift
// Background script service for running extension background scripts in hidden WKWebViews

import Foundation
import WebKit

/// Protocol for managing background script execution in extensions
@MainActor
public protocol BrowserExtensionBackgroundServiceProtocol {
    /// Start a background script for the given extension
    /// - Parameter browserExtension: The extension to start background script for
    /// - Returns: The webview running the background script, or nil if no background script exists
    /// - Throws: Error if background script cannot be started
    func startBackgroundScript(for browserExtension: BrowserExtension) async throws -> BrowserExtensionWKWebView?
    
    /// Stop background script for the given extension ID
    /// - Parameter extensionId: The extension ID to stop background script for
    func stopBackgroundScript(for extensionId: UUID)
    
    /// Stop all running background scripts
    func stopAllBackgroundScripts()
    
    /// Check if background script is active for the given extension ID
    /// - Parameter extensionId: The extension ID to check
    /// - Returns: True if background script is active
    func isBackgroundScriptActive(for extensionId: UUID) -> Bool
    
    /// Get list of extension IDs with active background scripts
    var activeBackgroundScriptExtensionIds: Set<UUID> { get }
    
    /// Delegate to access active extension content worlds
    var activeManagerDelegate: BrowserExtensionActiveManagerProtocol? { get set }
    
    /// Evaluate JavaScript in a specific extension's background script context
    /// - Parameters:
    ///   - javascript: The JavaScript code to evaluate
    ///   - extensionId: The extension ID to evaluate in
    /// - Returns: The result of the JavaScript evaluation
    func evaluateJavaScript(_ javascript: String, in extensionId: UUID) async throws -> Any?
}

/// Implementation of background service that runs extension background scripts in hidden WKWebViews
@MainActor
public class BrowserExtensionBackgroundService: BrowserExtensionBackgroundServiceProtocol {
    @MainActor
    private class BackgroundJob {
        let webView: WKWebView
        let navigationDelegate: BackgroundScriptNavigationDelegate
        let uiDelegate: BackgroundScriptUIDelegate
        let consoleMessageHandler: ConsoleMessageHandler
        let timer: Timer

        init(id: UUID,
             webView: WKWebView,
             navigationDelegate: BackgroundScriptNavigationDelegate,
             uiDelegate: BackgroundScriptUIDelegate,
             consoleMessageHandler: ConsoleMessageHandler,
             logger: BrowserExtensionLogger) {
            self.webView = webView
            self.navigationDelegate = navigationDelegate
            self.uiDelegate = uiDelegate
            self.consoleMessageHandler = consoleMessageHandler

            // TODO: There's a bunch of logic around when to tear down idle workers, how to detect
            // idleness, and so on. This is a workaround to prevent WKWebView from halting JS
            // execution, but it is wasteful without the other logic around stopping it.
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { _ in
                webView.evaluateJavaScript("true;")
            })
        }

        deinit {
            timer.invalidate()
        }
    }
    /// Map of extension ID to background job state
    private var jobs: [UUID: BackgroundJob] = [:]

    /// Hidden container view for WKWebViews (must be in view hierarchy)
    private let hiddenContainer: NSView
    
    /// Logger for debugging and error reporting
    private let logger: BrowserExtensionLogger
    
    /// Whether to use ephemeral data store (for incognito mode)
    private let useEphemeralDataStore: Bool
    
    /// URL scheme handler for isolated extension origins
    private let urlSchemeHandler: BrowserExtensionURLSchemeHandler
    
    /// Delegate to access active extension content worlds
    public weak var activeManagerDelegate: BrowserExtensionActiveManagerProtocol?
    
    /// Initialize background service
    /// - Parameters:
    ///   - hiddenContainer: Hidden container view for WKWebViews
    ///   - logger: Logger for debugging and error reporting
    ///   - useEphemeralDataStore: Whether to use ephemeral data store
    ///   - urlSchemeHandler: URL scheme handler for isolated origins
    public init(hiddenContainer: NSView, logger: BrowserExtensionLogger, useEphemeralDataStore: Bool, urlSchemeHandler: BrowserExtensionURLSchemeHandler) {
        self.hiddenContainer = hiddenContainer
        self.logger = logger
        self.useEphemeralDataStore = useEphemeralDataStore
        self.urlSchemeHandler = urlSchemeHandler
    }
    
    public func startBackgroundScript(for browserExtension: BrowserExtension) async throws -> BrowserExtensionWKWebView? {
        let extensionId = browserExtension.id

        // Check if already running
        if let existingJob = jobs[extensionId] {
            logger.debug("Background script already running for extension: \(extensionId)")
            return existingJob.webView
        }
        
        // Check if extension has background script
        guard let backgroundResource = browserExtension.backgroundScriptResource else {
            logger.debug("No background script for extension: \(extensionId)")
            return nil
        }
        
        logger.info("Starting background script for extension: \(extensionId)")
        
        // Create WebView using factory
        let factoryConfiguration = BrowserExtensionWebViewFactory.Configuration(
            extensionId: extensionId.uuidString,
            logger: logger,
            urlSchemeHandler: urlSchemeHandler,
            hiddenContainer: hiddenContainer,
            useEphemeralDataStore: useEphemeralDataStore
        )

        let webView = try BrowserExtensionWebViewFactory.createWebView(
            type: .backgroundScript,
            configuration: factoryConfiguration
        )
        
        // Console handler will be added by BrowserExtensionActiveManager when registering the webview
        let consoleHandler = ConsoleMessageHandler(logger: logger, extensionId: extensionId)
        
        // Inject extension background script in .page world (where webkit.messageHandlers is available)
        if let backgroundResource = browserExtension.backgroundScriptResource {
            let backgroundUserScript = WKUserScript(
                source: backgroundResource.jsContent,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false,
                in: .page
            )
            webView.configuration.userContentController.addUserScript(backgroundUserScript)
        }

        // Register the background script with the URL scheme handler
        urlSchemeHandler.registerBackgroundScript(backgroundResource, for: extensionId)
        
        // Load the background page from custom scheme for isolated origin
        let backgroundURL = BrowserExtensionURLSchemeHandler.backgroundPageURL(for: extensionId)
        
        // Create security delegates that will persist for the lifetime of the WebView
        let navigationDelegate = BackgroundScriptNavigationDelegate(
            allowedURL: backgroundURL,
            logger: logger,
            extensionId: extensionId
        )
        let uiDelegate = BackgroundScriptUIDelegate(
            logger: logger,
            extensionId: extensionId
        )
        
        // Store strong references to delegates
        jobs[extensionId] = .init(id: extensionId,
                                  webView: webView,
                                  navigationDelegate: navigationDelegate,
                                  uiDelegate: uiDelegate,
                                  consoleMessageHandler: consoleHandler,
                                  logger: logger)

        // Assign delegates to WebView
        webView.navigationDelegate = navigationDelegate
        webView.uiDelegate = uiDelegate

        do {
            // Load the background page
            let request = URLRequest(url: backgroundURL)
            _ = webView.load(request)

            // Wait for navigation to complete with cancellation support
            try await withTaskCancellationHandler {
                try await navigationDelegate.waitForLoad()
            } onCancel: {
                // Cancel the navigation if the Task is cancelled
                Task { @MainActor in
                    webView.stopLoading()
                    navigationDelegate.cancelWaitForLoad()
                }
            }
        } catch {
            // Clean up if loading fails to prevent resource leaks
            stopBackgroundScript(for: extensionId)
            throw error
        }
        
        logger.info("Background script loaded for: \(extensionId)")
        return webView
    }
    
    public func stopBackgroundScript(for extensionId: UUID) {
        guard let job = jobs[extensionId] else {
            logger.debug("No background script running for extension: \(extensionId)")
            return
        }
        let webView = job.webView
        logger.info("Stopping background script for extension: \(extensionId)")
        
        // Cancel any in-flight navigation to prevent 404 errors
        webView.stopLoading()
        
        // Clear delegates
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        
        // Remove console message handler
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "consoleLog")

        // Remove from container
        webView.removeFromSuperview()
        
        // Unregister from URL scheme handler
        urlSchemeHandler.unregisterBackgroundScript(for: extensionId)
        
        // Remove all references
        jobs.removeValue(forKey: extensionId)

        logger.debug("Background script stopped for extension: \(extensionId)")
    }
    
    public func stopAllBackgroundScripts() {
        logger.info("Stopping all background scripts")
        
        let extensionIds = Array(jobs.keys)
        for extensionId in extensionIds {
            stopBackgroundScript(for: extensionId)
        }
        
        logger.debug("All background scripts stopped")
    }
    
    public func isBackgroundScriptActive(for extensionId: UUID) -> Bool {
        return jobs[extensionId] != nil
    }
    
    public var activeBackgroundScriptExtensionIds: Set<UUID> {
        return Set(jobs.keys)
    }
    
    public func evaluateJavaScript(_ javascript: String, in extensionId: UUID) async throws -> Any? {
        guard let webView = jobs[extensionId]?.webView else {
            throw NSError(domain: "BrowserExtensionBackgroundService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No background script running for extension: \(extensionId)"
            ])
        }
        
        // Get the extension's content world from the active manager
        guard let activeManager = activeManagerDelegate,
              let activeExtension = activeManager.activeExtension(for: extensionId) else {
            throw BrowserExtensionError.internalError("Extension not active or no active manager: \(extensionId)")
        }
        
        // Evaluate in the extension's content world where Chrome APIs are injected
        return try await webView.be_evaluateJavaScript(javascript, in: nil, in: activeExtension.contentWorld)
    }
}

/// Navigation delegate that uses async/await for page load completion
/// and provides security by blocking all navigation except the initial background page
private class BackgroundScriptNavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private let allowedURL: URL
    private let logger: BrowserExtensionLogger
    private let extensionId: UUID
    private var navigationCount = 0

    init(allowedURL: URL, logger: BrowserExtensionLogger, extensionId: UUID) {
        self.allowedURL = allowedURL
        self.logger = logger
        self.extensionId = extensionId
        super.init()
    }
    
    func waitForLoad() async throws {
        try await withCheckedThrowingContinuation { continuation in
            // WK callbacks always come on main thread, so no locking needed
            self.continuation = continuation
        }
    }

    func cancelWaitForLoad() {
        if let saved = continuation {
            continuation = nil
            saved.resume()
        }
    }

    // Only allow the initial background page URL
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationCount > 0 {
            logger.error("Navigation blocked - already allowed one through. url=\(navigationAction.request.url?.absoluteString ?? "(nil)")")
            decisionHandler(.cancel)
            return
        }
        navigationCount += 1
        guard let url = navigationAction.request.url else {
            logger.error("Navigation blocked - no URL for extension: \(extensionId)")
            decisionHandler(.cancel)
            return
        }
        
        if url == allowedURL {
            logger.debug("Navigation allowed for background page: \(url) (extension: \(extensionId))")
            decisionHandler(.allow)
        } else {
            logger.error("Navigation blocked to unauthorized URL: \(url) (extension: \(extensionId))")
            decisionHandler(.cancel)
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
    
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logger.info("WebView process terminated during navigation for extension: \(extensionId)")
        continuation?.resume(throwing: NSError(
            domain: "BrowserExtensionBackgroundService",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "WebView process terminated for extension: \(extensionId)"]
        ))
        continuation = nil
    }
}

/// UI delegate that blocks all UI interactions from background scripts
private class BackgroundScriptUIDelegate: NSObject, WKUIDelegate {
    private let logger: BrowserExtensionLogger
    private let extensionId: UUID
    
    init(logger: BrowserExtensionLogger, extensionId: UUID) {
        self.logger = logger
        self.extensionId = extensionId
        super.init()
    }
    
    // Block all attempts to create new windows/tabs
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        logger.error("Blocked attempt to create new window from background script (extension: \(extensionId))")
        return nil
    }
    
    // Block all JavaScript alerts
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        logger.error("Blocked JavaScript alert from background script: '\(message)' (extension: \(extensionId))")
        completionHandler()
    }
    
    // Block all JavaScript confirms
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        logger.error("Blocked JavaScript confirm from background script: '\(message)' (extension: \(extensionId))")
        completionHandler(false)
    }
    
    // Block all JavaScript prompts
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        logger.error("Blocked JavaScript prompt from background script: '\(prompt)' (extension: \(extensionId))")
        completionHandler(nil)
    }
    
    // Block file open panels
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        logger.error("Blocked file open panel from background script (extension: \(extensionId))")
        completionHandler(nil)
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        logger.error("Blocked media capture from background script (extension: \(extensionId))")
        decisionHandler(.deny)
    }
    
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logger.info("WebView process terminated for extension: \(extensionId)")
    }
}

/// Console message handler that forwards console.log messages to the logger
private class ConsoleMessageHandler: NSObject, WKScriptMessageHandler {
    private let logger: BrowserExtensionLogger
    private let extensionId: UUID
    
    init(logger: BrowserExtensionLogger, extensionId: UUID) {
        self.logger = logger
        self.extensionId = extensionId
        super.init()
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "consoleLog",
              let messageBody = message.body as? String else {
            return
        }
        
        logger.info("Console [\(extensionId)]: \(messageBody)")
    }
}
