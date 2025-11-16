//
//  iTermBrowserFileHandler.swift
//  iTerm2
//
//  Created by George Nachman on 11/15/25.
//

import Foundation
@preconcurrency import WebKit

@objc(iTermBrowserFileHandler)
class iTermBrowserFileHandler: NSObject, iTermBrowserPageHandler {
    // MARK: - iTermBrowserPageHandler Protocol

    func injectJavaScript(into webView: iTermBrowserWebView) {
        // File pages don't need JavaScript injection
    }

    func resetState() {
        // No state to reset
    }

    func start(urlSchemeTask: WKURLSchemeTask, url: URL) {
        // Extract the file path from the URL
        // URL format: iterm2-file:///path/to/file or iterm2-file:///path/to/folder/
        var path = url.path
        NSLog("iTermBrowserFileHandler.start: url=\(url.absoluteString), path=\(path)")

        guard !path.isEmpty else {
            NSLog("iTermBrowserFileHandler.start: path is empty")
            urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No path specified"]))
            return
        }

        // Strip trailing slash (except for root "/")
        if path != "/" && path.hasSuffix("/") {
            path = String(path.dropLast())
        }

        let html: String
        do {
            html = try generateHTML(for: path)
            NSLog("iTermBrowserFileHandler.start: generated HTML, length=\(html.count)")
        } catch {
            NSLog("iTermBrowserFileHandler.start: error generating HTML: \(error)")
            urlSchemeTask.didFailWithError(error)
            return
        }

        guard let data = html.data(using: .utf8) else {
            NSLog("iTermBrowserFileHandler.start: failed to encode HTML")
            urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode HTML"]))
            return
        }

        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
        NSLog("iTermBrowserFileHandler.start: finished successfully")
    }

    // MARK: - HTML Generation

    private func generateHTML(for path: String) throws -> String {
        let fileURL = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: fileURL.resolvingSymlinksInPath().path, isDirectory: &isDirectory) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: [NSLocalizedDescriptionKey: "File not found: \(path)"])
        }

        if isDirectory.boolValue {
            return try generateDirectoryHTML(for: path)
        } else {
            return try generateFileHTML(for: fileURL)
        }
    }

    private func generateDirectoryHTML(for path: String) throws -> String {
        let url = URL(fileURLWithPath: path)

        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var items = ""

        // Add parent directory link if not at root
        if url.path != "/" {
            let parentURL = url.deletingLastPathComponent()
            var parentComponents = URLComponents()
            parentComponents.scheme = iTermBrowserSchemes.file
            parentComponents.path = parentURL.path
            if let parentHref = parentComponents.url?.absoluteString {
                items += "<li><a href=\"\(parentHref)\">..</a></li>\n"
            }
        }

        for item in contents.sorted(by: { a, b in
            let aValues = try? a.resourceValues(forKeys: [.isDirectoryKey])
            let bValues = try? b.resourceValues(forKeys: [.isDirectoryKey])
            let aIsDir = aValues?.isDirectory == true
            let bIsDir = bValues?.isDirectory == true

            // Directories first, then alphabetically
            if aIsDir != bIsDir {
                return aIsDir
            }
            return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
        }) {
            let values = try item.resourceValues(forKeys: [.isDirectoryKey])
            let isDir = values.isDirectory == true
            let name = item.lastPathComponent.escapedForHTML

            // Generate absolute iterm2-file:// URLs using URLComponents
            var components = URLComponents()
            components.scheme = iTermBrowserSchemes.file
            components.path = item.path
            // Add trailing slash for directories so CSS can style them with folder icons
            var href = components.url?.absoluteString ?? ""
            if isDir && !href.isEmpty {
                href += "/"
            }

            items += "<li><a href=\"\(href)\">\(name)</a></li>\n"
        }

        let directoryContent = "<ul>\n\(items)</ul>"

        let substitutions = [
            "TITLE": url.lastPathComponent.escapedForHTML,
            "PATH": url.path.escapedForHTML,
            "CONTENT": directoryContent
        ]

        return iTermBrowserTemplateLoader.loadTemplate(named: "file-page",
                                                       type: "html",
                                                       substitutions: substitutions)
    }

    private func generateFileHTML(for url: URL) throws -> String {
        let content: Data
        content = try Data(contentsOf: url)

        if ["html", "htm"].contains(url.path.pathExtension) {
            return content.lossyString
        } else if let string = String(data: content, encoding: .utf8) {
            return "<pre>" + string.escapedForHTML + "</pre>"
        } else if let string = String(data: content, encoding: .isoLatin1) {
            return "<pre>" + string.escapedForHTML + "</pre>"
        } else {
            return "<pre>\n" + content.chunks(of: 80).map { $0.slice.hexified }.joined(separator: "<br/>") + "</pre>"
        }
    }
}
