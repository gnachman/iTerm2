//
//  iTermBrowserFindManager.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import WebKit

@MainActor
protocol iTermBrowserFindManagerDelegate: AnyObject {
    func browserFindManager(_ manager: iTermBrowserFindManager, didUpdateResult result: iTermBrowserFindResultBundle)
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
    override var description: String {
        return "<iTermBrowserFindResult: \(it_addressString) index=\(index) id=\(encodedMatchID) matched=\(matchedText ?? "") before=\(contextBefore ?? "") after=\(contextAfter ?? "")>"
    }
    @objc let index: Int
    @objc let matchIdentifier: [String: Any]?
    @objc let matchedText: String?
    @objc let contextBefore: String?
    @objc let contextAfter: String?

    private var encodedMatchID: String {
        if let data = try? JSONSerialization.data(withJSONObject: matchIdentifier ?? [:]) {
            return data.lossyString
        }
        return "(nil)"
    }
    init(index: Int,
         matchIdentifier: [String: Any]?,
         matchedText: String?,
         contextBefore: String?,
         contextAfter: String?) {
        self.index = index
        self.matchIdentifier = matchIdentifier
        self.matchedText = matchedText
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
    }
}

@MainActor
class iTermBrowserFindResultBundle {
    @objc let matchFound: Bool
    @objc let results: [iTermBrowserFindResult]

    init(matchFound: Bool,
         results: [iTermBrowserFindResult]) {
        self.matchFound = matchFound
        self.results = results
    }
}

@objc(iTermBrowserFindManager)
@MainActor
class iTermBrowserFindManager: NSObject {
    static let messageHandlerName = "iTermCustomFind"
    static let graphDiscoveryMessageHandlerName = "iTermGraphDiscovery"
    private var ignoreForceSearch = 0
    private(set) var findInProgress = false

    var delegate: iTermBrowserFindManagerDelegate? {
        set {
            defaultState.delegate = newValue
        }
        get {
            defaultState.delegate
        }
    }

    @MainActor
    fileprivate class Shared: NSObject {
        let secret: String
        weak var webView: WKWebView!
        var isJavaScriptInjected = false

        init(secret: String) {
            self.secret = secret
        }
    }

