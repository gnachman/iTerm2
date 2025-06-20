//
//  iTermBrowserManager.swift
//  iTerm2
//
//  Created by George Nachman on 6/18/25.
//

@preconcurrency import WebKit

@available(macOS 11.0, *)
@objc protocol iTermBrowserManagerDelegate: AnyObject {
    func browserManager(_ manager: iTermBrowserManager, didUpdateURL url: String?)
    func browserManager(_ manager: iTermBrowserManager, didUpdateTitle title: String?)
    func browserManager(_ manager: iTermBrowserManager, didUpdateFavicon favicon: NSImage?)
    func browserManager(_ manager: iTermBrowserManager, didUpdateCanGoBack canGoBack: Bool)
    func browserManager(_ manager: iTermBrowserManager, didUpdateCanGoForward canGoForward: Bool)
    func browserManager(_ manager: iTermBrowserManager, didStartNavigation navigation: WKNavigation?)
    func browserManager(_ manager: iTermBrowserManager, didFinishNavigation navigation: WKNavigation?)
    func browserManager(_ manager: iTermBrowserManager, didFailNavigation navigation: WKNavigation?, withError error: Error)
    func browserManager(_ manager: iTermBrowserManager, requestNewWindowForURL url: URL, configuration: WKWebViewConfiguration) -> WKWebView?
}

@available(macOS 11.0, *)
@objc(iTermBrowserManager)
class iTermBrowserManager: NSObject, WKURLSchemeHandler, WKScriptMessageHandler, iTermBrowserWebViewDelegate {
    weak var delegate: iTermBrowserManagerDelegate?
    private(set) var webView: iTermBrowserWebView!
    private var lastFailedURL: URL?
    private var errorHandler = iTermBrowserErrorHandler()
    private var settingsHandler = iTermBrowserSettingsHandler()
    private var sourceHandler = iTermBrowserSourceHandler()
    private var historyViewHandler: iTermBrowserHistoryViewHandler
    private var currentPageURL: URL?
    private var hasSettingsMessageHandler = false
    private var hasHistoryMessageHandler = false
    private static let settingsMessageHandlerName = "iterm2BrowserSettings"
    private static let historyMessageHandlerName = "iterm2BrowserHistory"
    private(set) var favicon: NSImage?
    private var _findManager: Any?
    private var adblockManager: iTermAdblockManager?
    let sessionGuid: String
    let historyController: iTermBrowserHistoryController
    private let navigationState: iTermBrowserNavigationState

    init(configuration: WKWebViewConfiguration?,
         sessionGuid: String,
         historyController: iTermBrowserHistoryController,
         navigationState: iTermBrowserNavigationState) {
        self.sessionGuid = sessionGuid
        self.historyController = historyController
        self.navigationState = navigationState
        self.historyViewHandler = iTermBrowserHistoryViewHandler(historyController: historyController)
        super.init()

        historyViewHandler.delegate = self
        setupWebView(configuration: configuration)
    }
    
    private func setupWebView(configuration preferredConfiguration: WKWebViewConfiguration?) {
        let configuration: WKWebViewConfiguration
        if let preferredConfiguration {
            configuration = preferredConfiguration
        } else {
            let prefs = WKPreferences()

            // block JS-only popups
            prefs.javaScriptCanOpenWindowsAutomatically = false
            configuration = WKWebViewConfiguration()
            configuration.preferences = prefs

            // Trick google into thinking we're a real browser. Who knows what this might break.
            configuration.applicationNameForUserAgent = "Safari/16.4"

            // Register custom URL scheme handler for iterm2-about: URLs
            configuration.setURLSchemeHandler(self, forURLScheme: "iterm2-about")
        }


        webView = iTermBrowserWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.browserDelegate = self
        
        // Enable back/forward navigation
        webView.allowsBackForwardNavigationGestures = true
        
        // Initialize find manager for macOS 13+
        if #available(macOS 13.0, *) {
            _findManager = iTermBrowserFindManager(webView: webView)
        }
        
        // Setup adblocking
        setupAdblocking()
        
