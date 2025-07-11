import Foundation
import WebKit
import BrowserExtensionShared

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
    ///   - contentWorld: The content world to execute the callback in
    func invokeCallback(requestId: String, result: Any, in webView: WKWebView?, contentWorld: WKContentWorld) {
        invokeCallback(requestId: requestId, result: result, error: nil, in: webView, contentWorld: contentWorld)
    }
    
    /// Securely invoke a callback with an error
    /// - Parameters:
    ///   - requestId: The unique request identifier
    ///   - error: The error that occurred
    ///   - webView: The webview to execute the callback in
    ///   - contentWorld: The content world to execute the callback in
    func invokeCallback(requestId: String, error: Error, in webView: WKWebView?, contentWorld: WKContentWorld) {
        invokeCallback(requestId: requestId, result: nil, error: error, in: webView, contentWorld: contentWorld)
    }

    /// Securely invoke a callback with result and/or error
    /// - Parameters:
    ///   - requestId: The unique request identifier
    ///   - result: The result to pass to the callback (can be nil if error occurred)
    ///   - error: The error that occurred (can be nil if successful)
    ///   - webView: The webview to execute the callback in
    ///   - contentWorld: The content world to execute the callback in
    private func invokeCallback(requestId: String,
                                result: Any?,
                                error: Error?,
                                in webView: WKWebView?,
                                contentWorld: WKContentWorld) {
        logger.debug("SecureCallbackHandler received result: \(result ?? "nil") type: \(type(of: result)) error: \(error?.localizedDescription ?? "nil")")
        
        // The result should already be a serialized BrowserExtensionEncodedValue from the dispatcher
        let resultString: String
        if let result {
            if result as? [String: NoObjectPlaceholder] == ["": NoObjectPlaceholder.instance] {
                resultString = ""
            } else {
                // The dispatcher returns a [String: Any] that represents the encoded value
                logger.debug("SecureCallbackHandler encoding result: \(result)")
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: result, options: [])
                    resultString = String(data: jsonData, encoding: .utf8) ?? "undefined"
                    logger.debug("SecureCallbackHandler JSON string: \(resultString)")
                } catch {
                    logger.error("Failed to serialize encoded result for request \(requestId): \(error)")
                    return
                }
            }
        } else {
            // No result provided (nil) - send undefined
            let encodedValue = BrowserExtensionEncodedValue.undefined
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(encodedValue)
                resultString = String(data: data, encoding: .utf8) ?? "undefined"
            } catch {
                logger.error("Failed to encode undefined result for request \(requestId): \(error)")
                return
            }
        }
        
        // Encode error if present
        let errorString: String
        if let error {
            let errorInfo = BrowserExtensionErrorInfo(from: error)
            do {
                errorString = try errorInfo.toJSONString()
            } catch {
                logger.error("Failed to encode error to JSON for request \(requestId): \(error)")
                return
            }
        } else {
            errorString = "null"
        }
        
        // Call the secure callback function
        let callbackScript = """
            \(function.rawValue)('\(requestId)', \(resultString.asJSONFragment), \(errorString));
        """
        
        webView?.evaluateJavaScript(callbackScript, in: nil, in: contentWorld) { [weak self] result in
            switch result {
            case .success(_):
                self?.logger.info("Successfully invoked secure callback for request: \(requestId)")
            case .failure(let error):
                self?.logger.error("Error invoking secure callback for request \(requestId): \(error)")
            }
        }
    }
}


