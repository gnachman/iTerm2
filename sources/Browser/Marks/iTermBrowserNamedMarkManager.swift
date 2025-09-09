//
//  iTermBrowserNamedMarkManager.swift
//  iTerm2
//
//  Created by George Nachman on 6/27/25.
//

import WebKit

@MainActor
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
        Task {
            await loadMarksFromDatabase()
        }
    }
}

// MARK: - Location
extension iTermBrowserNamedMarkManager {
    struct Location: CustomDebugStringConvertible {
        var debugDescription: String {
            "<Location xpath=\(xpath) offsetY=\(offsetY) scrollY=\(scrollY) textFragment=\(textFragment.d) y=\(y)>"
        }
        var xpath: String
        var offsetY: Int
        var scrollY: Int
        var textFragment: String?
        var y: Int

        init?(_ data: [String: Any]) {
            guard let xpath = data["xpath"] as? String,
                  let offsetY = data["offsetY"] as? Int,
                  let scrollY = data["scrollY"] as? Int,
                  let y = data["y"] as? Int else {
                return nil
            }
            self.xpath = xpath
            self.offsetY = offsetY
            self.scrollY = scrollY
            self.textFragment = data["textFragment"] as? String
            self.y = y
        }

        init?(_ url: URL) {
            guard let fragment = url.fragment,
                  fragment.hasPrefix("iterm-mark:") else {
                DLog("Invalid mark fragment: \(url.fragment ?? "nil")")
                return nil
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
                  let offsetYStr = params["offsetY"],
                  let offsetY = Int(offsetYStr),
                  let scrollYStr = params["scrollY"],
                  let scrollY = Int(scrollYStr),
                  let yStr = params["y"],
                  let y = Int(yStr) else {
                DLog("Missing required parameters in mark fragment")
                return nil
            }

            self.textFragment = params["textFragment"]?.removingPercentEncoding
            self.xpath = xpath
            self.offsetY = offsetY
            self.scrollY = scrollY
            self.y = y
        }

        var fragment: String {
            // Create custom fragment with XPath and offset
            // Note: Don't URL-encode here - URLComponents will handle encoding when setting the fragment
            var fragment = "iterm-mark:xpath=\(xpath)&offsetY=\(offsetY)&scrollY=\(scrollY)&y=\(y)"

            // Add text fragment if available for improved reliability
            if let textFragment, !textFragment.isEmpty {
                // URL encode the text fragment value since it contains special characters
                if let encodedTextFragment = textFragment.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                    fragment += "&textFragment=\(encodedTextFragment)"
                }
            }
            return fragment
        }

        func jsDict(name: String?, guid: String) -> [String: Any] {
            [
                "name": name ?? "Unnamed",
                "xpath": xpath,
                "offsetY": offsetY,
                "textFragment": textFragment ?? "",
                "guid": guid,
                "y": y
            ]
        }
    }
}

// MARK: - Public API

@MainActor
extension iTermBrowserNamedMarkManager {
    var namedMarks: [iTermBrowserNamedMark] {
        return _cachedNamedMarks
    }

    func add(with name: String,
             webView: iTermBrowserWebView,
             httpMethod: String?,
             clickPoint: NSPoint) async throws {
        // Check if the current page was loaded with GET
        guard httpMethod == "GET" || httpMethod == nil else {
            DLog("Cannot create named mark: page was loaded with \(httpMethod ?? "unknown") method, not GET")
            throw iTermError("Invalid HTTP method \(httpMethod.d)")
        }

        do {
            let location = try await jsLocation(clickPoint: clickPoint, inWebView: webView)

            guard let markURL = webView.url?.namedMark(location: location) else {
                return
            }

            try await dbAdd(name: name, markURL: markURL)

            // Refresh cache and notify clients
            DLog("Refreshing cache and notifying clients after adding mark")
            await loadMarksFromDatabase()

            // Refresh annotations to show the new mark
            reloadAnnotations(webView: webView)
        } catch {
            DLog("\(error)")
            throw error
        }
    }

