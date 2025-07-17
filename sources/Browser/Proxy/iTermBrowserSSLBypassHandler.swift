//
//  iTermBrowserSSLBypassHandler.swift
//  iTerm2
//
//  Created by George Nachman on 7/17/25.
//

import WebKit

class iTermBrowserSSLBypassHandler: NSObject {
    static let messageHandlerName = "iTerm2SSLBypass"

    private struct Request {
        var hostname: String
        var secret: String

        init?(_ body: [String: String]) {
            guard let hostname = body["hostname"],
                  let secret = body["secret"] else {
                return nil
            }
            self.hostname = hostname
            self.secret = secret
        }
    }

    static func offerBypass(webView: WKWebView, message: WKScriptMessage) {
        guard let window = webView.window,
              let body = message.body as? [String: String],
              let request = Request(body) else {
            return
        }
        guard message.frameInfo.isMainFrame else {
            DLog("Request not from main frame")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Visit Insecure Site?"
        alert.informativeText = "This site does not have a proper TLS certificate. By adding the domain to the allowlist, certificate checks will not be performed for this domain until iTerm2 is restarted."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Allow (Unsafe)")
        alert.alertStyle = .warning

        alert.beginSheetModal(for: window) { response in
            if response == .alertSecondButtonReturn {
                allow(request, in: webView)
            }
        }
    }

    private static func allow(_ request: Request, in webView: WKWebView) {
        do {
            try HudsuckerProxy.standard?.addBypassedDomain(request.hostname, token: request.secret)
            webView.reload()
        } catch {
            DLog("\(error)")
        }
    }
}