    @MainActor
    fileprivate class State {
        var instanceID: String?
        weak var delegate: iTermBrowserFindManagerDelegate?
        var currentSearchTerm: String?
        // Are searching for or showing search results?
        var isSearchActive = false
        var findMode: iTermBrowserFindMode = .caseSensitive
        var stream: iTermBrowserGlobalSearchResultStream?

        // Incremental search state
        var totalMatches: Int = 0
        var currentMatchIndex: Int = 0
        var searchProgress: Double = 0.0
        // Did the last performed search finish?
        var searchComplete: Bool = false
        private var generation = 0
        private var mutex = AsyncMutex()

        init(instanceID: String?) {
            self.instanceID = instanceID
        }

        private func resetSearchState(active: Bool = true) {
            totalMatches = 0
            currentMatchIndex = 0
            searchProgress = 0.0
            searchComplete = false
            isSearchActive = active
        }

        @MainActor
        func handleResultsUpdate(_ data: [String: Any], findManager: iTermBrowserFindManager) {
            DLog("handleResultsUpdate:\n\(data)")
            let matchIdentifiers = data["matchIdentifiers"] as? [[String: Any]]
            guard let matchIdentifiers else {
                // Ignore partial updates, which do not include match IDs.
                return
            }
            let totalMatches = data["totalMatches"] as? Int ?? 0
            let currentMatch = data["currentMatch"] as? Int ?? 0
            let contexts = data["contexts"] as? [[String: String]]

            // Update internal state
            self.totalMatches = totalMatches
            self.currentMatchIndex = currentMatch

            // Mark search as complete when we get results
            if !searchComplete {
                searchComplete = true
                searchProgress = 1.0
            }

            let contextTuples: [(String, String)]? = contexts?.compactMap { (dict: [String: String]) -> (String, String)? in
                if let before = dict["contextBefore"], let after = dict["contextAfter"] {
                    (before, after)
                } else {
                    nil
                }
            }
            let results = (0..<matchIdentifiers.count).map { i in
                let matchIdentifier = matchIdentifiers[i]
                let context = contextTuples?[i]
                let matchedText = matchIdentifier["text"] as? String
                return iTermBrowserFindResult(index: i,
                                              matchIdentifier: matchIdentifier,
                                              matchedText: matchedText,
                                              contextBefore: context?.0,
                                              contextAfter: context?.1)
            }
            let result = iTermBrowserFindResultBundle(
                matchFound: totalMatches > 0,
                results: results)

            if let stream {
                if !stream.done {
                    stream.done = true
                    stream.push(results: results)
                }
            } else {
                delegate?.browserFindManager(findManager, didUpdateResult: result)
            }
        }

        struct InvalidResponseError: Error { }
        struct NoWebViewError: Error { }

        private func json(_ obj: Any?) -> String {
            guard let obj else {
                return "null"
            }
            return try! JSONSerialization.data(withJSONObject: obj, options: [.fragmentsAllowed]).lossyString
        }
        func matchBounds(for identifier: [String: Any], sharedState: Shared) async throws -> NSRect {
            guard let webView = sharedState.webView else {
                throw NoWebViewError()
            }
            let script = """
            return await window.iTermCustomFind.getMatchBoundsInEngine({sessionSecret: '\(sharedState.secret)',
                                                                        instanceId: \(json(self.instanceID)),
                                                                        identifier: \(json(identifier) ) }); 
            """
            do {
                let raw = try await webView.callAsyncJavaScript(script, contentWorld: .defaultClient)
                guard let dict = raw as? [String: Double] else {
                    DLog("Bad result: \(String(describing: raw)) in \(script)")
                    throw InvalidResponseError()
                }
                guard let x = dict["x"],
                      let y = dict["y"],
                      let width = dict["width"],
                      let height = dict["height"] else {
                    throw InvalidResponseError()
                }
                return NSRect(x: x, y: y, width: width, height: height)
            } catch {
                DLog("\(error)")
                throw error
            }
        }

        @discardableResult
        func executeJavaScript(command: [String: Any], sharedState: Shared) async throws -> Any? {
            guard sharedState.isJavaScriptInjected,
                  let webView = sharedState.webView else {
                return nil
            }

            var temp = command
            if let instanceID {
                temp["instanceId"] = instanceID
            }
            temp["sessionSecret"] = sharedState.secret
            let jsonData = try JSONSerialization.data(withJSONObject: temp)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            let script = "window.iTermCustomFind &&await  window.iTermCustomFind.handleCommand(\(jsonString))"

            do {
                return try await webView.callAsyncJavaScript(script, contentWorld: .defaultClient)
            } catch {
                DLog("\(error) while executing \(script)")
                throw error
            }
        }

        func reveal(_ identifier: [String: Any], sharedState: Shared) async throws {
            do {
                try await executeJavaScript(command: ["action": "reveal",
                                                      "identifier": identifier ],
                                            sharedState: sharedState)
            } catch {
                DLog("\(error)")
            }
        }

        func startFind(_ searchTerm: String,
                       mode: iTermBrowserFindMode,
                       contextLength: Int,
                       sharedState: Shared,
                       findManager: iTermBrowserFindManager) {
            guard !searchTerm.isEmpty else {
                Task {
                    try? await clearFind(sharedState: sharedState, findManager: findManager)
                }
                return
            }

            currentSearchTerm = searchTerm
            findMode = mode
            resetSearchState()
            generation = generation + 1
            let thisGeneration = generation

            Task {
                try await mutex.sync {
                    if generation != thisGeneration {
                        DLog("Not searching for \(searchTerm) because there is a more recent term")
                        return
                    }
                    DLog("Begin search for \(searchTerm)")
                    try await executeJavaScript(command: [
                        "action": "startFind",
                        "searchTerm": searchTerm,
                        "contextLength": contextLength,
                        "searchMode": mode.rawValue
                    ], sharedState: sharedState)
                    DLog("Completed search for \(searchTerm)")
                }
            }
        }

        func findNext(sharedState: Shared) {
            guard isSearchActive else { return }
            Task {
                try await executeJavaScript(command: ["action": "findNext"], sharedState: sharedState)
            }
        }

        func findPrevious(sharedState: Shared) {
            guard isSearchActive else {
                return
            }
            Task {
                try await executeJavaScript(command: ["action": "findPrevious"],
                                            sharedState: sharedState)
            }
        }

        func clearFind(sharedState: Shared, findManager: iTermBrowserFindManager) async throws {
            try await executeJavaScript(command: ["action": "clearFind"],
                                        sharedState: sharedState)

            currentSearchTerm = nil
            resetSearchState(active: false)

            // Notify delegate that find was cleared
            let result = iTermBrowserFindResultBundle(matchFound: false,
                                                      results: [])
            delegate?.browserFindManager(findManager, didUpdateResult: result)
        }

        func hideResults(sharedState: Shared, findManager: iTermBrowserFindManager) async throws {
            try await executeJavaScript(command: ["action": "hideResults"],
                                        sharedState: sharedState)
        }

        func showResults(sharedState: Shared, findManager: iTermBrowserFindManager) async throws {
            try await executeJavaScript(command: ["action": "showResults"],
                                        sharedState: sharedState)
        }
    }

