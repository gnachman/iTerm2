//
//  iTermBrowserWebView.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import WebKit

@available(macOS 11.0, *)
@objc protocol iTermBrowserWebViewDelegate: AnyObject {
    func webViewDidRequestViewSource(_ webView: iTermBrowserWebView)
}

@available(macOS 11.0, *)
class iTermBrowserWebView: WKWebView {
    weak var browserDelegate: iTermBrowserWebViewDelegate?
    
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        
        // Add View Source menu item
        let viewSourceItem = NSMenuItem(title: "View Source", action: #selector(viewSourceMenuClicked), keyEquivalent: "")
        viewSourceItem.target = self
        
        // Add separator and our menu item at the bottom
        menu.addItem(NSMenuItem.separator())
        menu.addItem(viewSourceItem)
    }
    
    @objc private func viewSourceMenuClicked() {
        browserDelegate?.webViewDidRequestViewSource(self)
    }
}
