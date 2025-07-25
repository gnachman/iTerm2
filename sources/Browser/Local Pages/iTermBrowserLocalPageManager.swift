//
//  iTermBrowserLocalPageManager.swift
//  iTerm2
//
//  Created by George Nachman on 6/22/25.
//

import Foundation
@preconcurrency import WebKit

// MARK: - Page Handler Protocol

@available(macOS 11.0, *)
protocol iTermBrowserPageHandler {
    @MainActor func start(urlSchemeTask: WKURLSchemeTask, url: URL)
    @MainActor func injectJavaScript(into webView: WKWebView)
    @MainActor func resetState()
}

// MARK: - Page Context

@available(macOS 11.0, *)
private struct iTermBrowserPageContext {
    let handler: any iTermBrowserPageHandler
    var messageHandlerRegistered: Bool
    let requiresMessageHandler: Bool
    
    init(handler: any iTermBrowserPageHandler, requiresMessageHandler: Bool) {
        self.handler = handler
        self.messageHandlerRegistered = false
        self.requiresMessageHandler = requiresMessageHandler
    }
}

// MARK: - Local Page Manager Delegate

@available(macOS 11.0, *)
@MainActor
protocol iTermBrowserLocalPageManagerDelegate: AnyObject {
    func localPageManagerDidUpdateAdblockSettings(_ manager: iTermBrowserLocalPageManager)
    func localPageManagerDidRequestAdblockUpdate(_ manager: iTermBrowserLocalPageManager)
    func localPageManagerDidNavigateToURL(_ manager: iTermBrowserLocalPageManager, url: String)
    func localPageManagerWebView(_ manager: iTermBrowserLocalPageManager) -> WKWebView?
    func localPageManagerExtensionManager(_ manager: iTermBrowserLocalPageManager) -> iTermBrowserExtensionManagerProtocol?
}

// MARK: - Local Page Manager

struct iTermBrowserSchemes {
    static let about = "iterm2-about"
}

@available(macOS 11.0, *)
@MainActor
class iTermBrowserLocalPageManager: NSObject {
    weak var delegate: iTermBrowserLocalPageManagerDelegate?
    private var activePageContexts: [String: iTermBrowserPageContext] = [:]
    private let historyController: iTermBrowserHistoryController
    private let user: iTermBrowserUser

    init(user: iTermBrowserUser,
         historyController: iTermBrowserHistoryController) {
        self.user = user
        self.historyController = historyController
        super.init()
    }
    
    // MARK: - Public API
    
    /// Prepare page context for navigation to a local page
    func prepareForNavigation(to url: URL) {
        let urlString = url.absoluteString
        guard urlString.hasPrefix(iTermBrowserSchemes.about + ":") else { return }

        setupPageContext(for: urlString)
    }
    
    /// Handle URL scheme task for local pages
    func handleURLSchemeTask(_ urlSchemeTask: WKURLSchemeTask, url: URL) -> Bool {
        let urlString = url.absoluteString
        guard urlString.hasPrefix(iTermBrowserSchemes.about + ":") else { return false }

        setupPageContext(for: urlString)
        
        guard let context = activePageContexts[urlString] else {
            urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserLocalPageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown \(iTermBrowserSchemes.about) URL"]))
            return true
        }
        
        context.handler.start(urlSchemeTask: urlSchemeTask, url: url)

        return true
    }
    
    /// Setup message handlers for current page
    func setupMessageHandlers(for webView: WKWebView, currentURL: String?) {
        guard let currentURL = currentURL else { return }
        
        // Setup context for current page if needed
        setupPageContext(for: currentURL)
        
        // Message handler registration will be done by the browser manager
    }
    
    /// Handle JavaScript message from local page
    func handleMessage(_ message: WKScriptMessage, webView: WKWebView, currentURL: URL?) -> Bool {
        guard let messageDict = message.body as? [String: Any],
              let currentURL = currentURL else {
            return false
        }
        
        // Route message based on URL (message.name is now the URL)
        let messageURL = message.name
        
        // Verify the message is coming from the expected page
        guard currentURL.absoluteString == messageURL,
              let webViewURL = webView.url?.absoluteString,
              webViewURL == messageURL else {
            DLog("Message from wrong URL: webView=\(webView.url?.absoluteString ?? "nil"), currentURL=\(currentURL.absoluteString), message=\(messageURL)")
            return false
        }
        
        guard let context = activePageContexts[messageURL] else {
            DLog("No active context for message URL: \(messageURL)")
            return false
        }
        
        return handleMessageForContext(context, messageURL: messageURL, messageDict: messageDict, message: message, webView: webView)
    }
    
