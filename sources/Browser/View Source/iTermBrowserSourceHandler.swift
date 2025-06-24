//
//  iTermBrowserSourceHandler.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import WebKit

@available(macOS 11.0, *)
class iTermBrowserSourceHandler: NSObject, iTermBrowserPageHandler {
    static let sourceURL = URL(string: "\(iTermBrowserSchemes.about):source")!

    private var pendingSourceHTML: String?
    
    func generateSourcePageHTML(for rawSource: String, url: URL) -> String {
        // Escape HTML entities for safe display but preserve whitespace characters
        let escapedSource = rawSource
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\n", with: "<br/>")
            .replacingOccurrences(of: "  ", with: "&nbsp;&nbsp;")
            // Keep tabs as tabs - CSS will handle the display with tab-size
        
        // Load template and substitute source
        return iTermBrowserTemplateLoader.loadTemplate(named: "view-source",
                                                       type: "html",
                                                      substitutions: ["SOURCE": escapedSource,
                                                                      "URL": url.absoluteString.escapedForHTML])
    }
    
    func setPendingSourceHTML(_ html: String) {
        pendingSourceHTML = html
    }
    
    func clearPendingSource() {
        pendingSourceHTML = nil
    }
    
    func start(urlSchemeTask: WKURLSchemeTask, url: URL) {
        guard url == Self.sourceURL else {
            urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserSourceHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid source URL"]))
            return
        }
        
        let htmlContent: String
        if let pendingHTML = pendingSourceHTML {
            htmlContent = pendingHTML
            pendingSourceHTML = nil // Clear after use
        } else {
            // Fallback content if no source is pending
            htmlContent = iTermBrowserTemplateLoader.loadTemplate(named: "view-source",
                                                                  type: "html",
                                                                  substitutions: ["SOURCE": "No source available"])
        }
        
        let data = htmlContent.data(using: .utf8) ?? Data()
        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    
    // MARK: - iTermBrowserPageHandler Protocol
    
    func injectJavaScript(into webView: WKWebView) {
        // Source pages don't need JavaScript injection
    }
    
    func resetState() {
        clearPendingSource()
    }
}
