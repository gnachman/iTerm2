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
    private let webView: iTermBrowserWebView
    private weak var parentWindow: NSWindow?
    
    init(webView: iTermBrowserWebView, parentWindow: NSWindow?) {
        self.webView = webView
        self.parentWindow = parentWindow
    }

    func savePageAs() {
        if let parentWindow {
            Task {
                await iTermBrowserPageSaver.pickDestinationAndSave(webView: webView,
                                                                   parentWindow: parentWindow)
            }
        }
    }
}
