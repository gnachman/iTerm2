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
    func handle(request: GetPlatformInfoRequest) async throws -> PlatformInfo
}
struct SendMessageRequestImpl: Codable {
    let requestId: String
    let arg1: AnyJSONCodable
    let arg2: AnyJSONCodable
    let arg3: AnyJSONCodable
}
protocol SendMessageRequest {
    var requestId: String { get }
    var arg1: AnyJSONCodable { get }
    var arg2: AnyJSONCodable { get }
    var arg3: AnyJSONCodable { get }
}
extension SendMessageRequestImpl: SendMessageRequest {}
protocol SendMessageHandlerProtocol {
    func handle(request: SendMessageRequest) async throws -> AnyJSONCodable
}