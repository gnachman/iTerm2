//
//  iTermBrowserNamedMarkManager.swift
//  iTerm2
//
//  Created by George Nachman on 6/27/25.
//

import WebKit

@available(macOS 11, *)
class iTermBrowserNamedMark: NSObject, iTermGenericNamedMarkReading {
    let url: URL
    let name: String?
    let namedMarkSort: Int
    var guid: String
    var text: String

    init(url: URL, name: String, sort: Int, guid: String, text: String = "") {
        self.url = url
        self.name = name
        self.namedMarkSort = sort
        self.guid = guid
        self.text = text

        super.init()
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case name
        case sort
        case guid
        case text
    }
    var dictionaryValue: [String: Any] {
        return [CodingKeys.url.rawValue: url.absoluteString,
                CodingKeys.name.rawValue: name!,
                CodingKeys.sort.rawValue: namedMarkSort,
                CodingKeys.guid.rawValue: guid,
                CodingKeys.text.rawValue: text]
    }

    init?(dictionaryValue: [String: Any]) {
        guard let urlString = dictionaryValue[CodingKeys.url.rawValue] as? String,
              let url = URL(string: urlString) else {
            return nil
        }
        self.url = url

        guard let name = dictionaryValue[CodingKeys.name.rawValue] as? String else {
            return nil
        }
        self.name = name

        guard let sort = dictionaryValue[CodingKeys.sort.rawValue] as? Int else {
            return nil
        }
        self.namedMarkSort = sort

        guard let guid = dictionaryValue[CodingKeys.guid.rawValue] as? String else {
            return nil
        }
        self.guid = guid

        // Text field is optional for backward compatibility
        self.text = dictionaryValue[CodingKeys.text.rawValue] as? String ?? ""

        super.init()
    }
}

@available(macOS 11, *)
class iTermBrowserNamedMarkManager {
    static let messageHandlerName = "iTerm2NamedMarkUpdate"
    static let layoutUpdateHandlerName = "iTerm2MarkLayoutUpdate"
    private var pendingNavigationMark: iTermBrowserNamedMark?
    private let secret: String
    private let user: iTermBrowserUser
    private var _cachedNamedMarks: [iTermBrowserNamedMark] = []
    
    init?(user: iTermBrowserUser) {
        guard let secret = String.makeSecureHexString() else {
            return nil
        }
        self.secret = secret
        self.user = user
        
        // Load marks from database in background
        loadMarksFromDatabase()
    }
    
    private func loadMarksFromDatabase() {
        Task {
            guard let db = await BrowserDatabase.instance(for: user) else { return }
            let dbMarks = await db.getAllNamedMarks()
            
            let marks = dbMarks.compactMap { dbMark -> iTermBrowserNamedMark? in
                guard let url = URL(string: dbMark.url) else { return nil }
                return iTermBrowserNamedMark(
                    url: url,
                    name: dbMark.name,
                    sort: Int(dbMark.sort ?? 0),
                    guid: dbMark.guid,
                    text: dbMark.text
                )
            }
            
            await MainActor.run {
                self._cachedNamedMarks = marks
                self.postNamedMarksDidChangeNotification()
            }
        }
    }
    
    private func postNamedMarksDidChangeNotification() {
        NamedMarksDidChangeNotification(sessionGuid: nil).post()
    }
    
    private func refreshCacheAndNotify(currentPageUrl: String? = nil) async {
        guard let db = await BrowserDatabase.instance(for: user) else { 
            DLog("Failed to get database instance in refreshCacheAndNotify")
            return 
        }
        let dbMarks = await db.getAllNamedMarks(sortBy: currentPageUrl)
        DLog("Retrieved \(dbMarks.count) marks from database")
        
        let marks = dbMarks.compactMap { dbMark -> iTermBrowserNamedMark? in
            guard let url = URL(string: dbMark.url) else { return nil }
            return iTermBrowserNamedMark(
                url: url,
                name: dbMark.name,
                sort: Int(dbMark.sort ?? 0),
                guid: dbMark.guid,
                text: dbMark.text
            )
        }
        
        await MainActor.run {
            self._cachedNamedMarks = marks
            DLog("Updated cache with \(marks.count) marks, posting notification")
            self.postNamedMarksDidChangeNotification()
        }
    }
    
