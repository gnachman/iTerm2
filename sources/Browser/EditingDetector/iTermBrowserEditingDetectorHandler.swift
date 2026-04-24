//
//  iTermBrowserEditingDetectorHandler.swift
//  iTerm2
//
//  Created by George Nachman on 8/11/25.
//

import WebKit

@MainActor
class iTermBrowserEditingDetectorHandler {
    static let messageHandlerName = "iTerm2EditingDetector"
    private let sessionSecret: String

    init?() {
        guard let secret = String.makeSecureHexString() else {
            return nil
        }
        sessionSecret = secret
    }

    var javascript: String {
        return iTermBrowserTemplateLoader.loadTemplate(named: "editing-detector",
                                                       type: "js",
                                                       substitutions: ["SECRET": sessionSecret])
    }

    func handleMessage(webView: iTermBrowserWebView, message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let secret = body["sessionSecret"] as? String,
              secret == self.sessionSecret,
              let editable = body["editable"] as? Bool else {
            return
        }
        webView.isEditingText = editable
    }
}
