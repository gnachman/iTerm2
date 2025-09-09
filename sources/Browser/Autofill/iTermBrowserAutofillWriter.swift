import WebKit

@available(macOS 11.0, *)
@MainActor
final class iTermBrowserAutofillWriter {
    private let webView: iTermBrowserWebView
    private let mutex = AsyncMutex()
    
    init(webView: iTermBrowserWebView) {
        self.webView = webView
    }
    
    // Takes an array of field info dictionaries with id, name, and value
    func fillFields(_ fields: [[String: String]]) async {
        await mutex.sync {
            for field in fields {
                guard let value = field["value"] else { continue }
                _ = await fillField(fieldId: field["id"] ?? "",
                                  fieldName: field["name"] ?? "",
                                  value: value)
            }
        }
    }
    
    private func fillField(fieldId: String, fieldName: String, value: String) async -> Bool {
        let js = iTermBrowserTemplateLoader.loadTemplate(
            named: "autofill-write",
            type: "js",
            substitutions: [
                "FIELD_ID": fieldId,
                "FIELD_NAME": fieldName,
                "VALUE": stringified(value)
            ])
        
        do {
            let result = try await webView.safelyEvaluateJavaScript(js, contentWorld: .page)
            return (result as? Bool) ?? false
        } catch {
            DLog("Failed to fill field (id: \(fieldId), name: \(fieldName)): \(error)")
            return false
        }
    }
    
    private func stringified(_ string: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed]),
           let str = String(data: data, encoding: .utf8) {
            return str
        } else {
            return "\"\""
        }
    }
}
