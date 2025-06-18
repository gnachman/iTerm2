//
//  iTermBrowserManager.swift
//  iTerm2
//
//  Created by George Nachman on 6/18/25.
//

import WebKit

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
class iTermBrowserManager: NSObject {
    weak var delegate: iTermBrowserManagerDelegate?
    private(set) var webView: WKWebView!
    
    override init() {
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
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
        webView.reload()
    }
    
    func stop() {
        webView.stopLoading()
    }
    
    // MARK: - Private Helpers
    
    private func normalizeURL(_ urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If it already has a scheme, use as-is
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        
        // If it looks like a domain, add https://
        if trimmed.contains(".") && !trimmed.contains(" ") {
            return URL(string: "https://\(trimmed)")
        }
        
        // Otherwise, treat as search query (could add search engine later)
        // For now, just try to make it a valid URL
        return URL(string: "https://\(trimmed)")
    }
    
    private func notifyDelegateOfUpdates() {
        delegate?.browserManager(self, didUpdateURL: webView.url?.absoluteString)
        delegate?.browserManager(self, didUpdateTitle: webView.title)
        delegate?.browserManager(self, didUpdateCanGoBack: webView.canGoBack)
        delegate?.browserManager(self, didUpdateCanGoForward: webView.canGoForward)
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
        notifyDelegateOfUpdates()
        delegate?.browserManager(self, didFinishNavigation: navigation)
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        delegate?.browserManager(self, didFailNavigation: navigation, withError: error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        delegate?.browserManager(self, didFailNavigation: navigation, withError: error)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
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