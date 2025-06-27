//
//  iTermBrowserHoverLinkHandler.swift
//  iTerm2
//
//  Created by George Nachman on 6/27/25.
//

import Foundation
import WebKit

@available(macOS 11.0, *)
class iTermBrowserHoverLinkHandler {
    static let messageHandlerName = "iTermHoverLink"
    private let secret: String
    
    struct HoverInfo {
        let url: String?
        let frame: NSRect
    }
    
    init?() {
        guard let secret = String.makeSecureHexString() else {
            return nil
        }
        self.secret = secret
    }
    
    var javascript: String {
        return iTermBrowserTemplateLoader.loadTemplate(named: "hover-link-detector",
                                                       type: "js", 
                                                       substitutions: ["SECRET": secret])
    }
    
    func handleMessage(webView: WKWebView, message: WKScriptMessage) -> HoverInfo? {
        guard let messageDict = message.body as? [String: Any],
              let type = messageDict["type"] as? String,
              let sessionSecret = messageDict["sessionSecret"] as? String,
              sessionSecret == secret else {
            DLog("Invalid hover link message format")
            return nil
        }
        
        switch type {
        case "hover":
            guard let url = messageDict["url"] as? String,
                  let x = messageDict["x"] as? Double,
                  let y = messageDict["y"] as? Double,
                  let width = messageDict["width"] as? Double,
                  let height = messageDict["height"] as? Double else {
                DLog("Invalid hover message parameters")
                return nil
            }
            
            // Convert JavaScript coordinates to view coordinates
            let pageZoom = webView.pageZoom
            let magnification = webView.magnification
            let jsRect = NSRect(x: x * pageZoom * magnification,
                               y: y * pageZoom * magnification,
                               width: width * pageZoom * magnification,
                               height: height * pageZoom * magnification)
            
            return HoverInfo(url: url, frame: jsRect)
            
        case "clear":
            return HoverInfo(url: nil, frame: NSZeroRect)
            
        default:
            DLog("Unknown hover link message type: \(type)")
            return nil
        }
    }
    
    func clearHover(in webView: WKWebView) {
        let script = "window.iTermHoverLinkHandler?.clearHover('\(secret)');"
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                DLog("Failed to clear hover: \(error)")
            }
        }
    }
}