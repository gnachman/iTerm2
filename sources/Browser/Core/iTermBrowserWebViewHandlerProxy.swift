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
        guard let handler = schemeHandler(for: webView) else {
            urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserWebViewHandlerProxy",
                                                   code: -1,
                                                   userInfo: [NSLocalizedDescriptionKey: "No handler for this web view"]))
            return
        }
        handler.webView(webView, start: urlSchemeTask)
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        schemeHandler(for: webView)?.webView(webView, stop: urlSchemeTask)
    }

    // A web view opened from another tab inherits its opener's URL scheme handlers, which can't
    // be replaced. Hand its tasks to its own manager, which serves its pages and outlives the
    // opener.
    // A browser web view with no manager (one being torn down) gets nothing rather than its
    // opener's manager, which would answer from its own pages.
    private func schemeHandler(for webView: WKWebView) -> WKURLSchemeHandler? {
        if let browserWebView = webView as? iTermBrowserWebView {
            return browserWebView.browserDelegate as? WKURLSchemeHandler        }
        return delegate
    }
}
