import Foundation
import WebKit

@MainActor
protocol iTermBrowserAutofillHandlerDelegate: AnyObject {
    func autoFillHandler(_ handler: iTermBrowserAutofillHandler,
                         requestAutofillForHost host: String,
                         fields: [[String: Any]])
}

@MainActor
class iTermBrowserAutofillHandler {
    static let messageHandlerName = "iTermAutofillHandler"
    
    weak var delegate: iTermBrowserAutofillHandlerDelegate?
    
    private let sessionSecret: String
    private var pendingAutofillWebView: iTermBrowserWebView?
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
    
    func handleMessage(webView: iTermBrowserWebView, message: WKScriptMessage) -> AutofillAction? {
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
    
    private func handleAutofillRequest(webView: iTermBrowserWebView, body: [String: Any]) {
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

    func fillAll(webView: iTermBrowserWebView) async {
        DLog("fillAll() method called")
        
        // Create JavaScript that rediscovers autofillable fields and fills them all
        let js = iTermBrowserTemplateLoader.loadTemplate(
            named: "autofill-fill-all",
            type: "js", 
            substitutions: ["SECRET": sessionSecret])
        
        DLog("fillAll() loaded JavaScript template, length: \(js.count)")
        
        do {
            let result = try await webView.safelyEvaluateJavaScript(js, contentWorld: .defaultClient)
            if let resultDict = result as? [String: Any],
               let success = resultDict["success"] as? Bool,
               let fieldsFound = resultDict["fieldsFound"] as? Int {
                if success {
                    DLog("fillAll successfully found and triggered autofill for \(fieldsFound) fields")
                } else {
                    DLog("fillAll failed - authentication or other error")
                }
            }
        } catch {
            DLog("fillAll failed: \(error)")
        }
    }
}
