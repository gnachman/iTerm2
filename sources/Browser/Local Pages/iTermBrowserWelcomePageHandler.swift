//
//  iTermBrowserWelcomePageHandler.swift
//  iTerm2
//
//  Created by George Nachman on 1/3/25.
//

import WebKit
import Foundation

@available(macOS 11.0, *)
@objc protocol iTermBrowserWelcomePageHandlerDelegate: AnyObject {
    @MainActor func welcomePageHandlerDidNavigateToURL(_ handler: iTermBrowserWelcomePageHandler, url: String)
}

@available(macOS 11.0, *)
@objc(iTermBrowserWelcomePageHandler)
@MainActor
class iTermBrowserWelcomePageHandler: NSObject, iTermBrowserPageHandler {
    static let welcomeURL = URL(string: "\(iTermBrowserSchemes.about):welcome")!
    private let user: iTermBrowserUser
    private let secret: String
    weak var delegate: iTermBrowserWelcomePageHandlerDelegate?
    
    init?(user: iTermBrowserUser) {
        self.user = user
        guard let secret = String.makeSecureHexString() else {
            return nil
        }
        self.secret = secret
        super.init()
    }
    
    // MARK: - Public Interface
    
    func generateWelcomeHTML() -> String {
        let script = iTermBrowserTemplateLoader.loadTemplate(named: "welcome-page",
                                                             type: "js",
                                                             substitutions: ["SECRET": secret])
        return iTermBrowserTemplateLoader.loadTemplate(named: "welcome-page",
                                                       type: "html",
                                                       substitutions: [
                                                           "WELCOME_SCRIPT": script
                                                       ])
    }
    
    func start(urlSchemeTask: WKURLSchemeTask, url: URL) {
        // Check if onboarding is complete
        let onboardingCompleted = UserDefaults.standard.bool(forKey: "NoSyncBrowserOnboardingCompleted")
        
        if !onboardingCompleted {
            // Redirect to onboarding page
            let redirectHTML = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta http-equiv="refresh" content="0; url=iterm2-about:onboarding-intro">
            </head>
            <body>
                <script>window.location.href = "iterm2-about:onboarding-intro";</script>
            </body>
            </html>
            """
            
            guard let data = redirectHTML.data(using: .utf8) else {
                urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserWelcomePageHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode redirect HTML"]))
                return
            }
            
            let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
            return
        }
        
        // Onboarding is complete, show the welcome page with top sites
        let htmlToServe = generateWelcomeHTML()
        
        guard let data = htmlToServe.data(using: .utf8) else {
            urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserWelcomePageHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode HTML"]))
            return
        }
        
        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    
    func handleWelcomeMessage(_ message: [String: Any], webView: WKWebView) async {
        DLog("Welcome message received: \(message)")

        guard let action = message["action"] as? String,
              let sessionSecret = message["sessionSecret"] as? String,
              sessionSecret == secret else {
            DLog("Invalid or missing session secret for welcome action")
            return
        }
        
        switch action {
        case "loadTopSites":
            DLog("Handling welcome action: \(action)")
            return await loadTopSites(webView: webView)
            
        case "navigateToURL":
            if let url = message["url"] as? String {
                delegate?.welcomePageHandlerDidNavigateToURL(self, url: url)
            }
            return
            
        default:
            return
        }
    }
    
    // MARK: - iTermBrowserPageHandler Protocol
    
    func injectJavaScript(into webView: WKWebView) {
        // JavaScript will be injected via the template
    }
    
    func resetState() {
        // Welcome page doesn't have persistent state to reset
    }
    
    // MARK: - Private Implementation
    
    private func loadTopSites(webView: WKWebView) async {
        DLog("Loading top visited sites")
        
        guard let database = await BrowserDatabase.instance(for: user) else {
            DLog("Could not get database instance")
            await sendTopSitesResponse([], webView: webView)
            return
        }
        
        let topSites = await database.topVisitedUrls(limit: 5)
        
        DLog("Fetched \(topSites.count) top sites")
        
        // Convert to JavaScript-friendly format
        let sitesData = topSites.map { site in
            return [
                "url": site.url,
                "title": site.title ?? site.hostname,
                "hostname": site.hostname.removing(prefix: "."),
                "visitCount": site.visitCount
            ]
        }
        
        await sendTopSitesResponse(sitesData, webView: webView)
    }
    
    private func sendTopSitesResponse(_ sites: [[String: Any]], webView: WKWebView) async {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: sites, options: [])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
            
            let script = "window.handleTopSitesResponse(\(jsonString));"
            
            await MainActor.run {
                webView.evaluateJavaScript(script) { result, error in
                    if let error = error {
                        DLog("Error sending top sites response: \(error)")
                    } else {
                        DLog("Successfully sent top sites to page")
                    }
                }
            }
        } catch {
            DLog("Error serializing top sites: \(error)")
        }
    }
}
