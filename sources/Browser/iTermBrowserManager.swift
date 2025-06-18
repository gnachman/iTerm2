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
    func browserManager(_ manager: iTermBrowserManager, didUpdateCanGoBack canGoBack: Bool)
    func browserManager(_ manager: iTermBrowserManager, didUpdateCanGoForward canGoForward: Bool)
    func browserManager(_ manager: iTermBrowserManager, didStartNavigation navigation: WKNavigation?)
    func browserManager(_ manager: iTermBrowserManager, didFinishNavigation navigation: WKNavigation?)
    func browserManager(_ manager: iTermBrowserManager, didFailNavigation navigation: WKNavigation?, withError error: Error)
}

@available(macOS 11.0, *)
@objc(iTermBrowserManager)
class iTermBrowserManager: NSObject, WKURLSchemeHandler {
    weak var delegate: iTermBrowserManagerDelegate?
    private(set) var webView: WKWebView!
    private var lastRequestedURL: URL?
    private var lastFailedURL: URL?
    private var errorHandler = iTermBrowserErrorHandler()
    private var settingsHandler = iTermBrowserSettingsHandler()
    private var navigationToURL: [WKNavigation: URL] = [:]

    override init() {
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        
        // Register custom URL scheme handler for iterm2-about: URLs
        configuration.setURLSchemeHandler(self, forURLScheme: "iterm2-about")
        
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
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }
    
    func goForward() {
        if webView.canGoForward {
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
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("iterm2-about:") {
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
        
        notifyDelegateOfUpdates()
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
        
        // For now, allow all navigation
        // TODO: Add security policies, popup blocking, etc.
        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate

@available(macOS 11.0, *)
extension iTermBrowserManager: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Handle popup windows - for now, just load in current view
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
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
