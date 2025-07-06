import Foundation
import BrowserExtensionShared

class SendMessageHandler: SendMessageHandlerProtocol {
    func handle(request: SendMessageRequest) async throws -> AnyJSONCodable {
        throw NSError(domain: "BrowserExtension", code: 1, userInfo: [NSLocalizedDescriptionKey: "SendMessageHandler not implemented"])
    }
}