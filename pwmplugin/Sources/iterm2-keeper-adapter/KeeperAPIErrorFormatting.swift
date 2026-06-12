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
