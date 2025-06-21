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
    func browserViewControllerShowFindPanel(_ controller: iTermBrowserViewController)
    func browserViewController(_ controller: iTermBrowserViewController,
                               openNewTabForURL url: URL)
    func browserViewController(_ controller: iTermBrowserViewController,
                               openNewSplitPaneForURL url: URL,
                               vertical: Bool)
}

@available(macOS 11.0, *)
@objc(iTermBrowserViewController)
class iTermBrowserViewController: NSViewController {
    @objc weak var delegate: iTermBrowserViewControllerDelegate?
    private let browserManager: iTermBrowserManager
    private var toolbar: iTermBrowserToolbar!
    private var backgroundView: NSVisualEffectView!
    private let historyController: iTermBrowserHistoryController
    private let suggestionsController: iTermBrowserSuggestionsController
    private let navigationState = iTermBrowserNavigationState()
    @objc let sessionGuid: String

    @objc(initWithConfiguration:sessionGuid:)
    init(configuration: WKWebViewConfiguration?, sessionGuid: String)  {
        self.sessionGuid = sessionGuid
        historyController = iTermBrowserHistoryController(sessionGuid: sessionGuid,
                                                          navigationState: navigationState)
        browserManager = iTermBrowserManager(configuration: configuration,
                                             sessionGuid: sessionGuid,
                                             historyController: historyController,
                                             navigationState: navigationState)
        suggestionsController = iTermBrowserSuggestionsController(historyController: historyController,
                                                                  attributes: CompletionsWindow.regularAttributes(font: nil))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
}

// MARK: -  Public API

@available(macOS 11.0, *)
extension iTermBrowserViewController {
    @objc var interactionState: NSObject? {
        get {
            if #available(macOS 12, *) {
                return browserManager.webView.interactionState as? NSData
            } else {
                return nil
            }
        }
        set {
            if #available(macOS 12, *) {
                browserManager.webView.interactionState = newValue
            }
        }
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

    var activeSearchTerm: String? {
        if #available (macOS 13.0, *) {
            browserManager.browserFindManager?.activeSearchTerm
        } else {
            nil
        }
    }

    // MARK: - Search

    func startFind(_ string: String, caseSensitive: Bool) {
        if #available (macOS 13.0, *) {
            browserManager.browserFindManager?.startFind(string, caseSensitive: caseSensitive)
        }
    }

    @objc func findNext(_ sender: Any?) {
        if #available(macOS 13.0, *) {
            browserManager.browserFindManager?.findNext()
        }
    }

    @objc func findPrevious(_ sender: Any?) {
        if #available(macOS 13.0, *) {
            browserManager.browserFindManager?.findPrevious()
        }
    }

    @objc func clearFindString(_ sender: Any?) {
        if #available(macOS 13.0, *) {
            browserManager.browserFindManager?.clearFind()
        }
    }

    @objc func loadURL(_ urlString: String) {
        browserManager.loadURL(urlString)
    }

    // MARK: - Password

    @available(macOS 12, *)
    @objc(enterPassword:)
    func enter(password: String) {
        let writer = iTermBrowserPasswordWriter(webView: browserManager.webView,
                                                password: password)
        Task {
            try? await writer.fillPassword()
        }
    }
}

// MARK: -  Overrides

@available(macOS 11.0, *)
extension iTermBrowserViewController {
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

    @objc
    func performFindPanelAction(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else { return }

        switch NSFindPanelAction(rawValue: UInt(menuItem.tag)) {
        case .showFindPanel:
            delegate?.browserViewControllerShowFindPanel(self)
        case .setFindString:
            // TODO: Implement setting find string from selection if needed
            break
        default:
            // Other actions are handled by the dedicated methods below
            break
        }
    }
}

// MARK: -  Setup

@available(macOS 11.0, *)
extension iTermBrowserViewController {
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
}

// MARK: - iTermBrowserToolbarDelegate

@available(macOS 11.0, *)
extension iTermBrowserViewController: iTermBrowserToolbarDelegate {
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

