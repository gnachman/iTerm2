import Foundation
import WebKit

/// Secure callback handler that manages callback dispatch without exposing internals to page scripts
class BrowserExtensionSecureCallbackHandler {
    
    private let logger: BrowserExtensionLogger
    
    init(logger: BrowserExtensionLogger) {
        self.logger = logger
    }
    
    /// Securely invoke a callback with the given result
    /// - Parameters:
    ///   - requestId: The unique request identifier
    ///   - result: The result to pass to the callback
    ///   - webView: The webview to execute the callback in
    func invokeCallback(requestId: String, result: Any, in webView: WKWebView?) {
        logger.info("Invoking secure callback for request: \(requestId)")
        
        // Use JSONEncoder to safely encode any type
        let jsonString: String
        do {
            if let stringResult = result as? String {
                let jsonData = try JSONEncoder().encode(stringResult)
                jsonString = String(data: jsonData, encoding: .utf8) ?? "\"\""
            } else if let dictResult = result as? [String: String] {
                let jsonData = try JSONEncoder().encode(dictResult)
                jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            } else {
                // Fallback to JSONSerialization for other types
                let jsonData = try JSONSerialization.data(withJSONObject: result)
                jsonString = String(data: jsonData, encoding: .utf8) ?? "null"
            }
        } catch {
            logger.error("Failed to encode result to JSON for request \(requestId): \(error)")
            return
        }
        
        // Call the secure callback function
        let callbackScript = """
            window.__EXT_invokeCallback__('\(requestId)', \(jsonString));
        """
        
        webView?.evaluateJavaScript(callbackScript) { [weak self] _, error in
            if let error = error {
                self?.logger.error("Error invoking secure callback for request \(requestId): \(error)")
            } else {
                self?.logger.info("Successfully invoked secure callback for request: \(requestId)")
            }
        }
    }
}


