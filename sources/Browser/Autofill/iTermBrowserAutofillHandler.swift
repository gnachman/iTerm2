import Foundation
import WebKit

@available(macOS 11.0, *)
@MainActor
protocol iTermBrowserAutofillHandlerDelegate: AnyObject {
    func autoFillHandler(_ handler: iTermBrowserAutofillHandler,
                         requestAutofillForHost host: String,
                         fields: [[String: Any]])
}

@available(macOS 11.0, *)
@MainActor
class iTermBrowserAutofillHandler {
    static let messageHandlerName = "iTermAutofillHandler"
    
    weak var delegate: iTermBrowserAutofillHandlerDelegate?
    
    private let sessionSecret: String
    private var pendingAutofillWebView: WKWebView?
    private let contactSource = iTermBrowserAutofillContactSource()
    
    init?() {
        guard let secret = String.makeSecureHexString() else {
            return nil
        }
        self.sessionSecret = secret
    }
    
    var javascript: String {
        return iTermBrowserTemplateLoader.loadTemplate(
            named: "autofill-detector",
            type: "js",
            substitutions: ["SECRET": sessionSecret])
    }
    
    enum AutofillAction: String {
        case autofillRequest
    }
    
    func handleMessage(webView: WKWebView, message: WKScriptMessage) -> AutofillAction? {
        guard let body = message.body as? [String: Any],
              let secret = body["sessionSecret"] as? String,
              secret == sessionSecret,
              let typeString = body["type"] as? String,
              let action = AutofillAction(rawValue: typeString) else {
            return nil
        }
        
        switch action {
        case .autofillRequest:
            handleAutofillRequest(webView: webView, body: body)
        }
        
        return action
    }
    
    private func handleAutofillRequest(webView: WKWebView, body: [String: Any]) {
        guard body["activeField"] as? [String: Any] != nil,
              let fields = body["fields"] as? [[String: Any]] else {
            return
        }
        
        pendingAutofillWebView = webView
        
        let host = webView.url?.host ?? "unknown"
        delegate?.autoFillHandler(self,
                                  requestAutofillForHost: host,
                                  fields: fields)
    }
    
    func fillFields(_ fields: [[String: String]]) async {
        guard let webView = pendingAutofillWebView else { return }
        
        let writer = iTermBrowserAutofillWriter(webView: webView)
        await writer.fillFields(fields)
    }
}