    func browserToolbarDidTapHistory() {
        browserManager.loadURL(iTermBrowserHistoryViewHandler.historyURL.absoluteString)
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

    func browserToolbarDidRequestSuggestions(_ query: String) async -> [URLSuggestion] {
        return await suggestionsController.suggestions(forQuery: query)
    }

    func browserToolbarDidBeginEditingURL(string: String) -> String? {
        return suggestionsController.searchQueryFromURL(string)
    }

    func browserToolbarUserDidSubmitNavigationRequest() {
        // When the user presses enter in the URL bar, the URL bar must lose first responder.
        browserManager.webView.window?.makeFirstResponder(browserManager.webView)
    }
    
    func browserToolbarDidTapAddBookmark() async {
        guard let currentURL = browserManager.webView.url?.absoluteString else {
            return
        }
        
        guard let database = await BrowserDatabase.instance else {
            return
        }
        
        let isBookmarked = await database.isBookmarked(url: currentURL)
        
        if isBookmarked {
            // Remove bookmark
            let success = await database.removeBookmark(url: currentURL)
            if success {
                ToastWindowController.showToast(withMessage: "Bookmark Removed")
            }
        } else {
            // Add bookmark
            let title = browserManager.webView.title
            let success = await database.addBookmark(url: currentURL, title: title)
            if success {
                ToastWindowController.showToast(withMessage: "Bookmark Added")
            }
        }
    }
    
    func browserToolbarDidTapManageBookmarks() {
        browserManager.loadURL(iTermBrowserBookmarkViewHandler.bookmarksURL.absoluteString)
    }
    
    func browserToolbarCurrentURL() -> String? {
        return browserManager.webView.url?.absoluteString
    }
    
    func browserToolbarIsCurrentURLBookmarked() async -> Bool {
        guard let currentURL = browserManager.webView.url?.absoluteString,
              let database = await BrowserDatabase.instance else {
            return false
        }
        
        return await database.isBookmarked(url: currentURL)
    }
}

// MARK: - iTermBrowserManagerDelegate

@available(macOS 11.0, *)
extension iTermBrowserViewController: iTermBrowserManagerDelegate {
    func browserManager(_ manager: iTermBrowserManager, didUpdateURL url: String?) {
        toolbar.updateURL(url)
    }

    func browserManager(_ manager: iTermBrowserManager, didUpdateTitle title: String?) {
        delegate?.browserViewController(self, didUpdateTitle: title)
    }

    func browserManager(_ manager: iTermBrowserManager, didUpdateFavicon favicon: NSImage?) {
        toolbar.updateFavicon(favicon)
        delegate?.browserViewController(self, didUpdateFavicon: favicon)
    }

    func browserManager(_ manager: iTermBrowserManager, didUpdateCanGoBack canGoBack: Bool) {
        toolbar.updateNavigationButtons(canGoBack: canGoBack, canGoForward: manager.webView.canGoForward)
    }

    func browserManager(_ manager: iTermBrowserManager, didUpdateCanGoForward canGoForward: Bool) {
        toolbar.updateNavigationButtons(canGoBack: manager.webView.canGoBack, canGoForward: canGoForward)
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

    func browserManager(_ manager: iTermBrowserManager, openNewTabForURL url: URL) {
        delegate?.browserViewController(self, openNewTabForURL: url)
    }

    func browserManager(_ manager: iTermBrowserManager, openNewSplitPaneForURL url: URL, vertical: Bool) {
        delegate?.browserViewController(self, openNewSplitPaneForURL: url, vertical: vertical)
    }

}

// MARK: - Actions
@available(macOS 11.0, *)
extension iTermBrowserViewController {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return true
    }

    @objc
    @IBAction
    func browserOpenLocation(_ sender: Any) {
        toolbar.focusURLBar()
    }

    @objc
    @IBAction
    func browserBack(_ sender: Any) {
        toolbar.backTapped()
    }

    @objc
    @IBAction
    func browserForward(_ sender: Any) {
        toolbar.forwardTapped()
    }

    @objc
    @IBAction
    func browserReload(_ sender: Any) {
        toolbar.reloadTapped()
    }

    @objc
    @IBAction
    func browserHistory(_ sender: Any) {
        browserManager.loadURL(iTermBrowserHistoryViewHandler.historyURL.absoluteString)
    }
}

@available(macOS 11.0, *)
@objc(iTermBrowserView)
class iTermBrowserView: NSView {
}