        // Setup settings delegate
        setupSettingsDelegate()
    }
    
    // MARK: - Public Interface
    
    func loadURL(_ urlString: String) {
        guard let url = normalizeURL(urlString) else {
            // TODO: Handle invalid URL
            return
        }
        
        navigationState.willLoadURL(url)
        errorHandler.clearPendingError()
        lastFailedURL = nil  // Reset failed URL when loading new URL
        favicon = nil  // Clear favicon when loading new URL
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    func goBack() {
        if webView.canGoBack {
            favicon = nil  // Clear favicon when navigating
            webView.goBack()
        }
    }
    
    func goForward() {
        if webView.canGoForward {
            favicon = nil  // Clear favicon when navigating
            webView.goForward()
        }
    }
    
    func reload() {
        // Always reload current page
        webView.reload()
    }
    
    func stop() {
        webView.stopLoading()
    }
    
    func getBackHistoryItems() -> [iTermBrowserHistoryItem] {
        var items: [iTermBrowserHistoryItem] = []
        let backList = webView.backForwardList.backList
        
        for (index, item) in backList.enumerated().reversed() {
            let steps = -(backList.count - index)  // Most recent back item = -1, next = -2, etc.
            let historyItem = iTermBrowserHistoryItem(
                title: item.title ?? "",
                url: item.url.absoluteString,
                steps: steps
            )
            items.append(historyItem)
        }
        
        return items
    }
    
    func getForwardHistoryItems() -> [iTermBrowserHistoryItem] {
        var items: [iTermBrowserHistoryItem] = []
        let forwardList = webView.backForwardList.forwardList
        
        for (index, item) in forwardList.enumerated() {
            let steps = index + 1  // Positive steps for going forward
            let historyItem = iTermBrowserHistoryItem(
                title: item.title ?? "",
                url: item.url.absoluteString,
                steps: steps
            )
            items.append(historyItem)
        }
        
        return items
    }
    
    func navigateHistory(steps: Int) {
        if steps == -1 && webView.canGoBack {
            webView.goBack()
        } else if steps == 1 && webView.canGoForward {
            webView.goForward()
        } else if steps != 0 {
            // For multi-step navigation, use go(to:)
            let backForwardList = webView.backForwardList
            var targetItem: WKBackForwardListItem?
            
            if steps < 0 {
                // Going back
                let backList = backForwardList.backList
                let index = abs(steps) - 1
                if index < backList.count {
                    targetItem = backList[backList.count - 1 - index]
                }
            } else {
                // Going forward
                let forwardList = backForwardList.forwardList
                let index = steps - 1
                if index < forwardList.count {
                    targetItem = forwardList[index]
                }
            }
            
            if let targetItem = targetItem {
                favicon = nil  // Clear favicon when navigating
                webView.go(to: targetItem)
            }
        }
    }
    
    // MARK: - Find Support
    
    @available(macOS 13.0, *)
    @objc var browserFindManager: iTermBrowserFindManager? {
        return _findManager as? iTermBrowserFindManager
    }
    
    @objc var supportsFinding: Bool {
        if #available(macOS 13.0, *) {
            return _findManager != nil
        }
        return false
    }
    
    private func showErrorPage(for error: Error, failedURL: URL?) {
        let errorHTML = errorHandler.generateErrorPageHTML(for: error, failedURL: failedURL)
        
        // Store the error HTML to serve when iterm2-about:error is requested
        errorHandler.setPendingErrorHTML(errorHTML)
        
        // Navigate to iterm2-about:error which our custom URL scheme handler will serve
        webView.load(URLRequest(url: iTermBrowserErrorHandler.errorURL))
    }
    
    private func isDownloadRelatedError(_ error: Error) -> Bool {
        let nsError = error as NSError
        
        // Check for common download-related error codes
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCancelled:
                // Navigation was cancelled, likely due to download policy
                return true
            default:
                break
            }
        }
        
        // Check for WebKit-specific cancellation
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 {
            // Frame load interrupted
            return true
        }
        
        return false
    }
    
    // MARK: - Private Helpers

    private func notifyDelegateOfUpdates() {
        delegate?.browserManager(self, didUpdateURL: webView.url?.absoluteString)
        delegate?.browserManager(self, didUpdateTitle: webView.title)
        delegate?.browserManager(self, didUpdateCanGoBack: webView.canGoBack)
        delegate?.browserManager(self, didUpdateCanGoForward: webView.canGoForward)
    }
    
    private func notifyDelegateOfFaviconUpdate() {
        delegate?.browserManager(self, didUpdateFavicon: favicon)
    }
    

    private func loadFavicon(from url: URL) {
        // Use URLSession to download favicon
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  error == nil,
                  let image = NSImage(data: data) else {
                return
            }
            
            DispatchQueue.main.async {
                self.favicon = image
                self.notifyDelegateOfFaviconUpdate()
            }
        }.resume()
    }
    
    private func injectMessageHandlersIfNeeded() {
        guard let currentURL = webView.url?.absoluteString else { return }
        
        // Handle settings page
        if currentURL == iTermBrowserSettingsHandler.settingsURL.absoluteString {
            // Add message handler for settings only if not already added
            if !hasSettingsMessageHandler {
                webView.configuration.userContentController.add(self, name: Self.settingsMessageHandlerName)
                hasSettingsMessageHandler = true
            }
            settingsHandler.injectSettingsJavaScript(into: webView)
        } else {
            // Remove message handler when not on settings page
            if hasSettingsMessageHandler {
                webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.settingsMessageHandlerName)
                hasSettingsMessageHandler = false
            }
        }
        
        // Handle history page
        if currentURL == iTermBrowserHistoryViewHandler.historyURL.absoluteString {
            // Add message handler for history only if not already added
            if !hasHistoryMessageHandler {
                DLog("Adding history message handler for URL: \(currentURL)")
                webView.configuration.userContentController.add(self, name: Self.historyMessageHandlerName)
                hasHistoryMessageHandler = true
            }
        } else {
            // Remove message handler when not on history page
            if hasHistoryMessageHandler {
                DLog("Removing history message handler, current URL: \(currentURL)")
                webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.historyMessageHandlerName)
                hasHistoryMessageHandler = false
            }
        }
    }
    
    private func cleanupMessageHandlersForFailedNavigation() {
        // If navigation fails, clean up any message handlers that shouldn't be there
        // We'll re-register them properly if needed when navigation succeeds
        let currentURL = webView.url?.absoluteString ?? ""
        
        if hasHistoryMessageHandler && currentURL != iTermBrowserHistoryViewHandler.historyURL.absoluteString {
            DLog("Cleaning up history message handler after failed navigation")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.historyMessageHandlerName)
            hasHistoryMessageHandler = false
        }
        
        if hasSettingsMessageHandler && currentURL != iTermBrowserSettingsHandler.settingsURL.absoluteString {
            DLog("Cleaning up settings message handler after failed navigation")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.settingsMessageHandlerName)
            hasSettingsMessageHandler = false
        }
    }
    
}

