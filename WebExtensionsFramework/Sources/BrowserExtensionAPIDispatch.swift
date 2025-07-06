// Generated file - do not edit
import Foundation
import BrowserExtensionShared

func dispatch(api: String, requestId: String, body: [String: Any]) async throws -> [String: Any] {
    let jsonData = try JSONSerialization.data(withJSONObject: body)
    switch api {

    case "getPlatformInfo":
        let decoder = JSONDecoder()
        let request = try decoder.decode(GetPlatformInfoRequestImpl.self, from: jsonData)
        let handler = GetPlatformInfoHandler()
        let response = try await handler.handle(request: request)
        let encodedResponse = try JSONEncoder().encode(response)
        return try JSONSerialization.jsonObject(with: encodedResponse) as! [String: Any]
    case "sendMessage":
        let decoder = JSONDecoder()
        let request = try decoder.decode(SendMessageRequestImpl.self, from: jsonData)
        let handler = SendMessageHandler()
        let response = try await handler.handle(request: request)
        let encodedResponse = try JSONEncoder().encode(response)
        return try JSONSerialization.jsonObject(with: encodedResponse) as! [String: Any]

    default:
        throw NSError(domain: "BrowserExtension", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown API: \(api)"])
    }
}