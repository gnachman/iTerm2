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
        invokeCallback(requestId: requestId, result: result, error: nil, in: webView)
    }
    
    /// Securely invoke a callback with an error
    /// - Parameters:
    ///   - requestId: The unique request identifier
    ///   - error: The error that occurred
    ///   - webView: The webview to execute the callback in
    func invokeCallback(requestId: String, error: Error, in webView: WKWebView?) {
        invokeCallback(requestId: requestId, result: nil, error: error, in: webView)
    }
    
    /// Securely invoke a callback with result and/or error
    /// - Parameters:
    ///   - requestId: The unique request identifier
    ///   - result: The result to pass to the callback (can be nil if error occurred)
    ///   - error: The error that occurred (can be nil if successful)
    ///   - webView: The webview to execute the callback in
    private func invokeCallback(requestId: String, result: Any?, error: Error?, in webView: WKWebView?) {
        logger.info("Invoking secure callback for request: \(requestId)\(error != nil ? " with error" : "")")
        
        // Encode result if present
        let resultString: String
        if let result = result {
            do {
                if let stringResult = result as? String {
                    let jsonData = try JSONEncoder().encode(stringResult)
                    resultString = String(data: jsonData, encoding: .utf8) ?? "\"\""
                } else if let dictResult = result as? [String: String] {
                    let jsonData = try JSONEncoder().encode(dictResult)
                    resultString = String(data: jsonData, encoding: .utf8) ?? "{}"
                } else {
                    // Fallback to JSONSerialization for other types
                    let jsonData = try JSONSerialization.data(withJSONObject: result)
                    resultString = String(data: jsonData, encoding: .utf8) ?? "null"
                }
            } catch {
                logger.error("Failed to encode result to JSON for request \(requestId): \(error)")
                return
            }
        } else {
            resultString = "null"
        }
        
        // Encode error if present
        let errorString: String
        if let error = error {
            let errorInfo = BrowserExtensionErrorInfo(from: error)
            do {
                let jsonData = try JSONEncoder().encode(errorInfo)
                errorString = String(data: jsonData, encoding: .utf8) ?? "null"
            } catch {
                logger.error("Failed to encode error to JSON for request \(requestId): \(error)")
                return
            }
        } else {
            errorString = "null"
        }
        
        // Call the secure callback function
        let callbackScript = """
            window.__EXT_invokeCallback__('\(requestId)', \(resultString), \(errorString));
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


