// BrowserExtensionProtocols.swift
// Protocol definitions for WebKit types to enable testing and decoupling

import Foundation
import WebKit

// MARK: - WebView Protocol

public protocol BrowserExtensionWKWebView: AnyObject {
    var be_url: URL? { get }
    var be_configuration: BrowserExtensionWKWebViewConfiguration { get }
    func be_evaluateJavaScript(_ javaScriptString: String, in frame: WKFrameInfo?, in contentWorld: WKContentWorld) async throws -> Any?
}

// MARK: - Configuration Protocol

public protocol BrowserExtensionWKWebViewConfiguration: AnyObject {
    var be_userContentController: BrowserExtensionWKUserContentController { get }
}

public protocol BrowserExtensionWKUserContentController: AnyObject {
    func be_addUserScript(_ userScript: WKUserScript)
    func be_removeAllUserScripts()
    func be_add(_ scriptMessageHandler: WKScriptMessageHandler, name: String, contentWorld: WKContentWorld)
}

// MARK: - Navigation Protocols

public protocol BrowserExtensionWKNavigation: AnyObject {
}

public protocol BrowserExtensionWKNavigationAction: AnyObject {
    var be_request: URLRequest { get }
    var be_targetFrame: BrowserExtensionWKFrameInfo? { get }
    var be_sourceFrame: BrowserExtensionWKFrameInfo? { get }
    var be_navigationType: WKNavigationType { get }
}

public protocol BrowserExtensionWKNavigationResponse: AnyObject {
    var be_response: URLResponse { get }
    var be_isForMainFrame: Bool { get }
    var be_canShowMIMEType: Bool { get }
}

public protocol BrowserExtensionWKFrameInfo: AnyObject {
    var be_isMainFrame: Bool { get }
    var be_request: URLRequest { get }
}

// MARK: - Navigation Delegate Protocol

@MainActor
public protocol BrowserExtensionWKNavigationDelegate: AnyObject {
    func webView(_ webView: BrowserExtensionWKWebView, decidePolicyFor navigationAction: BrowserExtensionWKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void)
    func webView(_ webView: BrowserExtensionWKWebView, decidePolicyFor navigationResponse: BrowserExtensionWKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void)
    func webView(_ webView: BrowserExtensionWKWebView, didStartProvisionalNavigation navigation: BrowserExtensionWKNavigation?)
    func webView(_ webView: BrowserExtensionWKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: BrowserExtensionWKNavigation?)
    func webView(_ webView: BrowserExtensionWKWebView, didFailProvisionalNavigation navigation: BrowserExtensionWKNavigation?, withError error: Error)
    func webView(_ webView: BrowserExtensionWKWebView, didCommit navigation: BrowserExtensionWKNavigation?)
    func webView(_ webView: BrowserExtensionWKWebView, didFinish navigation: BrowserExtensionWKNavigation?)
    func webView(_ webView: BrowserExtensionWKWebView, didFail navigation: BrowserExtensionWKNavigation?, withError error: Error)
    func webView(_ webView: BrowserExtensionWKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)
    func webView(_ webView: BrowserExtensionWKWebView, webContentProcessDidTerminate navigation: BrowserExtensionWKNavigation?)
}

// MARK: - Extensions to make WebKit types conform

extension WKWebView: BrowserExtensionWKWebView {
    public var be_url: URL? { url }
    public var be_configuration: BrowserExtensionWKWebViewConfiguration { configuration }
    
    public func be_evaluateJavaScript(_ javaScriptString: String, in frame: WKFrameInfo?, in contentWorld: WKContentWorld) async throws -> Any? {
        return try await evaluateJavaScript(javaScriptString, in: frame, contentWorld: contentWorld)
    }
    }

extension WKWebViewConfiguration: BrowserExtensionWKWebViewConfiguration {
    public var be_userContentController: BrowserExtensionWKUserContentController { userContentController }
}

extension WKUserContentController: BrowserExtensionWKUserContentController {
    public func be_addUserScript(_ userScript: WKUserScript) {
        addUserScript(userScript)
    }
    
    public func be_removeAllUserScripts() {
        removeAllUserScripts()
    }
    
    public func be_add(_ scriptMessageHandler: WKScriptMessageHandler, name: String, contentWorld: WKContentWorld) {
        add(scriptMessageHandler, contentWorld: contentWorld, name: name)
    }
}

extension WKNavigation: BrowserExtensionWKNavigation {
}

extension WKFrameInfo: BrowserExtensionWKFrameInfo {
    public var be_isMainFrame: Bool { isMainFrame }
    public var be_request: URLRequest { request }
}

extension WKNavigationAction: BrowserExtensionWKNavigationAction {
    public var be_request: URLRequest { request }
    public var be_targetFrame: BrowserExtensionWKFrameInfo? { targetFrame }
    public var be_sourceFrame: BrowserExtensionWKFrameInfo? { sourceFrame }
    public var be_navigationType: WKNavigationType { navigationType }
}

extension WKNavigationResponse: BrowserExtensionWKNavigationResponse {
    public var be_response: URLResponse { response }
    public var be_isForMainFrame: Bool { isForMainFrame }
    public var be_canShowMIMEType: Bool { canShowMIMEType }
}
