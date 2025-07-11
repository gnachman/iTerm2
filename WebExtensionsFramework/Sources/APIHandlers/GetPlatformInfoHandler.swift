import Foundation
import BrowserExtensionShared

class RuntimeGetPlatformInfoHandler: RuntimeGetPlatformInfoHandlerProtocol {
    
    /// getPlatformInfo requires no permissions
    var requiredPermissions: [BrowserExtensionAPIPermission] { [] }
    
    @MainActor
    func handle(request: RuntimeGetPlatformInfoRequest,
                context: BrowserExtensionContext,
                namespace: String?) async throws -> PlatformInfo {
        let arch: String
        #if arch(x86_64)
        arch = "x86-64"
        #elseif arch(arm64)
        arch = "arm64"
        #else
        #error("Unknown architecture")
        #endif
        return .init(os: "mac", arch: arch, nacl_arch: arch)
    }
}