    func remove(_ mark: iTermBrowserNamedMark, webView: iTermBrowserWebView) {
        Task {
            do {
                try await dbRemove(guid: mark.guid)
                _cachedNamedMarks.removeFirst { $0.guid == mark.guid }
                self.postNamedMarksDidChangeNotification()

                // Refresh annotations after removing the mark
                reloadAnnotations(webView: webView)
            } catch {
                DLog("\(error)")
            }
        }
    }

    func reveal(_ namedMark: iTermBrowserNamedMark, webView: iTermBrowserWebView) {
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

    func rename(_ mark: iTermBrowserNamedMark, to newName: String, webView: iTermBrowserWebView) {
        Task {
            do {
                try await dbRename(guid: mark.guid, newName: newName)
                mutate(guid: mark.guid) {
                    $0.name = newName
                }

                // Refresh annotations to show the updated name
                reloadAnnotations(webView: webView)
            } catch {
                DLog("\(error)")
            }
        }
    }

    func didFinishNavigation(webView: iTermBrowserWebView, success: Bool) {
        if success {
            if pendingNavigationMark != nil {
                navigateToMark(webView: webView)
            }

            // Show annotations for any marks on this page
            reloadAnnotations(webView: webView)
            // Set up layout change monitoring
            jsSetupLayoutChangeMonitoring(webView: webView)
        } else {
            DLog("Navigation failed for \(webView.url.d) with pending mark \((pendingNavigationMark?.guid).d)")
        }
    }

    func handleMessage(webView: iTermBrowserWebView, message: WKScriptMessage) -> Bool {
        guard let messageData = message.body as? [String: Any],
              let guid = messageData["guid"] as? String,
              let sessionSecret = messageData["sessionSecret"] as? String,
              sessionSecret == secret else {
            return false
        }

        // Check if this is a delete operation
        if let shouldDelete = messageData["delete"] as? Bool, shouldDelete {
            // Find the mark and delete it
            if let mark = namedMarks.first(where: { $0.guid == guid }) {
                self.remove(mark, webView: webView)
                return true
            }
        } else if let name = messageData["name"] as? String {
            // Find the mark and update its name
            if let mark = namedMarks.first(where: { $0.guid == guid }) {
                rename(mark, to: name, webView: webView)
                return true
            }
        }

        return false
    }

    func handleLayoutUpdateMessage(webView: iTermBrowserWebView, message: WKScriptMessage) {
        NSLog("Handle layout update")
        guard let messageData = message.body as? [String: Any],
              let type = messageData["type"] as? String,
              type == "layoutChange" else {
            return
        }

        DLog("Handling layout change, updating mark positions")
        updateMarkPositions(webView: webView)
    }
}

// MARK: - Private Implementation

@MainActor
private extension iTermBrowserNamedMarkManager {
    func setLocationChangeMonitoringEnabled(in webView: iTermBrowserWebView, _ value: Bool) async {
        if value {
            _ = try? await webView.safelyCallAsyncJavaScript(
                "console.log('Swift enabling monitor.'); window.iTermLayoutChangeMonitor.reenableLayoutChangeMonitoring()",
                contentWorld: .defaultClient)
        } else {
            _ = try? await webView.safelyCallAsyncJavaScript(
                "console.log('Swift disabling monitor.'); window.iTermLayoutChangeMonitor.disableLayoutChangeMonitoring()",
                contentWorld: .defaultClient)
        }
    }

    func safelyModifyDOM(in webView: iTermBrowserWebView, _ closure: () async throws -> ()) async rethrows {
        await setLocationChangeMonitoringEnabled(in: webView, false)
        do {
            try await closure()
            await setLocationChangeMonitoringEnabled(in: webView, true)
        } catch {
            await setLocationChangeMonitoringEnabled(in: webView, true)
            throw error
        }
    }

    func mutate(guid: String, closure: (iTermBrowserNamedMark) -> ()) {
        if let i = _cachedNamedMarks.firstIndex(where: { $0.guid == guid}) {
            closure(_cachedNamedMarks[i])
            self.postNamedMarksDidChangeNotification()
        }
    }

    // Populate cache. Called once during initialization.
    func loadMarksFromDatabase() async {
        guard let marks = await dbLoad() else {
            return
        }
        self._cachedNamedMarks = marks
        self.postNamedMarksDidChangeNotification()
    }

