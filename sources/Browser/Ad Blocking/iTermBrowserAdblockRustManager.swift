import Foundation
import iTermSwiftPackages

extension Notification.Name {
    static let rustAdblockStatsChanged = Notification.Name("rustAdblockStatsChanged")
}

class iTermBrowserAdblockRustManager {
    static let shared = iTermBrowserAdblockRustManager()
    private(set) var engine: iTermBrowserAdblockRustWrapper?
    private(set) var ruleCount: Int = 0
    private(set) var isDownloading: Bool = false

    struct Configuration {
        var url: String?
        var enabled: Bool

        init() {
            dispatchPrecondition(condition: .onQueue(.main))
            url = iTermAdvancedSettingsModel.rustAdblockListURL()
            enabled = iTermAdvancedSettingsModel.adblockEnabled()
        }
    }
    private var configuration: MutableAtomicObject<Configuration>
    private let userDefaultsObserver: iTermUserDefaultsObserver

    private var filterListURLs: [URL] {
        guard let urlString = configuration.value.url,
              !urlString.isEmpty else {
            return []
        }
        
        return urlString.components(separatedBy: " ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { URL(string: $0) }
    }

    private init() {
        configuration = .init(Configuration())

        userDefaultsObserver = iTermUserDefaultsObserver()
        userDefaultsObserver.observeKey("rustAdblockListURL") { [weak self] in
            self?.updateConfiguration()
        }
        userDefaultsObserver.observeKey("adblockEnabled") { [weak self] in
            self?.updateConfiguration()
        }
        if configuration.value.enabled {
            Task {
                await loadFilterLists()
            }
        }
    }

    private func updateConfiguration() {
        configuration.mutate { _ in
            return Configuration()
        }
    }

    private func loadFilterLists() async {
        let urls = filterListURLs
        guard !urls.isEmpty else {
            DLog("No valid Rust adblock filter list URLs configured")
            engine = nil
            ruleCount = 0
            isDownloading = false
            notifyStatsChanged()
            return
        }

        isDownloading = true
        notifyStatsChanged()
        
        DLog("Downloading Rust adblock filter lists from \(urls.count) URLs")
        var allRules = ""
        
        for (index, url) in urls.enumerated() {
            DLog("Downloading filter list \(index + 1)/\(urls.count) from: \(url)")
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let rulesString = String(data: data, encoding: .utf8) else {
                    DLog("Failed to decode filter list from \(url)")
                    continue
                }

                DLog("Filter list \(index + 1) size: \(data.count) bytes, \(rulesString.count) characters")
                if index == 0 {
                    DLog("First 200 chars of rules: \(String(rulesString.prefix(200)))")
                }
                
                allRules += rulesString
                if index < urls.count - 1 {
                    allRules += "\n"
                }
            } catch {
                DLog("Failed to download filter list from \(url): \(error)")
                continue
            }
        }
        
        guard !allRules.isEmpty else {
            DLog("No filter lists could be downloaded")
            engine = nil
            ruleCount = 0
            isDownloading = false
            notifyStatsChanged()
            return
        }

        // Count the number of rules (non-empty, non-comment lines)
        let lines = allRules.components(separatedBy: .newlines)
        ruleCount = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("!") && !trimmed.hasPrefix("[")
        }.count

        DLog("Combined filter lists: \(allRules.count) characters total, \(ruleCount) rules")
        engine = iTermBrowserAdblockRustWrapper(rules: allRules)
        isDownloading = false
        
        if engine == nil {
            DLog("Failed to create Rust adblock engine")
            ruleCount = 0
        } else {
            DLog("Successfully loaded \(urls.count) filter lists with \(ruleCount) rules into Rust adblock engine")
        }
        
        notifyStatsChanged()
    }
    
    private func notifyStatsChanged() {
        NotificationCenter.default.post(name: .rustAdblockStatsChanged, object: nil)
    }

    func shouldBlockRequest(url: URL, tabHost: String? = nil) -> Bool {
        guard configuration.value.enabled,
              let engine = engine,
              let host = url.host else {
            return false
        }

        let urlString = url.absoluteString
        let effectiveTabHost = tabHost ?? host

        return engine.shouldBlockRequest(url: urlString, host: host, tabHost: effectiveTabHost)
    }

    func getCosmeticResources(for url: URL) async -> (hideSelectors: [String], injectedScript: String?) {
        guard configuration.value.enabled,
              let engine = engine else {
            return ([], nil)
        }

        return engine.getCosmeticResources(for: url.absoluteString)
    }

    func reload() async {
        await loadFilterLists()
    }

    func updateInternalProxyInstalled(desired: Bool) {
        let server = iTermSwiftPackages.Server.instance
        if desired {
            if server.portIfRunning != nil && server.monitor == nil {
                server.monitor = self
            }
        } else {
            server.monitor = nil
        }
    }
}

extension iTermBrowserAdblockRustManager: ConnectionMonitor {
    func connectionMonitorShouldConnect(method: String, host: String, port: Int, headers: [String : String]) -> Bool {
        let hostHeaderKey = headers.keys.first(where: { $0.lowercased() == "host"})
        let hostHeaderValue = hostHeaderKey.compactMap { headers[$0] }
        let host = hostHeaderValue ?? host
        let scheme = switch method {
        case "CONNECT":
            "https"
        default:
            "http"
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        guard let url = components.url else {
            return false
        }
        return !shouldBlockRequest(url: url)
    }
}
