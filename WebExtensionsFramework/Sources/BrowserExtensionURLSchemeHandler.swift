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
    private var extensionResources: [ExtensionID: BackgroundScriptResource] = [:]
    
    /// Logger for debugging and error reporting
    private let logger: BrowserExtensionLogger
    
    /// Initialize the URL scheme handler
    /// - Parameter logger: Logger for debugging and error reporting
    public init(logger: BrowserExtensionLogger) {
        self.logger = logger
        super.init()
    }
    
    /// Register a background script resource for an extension
    /// - Parameters:
    ///   - resource: The background script resource
    ///   - extensionId: The extension ID
    public func registerBackgroundScript(_ resource: BackgroundScriptResource, for extensionId: ExtensionID) {
        logger.debug("Registering background script for extension: \(extensionId)")
        extensionResources[extensionId] = resource
    }
    
    /// Unregister background script resource for an extension
    /// - Parameter extensionId: The extension ID
    public func unregisterBackgroundScript(for extensionId: ExtensionID) {
        logger.debug("Unregistering background script for extension: \(extensionId)")
        extensionResources.removeValue(forKey: extensionId)
    }
    
    /// Generate URL for extension's background page
    /// - Parameter extensionId: The extension ID
    /// - Returns: URL for the background page
    public static func backgroundPageURL(for extensionId: ExtensionID) -> URL {
        return URL(string: "\(scheme)://\(extensionId.stringValue)/background.html")!
    }
    
    // MARK: - WKURLSchemeHandler
    
    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        logger.inContext("Handle URL scheme request for \(urlSchemeTask.request.url?.absoluteString ?? "nil")") {
            guard let url = urlSchemeTask.request.url,
                  url.scheme == Self.scheme,
                  let host = url.host else {
                logger.error("Invalid extension URL: \(urlSchemeTask.request.url?.absoluteString ?? "nil")")
                urlSchemeTask.didFailWithError(NSError(
                    domain: "BrowserExtensionURLSchemeHandler",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid extension URL: \(urlSchemeTask.request.url?.absoluteString ?? "nil")"]
                ))
                return
            }
            
            guard let extensionId = ExtensionID(host) else {
                logger.error("Invalid extension ID: \(host)")
                urlSchemeTask.didFailWithError(NSError(
                    domain: "BrowserExtensionURLSchemeHandler",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid extension ID: \(host)"]
                ))
                return
            }
            
            let path = url.path
            logger.debug("Handling request for extension \(extensionId), path: \(path)")
            
            // Handle background.html requests
            if path == "/background.html" {
                handleBackgroundPageRequest(for: extensionId, task: urlSchemeTask)
            } else {
                logger.error("Unknown path requested: \(path)")
                // Unknown path
                urlSchemeTask.didFailWithError(NSError(
                    domain: "BrowserExtensionURLSchemeHandler", 
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Unknown path: \(path)"]
                ))
            }
        }
    }
    
    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Nothing to stop - we respond immediately
    }
    
    // MARK: - Private Methods
    
    private func handleBackgroundPageRequest(for extensionId: ExtensionID, task: WKURLSchemeTask) {
        guard extensionResources[extensionId] != nil else {
            logger.error("No background script registered for extension: \(extensionId)")
            task.didFailWithError(NSError(
                domain: "BrowserExtensionURLSchemeHandler",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "No background script registered for extension: \(extensionId)"]
            ))
            return
        }
        
        logger.debug("Serving background page for extension: \(extensionId)")
        
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
        
        // Create response with CSP headers to prevent runtime injection
        let data = html.data(using: .utf8)!
        let headers = [
            "Content-Security-Policy": "default-src 'none'; script-src 'self'; connect-src https:;",
            "Content-Type": "text/html; charset=utf-8"
        ]
        let response = HTTPURLResponse(
            url: task.request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        
        // Send response
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
        logger.debug("Successfully served background page for extension: \(extensionId)")
    }
}