    fileprivate var defaultState = State(instanceID: "main_" + UUID().uuidString)
    fileprivate var globalState = State(instanceID: "global_" + UUID().uuidString)
    private var sharedState: Shared!
    private var lastSearchWasGlobal = false

    static func create() -> iTermBrowserFindManager? {
        guard let secret = String.makeSecureHexString() else {
            return nil
        }
        return iTermBrowserFindManager(secret: secret)
    }

    private init(secret: String) {
        super.init()
        self.sharedState = Shared(secret: secret)
    }

    var javascript: String {
        sharedState.isJavaScriptInjected = true
        let script = iTermBrowserTemplateLoader.loadTemplate(
            named: "custom-find",
            type: "js",
            substitutions: ["SECRET": sharedState.secret,
                            "SCROLL_BEHAVIOR": "smooth",
                            "TEST_FUNCTIONS": "",
                            "TEST_IMPLS": "",
                            "TEST_FREEZE": "" ])
        return script
    }

    var webView: WKWebView? {
        didSet {
            sharedState.webView = webView
        }
    }
    
    // MARK: - Public Interface

    func convertVisibleSearchResultsToContentNavigationShortcuts(action: iTermContentNavigationAction,
                                                                 clearOnEnd: Bool) {
        hideGlobalSearchResultsIfNeeded()
        Task {
            do {
                let state = defaultState
                let selectionAction = switch action {
                case .open:
                    "open"
                case .copy:
                    "copy"
                @unknown default:
                    it_fatalError()
                }
                try await state.executeJavaScript(command: ["action": "startNavigationShortcuts",
                                                            "selectionAction": selectionAction],
                                                  sharedState: sharedState)
                DLog("Started navigation shortcuts")
            } catch {
                DLog("Failed to start navigation shortcuts: \(error)")
            }
        }
    }

    func clearNavigationShortcuts() {
        Task {
            do {
                let state = defaultState
                try await state.executeJavaScript(command: ["action": "clearNavigationShortcuts"], 
                                                  sharedState: sharedState)
                DLog("Cleared navigation shortcuts")
            } catch {
                DLog("Failed to clear navigation shortcuts: \(error)")
            }
        }
    }

