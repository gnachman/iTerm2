//
//  iTermBrowserView.swift
//  iTerm2
//
//  Created by George Nachman on 6/18/25.
//

import WebKit

@available(macOS 11.0, *)
@objc protocol iTermBrowserViewControllerDelegate: AnyObject {
    func browserViewController(_ controller: iTermBrowserViewController,
                               didUpdateTitle title: String?)
    func browserViewController(_ controller: iTermBrowserViewController,
                               didUpdateFavicon favicon: NSImage?)
    func browserViewController(_ controller: iTermBrowserViewController,
                               requestNewWindowForURL url: URL,
                               configuration: WKWebViewConfiguration) -> WKWebView?
}

@available(macOS 11.0, *)
@objc(iTermBrowserViewController)
class iTermBrowserViewController: NSViewController, iTermBrowserToolbarDelegate, iTermBrowserManagerDelegate {
    @objc weak var delegate: iTermBrowserViewControllerDelegate?
    private let browserManager: iTermBrowserManager
    private var toolbar: iTermBrowserToolbar!
    private var backgroundView: NSVisualEffectView!

    @objc(initWithConfiguration:)
    init(configuration: WKWebViewConfiguration?)  {
        browserManager = iTermBrowserManager(configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
    
    @objc override var title: String? {
        get {
            return browserManager.webView.title
        }
        set {
            super.title = newValue
        }
    }
    
    @objc var favicon: NSImage? {
        return browserManager.favicon
    }

    @objc var webView: WKWebView {
        return browserManager.webView
    }

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
    
    func browserToolbarDidTapReload() {
        browserManager.reload()
    }
    
    func browserToolbarDidTapStop() {
        browserManager.stop()
    }
    
    func browserToolbarDidSubmitURL(_ url: String) {
        browserManager.loadURL(url)
    }
    
    func browserToolbarDidTapSettings() {
        browserManager.loadURL(iTermBrowserSettingsHandler.settingsURL.absoluteString)
    }
    
    func browserToolbarBackHistoryItems() -> [iTermBrowserHistoryItem] {
        return browserManager.getBackHistoryItems()
    }
    
    func browserToolbarForwardHistoryItems() -> [iTermBrowserHistoryItem] {
        return browserManager.getForwardHistoryItems()
    }
    
    func browserToolbarDidSelectHistoryItem(steps: Int) {
        browserManager.navigateHistory(steps: steps)
    }
    
    // MARK: - iTermBrowserManagerDelegate
    
    func browserManager(_ manager: iTermBrowserManager, didUpdateURL url: String?) {
        toolbar.updateURL(url)
    }
    
    func browserManager(_ manager: iTermBrowserManager, didUpdateTitle title: String?) {
        delegate?.browserViewController(self, didUpdateTitle: title)
    }
    
    func browserManager(_ manager: iTermBrowserManager, didUpdateFavicon favicon: NSImage?) {
        delegate?.browserViewController(self, didUpdateFavicon: favicon)
    }
    
    func browserManager(_ manager: iTermBrowserManager, didUpdateCanGoBack canGoBack: Bool) {
        // Could enable/disable back button
    }
    
    func browserManager(_ manager: iTermBrowserManager, didUpdateCanGoForward canGoForward: Bool) {
        // Could enable/disable forward button
    }
    
    func browserManager(_ manager: iTermBrowserManager, didStartNavigation navigation: WKNavigation?) {
        toolbar.setLoading(true)
    }
    
    func browserManager(_ manager: iTermBrowserManager, didFinishNavigation navigation: WKNavigation?) {
        toolbar.setLoading(false)
    }
    
    func browserManager(_ manager: iTermBrowserManager, didFailNavigation navigation: WKNavigation?, withError error: Error) {
        toolbar.setLoading(false)
    }
    
    func browserManager(_ manager: iTermBrowserManager, requestNewWindowForURL url: URL, configuration: WKWebViewConfiguration) -> WKWebView? {
        return delegate?.browserViewController(self,
                                               requestNewWindowForURL: url,
                                               configuration: configuration)
    }
    
    // MARK: - Public Interface
    
    @objc func loadURL(_ urlString: String) {
        browserManager.loadURL(urlString)
    }
}

@available(macOS 11.0, *)
@objc(iTermBrowserView)
class iTermBrowserView: NSView {
}
