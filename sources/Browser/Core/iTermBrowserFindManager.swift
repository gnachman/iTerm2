//
//  iTermBrowserFindManager.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import WebKit
import Combine

@MainActor
@objc protocol iTermBrowserFindManagerDelegate: AnyObject {
    func browserFindManager(_ manager: iTermBrowserFindManager, didUpdateResult result: iTermBrowserFindResult)
}

enum iTermBrowserFindMode: String {
    case caseSensitive = "caseSensitive"
    case caseInsensitive = "caseInsensitive"
    case caseSensitiveRegex = "caseSensitiveRegex"
    case caseInsensitiveRegex = "caseInsensitiveRegex"
}

@objc(iTermBrowserFindResult)
@MainActor
class iTermBrowserFindResult: NSObject {
    @objc let matchFound: Bool
    @objc let searchTerm: String
    @objc let totalMatches: Int
    @objc let currentMatch: Int
    
    init(matchFound: Bool, searchTerm: String, totalMatches: Int = 0, currentMatch: Int = 0) {
        self.matchFound = matchFound
        self.searchTerm = searchTerm
        self.totalMatches = totalMatches
        self.currentMatch = currentMatch
    }
}

@objc(iTermBrowserFindManager)
@MainActor
class iTermBrowserFindManager: NSObject {
    @objc weak var delegate: iTermBrowserFindManagerDelegate?
    private weak var webView: WKWebView?
    private var currentSearchTerm: String?
    private var isSearchActive = false
    private var findMode: iTermBrowserFindMode = .caseSensitive
    private let secret: String
    private var isJavaScriptInjected = false
    
    // Incremental search state
    private var totalMatches: Int = 0
    private var currentMatchIndex: Int = 0
    private var searchProgress: Double = 0.0
    private var searchComplete: Bool = false
    
    @objc init?(webView: WKWebView) {
        guard let secret = String.makeSecureHexString() else {
            return nil
        }
        self.secret = secret
        self.webView = webView
        super.init()
        setupJavaScript()
    }
    
    // MARK: - Public Interface
    
    func startFind(_ searchTerm: String, mode: iTermBrowserFindMode) {
        guard !searchTerm.isEmpty else {
            clearFind()
            return
        }
        
        currentSearchTerm = searchTerm
        self.findMode = mode
        resetSearchState()
        
        executeJavaScript(command: [
            "action": "startFind",
            "searchTerm": searchTerm,
            "searchMode": mode.rawValue
        ])
    }
    
    @objc func findNext() {
        guard isSearchActive else { return }
        
        executeJavaScript(command: ["action": "findNext"])
    }
    
    @objc func findPrevious() {
        guard isSearchActive else { return }
        
        executeJavaScript(command: ["action": "findPrevious"])
    }
    
    @objc func clearFind() {
        executeJavaScript(command: ["action": "clearFind"])
        
        currentSearchTerm = nil
        resetSearchState(active: false)
        
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
    
    // MARK: - Incremental Search Support
    
    @objc var numberOfSearchResults: Int {
        return totalMatches
    }
    
    @objc var currentIndex: Int {
        return currentMatchIndex
    }
    
    @objc var findInProgress: Bool {
        return isSearchActive && !searchComplete
    }
    
    @objc func continueFind(progress: UnsafeMutablePointer<Double>, range: NSRangePointer) -> Bool {
        guard isSearchActive else {
            progress.pointee = 1.0
            range.pointee = NSRange(location: 100, length: 100)
            return false
        }
        
        // Update progress based on search state
        progress.pointee = searchProgress
        
        // For browser, range represents search progress as percentage
        // location = current progress (0-100), length = total (100)
        let progressPercent = Int(searchProgress * 100)
        range.pointee = NSRange(location: progressPercent, length: 100)
        
        // If search is complete, no more work to do
        if searchComplete {
            progress.pointee = 1.0
            range.pointee = NSRange(location: 100, length: 100)
            return false
        }
        
        // For now, browser search completes immediately
        // In the future, this could be enhanced for incremental search
        searchComplete = true
        searchProgress = 1.0
        return false
    }
    
    @objc func resetFindCursor() {
        clearFind()
    }
    
    // MARK: - Private Methods
    
    private func setupJavaScript() {
        guard let webView = webView else { return }
        
        // Load and inject the custom find JavaScript
        let script = iTermBrowserTemplateLoader.loadTemplate(
            named: "custom-find",
            type: "js",
            substitutions: ["SECRET": secret]
        )
        
        let userScript = WKUserScript(
            source: script,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        
        webView.configuration.userContentController.addUserScript(userScript)
        
        // Add message handler
        webView.configuration.userContentController.add(
            self,
            name: "iTermCustomFind"
        )
        
        isJavaScriptInjected = true
    }
    
    private func executeJavaScript(command: [String: Any]) {
        guard isJavaScriptInjected, let webView = webView else { return }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: command)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            let script = "window.iTermCustomFind && window.iTermCustomFind.handleCommand(\(jsonString))"
            
            webView.evaluateJavaScript(script) { _, error in
                if let error = error {
                    DLog("Find JavaScript error: \(error)")
                }
            }
        } catch {
            DLog("Failed to serialize find command: \(error)")
        }
    }
    
    private func resetSearchState(active: Bool = true) {
        isSearchActive = active
        totalMatches = 0
        currentMatchIndex = 0
        searchProgress = 0.0
        searchComplete = false
    }
}

// MARK: - WKScriptMessageHandler

extension iTermBrowserFindManager: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                             didReceive message: WKScriptMessage) {
        guard message.name == "iTermCustomFind",
              let body = message.body as? [String: Any],
              let sessionSecret = body["sessionSecret"] as? String,
              sessionSecret == secret,
              let action = body["action"] as? String else {
            return
        }
        
        if action == "resultsUpdated",
           let data = body["data"] as? [String: Any] {
            handleResultsUpdate(data)
        }
    }
    
    private func handleResultsUpdate(_ data: [String: Any]) {
        let searchTerm = data["searchTerm"] as? String ?? ""
        let totalMatches = data["totalMatches"] as? Int ?? 0
        let currentMatch = data["currentMatch"] as? Int ?? 0
        
        // Update internal state
        self.totalMatches = totalMatches
        self.currentMatchIndex = currentMatch
        
        // Mark search as complete when we get results
        if !searchComplete {
            searchComplete = true
            searchProgress = 1.0
        }
        
        let result = iTermBrowserFindResult(
            matchFound: totalMatches > 0,
            searchTerm: searchTerm,
            totalMatches: totalMatches,
            currentMatch: currentMatch
        )
        
        delegate?.browserFindManager(self, didUpdateResult: result)
    }
}
