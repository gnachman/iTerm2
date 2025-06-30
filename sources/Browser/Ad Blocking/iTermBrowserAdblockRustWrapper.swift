import Foundation

class iTermBrowserAdblockRustWrapper {
    private var engine: OpaquePointer?
    private let mutex = Mutex()

    init?(rules: String) {
        engine = rules.withCString { cString in
            engine_create(cString)
        }
        
        guard engine != nil else {
            return nil
        }
    }
    
    deinit {
        if let engine = engine {
            engine_destroy(engine)
        }
    }
    
    func shouldBlockRequest(url: String, host: String, tabHost: String) -> Bool {
        return mutex.sync {
            guard let engine = engine else { return false }

            return url.withCString { urlCString in
                host.withCString { hostCString in
                    tabHost.withCString { tabHostCString in
                        engine_match(engine, urlCString, hostCString, tabHostCString)
                    }
                }
            }
        }
    }
    
    func getCosmeticResources(for url: String) -> (hideSelectors: [String], injectedScript: String?) {
        return mutex.sync {
            guard let engine = engine else { return ([], nil) }

            let resources = url.withCString { urlCString in
                engine_url_cosmetic_resources(engine, urlCString)
            }

            guard let resources = resources else { return ([], nil) }

            var hideSelectors: [String] = []
            var injectedScript: String?

            if let selectorsPtr = resources.pointee.hide_selectors {
                let selectorsString = String(cString: selectorsPtr)
                hideSelectors = selectorsString.split(separator: ",").map { String($0) }
            }

            if let scriptPtr = resources.pointee.injected_script {
                injectedScript = String(cString: scriptPtr)
            }

            url_specific_resources_destroy(resources)

            return (hideSelectors, injectedScript)
        }
    }
}
