//
//  iTermBrowserSelectionMonitor.swift
//  iTerm2
//
//  Created by George Nachman on 6/30/25.
//

import WebKit

@available(macOS 11, *)
class iTermBrowserSelectionMonitor {
    static let messageHandlerName = "iTermSelectionMonitor"
    private let secret: String

    init?() {
        guard let secret = String.makeSecureHexString() else {
            return nil
        }
        self.secret = secret
    }

    var javascript: String {
        return iTermBrowserTemplateLoader.loadTemplate(named: "monitor-selection",
                                                       type: "js",
                                                       substitutions: [ "SECRET": secret ])

    }

    func handleMessage(_ message: WKScriptMessage, webView: iTermBrowserWebView) {
        guard let messageDict = message.body as? [String: Any],
              let selection = messageDict["selection"] as? String,
              let sessionSecret = messageDict["sessionSecret"] as? String,
              sessionSecret == secret else {
            return
        }
        webView.currentSelection = selection
    }
}
