//
//  iTermBrowserSettingsHandler.swift
//  iTerm2
//
//  Created by George Nachman on 6/18/25.
//

import Foundation
@preconcurrency import WebKit
import WebExtensionsFramework
import AppKit

@available(macOS 11.0, *)
protocol iTermBrowserSettingsHandlerDelegate: AnyObject {
    @MainActor func settingsHandlerDidUpdateAdblockSettings(_ handler: iTermBrowserSettingsHandler)
    @MainActor func settingsHandlerDidRequestAdblockUpdate(_ handler: iTermBrowserSettingsHandler)
    @MainActor func settingsHandlerWebView(_ handler: iTermBrowserSettingsHandler) -> WKWebView?
    @MainActor func settingsHandlerExtensionManager(_ handler: iTermBrowserSettingsHandler) -> iTermBrowserExtensionManagerProtocol?
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
        
        // Observe Rust adblock stats changes
        NotificationCenter.default.addObserver(self, 
                                               selector: #selector(rustAdblockStatsChanged), 
                                               name: .rustAdblockStatsChanged, 
                                               object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func rustAdblockStatsChanged() {
        guard let webView = delegate?.settingsHandlerWebView(self) else { return }
        sendRustAdblockStats(to: webView)
    }
    
    // MARK: - Public Interface
    
    func generateSettingsHTML() -> String {
        let isDevNull = (user == .devNull)
        
        // Check if extensions should be shown
        var showExtensions = false
#if ITERM_DEBUG
        if #available(macOS 14, *) {
            showExtensions = true
        }
#endif
        
        let substitutions = ["ADBLOCK_ENABLED": iTermAdvancedSettingsModel.adblockEnabled() ? "checked" : "",
                             "ADBLOCK_URL": iTermAdvancedSettingsModel.adblockListURL().replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;"),
                             "RUST_ADBLOCK_ENABLED": iTermAdvancedSettingsModel.adblockEnabled() ? "checked" : "",
                             "SECRET": secret,
                             "DEV_NULL_NOTE": isDevNull ? "" : "display: none;",
                             "SHOW_EXTENSIONS": showExtensions ? "" : "display: none;"]
        
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
        case "setProxyEnabled":
            if let enabled = message["value"] as? Bool {
                setProxyEnabled(enabled, webView: webView)
            }
        case "setProxyHost":
            if let host = message["value"] as? String {
                setProxyHost(host, webView: webView)
            }
        case "setProxyPort":
            if let port = message["value"] as? Int {
                setProxyPort(port, webView: webView)
            }
        case "getProxySettings":
            sendProxySettings(to: webView)
        case "setRustAdblockEnabled":
            if let enabled = message["value"] as? Bool {
                setRustAdblockEnabled(enabled, webView: webView)
            }
        case "forceRustAdblockUpdate":
            forceRustAdblockUpdate(webView: webView)
        case "getRustAdblockSettings":
            sendRustAdblockSettings(to: webView)
        case "getRustAdblockStats":
            sendRustAdblockStats(to: webView)
        case "setRustAdblockURL":
            if let url = message["value"] as? String {
                setRustAdblockURL(url, webView: webView)
            }
        case "getExtensions":
#if ITERM_DEBUG
            if #available(macOS 14, *) {
                sendExtensions(to: webView)
            }
#endif
        case "setExtensionEnabled":
#if ITERM_DEBUG
            if #available(macOS 14, *) {
                if let extensionId = message["extensionId"] as? String,
                   let enabled = message["enabled"] as? Bool {
                    setExtensionEnabled(extensionId, enabled: enabled, webView: webView)
                }
            }
#endif
        case "revealExtensionsDirectory":
#if ITERM_DEBUG
            if #available(macOS 14, *) {
                revealExtensionsDirectory(webView: webView)
            }