    // Notify client of state change.
    func postNamedMarksDidChangeNotification() {
        NamedMarksDidChangeNotification(sessionGuid: nil).post()
    }
    
    func navigateToMark(webView: iTermBrowserWebView) {
        guard let mark = pendingNavigationMark else {
            DLog("No pending navigation mark")
            return
        }
        defer {
            pendingNavigationMark = nil
        }

        guard let location = Location(mark.url) else {
            DLog("Invalid URL: \(mark.url)")
            return
        }

        DLog("Parsed location: \(location)")
        jsNavigate(location, webView: webView)
    }

    func reloadAnnotations(webView: iTermBrowserWebView) {
        guard let currentURL = webView.url else {
            return
        }

        Task {
            do {
                let dbMarks = try await dbFetch(forURL: currentURL)
                let marksForPage = dbMarks.compactMap {
                    iTermBrowserNamedMark(row: $0)
                }

                guard !marksForPage.isEmpty else {
                    return
                }

                await showAnnotations(marksForPage: marksForPage, webView: webView)
            } catch {
                DLog("\(error)")
            }
        }
    }

    func showAnnotations(marksForPage: [iTermBrowserNamedMark], webView: iTermBrowserWebView) async {
        await safelyModifyDOM(in: webView) {
            let markData = marksForPage.compactMap { $0.jsDict }
            await jsShow(markData: markData, webView: webView)
        }
    }

    func urlEncode(_ string: String) -> String {
        return string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }

    func updateMarkPositions(webView: iTermBrowserWebView) {
        guard let currentURL = webView.url else {
            return
        }

        // Find marks for this page
        let marksForPage = namedMarks.filter { mark in
            mark.url.withoutFragment == currentURL.withoutFragment
        }
        
        guard !marksForPage.isEmpty else {
            return
        }
        jsUpdatePositions(webView: webView)
    }
    
