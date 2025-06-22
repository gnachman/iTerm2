//
//  iTermBrowserFavicon.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

import WebKit

struct FaviconError: Error {}

@available(macOS 11, *)
@MainActor
func detectFavicon(webView: WKWebView) async throws -> Either<NSImage, URL> {
    guard let currentURL = webView.url else {
        throw FaviconError()
    }

    // For internal pages, use the main app icon
    if currentURL.absoluteString.hasPrefix(iTermBrowserSchemes.about) {
        return .left(NSApp.applicationIconImage)
    }

    // JavaScript to find favicon links in the page
    let script = iTermBrowserTemplateLoader.loadTemplate(named: "detect-favicon",
                                                         type: "js",
                                                         substitutions: [:])
    let result = try await webView.evaluateJavaScript(script)
    guard let faviconURLString = result as? String,
          let faviconURL = URL(string: faviconURLString) else {
        throw FaviconError()
    }
    return .right(faviconURL)
}
