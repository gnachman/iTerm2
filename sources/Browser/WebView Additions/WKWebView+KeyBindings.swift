//
//  WKWebView+KeyBindings.swift
//  iTerm2
//
//  Created by George Nachman on 12/24/24.
//

import WebKit

@available(macOS 11.0, *)
extension WKWebView {
    func performScroll(movement: ScrollMovement) {
        let script: String
        
        switch movement {
        case .end:
            script = "window.scrollTo(0, document.body.scrollHeight);"
        case .home:
            script = "window.scrollTo(0, 0);"
        case .down:
            script = "window.scrollBy(0, 40);"
        case .up:
            script = "window.scrollBy(0, -40);"
        case .pageDown:
            script = "window.scrollBy(0, window.innerHeight);"
        case .pageUp:
            script = "window.scrollBy(0, -window.innerHeight);"
        }
        
        evaluateJavaScript(script) { _, _ in }
    }
    
    func sendText(_ string: String) async {
        // First try JavaScript approach
        let escapedString = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        
        let script = iTermBrowserTemplateLoader.loadTemplate(
            named: "insert-text",
            type: "js",
            substitutions: ["TEXT": escapedString]
        )
        
        do {
            let result = try await evaluateJavaScript(script)
            if let success = result as? Bool, !success {
                await MainActor.run {
                    self.sendTextViaClipboard(string)
                }
            }
        } catch {
            // If JavaScript approach failed, fall back to clipboard hack
            await MainActor.run {
                self.sendTextViaClipboard(string)
            }
        }
    }
    
    private func sendTextViaClipboard(_ string: String) {
        // Save current clipboard content
        let pasteboard = NSPasteboard.general
        let savedTypes = pasteboard.types
        var savedContent: [NSPasteboard.PasteboardType: Any] = [:]
        for type in savedTypes ?? [] {
            savedContent[type] = pasteboard.data(forType: type)
        }
        
        // Put text on clipboard
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        
        // Send paste action to webView
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        
        // Restore clipboard after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pasteboard.clearContents()
            for (type, data) in savedContent {
                if let data = data as? Data {
                    pasteboard.setData(data, forType: type)
                }
            }
        }
    }
    
    func extendSelection(start: Bool, forward: Bool, by unit: PTYTextViewSelectionExtensionUnit) {
        // Skip mark case as requested
        if unit == .mark {
            return
        }
        
        let script: String
        switch unit {
        case .character:
            script = iTermBrowserTemplateLoader.loadTemplate(
                named: "extend-selection-character",
                type: "js",
                substitutions: [
                    "START": start ? "true" : "false",
                    "FORWARD": forward ? "true" : "false"
                ]
            )
            
        case .word:
            script = iTermBrowserTemplateLoader.loadTemplate(
                named: "extend-selection-word",
                type: "js",
                substitutions: [
                    "START": start ? "true" : "false",
                    "FORWARD": forward ? "true" : "false"
                ]
            )
            
        case .bigWord:
            // Vim's W - whitespace delimited words
            script = iTermBrowserTemplateLoader.loadTemplate(
                named: "extend-selection-bigword",
                type: "js",
                substitutions: [
                    "START": start ? "true" : "false",
                    "FORWARD": forward ? "true" : "false"
                ]
            )
            
        case .line:
            script = iTermBrowserTemplateLoader.loadTemplate(
                named: "extend-selection-line",
                type: "js",
                substitutions: [
                    "START": start ? "true" : "false",
                    "FORWARD": forward ? "true" : "false"
                ]
            )
            
        default:
            return
        }
        
        evaluateJavaScript(script) { _, _ in }
    }
    
    func hasSelection() async -> Bool {
        let script = iTermBrowserTemplateLoader.loadTemplate(
            named: "has-selection",
            type: "js"
        )
        
        do {
            let result = try await evaluateJavaScript(script)
            return result as? Bool ?? false
        } catch {
            return false
        }
    }
}
