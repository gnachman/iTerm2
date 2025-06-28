import Foundation
import WebKit

@available(macOS 11, *)
class iTermBrowserAdblockHandler {
    private let webView: WKWebView
    
    init(webView: WKWebView) {
        self.webView = webView
    }
    
    func applyCosmeticFiltering() {
        guard let url = webView.url else { return }
        
        Task { @MainActor in
            let resources = await iTermBrowserAdblockRustManager.shared.getCosmeticResources(for: url)
            
            // Hide elements using CSS selectors
            if !resources.hideSelectors.isEmpty {
                injectHideCSS(selectors: resources.hideSelectors)
            }
            
            // Inject JavaScript if provided
            if let injectedScript = resources.injectedScript, !injectedScript.isEmpty {
                injectAdblockScript(injectedScript)
            }
        }
    }
    
    private func injectHideCSS(selectors: [String]) {
        let hideCSS = selectors.map { "\($0) { display: none !important; }" }.joined(separator: " ")
        // Replace placeholder with escaped CSS
        let escapedCSS = hideCSS.replacingOccurrences(of: "\\", with: "\\\\")
                               .replacingOccurrences(of: "'", with: "\\'")
                               .replacingOccurrences(of: "\n", with: "\\n")
                               .replacingOccurrences(of: "\r", with: "\\r")

        // Load the CSS injection template
        let javascript = iTermBrowserTemplateLoader.load(template: "adblock-css-injection.js",
                                                         substitutions: ["CSS_CONTENT": escapedCSS])
        Task {
            do {
                _ = try await webView.evaluateJavaScript(javascript)
                DLog("Successfully hid \(selectors.count) elements")
            } catch {
                DLog("Error injecting CSS: \(error)")
                DLog("Failed JavaScript: \(javascript)")
            }
        }
    }
    
    private func injectAdblockScript(_ script: String) {
        Task {
            do {
                _ = try await webView.evaluateJavaScript(script)
                DLog("Successfully injected adblock script")
            } catch {
                DLog("Error injecting adblock script: \(error)")
                DLog("Failed script: \(script.prefix(200))...")
            }
        }
    }
}
