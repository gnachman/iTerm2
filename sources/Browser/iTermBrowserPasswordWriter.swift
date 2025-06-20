//
//  iTermBrowserPasswordWriter.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

import WebKit

@available(macOS 11.0, *)
final class iTermBrowserPasswordWriter {
    private let webView: WKWebView
    private let password: String

    init(webView: WKWebView, password: String) {
        self.webView = webView
        self.password = password
    }

    @MainActor
    func fillPassword() async throws -> Bool {
        switch await probe() {
        case .notAnInput:
            return false
        case .unsafe:
            if !confirm() {
                return false
            }
            return await write(wasPassword: false)
        case .safe:
            return await write(wasPassword: true)
        }
    }

    private func stringified(password: String) -> String {
        let pwLiteral: String
        if
            let data = try? JSONSerialization.data(withJSONObject: password, options: [.fragmentsAllowed]),
            let str = String(data: data, encoding: .utf8) {
            return str
        } else {
            return "\"\""
        }
    }

    private enum ProbeResult {
        case notAnInput
        case unsafe
        case safe
    }

    private func probe() async -> ProbeResult {
        let js = iTermBrowserTemplateLoader.loadTemplate(named: "probe-password",
                                                         type: "js",
                                                         substitutions: [:])


        let anyResult = try? await webView.evaluateJavaScript(js)
        guard let info = anyResult as? [String: Any],
              let found = info["found"] as? Bool else {
            return .notAnInput
        }
        if !found {
            return .notAnInput
        }
        if info["isPassword"] as? Bool != true || info["visible"] as? Bool != true {
            return .unsafe
        }
        return .safe
    }

    private func confirm() -> Bool {
        let message = "The focused field is not a password field. Fill it anyway?"
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func write(wasPassword: Bool) async -> Bool {
        let passwordLiteral = stringified(password: password)
        let js = iTermBrowserTemplateLoader.loadTemplate(named: "write-password",
                                                         type: "js",
                                                         substitutions: ["PASSWORD": passwordLiteral,
                                                                         "REQUIRE_SECURE": wasPassword ? "true" : "false"])

        do {
            _ = try await webView.evaluateJavaScript(js)
            return true
        } catch {
            return false
        }
    }
}
