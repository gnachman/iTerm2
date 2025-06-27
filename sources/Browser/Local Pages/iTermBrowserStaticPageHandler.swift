//
//  iTermBrowserStaticPageHandler.swift
//  iTerm2
//
//  Created by George Nachman on 6/22/25.
//

//    # Adding Static iterm2-about: Pages
//
//    This document explains how to add simple static HTML pages to iTerm2's browser system using the built-in template system.
//
//    ## For Static Pages (No JavaScript interaction)
//
//    If you want to add a simple static page that doesn't need to communicate with Swift code:
//
//    ### 1. Create your HTML template
//
//    Create an HTML template file in the Browser sources folder (e.g., `help-page.html`):
//
//    ```html
//    <!DOCTYPE html>
//    <html lang="en">
//    <head>
//        <meta charset="UTF-8">
//        <meta name="viewport" content="width=device-width, initial-scale=1.0">
//        <title>{{TITLE}}</title>
//        <style>
//            {{COMMON_CSS}}
//
//            /* Your custom styles here */
//            .help-container {
//                max-width: 800px;
//            }
//
//            .help-section {
//                margin-bottom: 32px;
//            }
//        </style>
//    </head>
//    <body>
//        <div class="container help-container">
//            <h1>{{TITLE}}</h1>
//            <p>{{SUBTITLE}}</p>
//
//            <div class="help-section">
//                <h2>Getting Started</h2>
//                <p>Your help content here...</p>
//            </div>
//        </div>
//    </body>
//    </html>
//    ```
//
//    ### 2. Register the page
//
//    Add your page to the static page registry in `iTermBrowserStaticPageHandler.swift`:
//
//    ```swift
//    private func setupDefaultPages() {
//        registerStaticPage(urlPath: "welcome", templateName: "welcome-page", substitutions: [
//            "TITLE": "Welcome to iTerm2",
//            "SUBTITLE": "The terminal emulator for macOS that does amazing things."
//        ])
//
//        // Add your page here
//        registerStaticPage(urlPath: "help", templateName: "help-page", substitutions: [
//            "TITLE": "iTerm2 Help",
//            "SUBTITLE": "Find answers to common questions and learn about features."
//        ])
//    }
//    ```
//
//    ### 3. Access your page
//
//    Navigate to `iterm2-about:help` (or whatever urlPath you chose) in the browser.
//
//    ## That's it!
//
//    ## For Interactive Pages
//
//    If you need JavaScript communication with Swift code (like the existing settings, history, and bookmarks pages), you still need to create a custom handler implementing `iTermBrowserPageHandler` and add it to the switch statement in `setupPageContext(for:)`.

import Foundation
@preconcurrency import WebKit

// MARK: - Static Page Configuration

@available(macOS 11.0, *)
struct iTermBrowserStaticPageConfig {
    let url: URL
    let templateName: String
    let substitutions: [String: String]
    
    init(urlPath: String, templateName: String, substitutions: [String: String] = [:]) {
        self.url = URL(string: "\(iTermBrowserSchemes.about):\(urlPath)")!
        self.templateName = templateName
        self.substitutions = substitutions
    }
}

// MARK: - Static Page Handler

@available(macOS 11.0, *)
@MainActor
class iTermBrowserStaticPageHandler: NSObject, iTermBrowserPageHandler {
    private let config: iTermBrowserStaticPageConfig
    
    init(config: iTermBrowserStaticPageConfig) {
        self.config = config
        super.init()
    }
    
    func start(urlSchemeTask: WKURLSchemeTask, url: URL) {
        let htmlContent = generateHTML()
        
        guard let data = htmlContent.data(using: .utf8) else {
            let error = NSError(domain: "iTermBrowserStaticPageHandler", 
                               code: -1, 
                               userInfo: [NSLocalizedDescriptionKey: "Failed to encode HTML"])
            urlSchemeTask.didFailWithError(error)
            return
        }
        
        // Create HTTP response
        let response = URLResponse(
            url: url,
            mimeType: "text/html",
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    
    func injectJavaScript(into webView: WKWebView) {
        // Static pages don't need JavaScript injection
    }
    
    func resetState() {
        // Static pages don't have state to reset
    }
    
    // MARK: - Private Methods
    
    private func generateHTML() -> String {
        return iTermBrowserTemplateLoader.loadTemplate(
            named: config.templateName,
            type: "html",
            substitutions: config.substitutions
        )
    }
}

// MARK: - Static Page Registry

@available(macOS 11.0, *)
class iTermBrowserStaticPageRegistry {
    static let shared = iTermBrowserStaticPageRegistry()
    
    private var staticPages: [String: iTermBrowserStaticPageConfig] = [:]
    
    private init() {
        setupDefaultPages()
    }
    
    private func setupDefaultPages() {
        // Register all static pages here
        registerStaticPage(urlPath: "welcome", templateName: "welcome-page", substitutions: [:])
        #if DEBUG
        let pages = [
            "notifications-demo",
            "geolocation-demo",
            "media-demo",
            "password-demo",
            "selection-test",
            "smartselection-demo",
            "indexeddb-demo",
            "clipboard-demo",
            "dragdrop-demo",
            "autofill-demo"
        ]
        for page in pages {
            registerStaticPage(urlPath: page, templateName: page, substitutions: [:])
        }
        #endif
    }
    
    func registerStaticPage(urlPath: String, templateName: String, substitutions: [String: String] = [:]) {
        let config = iTermBrowserStaticPageConfig(urlPath: urlPath, templateName: templateName, substitutions: substitutions)
        staticPages[config.url.absoluteString] = config
    }
    
    func getConfig(for urlString: String) -> iTermBrowserStaticPageConfig? {
        return staticPages[urlString]
    }
    
    func isStaticPage(_ urlString: String) -> Bool {
        return staticPages[urlString] != nil
    }
    
    // MARK: - Convenience Methods
    
    /// Register multiple static pages at once
    func registerStaticPages(_ pages: [(urlPath: String, templateName: String, substitutions: [String: String])]) {
        for page in pages {
            registerStaticPage(urlPath: page.urlPath, templateName: page.templateName, substitutions: page.substitutions)
        }
    }
    
    /// Get all registered static page URLs
    var registeredURLs: [String] {
        return Array(staticPages.keys)
    }
}