// MARK: - WKScriptMessageHandler

@available(macOS 11.0, *)
extension iTermBrowserManager {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let messageDict = message.body as? [String: Any],
              let currentURL = currentPageURL else {
            return
        }
        
        if message.name == Self.settingsMessageHandlerName {
            // Verify the message is coming from our settings page
            guard currentURL.absoluteString == iTermBrowserSettingsHandler.settingsURL.absoluteString else {
                return
            }
            settingsHandler.handleSettingsMessage(messageDict, webView: webView)
            
        } else if message.name == Self.historyMessageHandlerName {
            // Double-verify the message is coming from our history page
            guard let webViewURL = webView.url?.absoluteString,
                  webViewURL == iTermBrowserHistoryViewHandler.historyURL.absoluteString,
                  currentURL.absoluteString == iTermBrowserHistoryViewHandler.historyURL.absoluteString else {
                DLog("History message from wrong URL: webView=\(webView.url?.absoluteString ?? "nil"), currentURL=\(currentURL.absoluteString)")
                return
            }
            DLog("Received history message, forwarding to handler")
            if let webView = message.webView {
                Task { @MainActor in
                    await historyViewHandler.handleHistoryMessage(messageDict, webView: webView)
                }
            }
        }
    }
}

// MARK: - WKURLSchemeHandler

@available(macOS 11.0, *)
extension iTermBrowserManager {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        
        switch url.absoluteString {
        case iTermBrowserErrorHandler.errorURL.absoluteString:
            errorHandler.start(urlSchemeTask: urlSchemeTask, url: url)
        case iTermBrowserSettingsHandler.settingsURL.absoluteString:
            settingsHandler.start(urlSchemeTask: urlSchemeTask, url: url)
        case iTermBrowserSourceHandler.sourceURL.absoluteString:
            sourceHandler.start(urlSchemeTask: urlSchemeTask, url: url)
        case iTermBrowserHistoryViewHandler.historyURL.absoluteString:
            historyViewHandler.start(urlSchemeTask: urlSchemeTask, url: url)
        default:
            urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown iterm2-about: URL"]))
        }
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Cancel any ongoing work if needed
    }
}

