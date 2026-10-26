//
//  iTermBrowserContextMenuMonitor.swift
//  iTerm2
//
//  Created by George Nachman on 6/30/25.
//

import WebKit

@MainActor
class iTermBrowserContextMenuMonitor {
    static let messageHandlerName = "iTermContextMenuMonitor"
    private let secret: String

    init?() {
        guard let secret = String.makeSecureHexString() else {
            return nil
        }
        self.secret = secret
    }

    var javascript: String {
        return iTermBrowserTemplateLoader.loadTemplate(named: "monitor-context-menu",
                                                       type: "js",
                                                       substitutions: [ "SECRET": secret ])
    }

    // Opens the menu in the web view that sent the message. A web view opened by a target=_blank
    // link shares its opener's configuration, so its messages arrive at the opener's handler,
    // whose own web view is the wrong one.
    func handleMessage(_ message: WKScriptMessage) {
        guard let webView = message.webView as? iTermBrowserWebView,
              let messageDict = message.body as? [String: Any],
              let xStr = messageDict["x"] as? NSNumber,
              let yStr = messageDict["y"] as? NSNumber,
              let sessionSecret = messageDict["sessionSecret"] as? String,
              sessionSecret == secret else {
            return
        }
        if let selection = messageDict["selection"] as? String {
            webView.currentSelection = selection
        }
        let x = xStr.doubleValue
        let y = yStr.doubleValue
        webView.openContextMenu(atJavascriptLocation: NSPoint(x: x, y: y))
    }
}