    func executeGlobalSearch(query: String, mode: iTermBrowserFindMode) -> iTermBrowserGlobalSearchResultStream {
        let stream = iTermBrowserGlobalSearchResultStream()
        Task {
            if !lastSearchWasGlobal {
                try? await defaultState.clearFind(sharedState: sharedState, findManager: self)
            }
            lastSearchWasGlobal = true
            do {
                // The user script won't be installed until documentStart. If it isn't there now it may never arrive.
                let myFunction = try await sharedState.webView?.evaluateJavaScript("typeof window.iTermCustomFind", contentWorld: .defaultClient)
                if myFunction as? String == "undefined" {
                    stream.done = true
                    return
                }
                try await globalState.clearFind(sharedState: sharedState, findManager: self)
                globalState.stream = stream
                globalState.startFind(query, mode: mode, contextLength: 40, sharedState: sharedState, findManager: self)
            } catch {
                DLog("\(error)")
            }
        }
        return stream
    }

    func reveal(globalFindResultWithIdentifier identifier: [String: Any]) async throws -> NSRect {
        if !lastSearchWasGlobal {
            try await globalState.showResults(sharedState: sharedState, findManager: self)
        }
        // Scroll to show findResult, highlight it, and rect in screen coords of the text.
        try await globalState.reveal(identifier, sharedState: sharedState)
        if let webView = sharedState.webView {
            await webView.waitForScrollingToComplete()
        }
        return try await globalState.matchBounds(for: identifier,
                                                 sharedState: sharedState)

    }

    private func hideGlobalSearchResultsIfNeeded() {
        if lastSearchWasGlobal {
            Task {
                try? await globalState.hideResults(sharedState: sharedState, findManager: self)
            }
            lastSearchWasGlobal = false
        }
    }

    func withoutForceSearch(_ closure: () -> ()) {
        ignoreForceSearch += 1
        defer {
            ignoreForceSearch -= 1
        }
        closure()
    }

    func startFind(_ searchTerm: String, mode: iTermBrowserFindMode, force: Bool) {
        hideGlobalSearchResultsIfNeeded()
        if searchTerm == defaultState.currentSearchTerm && !(force && ignoreForceSearch == 0) {
            DLog("Search query is unchanged and search is not forced. Do nothing.")
            return
        }
        findInProgress = true
        defaultState.startFind(searchTerm, mode: mode, contextLength: 0, sharedState: sharedState, findManager: self)
    }

    func findNext() {
        hideGlobalSearchResultsIfNeeded()
        defaultState.findNext(sharedState: sharedState)
    }

    func findPrevious() {
        hideGlobalSearchResultsIfNeeded()
        defaultState.findPrevious(sharedState: sharedState)
    }

    func clearFind() {
        Task {
            do {
                try await defaultState.clearFind(sharedState: sharedState, findManager: self)
            } catch {
                DLog("\(error)")
            }
        }
    }

    var hasActiveSearch: Bool {
        return defaultState.isSearchActive && defaultState.currentSearchTerm != nil
    }
    
    var activeSearchTerm: String? {
        return defaultState.isSearchActive ? defaultState.currentSearchTerm : nil
    }
    
    // MARK: - Incremental Search Support
    
    var numberOfSearchResults: Int {
        return defaultState.totalMatches
    }
    
    var currentIndex: Int {
        return defaultState.currentMatchIndex
    }
    

    func continueFind(progress: UnsafeMutablePointer<Double>, range: NSRangePointer) -> Bool {
        hideGlobalSearchResultsIfNeeded()
        guard defaultState.isSearchActive else {
            progress.pointee = 1.0
            range.pointee = NSRange(location: 100, length: 100)
            findInProgress = false
            return false
        }
        
        // Update progress based on search state
        progress.pointee = defaultState.searchProgress

        // For browser, range represents search progress as percentage
        // location = current progress (0-100), length = total (100)
        let progressPercent = Int(defaultState.searchProgress * 100)
        range.pointee = NSRange(location: progressPercent, length: 100)
        
        // If search is complete, no more work to do
        if defaultState.searchComplete {
            progress.pointee = 1.0
            range.pointee = NSRange(location: 100, length: 100)
            findInProgress = false
            return false
        }

        return true
    }
    
    func resetFindCursor() {
        clearFind()
    }

    func handleMessage(webView: WKWebView, message: WKScriptMessage) {
        if message.name == Self.graphDiscoveryMessageHandlerName {
            handleGraphDiscoveryMessage(webView: webView, message: message)
        } else {
            handleFindMessage(webView: webView, message: message)
        }
    }

