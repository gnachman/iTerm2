//
//  iTermBrowserErrorHandler.swift
//  iTerm2
//
//  Created by George Nachman on 6/18/25.
//

import Foundation
@preconcurrency import WebKit

@available(macOS 11.0, *)
@objc(iTermBrowserErrorHandler)
class iTermBrowserErrorHandler: NSObject, iTermBrowserPageHandler {
    private var pendingErrorHTML: String?
    
    static let errorURL = URL(string: "\(iTermBrowserSchemes.about):error")!
    
    // MARK: - Public Interface
    
    func generateErrorPageHTML(for error: Error, failedURL: URL?) -> String {
        let (title, message) = errorTitleAndMessage(for: error)
        return generateErrorHTML(title: title, message: message, originalURL: failedURL?.absoluteString)
    }
    
    func setPendingErrorHTML(_ html: String) {
        pendingErrorHTML = html
    }
    
    func consumePendingErrorHTML() -> String? {
        let html = pendingErrorHTML
        pendingErrorHTML = nil
        return html
    }
    
    func hasPendingError() -> Bool {
        return pendingErrorHTML != nil
    }
    
    func clearPendingError() {
        pendingErrorHTML = nil
    }
    
    // MARK: - iTermBrowserPageHandler Protocol
    
    func injectJavaScript(into webView: iTermBrowserWebView) {
        // Error pages don't need JavaScript injection
    }
    
    func resetState() {
        clearPendingError()
    }

    func start(urlSchemeTask: WKURLSchemeTask, url: URL) {
        // Serve our error page HTML
        let htmlToServe = consumePendingErrorHTML() ?? generateErrorPageHTML(
            for: NSError(domain: NSURLErrorDomain, code: NSURLErrorResourceUnavailable, userInfo: [NSLocalizedDescriptionKey: "Page Not Available"]),
            failedURL: nil
        )

        guard let data = htmlToServe.data(using: .utf8) else {
            urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode HTML"]))
            return
        }

        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    // MARK: - Error Page Generation
    
    private func generateErrorHTML(title: String, message: String, originalURL: String?) -> String {
        let urlDisplay = originalURL ?? ""
        let urlDisplayHTML = urlDisplay.isEmpty ? "" : "<div class=\"error-url\">\(urlDisplay)</div>"
        
        let substitutions = [
            "TITLE": title,
            "MESSAGE": message,
            "URL_DISPLAY": urlDisplayHTML,
            "ORIGINAL_URL": originalURL ?? ""
        ]
        
        return iTermBrowserTemplateLoader.loadTemplate(named: "error-page",
                                                       type: "html",
                                                       substitutions: substitutions)
    }
    
    private func errorTitleAndMessage(for error: Error) -> (title: String, message: String) {
        let nsError = error as NSError

        let tuple: (String, String, String?) = {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return ("No Internet Connection", "Your computer appears to be offline. Check your internet connection and try again.", nil)

            case NSURLErrorCannotFindHost:
                return ("Server Not Found", "iTerm2 can’t find the server. Check that the web address is correct and try again.", nil)

            case NSURLErrorTimedOut:
                return ("The Connection Timed Out", "The server didn’t respond in time. The site may be temporarily unavailable or overloaded.", nil)

            case NSURLErrorCannotConnectToHost:
                return ("Can’t Connect to Server", "iTerm2 can’t establish a secure connection to the server. The server may be down or unreachable.", nil)

            case NSURLErrorNetworkConnectionLost:
                return ("Network Connection Lost", "The network connection was lost. Check your internet connection and try again.", nil)

            case NSURLErrorDNSLookupFailed:
                return ("Server Not Found", "The server’s DNS address could not be found. Check that the web address is correct.", nil)

            case NSURLErrorHTTPTooManyRedirects:
                return ("Too Many Redirects", "iTerm2 can’t open the page because the server redirected too many times.", nil)

            case NSURLErrorResourceUnavailable:
                return ("Page Unavailable", "The requested page is currently unavailable. Try again later.", nil)

            case NSURLErrorNotConnectedToInternet:
                return ("No Internet Connection", "Your computer is not connected to the internet. Check your connection and try again.", nil)

            case NSURLErrorServerCertificateUntrusted, NSURLErrorSecureConnectionFailed:
                return ("Secure Connection Failed", "iTerm2 can’t verify the identity of the website. The connection may not be secure.", sslErrorDetails(from: error))

            default:
                return ("Page Can’t Be Loaded", "An error occurred while loading this page. \(error.localizedDescription)", nil)
            }
        }()
        return (title: tuple.0,
                message: "<strong>" + tuple.1 + "</strong><br/><br/>" + (tuple.2 ?? error.localizedDescription))
    }
}

