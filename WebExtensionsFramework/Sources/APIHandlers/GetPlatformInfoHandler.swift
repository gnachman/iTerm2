import Foundation
import BrowserExtensionShared

class GetPlatformInfoHandler: GetPlatformInfoHandlerProtocol {
    func handle(request: GetPlatformInfoRequest) async throws -> PlatformInfo {
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
