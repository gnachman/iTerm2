// Generated file - do not edit
import Foundation
import BrowserExtensionShared

@MainActor
class BrowserExtensionDispatcher {
    func dispatch(api: String, requestId: String, body: [String: Any], context: BrowserExtensionContext) async throws -> [String: Any] {
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        switch api {

        case "getPlatformInfo":
            let decoder = JSONDecoder()
            let request = try decoder.decode(GetPlatformInfoRequestImpl.self, from: jsonData)
            let handler = GetPlatformInfoHandler()
            let response = try await handler.handle(request: request, context: context)
            context.logger.debug("Dispatcher got response: \(response) type: \(type(of: response))")
            let encodedValue = response.browserExtensionEncodedValue
            context.logger.debug("Dispatcher encoded value: \(encodedValue)")
            let encoder = JSONEncoder()
            let data = try encoder.encode(encodedValue)
            let jsonObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            context.logger.debug("Dispatcher returning: \(jsonObject)")
            return jsonObject
        case "sendMessage":
            let decoder = JSONDecoder()
            let request = try decoder.decode(SendMessageRequestImpl.self, from: jsonData)
            let handler = SendMessageHandler()
            let response = try await handler.handle(request: request, context: context)
            context.logger.debug("Dispatcher got response: \(response) type: \(type(of: response))")
            let encodedValue = response.browserExtensionEncodedValue
            context.logger.debug("Dispatcher encoded value: \(encodedValue)")
            let encoder = JSONEncoder()
            let data = try encoder.encode(encodedValue)
            let jsonObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            context.logger.debug("Dispatcher returning: \(jsonObject)")
            return jsonObject

        default:
            throw NSError(domain: "BrowserExtension", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown API: \(api)"])
        }
    }
}