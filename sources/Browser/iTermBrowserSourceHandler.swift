//
//  iTermBrowserSourceHandler.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import WebKit

@available(macOS 11.0, *)
class iTermBrowserSourceHandler: NSObject {
    static let sourceURL = URL(string: "iterm2-about:source")!
    
    private var pendingSourceHTML: String?
    
    func generateSourcePageHTML(for rawSource: String) -> String {
        // Escape HTML entities for display
        let escapedSource = rawSource
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        
        // Load template and substitute source
        return iTermBrowserTemplateLoader.loadTemplate(named: "view-source",
                                                      substitutions: ["SOURCE": escapedSource])
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
                                                                  substitutions: ["SOURCE": "No source available"])
        }
        
        let data = htmlContent.data(using: .utf8) ?? Data()
        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
}
