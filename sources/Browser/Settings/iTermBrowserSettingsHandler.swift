//
//  iTermBrowserSettingsHandler.swift
//  iTerm2
//
//  Created by George Nachman on 6/18/25.
//

import Foundation
@preconcurrency import WebKit

@available(macOS 11.0, *)
@objc protocol iTermBrowserSettingsHandlerDelegate: AnyObject {
    @MainActor func settingsHandlerDidUpdateAdblockSettings(_ handler: iTermBrowserSettingsHandler)
    @MainActor func settingsHandlerDidRequestAdblockUpdate(_ handler: iTermBrowserSettingsHandler)
}

@available(macOS 11.0, *)
@objc(iTermBrowserSettingsHandler)
@MainActor
class iTermBrowserSettingsHandler: NSObject, iTermBrowserPageHandler {
    static let settingsURL = URL(string: "\(iTermBrowserSchemes.about):settings")!
    weak var delegate: iTermBrowserSettingsHandlerDelegate?
    private let secret: String
    private let user: iTermBrowserUser

    init(user: iTermBrowserUser) {
        self.user = user
        guard let secret = String.makeSecureHexString() else {
            it_fatalError("Failed to generate secure hex string for settings handler")
        }
        self.secret = secret
        super.init()
    }

    // MARK: - Public Interface
    
    func generateSettingsHTML() -> String {
        let isDevNull = (user == .devNull)
        let substitutions = ["ADBLOCK_ENABLED": iTermAdvancedSettingsModel.adblockEnabled() ? "checked" : "",
                             "ADBLOCK_URL": iTermAdvancedSettingsModel.adblockListURL().replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;"),
                             "SECRET": secret,
                             "DEV_NULL_NOTE": isDevNull ? "" : "display: none;"]

        return iTermBrowserTemplateLoader.loadTemplate(named: "settings-page",
                                                       type: "html",
                                                       substitutions: substitutions)
    }
    
    func start(urlSchemeTask: WKURLSchemeTask, url: URL) {
        let htmlToServe = generateSettingsHTML()
        
        guard let data = htmlToServe.data(using: .utf8) else {
            urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserSettingsHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode HTML"]))
            return
        }
        
        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    
    func injectSettingsJavaScript(into webView: WKWebView) {
        let script = """
        // Direct functions that call Swift
        window.clearCookies = function() {
            if (confirm('This will remove all cookies from all websites. Continue?')) {
                window.webkit.messageHandlers['\(iTermBrowserSchemes.about):settings'].postMessage({action: 'clearCookies'});
            }
        };
        
        window.clearAllData = function() {
            if (confirm('This will remove all browsing data including cookies, cache, and local storage. Continue?')) {
                window.webkit.messageHandlers['\(iTermBrowserSchemes.about):settings'].postMessage({action: 'clearAllData'});
            }
        };
        
        """
        
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    
    func handleSettingsMessage(_ message: [String: Any], webView: WKWebView) {
        guard let action = message["action"] as? String,
              let sessionSecret = message["sessionSecret"] as? String,
              sessionSecret == secret else {
            DLog("Invalid or missing session secret for settings action")
            return
        }
        
        switch action {
        case "clearCookies":
            clearCookies(webView: webView)
        case "clearAllData":
            clearAllWebsiteData(webView: webView)
        case "setAdblockEnabled":
            if let enabled = message["value"] as? Bool {
                setAdblockEnabled(enabled, webView: webView)
            }
        case "setAdblockURL":
            if let url = message["value"] as? String {
                setAdblockURL(url, webView: webView)
            }
        case "setSearchCommand":
            if let url = message["value"] as? String {
                setSearchCommand(url, webView: webView)
            }
        case "setSearchSuggestURL":
            if let url = message["value"] as? String {
                setSearchSuggestURL(url, webView: webView)
            }
        case "forceAdblockUpdate":
            forceAdblockUpdate(webView: webView)
        case "getAdblockSettings":
            sendAdblockSettings(to: webView)
        case "getSearchSettings":
            sendSearchSettings(to: webView)
        case "getAdblockStats":
            sendAdblockStats(to: webView)
        default:
            break
        }
    }
    
    private func clearCookies(webView: WKWebView) {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        cookieStore.getAllCookies { cookies in
            for cookie in cookies {
                cookieStore.delete(cookie) {
                    DLog("Cookie deleted")
                }
            }
        }
    }
    
    private func clearAllWebsiteData(webView: WKWebView) {
        let websiteDataStore = webView.configuration.websiteDataStore
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        websiteDataStore.removeData(ofTypes: dataTypes, modifiedSince: Date(timeIntervalSince1970: 0)) {
            let user = self.user
            Task {
                let message: String
                if await BrowserDatabase.instance(for: user)?.erase() == true {
                    message = "All website data has been cleared successfully!"
                } else {
                    if let url = BrowserDatabase.url(for: user) {
                        message = "The browser database could not be deleted. It is in \(url.path)"
                    } else {
                        message = "The browser database could not be deleted. Your application support folder could not be found."
                    }
                }
                DispatchQueue.main.async {
                    webView.evaluateJavaScript("alert('\(message)');", completionHandler: nil)
                }
            }
        }
    }
    
    // MARK: - Adblock Settings
    
    private func setAdblockEnabled(_ enabled: Bool, webView: WKWebView) {
        iTermAdvancedSettingsModel.setAdblockEnabled(enabled)
        delegate?.settingsHandlerDidUpdateAdblockSettings(self)
        
        DLog("Ad blocking \(enabled ? "enabled" : "disabled")")
        
        let message = enabled ? "Ad blocking enabled" : "Ad blocking disabled"
        showStatusMessage(message, type: "success", in: webView)
    }
    
    private func setAdblockURL(_ url: String, webView: WKWebView) {
        guard !url.isEmpty else { return }
        
        iTermAdvancedSettingsModel.setAdblockListURL(url)
        delegate?.settingsHandlerDidUpdateAdblockSettings(self)
        
        DLog("Ad block URL updated to: \(url)")
        showStatusMessage("Filter list URL updated", type: "success", in: webView)
    }
    
    private func forceAdblockUpdate(webView: WKWebView) {
        delegate?.settingsHandlerDidRequestAdblockUpdate(self)
        DLog("Force update of ad block rules requested")
    }
    
    private func sendAdblockSettings(to webView: WKWebView) {
        let enabled = iTermAdvancedSettingsModel.adblockEnabled()
        let url = iTermAdvancedSettingsModel.adblockListURL() ?? ""
        
        let settings = [
            "enabled": enabled,
            "url": url
        ] as [String: Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: settings)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            
            let script = "updateAdblockUI(\(jsonString));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        } catch {
            DLog("Failed to encode adblock settings: \(error)")
        }
    }
    
    private func sendAdblockStats(to webView: WKWebView) {
        let ruleCount = iTermAdblockManager.shared.getRuleCount()
        let lastUpdate = UserDefaults.standard.object(forKey: "NoSyncAdblockLastUpdate") as? Date
        
        let stats = [
            "ruleCount": ruleCount,
            "lastUpdate": lastUpdate?.timeIntervalSince1970 ?? 0
        ] as [String: Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: stats)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            
            let script = "updateAdblockStats(\(jsonString));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        } catch {
            DLog("Failed to encode adblock stats: \(error)")
        }
    }
    
