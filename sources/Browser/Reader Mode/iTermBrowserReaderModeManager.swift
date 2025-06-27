//
//  iTermBrowserReaderModeManager.swift
//  iTerm2
//
//  Created by George Nachman on 6/24/25.
//

import WebKit

@available(macOS 11.0, *)
@objc protocol iTermBrowserReaderModeManagerDelegate: AnyObject {
    func readerModeManager(_ manager: iTermBrowserReaderModeManager, didChangeActiveState isActive: Bool)
    func readerModeManager(_ manager: iTermBrowserReaderModeManager, didChangeDistractionRemovalState isActive: Bool)
}

@available(macOS 11.0, *)
@objc(iTermBrowserReaderModeManager)
class iTermBrowserReaderModeManager: NSObject {
    weak var delegate: iTermBrowserReaderModeManagerDelegate?
    private var isReaderModeActive = false
    private(set) var isDistractionRemovalActive = false
    private var scriptsInjected = false
    private var cached: String?

    @objc var isActive: Bool {
        return isReaderModeActive
    }
    
    @objc func toggle(webView: WKWebView) {
        Task {
            await toggleReaderMode(webView: webView)
        }
    }

    func plainTextContent(webView: WKWebView) async -> String? {
        if let cached {
            return cached
        }
        // Ensure Readability.js is loaded first
        guard await ensureScriptsInjected(webView: webView) else {
            return nil
        }

        do {
            let script = iTermBrowserTemplateLoader.loadTemplate(named: "extract-plain-text",
                                                               type: "js",
                                                               substitutions: [:])
            let result = try await webView.evaluateJavaScript(script)
            if let string = result as? String, !string.isEmpty {
                cached = string
                return string
            } else {
                cached = ""
                return nil
            }
        } catch {
            DLog("Error extracting plain text content: \(error)")
            cached = ""
            return nil
        }
    }

    private func toggleReaderMode(webView: WKWebView) async {
        if isReaderModeActive {
            await exitReaderMode(webView: webView)
        } else {
            await enterReaderMode(webView: webView)
        }
    }
    
    private func enterReaderMode(webView: WKWebView) async {
        guard await ensureScriptsInjected(webView: webView) else { return }

        do {
            let script = iTermBrowserTemplateLoader.loadTemplate(named: "enter-reader-mode",
                                                               type: "js",
                                                               substitutions: [:])
            if let result = try await webView.evaluateJavaScript(script) as? Bool,
               result {
                await updateReaderModeState(true)
            }
        } catch {
            DLog("Error entering reader mode: \(error)")
        }
    }
    
    private func exitReaderMode(webView: WKWebView) async {
        do {
            let script = iTermBrowserTemplateLoader.loadTemplate(named: "exit-reader-mode",
                                                               type: "js",
                                                               substitutions: [:])
            try await webView.evaluateJavaScript(script)
            await updateReaderModeState(false)
        } catch {
            DLog("Error exiting reader mode: \(error)")
        }
    }
    
    func toggleDistractionRemovalMode(webView: WKWebView) async {
        if isDistractionRemovalActive {
            await exitDistractionRemovalMode(webView: webView)
        } else {
            await enterDistractionRemovalMode(webView: webView)
        }
    }
    
    private func enterDistractionRemovalMode(webView: WKWebView) async {
        guard await ensureScriptsInjected(webView: webView) else { return }

        do {
            // First inject the distraction removal functionality
            let distractionRemovalJS = iTermBrowserTemplateLoader.loadTemplate(named: "distraction-removal",
                                                                             type: "js",
                                                                             substitutions: [:])
            try await webView.evaluateJavaScript(distractionRemovalJS)
            
            // Then enter distraction removal mode
            let script = iTermBrowserTemplateLoader.loadTemplate(named: "enter-distraction-removal",
                                                               type: "js",
                                                               substitutions: [:])
            if let result = try await webView.evaluateJavaScript(script) as? Bool,
               result {
                await updateDistractionRemovalState(true)
            }
        } catch {
            DLog("Error entering distraction removal mode: \(error)")
        }
    }
    
    private func exitDistractionRemovalMode(webView: WKWebView) async {
        do {
            let script = iTermBrowserTemplateLoader.loadTemplate(named: "exit-distraction-removal",
                                                               type: "js",
                                                               substitutions: [:])
            try await webView.evaluateJavaScript(script)
            await updateDistractionRemovalState(false)
        } catch {
            DLog("Error exiting distraction removal mode: \(error)")
        }
    }

    @MainActor
    private func ensureScriptsInjected(webView: WKWebView) async -> Bool {
        if scriptsInjected {
            return true
        }
        
        let readabilityJS = iTermBrowserTemplateLoader.loadTemplate(named: "Readability",
                                                                   type: "js",
                                                                   substitutions: [:])
        let readerModeCSS = iTermBrowserTemplateLoader.loadTemplate(named: "reader-mode",
                                                                    type: "css",
                                                                    substitutions: [:])
        let readerModeJS = iTermBrowserTemplateLoader.loadTemplate(named: "reader-mode-with-styles",
                                                                  type: "js",
                                                                  substitutions: ["READER_MODE_CSS": readerModeCSS])
        
        let loadReadabilityScript = iTermBrowserTemplateLoader.loadTemplate(named: "load-readability",
                                                                           type: "js",
                                                                           substitutions: ["READABILITY_JS": readabilityJS])
        let loadReaderModeScript = iTermBrowserTemplateLoader.loadTemplate(named: "load-reader-mode",
                                                                          type: "js",
                                                                          substitutions: ["READER_MODE_JS": readerModeJS])
        
        do {
            // Inject Readability.js first
            try await webView.evaluateJavaScript(loadReadabilityScript)
            
            // Then inject reader mode script
            try await webView.evaluateJavaScript(loadReaderModeScript)
            
            scriptsInjected = true
            return true
        } catch {
            DLog("Error injecting reader mode scripts: \(error)")
            return false
        }
    }
    
    @MainActor
    private func updateReaderModeState(_ isActive: Bool) {
        isReaderModeActive = isActive
        delegate?.readerModeManager(self, didChangeActiveState: isActive)
    }
    
    @MainActor
    private func updateDistractionRemovalState(_ isActive: Bool) {
        isDistractionRemovalActive = isActive
        delegate?.readerModeManager(self, didChangeDistractionRemovalState: isActive)
    }
    
    // Called when navigation occurs to reset state
    @objc func resetForNavigation() {
        cached = nil
        isReaderModeActive = false
        isDistractionRemovalActive = false
        scriptsInjected = false
    }
}

// MARK: - WKScriptMessageHandler

@available(macOS 11.0, *)
extension iTermBrowserReaderModeManager: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "readerMode",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }
        
        Task { @MainActor in
            switch action {
            case "entered":
                updateReaderModeState(true)
            case "exited":
                updateReaderModeState(false)
            case "distractionRemovalEntered":
                updateDistractionRemovalState(true)
            case "distractionRemovalExited":
                updateDistractionRemovalState(false)
            default:
                break
            }
        }
    }
}
