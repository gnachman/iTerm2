//
//  iTermBrowserView.swift
//  iTerm2
//
//  Created by George Nachman on 6/18/25.
//

import WebKit

@available(macOS 11.0, *)
@objc(iTermBrowserViewController)
class iTermBrowserViewController: NSViewController, iTermBrowserToolbarDelegate, iTermBrowserManagerDelegate {
    private var browserManager: iTermBrowserManager!
    private var toolbar: iTermBrowserToolbar!
    private var backgroundView: NSVisualEffectView!
    
    override func loadView() {
        view = iTermBrowserView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupBackgroundView()
        setupBrowserManager()
        setupToolbar()
        setupWebView()
        setupConstraints()
    }
    
    private func setupBackgroundView() {
        backgroundView = NSVisualEffectView()
        backgroundView.material = .contentBackground
        backgroundView.blendingMode = .behindWindow
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)
    }
    
    private func setupBrowserManager() {
        browserManager = iTermBrowserManager()
        browserManager.delegate = self
    }
    
    private func setupToolbar() {
        toolbar = iTermBrowserToolbar()
        toolbar.delegate = self
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)
    }
    
    private func setupWebView() {
        browserManager.webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(browserManager.webView)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Background view constraints (full view coverage)
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Toolbar constraints
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44),
            
            // WebView constraints
            browserManager.webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            browserManager.webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            browserManager.webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            browserManager.webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - iTermBrowserToolbarDelegate
    
    func browserToolbarDidTapBack() {
        browserManager.goBack()
    }
    
    func browserToolbarDidTapForward() {
        browserManager.goForward()
    }
    
    func browserToolbarDidTapReload() {
        browserManager.reload()
    }
    
    func browserToolbarDidSubmitURL(_ url: String) {
        browserManager.loadURL(url)
    }
    
    // MARK: - iTermBrowserManagerDelegate
    
    func browserManager(_ manager: iTermBrowserManager, didUpdateURL url: String?) {
        toolbar.updateURL(url)
    }
    
    func browserManager(_ manager: iTermBrowserManager, didUpdateTitle title: String?) {
        // Could update window title or other UI
    }
    
    func browserManager(_ manager: iTermBrowserManager, didUpdateCanGoBack canGoBack: Bool) {
        // Could enable/disable back button
    }
    
    func browserManager(_ manager: iTermBrowserManager, didUpdateCanGoForward canGoForward: Bool) {
        // Could enable/disable forward button
    }
    
    func browserManager(_ manager: iTermBrowserManager, didStartNavigation navigation: WKNavigation?) {
        // Could show loading indicator
    }
    
    func browserManager(_ manager: iTermBrowserManager, didFinishNavigation navigation: WKNavigation?) {
        // Could hide loading indicator
    }
    
    func browserManager(_ manager: iTermBrowserManager, didFailNavigation navigation: WKNavigation?, withError error: Error) {
        // Could show error message
    }
}

@available(macOS 11.0, *)
@objc(iTermBrowserView)
class iTermBrowserView: NSView {
}
