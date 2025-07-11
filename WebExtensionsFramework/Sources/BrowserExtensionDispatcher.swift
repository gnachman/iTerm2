// Generated file - do not edit
import Foundation
import BrowserExtensionShared

@MainActor
class BrowserExtensionDispatcher {
    weak var storageManager: BrowserExtensionStorageManager?
    
    func dispatch(api: String, requestId: String, body: [String: Any], context: BrowserExtensionContext) async throws -> [String: Any] {
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        switch api {

        case "runtime.getPlatformInfo":
            let handler = RuntimeGetPlatformInfoHandler()
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(RuntimeGetPlatformInfoRequestImpl.self, from: jsonData)
            let response = try await handler.handle(request: request, context: context, namespace: "runtime")
            context.logger.debug("Dispatcher got response: \(response) type: \(type(of: response))")
            let encodedValue = response.browserExtensionEncodedValue
            context.logger.debug("Dispatcher encoded value: \(encodedValue)")
            let encoder = JSONEncoder()
            let data = try encoder.encode(encodedValue)
            let jsonObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            context.logger.debug("Dispatcher returning: \(jsonObject)")
            return jsonObject
        case "runtime.sendMessage":
            let handler = RuntimeSendMessageHandler()
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(RuntimeSendMessageRequestImpl.self, from: jsonData)
            let response = try await handler.handle(request: request, context: context)
            context.logger.debug("Dispatcher got response: \(response) type: \(type(of: response))")
            let encodedValue = response.browserExtensionEncodedValue
            context.logger.debug("Dispatcher encoded value: \(encodedValue)")
            let encoder = JSONEncoder()
            let data = try encoder.encode(encodedValue)
            let jsonObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            context.logger.debug("Dispatcher returning: \(jsonObject)")
            return jsonObject

        case "storage.local.get":
            let handler = StorageLocalGetHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageLocalGetRequestImpl.self, from: jsonData)
            let response = try await handler.handle(request: request, context: context, namespace: "storage.local")
            context.logger.debug("Dispatcher got response: \(response) type: \(type(of: response))")
            let encodedValue = response.browserExtensionEncodedValue
            context.logger.debug("Dispatcher encoded value: \(encodedValue)")
            let encoder = JSONEncoder()
            let data = try encoder.encode(encodedValue)
            let jsonObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            context.logger.debug("Dispatcher returning: \(jsonObject)")
            return jsonObject
        case "storage.local.set":
            let handler = StorageLocalSetHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageLocalSetRequestImpl.self, from: jsonData)
            try await handler.handle(request: request, context: context, namespace: "storage.local")
            return ["": NoObjectPlaceholder.instance];
        case "storage.local.remove":
            let handler = StorageLocalRemoveHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageLocalRemoveRequestImpl.self, from: jsonData)
            try await handler.handle(request: request, context: context, namespace: "storage.local")
            return ["": NoObjectPlaceholder.instance];
        case "storage.local.clear":
            let handler = StorageLocalClearHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageLocalClearRequestImpl.self, from: jsonData)
            try await handler.handle(request: request, context: context, namespace: "storage.local")
            return ["": NoObjectPlaceholder.instance];
        case "storage.local.setAccessLevel":
            let handler = StorageLocalSetAccessLevelHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageLocalSetAccessLevelRequestImpl.self, from: jsonData)
            try await handler.handle(request: request, context: context, namespace: "storage.local")
            return ["": NoObjectPlaceholder.instance];
        case "storage.sync.get":
            let handler = StorageSyncGetHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageSyncGetRequestImpl.self, from: jsonData)
            let response = try await handler.handle(request: request, context: context, namespace: "storage.sync")
            context.logger.debug("Dispatcher got response: \(response) type: \(type(of: response))")
            let encodedValue = response.browserExtensionEncodedValue
            context.logger.debug("Dispatcher encoded value: \(encodedValue)")
            let encoder = JSONEncoder()
            let data = try encoder.encode(encodedValue)
            let jsonObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            context.logger.debug("Dispatcher returning: \(jsonObject)")
            return jsonObject
        case "storage.sync.set":
            let handler = StorageSyncSetHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageSyncSetRequestImpl.self, from: jsonData)
            try await handler.handle(request: request, context: context, namespace: "storage.sync")
            return ["": NoObjectPlaceholder.instance];
        case "storage.sync.remove":
            let handler = StorageSyncRemoveHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageSyncRemoveRequestImpl.self, from: jsonData)
            try await handler.handle(request: request, context: context, namespace: "storage.sync")
            return ["": NoObjectPlaceholder.instance];
        case "storage.sync.clear":
            let handler = StorageSyncClearHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageSyncClearRequestImpl.self, from: jsonData)
            try await handler.handle(request: request, context: context, namespace: "storage.sync")
            return ["": NoObjectPlaceholder.instance];
        case "storage.sync.setAccessLevel":
            let handler = StorageSyncSetAccessLevelHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageSyncSetAccessLevelRequestImpl.self, from: jsonData)
            try await handler.handle(request: request, context: context, namespace: "storage.sync")
            return ["": NoObjectPlaceholder.instance];
        case "storage.session.get":
            let handler = StorageSessionGetHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageSessionGetRequestImpl.self, from: jsonData)
            let response = try await handler.handle(request: request, context: context, namespace: "storage.session")
            context.logger.debug("Dispatcher got response: \(response) type: \(type(of: response))")
            let encodedValue = response.browserExtensionEncodedValue
            context.logger.debug("Dispatcher encoded value: \(encodedValue)")
            let encoder = JSONEncoder()
            let data = try encoder.encode(encodedValue)
            let jsonObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            context.logger.debug("Dispatcher returning: \(jsonObject)")
            return jsonObject
        case "storage.session.set":
            let handler = StorageSessionSetHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageSessionSetRequestImpl.self, from: jsonData)
            try await handler.handle(request: request, context: context, namespace: "storage.session")
            return ["": NoObjectPlaceholder.instance];
        case "storage.session.remove":
            let handler = StorageSessionRemoveHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageSessionRemoveRequestImpl.self, from: jsonData)
            try await handler.handle(request: request, context: context, namespace: "storage.session")
            return ["": NoObjectPlaceholder.instance];
        case "storage.session.clear":
            let handler = StorageSessionClearHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageSessionClearRequestImpl.self, from: jsonData)
            try await handler.handle(request: request, context: context, namespace: "storage.session")
            return ["": NoObjectPlaceholder.instance];
        case "storage.session.setAccessLevel":
            let handler = StorageSessionSetAccessLevelHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageSessionSetAccessLevelRequestImpl.self, from: jsonData)
            try await handler.handle(request: request, context: context, namespace: "storage.session")
            return ["": NoObjectPlaceholder.instance];
        case "storage.managed.get":
            let handler = StorageManagedGetHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageManagedGetRequestImpl.self, from: jsonData)
            let response = try await handler.handle(request: request, context: context, namespace: "storage.managed")
            context.logger.debug("Dispatcher got response: \(response) type: \(type(of: response))")
            let encodedValue = response.browserExtensionEncodedValue
            context.logger.debug("Dispatcher encoded value: \(encodedValue)")
            let encoder = JSONEncoder()
            let data = try encoder.encode(encodedValue)
            let jsonObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            context.logger.debug("Dispatcher returning: \(jsonObject)")
            return jsonObject
        case "storage.managed.set":
            let handler = StorageManagedSetHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageManagedSetRequestImpl.self, from: jsonData)
            try await handler.handle(request: request, context: context, namespace: "storage.managed")
            return ["": NoObjectPlaceholder.instance];
        case "storage.managed.remove":
            let handler = StorageManagedRemoveHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageManagedRemoveRequestImpl.self, from: jsonData)
            try await handler.handle(request: request, context: context, namespace: "storage.managed")
            return ["": NoObjectPlaceholder.instance];
        case "storage.managed.clear":
            let handler = StorageManagedClearHandler(storageManager: storageManager)
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(StorageManagedClearRequestImpl.self, from: jsonData)
            try await handler.handle(request: request, context: context, namespace: "storage.managed")
            return ["": NoObjectPlaceholder.instance];

        default:
            throw BrowserExtensionError.unknownAPI(api)
        }
    }
}