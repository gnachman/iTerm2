//
//  iTermBrowserFindManager.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import WebKit

@available(macOS 13.0, *)
@MainActor
@objc protocol iTermBrowserFindManagerDelegate: AnyObject {
    func browserFindManager(_ manager: iTermBrowserFindManager, didUpdateResult result: iTermBrowserFindResult)
}

@available(macOS 13.0, *)
@objc(iTermBrowserFindResult)
@MainActor
class iTermBrowserFindResult: NSObject {
    @objc let matchFound: Bool
    @objc let searchTerm: String
    
    init(matchFound: Bool, searchTerm: String) {
        self.matchFound = matchFound
        self.searchTerm = searchTerm
    }
}

@available(macOS 13.0, *)
@objc(iTermBrowserFindManager)
@MainActor
class iTermBrowserFindManager: NSObject {
    @objc weak var delegate: iTermBrowserFindManagerDelegate?
    private weak var webView: WKWebView?
    private var currentSearchTerm: String?
    private var isSearchActive = false
    private var caseSensitive = false
    
    @objc init(webView: WKWebView) {
        self.webView = webView
        super.init()
    }
    
    // MARK: - Public Interface
    
    @objc func startFind(_ searchTerm: String, caseSensitive: Bool = false) {
        guard !searchTerm.isEmpty else {
            clearFind()
            return
        }
        
        currentSearchTerm = searchTerm
        self.caseSensitive = caseSensitive
        isSearchActive = true
        
        let configuration = WKFindConfiguration()
        configuration.caseSensitive = caseSensitive
        configuration.wraps = true
        
        webView?.find(searchTerm, configuration: configuration) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleFindResult(result, searchTerm: searchTerm)
            }
        }
    }
    
    @objc func findNext() {
        guard isSearchActive, let searchTerm = currentSearchTerm else { return }
        
        let configuration = WKFindConfiguration()
        configuration.caseSensitive = self.caseSensitive
        configuration.wraps = true
        configuration.backwards = false
        
        webView?.find(searchTerm, configuration: configuration) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleFindResult(result, searchTerm: searchTerm)
            }
        }
    }
    
    @objc func findPrevious() {
        guard isSearchActive, let searchTerm = currentSearchTerm else { return }
        
        let configuration = WKFindConfiguration()
        configuration.caseSensitive = self.caseSensitive
        configuration.wraps = true
        configuration.backwards = true
        
        webView?.find(searchTerm, configuration: configuration) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleFindResult(result, searchTerm: searchTerm)
            }
        }
    }
    
    @objc func clearFind() {
        // Clear find by searching for empty string
        let configuration = WKFindConfiguration()
        configuration.caseSensitive = false
        configuration.wraps = false
        
        webView?.find("", configuration: configuration) { _ in
            // Ignore result for clear operation
        }
        
        currentSearchTerm = nil
        isSearchActive = false
        
        // Notify delegate that find was cleared
        let result = iTermBrowserFindResult(matchFound: false, searchTerm: "")
        delegate?.browserFindManager(self, didUpdateResult: result)
    }
    
    @objc var hasActiveSearch: Bool {
        return isSearchActive && currentSearchTerm != nil
    }
    
    @objc var activeSearchTerm: String? {
        return isSearchActive ? currentSearchTerm : nil
    }
    
    // MARK: - Private Methods
    
    private func handleFindResult(_ result: WKFindResult, searchTerm: String) {
        let findResult = iTermBrowserFindResult(
            matchFound: result.matchFound,
            searchTerm: searchTerm
        )
        
        delegate?.browserFindManager(self, didUpdateResult: findResult)
    }
}
