//
//  iTermBrowserPageSaver.swift
//  iTerm2
//
//  Created by Claude on 6/23/25.
//

import Foundation
import WebKit

@available(macOS 11.0, *)
class iTermBrowserPageSaver {
    private let webView: WKWebView
    private let baseURL: URL
    private var downloadedResources: [String: String] = [:]
    private var resourcesFolder: URL!
    
    init(webView: WKWebView, baseURL: URL) {
        self.webView = webView
        self.baseURL = baseURL
    }
    
    func savePageWithResources(to folderURL: URL) async throws {
        // Create main folder and resources subfolder
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        resourcesFolder = folderURL.appendingPathComponent("resources")
        try FileManager.default.createDirectory(at: resourcesFolder, withIntermediateDirectories: true)

        // Extract all resource URLs using JavaScript
        let resourceURLs = await extractResourceURLs()
        
        // Download all resources
        for urlString in resourceURLs {
            await downloadResource(urlString)
        }
        
        // Add rewritten URLs as custom data attributes (doesn't break the page)
        await addSavedResourceAttributes()
        
        // Get HTML with the custom attributes and convert them to real attributes
        let processedHTML = await getHTMLWithSavedAttributes()
        guard let processedHTML = processedHTML else {
            throw PageSaveError.failedToGetHTML
        }
        
        // Save the main HTML file
        let htmlFile = folderURL.appendingPathComponent("index.html")
        try processedHTML.write(to: htmlFile, atomically: true, encoding: .utf8)
        
        DLog("Page saved successfully to \(folderURL.path)")
    }
    
    @MainActor
    private func extractResourceURLs() async -> [String] {
        let script = iTermBrowserTemplateLoader.loadTemplate(named: "extract-resources", type: "js")
        
        do {
            let result = try await webView.evaluateJavaScript(script)
            let urls = (result as? [String]) ?? []
            DLog("Extracted \(urls.count) resource URLs")
            return urls
        } catch {
            DLog("Error extracting resource URLs: \(error)")
            return []
        }
    }
    
    @MainActor
    private func addSavedResourceAttributes() async {
        let scriptTemplate = iTermBrowserTemplateLoader.loadTemplate(named: "add-saved-attributes", type: "js")
        
        // Build mapping array for JavaScript
        let mappingEntries = downloadedResources.map { (original, local) in
            "[\(original.jsonEscaped), \(local.jsonEscaped)]"
        }.joined(separator: ", ")
        
        // Replace placeholder with actual mapping data
        let script = scriptTemplate.replacingOccurrences(
            of: "URL_MAPPING_PLACEHOLDER", 
            with: "[\(mappingEntries)]"
        )
        
        do {
            _ = try await webView.evaluateJavaScript(script)
            DLog("Added saved resource attributes")
        } catch {
            DLog("Error adding saved resource attributes: \(error)")
        }
    }
    
    @MainActor
    private func getHTMLWithSavedAttributes() async -> String? {
        // Apply all saved attributes to the actual DOM attributes, then get the HTML
        let applyScript = """
        (function() {
            // Apply saved src attributes
            document.querySelectorAll('[data-saved-src]').forEach(el => {
                el.setAttribute('src', el.getAttribute('data-saved-src'));
                el.removeAttribute('data-saved-src');
            });
            
            // Replace CSS link tags with style tags containing the CSS content
            document.querySelectorAll('link[rel="stylesheet"][data-saved-css-content]').forEach(link => {
                const cssContent = link.getAttribute('data-saved-css-content');
                const styleEl = document.createElement('style');
                styleEl.textContent = cssContent;
                link.parentNode.replaceChild(styleEl, link);
            });
            
            // Apply saved href attributes for non-CSS links
            document.querySelectorAll('[data-saved-href]').forEach(el => {
                el.setAttribute('href', el.getAttribute('data-saved-href'));
                el.removeAttribute('data-saved-href');
            });
            
            // Apply saved data attributes
            document.querySelectorAll('[data-saved-data]').forEach(el => {
                el.setAttribute('data', el.getAttribute('data-saved-data'));
                el.removeAttribute('data-saved-data');
            });
            
            // Apply saved styles
            document.querySelectorAll('[data-saved-style]').forEach(el => {
                el.setAttribute('style', el.getAttribute('data-saved-style'));
                el.removeAttribute('data-saved-style');
            });
            
            // Apply saved content to style tags
            document.querySelectorAll('style[data-saved-content]').forEach(styleEl => {
                styleEl.textContent = styleEl.getAttribute('data-saved-content');
                styleEl.removeAttribute('data-saved-content');
            });
            
            // Get the full document including DOCTYPE
            const doctype = document.doctype ? 
                '<!DOCTYPE ' + document.doctype.name + '>' : '';
            return doctype + document.documentElement.outerHTML;
        })();
        """
        
        do {
            let result = try await webView.evaluateJavaScript(applyScript)
            return result as? String
        } catch {
            DLog("Error getting HTML with saved attributes: \(error)")
            return nil
        }
    }
    