#endif
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
        let ruleCount = iTermBrowserAdblockManager.shared.getRuleCount()
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
    
    // MARK: - Rust Adblock Settings
    
    private func setRustAdblockEnabled(_ enabled: Bool, webView: WKWebView) {
        iTermAdvancedSettingsModel.setAdblockEnabled(enabled)
        
        DLog("Rust ad blocking \(enabled ? "enabled" : "disabled")")
        
        let message = enabled ? "Rust ad blocking enabled" : "Rust ad blocking disabled"
        showStatusMessage(message, type: "success", in: webView)
        
        // Reload the manager if enabled
        if enabled {
            Task {
                await iTermBrowserAdblockRustManager.shared.reload()
            }
        }
    }
    
    private func forceRustAdblockUpdate(webView: WKWebView) {
        Task {
            await iTermBrowserAdblockRustManager.shared.reload()
            await MainActor.run {
                showStatusMessage("Rust ad blocking filter lists reloaded", type: "success", in: webView)
                // Update stats after reload
                sendRustAdblockStats(to: webView)
            }
        }
    }
    
    private func setRustAdblockURL(_ url: String, webView: WKWebView) {
        guard !url.isEmpty else { return }
        
        iTermAdvancedSettingsModel.setRustAdblockListURL(url)
        
        DLog("Rust adblock URL updated to: \(url)")
        showStatusMessage("Filter list URL updated", type: "success", in: webView)
    }
    
    private func sendRustAdblockSettings(to webView: WKWebView) {
        let enabled = iTermAdvancedSettingsModel.adblockEnabled()
        let url = iTermAdvancedSettingsModel.rustAdblockListURL() ?? "https://easylist.to/easylist/easylist.txt"
        
        let settings = [
            "enabled": enabled,
            "url": url
        ] as [String: Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: settings)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            
            let script = "updateRustAdblockUI(\(jsonString));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        } catch {
            DLog("Failed to encode Rust adblock settings: \(error)")
        }
    }
    
    private func sendRustAdblockStats(to webView: WKWebView) {
        let enabled = iTermAdvancedSettingsModel.adblockEnabled()
        let manager = iTermBrowserAdblockRustManager.shared
        
        let stats = [
            "enabled": enabled,
            "engineLoaded": manager.engine != nil,
            "isDownloading": manager.isDownloading,
            "ruleCount": manager.ruleCount,
            "hiddenElementsCount": 0, // Could be enhanced with actual tracking
            "blockedRequestsCount": 0  // Could be enhanced with actual tracking
        ] as [String: Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: stats)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            
            let script = "updateRustAdblockStats(\(jsonString));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        } catch {
            DLog("Failed to encode Rust adblock stats: \(error)")
        }
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
    
    // MARK: - Proxy Settings
    
    private func setProxyEnabled(_ enabled: Bool, webView: WKWebView) {
        iTermAdvancedSettingsModel.setBrowserProxyEnabled(enabled)
        
        DLog("Browser proxy \(enabled ? "enabled" : "disabled")")
        
        let message = enabled ? "Proxy enabled" : "Proxy disabled"
        showStatusMessage(message, type: "success", in: webView)
        
        // Notify delegate to reconfigure webview if needed
        delegate?.settingsHandlerDidUpdateAdblockSettings(self)
    }
    
    private func setProxyHost(_ host: String, webView: WKWebView) {
        guard !host.isEmpty else { return }
        
        iTermAdvancedSettingsModel.setBrowserProxyHost(host)
        
        DLog("Browser proxy host updated to: \(host)")
        showStatusMessage("Proxy host updated", type: "success", in: webView)
        
        // Notify delegate to reconfigure webview if needed
        delegate?.settingsHandlerDidUpdateAdblockSettings(self)
    }
    
    private func setProxyPort(_ port: Int, webView: WKWebView) {
        guard port >= 1 && port <= 65535 else {
            showStatusMessage("Invalid port number", type: "error", in: webView)
            return
        }
        
        iTermAdvancedSettingsModel.setBrowserProxyPort(Int32(port))
        
        DLog("Browser proxy port updated to: \(port)")
        showStatusMessage("Proxy port updated", type: "success", in: webView)
        
        // Notify delegate to reconfigure webview if needed
        delegate?.settingsHandlerDidUpdateAdblockSettings(self)
    }
    
    private func sendProxySettings(to webView: WKWebView) {
        let enabled = iTermAdvancedSettingsModel.browserProxyEnabled()
        let host = iTermAdvancedSettingsModel.browserProxyHost() ?? "127.0.0.1"
        let port = iTermAdvancedSettingsModel.browserProxyPort()
        
        let settings = [
            "enabled": enabled,
            "host": host,
            "port": port
        ] as [String: Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: settings)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            
            let script = "updateProxyUI(\(jsonString));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        } catch {
            DLog("Failed to encode proxy settings: \(error)")
        }
    }
    
    // MARK: - Extension Settings
    
    private func sendExtensions(to webView: WKWebView) {
        if #available(macOS 14, *) {
            sendExtensionsForMacOS14(to: webView)
        } else {
            // Extensions not supported on macOS < 14
            let script = "updateExtensionsUI([]);"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
    
    @available(macOS 14, *)
    private func sendExtensionsForMacOS14(to webView: WKWebView) {
        guard let extensionManager = delegate?.settingsHandlerExtensionManager(self) else {
            // Send empty array if extension manager is not available
            let script = "updateExtensionsUI([]);"
            webView.evaluateJavaScript(script, completionHandler: nil)
            return
        }
        
        let availableExtensions = extensionManager.availableExtensions
        
        let extensionsData = availableExtensions.map { browserExtension in
            let manifest = browserExtension.manifest
            return [
                "id": browserExtension.id.stringValue,
                "name": manifest.name,
                "description": manifest.description ?? "No description available",
                "version": manifest.version,
                "permissions": manifest.permissions ?? [],
                "hostPermissions": manifest.hostPermissions ?? [],
                "enabled": extensionManager.extensionEnabled(id: browserExtension.id)
            ] as [String: Any]
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: extensionsData)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            
            let script = "updateExtensionsUI(\(jsonString));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        } catch {
            DLog("Failed to encode extensions data: \(error)")
            let script = "updateExtensionsUI([]);"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
    
    private func setExtensionEnabled(_ extensionIdString: String, enabled: Bool, webView: WKWebView) {
        if #available(macOS 14, *) {
            setExtensionEnabledForMacOS14(extensionIdString, enabled: enabled, webView: webView)
        } else {
            showStatusMessage("Extensions not supported on this macOS version", type: "error", in: webView)
        }
    }
    
    @available(macOS 14, *)
    private func setExtensionEnabledForMacOS14(_ extensionIdString: String, enabled: Bool, webView: WKWebView) {
        guard let extensionManager = delegate?.settingsHandlerExtensionManager(self) else {
            showStatusMessage("Extension management not available", type: "error", in: webView)
            return
        }
        
        let extensionId = ExtensionID(stringValue: extensionIdString)
        extensionManager.set(id: extensionId, enabled: enabled)
        
        DLog("Extension \(extensionIdString) \(enabled ? "enabled" : "disabled")")
        
        let message = enabled ? "Extension enabled" : "Extension disabled"
        showStatusMessage(message, type: "success", in: webView)
        
        // Note: Extensions list will be automatically refreshed via delegate callback
        // when the profile observer detects the change
    }
    
    private func revealExtensionsDirectory(webView: WKWebView) {
        if #available(macOS 14, *) {
            revealExtensionsDirectoryForMacOS14(webView: webView)
        } else {
            showStatusMessage("Extensions not supported on this macOS version", type: "error", in: webView)
        }
    }
    
    @available(macOS 14, *)
    private func revealExtensionsDirectoryForMacOS14(webView: WKWebView) {
        guard let extensionManager = delegate?.settingsHandlerExtensionManager(self) else {
            showStatusMessage("Extension management not available", type: "error", in: webView)
            return
        }
        
        // Get the extensions directory from the extension manager
        guard let extensionsURL = extensionManager.extensionsDirectory else {
            showStatusMessage("Extensions directory not configured in profile preferences", type: "error", in: webView)
            return
        }
        
        // Create the directory if it doesn't exist
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: extensionsURL, withIntermediateDirectories: true, attributes: nil)
            
            // Reveal in Finder
            NSWorkspace.shared.activateFileViewerSelecting([extensionsURL])
            
            DLog("Revealed extensions directory in Finder: \(extensionsURL.path)")
            showStatusMessage("Extensions directory revealed in Finder", type: "success", in: webView)
            
        } catch {
            DLog("Failed to create or reveal extensions directory: \(error)")
            showStatusMessage("Failed to create extensions directory: \(error.localizedDescription)", type: "error", in: webView)
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

// MARK: - iTermBrowserExtensionManagerDelegate

@available(macOS 11.0, *)
extension iTermBrowserSettingsHandler: iTermBrowserExtensionManagerDelegate {
    func extensionManagerDidUpdateExtensions(_ manager: iTermBrowserExtensionManagerProtocol) {
        // Refresh the extensions list in the settings UI
        guard let webView = delegate?.settingsHandlerWebView(self) else { return }
        sendExtensions(to: webView)
    }
}