    private func handleFindMessage(webView: WKWebView, message: WKScriptMessage) {
        guard message.name == "iTermCustomFind",
              let body = message.body as? [String: Any],
              let sessionSecret = body["sessionSecret"] as? String,
              sessionSecret == sharedState.secret,
              let action = body["action"] as? String else {
            return
        }
        
        if action == "resultsUpdated" || action == "currentChanged",
           let data = body["data"] as? [String: Any] {
            handleResultsUpdate(data)
        }
    }
    
    private func handleResultsUpdate(_ data: [String: Any]) {
        if data["instanceId"] as? String == globalState.instanceID {
            globalState.handleResultsUpdate(data, findManager: self)
        } else {
            defaultState.handleResultsUpdate(data, findManager: self)
        }
    }
}

@objc
@MainActor
class iTermBrowserGlobalSearchResultStream: NSObject {
    @objc
    private(set) var results = [iTermBrowserFindResult]()
    @objc
    fileprivate(set) var done = false {
        didSet {
            DLog("\(ObjectIdentifier(self).debugDescription) Set done=\(done)")
        }
    }

    override init() {
        super.init()
        DLog("Create \(ObjectIdentifier(self).debugDescription) from:\n\(Thread.callStackSymbols)")
    }

    fileprivate func push(results: [iTermBrowserFindResult]) {
        DLog("\(ObjectIdentifier(self).debugDescription) Add \(results.count) results: \(results)")
        self.results.append(contentsOf: results)
    }

    @objc
    func consume() -> [iTermBrowserFindResult] {
        defer {
            results = []
        }
        DLog("\(ObjectIdentifier(self).debugDescription) Consumed \(results.count) items. done=\(done)")
        return results
    }
}

extension WKWebView {
    func waitForScrollingToComplete() async {
        // Poll until the current match position is stable
        let checkScript = """
        (() => {
            const current = document.querySelector('.iterm-find-highlight-current');
            if (!current) return true; // No current match, consider complete
            
            const rect = current.getBoundingClientRect();
            const key = '_lastMatchPos';
            
            if (!window[key] || 
                Math.abs(window[key].top - rect.top) > 1 || 
                Math.abs(window[key].left - rect.left) > 1) {
                window[key] = { top: rect.top, left: rect.left };
                return false; // Still moving
            }
            
            return true; // Position stable
        })()
        """
        
        let maxIterations = 5
        for _ in 0..<maxIterations {
            do {
                if let isComplete = try await evaluateJavaScript(checkScript, contentWorld: .defaultClient) as? Bool,
                   isComplete {
                    // Scrolling is complete
                    return
                }
            } catch {
                // If evaluation fails, assume scrolling is complete
                DLog("Error checking scroll completion: \(error)")
                return
            }
            
            // Wait 100ms before checking again
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        // Timeout after 500ms - assume scrolling is complete
        DLog("Scroll completion check timed out after 500ms")
    }
}

// MARK: - Graph discovery
@MainActor
extension iTermBrowserFindManager {
    private func handleGraphDiscoveryMessage(webView: WKWebView, message: WKScriptMessage) {
        DLog("[IFD] NATIVE - got a message: \(message.body)")
        if let body = message.body as? [String: Any],
           let type = body["type"] as? String,
           type == "DISCOVERY_COMPLETE",
           let graph = body["graph"] as? [String: Any] {

            DLog("[IFD] NATIVE - iframe graph discovery complete:")
            processGraphNode(graph, indent: 0)
        }
    }

    private func processGraphNode(_ node: [String: Any], indent: Int) {
        let spacing = String(repeating: "  ", count: indent)

        if let frameId = node["frameId"] as? String {
            DLog("\(spacing)Frame ID: \(frameId)")
        }

        if let error = node["error"] as? String {
            DLog("\(spacing)  Error: \(error)")
        }

        if let children = node["children"] as? [[String: Any]] {
            for child in children {
                processGraphNode(child, indent: indent + 1)
            }
        }
    }
}
