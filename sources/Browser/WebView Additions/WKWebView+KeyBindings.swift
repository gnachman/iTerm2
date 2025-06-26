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

    func extendSelection(toPointInWindow point: NSPoint) {
        let pointInView = self.convert(point, from: nil)
        
        // Scale from view coordinates to JavaScript client coordinates
        // Account for both pageZoom and magnification
        let baseJSX = pointInView.x / self.pageZoom
        let baseJSY = pointInView.y / self.pageZoom
        
        // When magnified, we need to scale down by magnification
        let jsX = baseJSX / self.magnification
        let jsY = baseJSY / self.magnification
        
        let script = iTermBrowserTemplateLoader.loadTemplate(
            named: "extend-selection-to-point",
            type: "js",
            substitutions: [
                "X": "\(jsX)",
                "Y": "\(jsY)"
            ]
        )
        
        evaluateJavaScript(script) { _, _ in }
    }

    @MainActor
    func openLink(atPointInWindow point: NSPoint,
                  inNewTab: Bool) {
        Task {
            let pointInView = self.convert(point, from: nil)
            
            // Scale from view coordinates to JavaScript client coordinates
            // Account for both pageZoom and magnification
            let baseJSX = pointInView.x / self.pageZoom
            let baseJSY = pointInView.y / self.pageZoom
            let jsX = baseJSX / self.magnification
            let jsY = baseJSY / self.magnification
            
            let script = iTermBrowserTemplateLoader.loadTemplate(
                named: "open-link-at-point",
                type: "js",
                substitutions: [
                    "X": "\(jsX)",
                    "Y": "\(jsY)"
                ]
            )
            
            guard let result = try? await evaluateJavaScript(script),
                  let linkInfo = result as? [String: Any],
                  let urlString = linkInfo["url"] as? String,
                  let url = URL(string: urlString) else {
                return
            }
            
            await MainActor.run {
                if inNewTab {
                    // Find the delegate through the responder chain
                    var responder: NSResponder? = self
                    while let r = responder {
                        if let viewController = r as? iTermBrowserViewController {
                            viewController.delegate?.browserViewController(viewController,
                                                                          openNewTabForURL: url)
                            break
                        }
                        responder = r.nextResponder
                    }
                } else {
                    self.load(URLRequest(url: url))
                }
            }
        }
    }

    @MainActor
    private func text(atPointInWindow point: NSPoint,
                      radius: Int) async -> (String, String) {
        let pointInView = self.convert(point, from: nil)
        
        // Scale from view coordinates to JavaScript client coordinates
        // Account for both pageZoom and magnification
        let baseJSX = pointInView.x / self.pageZoom
        let baseJSY = pointInView.y / self.pageZoom
        let jsX = baseJSX / self.magnification
        let jsY = baseJSY / self.magnification
        
        let script = iTermBrowserTemplateLoader.loadTemplate(
            named: "extract-text-at-point",
            type: "js",
            substitutions: [
                "X": "\(jsX)",
                "Y": "\(jsY)",
                "RADIUS": String(radius)
            ]
        )
        
        guard let result = try? await evaluateJavaScript(script),
              let textInfo = result as? [String: Any],
              let beforeText = textInfo["before"] as? String,
              let afterText = textInfo["after"] as? String else {
            return ("", "")
        }
        
        return (beforeText, afterText)
    }

    @MainActor
    func performSmartSelection(atPointInWindow point: NSPoint,
                               rules: [SmartSelectRule]) async {
        guard let match = await firstMatch(atPointInWindow: point, rules: rules) else {
            return
        }
        
        let pointInView = self.convert(point, from: nil)
        
        // Scale from view coordinates to JavaScript client coordinates
        // Account for both pageZoom and magnification
        let baseJSX = pointInView.x / self.pageZoom
        let baseJSY = pointInView.y / self.pageZoom
        let jsX = baseJSX / self.magnification
        let jsY = baseJSY / self.magnification
        
        let script = iTermBrowserTemplateLoader.loadTemplate(
            named: "select-text",
            type: "js",
            substitutions: [
                "X": "\(jsX)",
                "Y": "\(jsY)",
                "BEFORE_COUNT": String(match.beforeCount),
                "AFTER_COUNT": String(match.afterCount)
            ]
        )
        
        _ = try? await evaluateJavaScript(script)
    }

    @MainActor
    func urls(atPointInWindow point: NSPoint) async -> [URL] {
        let pointInView = self.convert(point, from: nil)
        
        // Scale from view coordinates to JavaScript client coordinates
        // Account for both pageZoom and magnification
        let baseJSX = pointInView.x / self.pageZoom
        let baseJSY = pointInView.y / self.pageZoom
        let jsX = baseJSX / self.magnification
        let jsY = baseJSY / self.magnification
        
        let script = iTermBrowserTemplateLoader.loadTemplate(
            named: "urls-at-point",
            type: "js",
            substitutions: [
                "X": "\(jsX)",
                "Y": "\(jsY)"
            ]
        )
        
        guard let result = try? await evaluateJavaScript(script),
              let urlStrings = result as? [String] else {
            return []
        }
        
        return urlStrings.compactMap { URL(string: $0) }
    }

    struct SmartMatch {
        var beforeCount: Int
        var afterCount: Int
        var rule: SmartSelectRule
        var components: [String]
        var score: Double
    }
    func firstMatch(atPointInWindow point: NSPoint,
                    rules: [SmartSelectRule]) async -> SmartMatch? {
        // Number of lines above and below the location to include in the search
        var matches = [String: SmartMatch]()
        let radius = Int(iTermAdvancedSettingsModel.smartSelectionRadius())
        let (before, after) = await text(atPointInWindow: point, radius: radius)
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.regex) else {
                continue
            }
            var startOffset = 0
            while startOffset < before.utf16.count {
                let substring = before[utf16: startOffset...] + after
                let fullRange = NSRange(location: 0,
                                        length: substring.utf16.count)
                let result = regex.firstMatch(in: String(substring),
                                              range: fullRange)
                if let result {
                    let matchingRange = result.range(at: 0)
                    let matchingText = String(substring)[utf16: matchingRange]
                    let score = rule.weight * Double(matchingText.utf16.count)
                    let beforeCount = before.utf16.count - matchingRange.lowerBound
                    if beforeCount > 0 {
                        if (matches[matchingText]?.score ?? 0) < score {
                            let components = (1..<result.numberOfRanges).map { i in
                                let range = result.range(at: i)
                                return String(substring)[utf16: range]
                            }
                            matches[matchingText] = SmartMatch(
                                beforeCount: beforeCount,
                                afterCount: matchingRange.length - beforeCount,
                                rule: rule,
                                components: components,
                                score: score)
                        }
                        startOffset = matchingRange.upperBound - 1
                    } else {
                        startOffset += matchingRange.lowerBound
                    }
                } else {
                    break
                }
            }
        }
        return matches.values.max { lhs, rhs in
            lhs.score < rhs.score
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
