//
//  iTermBrowserErrorHandler.swift
//  iTerm2
//
//  Created by George Nachman on 6/18/25.
//

import Foundation
@preconcurrency import WebKit

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
            // Localization unneeded
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
                return (String(localized: "BrowserErrorHandler.NoInternetTitle", defaultValue: "No Internet Connection", comment: "Error title: no internet connection"), String(localized: "BrowserErrorHandler.NoInternetOfflineMessage", defaultValue: "Your computer appears to be offline. Check your internet connection and try again.", comment: "Error message: computer appears offline"), nil)

            case NSURLErrorCannotFindHost:
                return (String(localized: "BrowserErrorHandler.ServerNotFoundTitle", defaultValue: "Server Not Found", comment: "Error title: server not found"), String(localized: "BrowserErrorHandler.CannotFindHostMessage", defaultValue: "iTerm2 can’t find the server. Check that the web address is correct and try again.", comment: "Error message: cannot find host"), nil)

            case NSURLErrorTimedOut:
                return (String(localized: "BrowserErrorHandler.TimedOutTitle", defaultValue: "The Connection Timed Out", comment: "Error title: connection timed out"), String(localized: "BrowserErrorHandler.TimedOutMessage", defaultValue: "The server didn’t respond in time. The site may be temporarily unavailable or overloaded.", comment: "Error message: connection timed out"), nil)

            case NSURLErrorCannotConnectToHost:
                return (String(localized: "BrowserErrorHandler.CannotConnectTitle", defaultValue: "Can’t Connect to Server", comment: "Error title: cannot connect to server"), String(localized: "BrowserErrorHandler.CannotConnectMessage", defaultValue: "iTerm2 can’t establish a secure connection to the server. The server may be down or unreachable.", comment: "Error message: cannot connect to host"), nil)

            case NSURLErrorNetworkConnectionLost:
                return (String(localized: "BrowserErrorHandler.NetworkLostTitle", defaultValue: "Network Connection Lost", comment: "Error title: network connection lost"), String(localized: "BrowserErrorHandler.NetworkLostMessage", defaultValue: "The network connection was lost. Check your internet connection and try again.", comment: "Error message: network connection lost"), nil)

            case NSURLErrorDNSLookupFailed:
                return (String(localized: "BrowserErrorHandler.ServerNotFoundTitle", defaultValue: "Server Not Found", comment: "Error title: server not found"), String(localized: "BrowserErrorHandler.DNSFailedMessage", defaultValue: "The server’s DNS address could not be found. Check that the web address is correct.", comment: "Error message: DNS lookup failed"), nil)

            case NSURLErrorHTTPTooManyRedirects:
                return (String(localized: "BrowserErrorHandler.TooManyRedirectsTitle", defaultValue: "Too Many Redirects", comment: "Error title: too many redirects"), String(localized: "BrowserErrorHandler.TooManyRedirectsMessage", defaultValue: "iTerm2 can’t open the page because the server redirected too many times.", comment: "Error message: too many redirects"), nil)

            case NSURLErrorResourceUnavailable:
                return (String(localized: "BrowserErrorHandler.PageUnavailableTitle", defaultValue: "Page Unavailable", comment: "Error title: page unavailable"), String(localized: "BrowserErrorHandler.PageUnavailableMessage", defaultValue: "The requested page is currently unavailable. Try again later.", comment: "Error message: page unavailable"), nil)

            case NSURLErrorNotConnectedToInternet:
                return (String(localized: "BrowserErrorHandler.NoInternetTitle", defaultValue: "No Internet Connection", comment: "Error title: no internet connection"), String(localized: "BrowserErrorHandler.NoInternetNotConnectedMessage", defaultValue: "Your computer is not connected to the internet. Check your connection and try again.", comment: "Error message: computer not connected to internet"), nil)

            case NSURLErrorServerCertificateUntrusted, NSURLErrorSecureConnectionFailed:
                return (String(localized: "BrowserErrorHandler.SecureConnectionFailedTitle", defaultValue: "Secure Connection Failed", comment: "Error title: secure connection failed"), String(localized: "BrowserErrorHandler.SecureConnectionFailedMessage", defaultValue: "iTerm2 can’t verify the identity of the website. The connection may not be secure.", comment: "Error message: secure connection failed"), sslErrorDetails(from: error))

            case NSURLErrorFileDoesNotExist:
                return (String(localized: "BrowserErrorHandler.FileNotFoundTitle", defaultValue: "File Not Found", comment: "Error title: file not found"), String(localized: "BrowserErrorHandler.FileNotFoundMessage", defaultValue: "The requested file does not exist.", comment: "Error message: file does not exist"), nil)

            default:
                return (String(localized: "BrowserErrorHandler.PageCannotLoadTitle", defaultValue: "Page Can’t Be Loaded", comment: "Error title: page cannot be loaded"), String(localized: "BrowserErrorHandler.PageCannotLoadMessage", defaultValue: "An error occurred while loading this page. \(error.localizedDescription)", comment: "Error message: generic page load failure"), nil)
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
            lines.append(String(localized: "BrowserErrorHandler.CertificateChain", defaultValue: "Certificate chain:", comment: "Label preceding the list of certificates in the chain"))
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
    case errSSLXCertChainInvalid:        return String(localized: "BrowserErrorHandler.SSLChainInvalid", defaultValue: "The presented chain is not valid (e.g., self-signed without trust).", comment: "SSL error detail: certificate chain invalid")
    case errSSLUnknownRootCert:          return String(localized: "BrowserErrorHandler.SSLUnknownRoot", defaultValue: "The root CA is unknown (not in trust store).", comment: "SSL error detail: unknown root CA")
    case errSSLNoRootCert:               return String(localized: "BrowserErrorHandler.SSLNoRoot", defaultValue: "No root certificate found to anchor the chain.", comment: "SSL error detail: no root certificate")
    case errSSLBadCert:                  return String(localized: "BrowserErrorHandler.SSLBadCert", defaultValue: "The certificate is malformed or otherwise bad.", comment: "SSL error detail: malformed certificate")
    case errSSLCertExpired:              return String(localized: "BrowserErrorHandler.SSLCertExpired", defaultValue: "The certificate is expired.", comment: "SSL error detail: expired certificate")
    case errSSLCertNotYetValid:          return String(localized: "BrowserErrorHandler.SSLCertNotYetValid", defaultValue: "The certificate is not yet valid.", comment: "SSL error detail: certificate not yet valid")
    case errSSLHostNameMismatch:         return String(localized: "BrowserErrorHandler.SSLHostnameMismatch", defaultValue: "The hostname does not match the certificate.", comment: "SSL error detail: hostname mismatch")
    default:                             return SecCopyErrorMessageString(OSStatus(status), nil) as? String
    }
}

/// Get human-friendly subject summaries for the chain.
private func certificateSubjects(from trust: SecTrust) -> [String] {
    guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
        return []
    }
    return chain.compactMap { SecCertificateCopySubjectSummary($0) as String? }
}
