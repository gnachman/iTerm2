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
class iTermBrowserManager: NSObject, WKURLSchemeHandler, WKScriptMessageHandler {
    weak var delegate: iTermBrowserManagerDelegate?
    private(set) var webView: WKWebView!
    private var lastRequestedURL: URL?
    private var lastFailedURL: URL?
    private var errorHandler = iTermBrowserErrorHandler()
    private var settingsHandler = iTermBrowserSettingsHandler()
    private var navigationToURL: [WKNavigation: URL] = [:]
    private var currentPageURL: URL?
    private var hasSettingsMessageHandler = false
    private static let settingsMessageHandlerName = "iterm2BrowserSettings"
    private(set) var favicon: NSImage?

    init(configuration: WKWebViewConfiguration?) {
        super.init()
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

            // Register custom URL scheme handler for iterm2-about: URLs
            configuration.setURLSchemeHandler(self, forURLScheme: "iterm2-about")
        }


        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        
        // Enable back/forward navigation
        webView.allowsBackForwardNavigationGestures = true
    }
    
    // MARK: - Public Interface
    
    func loadURL(_ urlString: String) {
        guard let url = normalizeURL(urlString) else {
            // TODO: Handle invalid URL
            return
        }
        
        lastRequestedURL = url
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
    
    private func showErrorPage(for error: Error, failedURL: URL?) {
        let errorHTML = errorHandler.generateErrorPageHTML(for: error, failedURL: failedURL)
        
        // Store the error HTML to serve when iterm2-about:error is requested
        errorHandler.setPendingErrorHTML(errorHTML)
        
        // Navigate to iterm2-about:error which our custom URL scheme handler will serve
        webView.load(URLRequest(url: iTermBrowserErrorHandler.errorURL))
    }
    
    // MARK: - Private Helpers
    
    private func normalizeURL(_ urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If it already has a scheme, use as-is
        if trimmed.hasPrefix("http://") ||
            trimmed.hasPrefix("https://") ||
            trimmed.hasPrefix("iterm2-about:") ||
            trimmed.hasPrefix("about:") ||
            trimmed.hasPrefix("file://") {
            return URL(string: trimmed)
        }
        
        // If it looks like a domain/IP, add https://
        if isValidDomainOrIP(trimmed) {
            return URL(string: "https://\(trimmed)")
        }
        
        // Otherwise, treat as search query and send to search.
        let searchQuery = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return URL(string: iTermAdvancedSettingsModel.searchCommand().replacingOccurrences(of: "%@", with: searchQuery))
    }
    
    private func isValidDomainOrIP(_ input: String) -> Bool {
        // Check if it contains spaces (definitely not a URL)
        if input.contains(" ") {
            return false
        }
        
        // Check for IPv4 address pattern
        let ipv4Pattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?$"#
        if input.range(of: ipv4Pattern, options: .regularExpression) != nil {
            return true
        }
        
        // Check for IPv6 address pattern (basic check)
        if input.hasPrefix("[") && input.hasSuffix("]") {
            return true
        }
        
        // Check for localhost or local addresses
        if input.hasPrefix("localhost") || input.hasPrefix("127.0.0.1") {
            return true
        }
        
        // Check if it looks like a domain (contains a dot and no spaces)
        if input.contains(".") && !input.contains(" ") {
            // Additional validation: must have at least one character before and after the dot
            let components = input.split(separator: ".")
            return components.count >= 2 && components.allSatisfy { !$0.isEmpty }
        }
        
        // Check for intranet-style hostnames (single word, possibly with port)
        let hostPattern = #"^[a-zA-Z0-9-]+(:\d+)?$"#
        if input.range(of: hostPattern, options: .regularExpression) != nil {
            return true
        }

        return false
    }
    
    private func notifyDelegateOfUpdates() {
        delegate?.browserManager(self, didUpdateURL: webView.url?.absoluteString)
        delegate?.browserManager(self, didUpdateTitle: webView.title)
        delegate?.browserManager(self, didUpdateCanGoBack: webView.canGoBack)
        delegate?.browserManager(self, didUpdateCanGoForward: webView.canGoForward)
    }
    
    private func notifyDelegateOfFaviconUpdate() {
        delegate?.browserManager(self, didUpdateFavicon: favicon)
    }
    
    private func detectFavicon() {
        guard let currentURL = webView.url else { return }
        
        // For internal pages, use the main app icon
        if currentURL.absoluteString.hasPrefix("iterm2-about:") {
            favicon = NSApp.applicationIconImage
            notifyDelegateOfFaviconUpdate()
            return
        }
        
        // JavaScript to find favicon links in the page
        let script = """
            (function() {
              function getFaviconUrl() {
                var links = document.querySelectorAll('link[rel]');
                var icons = [];
                
                Array.prototype.forEach.call(links, function(link) {
                  var rels = link.getAttribute('rel').toLowerCase().split(/\\s+/);
                  
                  if (rels.indexOf('icon') !== -1 || rels.indexOf('mask-icon') !== -1) {
                    icons.push(link);
                  }
                });
                
                if (icons.length) {
                  icons.sort(function(a, b) {
                    return sizeValue(b) - sizeValue(a);
                  });
                  
                  return new URL(icons[0].getAttribute('href'), document.baseURI).href;
                }
                
                return new URL('/favicon.ico', location.origin).href;
              }
              
              function sizeValue(link) {
                var sz = link.getAttribute('sizes');
                if (!sz) {
                  return 0;
                }
                
                var parts = sz.split('x').map(function(n) {
                  return parseInt(n, 10) || 0;
                });
                
                return (parts[0] * parts[1]) || 0;
              }
              
              return getFaviconUrl();
            })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self = self,
                  let faviconURLString = result as? String,
                  let faviconURL = URL(string: faviconURLString) else {
                return
            }
            
            self.loadFavicon(from: faviconURL)
        }
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
    }
    
}

// MARK: - WKScriptMessageHandler

@available(macOS 11.0, *)
extension iTermBrowserManager {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.settingsMessageHandlerName,
              let action = message.body as? String else {
            return
        }
        
        // Verify the message is coming from our settings page
        guard let currentURL = currentPageURL,
              currentURL.absoluteString == iTermBrowserSettingsHandler.settingsURL.absoluteString else {
            return
        }
        
        settingsHandler.handleSettingsAction(action, webView: webView)
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
        detectFavicon()
        
        delegate?.browserManager(self, didFinishNavigation: navigation)
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let failedURL = lastRequestedURL
        
        // Only show error page if this isn't the same URL that already failed
        if failedURL != lastFailedURL && failedURL != nil {
            showErrorPage(for: error, failedURL: failedURL)
            lastFailedURL = failedURL
        }
        
        delegate?.browserManager(self, didFailNavigation: navigation, withError: error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let failedURL = lastRequestedURL
        
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
            lastRequestedURL = targetURL
        }
        
        // Popup blocking logic
        guard let targetURL = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        
        // Always allow our internal pages
        if targetURL.absoluteString.hasPrefix("iterm2-about:") {
            decisionHandler(.allow)
            return
        }
        
        // Check for popup behavior
        if navigationAction.targetFrame == nil {
            // This is a popup (no target frame = new window/tab)
            switch navigationAction.navigationType {
            case .linkActivated:
                // User clicked a link - request new window from delegate
                delegate?.browserManager(self, requestNewWindowForURL: targetURL, configuration: webView.configuration.copy() as! WKWebViewConfiguration)
                decisionHandler(.cancel)
                return
            case .other:
                // Automatic popup (JavaScript without user interaction) - block it
                print("Blocked automatic popup to: \(targetURL)")
                decisionHandler(.cancel)
                return
            default:
                // Block other popup types for safety
                print("Blocked popup navigation type \(navigationAction.navigationType.rawValue) to: \(targetURL)")
                decisionHandler(.cancel)
                return
            }
        }
        
        // Regular navigation in same frame - allow
        decisionHandler(.allow)
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
}
