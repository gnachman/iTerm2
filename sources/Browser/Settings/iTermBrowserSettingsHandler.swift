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

    // MARK: - Public Interface
    
    func generateSettingsHTML() -> String {
        let substitutions = ["ADBLOCK_ENABLED": iTermAdvancedSettingsModel.adblockEnabled() ? "checked" : "",
                             "ADBLOCK_URL": iTermAdvancedSettingsModel.adblockListURL().replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")]

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
        guard let action = message["action"] as? String else { return }
        
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
        case "forceAdblockUpdate":
            forceAdblockUpdate(webView: webView)
        case "getAdblockSettings":
            sendAdblockSettings(to: webView)
        default:
            break
        }
    }
    
    private func clearCookies(webView: WKWebView) {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        cookieStore.getAllCookies { cookies in
            let group = DispatchGroup()
            
            for cookie in cookies {
                group.enter()
                cookieStore.delete(cookie) {
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                // Show confirmation alert
                webView.evaluateJavaScript("alert('All cookies have been cleared successfully!');", completionHandler: nil)
            }
        }
    }
    
    private func clearAllWebsiteData(webView: WKWebView) {
        let websiteDataStore = webView.configuration.websiteDataStore
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        websiteDataStore.removeData(ofTypes: dataTypes, modifiedSince: Date(timeIntervalSince1970: 0)) {
            Task {
                let message: String
                if await BrowserDatabase.instance?.erase() == true {
                    message = "All website data has been cleared successfully!"
                } else {
                    if let url = BrowserDatabase.url {
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
        
        let script = """
        updateAdblockUI({
            enabled: \(enabled),
            url: '\(url.replacingOccurrences(of: "'", with: "\\'"))'
        });
        """
        
        webView.evaluateJavaScript(script, completionHandler: nil)
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
    
    // MARK: - iTermBrowserPageHandler Protocol
    
    func injectJavaScript(into webView: WKWebView) {
        injectSettingsJavaScript(into: webView)
    }
    
    func resetState() {
        // Settings handler doesn't maintain state that needs resetting
    }
}
