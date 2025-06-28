import Foundation

@MainActor
class iTermBrowserAdblockRustManager {
    static let shared = iTermBrowserAdblockRustManager()
    
    private var engine: iTermBrowserAdblockRustWrapper?
    private var filterListURL: URL? {
        guard let urlString = iTermAdvancedSettingsModel.rustAdblockListURL(),
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return nil
        }
        return url
    }
    
    private init() {
        Task {
            if iTermAdvancedSettingsModel.adblockEnabled() {
                await loadFilterLists()
            }
        }
    }
    
    private func loadFilterLists() async {
        guard let url = filterListURL else {
            DLog("No valid Rust adblock filter list URL configured")
            engine = nil
            return
        }
        
        DLog("Downloading Rust adblock filter list from: \(url)")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let rulesString = String(data: data, encoding: .utf8) else {
                DLog("Failed to decode filter list")
                engine = nil
                return
            }
            
            DLog("Filter list size: \(data.count) bytes, \(rulesString.count) characters")
            DLog("First 200 chars of rules: \(String(rulesString.prefix(200)))")
            
            engine = iTermBrowserAdblockRustWrapper(rules: rulesString)
            if engine == nil {
                DLog("Failed to create Rust adblock engine")
            } else {
                DLog("Successfully loaded filter list into Rust adblock engine")
            }
        } catch {
            DLog("Failed to download filter list: \(error)")
            engine = nil
        }
    }
    
    func shouldBlockRequest(url: URL, tabHost: String? = nil) async -> Bool {
        guard iTermAdvancedSettingsModel.adblockEnabled(),
              let engine = engine,
              let host = url.host else {
            return false
        }
        
        let urlString = url.absoluteString
        let effectiveTabHost = tabHost ?? host
        
        return await engine.shouldBlockRequest(url: urlString, host: host, tabHost: effectiveTabHost)
    }
    
    func getCosmeticResources(for url: URL) async -> (hideSelectors: [String], injectedScript: String?) {
        guard iTermAdvancedSettingsModel.adblockEnabled(),
              let engine = engine else {
            return ([], nil)
        }
        
        return await engine.getCosmeticResources(for: url.absoluteString)
    }
    
    func reload() async {
        await loadFilterLists()
    }
}
