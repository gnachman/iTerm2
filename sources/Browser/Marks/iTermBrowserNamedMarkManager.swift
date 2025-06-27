//
//  iTermBrowserNamedMarkManager.swift
//  iTerm2
//
//  Created by George Nachman on 6/27/25.
//

import WebKit

extension URL {
    var withoutFragment: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.fragment = nil
        return components.url
    }
}

@available(macOS 11, *)
class iTermBrowserNamedMark: NSObject, iTermGenericNamedMarkReading {
    let url: URL
    let name: String?
    let namedMarkSort: Int
    var guid: String

    init(url: URL, name: String, sort: Int, guid: String) {
        self.url = url
        self.name = name
        self.namedMarkSort = sort
        self.guid = guid

        super.init()
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case name
        case sort
        case guid
    }
    var dictionaryValue: [String: Any] {
        return [CodingKeys.url.rawValue: url.absoluteString,
                CodingKeys.name.rawValue: name!,
                CodingKeys.sort.rawValue: namedMarkSort,
                CodingKeys.guid.rawValue: guid]
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

        super.init()
    }
}

@available(macOS 11, *)
class iTermBrowserNamedMarkManager {
    private var _namedMarks = [iTermBrowserNamedMark]()
    private var pendingNavigationMark: iTermBrowserNamedMark?

    private var nextSort = 0
}

@available(macOS 11, *)
extension iTermBrowserNamedMarkManager {
    var namedMarks: [iTermBrowserNamedMark] {
        get {
            _namedMarks
        }
        set {
            _namedMarks = newValue
            nextSort = _namedMarks.map { $0.namedMarkSort }.max() ?? 0
        }
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
            let fragment = "iterm-mark:xpath=\(xpath)&offsetY=\(offsetY)&scrollY=\(scrollY)"
            components?.fragment = fragment
            
            guard let markURL = components?.url else { return }
            
            // Create and store the named mark
            let mark = iTermBrowserNamedMark(url: markURL, name: name, sort: nextSort, guid: UUID().uuidString)
            nextSort += 1
            
            // Add the new mark
            self.namedMarks.append(mark)
            
            // Refresh annotations to show the new mark
            reloadAnnotations(webView: webView)
        } catch {
            DLog("\(error)")
            throw error
        }
    }
    
    func rename(_ mark: iTermBrowserNamedMark, to newName: String, webView: WKWebView) {
        if let i = namedMarks.firstIndex(where: { $0.guid == mark.guid }) {
            namedMarks[i] = iTermBrowserNamedMark(url: mark.url,
                                                  name: newName,
                                                  sort: mark.namedMarkSort,
                                                  guid: mark.guid)
            
            // Refresh annotations to show the updated name
            reloadAnnotations(webView: webView)
        }
    }

    func remove(_ mark: iTermBrowserNamedMark) {
        namedMarks.removeAll {
            $0.guid == mark.guid
        }
    }
    
    func remove(_ mark: iTermBrowserNamedMark, webView: WKWebView) {
        namedMarks.removeAll {
            $0.guid == mark.guid
        }
        
        // Refresh annotations after removing the mark
        reloadAnnotations(webView: webView)
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
            // Show annotations for any marks on this page
            reloadAnnotations(webView: webView)
        } else {
            DLog("Navigation failed for \(webView.url.d) with pending mark \((pendingNavigationMark?.guid).d)")
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
        
        DLog("Parsed parameters - xpath: \(xpath), offsetY: \(offsetY), scrollY: \(scrollY)")
        
        let script = iTermBrowserTemplateLoader.loadTemplate(
            named: "navigate-to-named-mark",
            type: "js",
            substitutions: [
                "XPATH": xpath,
                "OFFSET_Y": offsetY,
                "SCROLL_Y": scrollY
            ]
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
        
        // Find marks for this page (ignoring fragment)
        let marksForPage = namedMarks.filter { mark in
            mark.url.withoutFragment == currentURL.withoutFragment
        }
        
        guard !marksForPage.isEmpty else { return }
        
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
                "offsetY": offsetY
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
                    "MARKS_JSON": jsonString
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

