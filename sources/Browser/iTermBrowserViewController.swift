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
}

@available(macOS 11.0, *)
@objc(iTermBrowserViewController)
class iTermBrowserViewController: NSViewController, iTermBrowserToolbarDelegate, iTermBrowserManagerDelegate {
    @objc weak var delegate: iTermBrowserViewControllerDelegate?
    private let browserManager: iTermBrowserManager
    private var toolbar: iTermBrowserToolbar!
    private var backgroundView: NSVisualEffectView!

    @objc(initWithConfiguration:sessionGuid:)
    init(configuration: WKWebViewConfiguration?, sessionGuid: String)  {
        browserManager = iTermBrowserManager(configuration: configuration, sessionGuid: sessionGuid)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

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

    func startFind(_ string: String, caseSensitive: Bool) {
        if #available (macOS 13.0, *) {
            browserManager.browserFindManager?.startFind(string, caseSensitive: caseSensitive)
        }
    }

    func findNext() {
        if #available (macOS 13.0, *) {
            browserManager.browserFindManager?.findNext()
        }
    }

    func findPrevious() {
        if #available (macOS 13.0, *) {
            browserManager.browserFindManager?.findPrevious()
        }
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

    private func searchQueryFromURL(_ url: String) -> String? {
        guard let actualComponents = URLComponents(string: url),
              let searchEngineComponents = URLComponents(string: iTermAdvancedSettingsModel.searchCommand()) else {
            return nil
        }
        
        // Helper function to normalize host by removing common prefixes
        func normalizeHost(_ host: String?) -> String? {
            guard let host = host?.lowercased() else { return nil }
            let prefixesToRemove = ["www.", "m.", "mobile."]
            for prefix in prefixesToRemove {
                if host.hasPrefix(prefix) {
                    return String(host.dropFirst(prefix.count))
                }
            }
            return host
        }
        
        // Check if hosts match (ignoring common prefixes)
        let normalizedActualHost = normalizeHost(actualComponents.host)
        let normalizedSearchHost = normalizeHost(searchEngineComponents.host)
        guard normalizedActualHost == normalizedSearchHost else {
            return nil
        }
        
        // Check if paths match
        guard actualComponents.path == searchEngineComponents.path else {
            return nil
        }
        
        // Extract query parameters from both URLs
        guard let actualQueryItems = actualComponents.queryItems,
              let searchQueryItems = searchEngineComponents.queryItems else {
            return nil
        }
        
        // Find the query parameter that contains "%@" in the search template
        var targetQueryParam: String?
        for item in searchQueryItems {
            if let value = item.value, value.contains("%@") {
                targetQueryParam = item.name
                break
            }
        }
        
        guard let queryParamName = targetQueryParam else {
            return nil
        }
        
        // Find the corresponding parameter in the actual URL
        for item in actualQueryItems {
            if item.name == queryParamName, let value = item.value {
                // Return the decoded query value
                return value.removingPercentEncoding ?? value
            }
        }
        
        return nil
    }

    private struct ScoredSuggestion {
        let suggestion: URLSuggestion
        let score: Int
    }
    
    func browserToolbarDidRequestSuggestions(_ query: String) async -> [URLSuggestion] {
        var scoredResults = [ScoredSuggestion]()
        let attributes = CompletionsWindow.regularAttributes(font: nil)
        
        // Get history suggestions
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let historySuggestions = getHistorySuggestions(for: query)
            scoredResults.append(contentsOf: historySuggestions)
        }
        
        var searchScore = 0
        
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let actualQuery: String
            if let search = searchQueryFromURL(query) {
                searchScore = Int.max
                actualQuery = search
            } else {
                searchScore = 99999
                actualQuery = query
            }
            let trimmed = actualQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let queryParameterValue = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            let url = iTermAdvancedSettingsModel.searchCommand().replacingOccurrences(of: "%@", with: queryParameterValue)
            
            let searchSuggestion = URLSuggestion(
                text: actualQuery,
                url: url,
                displayText: NSAttributedString(string: "Search for \"\(actualQuery)\"", attributes: attributes),
                detail: "Web Search",
                type: .webSearch
            )
            
            scoredResults.append(ScoredSuggestion(suggestion: searchSuggestion, score: searchScore))
        }
        
        if let normal = browserManager.normalizeURL(query) {
            let suggestion = URLSuggestion(
                text: query,
                url: normal.absoluteString,
                displayText: NSAttributedString(string: "Navigate to \"\(normal.absoluteString)\"",
                                                attributes: attributes),
                detail: "URL",
                type: .navigation
            )
            let urlScore: Int
            if browserManager.stringIsStronglyURLLike(query) {
                urlScore = 100000
            } else {
                urlScore = 99998
            }
            
            scoredResults.append(ScoredSuggestion(suggestion: suggestion, score: urlScore))
        }
        
        // Sort by score (highest first) and return suggestions
        return scoredResults
            .sorted { $0.score > $1.score }
            .map { $0.suggestion }
    }
    
    private func getHistorySuggestions(for query: String) -> [ScoredSuggestion] {
        guard let database = BrowserDatabase.instance else {
            return []
        }
        
        let (dbQuery, args) = BrowserVisits.suggestionsQuery(prefix: query, limit: 10)
        guard let resultSet = database.db.executeQuery(dbQuery, withArguments: args) else {
            return []
        }
        
        var suggestions: [ScoredSuggestion] = []
        let attributes = CompletionsWindow.regularAttributes(font: nil)
        
        while resultSet.next() {
            guard let visit = BrowserVisits(dbResultSet: resultSet) else { continue }
            
            // Reconstruct full URL for display (add https:// if needed)
            let displayUrl = visit.fullUrl.hasPrefix("http") ? visit.fullUrl : "https://\(visit.fullUrl)"
            
            let suggestion = URLSuggestion(
                text: displayUrl,
                url: displayUrl,
                displayText: NSAttributedString(string: displayUrl, attributes: attributes),
                detail: "Visited \(visit.visitCount) time\(visit.visitCount == 1 ? "" : "s")",
                type: .history
            )
            
            suggestions.append(ScoredSuggestion(suggestion: suggestion, score: visit.visitCount))
        }
        
        resultSet.close()
        return suggestions
    }
    
    func browserToolbarDidBeginEditingURL(string: String) -> String? {
        return searchQueryFromURL(string)
    }
    
    func browserToolbarUserDidSubmitNavigationRequest() {
        // When the user presses enter in the URL bar, the URL bar must lose first responder.
        browserManager.webView.window?.makeFirstResponder(browserManager.webView)
    }
    
    // MARK: - iTermBrowserManagerDelegate
    
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
    
    // MARK: - Public Interface
    
    @objc func loadURL(_ urlString: String) {
        browserManager.loadURL(urlString)
    }
    
    // MARK: - Find Support
    
    @objc func performFindPanelAction(_ sender: Any?) {
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
}

@available(macOS 11.0, *)
@objc(iTermBrowserView)
class iTermBrowserView: NSView {
}
