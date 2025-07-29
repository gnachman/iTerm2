//
//  iTermBrowserPageSaver.swift
//  iTerm2
//
//  Created by Claude on 6/23/25.
//

import Foundation
import WebKit

@MainActor
struct SSHLocation {
    var description: String {
        return "\(endpoint.sshIdentity.displayName):\(path)"
    }
    var path: String
    var endpoint: SSHEndpoint

    func appendingPathComponent(_ component: String) -> SSHLocation {
        return SSHLocation(path: path.appending(pathComponent: component), endpoint: endpoint)
    }
}

extension SSHLocation {
    init?(_ item: iTermSavePanelItem) {
        path = item.filename
        if item.host.isLocalhost {
            self.endpoint = LocalhostEndpoint.instance
        } else {
            guard let endpoint = ConductorRegistry.instance[item.host].first else {
                return nil
            }
            self.endpoint = endpoint
        }
    }
}

@available(macOS 11.0, *)
@MainActor
class iTermBrowserPageSaver {
    private let webView: WKWebView
    private let baseURL: URL
    private var downloadedResources: [String: String] = [:]
    private var resourcesFolder: SSHLocation!

    init(webView: WKWebView, baseURL: URL) {
        self.webView = webView
        self.baseURL = baseURL
    }
    
    func savePageWithResources(to location: SSHLocation) async throws {
        // Create main folder and resources subfolder
        try await location.endpoint.mkdir(location.path)
        resourcesFolder = location.appendingPathComponent("resources")
        try await resourcesFolder.endpoint.mkdir(resourcesFolder.path)

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
        let htmlFile = location.appendingPathComponent("index.html")
        try await htmlFile.endpoint.create(htmlFile.path, content: processedHTML.lossyData)

        DLog("Page saved successfully to \(htmlFile.description)")
    }
    
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
    
    private func getHTMLWithSavedAttributes() async -> String? {
        // Get HTML by cloning the DOM and applying changes to the clone, not the live DOM
        let cloneAndProcessScript = """
        (function() {
            // Clone the entire document
            const clonedDoc = document.cloneNode(true);
            
            // Apply saved src attributes in the clone
            clonedDoc.querySelectorAll('[data-saved-src]').forEach(el => {
                el.setAttribute('src', el.getAttribute('data-saved-src'));
                el.removeAttribute('data-saved-src');
            });
            
            // Replace CSS link tags with style tags in the clone
            clonedDoc.querySelectorAll('link[rel="stylesheet"][data-saved-css-content]').forEach(link => {
                const cssContent = link.getAttribute('data-saved-css-content');
                const styleEl = clonedDoc.createElement('style');
                styleEl.textContent = cssContent;
                link.parentNode.replaceChild(styleEl, link);
            });
            
            // Apply saved href attributes for non-CSS links in the clone
            clonedDoc.querySelectorAll('[data-saved-href]').forEach(el => {
                el.setAttribute('href', el.getAttribute('data-saved-href'));
                el.removeAttribute('data-saved-href');
            });
            
            // Apply saved data attributes in the clone
            clonedDoc.querySelectorAll('[data-saved-data]').forEach(el => {
                el.setAttribute('data', el.getAttribute('data-saved-data'));
                el.removeAttribute('data-saved-data');
            });
            
            // Apply saved styles in the clone
            clonedDoc.querySelectorAll('[data-saved-style]').forEach(el => {
                el.setAttribute('style', el.getAttribute('data-saved-style'));
                el.removeAttribute('data-saved-style');
            });
            
            // Apply saved content to style tags in the clone
            clonedDoc.querySelectorAll('style[data-saved-content]').forEach(styleEl => {
                styleEl.textContent = styleEl.getAttribute('data-saved-content');
                styleEl.removeAttribute('data-saved-content');
            });
            
            // Get the full document including DOCTYPE from the clone
            const doctype = document.doctype ? 
                '<!DOCTYPE ' + document.doctype.name + '>' : '';
            return doctype + clonedDoc.documentElement.outerHTML;
        })();
        """
        
        do {
            let result = try await webView.evaluateJavaScript(cloneAndProcessScript)
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
        guard iTermBrowserMetadata.supportedSchemes.contains(resourceURL.scheme?.lowercased() ?? "") else {
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
            let filename = await generateFilename(for: resourceURL, response: response)
            let localFile = resourcesFolder.appendingPathComponent(filename)
            
            // Save the file
            try await localFile.endpoint.create(localFile.path, content: data)

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
    
    private func generateFilename(for url: URL, response: URLResponse?) async -> String {
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
        while await Self.fileExists(resourcesFolder.appendingPathComponent(filename)) {
            let nameWithoutExt = (originalFilename as NSString).deletingPathExtension
            let ext = (originalFilename as NSString).pathExtension
            filename = ext.isEmpty ? "\(nameWithoutExt)_\(counter)" : "\(nameWithoutExt)_\(counter).\(ext)"
            counter += 1
        }
        
        return filename
    }

    private static func fileExists(_ location: SSHLocation) async -> Bool {
        do {
            _ = try await location.endpoint.stat(location.path)
            return true
        } catch {
            return false
        }
    }

    private func extensionForMimeType(_ mimeType: String) -> String {
        return MimeTypeUtilities.extensionForMimeType(mimeType)
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

extension iTermBrowserPageSaver {
    @MainActor
    static func pickDestinationAndSave(webView: WKWebView, parentWindow: NSWindow) async {
        guard let url = webView.url else { return }

        let savePanel = iTermModernSavePanel()
        savePanel.defaultFilename = sanitizeFilename(url.host ?? "page")

        let response = await savePanel.beginSheetModal(for: parentWindow)
        guard response == .OK,
              let item = savePanel.item,
        let location = SSHLocation(item) else {
            return
        }

        await self.performPageSave(url: url,
                                   to: location,
                                   webView: webView,
                                   window: parentWindow)
    }

    private static func performPageSave(url: URL,
                                        to location: SSHLocation,
                                        webView: WKWebView,
                                        window: NSWindow) async {
        let pageSaver = iTermBrowserPageSaver(webView: webView, baseURL: url)

        do {
            try await pageSaver.savePageWithResources(to: location)

            if location.endpoint.sshIdentity.isLocalhost {
                await MainActor.run {
                    let htmlFile = location.appendingPathComponent("index.html")
                    NSWorkspace.shared.selectFile(htmlFile.path, inFileViewerRootedAtPath: location.path)
                }
            }
        } catch {
            DLog("Error saving page: \(error)")
            showSaveError(error, window: window)
        }
    }

    @MainActor
    private static func showSaveError(_ error: Error, window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = "Save Failed"
        alert.informativeText = "Could not save the page: \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window, completionHandler: nil)
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }
}
