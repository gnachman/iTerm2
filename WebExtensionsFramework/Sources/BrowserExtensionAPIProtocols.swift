// Generated file - do not edit
import Foundation
import BrowserExtensionShared


struct RuntimeGetPlatformInfoRequestImpl: Codable {
    let requestId: String
}
protocol RuntimeGetPlatformInfoRequest {
    var requestId: String { get }
}
extension RuntimeGetPlatformInfoRequestImpl: RuntimeGetPlatformInfoRequest {}
protocol RuntimeGetPlatformInfoHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    @MainActor func handle(request: RuntimeGetPlatformInfoRequest, context: BrowserExtensionContext, namespace: String?) async throws -> PlatformInfo
}
struct RuntimeSendMessageRequestImpl: Codable {
    let requestId: String
    let args: [AnyJSONCodable]
}
protocol RuntimeSendMessageRequest {
    var requestId: String { get }
    var args: [AnyJSONCodable] { get }
}
extension RuntimeSendMessageRequestImpl: RuntimeSendMessageRequest {}
protocol RuntimeSendMessageHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    func handle(request: RuntimeSendMessageRequest, context: BrowserExtensionContext) async throws -> AnyJSONCodable
}




struct StorageLocalGetRequestImpl: Codable {
    let requestId: String
    let keys: Optional<AnyJSONCodable>
}
protocol StorageLocalGetRequest {
    var requestId: String { get }
    var keys: Optional<AnyJSONCodable> { get }
}
extension StorageLocalGetRequestImpl: StorageLocalGetRequest {}
protocol StorageLocalGetHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageLocalGetRequest, context: BrowserExtensionContext, namespace: String?) async throws -> StringToJSONObject
}
struct StorageLocalSetRequestImpl: Codable {
    let requestId: String
    let items: [String: String]
}
protocol StorageLocalSetRequest {
    var requestId: String { get }
    var items: [String: String] { get }
}
extension StorageLocalSetRequestImpl: StorageLocalSetRequest {}
protocol StorageLocalSetHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageLocalSetRequest, context: BrowserExtensionContext, namespace: String?) async throws -> ()
}
struct StorageLocalRemoveRequestImpl: Codable {
    let requestId: String
    let keys: AnyJSONCodable
}
protocol StorageLocalRemoveRequest {
    var requestId: String { get }
    var keys: AnyJSONCodable { get }
}
extension StorageLocalRemoveRequestImpl: StorageLocalRemoveRequest {}
protocol StorageLocalRemoveHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageLocalRemoveRequest, context: BrowserExtensionContext, namespace: String?) async throws -> ()
}
struct StorageLocalClearRequestImpl: Codable {
    let requestId: String
}
protocol StorageLocalClearRequest {
    var requestId: String { get }
}
extension StorageLocalClearRequestImpl: StorageLocalClearRequest {}
protocol StorageLocalClearHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageLocalClearRequest, context: BrowserExtensionContext, namespace: String?) async throws -> ()
}
struct StorageLocalSetAccessLevelRequestImpl: Codable {
    let requestId: String
    let details: Dictionary<String, String>
}
protocol StorageLocalSetAccessLevelRequest {
    var requestId: String { get }
    var details: Dictionary<String, String> { get }
}
extension StorageLocalSetAccessLevelRequestImpl: StorageLocalSetAccessLevelRequest {}
protocol StorageLocalSetAccessLevelHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageLocalSetAccessLevelRequest, context: BrowserExtensionContext, namespace: String?) async throws -> ()
}
struct StorageSyncGetRequestImpl: Codable {
    let requestId: String
    let keys: Optional<AnyJSONCodable>
}
protocol StorageSyncGetRequest {
    var requestId: String { get }
    var keys: Optional<AnyJSONCodable> { get }
}
extension StorageSyncGetRequestImpl: StorageSyncGetRequest {}
protocol StorageSyncGetHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageSyncGetRequest, context: BrowserExtensionContext, namespace: String?) async throws -> StringToJSONObject
}
struct StorageSyncSetRequestImpl: Codable {
    let requestId: String
    let items: [String: String]
}
protocol StorageSyncSetRequest {
    var requestId: String { get }
    var items: [String: String] { get }
}
extension StorageSyncSetRequestImpl: StorageSyncSetRequest {}
protocol StorageSyncSetHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageSyncSetRequest, context: BrowserExtensionContext, namespace: String?) async throws -> ()
}
struct StorageSyncRemoveRequestImpl: Codable {
    let requestId: String
    let keys: AnyJSONCodable
}
protocol StorageSyncRemoveRequest {
    var requestId: String { get }
    var keys: AnyJSONCodable { get }
}
extension StorageSyncRemoveRequestImpl: StorageSyncRemoveRequest {}
protocol StorageSyncRemoveHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageSyncRemoveRequest, context: BrowserExtensionContext, namespace: String?) async throws -> ()
}
struct StorageSyncClearRequestImpl: Codable {
    let requestId: String
}
protocol StorageSyncClearRequest {
    var requestId: String { get }
}
extension StorageSyncClearRequestImpl: StorageSyncClearRequest {}
protocol StorageSyncClearHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageSyncClearRequest, context: BrowserExtensionContext, namespace: String?) async throws -> ()
}
struct StorageSyncSetAccessLevelRequestImpl: Codable {
    let requestId: String
    let details: Dictionary<String, String>
}
protocol StorageSyncSetAccessLevelRequest {
    var requestId: String { get }
    var details: Dictionary<String, String> { get }
}
extension StorageSyncSetAccessLevelRequestImpl: StorageSyncSetAccessLevelRequest {}
protocol StorageSyncSetAccessLevelHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageSyncSetAccessLevelRequest, context: BrowserExtensionContext, namespace: String?) async throws -> ()
}
struct StorageSessionGetRequestImpl: Codable {
    let requestId: String
    let keys: Optional<AnyJSONCodable>
}
protocol StorageSessionGetRequest {
    var requestId: String { get }
    var keys: Optional<AnyJSONCodable> { get }
}
extension StorageSessionGetRequestImpl: StorageSessionGetRequest {}
protocol StorageSessionGetHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageSessionGetRequest, context: BrowserExtensionContext, namespace: String?) async throws -> StringToJSONObject
}
struct StorageSessionSetRequestImpl: Codable {
    let requestId: String
    let items: [String: String]
}
protocol StorageSessionSetRequest {
    var requestId: String { get }
    var items: [String: String] { get }
}
extension StorageSessionSetRequestImpl: StorageSessionSetRequest {}
protocol StorageSessionSetHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageSessionSetRequest, context: BrowserExtensionContext, namespace: String?) async throws -> ()
}
struct StorageSessionRemoveRequestImpl: Codable {
    let requestId: String
    let keys: AnyJSONCodable
}
protocol StorageSessionRemoveRequest {
    var requestId: String { get }
    var keys: AnyJSONCodable { get }
}
extension StorageSessionRemoveRequestImpl: StorageSessionRemoveRequest {}
protocol StorageSessionRemoveHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageSessionRemoveRequest, context: BrowserExtensionContext, namespace: String?) async throws -> ()
}
struct StorageSessionClearRequestImpl: Codable {
    let requestId: String
}
protocol StorageSessionClearRequest {
    var requestId: String { get }
}
extension StorageSessionClearRequestImpl: StorageSessionClearRequest {}
protocol StorageSessionClearHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageSessionClearRequest, context: BrowserExtensionContext, namespace: String?) async throws -> ()
}
struct StorageSessionSetAccessLevelRequestImpl: Codable {
    let requestId: String
    let details: Dictionary<String, String>
}
protocol StorageSessionSetAccessLevelRequest {
    var requestId: String { get }
    var details: Dictionary<String, String> { get }
}
extension StorageSessionSetAccessLevelRequestImpl: StorageSessionSetAccessLevelRequest {}
protocol StorageSessionSetAccessLevelHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageSessionSetAccessLevelRequest, context: BrowserExtensionContext, namespace: String?) async throws -> ()
}
struct StorageManagedGetRequestImpl: Codable {
    let requestId: String
    let keys: Optional<AnyJSONCodable>
}
protocol StorageManagedGetRequest {
    var requestId: String { get }
    var keys: Optional<AnyJSONCodable> { get }
}
extension StorageManagedGetRequestImpl: StorageManagedGetRequest {}
protocol StorageManagedGetHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageManagedGetRequest, context: BrowserExtensionContext, namespace: String?) async throws -> StringToJSONObject
}
struct StorageManagedSetRequestImpl: Codable {
    let requestId: String
    let items: [String: String]
}
protocol StorageManagedSetRequest {
    var requestId: String { get }
    var items: [String: String] { get }
}
extension StorageManagedSetRequestImpl: StorageManagedSetRequest {}
protocol StorageManagedSetHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageManagedSetRequest, context: BrowserExtensionContext, namespace: String?) async throws -> ()
}
struct StorageManagedRemoveRequestImpl: Codable {
    let requestId: String
    let keys: AnyJSONCodable
}
protocol StorageManagedRemoveRequest {
    var requestId: String { get }
    var keys: AnyJSONCodable { get }
}
extension StorageManagedRemoveRequestImpl: StorageManagedRemoveRequest {}
protocol StorageManagedRemoveHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageManagedRemoveRequest, context: BrowserExtensionContext, namespace: String?) async throws -> ()
}
struct StorageManagedClearRequestImpl: Codable {
    let requestId: String
}
protocol StorageManagedClearRequest {
    var requestId: String { get }
}
extension StorageManagedClearRequestImpl: StorageManagedClearRequest {}
protocol StorageManagedClearHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { get }
    init(storageManager: BrowserExtensionStorageManager?)
    @MainActor func handle(request: StorageManagedClearRequest, context: BrowserExtensionContext, namespace: String?) async throws -> ()
}



