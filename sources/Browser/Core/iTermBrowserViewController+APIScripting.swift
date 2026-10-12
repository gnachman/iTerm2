//
//  iTermBrowserViewController+APIScripting.swift
//  iTerm2
//
//  Lets the Python API run JavaScript in a browser session's page (iterm2.browser_eval_js).
//
//  Origins come from the page itself (location.origin), never from webView.url. While a
//  navigation is pending, webView.url already names the destination even though the old
//  document, which is where JavaScript would run, is still showing.
//

import WebKit

@MainActor
extension iTermBrowserViewController {
    private static let apiScriptingErrorDomain = "com.iterm2.browser-eval-js"

    // Gets the origin of the document now showing. `pageOrigin` is location.origin
    // verbatim, for comparing against later in the page. `siteOrigin` is the same origin
    // as iTermBrowserScriptingPermissions keys it. Both are nil unless it is an http or
    // https page.
    @objc(fetchAPIScriptingOriginWithCompletion:)
    func fetchAPIScriptingOrigin(completion: @escaping (_ pageOrigin: String?, _ siteOrigin: String?) -> Void) {
        // The default client world is out of the page's reach, though location is
        // unforgeable in any world.
        webView.callAsyncJavaScript("return location.origin",
                                    arguments: [:],
                                    in: nil,
                                    in: .defaultClient) { result in
            guard case .success(let value) = result,
                  let pageOrigin = value as? String,
                  let siteOrigin = iTermBrowserScriptingPermissions.javaScriptOrigin(for: URL(string: pageOrigin)) else {
                DLog("No usable origin: \(result)")
                completion(nil, nil)
                return
            }
            completion(pageOrigin, siteOrigin)
        }
    }

    // Runs `body` as the body of an async function in the page world. On success the
    // completion gets the function's return value encoded as JSON (undefined becomes
    // null). Nothing runs unless the document is still at `expectedPageOrigin` (from
    // fetchAPIScriptingOrigin), since the user approved that origin and the page may have
    // navigated since. The check happens in the page, in the same call that runs `body`,
    // so no navigation can come between them.
    @objc(evaluateJavaScriptFromAPI:expectedPageOrigin:completion:)
    func evaluateJavaScriptFromAPI(_ body: String,
                                   expectedPageOrigin: String,
                                   completion: @escaping (String?, Error?) -> Void) {
        // Exceptions thrown while running are caught here so their messages reach the
        // script. A syntax error in `body` can't be caught this way; it comes back as a
        // WKError, handled below.
        let wrapped = """
            if (location.origin !== __itermExpectedOrigin) {
                return { navigated: true };
            }
            try {
                const __itermResult = await (async () => {
            \(body)
                })();
                return { json: JSON.stringify(__itermResult === undefined ? null : __itermResult) ?? "null" };
            } catch (e) {
                return { error: String(e) };
            }
            """
        webView.callAsyncJavaScript(wrapped,
                                    arguments: ["__itermExpectedOrigin": expectedPageOrigin],
                                    in: nil,
                                    in: .page) { result in
            switch result {
            case .success(let value):
                let dict = value as? [String: Any]
                if let json = dict?["json"] as? String {
                    completion(json, nil)
                } else if let message = dict?["error"] as? String {
                    completion(nil, Self.exceptionError(message: message))
                } else if dict?["navigated"] != nil {
                    DLog("Origin is no longer \(expectedPageOrigin)")
                    completion(nil, Self.apiScriptingError(
                        code: 7,
                        message: String(localized: "BrowserEvalJS.Navigated",
                                        defaultValue: "The page navigated to a different site before the JavaScript could run.",
                                        comment: "Error returned to a script when a browser page changed sites while the user was approving JavaScript")))
                } else {
                    completion(nil, Self.apiScriptingError(
                        code: 9,
                        message: String(localized: "BrowserEvalJS.NoResult",
                                        defaultValue: "The JavaScript did not produce a result.",
                                        comment: "Error returned to a script when JavaScript run in a browser page gave back nothing usable")))
                }
            case .failure(let error):
                completion(nil, Self.apiScriptingError(from: error))
            }
        }
    }

    private static func apiScriptingError(code: Int, message: String) -> NSError {
        return NSError(domain: apiScriptingErrorDomain,
                       code: code,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    // WebKit's own description is just "A JavaScript exception occurred". The useful
    // part (such as what the syntax error was) is in the user info.
    private static func apiScriptingError(from error: Error) -> NSError {
        let nsError = error as NSError
        guard let message = nsError.userInfo["WKJavaScriptExceptionMessage"] as? String else {
            return apiScriptingError(code: 8, message: nsError.localizedDescription)
        }
        return exceptionError(message: message)
    }

    private static func exceptionError(message: String) -> NSError {
        return apiScriptingError(
            code: 8,
            message: String(localized: "BrowserEvalJS.Exception",
                            defaultValue: "JavaScript exception: \(message)",
                            comment: "Error returned to a script when JavaScript it ran in a browser page threw; placeholder is the exception’s message from the browser"))
    }
}
