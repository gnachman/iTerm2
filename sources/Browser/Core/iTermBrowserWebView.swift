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
    var deferrableInteractionState: Any?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        allowsMagnification = true
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Deferred Interaction State
    
    @available(macOS 12.0, *)
    @discardableResult
    func applyDeferredInteractionStateIfNeeded() -> Bool {
        guard let deferred = deferrableInteractionState else { return false }

        DLog("Applying deferred interaction state")
        deferrableInteractionState = nil
        interactionState = deferred
        return true
    }
    
    // MARK: - Override navigation methods to apply deferred state
    
    @discardableResult
    override func load(_ request: URLRequest) -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.load(request)
    }
    
    @discardableResult
    override func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.loadHTMLString(string, baseURL: baseURL)
    }
    
    @discardableResult
    override func load(_ data: Data, mimeType MIMEType: String, characterEncodingName: String, baseURL: URL) -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.load(data, mimeType: MIMEType, characterEncodingName: characterEncodingName, baseURL: baseURL)
    }
    
    @discardableResult
    override func loadFileURL(_ URL: URL, allowingReadAccessTo readAccessURL: URL) -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.loadFileURL(URL, allowingReadAccessTo: readAccessURL)
    }
    
    @discardableResult
    override func reload() -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.reload()
    }
    
    @discardableResult
    override func reloadFromOrigin() -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.reloadFromOrigin()
    }
    
    @discardableResult
    override func goBack() -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.goBack()
    }
    
    @discardableResult
    override func goForward() -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.goForward()
    }
    
    @discardableResult
    override func go(to item: WKBackForwardListItem) -> WKNavigation? {
        if #available(macOS 12.0, *) {
            applyDeferredInteractionStateIfNeeded()
        }
        return super.go(to: item)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        // Add separator before our custom items
        menu.addItem(NSMenuItem.separator())
        
        // Add Save Page As menu item
        let savePageItem = NSMenuItem(title: "Save Page As…", action: #selector(savePageAsMenuClicked), keyEquivalent: "")
        savePageItem.target = self
        menu.addItem(savePageItem)
        
        // Add Print Page menu item
        let printPageItem = NSMenuItem(title: "Print…", action: #selector(printView(_:)), keyEquivalent: "")
        printPageItem.target = self
        menu.addItem(printPageItem)
        
        // Add Copy Page Title menu item
        let copyTitleItem = NSMenuItem(title: "Copy Page Title", action: #selector(copyPageTitleMenuClicked), keyEquivalent: "")
        copyTitleItem.target = self
        menu.addItem(copyTitleItem)

        menu.addItem(NSMenuItem.separator())

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