    @discardableResult
    private func downloadResource(_ urlString: String) async -> String? {
        // Check if we've already downloaded this resource
        if let cachedPath = downloadedResources[urlString] {
            return cachedPath
        }
        
        guard let resourceURL = URL(string: urlString) else {
            return nil
        }
        
        // Skip non-HTTP(S) URLs
        guard ["http", "https"].contains(resourceURL.scheme?.lowercased()) else {
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: resourceURL)
            
            // For CSS files, store the content directly instead of a file path
            let mimeType = response.mimeType
            if mimeType == "text/css" {
                if let cssContent = String(data: data, encoding: .utf8) {
                    // Rewrite URLs in CSS content to be relative to the base URL
                    let processedCSS = await rewriteCSSUrls(cssContent, baseURL: resourceURL)
                    downloadedResources[urlString] = processedCSS
                    DLog("Downloaded CSS content: \(urlString)")
                    return processedCSS
                }
            }
            
            // For other resources, save as files
            let filename = generateFilename(for: resourceURL, response: response)
            let localFile = resourcesFolder.appendingPathComponent(filename)
            
            // Save the file
            try data.write(to: localFile)
            
            // Store the relative path
            let relativePath = "resources/\(filename)"
            downloadedResources[urlString] = relativePath
            
            DLog("Downloaded resource: \(urlString) -> \(relativePath)")
            return relativePath
            
        } catch {
            DLog("Failed to download resource \(urlString): \(error)")
            return nil
        }
    }
    
    private func generateFilename(for url: URL, response: URLResponse?) -> String {
        var filename = url.lastPathComponent
        
        // If no filename, generate one based on URL path
        if filename.isEmpty || filename == "/" {
            let pathComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            filename = pathComponents.last ?? "resource"
        }
        
        // If no extension, try to determine from MIME type using the comprehensive mapping
        if !filename.contains("."), let mimeType = response?.mimeType {
            let fileExtension = extensionForMimeType(mimeType)
            filename += ".\(fileExtension)"
        }
        
        // Sanitize filename
        filename = sanitizeFilename(filename)
        
        // Ensure uniqueness
        var counter = 1
        let originalFilename = filename
        while FileManager.default.fileExists(atPath: resourcesFolder.appendingPathComponent(filename).path) {
            let nameWithoutExt = (originalFilename as NSString).deletingPathExtension
            let ext = (originalFilename as NSString).pathExtension
            filename = ext.isEmpty ? "\(nameWithoutExt)_\(counter)" : "\(nameWithoutExt)_\(counter).\(ext)"
            counter += 1
        }
        
        return filename
    }
    
    private func extensionForMimeType(_ mimeType: String) -> String {
        // Create reverse mapping from the comprehensive extensionToMime dictionary
        let mimeToExtension = Dictionary(uniqueKeysWithValues: extensionToMime.map { ($1, $0) })
        
        // Try exact match first
        if let fileExtension = mimeToExtension[mimeType.lowercased()] {
            return fileExtension
        }
        
        // Try without parameters (e.g., "text/html; charset=utf-8" -> "text/html")
        let cleanMimeType = mimeType.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? mimeType
        if let fileExtension = mimeToExtension[cleanMimeType.lowercased()] {
            return fileExtension
        }
        
        // Fallback to common types for major categories
        switch cleanMimeType.lowercased() {
        case let mime where mime.hasPrefix("image/"):
            return "img"
        case let mime where mime.hasPrefix("video/"):
            return "vid"
        case let mime where mime.hasPrefix("audio/"):
            return "aud"
        case let mime where mime.hasPrefix("text/"):
            return "txt"
        case let mime where mime.hasPrefix("application/"):
            return "bin"
        default:
            return "dat"
        }
    }
    
    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }
    
    private func rewriteCSSUrls(_ cssContent: String, baseURL: URL) async -> String {
        var rewrittenCSS = cssContent
        
        // Find all url() references in CSS
        let urlPattern = #"url\s*\(\s*['""]?([^'"")\s]+)['""]?\s*\)"#
        let regex = try! NSRegularExpression(pattern: urlPattern, options: [.caseInsensitive])
        let matches = regex.matches(in: cssContent, options: [], range: NSRange(location: 0, length: cssContent.count))
        
        // Process matches in reverse order to avoid index shifting
        for match in matches.reversed() {
            if let urlRange = Range(match.range(at: 1), in: cssContent) {
                let urlString = String(cssContent[urlRange])
                
                // Convert relative URLs to absolute URLs based on the CSS file's location
                if let absoluteURL = URL(string: urlString, relativeTo: baseURL) {
                    let absoluteURLString = absoluteURL.absoluteString
                    
                    // Download the referenced resource and get its local path
                    if let localPath = await downloadResource(absoluteURLString) {
                        // Replace the URL in the CSS
                        let fullMatchRange = Range(match.range(at: 0), in: cssContent)!
                        let originalMatch = String(cssContent[fullMatchRange])
                        let newURL = "url('\(localPath)')"
                        rewrittenCSS = rewrittenCSS.replacingOccurrences(of: originalMatch, with: newURL)
                    }
                }
            }
        }
        
        return rewrittenCSS
    }
}

extension String {
    var jsonEscaped: String {
        let data = try! JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8)!
    }
}

enum PageSaveError: LocalizedError {
    case failedToGetHTML
    case failedToCreateDirectory
    case failedToSaveFile
    
    var errorDescription: String? {
        switch self {
        case .failedToGetHTML:
            return "Failed to get page HTML content"
        case .failedToCreateDirectory:
            return "Failed to create save directory"
        case .failedToSaveFile:
            return "Failed to save file"
        }
    }
}
