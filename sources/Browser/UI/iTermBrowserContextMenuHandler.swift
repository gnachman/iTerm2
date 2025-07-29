//
//  iTermBrowserContextMenuHandler.swift
//  iTerm2
//
//  Created by Claude on 6/23/25.
//

import Foundation
import WebKit

@available(macOS 11.0, *)
class iTermBrowserContextMenuHandler {
    private let webView: WKWebView
    private weak var parentWindow: NSWindow?
    
    init(webView: WKWebView, parentWindow: NSWindow?) {
        self.webView = webView
        self.parentWindow = parentWindow
    }

    func savePageAs() {
        if let parentWindow {
            iTermBrowserPageSaver.pickDestinationAndSave(webView: webView,
                                                         parentWindow: parentWindow)
        }
    }
}
