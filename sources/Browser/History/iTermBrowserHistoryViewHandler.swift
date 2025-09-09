//
//  iTermBrowserHistoryViewHandler.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

import WebKit
import Foundation

@available(macOS 11.0, *)
@objc protocol iTermBrowserHistoryViewHandlerDelegate: AnyObject {
    @MainActor func historyViewHandlerDidNavigateToURL(_ handler: iTermBrowserHistoryViewHandler, url: String)
}

@available(macOS 11.0, *)
@objc(iTermBrowserHistoryViewHandler)
@MainActor
class iTermBrowserHistoryViewHandler: NSObject, iTermBrowserPageHandler {
    static let historyURL = URL(string: "\(iTermBrowserSchemes.about):history")!
    private let user: iTermBrowserUser
    weak var delegate: iTermBrowserHistoryViewHandlerDelegate?
    private let historyController: iTermBrowserHistoryController
    
    init(user: iTermBrowserUser,
         historyController: iTermBrowserHistoryController) {
        self.user = user
        self.historyController = historyController
        super.init()
    }
    
    // MARK: - Public Interface
    
    func generateHistoryHTML() -> String {
        let script = iTermBrowserTemplateLoader.loadTemplate(named: "history-page",
                                                             type: "js",
                                                             substitutions: [:])
        return iTermBrowserTemplateLoader.loadTemplate(named: "history-page",
                                                       type: "html",
                                                       substitutions: ["HISTORY_SCRIPT": script])
    }
    
    func start(urlSchemeTask: WKURLSchemeTask, url: URL) {
        let htmlToServe = generateHistoryHTML()
        
        guard let data = htmlToServe.data(using: .utf8) else {
            urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserHistoryViewHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode HTML"]))
            return
        }
        
        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    
    
    func handleHistoryMessage(_ message: [String: Any], webView: iTermBrowserWebView) async {
        DLog("History message received: \(message)")

        guard let action = message["action"] as? String else {
            DLog("No action in history message")
            return
        }
        switch action {
        case "loadEntries":
            DLog("Handling history action: \(action)")
            let offset = message["offset"] as? Int ?? 0
            let limit = message["limit"] as? Int ?? 50
            let searchQuery = message["searchQuery"] as? String ?? ""
            return await loadHistoryEntries(offset: offset,
                                            limit: limit,
                                            searchQuery: searchQuery,
                                            webView: webView)

        case "deleteEntry":
            if let entryId = message["entryId"] as? String {
                await deleteHistoryEntry(entryId: entryId, webView: webView)
            }
            return

        case "navigateToURL":
            if let url = message["url"] as? String {
                delegate?.historyViewHandlerDidNavigateToURL(self, url: url)
            }
            return

        case "clearAllHistory":
            await clearAllHistory(webView: webView)
        default:
            return
        }
}

    
    // MARK: - Private Implementation
    
    private func loadHistoryEntries(offset: Int, limit: Int, searchQuery: String, webView: iTermBrowserWebView) async {
        DLog("Loading history entries: offset=\(offset), limit=\(limit), query='\(searchQuery)'")
        
        guard let database = await BrowserDatabase.instance(for: user) else {
            DLog("Failed to get database instance")
            await sendHistoryEntries([], hasMore: false, to: webView)
            return
        }
        
        DLog("Got database instance, querying entries...")
        
        let entries: [BrowserHistory]
        if searchQuery.isEmpty {
            entries = await database.getRecentHistory(offset: offset, limit: limit + 1) // +1 to check if there are more
        } else {
            entries = await database.searchHistory(terms: searchQuery, offset: offset, limit: limit + 1)
        }
        
        DLog("Found \(entries.count) history entries")
        
        let hasMore = entries.count > limit
        let limitedEntries = Array(entries.prefix(limit))
        
        await sendHistoryEntries(limitedEntries, hasMore: hasMore, to: webView)
    }
    
    private func deleteHistoryEntry(entryId: String, webView: iTermBrowserWebView) async {
        guard let database = await BrowserDatabase.instance(for: user) else { return }
        await database.deleteHistoryEntry(id: entryId)
        
        // Send confirmation to UI on main actor
        await sendEntryDeletedConfirmation(entryId: entryId, to: webView)
    }
    
    private func clearAllHistory(webView: iTermBrowserWebView) async {
        guard let database = await BrowserDatabase.instance(for: user) else { return }
        await database.deleteAllHistory()
        
        // Reload the history view on main actor
        await sendHistoryClearedConfirmation(to: webView)
    }
    
    @MainActor
    private func sendHistoryEntries(_ entries: [BrowserHistory], hasMore: Bool, to webView: iTermBrowserWebView) async {
        let entriesData = entries.map { entry in
            [
                "id": entry.id,
                "url": entry.url,
                "title": entry.title ?? "",
                "visitDate": entry.visitDate.timeIntervalSince1970,
                "transitionType": entry.transitionType.rawValue
            ]
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: [
                "entries": entriesData,
                "hasMore": hasMore
            ], options: [])

            if let jsonString = String(data: jsonData, encoding: .utf8) {
                // NOTE: evaluateJavaScript crashes if the script doesn't return a value. So return 1.
                let script = "window.onHistoryEntriesLoaded && window.onHistoryEntriesLoaded(\(jsonString)); 1"
                do {
                    let result = try await webView.evaluateJavaScript(script)
                    DLog("JavaScript executed successfully: \(String(describing: result))")
                } catch {
                    DLog("Failed to execute JavaScript: \(error)")
                }
            }
        } catch {
            DLog("Failed to serialize history entries: \(error)")
        }
    }
    
    @MainActor
    private func sendEntryDeletedConfirmation(entryId: String, to webView: iTermBrowserWebView) async {
        // NOTE: evaluateJavaScript crashes if the script doesn't return a value. So return 1.
        let script = "window.onHistoryEntryDeleted && window.onHistoryEntryDeleted('\(entryId)'); 1"
        do {
            let result = try await webView.evaluateJavaScript(script)
            DLog("JavaScript executed successfully: \(String(describing: result))")
        } catch {
            DLog("Failed to execute JavaScript: \(error)")
        }
    }
    
    @MainActor
    private func sendHistoryClearedConfirmation(to webView: iTermBrowserWebView) async {
        // NOTE: evaluateJavaScript crashes if the script doesn't return a value. So return 1.
        let script = "window.onHistoryCleared && window.onHistoryCleared(); 1"
        do {
            let result = try await webView.evaluateJavaScript(script)
            DLog("JavaScript executed successfully: \(String(describing: result))")
        } catch {
            DLog("Failed to execute JavaScript: \(error)")
        }
    }
    
    // MARK: - iTermBrowserPageHandler Protocol
    
    func injectJavaScript(into webView: iTermBrowserWebView) {
        // History pages don't need JavaScript injection beyond what's in the HTML
    }
    
    func resetState() {
        // History handler doesn't maintain state that needs resetting
    }
}