/// Returns a detailed TLS/SSL error message if `error` is an SSL-related NSURLError.
func sslErrorDetails(from error: Error) -> String? {
    let ns = error as NSError
    if ns.domain != NSURLErrorDomain {
        return nil
    }
    // Common TLS/SSL URL error codes
    let sslURLCodes: Set<Int> = [
        URLError.serverCertificateUntrusted.rawValue,
        URLError.serverCertificateHasBadDate.rawValue,
        URLError.serverCertificateHasUnknownRoot.rawValue,
        URLError.serverCertificateNotYetValid.rawValue,
        URLError.clientCertificateRejected.rawValue,
        URLError.clientCertificateRequired.rawValue
    ]
    if !sslURLCodes.contains(ns.code) {
        return nil
    }

    var lines: [String] = []

    if let os = ns.userInfo["_kCFStreamErrorCodeKey"] as? Int,
       let description = sslErrorDescription(for: os) {
        lines.append(description.escapedForHTML)
    }

    // Extract SecTrust safely from userInfo (NSURLErrorFailingURLPeerTrustErrorKey)
    if let trust = secTrust(fromUserInfo: ns.userInfo) {
        // Certificate chain subjects
        let subjects = certificateSubjects(from: trust)
        if !subjects.isEmpty {
            lines.append("Certificate chain:")
            for (idx, s) in subjects.enumerated() {
                lines.append("  [\(idx)] \(s.escapedForHTML)")
            }
        }
    }

    return lines.joined(separator: "<br/>\n")
}

/// Robustly extract SecTrust from NSError.userInfo, handling CF bridging.
private func secTrust(fromUserInfo ui: [String: Any]) -> SecTrust? {
    guard let any = ui[NSURLErrorFailingURLPeerTrustErrorKey] else {
        return nil
    }
    // Work through CFTypeRef to avoid “AnyObject is not convertible to SecTrust”
    let cf = any as CFTypeRef
    if CFGetTypeID(cf) == SecTrustGetTypeID() {
        return (cf as! SecTrust)
    }
    return nil
}

/// Map SecureTransport OSStatus to a readable name and a short hint.
private func sslErrorDescription(for status: Int) -> String? {
    // Subset of the most useful SSL codes you’ll actually see.
    switch OSStatus(status) {
    case errSSLXCertChainInvalid:        return "The presented chain is not valid (e.g., self-signed without trust)."
    case errSSLUnknownRootCert:          return "The root CA is unknown (not in trust store)."
    case errSSLNoRootCert:               return "No root certificate found to anchor the chain."
    case errSSLBadCert:                  return "The certificate is malformed or otherwise bad."
    case errSSLCertExpired:              return "The certificate is expired."
    case errSSLCertNotYetValid:          return "The certificate is not yet valid."
    case errSSLHostNameMismatch:         return "The hostname does not match the certificate."
    default:                             return SecCopyErrorMessageString(OSStatus(status), nil) as? String
    }
}

/// Get human-friendly subject summaries for the chain.
private func certificateSubjects(from trust: SecTrust) -> [String] {
    if #available(macOS 10.15, *) {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
            return []
        }
        return chain.compactMap { SecCertificateCopySubjectSummary($0) as String? }
    } else {
        var out: [String] = []
        let count = SecTrustGetCertificateCount(trust)
        if count <= 0 {
            return out
        }
        for i in 0..<count {
            if let cert = SecTrustGetCertificateAtIndex(trust, i) {
                if let s = SecCertificateCopySubjectSummary(cert) as String? {
                    out.append(s)
                } else {
                    out.append("(no subject summary)")
                }
            }
        }
        return out
    }
}
