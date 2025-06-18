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
class iTermBrowserManager: NSObject, WKURLSchemeHandler {
    weak var delegate: iTermBrowserManagerDelegate?
    private(set) var webView: WKWebView!
    private var lastRequestedURL: URL?
    private var lastFailedURL: URL?
    private var pendingErrorHTML: String?
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
        pendingErrorHTML = nil
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
    
    // MARK: - Error Page Generation
    
    private func generateErrorHTML(title: String, message: String, originalURL: String?) -> String {
        let urlDisplay = originalURL ?? ""
        
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(title)</title>
            <style>
                :root {
                    --bg-color: #ffffff;
                    --text-color: #1d1d1f;
                    --secondary-text: #86868b;
                    --accent-color: #007aff;
                    --button-bg: #007aff;
                    --button-text: #ffffff;
                    --button-hover: #0056cc;
                    --border-color: #d2d2d7;
                    --shadow: rgba(0, 0, 0, 0.1);
                }
                
                @media (prefers-color-scheme: dark) {
                    :root {
                        --bg-color: #1c1c1e;
                        --text-color: #ffffff;
                        --secondary-text: #8e8e93;
                        --accent-color: #0a84ff;
                        --button-bg: #0a84ff;
                        --button-text: #ffffff;
                        --button-hover: #0066cc;
                        --border-color: #38383a;
                        --shadow: rgba(0, 0, 0, 0.3);
                    }
                }
                
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }
                
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
                    background-color: var(--bg-color);
                    color: var(--text-color);
                    line-height: 1.6;
                    height: 100vh;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    padding: 40px 20px;
                }
                
                .error-container {
                    text-align: center;
                    max-width: 500px;
                    width: 100%;
                }
                
                .error-icon {
                    width: 80px;
                    height: 80px;
                    margin: 0 auto 32px;
                    background: linear-gradient(135deg, #ff6b6b, #ffa500);
                    border-radius: 50%;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    box-shadow: 0 8px 25px var(--shadow);
                }
                
                .error-icon::before {
                    content: "⚠";
                    font-size: 36px;
                    color: white;
                    font-weight: bold;
                }
                
                .error-title {
                    font-size: 28px;
                    font-weight: 600;
                    margin-bottom: 16px;
                    color: var(--text-color);
                }
                
                .error-message {
                    font-size: 16px;
                    color: var(--secondary-text);
                    margin-bottom: 24px;
                    line-height: 1.5;
                }
                
                .error-url {
                    font-family: 'SF Mono', Monaco, 'Cascadia Code', monospace;
                    font-size: 14px;
                    color: var(--secondary-text);
                    background: var(--border-color);
                    padding: 12px 16px;
                    border-radius: 8px;
                    margin: 20px 0;
                    word-break: break-all;
                    border: 1px solid var(--border-color);
                }
                
                .retry-button {
                    background: var(--button-bg);
                    color: var(--button-text);
                    border: none;
                    padding: 12px 24px;
                    font-size: 16px;
                    font-weight: 500;
                    border-radius: 10px;
                    cursor: pointer;
                    transition: all 0.2s ease;
                    margin-top: 16px;
                    min-width: 120px;
                    box-shadow: 0 2px 8px var(--shadow);
                }
                
                .retry-button:hover {
                    background: var(--button-hover);
                    transform: translateY(-1px);
                    box-shadow: 0 4px 12px var(--shadow);
                }
                
                .retry-button:active {
                    transform: translateY(0);
                    box-shadow: 0 2px 4px var(--shadow);
                }
                
                .details {
                    margin-top: 32px;
                    font-size: 14px;
                    color: var(--secondary-text);
                }
                
                @media (max-width: 480px) {
                    .error-title {
                        font-size: 24px;
                    }
                    
                    .error-message {
                        font-size: 15px;
                    }
                    
                    .error-container {
                        padding: 20px;
                    }
                }
            </style>
        </head>
        <body>
            <div class="error-container">
                <div class="error-icon"></div>
                <h1 class="error-title">\(title)</h1>
                <p class="error-message">\(message)</p>
                \(urlDisplay.isEmpty ? "" : "<div class=\"error-url\">\(urlDisplay)</div>")
                <button class="retry-button" onclick="retryLoad()">Try Again</button>
                <div class="details">
                    Check your internet connection and try reloading the page.
                </div>
            </div>
            
            <script>
                function retryLoad() {
                    const originalURL = '\(originalURL ?? "")';
                    if (originalURL) {
                        window.location.href = originalURL;
                    } else {
                        window.location.reload();
                    }
                }
                
                // Add keyboard support
                document.addEventListener('keydown', function(event) {
                    if (event.key === 'Enter' || event.key === ' ') {
                        retryLoad();
                    }
                });
            </script>
        </body>
        </html>
        """
    }
    
    private func showErrorPage(for error: Error, failedURL: URL?) {
        let (title, message) = errorTitleAndMessage(for: error)
        let errorHTML = generateErrorHTML(title: title, message: message, originalURL: failedURL?.absoluteString)
        
        // Store the error HTML to serve when iterm2-about:error is requested
        pendingErrorHTML = errorHTML
        
        // Navigate to iterm2-about:error which our custom URL scheme handler will serve
        let errorURL = URL(string: "iterm2-about:error")!
        webView.load(URLRequest(url: errorURL))
    }
    
    private func errorTitleAndMessage(for error: Error) -> (title: String, message: String) {
        let nsError = error as NSError
        
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return ("No Internet Connection", "Your computer appears to be offline. Check your internet connection and try again.")
            
        case NSURLErrorCannotFindHost:
            return ("Server Not Found", "Safari can't find the server. Check that the web address is correct and try again.")
            
        case NSURLErrorTimedOut:
            return ("The Connection Timed Out", "The server didn't respond in time. The site may be temporarily unavailable or overloaded.")
            
        case NSURLErrorCannotConnectToHost:
            return ("Can't Connect to Server", "Safari can't establish a secure connection to the server. The server may be down or unreachable.")
            
        case NSURLErrorNetworkConnectionLost:
            return ("Network Connection Lost", "The network connection was lost. Check your internet connection and try again.")
            
        case NSURLErrorDNSLookupFailed:
            return ("Server Not Found", "The server's DNS address could not be found. Check that the web address is correct.")
            
        case NSURLErrorHTTPTooManyRedirects:
            return ("Too Many Redirects", "Safari can't open the page because the server redirected too many times.")
            
        case NSURLErrorResourceUnavailable:
            return ("Page Unavailable", "The requested page is currently unavailable. Try again later.")
            
        case NSURLErrorNotConnectedToInternet:
            return ("No Internet Connection", "Your computer is not connected to the internet. Check your connection and try again.")
            
        case NSURLErrorServerCertificateUntrusted, NSURLErrorSecureConnectionFailed:
            return ("Secure Connection Failed", "Safari can't verify the identity of the website. The connection may not be secure.")
            
        default:
            return ("Page Can't Be Loaded", "An error occurred while loading this page. \(error.localizedDescription)")
        }
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

// MARK: - WKURLSchemeHandler

@available(macOS 11.0, *)
extension iTermBrowserManager {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        
        if url.absoluteString == "iterm2-about:error" {
            // Serve our error page HTML
            let htmlToServe = pendingErrorHTML ?? generateErrorHTML(
                title: "Page Not Available",
                message: "The requested page is not available.",
                originalURL: nil
            )
            
            guard let data = htmlToServe.data(using: .utf8) else {
                urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode HTML"]))
                return
            }
            
            let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
            
            // Clear pending error HTML after serving it
            pendingErrorHTML = nil
        } else {
            // Handle other iterm2-about: URLs if needed
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
        if webView.url?.absoluteString != "iterm2-about:error" {
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
        if let targetURL = navigationAction.request.url, targetURL.absoluteString != "iterm2-about:error" {
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