    func processMarkPositionUpdates(updates: [[String: Any]], webView: iTermBrowserWebView) async {
        // Position updates from layout changes should not modify the stored URL
        // The URL contains XPath and text fragment which are stable identifiers
        // We just update the annotations to reflect new positions visually
        let hasUpdates = updates.anySatisfies { update in
            guard let guid = update["guid"] as? String,
                  update["scrollY"] is Int,
                  update["offsetY"] is Int,
                  update["y"] is Int,
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

// MARK: - Calls to JS

private extension iTermBrowserNamedMarkManager {
    private func jsLocation(clickPoint: NSPoint, inWebView webView: iTermBrowserWebView) async throws -> Location {
        let script: String
        // Use click point to get XPath
        script = iTermBrowserTemplateLoader.loadTemplate(
            named: "get-xpath-at-point",
            type: "js",
            substitutions: [
                "CLICK_X": String(Int(clickPoint.x)),
                "CLICK_Y": String(Int(clickPoint.y))
            ]
        )

        let result = try await webView.safelyEvaluateJavaScript(script, contentWorld: .defaultClient)

        guard let data = result as? [String: Any] else {
            throw iTermError("Bad result from js")
        }
        guard let location = Location(data) else {
            throw iTermError("Bad result from js")
        }
        return location
    }

    func jsSetupLayoutChangeMonitoring(webView: iTermBrowserWebView) {
        let script = iTermBrowserTemplateLoader.load(template: "layout-change-monitor.js",
                                                     substitutions: [:])

        Task {
            do {
                _ = try await webView.safelyEvaluateJavaScript(script, contentWorld: .defaultClient)
            } catch {
                DLog("Error setting up layout change monitoring: \(error)")
            }
        }
    }

    func jsNavigate(_ location: Location, webView: iTermBrowserWebView) {
        var substitutions: [String: String] = [
            "XPATH": location.xpath,
            "OFFSET_Y": String(location.offsetY),
            "SCROLL_Y": String(location.scrollY),
            "Y": String(location.y)
        ]

        // Add text fragment if available
        if let textFragment = location.textFragment {
            substitutions["TEXT_FRAGMENT"] = textFragment
        } else {
            substitutions["TEXT_FRAGMENT"] = ""
        }

        let script = iTermBrowserTemplateLoader.loadTemplate(
            named: "navigate-to-named-mark",
            type: "js",
            substitutions: substitutions)

        Task {
            do {
                try await safelyModifyDOM(in: webView) {
                    let result = try await webView.safelyEvaluateJavaScript(script, contentWorld: .defaultClient)
                    if let success = result as? Bool, !success {
                        DLog("Failed to navigate to mark - element not found")
                    }
                }
            } catch {
                DLog("Error navigating to mark: \(error)")
            }
        }
    }

    func jsShow(markData: [[String: Any]], webView: iTermBrowserWebView) async {
        NSLog("%@", "jsShow \(markData)")
        if markData.isEmpty {
            // This would be a no-op
            return
        }
        // Convert to JSON
        let jsonString: String
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: markData, options: [])
            jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        } catch {
            DLog("Error serializing mark data: \(error)")
            return
        }

        let script = iTermBrowserTemplateLoader.loadTemplate(
            named: "show-named-mark-annotations",
            type: "js",
            substitutions: [
                "MARKS_JSON": jsonString,
                "SECRET": secret
            ])

        do {
            _ = try await webView.safelyEvaluateJavaScript(script, contentWorld: .defaultClient)
        } catch {
            DLog("Error showing mark annotations: \(error)")
        }
    }

    func jsUpdatePositions(webView: iTermBrowserWebView) {
        let script = iTermBrowserTemplateLoader.loadTemplate(
            named: "update-mark-positions",
            type: "js",
            substitutions: [
                "SECRET": secret
            ])

        Task {
            do {
                try await safelyModifyDOM(in: webView) {
                    let result = try await webView.safelyEvaluateJavaScript(script,
                                                                      contentWorld: .defaultClient)
                    if let updates = result as? [[String: Any]] {
                        await processMarkPositionUpdates(updates: updates, webView: webView)
                    }
                }
            } catch {
                DLog("Error updating mark positions: \(error)")
            }
        }
    }
}

// MARK: - DB

@MainActor
private extension iTermBrowserNamedMarkManager {
    func dbAdd(name: String, markURL: URL) async throws {
        // Add to database
        guard let db = await BrowserDatabase.instance(for: user) else {
            throw iTermError("Failed to get database instance")
        }

        let guid = UUID().uuidString
        let success = await db.addNamedMark(guid: guid, url: markURL.absoluteString, name: name, text: "")
        DLog("Database add result: \(success) for mark '\(name)' with URL: \(markURL.absoluteString)")

        if !success {
            throw iTermError("Failed to save named mark to database")
        }
    }

    func dbLoad() async -> [iTermBrowserNamedMark]? {
        guard let db = await BrowserDatabase.instance(for: user) else {
            return nil
        }
        let dbMarks = await db.getPaginatedNamedMarksQuery(urlToSortFirst: nil,
                                                           offset: 0,
                                                           limit: 1_000_000)

        let marks = dbMarks.compactMap { dbMark -> iTermBrowserNamedMark? in
            guard let url = URL(string: dbMark.url) else {
                return nil
            }
            return iTermBrowserNamedMark(
                url: url,
                name: dbMark.name,
                sort: Int(dbMark.sort ?? 0),
                guid: dbMark.guid
            )
        }
        return marks
    }

    func dbRename(guid: String, newName: String) async throws {
        guard let db = await BrowserDatabase.instance(for: user) else {
            throw iTermError("No database")
        }

        let success = await db.updateNamedMarkName(guid: guid,
                                                   name: newName)
        if !success {
            throw iTermError("updateNamedMarkName failed")
        }
    }

    func dbRemove(guid: String) async throws {
        guard let db = await BrowserDatabase.instance(for: user) else {
            throw iTermError("No database")
        }
        let success = await db.removeNamedMark(guid: guid)
        if !success {
            throw iTermError("removeNamedMark failed")
        }
    }

    func dbFetch(forURL currentURL: URL) async throws -> [BrowserNamedMarks] {
        guard let db = await BrowserDatabase.instance(for: user) else {
            throw iTermError("No database")
        }

        return await db.getNamedMarksForUrl(currentURL.absoluteString)
    }
}

extension URL {
    func namedMark(location: iTermBrowserNamedMarkManager.Location) -> URL? {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.fragment = location.fragment
        return components?.url
    }
}