    private func showStatusMessage(_ message: String, type: String, in webView: WKWebView) {
        let escapedMessage = message.replacingOccurrences(of: "'", with: "\\'")
        let script = "showStatus('\(escapedMessage)', '\(type)');"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    
    @objc func showAdblockUpdateSuccess(in webView: WKWebView) {
        showStatusMessage("Ad block rules updated successfully", type: "success", in: webView)
    }
    
    @objc func showAdblockUpdateError(_ error: String, in webView: WKWebView) {
        showStatusMessage("Failed to update ad block rules: \(error)", type: "error", in: webView)
    }
    
    // MARK: - Search Settings
    
    private func setSearchCommand(_ url: String, webView: WKWebView) {
        guard !url.isEmpty, url.contains("%@") else {
            showStatusMessage("Invalid search URL: must contain %@ placeholder", type: "error", in: webView)
            return
        }
        
        iTermAdvancedSettingsModel.setSearchCommand(url)
        DLog("Search command updated to: \(url)")
        showStatusMessage("Search engine updated", type: "success", in: webView)
    }
    
    private func setSearchSuggestURL(_ url: String, webView: WKWebView) {
        if !url.isEmpty && !url.contains("%@") {
            showStatusMessage("Invalid suggestion URL: must contain %@ placeholder", type: "error", in: webView)
            return
        }
        
        iTermAdvancedSettingsModel.setSearchSuggestURL(url)
        DLog("Search suggestion URL updated to: \(url.isEmpty ? "disabled" : url)")
        if url.isEmpty {
            showStatusMessage("Search suggestions disabled", type: "success", in: webView)
        } else {
            showStatusMessage("Search suggestions updated", type: "success", in: webView)
        }
    }
    
    private func sendSearchSettings(to webView: WKWebView) {
        let searchCommand = iTermAdvancedSettingsModel.searchCommand()!
        let searchSuggestURL = iTermAdvancedSettingsModel.searchSuggestURL()!
        
        let settings = [
            "searchCommand": searchCommand,
            "searchSuggestURL": searchSuggestURL
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: settings)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            
            let script = "updateSearchEngineUI(\(jsonString));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        } catch {
            DLog("Failed to encode search settings: \(error)")
        }
    }
    
    // MARK: - iTermBrowserPageHandler Protocol
    
    func injectJavaScript(into webView: WKWebView) {
        injectSettingsJavaScript(into: webView)
    }
    
    func resetState() {
        // Settings handler doesn't maintain state that needs resetting
    }
}
