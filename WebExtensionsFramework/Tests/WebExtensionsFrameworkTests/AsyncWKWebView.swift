@testable import WebExtensionsFramework
import WebKit
import XCTest

enum NavigationError: Error {
    case loadFailed
}

/// Custom URL scheme handler for test iframe contexts
class TestIframeSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        // Serve a simple HTML page for test iframes
        let html = """
            <html>
            <head><title>Test Iframe</title></head>
            <body>
                <h1>Test Iframe Context</h1>
                <p>Origin: \(urlSchemeTask.request.url?.absoluteString ?? "unknown")</p>
                <script>
                    // Signal that iframe has loaded
                    window.iframeLoaded = true;
                </script>
            </body>
            </html>
        """
        
        let data = html.data(using: .utf8)!
        let response = URLResponse(url: urlSchemeTask.request.url!, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Nothing to do for stop
    }
}

class AsyncWKWebView: WKWebView, WKNavigationDelegate {
    private var continuations = [ObjectIdentifier: CheckedContinuation<Void, Error>]()
    private var frameInfoMap = [URL: WKFrameInfo]()

    override init(frame: CGRect = .zero, configuration: WKWebViewConfiguration = WKWebViewConfiguration()) {
        // Register custom scheme handler for test iframes
        configuration.setURLSchemeHandler(TestIframeSchemeHandler(), forURLScheme: "test-iframe")
        
        super.init(frame: frame, configuration: configuration)
        navigationDelegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        navigationDelegate = self
        // Note: Custom scheme handler not set up in this init path since we can't modify the configuration
    }

    override func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
        return super.loadHTMLString(string, baseURL: baseURL)
    }

    func loadHTMLStringAsync(_ string: String, baseURL: URL?) async throws {
        guard let nav = loadHTMLString(string, baseURL: baseURL) else {
            throw NavigationError.loadFailed
        }
        try await waitFor(nav)
    }

    private func waitFor(_ navigation: WKNavigation) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let key = ObjectIdentifier(navigation)
            continuations[key] = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let navigation = navigation else { return }
        let key = ObjectIdentifier(navigation)
        guard let cont = continuations[key] else { return }
        cont.resume()
        continuations.removeValue(forKey: key)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard let navigation = navigation else { return }
        let key = ObjectIdentifier(navigation)
        guard let cont = continuations[key] else { return }
        cont.resume(throwing: error)
        continuations.removeValue(forKey: key)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard let navigation = navigation else { return }
        let key = ObjectIdentifier(navigation)
        guard let cont = continuations[key] else { return }
        cont.resume(throwing: error)
        continuations.removeValue(forKey: key)
    }

    override func evaluateJavaScript(_ javaScriptString: String) async throws -> Any? {
        return try await super.evaluateJavaScript(javaScriptString)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Capture frame info from navigation action
        if let request = navigationAction.request.url,
            let frame = navigationAction.targetFrame {
            frameInfoMap[request] = frame
        }
        decisionHandler(.allow)
    }
    
    /// Get frame info for a specific URL
    func frameInfo(for url: URL) -> WKFrameInfo? {
        return frameInfoMap[url]
    }
    
    /// Create a real iframe and wait for it to load, returning its frame info
    func createIframeAsync(origin: String) async throws -> WKFrameInfo? {
        // Create iframe and wait for it to load
        let iframeScript = """
            const iframe = document.createElement('iframe');
            iframe.src = '\(origin)';
            iframe.id = 'test-iframe';
            iframe.style.width = '100%';
            iframe.style.height = '400px';
            document.body.appendChild(iframe);
            
            // Wait for iframe to load
            await new Promise((resolve) => {
                iframe.onload = resolve;
                // Fallback timeout
                setTimeout(resolve, 1000);
            });
            
            return iframe.src;
        """

        guard let iframeSrc = try await callAsyncJavaScript(iframeScript, contentWorld: .page) as? String,
              let iframeURL = URL(string: iframeSrc) else {
            throw NavigationError.loadFailed
        }
        
        return frameInfo(for: iframeURL)
    }
}