    /// Reset state for all active handlers
    func resetAllHandlerState() {
        for context in activePageContexts.values {
            context.handler.resetState()
        }
    }
    
    /// Show error page
    func showErrorPage(for error: Error, failedURL: URL?, webView: WKWebView) {
        let urlString = iTermBrowserErrorHandler.errorURL.absoluteString
        setupPageContext(for: urlString)
        
        guard let context = activePageContexts[urlString],
              let errorHandler = context.handler as? iTermBrowserErrorHandler else {
            return
        }
        
        let errorHTML = errorHandler.generateErrorPageHTML(for: error, failedURL: failedURL)
        errorHandler.setPendingErrorHTML(errorHTML)
        
        // Navigate to iterm2-about:error which our custom URL scheme handler will serve
        webView.load(URLRequest(url: iTermBrowserErrorHandler.errorURL))
    }
    
    /// Show source page
    func showSourcePage(htmlSource: String, url: URL, webView: WKWebView) {
        let urlString = iTermBrowserSourceHandler.sourceURL.absoluteString
        setupPageContext(for: urlString)
        
        guard let context = activePageContexts[urlString],
              let sourceHandler = context.handler as? iTermBrowserSourceHandler else {
            return
        }
        
        // Generate the formatted source page HTML
        let sourceHTML = sourceHandler.generateSourcePageHTML(for: htmlSource, url: url)
        
        // Store the source HTML to serve when iterm2-about:source is requested
        sourceHandler.setPendingSourceHTML(sourceHTML)
        
        // Navigate to iterm2-about:source which our custom URL scheme handler will serve
        webView.load(URLRequest(url: iTermBrowserSourceHandler.sourceURL))
    }
    
    /// Notify settings page of adblock update
    func notifySettingsPageOfAdblockUpdate(success: Bool, error: String?, webView: WKWebView) {
        let urlString = iTermBrowserSettingsHandler.settingsURL.absoluteString
        if let context = activePageContexts[urlString],
           let settingsHandler = context.handler as? iTermBrowserSettingsHandler {
            if success {
                settingsHandler.showAdblockUpdateSuccess(in: webView)
            } else if let error = error {
                settingsHandler.showAdblockUpdateError(error, in: webView)
            }
        }
    }
    
    /// Check if message handler should be registered for URL
    func shouldRegisterMessageHandler(for urlString: String) -> Bool {
        guard let context = activePageContexts[urlString] else { return false }
        return context.requiresMessageHandler && !context.messageHandlerRegistered
    }
    
    /// Mark message handler as registered for URL
    func markMessageHandlerRegistered(for urlString: String) {
        guard var context = activePageContexts[urlString] else { return }
        context.messageHandlerRegistered = true
        activePageContexts[urlString] = context
    }
    
    /// Inject JavaScript for URL
    func injectJavaScript(for urlString: String, webView: WKWebView) {
        guard let context = activePageContexts[urlString] else { return }
        context.handler.injectJavaScript(into: webView)
    }
}

// MARK: - Private Implementation

@available(macOS 11.0, *)
private extension iTermBrowserLocalPageManager {
    
