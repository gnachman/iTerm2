// HTTP/API error strings for Commander responses (shared by KeeperCommanderClient).

import Foundation

func keeperHumanReadableError(fromResponseData data: Data?) -> String? {
    guard let data = data,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    if let error = json["error"] as? String, !error.isEmpty { return error }
    if let message = json["message"] as? String, !message.isEmpty { return message }
    return nil
}

func keeperUserFacingPasswordUpdateError(apiDetail: String) -> String {
    let lower = apiDetail.lowercased()
    if lower.contains("base64") || lower.contains("pwd") || (lower.contains("password") && (lower.contains("failed") || lower.contains("invalid") || lower.contains("required") || lower.contains("empty"))) {
        return "Password field is required."
    }
    return apiDetail
}

private let keeperUpdateCredentialsAdvice =
    "Update your Service URL and API key in Password Manager settings, and confirm your Keeper Commander server is running."

private func keeperResponseBodyLooksLikeHTML(_ data: Data) -> Bool {
    guard let head = String(data: data.prefix(2048), encoding: .utf8)?.lowercased() else { return false }
    return head.contains("<!doctype html") || head.contains("<html") || head.contains("<body")
}

func keeperConnectivityErrorMessage(statusCode: Int?, data: Data?) -> String {
    if let detail = keeperHumanReadableError(fromResponseData: data) {
        return detail
    }
    if let body = data, !body.isEmpty, keeperResponseBodyLooksLikeHTML(body) {
        return "The Service URL returned an HTML error page (the server may be offline, the URL may be wrong, or a proxy/tunnel may be misconfigured). \(keeperUpdateCredentialsAdvice)"
    }
    if let code = statusCode {
        if code == 401 || code == 403 {
            return "API key rejected (HTTP \(code)). \(keeperUpdateCredentialsAdvice)"
        }
        if code >= 500 {
            return "Keeper Commander returned an error (HTTP \(code)). \(keeperUpdateCredentialsAdvice)"
        }
        return "Unexpected response from Keeper Commander (HTTP \(code)). \(keeperUpdateCredentialsAdvice)"
    }
    return "Could not reach Keeper Commander. \(keeperUpdateCredentialsAdvice)"
}

func keeperConnectivityErrorMessage(urlError: Error?) -> String? {
    guard let urlError = urlError as? URLError else { return nil }
    switch urlError.code {
    case .timedOut:
        return "Could not reach the Keeper Commander server (request timed out). \(keeperUpdateCredentialsAdvice)"
    case .cannotFindHost, .dnsLookupFailed:
        return "The Service URL host could not be resolved. \(keeperUpdateCredentialsAdvice)"
    case .cannotConnectToHost:
        return "The Service URL is unreachable (connection refused). \(keeperUpdateCredentialsAdvice)"
    case .notConnectedToInternet:
        return "No internet connection. \(keeperUpdateCredentialsAdvice)"
    case .networkConnectionLost, .resourceUnavailable:
        return "The connection to Keeper Commander was lost. \(keeperUpdateCredentialsAdvice)"
    case .secureConnectionFailed, .serverCertificateUntrusted,
         .serverCertificateHasBadDate, .serverCertificateNotYetValid,
         .serverCertificateHasUnknownRoot, .clientCertificateRejected,
         .clientCertificateRequired:
        return "TLS handshake with the Service URL failed. \(keeperUpdateCredentialsAdvice)"
    case .badURL, .unsupportedURL:
        return "The Service URL is malformed. \(keeperUpdateCredentialsAdvice)"
    default:
        return "Could not reach Keeper Commander (\(urlError.localizedDescription)). \(keeperUpdateCredentialsAdvice)"
    }
}