    func getNamedMarksSortedByCurrentPage(currentPageUrl: String) async -> [iTermBrowserNamedMark] {
        guard let db = await BrowserDatabase.instance(for: user) else { return [] }
        let dbMarks = await db.getAllNamedMarks(sortBy: currentPageUrl)
        
        return dbMarks.compactMap { dbMark -> iTermBrowserNamedMark? in
            guard let url = URL(string: dbMark.url) else { return nil }
            return iTermBrowserNamedMark(
                url: url,
                name: dbMark.name,
                sort: Int(dbMark.sort ?? 0),
                guid: dbMark.guid,
                text: dbMark.text
            )
        }
    }
}

@available(macOS 11, *)
extension iTermBrowserNamedMarkManager {
    var namedMarks: [iTermBrowserNamedMark] {
        return _cachedNamedMarks
    }

    func add(with name: String, webView: WKWebView, httpMethod: String?, clickPoint: NSPoint? = nil) async throws {
        // Check if the current page was loaded with GET
        guard httpMethod == "GET" || httpMethod == nil else {
            DLog("Cannot create named mark: page was loaded with \(httpMethod ?? "unknown") method, not GET")
            throw iTermError("Invalid HTTP method \(httpMethod.d)")
        }
        
        let script: String
        if let clickPoint = clickPoint {
            // Use click point to get XPath
            script = iTermBrowserTemplateLoader.loadTemplate(
                named: "get-xpath-at-point",
                type: "js",
                substitutions: [
                    "CLICK_X": String(Int(clickPoint.x)),
                    "CLICK_Y": String(Int(clickPoint.y))
                ]
            )
        } else {
            // Use viewport center to get XPath
            script = iTermBrowserTemplateLoader.loadTemplate(
                named: "get-viewport-center-xpath",
                type: "js"
            )
        }

        do {
            let result = try await webView.evaluateJavaScript(script)
            guard let data = result as? [String: Any],
                  let xpath = data["xpath"] as? String,
                  let offsetY = data["offsetY"] as? Int,
                  let scrollY = data["scrollY"] as? Int else {
                throw iTermError("Bad result from js")
            }
            
            // Get current URL without fragment
            guard let currentURL = await webView.url else { return }
            var components = URLComponents(url: currentURL, resolvingAgainstBaseURL: false)
            
            // Create custom fragment with XPath and offset
            // Note: Don't URL-encode here - URLComponents will handle encoding when setting the fragment
            var fragment = "iterm-mark:xpath=\(xpath)&offsetY=\(offsetY)&scrollY=\(scrollY)"
            
            // Add text fragment if available for improved reliability
            if let textFragment = data["textFragment"] as? String, !textFragment.isEmpty {
                // URL encode the text fragment value since it contains special characters
                if let encodedTextFragment = textFragment.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                    fragment += "&textFragment=\(encodedTextFragment)"
                }
            }
            
            components?.fragment = fragment
            
            guard let markURL = components?.url else { return }
            
            // Create and store the named mark in database
            let guid = UUID().uuidString
            
            // Add to database
            guard let db = await BrowserDatabase.instance(for: user) else {
                throw iTermError("Failed to get database instance")
            }
            
            let success = await db.addNamedMark(guid: guid, url: markURL.absoluteString, name: name, text: "")
            DLog("Database add result: \(success) for mark '\(name)' with URL: \(markURL.absoluteString)")
            
            if !success {
                throw iTermError("Failed to save named mark to database")
            }
            
            // Refresh cache and notify clients
            DLog("Refreshing cache and notifying clients after adding mark")
            await refreshCacheAndNotify()
            
            // Refresh annotations to show the new mark
            reloadAnnotations(webView: webView)
        } catch {
            DLog("\(error)")
            throw error
        }
    }
    
    func rename(_ mark: iTermBrowserNamedMark, to newName: String, webView: WKWebView) {
        Task {
            guard let db = await BrowserDatabase.instance(for: user) else { return }
            
            let success = await db.updateNamedMarkName(guid: mark.guid, name: newName)
            if success {
                // Refresh cache and notify clients
                await refreshCacheAndNotify()
                
                // Refresh annotations to show the updated name
                reloadAnnotations(webView: webView)
            }
        }
    }
    
    func updateText(_ mark: iTermBrowserNamedMark, text: String, webView: WKWebView) {
        Task {
            guard let db = await BrowserDatabase.instance(for: user) else { return }
            
            let success = await db.updateNamedMarkText(guid: mark.guid, text: text)
            if success {
                // Refresh cache and notify clients
                await refreshCacheAndNotify()
                
                // Refresh annotations to show the updated mark
                reloadAnnotations(webView: webView)
            }
        }
    }

    func remove(_ mark: iTermBrowserNamedMark) {
        Task {
            guard let db = await BrowserDatabase.instance(for: user) else { return }
            let success = await db.removeNamedMark(guid: mark.guid)
            if success {
                // Refresh cache and notify clients
                await refreshCacheAndNotify()
            }
        }
    }
    
    func remove(_ mark: iTermBrowserNamedMark, webView: WKWebView) {
        Task {
            guard let db = await BrowserDatabase.instance(for: user) else { return }
            let success = await db.removeNamedMark(guid: mark.guid)
            if success {
                // Refresh cache and notify clients
                await refreshCacheAndNotify()
                
                // Refresh annotations after removing the mark
                reloadAnnotations(webView: webView)
            }
        }
    }

    func reveal(_ namedMark: iTermBrowserNamedMark, webView: WKWebView) {
        pendingNavigationMark = namedMark
        
        // Check if we're already at the correct URL (ignoring fragment)
        if namedMark.url.withoutFragment == webView.url?.withoutFragment {
            // Same page, just navigate to the fragment
            navigateToMark(webView: webView)
        } else {
            // Need to load the page first
            let request = URLRequest(url: namedMark.url)
            webView.load(request)
        }
    }
    
    func didFinishNavigation(webView: WKWebView, success: Bool) {
        if success {
            if pendingNavigationMark != nil {
                navigateToMark(webView: webView)
            }
            
            // Refresh cache with current page URL for sorting
            if let currentURL = webView.url {
                Task {
                    await refreshCacheAndNotify(currentPageUrl: currentURL.absoluteString)
                }
            }
            
            // Show annotations for any marks on this page
            reloadAnnotations(webView: webView)
            // Set up layout change monitoring
            setupLayoutChangeMonitoring(webView: webView)
        } else {
            DLog("Navigation failed for \(webView.url.d) with pending mark \((pendingNavigationMark?.guid).d)")
        }
    }
    
    private func setupLayoutChangeMonitoring(webView: WKWebView) {
        let script = """
        (function() {
            var lastViewportWidth = window.innerWidth;
            var lastViewportHeight = window.innerHeight;
            var lastScrollY = window.pageYOffset;
            var updatePending = false;
            
            function scheduleMarkUpdate() {
                if (updatePending) return;
                updatePending = true;
                
                setTimeout(function() {
                    updatePending = false;
                    var currentWidth = window.innerWidth;
                    var currentHeight = window.innerHeight;
                    var currentScrollY = window.pageYOffset;
                    
                    // Check if significant layout changes occurred
                    var widthChanged = Math.abs(currentWidth - lastViewportWidth) > 50;
                    var heightChanged = Math.abs(currentHeight - lastViewportHeight) > 50;
                    var significantScroll = Math.abs(currentScrollY - lastScrollY) > 100;
                    
                    if (widthChanged || heightChanged || significantScroll) {
                        console.log('Layout change detected, updating marks');
                        try {
                            window.webkit.messageHandlers.iTerm2MarkLayoutUpdate.postMessage({
                                type: 'layoutChange',
                                width: currentWidth,
                                height: currentHeight,
                                scrollY: currentScrollY
                            });
                        } catch (error) {
                            console.log('Error sending layout update:', error);
                        }
                        
                        lastViewportWidth = currentWidth;
                        lastViewportHeight = currentHeight;
                        lastScrollY = currentScrollY;
                    }
                }, 500); // Debounce updates
            }
            
            // Monitor resize events
            window.addEventListener('resize', scheduleMarkUpdate);
            
            // Monitor scroll events (for significant scrolling that might indicate content changes)
            window.addEventListener('scroll', scheduleMarkUpdate);
            
            // Monitor DOM mutations that might affect layout
            if (window.MutationObserver) {
                var observer = new MutationObserver(function(mutations) {
                    var significantChange = false;
                    for (var i = 0; i < mutations.length; i++) {
                        var mutation = mutations[i];
                        if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
                            // Check if added nodes are significant (not just text or small elements)
                            for (var j = 0; j < mutation.addedNodes.length; j++) {
                                var node = mutation.addedNodes[j];
                                if (node.nodeType === Node.ELEMENT_NODE) {
                                    var element = node;
                                    var rect = element.getBoundingClientRect();
                                    if (rect.height > 50 || rect.width > 200) {
                                        significantChange = true;
                                        break;
                                    }
                                }
                            }
                        }
                        if (significantChange) break;
                    }
                    
                    if (significantChange) {
                        console.log('Significant DOM change detected');
                        scheduleMarkUpdate();
                    }
                });
                
                observer.observe(document.body, {
                    childList: true,
                    subtree: true
                });
            }
            
            console.log('Mark layout monitoring initialized');
        })();
        """
        
        Task {
            do {
                try await webView.evaluateJavaScript(script)
            } catch {
                DLog("Error setting up layout change monitoring: \(error)")
            }
        }
    }
    
    private func navigateToMark(webView: WKWebView) {
        guard let mark = pendingNavigationMark else {
            DLog("No pending navigation mark")
            return
        }
        defer {
            pendingNavigationMark = nil
        }

        // Parse the fragment to extract parameters
        guard let fragment = mark.url.fragment,
              fragment.hasPrefix("iterm-mark:") else {
            DLog("Invalid mark fragment: \(mark.url.fragment ?? "nil")")
            return
        }
        
        // Parse parameters from fragment
        // Note: fragment is already percent-decoded by URL, but the individual parameter values may still be encoded
        let paramString = String(fragment.dropFirst("iterm-mark:".count))
        DLog("Raw fragment parameters: \(paramString)")
        var params: [String: String] = [:]
        for pair in paramString.split(separator: "&") {
            let components = pair.split(separator: "=", maxSplits: 1)
            if components.count == 2 {
                let key = String(components[0])
                let value = String(components[1])
                // Decode the value - this is important for XPath which contains special characters
                params[key] = value.removingPercentEncoding ?? value
            }
        }
        
        guard let xpath = params["xpath"],
              let offsetY = params["offsetY"],
              let scrollY = params["scrollY"] else {
            DLog("Missing required parameters in mark fragment")
            return
        }
        
        // Extract text fragment if available
        let textFragment = params["textFragment"]?.removingPercentEncoding
        
        DLog("Parsed parameters - xpath: \(xpath), offsetY: \(offsetY), scrollY: \(scrollY), textFragment: \(textFragment ?? "none")")
        
        var substitutions: [String: String] = [
            "XPATH": xpath,
            "OFFSET_Y": offsetY,
            "SCROLL_Y": scrollY
        ]
        
        // Add text fragment if available
        if let textFragment = textFragment {
            substitutions["TEXT_FRAGMENT"] = textFragment
        } else {
            substitutions["TEXT_FRAGMENT"] = ""
        }
        
        let script = iTermBrowserTemplateLoader.loadTemplate(
            named: "navigate-to-named-mark",
            type: "js",
            substitutions: substitutions
        )
        
        Task {
            do {
                let result = try await webView.evaluateJavaScript(script)
                if let success = result as? Bool, !success {
                    DLog("Failed to navigate to mark - element not found")
                }
            } catch {
                DLog("Error navigating to mark: \(error)")
            }
        }
    }

    private func reloadAnnotations(webView: WKWebView) {
        guard let currentURL = webView.url else { return }
        
        Task {
            guard let db = await BrowserDatabase.instance(for: user) else { return }
            
            // Get marks for this URL from database
            let dbMarks = await db.getNamedMarksForUrl(currentURL.absoluteString)
            
            // Convert to iTermBrowserNamedMark objects
            let marksForPage = dbMarks.compactMap { dbMark -> iTermBrowserNamedMark? in
                guard let url = URL(string: dbMark.url) else { return nil }
                return iTermBrowserNamedMark(
                    url: url,
                    name: dbMark.name,
                    sort: Int(dbMark.sort ?? 0),
                    guid: dbMark.guid,
                    text: dbMark.text
                )
            }
            
            guard !marksForPage.isEmpty else { return }
            
            await showAnnotations(marksForPage: marksForPage, webView: webView)
        }
    }
    
    private func showAnnotations(marksForPage: [iTermBrowserNamedMark], webView: WKWebView) async {
        
        // Convert marks to JavaScript format
        var markData: [[String: Any]] = []
        for mark in marksForPage {
            guard let fragment = mark.url.fragment,
                  fragment.hasPrefix("iterm-mark:") else {
                continue
            }
            
            // Parse the fragment to extract XPath and offset
            let paramString = String(fragment.dropFirst("iterm-mark:".count))
            var params: [String: String] = [:]
            for pair in paramString.split(separator: "&") {
                let components = pair.split(separator: "=", maxSplits: 1)
                if components.count == 2 {
                    let key = String(components[0])
                    let value = String(components[1])
                    params[key] = value.removingPercentEncoding ?? value
                }
            }
            
            guard let xpath = params["xpath"],
                  let offsetYString = params["offsetY"],
                  let offsetY = Int(offsetYString) else {
                continue
            }
            
            markData.append([
                "name": mark.name ?? "Unnamed",
                "xpath": xpath,
                "offsetY": offsetY,
                "text": mark.text,
                "guid": mark.guid
            ])
        }
        
        guard !markData.isEmpty else { return }
        
        // Convert to JSON
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: markData, options: [])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
            
            let script = iTermBrowserTemplateLoader.loadTemplate(
                named: "show-named-mark-annotations",
                type: "js",
                substitutions: [
                    "MARKS_JSON": jsonString,
                    "SECRET": secret
                ]
            )
            
            Task {
                do {
                    try await webView.evaluateJavaScript(script)
                } catch {
                    DLog("Error showing mark annotations: \(error)")
                }
            }
        } catch {
            DLog("Error serializing mark data: \(error)")
        }
    }

    private func urlEncode(_ string: String) -> String {
        return string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }
    
    func handleMessage(webView: WKWebView, message: WKScriptMessage) -> (guid: String, text: String)? {
        guard let messageData = message.body as? [String: Any],
              let guid = messageData["guid"] as? String,
              let text = messageData["text"] as? String,
              let sessionSecret = messageData["sessionSecret"] as? String,
              sessionSecret == secret else {
            return nil
        }
        
        // Find the mark and update its text
        if let mark = namedMarks.first(where: { $0.guid == guid }) {
            updateText(mark, text: text, webView: webView)
            return (guid: guid, text: text)
        }
        
        return nil
    }
    
    func handleLayoutUpdateMessage(webView: WKWebView, message: WKScriptMessage) {
        guard let messageData = message.body as? [String: Any],
              let type = messageData["type"] as? String,
              type == "layoutChange" else {
            return
        }
        
        DLog("Handling layout change, updating mark positions")
        updateMarkPositions(webView: webView)
    }
    
    private func updateMarkPositions(webView: WKWebView) {
        guard let currentURL = webView.url else { return }
        
        // Find marks for this page
        let marksForPage = namedMarks.filter { mark in
            mark.url.withoutFragment == currentURL.withoutFragment
        }
        
        guard !marksForPage.isEmpty else { return }
        
        let script = iTermBrowserTemplateLoader.loadTemplate(
            named: "update-mark-positions",
            type: "js",
            substitutions: [
                "SECRET": secret
            ]
        )
        
        Task {
            do {
                let result = try await webView.evaluateJavaScript(script)
                if let updates = result as? [[String: Any]] {
                    await processMarkPositionUpdates(updates: updates, webView: webView)
                }
            } catch {
                DLog("Error updating mark positions: \(error)")
            }
        }
    }
    
    private func processMarkPositionUpdates(updates: [[String: Any]], webView: WKWebView) async {
        // Position updates from layout changes should not modify the stored URL
        // The URL contains XPath and text fragment which are stable identifiers
        // We just update the annotations to reflect new positions visually
        let hasUpdates = updates.anySatisfies { update in
            guard let guid = update["guid"] as? String,
                  update["scrollY"] is Int,
                  update["offsetY"] is Int,
                  namedMarks.first(where: { $0.guid == guid }) != nil else {
                return false
            }
            return true
        }

        if hasUpdates {
            // Just refresh the visual annotations with current positions
            reloadAnnotations(webView: webView)
        }
    }
}

@objc(iTermError) public class iTermErrorObjC: NSObject {
    @objc static let domain = "com.iterm2.generic"
    @objc(iTermErrorType) public enum ErrorType: Int, Codable {
        case generic = 0
        case requestTooLarge = 1
    }
}

struct iTermError: LocalizedError, CustomStringConvertible, CustomNSError, Codable {
    public internal(set) var message: String
    public internal(set) var type = iTermErrorObjC.ErrorType.generic

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }

    public var description: String {
        message
    }

    var localizedDescription: String {
        message
    }

    public static var errorDomain: String { iTermErrorObjC.domain }
    public var errorCode: Int { type.rawValue }
}