// MARK: - WKNavigationDelegate

@available(macOS 11.0, *)
extension iTermBrowserManager: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        delegate?.browserManager(self, didStartNavigation: navigation)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // URL is now committed, update UI
        notifyDelegateOfUpdates()
        
        // Track the current page URL for security checks
        if let url = webView.url {
            currentPageURL = url
        }
        
        // Setup message handlers early for our about: pages
        injectMessageHandlersIfNeeded()
        
        Task {
            await historyController.recordVisit(for: webView.url, title: webView.title)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Clear failed URL on successful navigation to a real page (not error pages)
        if webView.url != iTermBrowserErrorHandler.errorURL {
            lastFailedURL = nil
        }

        // Track the current page URL for security checks
        if let url = webView.url {
            currentPageURL = url
        }

        // Conditionally inject message handlers for our about: pages
        injectMessageHandlersIfNeeded()

        notifyDelegateOfUpdates()

        // Try to detect and load favicon
        Task {
            do {
                switch try await detectFavicon(webView: webView) {
                case .left(let image):
                    self.favicon = image
                    notifyDelegateOfFaviconUpdate()
                case .right(let url):
                    loadFavicon(from: url)
                }
            } catch {
                DLog("Failed to detect favicon: \(error)")
            }
        }
        // Update title in browser history if available
        historyController.titleDidChange(for: webView.url, title: webView.title)

        delegate?.browserManager(self, didFinishNavigation: navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let failedURL = navigationState.lastRequestedURL

        // Clean up any pre-registered message handlers for failed navigation
        cleanupMessageHandlersForFailedNavigation()

        // Don't show error page for download-related cancellations
        if isDownloadRelatedError(error) {
            delegate?.browserManager(self, didFailNavigation: navigation, withError: error)
            return
        }

        // Only show error page if this isn't the same URL that already failed
        if failedURL != lastFailedURL && failedURL != nil {
            showErrorPage(for: error, failedURL: failedURL)
            lastFailedURL = failedURL
        }

        delegate?.browserManager(self, didFailNavigation: navigation, withError: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let failedURL = navigationState.lastRequestedURL

        // Clean up any pre-registered message handlers for failed navigation
        cleanupMessageHandlersForFailedNavigation()

        // Don't show error page for download-related cancellations
        if isDownloadRelatedError(error) {
            delegate?.browserManager(self, didFailNavigation: navigation, withError: error)
            return
        }

        // Only show error page if this isn't the same URL that already failed
        if failedURL != lastFailedURL && failedURL != nil {
            showErrorPage(for: error, failedURL: failedURL)
            lastFailedURL = failedURL
        }

        delegate?.browserManager(self, didFailNavigation: navigation, withError: error)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Store the target URL for this navigation so we can use it in error handlers
        // But don't overwrite if this is our error page navigation
        if let targetURL = navigationAction.request.url, targetURL != iTermBrowserErrorHandler.errorURL {
            navigationState.willLoadURL(targetURL)
        }

        // Store the transition type for the upcoming navigation
        navigationState.willNavigate(action: navigationAction)

        // Popup blocking logic
        guard let targetURL = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        // Always allow our internal pages and prepare message handlers early
        if targetURL.absoluteString.hasPrefix("iterm2-about:") {
            // Pre-register message handlers for our internal pages
            if targetURL.absoluteString == iTermBrowserHistoryViewHandler.historyURL.absoluteString {
                if !hasHistoryMessageHandler {
                    DLog("Pre-registering history message handler for navigation to: \(targetURL.absoluteString)")
                    webView.configuration.userContentController.add(self, name: Self.historyMessageHandlerName)
                    hasHistoryMessageHandler = true
                }
            } else if targetURL.absoluteString == iTermBrowserSettingsHandler.settingsURL.absoluteString {
                if !hasSettingsMessageHandler {
                    webView.configuration.userContentController.add(self, name: Self.settingsMessageHandlerName)
                    hasSettingsMessageHandler = true
                }
            }
            decisionHandler(.allow)
            return
        }

        // Check for popup behavior
        if navigationAction.targetFrame == nil {
            // This is a popup (no target frame = new window/tab)
            switch navigationAction.navigationType {
            case .linkActivated:
                // User clicked a link - request new window from delegate
                let _ = delegate?.browserManager(self,
                                                 requestNewWindowForURL: targetURL,
                                                 configuration: webView.configuration.copy() as! WKWebViewConfiguration)
                decisionHandler(.cancel)
                return
            case .other:
                // Automatic popup (JavaScript without user interaction) - block it
                DLog("Blocked automatic popup to: \(targetURL)")
                decisionHandler(.cancel)
                return
            default:
                // Block other popup types for safety
                DLog("Blocked popup navigation type \(navigationAction.navigationType.rawValue) to: \(targetURL)")
                decisionHandler(.cancel)
                return
            }
        }

        // Regular navigation in same frame - allow
        decisionHandler(.allow)
    }

    @available(macOS 11, *)
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {

        // Check if this should be downloaded instead of displayed
        guard let response = navigationResponse.response as? HTTPURLResponse else {
            decisionHandler(.allow)
            return
        }

        // Check content disposition and content type for download triggers
        let contentDisposition = response.allHeaderFields["Content-Disposition"] as? String ?? ""
        let contentType = response.mimeType ?? ""

        // Download if:
        // 1. Content-Disposition header indicates attachment
        // 2. Content type is not something WKWebView can display well
        if #available(macOS 11.3, *) {
            if contentDisposition.lowercased().contains("attachment") ||
                !canWebViewDisplay(contentType: contentType) {
                decisionHandler(.download)
                return
            }
        }

        decisionHandler(.allow)
    }

    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView,
                 navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        handleDownload(download, sourceURL: navigationAction.request.url)
    }

    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView,
                 navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        handleDownload(download, sourceURL: navigationResponse.response.url)
    }

    @available(macOS 11.3, *)
    private func canWebViewDisplay(contentType: String) -> Bool {
        let lowerContentType = contentType.lowercased()

        // Content types that WKWebView can display well
        let displayableTypes = [
            "text/html",
            "text/plain",
            "text/css",
            "text/javascript",
            "application/javascript",
            "application/json",
            "application/xml",
            "text/xml",
            "image/png",
            "image/jpeg",
            "image/jpg",
            "image/gif",
            "image/svg+xml",
            "image/webp",
            "application/pdf",
            "video/mp4",
            "video/webm",
            "audio/mp3",
            "audio/mpeg",
            "audio/wav",
            "audio/webm"
        ]

        // If no content type specified, assume it can be displayed (let WKWebView decide)
        if lowerContentType.isEmpty {
            return true
        }

        return displayableTypes.contains { lowerContentType.hasPrefix($0) }
    }

    @available(macOS 11.3, *)
    private func handleDownload(_ download: WKDownload, sourceURL: URL?) {
        guard let sourceURL = sourceURL else { return }

        let suggestedFilename = sourceURL.lastPathComponent.isEmpty ?
        "download" : sourceURL.lastPathComponent

        let browserDownload = iTermBrowserDownload(
            wkDownload: download,
            sourceURL: sourceURL,
            suggestedFilename: suggestedFilename
        )

        // Start the download (adds to FileTransferManager)
        browserDownload.download()
    }
}