    func setupPageContext(for urlString: String) {
        guard activePageContexts[urlString] == nil else { return }
        
        let context: iTermBrowserPageContext?
        
        switch urlString {
        case iTermBrowserSettingsHandler.settingsURL.absoluteString:
            let handler = iTermBrowserSettingsHandler(user: user)
            handler.delegate = self
            // Set up extension manager delegate for automatic refresh
            if let extensionManager = delegate?.localPageManagerExtensionManager(self) {
                extensionManager.delegate = handler
            }
            context = iTermBrowserPageContext(handler: handler, requiresMessageHandler: true)
            
        case iTermBrowserHistoryViewHandler.historyURL.absoluteString:
            let handler = iTermBrowserHistoryViewHandler(user: user,
                                                         historyController: historyController)
            handler.delegate = self
            context = iTermBrowserPageContext(handler: handler, requiresMessageHandler: true)
            
        case iTermBrowserBookmarkViewHandler.bookmarksURL.absoluteString:
            let handler = iTermBrowserBookmarkViewHandler(user: user)
            handler.delegate = self
            context = iTermBrowserPageContext(handler: handler, requiresMessageHandler: true)
            
        case iTermBrowserPermissionsViewHandler.permissionsURL.absoluteString:
            let handler = iTermBrowserPermissionsViewHandler(user: user)
            handler.delegate = self
            context = iTermBrowserPageContext(handler: handler, requiresMessageHandler: true)
            
        case iTermBrowserErrorHandler.errorURL.absoluteString:
            context = iTermBrowserPageContext(handler: iTermBrowserErrorHandler(), requiresMessageHandler: false)
            
        case iTermBrowserSourceHandler.sourceURL.absoluteString:
            context = iTermBrowserPageContext(handler: iTermBrowserSourceHandler(), requiresMessageHandler: false)
            
        default:
            // Check if this is a registered static page
            if let staticConfig = iTermBrowserStaticPageRegistry.shared.getConfig(for: urlString) {
                let handler = iTermBrowserStaticPageHandler(config: staticConfig)
                context = iTermBrowserPageContext(handler: handler, requiresMessageHandler: false)
            } else {
                context = nil
            }
        }
        
        if let context = context {
            activePageContexts[urlString] = context
        }
    }
    
    
    func handleMessageForContext(_ context: iTermBrowserPageContext, messageURL: String, messageDict: [String: Any], message: WKScriptMessage, webView: WKWebView) -> Bool {
        switch messageURL {
        case iTermBrowserSettingsHandler.settingsURL.absoluteString:
            if let settingsHandler = context.handler as? iTermBrowserSettingsHandler {
                settingsHandler.handleSettingsMessage(messageDict, webView: webView)
                return true
            }
            
        case iTermBrowserHistoryViewHandler.historyURL.absoluteString:
            if let historyHandler = context.handler as? iTermBrowserHistoryViewHandler,
               let webView = message.webView {
                DLog("Received history message, forwarding to handler")
                Task { @MainActor in
                    await historyHandler.handleHistoryMessage(messageDict, webView: webView)
                }
                return true
            }
            
        case iTermBrowserBookmarkViewHandler.bookmarksURL.absoluteString:
            if let bookmarkHandler = context.handler as? iTermBrowserBookmarkViewHandler,
               let webView = message.webView {
                DLog("Received bookmark message, forwarding to handler")
                Task { @MainActor in
                    await bookmarkHandler.handleBookmarkMessage(messageDict, webView: webView)
                }
                return true
            }
            
        case iTermBrowserPermissionsViewHandler.permissionsURL.absoluteString:
            if let permissionsHandler = context.handler as? iTermBrowserPermissionsViewHandler,
               let webView = message.webView {
                DLog("Received permissions message, forwarding to handler")
                Task { @MainActor in
                    await permissionsHandler.handlePermissionMessage(messageDict, webView: webView)
                }
                return true
            }
            
        default:
            DLog("Unknown message URL: \(messageURL)")
        }
        
        return false
    }
}


// MARK: - Handler Delegates

@available(macOS 11.0, *)
extension iTermBrowserLocalPageManager: iTermBrowserSettingsHandlerDelegate {
    func settingsHandlerDidUpdateAdblockSettings(_ handler: iTermBrowserSettingsHandler) {
        delegate?.localPageManagerDidUpdateAdblockSettings(self)
    }
    
    func settingsHandlerDidRequestAdblockUpdate(_ handler: iTermBrowserSettingsHandler) {
        delegate?.localPageManagerDidRequestAdblockUpdate(self)
    }
    
    func settingsHandlerWebView(_ handler: iTermBrowserSettingsHandler) -> WKWebView? {
        return delegate?.localPageManagerWebView(self)
    }
    
    func settingsHandlerExtensionManager(_ handler: iTermBrowserSettingsHandler) -> iTermBrowserExtensionManagerProtocol? {
        return delegate?.localPageManagerExtensionManager(self)
    }
}

@available(macOS 11.0, *)
extension iTermBrowserLocalPageManager: iTermBrowserHistoryViewHandlerDelegate {
    func historyViewHandlerDidNavigateToURL(_ handler: iTermBrowserHistoryViewHandler, url: String) {
        delegate?.localPageManagerDidNavigateToURL(self, url: url)
    }
}

@available(macOS 11.0, *)
extension iTermBrowserLocalPageManager: iTermBrowserBookmarkViewHandlerDelegate {
    func bookmarkViewHandlerDidNavigateToURL(_ handler: iTermBrowserBookmarkViewHandler, url: String) {
        delegate?.localPageManagerDidNavigateToURL(self, url: url)
    }
}

@available(macOS 11.0, *)
extension iTermBrowserLocalPageManager: iTermBrowserPermissionsViewHandlerDelegate {
    func permissionsViewHandlerDidRevokeAllPermissions(_ handler: iTermBrowserPermissionsViewHandler, for origin: String) {
        // Notify the browser controller that permissions have been revoked
        // This allows the browser to update any cached permission state
        DLog("All permissions revoked for origin: \(origin)")
    }
}
