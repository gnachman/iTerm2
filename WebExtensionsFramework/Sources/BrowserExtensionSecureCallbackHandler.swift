import Foundation
import WebKit

/// Secure callback handler that manages callback dispatch without exposing internals to page scripts
class BrowserExtensionSecureCallbackHandler {
    private let logger: BrowserExtensionLogger
    private let function: Function

    enum Function: String {
        case invokeCallback = "window.__EXT_invokeCallback__"
        case invokeListener = "window.__EXT_invokeListener__"
    }

    init(logger: BrowserExtensionLogger,
         function: Function) {
        self.logger = logger
        self.function = function
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
    private func invokeCallback(requestId: String,
                                result: Any?,
                                error: Error?,
                                in webView: WKWebView?) {
        logger.info("Invoking secure callback for request: \(requestId)\(error != nil ? " with error" : "")")
        
        // Encode result if present
        let resultString: String
        if let result {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed])
                resultString = String(data: jsonData, encoding: .utf8) ?? "null"
            } catch {
                logger.error("Failed to encode result to JSON for request \(requestId): \(error)")
                return
            }
        } else {
            resultString = "null"
        }
        
        // Encode error if present
        let errorString: String
        if let error {
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
            \(function.rawValue)('\(requestId)', \(resultString), \(errorString));
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


