// BrowserExtensionURLSchemeHandler.swift
// Custom URL scheme handler for isolated extension origins

import Foundation
import WebKit

/// URL scheme handler that provides isolated origins for extension background scripts
/// Each extension gets a unique origin: extension://<extensionId>/
@MainActor
public class BrowserExtensionURLSchemeHandler: NSObject, WKURLSchemeHandler {
    
    /// The URL scheme we handle
    public static let scheme = "extension"
    
    /// Map of extension ID to their background script resources
    private var extensionResources: [String: BackgroundScriptResource] = [:]
    
    /// Register a background script resource for an extension
    /// - Parameters:
    ///   - resource: The background script resource
    ///   - extensionId: The extension ID
    public func registerBackgroundScript(_ resource: BackgroundScriptResource, for extensionId: String) {
        extensionResources[extensionId] = resource
    }
    
    /// Unregister background script resource for an extension
    /// - Parameter extensionId: The extension ID
    public func unregisterBackgroundScript(for extensionId: String) {
        extensionResources.removeValue(forKey: extensionId)
    }
    
    /// Generate URL for extension's background page
    /// - Parameter extensionId: The extension ID
    /// - Returns: URL for the background page
    public static func backgroundPageURL(for extensionId: String) -> URL {
        return URL(string: "\(scheme)://\(extensionId)/background.html")!
    }
    
    // MARK: - WKURLSchemeHandler
    
    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == Self.scheme,
              let host = url.host else {
            urlSchemeTask.didFailWithError(NSError(
                domain: "BrowserExtensionURLSchemeHandler",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid extension URL: \(urlSchemeTask.request.url?.absoluteString ?? "nil")"]
            ))
            return
        }
        
        let extensionId = host
        let path = url.path
        
        // Handle background.html requests
        if path == "/background.html" {
            handleBackgroundPageRequest(for: extensionId, task: urlSchemeTask)
        } else {
            // Unknown path
            urlSchemeTask.didFailWithError(NSError(
                domain: "BrowserExtensionURLSchemeHandler", 
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unknown path: \(path)"]
            ))
        }
    }
    
    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Nothing to stop - we respond immediately
    }
    
    // MARK: - Private Methods
    
    private func handleBackgroundPageRequest(for extensionId: String, task: WKURLSchemeTask) {
        guard extensionResources[extensionId] != nil else {
            task.didFailWithError(NSError(
                domain: "BrowserExtensionURLSchemeHandler",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "No background script registered for extension: \(extensionId)"]
            ))
            return
        }
        
        // Create simple HTML page - background script is injected via user script in .defaultClient world
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>Background Script - \(extensionId)</title>
        </head>
        <body>
            <!-- Background script content is injected via WKUserScript in .defaultClient world -->
        </body>
        </html>
        """
        
        // Create response
        let data = html.data(using: .utf8)!
        let response = URLResponse(
            url: task.request.url!,
            mimeType: "text/html",
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        
        // Send response
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }
}