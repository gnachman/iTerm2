//
//  iTermBrowserPasswordWriter.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

import WebKit

@available(macOS 11.0, *)
final class iTermBrowserPasswordWriter {
    private let mutex = AsyncMutex()

    @MainActor
    func fillPassword(webView: iTermBrowserWebView, password: String) async throws -> Bool {
        return await mutex.sync {
            switch await probe(webView: webView) {
            case .notAnInput:
                return false
            case .unsafe:
                if !confirm() {
                    return false
                }
                return await write(webView: webView,
                                   requireSecure: false,
                                   string: password,
                                   autofocusNextPasswordField: false)
            case .safe:
                return await write(
                    webView: webView,
                    requireSecure: true,
                    string: password,
                    autofocusNextPasswordField: false)
            }
        }
    }

    @MainActor
    func fillUsername(webView: iTermBrowserWebView,
                      username: String) async throws -> Bool {
        return await mutex.sync {
            return await write(webView: webView,
                               requireSecure: false,
                               string: username,
                               autofocusNextPasswordField: true)
        }
    }

    @MainActor
    func focus(webView: iTermBrowserWebView,
               id: String) async -> Bool {
        let js = iTermBrowserTemplateLoader.loadTemplate(
            named: "focus-password",
            type: "js",
            substitutions: ["ID": id])

        return await mutex.sync {
            do {
                _ = try await webView.safelyEvaluateJavaScript(js)
                return true
            } catch {
                return false
            }
        }
    }
}

@available(macOS 11, *)
private extension iTermBrowserPasswordWriter {
    private func stringified(password: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: password, options: [.fragmentsAllowed]),
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

    private func probe(webView: iTermBrowserWebView) async -> ProbeResult {
        let js = iTermBrowserTemplateLoader.loadTemplate(named: "probe-password",
                                                         type: "js",
                                                         substitutions: [:])


        let anyResult = try? await webView.safelyEvaluateJavaScript(js)
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

    private func write(webView: iTermBrowserWebView,
                       requireSecure: Bool,
                       string: String,
                       autofocusNextPasswordField: Bool) async -> Bool {
        let focusNextPw = autofocusNextPasswordField
        let literal = stringified(password: string)
        let js = iTermBrowserTemplateLoader.loadTemplate(
            named: "write-password",
            type: "js",
            substitutions: ["STRING": literal,
                            "REQUIRE_SECURE": requireSecure ? "true" : "false",
                            "FOCUS_NEXT_PW": focusNextPw ? "true" : "false"])

        do {
            _ = try await webView.safelyEvaluateJavaScript(js)
            return true
        } catch {
            return false
        }
    }
}
