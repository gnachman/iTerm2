//
//  iTermBrowserWebViewHandlerProxy.swift
//  iTerm2
//
//  Created by George Nachman on 7/4/25.
//

import WebKit

// A proxy for various handlers that strongly retain their delegate-like object.
class iTermBrowserWebViewHandlerProxy: NSObject, WKScriptMessageHandler, WKURLSchemeHandler {
    weak var delegate: (WKScriptMessageHandler & WKURLSchemeHandler)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        delegate?.webView(webView, start: urlSchemeTask)
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        delegate?.webView(webView, stop: urlSchemeTask)
    }
}