// MARK: - WKUIDelegate

@available(macOS 11.0, *)
extension iTermBrowserManager: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else {
            return nil
        }
        return delegate?.browserManager(self,
                                        requestNewWindowForURL: url,
                                        configuration: configuration)
    }
    
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        // Handle JavaScript alerts
        let alert = NSAlert()
        alert.messageText = "Web Page Alert"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }
    
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        // Handle JavaScript confirmations
        let alert = NSAlert()
        alert.messageText = "Web Page Confirmation"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        completionHandler(response == .alertFirstButtonReturn)
    }
    
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        // Handle file input elements (e.g., <input type="file">)
        guard let window = webView.window else {
            completionHandler(nil)
            return
        }
        
        let panel = iTermOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else {
                completionHandler(nil)
                return
            }
            
            // Convert iTermOpenPanelItems to URLs
            var selectedURLs: [URL] = []
            let group = DispatchGroup()
            
            for item in panel.items {
                group.enter()
                item.urlPromise.then { url in
                    selectedURLs.append(url as URL)
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                // Respect multiple selection setting
                if parameters.allowsMultipleSelection {
                    completionHandler(selectedURLs)
                } else {
                    completionHandler(selectedURLs.isEmpty ? nil : [selectedURLs.first!])
                }
            }
        }
    }

    // MARK: - iTermBrowserWebViewDelegate
    
    func webViewDidRequestViewSource(_ webView: iTermBrowserWebView) {
        viewPageSource()
    }
    
    @objc private func viewPageSource() {
        // Get the current page's HTML source
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                DLog("Error getting page source: \(error)")
                return
            }
            
            guard let htmlSource = result as? String else {
                DLog("Failed to get HTML source")
                return
            }
            
            DispatchQueue.main.async {
                self.showSourceInBrowser(htmlSource: htmlSource)
            }
        }
    }
    
    private func showSourceInBrowser(htmlSource: String) {
        // Generate the formatted source page HTML
        let sourceHTML = sourceHandler.generateSourcePageHTML(for: htmlSource)
        
        // Store the source HTML to serve when iterm2-about:source is requested
        sourceHandler.setPendingSourceHTML(sourceHTML)
        
        // Navigate to iterm2-about:source which our custom URL scheme handler will serve
        webView.load(URLRequest(url: iTermBrowserSourceHandler.sourceURL))
    }
}

