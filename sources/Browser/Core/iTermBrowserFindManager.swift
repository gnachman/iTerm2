//
//  iTermBrowserFindManager.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import WebKit
import Combine

@available(macOS 13.0, *)
@MainActor
@objc protocol iTermBrowserFindManagerDelegate: AnyObject {
    func browserFindManager(_ manager: iTermBrowserFindManager, didUpdateResult result: iTermBrowserFindResult)
}

@available(macOS 13.0, *)
@objc enum iTermBrowserFindMode: Int {
    case substring = 0
    case caseSensitive = 1
    case caseInsensitive = 2
    case regex = 3
}

@available(macOS 13.0, *)
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

@available(macOS 13.0, *)
@objc(iTermBrowserFindManager)
@MainActor
class iTermBrowserFindManager: NSObject {
    @objc weak var delegate: iTermBrowserFindManagerDelegate?
    private weak var webView: WKWebView?
    private var currentSearchTerm: String?
    private var isSearchActive = false
    private var findMode: iTermBrowserFindMode = .substring
    private let secret: String
    private var isJavaScriptInjected = false
    
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
    
    @objc func startFind(_ searchTerm: String, caseSensitive: Bool = false) {
        guard !searchTerm.isEmpty else {
            clearFind()
            return
        }
        
        currentSearchTerm = searchTerm
        self.findMode = caseSensitive ? .caseSensitive : .caseInsensitive
        isSearchActive = true
        
        executeJavaScript(command: [
            "action": "startFind",
            "searchTerm": searchTerm,
            "searchMode": searchModeString(for: findMode)
        ])
    }
    
    @objc func startFind(_ searchTerm: String, mode: iTermBrowserFindMode) {
        guard !searchTerm.isEmpty else {
            clearFind()
            return
        }
        
        currentSearchTerm = searchTerm
        self.findMode = mode
        isSearchActive = true
        
        executeJavaScript(command: [
            "action": "startFind",
            "searchTerm": searchTerm,
            "searchMode": searchModeString(for: mode)
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
    
    private func searchModeString(for mode: iTermBrowserFindMode) -> String {
        switch mode {
        case .substring:
            return "substring"
        case .caseSensitive:
            return "caseSensitive"
        case .caseInsensitive:
            return "caseInsensitive"
        case .regex:
            return "regex"
        }
    }
}

// MARK: - WKScriptMessageHandler

@available(macOS 13.0, *)
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
        
        let result = iTermBrowserFindResult(
            matchFound: totalMatches > 0,
            searchTerm: searchTerm,
            totalMatches: totalMatches,
            currentMatch: currentMatch
        )
        
        delegate?.browserFindManager(self, didUpdateResult: result)
    }
}
