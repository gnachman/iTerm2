//
//  iTermBrowserReaderModeManager.swift
//  iTerm2
//
//  Created by George Nachman on 6/24/25.
//

import WebKit

@available(macOS 11.0, *)
@MainActor
@objc protocol iTermBrowserReaderModeManagerDelegate: AnyObject {
    func readerModeManager(_ manager: iTermBrowserReaderModeManager, didChangeActiveState isActive: Bool)
    func readerModeManager(_ manager: iTermBrowserReaderModeManager, didChangeDistractionRemovalState isActive: Bool)
}

@available(macOS 11.0, *)
@objc(iTermBrowserReaderModeManager)
@MainActor
class iTermBrowserReaderModeManager: NSObject {
    weak var delegate: iTermBrowserReaderModeManagerDelegate?
    private var isReaderModeActive = false
    private(set) var isDistractionRemovalActive = false
    private var scriptsInjected = false
    private var cached: String?

    @objc var isActive: Bool {
        return isReaderModeActive
    }
    
    @objc func toggle(webView: iTermBrowserWebView) {
        Task {
            await toggleReaderMode(webView: webView)
        }
    }

    func plainTextContent(webView: iTermBrowserWebView) async -> String? {
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
            let result = try await webView.safelyEvaluateJavaScript(script, contentWorld: .defaultClient)
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

    func markdown(fromContentsOf webView: iTermBrowserWebView, skipChrome: Bool) async throws -> String {
        let turndown = iTermBrowserTemplateLoader.loadTemplate(named: "convert-to-markdown",
                                                               type: "js",
                                                               substitutions: ["SKIP_CHROME": skipChrome ? "true" : "false"])
        return try await webView.safelyEvaluateJavaScript(turndown, contentWorld: .defaultClient) as? String ?? "No content found on page"
    }

    private func toggleReaderMode(webView: iTermBrowserWebView) async {
        if isReaderModeActive {
            await exitReaderMode(webView: webView)
        } else {
            await enterReaderMode(webView: webView)
        }
    }
    
    func enterReaderMode(webView: iTermBrowserWebView) async {
        if isReaderModeActive {
            return
        }
        guard await ensureScriptsInjected(webView: webView) else { return }

        do {
            let script = iTermBrowserTemplateLoader.loadTemplate(named: "enter-reader-mode",
                                                               type: "js",
                                                               substitutions: [:])
            if let result = try await webView.safelyEvaluateJavaScript(script, contentWorld: .defaultClient) as? Bool,
               result {
                updateReaderModeState(true)
            }
        } catch {
            DLog("Error entering reader mode: \(error)")
        }
    }
    
    private func exitReaderMode(webView: iTermBrowserWebView) async {
        do {
            let script = iTermBrowserTemplateLoader.loadTemplate(named: "exit-reader-mode",
                                                               type: "js",
                                                               substitutions: [:])
            _ = try await webView.safelyEvaluateJavaScript(script, contentWorld: .defaultClient)
            updateReaderModeState(false)
        } catch {
            DLog("Error exiting reader mode: \(error)")
        }
    }

    func removeElement(webView: iTermBrowserWebView, at point: NSPoint) {
        Task {
            do {
                let script = iTermBrowserTemplateLoader.loadTemplate(named: "remove-element-at-point",
                                                                     type: "js",
                                                                     substitutions: [
                                                                        "POINT_X": "\(point.x)",
                                                                        "POINT_Y": "\(point.y)"
                                                                     ])
                _ = try await webView.safelyEvaluateJavaScript(script, contentWorld: .defaultClient)
            } catch {
                DLog("Error in removeElement: \(error)")
            }
        }
    }

    func toggleDistractionRemovalMode(webView: iTermBrowserWebView) async {
        if isDistractionRemovalActive {
            await exitDistractionRemovalMode(webView: webView)
        } else {
            await enterDistractionRemovalMode(webView: webView)
        }
    }
    
    private func enterDistractionRemovalMode(webView: iTermBrowserWebView) async {
        guard await ensureScriptsInjected(webView: webView) else { return }

        do {
            // First inject the distraction removal functionality
            let distractionRemovalJS = iTermBrowserTemplateLoader.loadTemplate(named: "distraction-removal",
                                                                             type: "js",
                                                                             substitutions: [:])
            _ = try await webView.safelyEvaluateJavaScript(distractionRemovalJS, contentWorld: .defaultClient)

            // Then enter distraction removal mode
            let script = iTermBrowserTemplateLoader.loadTemplate(named: "enter-distraction-removal",
                                                               type: "js",
                                                               substitutions: [:])
            if let result = try await webView.safelyEvaluateJavaScript(script, contentWorld: .defaultClient) as? Bool,
               result {
                updateDistractionRemovalState(true)
            }
        } catch {
            DLog("Error entering distraction removal mode: \(error)")
        }
    }
    
    private func exitDistractionRemovalMode(webView: iTermBrowserWebView) async {
        do {
            let script = iTermBrowserTemplateLoader.loadTemplate(named: "exit-distraction-removal",
                                                               type: "js",
                                                               substitutions: [:])
            _ = try await webView.safelyEvaluateJavaScript(script, contentWorld: .defaultClient)
            updateDistractionRemovalState(false)
        } catch {
            DLog("Error exiting distraction removal mode: \(error)")
        }
    }

    private func ensureScriptsInjected(webView: iTermBrowserWebView) async -> Bool {
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
            _ = try await webView.safelyEvaluateJavaScript(loadReadabilityScript, contentWorld: .defaultClient)

            // Then inject reader mode script
            _ = try await webView.safelyEvaluateJavaScript(loadReaderModeScript, contentWorld: .defaultClient)

            scriptsInjected = true
            return true
        } catch {
            DLog("Error injecting reader mode scripts: \(error)")
            return false
        }
    }
    
    private func updateReaderModeState(_ isActive: Bool) {
        isReaderModeActive = isActive
        delegate?.readerModeManager(self, didChangeActiveState: isActive)
    }
    
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
@MainActor
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
