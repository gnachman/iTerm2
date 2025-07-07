// Generated file - do not edit
import Foundation
import BrowserExtensionShared


struct GetPlatformInfoRequestImpl: Codable {
    let requestId: String
}
protocol GetPlatformInfoRequest {
    var requestId: String { get }
}
extension GetPlatformInfoRequestImpl: GetPlatformInfoRequest {}
protocol GetPlatformInfoHandlerProtocol {
    func handle(request: GetPlatformInfoRequest, context: BrowserExtensionContext) async throws -> PlatformInfo
}
struct SendMessageRequestImpl: Codable {
    let requestId: String
    let args: [AnyJSONCodable]
}
protocol SendMessageRequest {
    var requestId: String { get }
    var args: [AnyJSONCodable] { get }
}
extension SendMessageRequestImpl: SendMessageRequest {}
protocol SendMessageHandlerProtocol {
    func handle(request: SendMessageRequest, context: BrowserExtensionContext) async throws -> AnyJSONCodable
}



