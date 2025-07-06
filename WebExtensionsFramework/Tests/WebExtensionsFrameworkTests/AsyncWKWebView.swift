import WebKit
import XCTest

enum NavigationError: Error {
    case loadFailed
}

class AsyncWKWebView: WKWebView, WKNavigationDelegate {
    private var continuations = [ObjectIdentifier: CheckedContinuation<Void, Error>]()

    override init(frame: CGRect = .zero, configuration: WKWebViewConfiguration = WKWebViewConfiguration()) {
        super.init(frame: frame, configuration: configuration)
        navigationDelegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        navigationDelegate = self
    }

    func loadHTMLStringAsync(_ string: String, baseURL: URL?) async throws {
        guard let nav = loadHTMLString(string, baseURL: baseURL) else {
            throw NavigationError.loadFailed
        }
        try await waitFor(nav)
    }

    private func waitFor(_ navigation: WKNavigation) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let key = ObjectIdentifier(navigation)
            continuations[key] = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let navigation = navigation else { return }
        let key = ObjectIdentifier(navigation)
        guard let cont = continuations[key] else { return }
        cont.resume()
        continuations.removeValue(forKey: key)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard let navigation = navigation else { return }
        let key = ObjectIdentifier(navigation)
        guard let cont = continuations[key] else { return }
        cont.resume(throwing: error)
        continuations.removeValue(forKey: key)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard let navigation = navigation else { return }
        let key = ObjectIdentifier(navigation)
        guard let cont = continuations[key] else { return }
        cont.resume(throwing: error)
        continuations.removeValue(forKey: key)
    }
}