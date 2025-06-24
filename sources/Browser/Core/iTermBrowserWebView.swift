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
    func webViewDidRequestSavePageAs(_ webView: iTermBrowserWebView)
    func webViewDidRequestCopyPageTitle(_ webView: iTermBrowserWebView)
}

@available(macOS 11.0, *)
class iTermBrowserWebView: WKWebView {
    weak var browserDelegate: iTermBrowserWebViewDelegate?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        allowsMagnification = true
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        // Add separator before our custom items
        menu.addItem(NSMenuItem.separator())
        
        // Add Save Page As menu item
        let savePageItem = NSMenuItem(title: "Save Page As...", action: #selector(savePageAsMenuClicked), keyEquivalent: "")
        savePageItem.target = self
        menu.addItem(savePageItem)
        
        // Add Print Page menu item
        let printPageItem = NSMenuItem(title: "Print Page", action: #selector(printView(_:)), keyEquivalent: "")
        printPageItem.target = self
        menu.addItem(printPageItem)
        
        // Add Copy Page Title menu item
        let copyTitleItem = NSMenuItem(title: "Copy Page Title", action: #selector(copyPageTitleMenuClicked), keyEquivalent: "")
        copyTitleItem.target = self
        menu.addItem(copyTitleItem)
        
        // Add Reload Page menu item
        let reloadPageItem = NSMenuItem(title: "Reload Page", action: #selector(reload(_:)), keyEquivalent: "")
        reloadPageItem.target = self
        menu.addItem(reloadPageItem)

        // Add View Source menu item
        let viewSourceItem = NSMenuItem(title: "View Source", action: #selector(viewSourceMenuClicked), keyEquivalent: "")
        viewSourceItem.target = self
        menu.addItem(viewSourceItem)
    }

    @objc private func viewSourceMenuClicked() {
        browserDelegate?.webViewDidRequestViewSource(self)
    }
    
    @objc private func savePageAsMenuClicked() {
        browserDelegate?.webViewDidRequestSavePageAs(self)
    }
    
    @objc private func copyPageTitleMenuClicked() {
        browserDelegate?.webViewDidRequestCopyPageTitle(self)
    }

    // https://stackoverflow.com/questions/46777468/swift-mac-os-blank-page-printed-when-i-try-to-print-webview-wkwebview
    @objc(print:)
    override func printView(_ sender: Any?) {
        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true

        let op = printOperation(with: printInfo)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.view?.frame = bounds
        op.runModal(
          for: window!,
          delegate: self,
          didRun: nil,
          contextInfo: nil
        )
    }
}