@available(macOS 11.0, *)
extension iTermBrowserManager: iTermBrowserSettingsHandlerDelegate {

    // MARK: - iTermBrowserSettingsHandlerDelegate

    func settingsHandlerDidUpdateAdblockSettings(_ handler: iTermBrowserSettingsHandler) {
        // Update adblock rules when settings change
        updateAdblockSettings()
    }

    func settingsHandlerDidRequestAdblockUpdate(_ handler: iTermBrowserSettingsHandler) {
        // Force update of adblock rules
        forceAdblockUpdate()
    }

    // MARK: - Settings Integration

    @objc func setupSettingsDelegate() {
        settingsHandler.delegate = self
    }

    @objc func notifySettingsPageOfAdblockUpdate(success: Bool, error: String? = nil) {
        // Find the settings page webview and update its status
        if webView.url == iTermBrowserSettingsHandler.settingsURL {
            if success {
                settingsHandler.showAdblockUpdateSuccess(in: webView)
            } else if let error = error {
                settingsHandler.showAdblockUpdateError(error, in: webView)
            }
        }
    }
}

@available(macOS 11.0, *)
extension iTermBrowserManager: iTermBrowserHistoryViewHandlerDelegate {
    func historyViewHandlerDidNavigateToURL(_ handler: iTermBrowserHistoryViewHandler, url: String) {
        // Navigate to the URL in the current browser
        loadURL(url)
    }
}

@available(macOS 11.0, *)
extension iTermBrowserManager {

    // MARK: - Adblock Integration

    @objc func setupAdblocking() {
        // Use shared adblock manager
        adblockManager = iTermAdblockManager.shared
        
        // Listen for adblock notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(adblockRulesDidUpdate),
            name: iTermAdblockManager.didUpdateRulesNotification,
            object: iTermAdblockManager.shared
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(adblockDidFail(_:)),
            name: iTermAdblockManager.didFailWithErrorNotification,
            object: iTermAdblockManager.shared
        )
        
        // Start updates if needed
        adblockManager?.updateRulesIfNeeded()
    }

    @objc func updateAdblockSettings() {
        // Called when settings change
        adblockManager?.updateRulesIfNeeded()
    }

    @objc func forceAdblockUpdate() {
        // Force update of adblock rules
        adblockManager?.forceUpdate()
    }

    // MARK: - Adblock Notification Handlers
    
    @objc private func adblockRulesDidUpdate() {
        // Apply or remove rules based on settings
        updateWebViewContentRules()

        // Notify settings page if it's open
        notifySettingsPageOfAdblockUpdate(success: true)
    }
    
    @objc private func adblockDidFail(_ notification: Notification) {
        guard let error = notification.userInfo?[iTermAdblockManager.errorKey] as? Error else {
            return
        }
        
        // Forward to delegate for user notification
        // For now, just log the error
        print("Adblock error: \(error.localizedDescription)")

        // Notify settings page if it's open
        notifySettingsPageOfAdblockUpdate(success: false, error: error.localizedDescription)
    }

    // MARK: - Private Implementation

    private func updateWebViewContentRules() {
        let userContentController = webView.configuration.userContentController

        // Remove existing adblock rules
        userContentController.removeAllContentRuleLists()

        // Add new rules if adblock is enabled
        if iTermAdvancedSettingsModel.adblockEnabled(),
           let ruleList = adblockManager?.getRuleList() {
            userContentController.add(ruleList)
        }
    }
}
