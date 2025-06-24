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
}

@available(macOS 11.0, *)
@objc(iTermBrowserReaderModeManager)
class iTermBrowserReaderModeManager: NSObject {
    weak var delegate: iTermBrowserReaderModeManagerDelegate?
    private weak var webView: WKWebView?
    private var isReaderModeActive = false
    private var scriptsInjected = false
    
    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        setupMessageHandler()
    }
    
    private func setupMessageHandler() {
        guard let webView = webView else { return }
        
        let userContentController = webView.configuration.userContentController
        userContentController.add(self, name: "readerMode")
    }
    
    @objc var isActive: Bool {
        return isReaderModeActive
    }
    
    @objc func toggle() {
        Task {
            await toggleReaderMode()
        }
    }
    
    private func toggleReaderMode() async {
        if isReaderModeActive {
            await exitReaderMode()
        } else {
            await enterReaderMode()
        }
    }
    
    private func enterReaderMode() async {
        guard await ensureScriptsInjected() else { return }
        
        do {
            let script = iTermBrowserTemplateLoader.loadTemplate(named: "enter-reader-mode",
                                                               type: "js",
                                                               substitutions: [:])
            if let result = try await webView?.evaluateJavaScript(script) as? Bool,
               result {
                await updateReaderModeState(true)
            }
        } catch {
            print("Error entering reader mode: \(error)")
        }
    }
    
    private func exitReaderMode() async {
        do {
            let script = iTermBrowserTemplateLoader.loadTemplate(named: "exit-reader-mode",
                                                               type: "js",
                                                               substitutions: [:])
            try await webView?.evaluateJavaScript(script)
            await updateReaderModeState(false)
        } catch {
            print("Error exiting reader mode: \(error)")
        }
    }
    
    private func ensureScriptsInjected() async -> Bool {
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
            try await webView?.evaluateJavaScript(loadReadabilityScript)
            
            // Then inject reader mode script
            try await webView?.evaluateJavaScript(loadReaderModeScript)
            
            scriptsInjected = true
            return true
        } catch {
            print("Error injecting reader mode scripts: \(error)")
            return false
        }
    }
    
    @MainActor
    private func updateReaderModeState(_ isActive: Bool) {
        isReaderModeActive = isActive
        delegate?.readerModeManager(self, didChangeActiveState: isActive)
    }
    
    // Called when navigation occurs to reset state
    @objc func resetForNavigation() {
        isReaderModeActive = false
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
            default:
                break
            }
        }
    }
}